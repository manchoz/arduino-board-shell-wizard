# Agent guide

This repository contains an interactive Bash wizard for App Lab-style board setup and a companion script for resetting App Lab setup state on an official Arduino Uno Q or Ventuno Q Linux image. One person operates the scripts on the board, from a local console or remotely through an interactive USB/ADB shell. Read [README.md](README.md) for user workflows and [docs/verification.md](docs/verification.md) for observed hardware results.

`board-host.sh` (Linux/macOS Bash 3.2+) and `board-host.ps1` (Windows PowerShell 5.1/7) transfer and launch the board tools. Unattended agents use an explicit serial and a private request file; `board/board-request.sh` reads literal inputs through stdin and returns a JSON result. Human and unattended paths share `board/board-common.sh`. Follow the [unattended request contract](docs/unattended.md); never automate by guessing terminal prompts when the request interface is available.

Host launchers remain at the repository root. Board tools live together in `board/`, optional SSH client helpers in `host/`, test suites in `tests/`, and verification documentation in `docs/`. Keep both `board/` and `host/` beside the launchers. Local payload paths use `board/`; uploaded files remain together in one flat temporary directory on the board. Launchers resolve helpers and payloads relative to their own location.

## Documentation map and policy

- [README.md](README.md) is a short quick start for immediate setup, reset, SSH, and Wi-Fi use. Keep primary interactive commands simple: one ready ADB device is selected automatically; multiple devices and agents need explicit serials.
- [ADB setup](docs/adb.md) owns host prerequisites, bundled ADB paths, `PATH` configuration, and device selection. Check for App Lab/IDE-provided ADB before recommending another installation; those copies may not be on `PATH`.
- [Interactive usage](docs/usage.md) owns detailed wizard choices, verification commands, reset precautions, and troubleshooting. [Manual transfer](docs/manual-transfer.md) owns direct board-console use, uploads, session variables, and cleanup.
- [Unattended use](docs/unattended.md) owns the literal request/result contract. [Technical reference](docs/technical.md) owns implementation choices, regression guidance, and developer checks. [Verification](docs/verification.md) owns completed hardware evidence.
- [Agent workspace setup](docs/agent-workspace.md) owns installing the tool and skill in another project, recording the local tool root, hardware-free readiness prompts, and provisioning multiple boards sequentially. Keep its examples agent-neutral and project installation primary; link credential templates and rules from the unattended guide.
- The [portable provisioning skill](.agents/skills/arduino-board-provision/SKILL.md) owns the reusable agent workflow; installation is documented in the [workspace guide](docs/agent-workspace.md#3-enable-the-skill-in-your-project). Resolve runtime guides from the installed tool root so copies of the skill work in other agents. Keep the request contract in its existing guide rather than duplicating it in the skill.
- Put detail in its owning guide and link from the quick start. When moving content, preserve commands, field tables, result semantics, and safety precautions; update inbound links, relative paths, and context-dependent wording. State the working directory and define required variables in each workflow.

## Repository work

- Keep changes small. The scripts depend on installed board tools; preserve that approach.
- Inspect the working tree before editing and preserve existing user changes and supplied untracked files. Honor requested commit boundaries and hooks; stage only intended files. Publishing, hosted-repository renames, amendments, and hook bypasses require explicit authorization; approval of a name alone does not identify a hosted repository to rename.
- For script bug fixes, add or adjust a meaningful regression first and demonstrate failure before the fix. If it does not fail, explain the conditions tested and why; do not silently skip reproduction. Respect explicit baseline/design gates and report discrepancies before dependent changes. See the [regression guidance](docs/technical.md#regression-and-validation-practices).
- Trace callers, shell conditionals, and mocked tests when changing shared functions. Bash error handling inside conditionals needs explicit checks where a failed read or command must stop execution.
- For script changes, run `shellcheck -P SCRIPTDIR *.sh board/*.sh host/*.sh tests/*.sh` so shared helpers resolve beside each script, the per-file `bash -n` loop over those same paths, the four Bash test scripts in `tests/`, and Windows host tests from the [technical documentation](docs/technical.md#hardware-free-checks). Run Bash host tests on native Linux/macOS to verify POSIX permissions. Documentation-only changes need link, example-syntax, and diff checks.
- On Windows, pass native tools explicit file lists, use LF-only drivers and a disposable repository copy inside the WSL Linux filesystem for Bash suites, and invoke Bash with `wsl --exec /bin/bash`. Run the PowerShell host suites sequentially because their harness changes shared console input encoding; restore temporary encoding/error preferences in `finally` blocks. The [Windows/WSL recipe](docs/technical.md#windowswsl-check-recipe) covers the commands.
- Mocked tests can run locally without hardware. Their disposable copies bypass the TTY check; the original scripts must retain it.
- Choose the README, [ADB setup guide](docs/adb.md), [interactive usage guide](docs/usage.md), and [manual transfer guide](docs/manual-transfer.md) examples matching the host: PowerShell uses `$boardSerial`/`$boardTemp`; Linux/macOS Bash or zsh uses `$board_serial`/`$board_temp`. Board scripts run under the board's Bash. Local checks require Bash 4.4 or later; for macOS tests, select Homebrew Bash on `PATH` so subprocesses use it too. Host provisioning still uses the supplied Bash 3.2.
- Preserve reset's mutation order: confirm, authenticate when needed, apply optional keyboard/hostname changes, clear setup flags, reset services if selected, then delete selected Wi-Fi profiles last. The unattended worker requires the exact reset token in its request before preflight.

## Real-board work

Hardware writes must stay within the user's requested operation. Authorization given earlier in the session still applies to that operation. Documentation work and local test runs do not require changing a connected board.

For an explicitly hardware-free task, use only disposable fixtures and mocks; do not contact a real board to validate examples or fill gaps in a report. Label documentation checks and mocked results accordingly, and keep them separate from hardware evidence.

1. Discover devices with `adb devices -l` and pass `-s SERIAL` to every subsequent ADB command. If several devices are plausible, identify the intended board before writing to it.
2. Capture the initial state: device-tree compatibility, current user and UID, CLI/daemon version, hostname, keyboard, `LC_ALL=C chage -l arduino`, setup flags, Network Mode, SSH/Avahi enabled/active state, and NetworkManager connection UUIDs/types. The image helper targets UID 1000, which is the `arduino` user on the verified image.
3. Capture the host/session date and `date -u` on the board. Compare password-aging dates against the board clock; a factory image can have an old clock.
4. Inspect the installed `/usr/local/bin/arduino-passwd` and `sudo -n -l` when testing a new image. The verified image permits the helper without password authentication, so first-use password setup works while the account password must be changed.
5. Prefer the host launcher, which copies all four board files into a unique directory and verifies their SHA-256 hashes. Human runs use `shell -tt`; unattended runs use `shell -T` and forward a private request through stdin. Keep the original wizard's TTY guard intact. Manual transfers must include `board-common.sh` beside each board entry point.
6. For automated terminal input, wait for each prompt before sending its answer. Enter passwords only after the silent password prompt is ready. Upload scripts separately from interactive input.
7. Compare actual postconditions with the requested choices. Launchers remove script copies; check/report cleanup warnings. Retain credentials in their protected location and report how the user can retrieve them. Request files can contain both Linux and Wi-Fi passwords and require the same protection.

Factory-state evidence includes missing setup flags, `password must be changed`, and disabled/inactive SSH/Avahi. These observations describe onboarding state; they do not prove that every file on the board is untouched.

## Credentials and setup choices

- Keep Linux and Wi-Fi passwords separate. Linux-password restrictions come from compatibility with the image helper; they do not impose a new Wi-Fi-password policy.
- Use `/usr/local/bin/arduino-passwd` through its full sudo path. The verified helper uses bare `read`; keep rejection of backslashes and edge whitespace until the helper preserves those inputs.
- Generate a random Linux password only when the user chooses that approach. Store it outside the repository, never in arguments, terminal transcripts, committed docs, or verification reports.
- Restrict the credential directory before writing secrets. On Windows, use a protected directory ACL granting only the current account access; on Linux/macOS, use a private directory and owner-only file permissions. Redact the credential from captured output and check the saved report for accidental inclusion.
- Blank hostname/keyboard input preserves existing values. Setting/changing the Linux password automatically enables disabled Network Mode. Keeping an existing password prompts for Network Mode only if it is disabled; that prompt defaults to yes.
- For Wi-Fi-only provisioning, rerun setup, keep hostname/keyboard, connect using `nmcli`'s interactive password prompt, and decline Linux-password changes. Honor the user's Network Mode choice if that prompt appears.
- Keep credentials and USB/ADB access available when a board operation fails. Report the failing stage and resulting state. Earlier changes are not rolled back; clearing flags does not restore a factory password.
- Unattended requests must explicitly preserve/set credentials and keep/enable Network Mode. First-use state requires a new valid password, and setting it requires Network Mode approval. Use JSON stage/completed/skipped results plus actual board state; a timeout or lost connection can leave changes applied even without a result. Never retry password changes or resets automatically.
- Optional SSH setup runs on the host after successful setup. Agents explicitly choose an existing public key with `--ssh-key` or `-SshKey`, optionally overriding `<board-name>.local` with `--ssh-host` or `-SshHost`. Never pass a private key or generate one implicitly. Network Mode must be enabled; ADB key installation does not verify external network reachability. The board alias uses the actual hostname and user `arduino`.
- Preserve existing SSH config and key restrictions. The host helpers validate a candidate config before installing the public key, update only their marked alias block, and reject explicit alias conflicts in the main config. A failure at host stage `ssh` retains the board's completed/skipped actions; inspect state before retrying. Reset preserves both keys and host config. Tests must use disposable SSH directories and keys, never the real user profile/config.
- Protect the host SSH directory before creating temporary files; Windows requires current-user-only inheritable access, including removal of explicit other-account grants. Avoid reapplying an already-correct Windows ACL on repeated runs. Managed aliases explicitly use port 22 and public-key authentication so unrelated host defaults cannot disable board access.

## API and state checks

All API URLs refer to the **board's** `127.0.0.1:8800`, not the host PC. Use the scripts' five-second connection and thirty-second total timeouts.

| Operation | Observed or required behavior |
| --- | --- |
| `GET /v1/properties` | JSON key list; `{"keys":null}` is valid when no properties exist. |
| `GET /v1/properties/{key}` | HTTP 200 with plain text `done` for these setup markers; HTTP 404 can have an empty body. |
| `PUT /v1/properties/{key}` | Setup sends the raw body `done`. |
| `DELETE /v1/properties/{key}` | Reset accepts HTTP 204 and HTTP 404; other statuses or transport failures stop it. |

Keep status and body separate. Preserve an empty body when parsing curl's appended status; do not assume every response is JSON.

`setup-board-name` and `setup-keyboard-name` are written even when values are kept. `setup-credentials` is written after a successful password change or when retaining an existing password. `setup-network` is written only after a successful connection initiated by setup. Its absence alone does not establish whether Wi-Fi is currently connected.

## Verification and reporting

- For first-use provisioning, verify invalid/mismatched inputs leave the password in first-use state and the credentials flag absent before submitting a valid password.
- Verify password-aging state and fresh sudo authentication. For an automated check, pass the password through stdin to `sudo -k -S -p '' /usr/bin/id -u`; expect `0`. Do not place the password in the command itself.
- If Network Mode is enabled, verify SSH host keys exist, SSH/Avahi are enabled and active, and SSH password login works. Force password authentication for the login test so an existing SSH key cannot hide a wrong password.
- Use a temporary known-hosts file for automated loopback SSH checks. Test external network access separately; an ADB connection and a successful loopback login do not prove Wi-Fi connectivity or Bonjour discovery from another computer.
- Debconf frontend fallbacks during `dpkg-reconfigure openssh-server` occurred in a successful real-board run. Assess exit status and postconditions rather than treating those messages alone as failure.
- Record the script revision/hash, image and CLI versions, initial state, selected answers, final state, and checks actually performed. Distinguish mocked tests, loopback tests, and external network tests.
- Summarize evidence without credentials, personal host paths, or reusable private-key material. Update the durable verification record only for tests actually completed; proposed Wi-Fi or reset tests are not results.
- Keep credentials and fixture passwords out of reports and new documentation; test passwords belong only in disposable test fixtures. Record reusable findings with their limits, rather than terminal transcripts. Mock timings do not establish board performance or external network reachability.
