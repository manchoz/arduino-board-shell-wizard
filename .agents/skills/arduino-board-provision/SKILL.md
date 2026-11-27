---
name: arduino-board-provision
description: Provision or update Arduino Uno Q and Ventuno Q boards over USB/ADB with the Arduino Q Board Shell Wizard. Use for board setup, hostname or keyboard changes, Wi-Fi connection, and optional SSH access through the existing unattended request interface.
license: MPL-2.0
---

# Arduino Q board provisioning

Use the installed host launcher and its literal request interface. This workflow invokes setup only; provisioning does not authorize reset, flashing, deletion of saved Wi-Fi profiles, or implicit SSH key generation.

## Locate the tool and its guides

When installed as a plugin, locate its bundled tool by walking upward from the host-supplied absolute path of this `SKILL.md` until a complete tool root is found. In Claude plugin skills, `${CLAUDE_PLUGIN_ROOT}` also identifies that root. Use the bundled installation unless the user explicitly requests another installation. Do not assume the application's working directory is the plugin root.

For a copied standalone skill, use the user's supplied `Arduino Shell Wizard tool root` or a complete installation in the current workspace. Identify a complete root by `board-host.sh`, `board-host.ps1`, all four `board/` scripts, both `host/` helpers, `AGENTS.md`, and the `docs/` guides. If no installation is available, ask for its location or direct the user to https://github.com/manchoz/arduino-board-shell-wizard/releases. A copied skill without surrounding tools must use this fallback; do not search unrelated user directories.

Resolve all following paths from that **tool root**, not this skill's folder. The skill may have been copied into another agent or installed globally.

Read the tool's `AGENTS.md` and `docs/unattended.md` before provisioning. They own the board precautions, request fields, validation rules, and failure semantics. Read `docs/adb.md` for host prerequisites and `docs/usage.md` for setup choices and verification. Read `docs/technical.md` only for implementation or troubleshooting details. Keep `board/` and `host/` beside the launchers.

The agent needs local command execution and USB/ADB access on the computer connected to the board. A skill alone does not grant execution permissions or provide a remote USB connection.

## Inspect before choosing inputs

For a preview, documentation task, or hardware-free check, use only disposable fixtures and mocks. Do not contact a board.

For requested provisioning, use the authorization already given for that operation. Ask only for missing choices, credential sources, or ambiguous device selection; do not request the same authorization again.

Locate ADB on PATH or in the existing App Lab/Arduino IDE installation described in `docs/adb.md`. List devices with `adb devices -l`. Read the device-tree identity of plausible devices using `adb -s SERIAL`; identify the intended supported board before writing. If several boards remain plausible, ask which one. Record and explicitly pass the selected serial even when only one board is connected.

Capture the initial state required by `AGENTS.md`, including password-aging state, Network Mode, hostname, keyboard, setup markers, services, saved connection UUIDs/types, image/CLI versions, and host/board clocks. Read-only inspection comes before configuration. Do not retrieve saved Wi-Fi passwords with `nmcli --show-secrets`. An old board clock can affect password-aging dates.

## Resolve the requested choices

Preserve unspecified settings on an already provisioned board. Translate choices into the exact fields in `docs/unattended.md`:

| User intent or initial state | Choice |
| --- | --- |
| Set a board name or keyboard layout | Use the supplied value; otherwise leave hostname/keyboard empty to preserve them. |
| Connect to the named Wi-Fi network | Choose `wifi=connect` with the SSID and its credential source. An empty password is valid only when the user identifies an open network. |
| Wi-Fi was not requested | Choose `wifi=keep`. |
| Keep an existing Linux password | Choose `linux_password=keep`. |
| First-use password state, or a requested password change | Resolve a new Linux-password source and choose `linux_password=set`. Setting it also requires explicit Network Mode approval and `network_mode=enable`. |
| Network Mode was not requested on a provisioned board | Choose `network_mode=keep`. |
| Enable disabled Network Mode while keeping the Linux password | Choose `network_mode=enable` and resolve the current Linux-password source for sudo authentication. |

