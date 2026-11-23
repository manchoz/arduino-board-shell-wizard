# Arduino App Lab board setup and reset

An interactive Bash wizard for App Lab-style board setup on an **official Arduino Uno Q or Ventuno Q Linux image**. It guides you through board name, keyboard layout, Wi-Fi, Linux password, and Network Mode configuration, following the board setup flow of the [Arduino App Lab setup wizard](https://docs.arduino.cc/software/app-lab/configure/config/).

The script runs on the board; copy it there and launch it remotely from Windows, Linux, or macOS over USB/ADB, or use a local board console. A companion script resets App Lab setup state.

The host launchers below handle transfer, verification, and cleanup. Humans use the interactive wizard; agents can supply an explicit private request and receive a JSON result. Both paths use the same board operations in `board/board-common.sh`. Host provisioning requires ADB and the OS's native Bash or PowerShell; configuration runs with the board's installed Bash and tools.

For agent instructions, read [AGENTS.md](AGENTS.md). The [verification record](docs/verification.md) describes the real-board tests and their limits.

## Repository layout

| Location | Contents |
| --- | --- |
| Root | `board-host.sh` and `board-host.ps1`, plus README, agent guidance, and Git configuration. |
| `board/` | Setup/reset wizards, unattended request worker, and shared board operations. |
| `host/` | Optional SSH key and client-config helpers used by the host launchers. |
| `tests/` | Hardware-free Bash and PowerShell test suites. |
| `docs/` | Verification evidence. |

Keep the `board/` and `host/` directories with the launchers when copying this repository to a host. The launchers locate their helpers and payloads relative to their own files, so they also work from another working directory. Direct board-script and test paths now start with `board/` and `tests/`, respectively.

## Run the setup wizard over USB/ADB

Install ADB on your computer and connect the board over USB. [Google's SDK Platform-Tools downloads](https://developer.android.com/tools/releases/platform-tools) provide ADB for Windows, Linux, and macOS without requiring Android Studio. If you extract that download, add its `platform-tools` directory to your host's `PATH`.

Run the commands for your host OS **from this repository directory**. Replace `YOUR_DEVICE_SERIAL` with a serial listed as `device` by `adb devices -l`; select the board explicitly even if only one is connected.

### Linux prerequisites

On Debian or Ubuntu, install ADB and the USB-device rules:

```sh
sudo apt-get update
sudo apt-get install adb android-sdk-platform-tools-common
adb version
```

The [Debian ADB package](https://packages.debian.org/trixie/adb) supplies the client. For another Linux distribution, use its ADB package or Google's Platform-Tools download. If `adb devices -l` reports `no permissions`, check your distribution's USB-device rules and group access. [Google's Ubuntu USB setup](https://developer.android.com/studio/run/device) uses the `plugdev` group; if your user is missing from that group, run `sudo usermod -aG plugdev "$(id -un)"`, then log out and back in and reconnect the board. Installing rules alone does not replace the group-membership step on Ubuntu.

### macOS prerequisites

If you use Homebrew, install its [Android Platform-Tools cask](https://formulae.brew.sh/cask/android-platform-tools):

```sh
brew install --cask android-platform-tools
adb version
```

Alternatively, use Google's macOS Platform-Tools download. macOS does not require an additional ADB USB driver; see [Google's USB host setup](https://developer.android.com/studio/run/device). Use Terminal with Bash or zsh for the host commands below. The setup script itself runs with the board's Bash and installed Linux tools.

### Host launchers

On **Windows**, use Windows PowerShell 5.1 or PowerShell 7:

```powershell
.\board-host.ps1 -Operation setup -Serial YOUR_DEVICE_SERIAL
.\board-host.ps1 -Operation reset -Serial YOUR_DEVICE_SERIAL
```

PowerShell accepts operation names regardless of capitalization, including `Setup` and `Reset`.

On **Linux or macOS**, use Bash (the macOS launcher supports the supplied Bash 3.2):

```sh
bash ./board-host.sh setup --serial YOUR_DEVICE_SERIAL
bash ./board-host.sh reset --serial YOUR_DEVICE_SERIAL
```

The launcher finds the board scripts in its `board/` directory, selects the requested device, checks its identity, uploads all four board files into a unique temporary directory, verifies SHA-256 hashes, and launches the wizard with an interactive board terminal. It cleans up script copies afterward and preserves the board operation's exit code. If cleanup fails, it reports the directory to remove after reconnecting; it does not undo configuration changes.

For human use, omitting the serial selects the only ready ADB device; multiple devices require an explicit serial. Every subsequent command uses that serial. Unattended runs always require an explicit serial. Supplying an empty request path is rejected before contacting ADB. Transport commands have a 120-second timeout (`--timeout SECONDS` or `-TimeoutSeconds SECONDS`); human password prompts are not timed out. If an unattended run times out or loses USB, board changes may still have occurred: inspect state before retrying. Launchers never retry configuration automatically.

### Optional SSH key and board alias

After successful interactive setup, the host launcher asks whether to install your SSH public key and configure `ssh <board-name>`. The answer defaults to **no**. If you accept, it suggests an existing `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or lets you enter another public-key path. It uses existing keys; it does not generate a new pair. This final step belongs to the host launcher, so a manually launched board wizard does not offer it.

You can request the step explicitly on **Windows**:

```powershell
.\board-host.ps1 -Operation setup -Serial YOUR_DEVICE_SERIAL -SshKey "$HOME\.ssh\id_ed25519.pub"
```

On **Linux or macOS**:

```sh
bash ./board-host.sh setup --serial YOUR_DEVICE_SERIAL --ssh-key "$HOME/.ssh/id_ed25519.pub"
```

The host needs the OpenSSH client commands `ssh` and `ssh-keygen`. On Debian/Ubuntu, install `openssh-client` if they are missing. macOS supplies them; for Windows, see Microsoft's [OpenSSH key authentication guidance](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement). Choose a single OpenSSH public key, normally a `.pub` file. Only its key type and public data travel over ADB to `/home/arduino/.ssh/authorized_keys`; the private key stays on your computer.

The launcher uses the board's actual hostname as the alias and writes a marked block at the start of your host's `~/.ssh/config` (on Windows, your user profile's `.ssh\config`). It sets `Port 22`, `User arduino`, `PubkeyAuthentication yes`, and `IdentitiesOnly yes`. `IdentityFile` points to the paired private-key path when that file exists; otherwise it uses the public-key path to select the matching key in your SSH agent. The port and key-authentication settings override conflicting defaults for this board alias. A passphrase-protected key may still ask for its passphrase unless loaded into your agent; see the [OpenSSH client configuration reference](https://man.openbsd.org/ssh_config).

The default address is `<board-name>.local`. Network Mode must be enabled, and your host must reach the board over Wi-Fi or Ethernet with working `.local` discovery. ADB installs the key but does not establish that network connection. Supply `-SshHost HOST_OR_IP` or `--ssh-host HOST_OR_IP` alongside the key option to use a reachable hostname or IP address when discovery is unavailable. Then connect with `ssh YOUR_BOARD_NAME`, replacing `YOUR_BOARD_NAME` with the hostname chosen during setup. Normal SSH host-key verification still applies on the first connection.

Repeated runs update that board's marked config block and avoid adding the same authorized key twice, preserving restrictions on an existing key entry. Other config text is retained. An explicit alias already present outside the managed block in the main config file is rejected; resolve that conflict yourself before retrying. Symlinked SSH directories/config files and invalid candidate configs are rejected. The host config is saved only after key installation succeeds; if saving then fails, the board may already have the key. Reset preserves installed keys and the host's config entry.

The host SSH directory and config are restricted to your account: permissions 700/600 on Linux/macOS, and protected current-user-only ACLs on Windows. The directory is protected before temporary files are created; existing access grants to other accounts are removed.

### Manual transfer: Windows PowerShell

```powershell
adb devices -l
$boardSerial = 'YOUR_DEVICE_SERIAL'
$boardTemp = (adb -s $boardSerial shell mktemp -d /tmp/arduino-board-tools.XXXXXX).Trim()
if ($LASTEXITCODE -ne 0 -or $boardTemp -notmatch '^/tmp/arduino-board-tools\.[A-Za-z0-9]+$') { throw 'Could not create a board temporary directory.' }
adb -s $boardSerial push board/board-common.sh "$boardTemp/board-common.sh"
if ($LASTEXITCODE -ne 0) { throw 'Shared operations upload failed.' }
adb -s $boardSerial push board/setup-arduino-board.sh "$boardTemp/setup-arduino-board.sh"
if ($LASTEXITCODE -ne 0) { throw 'Setup upload failed.' }
adb -s $boardSerial shell -tt bash "$boardTemp/setup-arduino-board.sh"
```

### Manual transfer: Linux and macOS Bash or zsh

```sh
adb devices -l
board_serial='YOUR_DEVICE_SERIAL'
board_temp=$(adb -s "$board_serial" shell mktemp -d /tmp/arduino-board-tools.XXXXXX) || exit 1
board_temp=$(printf '%s' "$board_temp" | tr -d '\r')
case "$board_temp" in
  /tmp/arduino-board-tools.*) ;;
  *) printf '%s\n' 'Could not create a board temporary directory.' >&2; exit 1 ;;
esac
adb -s "$board_serial" push board/board-common.sh "$board_temp/board-common.sh" || exit 1
adb -s "$board_serial" push board/setup-arduino-board.sh "$board_temp/setup-arduino-board.sh" || exit 1
adb -s "$board_serial" shell -tt bash "$board_temp/setup-arduino-board.sh"
```

`mktemp` runs on the board, so this uses the same board-side temporary-directory command on all host OSes. The `tr` command removes carriage returns from the captured directory name.

`-tt` forces an interactive board terminal, which the script requires for password entry. Upload the script first: piping the script into `bash -s` does not provide the required terminal. Keep the host terminal open to reuse its serial and temporary-directory variables for a later Wi-Fi run, reset, or cleanup.

From a local board console, with the setup script and shared helper already copied into the current directory, run:

```bash
bash setup-arduino-board.sh
```

Keep `board-common.sh` beside the script when using manual transfer or a local console. The host launchers transfer it automatically. If the repository is on the board, run `bash board/setup-arduino-board.sh` from its root instead.

### Setup wizard prompts

| Step | What to enter | Result |
| --- | --- | --- |
| Hostname | Blank keeps the current name; otherwise enter a new name. | Marks the hostname step complete. A new name must be 1–63 letters, digits, or hyphens and start/end with a letter or digit. Names that become `unoq` after removing hyphens and ignoring case are rejected; blank still keeps a factory `uno-q` name. |
| Keyboard | Blank keeps the current layout; otherwise enter a layout code such as `us` or `de`, using only letters, digits, underscores, or hyphens. | Marks the keyboard step complete. |
| Wi-Fi | Answer `y`/`yes` to connect, or blank/`n`/`no` to skip. | `nmcli` prompts for the SSID's password. A successful connection made by the script marks the Wi-Fi step complete. |
| Linux password | On first use, enter and confirm a new password. On later runs, answer `n`/`no` to keep it. | Sets or preserves the `arduino` account password and marks credentials complete. |
| Network Mode | If no password was changed and Network Mode is disabled, choose whether to enable it; blank means yes. | Enables SSH and Bonjour/Avahi if approved. Setting/changing the Linux password enables Network Mode automatically when it is disabled. Already enabled services are left enabled. |

**Wi-Fi and Network Mode are separate.** Wi-Fi connects the board to a wireless network. Network Mode enables SSH and Bonjour/Avahi. Enabling these services with Wi-Fi skipped does not give your PC a network route to the board.

Hostname and keyboard steps are marked complete even when you keep their current values. A skipped Wi-Fi step does not get a new completion flag. Seeing an existing Wi-Fi connection and declining to change it also does not write that flag.

Setup applies changes as it progresses. If a later step fails, earlier changes remain; inspect the board state before rerunning. The final completion message does not imply that a skipped Wi-Fi step was performed.

### Linux password compatibility

New Linux passwords must have at least eight characters, must not contain `arduino` (case-insensitive) or backslashes, and must not start/end with whitespace. These restrictions apply to the **Linux password**, not the Wi-Fi password. The installed password helper uses bare `read`, which can alter backslashes and edge whitespace; setup rejects those Linux passwords rather than silently changing them.

Setup calls `sudo /usr/local/bin/arduino-passwd` explicitly, so it does not require `/usr/local/bin` in sudo's `secure_path`. It queries `chage` in the C locale because it parses English field names. Neither script modifies sudoers or expires the account.

Setup verifies the device-tree identity before making changes. Its Network Mode prompt accepts blank/`y`/`yes` as approval and `n`/`no` as refusal, ignoring case. Invalid input or a failed read at that prompt stops setup. All script API requests have a five-second connection timeout and a thirty-second total timeout.

## Unattended use for agents

An unattended run uses `board/board-request.sh`, which shares configuration functions with the human wizard. It reads the complete request from stdin, validates all supplied choices before configuration, and never interprets values as shell code. It does not require or bypass the wizard's terminal guard.

Requests are UTF-8 text without a BOM, at most 64 KiB, beginning with `ARDUINO_BOARD_REQUEST_V1`. The limit counts bytes, including the header and line endings, and is enforced by both launchers and the direct board worker. Each following line is `key=literal value`, split at its first `=`. LF and CRLF line endings are accepted. Keys must be unique and known; blank lines, embedded CR/LF in values, and NUL bytes are rejected. Spaces, quotes, dollar signs, equals signs, and backslashes in values remain literal. Linux passwords retain the restrictions described above; those restrictions do not apply to Wi-Fi passwords.

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

Nonempty keyboard codes use only letters, digits, underscores, or hyphens, matching the interactive wizards.

Supply secrets through the private request file, not shell arguments, shell history, environment variables, or terminal transcripts. The host forwards its bytes through ADB stdin without copying the request to the board. The worker suppresses command output and returns no credentials. Create requests outside this repository; retain/delete them according to your credential-storage policy.

On Linux/macOS, create a private directory (`mkdir -m 700 /absolute/path/private-directory`) before writing credentials. The request must belong to your account and have owner-only permissions, for example `chmod 600 /absolute/path/private-directory/request.txt`. Run:

```sh
bash ./board-host.sh setup --serial YOUR_DEVICE_SERIAL --request-file /absolute/path/private-directory/request.txt
```

On Windows, use a private directory whose ACL grants file access to your account (SYSTEM/Administrators are also permitted). Restrict the directory **before** writing credentials. For example:

```powershell
$requestDir = Join-Path ([IO.Path]::GetTempPath()) ('board-request-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $requestDir | Out-Null
$acl = Get-Acl -LiteralPath $requestDir
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -LiteralPath $requestDir -AclObject $acl
$requestFile = Join-Path $requestDir 'request.txt'
# Save the chosen request into $requestFile as UTF-8 without a BOM, using a private editor or secret manager.
.\board-host.ps1 -Operation setup -Serial YOUR_DEVICE_SERIAL -RequestFile $requestFile
```

For reset, select `reset`/`-Operation reset` and supply a reset request with `confirm=RESET`. Privileged reset operations authenticate before configuration, clear the four flags before service changes, and delete selected Wi-Fi profiles last. Passwords, apps, files, and SSH keys remain preserved.

For valid unattended invocations, stdout contains one JSON object; diagnostics go to stderr:

```json
{"version":1,"operation":"setup","status":"ok","stage":"complete","completed":["verify"],"skipped":["hostname","keyboard","wifi","credentials","network"]}
```

`completed` records configuration actions/verification that finished; `skipped` records settings preserved or operations unnecessary. Setup still writes the hostname, keyboard, and credentials markers when those settings are preserved. On failure, `stage` identifies the failing phase and `completed` retains finished actions; the failing phase itself may already have made changes. Launcher failures use stages such as `arguments`, `device`, `upload`, or `transport`. Exit 0 means success; worker exit 2 means rejected input/preflight, exit 1 means a board-operation failure, and transport timeout exit 124 means a timeout. Worker interruption exits 130/143 are preserved; other nonzero codes can report transport failure. Cleanup warnings never replace the operation's result. Confirm actual settings before resuming after any partial or transport failure.

For unattended setup, add `--ssh-key PUBLIC_KEY` (Bash) or `-SshKey PUBLIC_KEY` (PowerShell) to the request-file invocation to enable the optional SSH step without prompts; the address override also works there. These options are setup-only and do not change the board request format. Successful output remains one board-result JSON object, emitted after the optional step succeeds. If SSH configuration fails after setup, the launcher returns a nonzero exit and one JSON object with status `error`, stage `ssh`, and the board's completed/skipped actions preserved. SSH actions are not added to those board-action arrays. Inspect the reported state before retrying; board setup is already complete.

For direct board use, copy `board/board-request.sh` and `board/board-common.sh` into the same directory on the board, then run `bash board-request.sh setup < /private/request.txt` (or `reset`) from that directory. With the repository on the board, use `bash board/board-request.sh setup < /private/request.txt` from its root.

## Add or change Wi-Fi later

Rerun setup using the same ADB launch command. If the earlier temporary copy was removed, repeat the transfer steps first.

1. Leave hostname and keyboard blank.
2. Answer **yes** to `Configure Wi-Fi now?`, or to changing the network if Wi-Fi is already connected.
3. Enter the SSID and let `nmcli` prompt interactively for the Wi-Fi password. Do not put the password in a command line.
4. Answer **no** to changing the Linux password.
5. If Network Mode is already enabled, that step is skipped. If it is disabled, choose whether to enable it separately.

After the connection succeeds, the script stores `setup-network=done`. Verify the connection on the **board**:

```bash
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status
nmcli -f GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY device show wlan0
curl --silent --show-error --connect-timeout 5 --max-time 30 \
  --write-out '\nHTTP %{http_code}\n' http://127.0.0.1:8800/v1/properties/setup-network
```

The Wi-Fi device should be connected, and the property should return the plain text `done` with HTTP 200. Use the Wi-Fi device name from `device status` if it differs from `wlan0`.

With Network Mode enabled and a reachable network address, connect from your **PC** using `ssh arduino@YOUR_HOSTNAME.local`. Use the board's IP address if `.local` lookup is unavailable. The Linux login password and the Wi-Fi password are separate credentials.

## Check setup results

Run these checks on the **board**, through its console or an interactive ADB shell:

Open that shell with `adb -s "$board_serial" shell -tt` on Linux/macOS, or `adb -s $boardSerial shell -tt` in PowerShell.

```bash
LC_ALL=C chage -l arduino
arduino-app-cli system network-mode status
systemctl is-enabled ssh.service avahi-daemon.service
systemctl is-active ssh.service avahi-daemon.service
arduino-app-cli system check
arduino-app-cli config get --format json
```

After password setup, `chage` should no longer say `password must be changed`. If Network Mode was enabled, its status should be `enabled`, and both services should be `enabled` and `active`. Check that the configured data/apps directories exist and are writable by `arduino`.

For a fresh password check, run `sudo -k /usr/bin/id -u` and enter the Linux password; the result should be `0`. An SSH password login to `arduino@127.0.0.1` from the board checks the local SSH service. Test login from another computer separately once Wi-Fi or another network connection is available. CLI prerequisite checks alone do not prove that password authentication works.

The board-local API exposes these setup markers:

| Key | When setup writes `done` |
| --- | --- |
| `setup-board-name` | After completing the hostname step, including keeping its value. |
| `setup-keyboard-name` | After completing the keyboard step, including keeping its value. |
| `setup-network` | After a successful Wi-Fi connection initiated by setup. |
| `setup-credentials` | After successfully setting a password, or choosing to keep an existing one. |

`GET /v1/properties` returns a JSON key list; a fresh image can return `{"keys":null}`. `GET /v1/properties/{key}` returns plain text `done` for a completed step, or HTTP 404 with an empty body for an absent key. Inspect the HTTP status as well as the body. These flags track setup progress; they are not saved copies of the original settings.

## Reset setup

Use a local board console or a USB/ADB terminal. SSH sessions are rejected because resetting network access can disconnect you. Close App Lab during the reset, then reconnect/reopen it afterward.

To launch the reset from the same **PowerShell** session:

```powershell
adb -s $boardSerial push board/board-common.sh "$boardTemp/board-common.sh"
if ($LASTEXITCODE -ne 0) { throw 'Shared operations upload failed.' }
adb -s $boardSerial push board/reset-arduino-board.sh "$boardTemp/reset-arduino-board.sh"
if ($LASTEXITCODE -ne 0) { throw 'Reset upload failed.' }
adb -s $boardSerial shell -tt bash "$boardTemp/reset-arduino-board.sh"
```

From the same **Linux/macOS** terminal used for setup:

```sh
adb -s "$board_serial" push board/board-common.sh "$board_temp/board-common.sh" || exit 1
adb -s "$board_serial" push board/reset-arduino-board.sh "$board_temp/reset-arduino-board.sh" || exit 1
adb -s "$board_serial" shell -tt bash "$board_temp/reset-arduino-board.sh"
```

If the temporary directory was removed or you opened a new terminal, repeat the serial selection and temporary-directory steps before transferring reset.

Alternatively, copy `board/reset-arduino-board.sh` and `board/board-common.sh` into the same directory on the board and run `bash reset-arduino-board.sh` there. With the repository on the board, run `bash board/reset-arduino-board.sh` from its root.

The reset script:

- Clears only `setup-board-name`, `setup-keyboard-name`, `setup-network`, and `setup-credentials` through the local App CLI API. Already-absent flags are accepted.
- Offers a replacement hostname and keyboard layout; blank keeps the current value. The setup script never recorded the original image defaults, so the reset does not guess them.
- Optionally masks/disables/stops SSH and Bonjour/Avahi, following Arduino's Network Mode reset. Answer **yes** to undo Network Mode setup.
- Optionally deletes **all** saved NetworkManager Wi-Fi profiles and their stored passwords, including the active profile. Ethernet/VPN profiles are left alone. Answer **yes** to forget Wi-Fi setup.
- Requires the exact confirmation `RESET` before applying changes.

Apps, user files, installed software, SSH keys, and the current Linux password are preserved. This is **not a factory restore**, and it does not reset microcontroller firmware.

Clearing the credentials flag does not expire or restore the Linux password. App Lab may still detect that the password is already set. To change it during setup, rerun the setup wizard and accept its password-change prompt. Keeping the password avoids lockout and an insecure shared default password.

If a command fails, the reset stops; earlier changes are not rolled back. Correct the error and rerun. Deleting Wi-Fi profiles cannot recover their saved passwords; have them available before confirming. The installed App CLI daemon must support `DELETE /v1/properties/{key}`.

## Troubleshooting and cleanup

- **Missing password helper under sudo:** On `mufi`, App Lab's bare `sudo arduino-passwd` call failed because sudo's search path omitted `/usr/local/bin`. Use this setup script's explicit helper path. Expiring the account does not fix command lookup; if it was already expired, use interactive `passwd` over USB/ADB to recover.
- **Debconf frontend messages during SSH initialization:** In the verified ADB run, `dpkg-reconfigure openssh-server` fell back to its noninteractive frontend and still created all SSH host keys successfully. Judge the result by the command exit status, host keys, service state, and login checks.
- **Unexpected password-change date:** Compare `date -u` on the board with your host clock. Password-aging dates use the board's clock; the verified factory board's clock lagged behind the session date.
- **A later setup step fails:** Keep USB/ADB access, inspect the already written flags and actual settings, and correct the failing step before rerunning.

After finishing with the uploaded copies, remove them from the same PowerShell session:

```powershell
adb -s $boardSerial shell rm -f -- "$boardTemp/setup-arduino-board.sh" "$boardTemp/reset-arduino-board.sh" "$boardTemp/board-common.sh" "$boardTemp/board-request.sh"
adb -s $boardSerial shell rmdir -- "$boardTemp"
```

In the same **Linux/macOS** terminal:

```sh
adb -s "$board_serial" shell rm -f -- "$board_temp/setup-arduino-board.sh" "$board_temp/reset-arduino-board.sh" "$board_temp/board-common.sh" "$board_temp/board-request.sh"
adb -s "$board_serial" shell rmdir -- "$board_temp"
```

Removing these script copies does not undo provisioning. Keep any generated credentials in a private location outside this repository, with access restricted to their owner.

## Hardware-free checks

Run these locally in **Bash 4.4 or later**, from this repository directory. A board is not required. The board scripts use Bash case conversion and the unattended worker uses associative arrays and empty arrays with `nounset`; plain `sh` is not suitable. The host launcher itself supports Bash 3.2.

For local development on Debian/Ubuntu, install ShellCheck with `sudo apt-get install shellcheck` and check your interpreter with `bash --version`. On macOS, select [Homebrew's Bash](https://formulae.brew.sh/formula/bash) and install [ShellCheck](https://formulae.brew.sh/formula/shellcheck) before entering the test commands:

```sh
brew install bash shellcheck
export PATH="$(brew --prefix bash)/bin:$PATH"
bash
```

The PATH change also makes child scripts resolve the same Bash. This host Bash installation is for local tests; provisioning over ADB uses the Bash installed on the board.

```bash
shellcheck -P SCRIPTDIR *.sh board/*.sh host/*.sh tests/*.sh
for script in *.sh board/*.sh host/*.sh tests/*.sh; do
  bash -n "$script" || exit 1
done
bash tests/test-reset-arduino-board.sh
bash tests/test-board-scripts.sh
bash tests/test-board-request.sh
bash tests/test-board-host.sh
```

Run the Bash host tests on native Linux/macOS; Windows Git Bash does not establish POSIX file-permission behavior. Windows host checks use a temporary fake ADB executable compiled by Windows PowerShell's installed .NET compiler:

```powershell
powershell.exe -NoProfile -File .\tests\test-board-host.ps1
powershell.exe -NoProfile -File .\tests\test-board-host.ps1 -HostShell pwsh.exe
```

The second command exercises the launcher under PowerShell 7 when `pwsh.exe` is installed; the test harness still runs under 5.1 to compile the fake executable. These check Wi-Fi profile selection, property-delete responses/errors, supported-board checks, password rejection/handoff, Network Mode confirmation (including invalid input/EOF), non-interactive rejection, and reset cancellation/confirmed mutation order. The control-flow tests use disposable script copies with device-tree fixtures and the TTY check bypassed; console rejection is checked against the original scripts. Input and board commands are mocked. They do not change board settings or make real HTTP requests.

The new tests additionally check literal unattended inputs, exact byte limits and oversized UTF-8 requests, validation before configuration, secret-free command arguments/results, partial failures, sudo preflight, and reset ordering. Host tests check device selection, paths containing spaces, empty request paths, capitalized PowerShell operations, uploaded hashes, timeouts versus interruptions, malformed results, cleanup failures, and exit codes. SSH tests generate a disposable key pair and use temporary host/board homes to check key validation, resolved SSH aliases, repeated updates, existing config, key restrictions, permissions, and failure preservation. They use fake ADB and never access hardware or modify your real SSH config.

`-P SCRIPTDIR` lets ShellCheck resolve shared helpers relative to each script. `bash -n` checks one script per invocation; additional filenames are script arguments. The loop checks all shell files.

## Recorded hardware verification

Full first-use provisioning passed on an UNO Q with App CLI/daemon `0.14.1` on November 23, 2026. The setup script at the recorded revision rejected unsafe/mismatched passwords, set a generated Linux password, created SSH host keys, enabled SSH/Avahi, and passed fresh sudo and loopback SSH authentication. Wi-Fi was skipped in that earlier run, so `setup-network` remained absent then. See the [verification record](docs/verification.md) for exact conditions and results.

The new Windows launcher later passed a real unattended setup preserving all settings under PowerShell 5.1, and rejected an unconfirmed reset under PowerShell 7. Both runs returned the expected JSON and exit codes, removed uploaded files, and preserved hostname, keyboard configuration, password-aging metadata, saved network profiles, setup markers, and service states. The board was already provisioned, with Wi-Fi configured before these checks. Native Debian mocked launcher tests passed; native Linux/macOS USB end-to-end checks and unattended Wi-Fi/password/reset mutations remain unverified.

Earlier checks that preserved board settings passed over ADB on these boards:

| Board | Model | App CLI / daemon |
| --- | --- | --- |
| `mnx-21q-mino` | VENTUNO Q | 0.14.1 |
| `mnx-unoq-mufi` | UNO Q | 0.13.0 |

Checked required tools/API access, syntax, the hardware-free tests, interactive cancellation, and SSH rejection (simulated SSH environment in an ADB PTY). A uniquely named temporary API property was created, read, deleted through the reset helper, and deleted again to verify absent-key handling.

Before/after checks confirmed unchanged setup flags, Wi-Fi profile UUIDs/types, hostname, keyboard, password-aging metadata, and SSH/Avahi enabled/active states. Temporary properties and test files were removed. Actual Wi-Fi deletion, service shutdown, and hostname/keyboard changes were deliberately not exercised.
