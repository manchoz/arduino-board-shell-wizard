# Unattended use for agents

For host prerequisites, see the [ADB setup guide](adb.md); interactive workflows are in the [usage guide](usage.md). Agent procedures are in [AGENTS.md](../AGENTS.md); implementation details and developer checks are in the [technical reference](technical.md). Return to the [quick start](../README.md) for the basic launcher commands.

Run host commands below from the **repository root**, with ADB on your terminal's `PATH`.

Use an explicit device serial and a private request file for unattended setup or reset, even when only one board is connected. All supplied choices are validated before configuration, and request values are treated as literal inputs.

## Portable agent skill

The [Arduino board provisioning skill](../.agents/skills/arduino-board-provision/SKILL.md) turns natural-language setup requests into this unattended workflow. It supports setup and Wi-Fi updates, including optional SSH integration. Keep a complete checkout or extracted release of the tool installed, or use the [bundled plugin](agent-workspace.md#alternative-install-the-bundled-plugin). Copying the standalone skill alone does not install the launchers or ADB.

Follow [Enable board provisioning in your agent workspace](agent-workspace.md) to install the local tool and project skill, record the tool location, check workspace readiness, and provision several boards using private requests. That guide includes personal installation alternatives and agent-specific discovery links.

The agent needs local command execution and USB/ADB access on the computer connected to the board. Give a standalone skill the local tool root; a plugin resolves its bundled root. Supply a protected request-file path or available secret-manager entry and keep passwords out of chat. Missing credentials or ambiguous device selection require clarification before configuration. For a fresh board, choose a new Linux-password source and approve enabling Network Mode. This setup skill does not perform resets; explicit reset requests use the separate contract below.

## Agent workflow

1. Use the authorization already given for the requested operation; do not ask for it again. For documentation or hardware-free checks, use the mocked suites in the [technical reference](technical.md#hardware-free-checks) instead of contacting a board.
2. Select the intended device explicitly, even if only one is ready. Use the [ADB guide](adb.md) to locate an existing App Lab/IDE installation and configure the terminal; use `-s SERIAL` for subsequent direct ADB commands.
3. Protect a request directory before writing the request outside the repository. Specify credential, Network Mode, and reset choices deliberately. Use an existing public key only when SSH integration is requested.
4. Invoke the host launcher once with the serial and private request file. Use this request interface rather than guessing prompts, and keep secrets out of command arguments and captured output.
5. Check the exit code and JSON `status`, `stage`, `completed`, and `skipped`, then compare actual board state with the requested choices. A failed stage may have partly applied changes; a timeout or lost connection can leave changes applied without a result.
6. On failure, retain USB/ADB access and the protected credentials. Inspect state before deciding how to resume; never automatically retry password changes or resets. A host-stage `ssh` failure preserves completed board actions, and cleanup warnings do not undo configuration.

## Request contract

Requests are UTF-8 text without a BOM, at most 64 KiB, beginning with `ARDUINO_BOARD_REQUEST_V1`. The limit counts bytes, including the header and line endings. Each following line is `key=literal value`, split at its first `=`. LF and CRLF line endings are accepted. Keys must be unique and known; blank lines, embedded CR/LF in values, and NUL bytes are rejected. Spaces, quotes, dollar signs, equals signs, and backslashes in values remain literal. New Linux passwords must have at least eight characters, must not contain `arduino` (case-insensitive) or backslashes, and must not start/end with whitespace. These [Linux password rules](usage.md#linux-password-rules) do not apply to Wi-Fi passwords.

This example preserves settings on an **already provisioned** board:

```text
ARDUINO_BOARD_REQUEST_V1
hostname=
keyboard=
wifi=keep
linux_password=keep
network_mode=keep
```

| Key | Setup | Reset |
| --- | --- | --- |
| `hostname`, `keyboard` | Required; empty preserves the setting. | Required; empty preserves the setting. |
| `wifi` | Required: `keep` or `connect`. | Not accepted. |
| `ssid`, `wifi_password` | Both required for `wifi=connect`; empty password selects an open network. Otherwise omit both. Uses the existing `nmcli` connection flow for personal/open Wi-Fi. | Not accepted. |
| `linux_password` | Required: `keep` or `set`. First-use password state requires `set`. | Not accepted. |
| `new_password` | Required for `set`; otherwise omit. | Not accepted. |
| `network_mode` | Required: `keep` or `enable`. Setting a Linux password requires `enable`, matching first-use setup. | Required: `keep` or `disable`. |
| `current_password` | Optional sudo authentication; required when enabling disabled Network Mode while keeping the Linux password. | Required for privileged changes unless sudo is already authorized. |
| `delete_wifi` | Not accepted. | Required: `no` or `yes` (all saved Wi-Fi profiles). |
| `confirm` | Not accepted. | Required: exactly `RESET`. |

Nonempty keyboard codes use only letters, digits, underscores, or hyphens, matching the [interactive wizard choices](usage.md#setup-wizard-prompts).

Supply secrets through the private request file, not shell arguments, shell history, environment variables, or terminal transcripts. The request file stays on the host, and the result contains no credentials. Create requests outside this repository; retain/delete them according to your credential-storage policy.

## Prepare and use a private request file

Humans can pass the same request file directly to a host launcher or give its path to the provisioning skill. It contains the complete setup request, including any needed passwords. Prepare it in a private editor or with an available local secret manager; keep its contents out of chat and captured output.

For an **already provisioned board**, this request changes the hostname and connects Wi-Fi while preserving the keyboard, Linux password, and Network Mode:

```text
ARDUINO_BOARD_REQUEST_V1
hostname=lab-q
keyboard=
wifi=connect
ssid=Workshop
wifi_password=<YOUR_WIFI_PASSWORD>
linux_password=keep
network_mode=keep
```

For a **fresh board**, use a new Linux password and approve enabling Network Mode:

```text
ARDUINO_BOARD_REQUEST_V1
hostname=lab-q
keyboard=
wifi=connect
ssid=Workshop
wifi_password=<YOUR_WIFI_PASSWORD>
linux_password=set
new_password=<YOUR_NEW_LINUX_PASSWORD>
network_mode=enable
```

Replace the example hostname/SSID and password placeholders locally; the angle brackets are not part of the passwords. Do not quote or escape values, add blank lines, or duplicate keys. Save as **UTF-8 without a BOM**. First-use setup and Linux-password changes require `network_mode=enable`; Wi-Fi-only updates on a provisioned board can keep both the Linux password and Network Mode.

### Linux/macOS storage and launcher

On Linux/macOS, create a private directory (`mkdir -m 700 /absolute/path/private-directory`) before writing credentials. The request must belong to your account and have owner-only permissions, for example `chmod 600 /absolute/path/private-directory/request.txt`. Run:

```sh
board_serial=YOUR_DEVICE_SERIAL
request_file=/absolute/path/private-directory/request.txt
bash ./board-host.sh setup --serial "$board_serial" --request-file "$request_file"
```

### Windows storage and launcher

Use a private directory outside the repository whose ACL grants file access to your account (SYSTEM/Administrators are also permitted by the launcher). Restrict the directory **before** writing credentials. The following creates a persistent request directory under `%LOCALAPPDATA%\ArduinoBoardWizard\requests\`, opens the file in Notepad, and displays its full path:

```powershell
$requestDir = Join-Path $env:LOCALAPPDATA ('ArduinoBoardWizard\requests\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $requestDir -Force | Out-Null
$acl = Get-Acl -LiteralPath $requestDir
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -LiteralPath $requestDir -AclObject $acl
$requestFile = Join-Path $requestDir 'request.txt'
notepad.exe $requestFile
$requestFile
```

Save the chosen request as UTF-8 without a BOM. Then run the following from the **repository root**, in the same PowerShell session so `$requestFile` remains defined. Use the intended board's serial from an entry listed as `device` by `adb devices -l`:

```powershell
$boardSerial = 'YOUR_DEVICE_SERIAL'
.\board-host.ps1 -Operation setup -Serial $boardSerial -RequestFile $requestFile
```

### Pass the file to the skill

Include the full request-file path in the same message as the skill invocation; replace `<full path>` with the displayed path, not the literal variable name `$requestFile`:

```text
$arduino-board-provision Provision my board using the private request file at <full path>.
```

For Claude Code, use `/arduino-board-provision` with the same request. The agent checks the private file and supplies its path to the launcher; passwords stay in protected local storage. If additional requested settings conflict with the file, resolve those choices before configuration. Keep generated Linux credentials available for future login, and retain the protected request if an operation fails.

## Reset requests

For reset, select `reset`/`-Operation reset` and supply a reset request with `confirm=RESET`. Privileged operations authenticate before configuration. Passwords, apps, files, and SSH keys remain preserved.

## Results and failure handling

For valid unattended invocations, stdout contains one JSON object; diagnostics go to stderr:

```json
{"version":1,"operation":"setup","status":"ok","stage":"complete","completed":["verify"],"skipped":["hostname","keyboard","wifi","credentials","network"]}
```

`completed` records configuration actions/verification that finished; `skipped` records settings preserved or operations unnecessary. On failure, `stage` identifies the failing phase and `completed` retains finished actions; the failing phase itself may already have made changes. Launcher failures use stages such as `arguments`, `device`, `upload`, or `transport`. Exit 0 means success; worker exit 2 means rejected input/preflight, exit 1 means a board-operation failure, and transport timeout exit 124 means a timeout. Worker interruption exits 130/143 are preserved; other nonzero codes can report transport failure. Cleanup warnings never replace the operation's result. Confirm actual settings before resuming after any partial or transport failure.

For unattended setup, add `--ssh-key PUBLIC_KEY` (Bash) or `-SshKey PUBLIC_KEY` (PowerShell) to the request-file invocation to enable the optional SSH step without prompts; optionally add `--ssh-host HOST_OR_IP` or `-SshHost HOST_OR_IP` to override the default `<board-name>.local` address. These options are setup-only and do not change the board request format. Successful output remains one board-result JSON object, emitted after the optional step succeeds. If SSH configuration fails after setup, the launcher returns a nonzero exit and one JSON object with status `error`, stage `ssh`, and the board's completed/skipped actions preserved. SSH actions are not added to those board-action arrays. Inspect the reported state before retrying; board setup is already complete.

For direct board use, copy `board/board-request.sh` and `board/board-common.sh` into the same directory on the board, then run `bash board-request.sh setup < /private/request.txt` (or `reset`) from that directory. With the repository on the board, use `bash board/board-request.sh setup < /private/request.txt` from its root.