Linux and Wi-Fi passwords are separate. Apply the Linux-password restrictions from the request contract only to Linux passwords. Never generate a Linux password unless the user chooses that approach.

For optional SSH integration, use only an existing public key explicitly selected by the user. Resolve Network Mode approval as needed and read the host SSH-directory/config permission effects in `docs/technical.md`. Add `--ssh-key` or `-SshKey`, and an address override only when requested. ADB key installation does not establish external network reachability.

Resolve missing first-use choices before launching. Do not run setup merely to discover whether a password is needed: setup can rewrite markers even when preserving settings.

## Keep credentials out of the conversation

Accept a protected request file, a named entry in an available local secret manager, or another protected local credential source. If none is available, ask the user to prepare the request through a private editor or their secret manager using `docs/unattended.md`; do not ask them to paste passwords into chat.

Restrict the request directory **before** writing secrets, outside the repository. Use owner-only directory/file permissions on Linux/macOS and a protected Windows ACL as documented. A local serializer may read a protected credential source and write the request directly without printing its contents. Never embed secret values in tool-call text, command arguments, environment variables, captured output, or reports.

When an existing private request is supplied, check its permissions and validate its requested choices locally without exposing its contents. Resolve any conflict with the user's requested nonsecret settings before invoking the launcher.

When the user supplies a request-file path alongside the skill invocation, use that local file as the request source. The file-format, private-storage, and direct-launcher walkthrough is under 'Prepare and use a private request file' in the installed tool's docs/unattended.md. Do not ask for the file contents in chat.

Follow the BOM-free UTF-8, 64 KiB, unique-key, and literal-value rules in `docs/unattended.md`; do not evaluate or shell-expand request values. Treat missing Wi-Fi credentials as missing information, not an open-network choice. Retain generated credentials and failed-operation requests in their protected location; report their nonsecret storage label so the user can retrieve them.

## Invoke the launcher once

Assign the tool root, selected serial, and protected request-file path from the resolved inputs. Run the matching host example from the tool root. No secret values appear in these command arguments.

Windows PowerShell, using `$toolRoot`, `$boardSerial`, and `$requestFile`:

```powershell
Set-Location -LiteralPath $toolRoot
.\board-host.ps1 -Operation setup -Serial $boardSerial -RequestFile $requestFile
```

Linux/macOS Bash, using `$tool_root`, `$board_serial`, and `$request_file`:

```sh
cd "$tool_root"
bash ./board-host.sh setup --serial "$board_serial" --request-file "$request_file"
```

Use the unattended request interface instead of automating terminal prompts. Preserve the launcher's exit code and its single JSON stdout result; diagnostics are on stderr.

## Verify and report

Read `status`, `stage`, `completed`, and `skipped`, then compare actual board state against the selected settings using `AGENTS.md` and `docs/usage.md`. Check the actual hostname/keyboard, connected Wi-Fi SSID when requested, password-aging state and fresh sudo authentication when credentials changed, and service states when Network Mode is enabled. Send authentication secrets through stdin without exposing them in commands or transcripts.

Test external SSH/Bonjour only when requested and possible. An ADB connection, a setup marker, or loopback SSH alone does not prove external Wi-Fi/SSH reachability. Keep temporary SSH known-hosts files separate from the real host config.

A timeout or lost connection can leave changes applied without a JSON result. Any failing stage may have partly applied its changes. Never automatically retry password changes or resets, or rerun the entire setup after a partial failure. Retain USB/ADB access and protected credentials, inspect the resulting state, and resolve how to resume within the user's authorized operation. At stage `ssh`, preserve the completed board actions; cleanup warnings do not undo configuration.

Report the selected board, tool revision/hash, nonsecret requested choices, resulting state, checks actually performed, and any failed stage or cleanup warning. Distinguish mocked checks, board checks, loopback tests, and external network tests. Keep credentials and personal host paths out of the report. For cancelled or incomplete runs, say which actions were actually attempted.
