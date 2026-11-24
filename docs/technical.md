# Technical reference and development

For basic launcher commands, see the [quick start](../README.md). Host prerequisites are in the [ADB guide](adb.md); detailed setup, reset, Wi-Fi, and board checks are in the [interactive usage guide](usage.md). The [unattended guide](unattended.md) contains the complete request/result contract. Agent procedures are in [AGENTS.md](../AGENTS.md). This document explains the implementation and local development checks; the [verification record](verification.md) contains completed hardware evidence.

## Repository architecture

| Location | Contents |
| --- | --- |
| Root | `board-host.sh` and `board-host.ps1`, plus README, agent guidance, and Git configuration. |
| `board/` | Setup/reset wizards, unattended request worker, and shared board operations. |
| `host/` | Optional SSH key and client-config helpers used by the host launchers. |
| `tests/` | Hardware-free Bash and PowerShell test suites. |
| `docs/` | Technical reference, development checks, and verification evidence. |

Keep the `board/` and `host/` directories with the launchers when copying this repository to a host. The launchers locate their helpers and payloads relative to their own files, so they also work from another working directory. Direct board-script and test paths now start with `board/` and `tests/`, respectively.

The host launchers use the host's native Bash or PowerShell and ADB. Configuration runs under the board's Bash using installed image tools. The interactive wizards and `board/board-request.sh` share operations in `board/board-common.sh`; host-side SSH integration lives in `host/`.

## Backend behavior and design choices

### ADB transport and terminal handling

The launcher finds the board scripts in its `board/` directory, selects the requested device, checks its identity, uploads all four board files into a unique temporary directory, verifies SHA-256 hashes, and launches the wizard with an interactive board terminal. It cleans up script copies afterward and preserves the board operation's exit code. If cleanup fails, it reports the directory to remove after reconnecting; it does not undo configuration changes.

Upload uses one four-file ADB push and one board-side `sha256sum` call. Each returned hash and path is compared with the expected file, and missing, extra, or malformed results stop execution before the worker starts. Cleanup combines file removal and directory removal in one shell command.

In the [manual transfer examples](manual-transfer.md#setup-over-usbadb), `mktemp` runs on the board, so the same temporary-directory command works on all host OSes. The Bash/zsh example uses `tr` to remove carriage returns from the captured directory name.

Human launches use `shell -tt` so the original wizards receive an interactive terminal. Unattended launches use `shell -T` and forward request bytes through stdin. The worker validates the entire request before configuration and does not bypass the wizards' TTY guards. It shares configuration functions with the wizards and returns one credential-free JSON result.

Both launchers and the direct worker enforce the 64 KiB byte limit, including the header and line endings. The request is forwarded through stdin without being copied to the board. Command output is suppressed by the worker; JSON goes to stdout and diagnostics to stderr. The public format and failure semantics are in the [unattended guide](unattended.md).

The [App Lab tooling implementation](https://github.com/arduino/arduino-app-lab/blob/main/standalone-apps/app-lab-desktop/internal/board/operations.go) extracts its embedded ADB archive into the Arduino CLI data directory during startup. Installing the Arduino Q Boards core also installs ADB as a dependency. The default paths and terminal commands are in the [bundled-ADB instructions](adb.md#reuse-adb-installed-by-arduino).

### Linux password and Network Mode compatibility

The installed password helper uses bare `read`, which can alter backslashes and edge whitespace. Setup rejects those Linux-password inputs rather than silently changing them. This compatibility restriction does not impose a Wi-Fi-password policy; see the [user-facing password rules](usage.md#linux-password-rules).

Setup calls `sudo /usr/local/bin/arduino-passwd` explicitly, so it does not require `/usr/local/bin` in sudo's `secure_path`. It queries `chage` in the C locale because it parses English field names. Neither script modifies sudoers or expires the account.

Network Mode means SSH and Bonjour/Avahi, not a Wi-Fi connection. Its privileged operations unmask SSH and Avahi, reconfigure OpenSSH, then enable/start Avahi and SSH. Password authentication uses `sudo -k -S` to ignore cached credentials, and the privileged command redirects stdin from `/dev/null` before running service commands so the password cannot be inherited by them.

Setup verifies the board's device-tree identity before changes. Board-local API calls use five-second connection and thirty-second total timeouts. Host transport timeouts and partial-failure handling are described in the [usage guide](usage.md#device-selection-and-transport-failures).

### SSH client integration

For command examples and prerequisites, see the [optional SSH usage instructions](../README.md#optional-ssh-key-and-board-alias).

The optional prompt is offered by the host launcher after successful interactive setup; a manually launched board wizard does not offer it. It defaults to no and suggests an existing `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or accepts another public-key path. No key pair is generated implicitly.

Only the public key's type and data are forwarded through ADB to the board's `arduino` account and its `.ssh/authorized_keys`. The private key stays on the host.

The launcher uses the board's actual hostname as the alias and writes a marked block at the start of your host's `~/.ssh/config` (on Windows, your user profile's `.ssh\config`). It sets `Port 22`, `User arduino`, `PubkeyAuthentication yes`, and `IdentitiesOnly yes`. `IdentityFile` points to the paired private-key path when that file exists; otherwise it uses the public-key path to select the matching key in your SSH agent. The port and key-authentication settings override conflicting defaults for this board alias. A passphrase-protected key may still ask for its passphrase unless loaded into your agent; see the [OpenSSH client configuration reference](https://man.openbsd.org/ssh_config).

The default address is `<board-name>.local`. Network Mode must be enabled and the board reachable over Wi-Fi or Ethernet with working `.local` discovery. ADB key installation does not establish or verify that network connection. `-SshHost` or `--ssh-host`, supplied with the key option, overrides the address with a reachable hostname or IP address. Normal SSH host-key verification still applies on the first connection.

Repeated runs update that board's marked config block and avoid adding the same authorized key twice, preserving restrictions on an existing key entry. Other config text is retained. An explicit alias already present outside the managed block in the main config file is rejected; resolve that conflict yourself before retrying. Symlinked SSH directories/config files and invalid candidate configs are rejected. The host config is saved only after key installation succeeds; if saving then fails, the board may already have the key. Reset preserves installed keys and the host's config entry.

The host SSH directory and config are restricted to your account: permissions 700/600 on Linux/macOS, and protected current-user-only ACLs on Windows. The directory is protected before temporary files are created; existing access grants to other accounts are removed.

### Setup properties and API diagnostics

All API URLs below refer to the **board's** `127.0.0.1:8800`, not the host computer. Keep response status and body separate; an empty body must remain empty when parsing curl's appended status.

The board-local API exposes these setup markers:

| Key | When setup writes `done` |
| --- | --- |
| `setup-board-name` | After completing the hostname step, including keeping its value. |
| `setup-keyboard-name` | After completing the keyboard step, including keeping its value. |
| `setup-network` | After a successful Wi-Fi connection initiated by setup. |
| `setup-credentials` | After successfully setting a password, or choosing to keep an existing one. |

These flags track setup progress; they are not saved copies of the original settings.

| Operation | Expected behavior |
| --- | --- |
| `GET /v1/properties` | JSON key list; `{"keys":null}` is valid when no properties exist. |
| `GET /v1/properties/{key}` | HTTP 200 with plain text `done` for completed setup markers; HTTP 404 may have an empty body. |
| `PUT /v1/properties/{key}` | Setup sends the raw body `done`. |
| `DELETE /v1/properties/{key}` | Reset accepts HTTP 204 or 404; other statuses or transport failures stop it. |

Hostname and keyboard steps are marked complete even when their values are kept. A skipped Wi-Fi step gets no new completion flag; an existing connection that setup does not change also gets no new flag. The credentials marker is written after a successful password change or when retaining an existing password. The absence of `setup-network` alone does not establish whether Wi-Fi is connected.

For board-local Wi-Fi and setup-marker diagnostics:

```bash
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status
nmcli -f GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY device show wlan0
curl --silent --show-error --connect-timeout 5 --max-time 30 \
  --write-out '\nHTTP %{http_code}\n' http://127.0.0.1:8800/v1/properties/setup-network
```

The Wi-Fi device should be connected, and the property should return plain text `done` with HTTP 200. Use the Wi-Fi device name from `nmcli device status` if it differs from `wlan0`. A completion marker describes setup progress, not external network reachability.

### Reset mutation order

Interactive reset collects choices and requires the exact `RESET` confirmation before authentication or mutation. The unattended worker requires that token in the request before preflight. Privileged operations authenticate before configuration.

The mutation order is keyboard, hostname, the four setup flags, optional service reset, then selected Wi-Fi profiles last. This order avoids removing an active connection before the preceding operations finish. Service reset masks SSH/Avahi, disables/stops Avahi, then disables/stops SSH. Clearing flags does not restore a factory password or expire the current password; SSH keys and host config remain preserved.

The setup script did not record image defaults, so reset does not guess them. The installed App CLI daemon must support `DELETE /v1/properties/{key}`. Earlier changes are not rolled back after a later failure.

### Image compatibility observations

App Lab's bare `sudo arduino-passwd` call failed on a verified image because sudo's search path omitted `/usr/local/bin`. This tool uses the full helper path. Expiring the account does not fix command lookup.

Debconf frontend fallbacks during `dpkg-reconfigure openssh-server` occurred in a successful hardware run; exit status and postconditions determine success. Password-aging dates use the board's clock, which lagged behind the host session date in the verified first-use run. These observations are historical evidence, not guarantees for other images.

## Regression and validation practices

### PowerShell transport and native errors

PowerShell 5.1's .NET Framework creates the redirected stdin writer from the console input encoding. A UTF-8 encoding with a preamble can insert a BOM before bytes copied to `BaseStream`, corrupting both request headers and public keys. A test passing under another console encoding does not exercise that condition. The host harness deliberately sets BOM-producing `[Text.Encoding]::UTF8`, checks the received request/public key, and restores the console encoding in `finally`.

The launcher uses BOM-free `StandardInputEncoding` when available; otherwise it temporarily switches console input encoding around `Process.Start()` and restores it immediately. Preserve this handling when changing request or SSH-key transport. Run the Windows host suites sequentially because the test harness changes the shared console input encoding.

PowerShell 5.1 can turn native stderr into a terminating error under `$ErrorActionPreference = 'Stop'`. Public-key validation temporarily uses `Continue` around `ssh-keygen`, restores the previous preference in `finally`, and then checks `$LASTEXITCODE` to produce its own diagnostic. Keep these changes local; do not weaken error handling for the entire launcher.

### Shared board operations and privileged stdin

When modifying `board-common.sh`, trace setup, reset, and request-worker callers as well as their mocks. A function called in a Bash conditional can run with `errexit` disabled, so reads and commands that must stop the operation need explicit failure checks.

Test Network Mode commands with cached sudo credentials and NOPASSWD. `sudo -k -S` forces fresh authentication when a password is required, while the privileged command's initial `exec </dev/null` prevents password inheritance even when sudo does not consume stdin. Run the actual `sh -c` command with disposable executable service mocks; exported Bash functions are not a reliable substitute across shell boundaries. Check the service mutation order as well as the absence of leaked input.

Cover secret cleanup when services are already enabled, not only the branch that enables them. Shared keyboard validation must reject the same inputs in both wizards and the worker. CLI configuration checks must accept pretty and compact JSON while still rejecting missing/unwritable directories. Reset's mutation warning is installed after successful `RESET` confirmation, so invalid input or EOF before confirmation does not claim that settings changed.

### Upload results and measurements

Batching upload and cleanup reduces those ADB calls from ten to three: one push, one hash query, and one cleanup command. Validate the complete hash/path result set, including missing, extra, duplicate, wrong-path, and malformed entries, before launching the worker. Upload failures, worker exit codes, completed/skipped actions, and cleanup warnings remain part of the regression coverage.

Measure the same successful mocked scenario before and after transport changes and report the call counts. Individual mock timings include host startup and scheduling noise; fewer calls do not guarantee that every sample is faster. Label them as mocked measurements rather than board performance evidence.

### Documentation changes

Before reorganizing a guide, capture its existing examples and contract tables. After moving content, compare those examples and tables with the originals, check local links and heading anchors, and replace references such as "above" or implicit session variables with complete instructions. Code fences can be parsed without running their ADB, SSH, or installation commands: use PowerShell's parser, `bash -n`, and JSON parsing as appropriate. Documentation-only checks do not require rerunning board operations or the full mocked runtime suites.

Keep detailed material in the guide identified by the [documentation map](../AGENTS.md#documentation-map-and-policy), and keep the README focused on the immediate launcher use cases. Preserve pre-existing working-tree edits and supplied handoffs. Do not turn speculative findings or cosmetic cleanups into confirmed bug or hardware claims.

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

Run these two commands sequentially; both harness runs temporarily change shared console input encoding. Collect the exit code and final result before starting the next suite.

The tests additionally check literal unattended inputs, exact byte limits and oversized UTF-8 requests, validation before configuration, secret-free command arguments/results, partial failures, sudo preflight, and reset ordering. Host tests check device selection, paths containing spaces, empty request paths, capitalized PowerShell operations, uploaded hashes, timeouts versus interruptions, malformed results, cleanup failures, and exit codes. SSH tests generate a disposable key pair and use temporary host/board homes to check key validation, resolved SSH aliases, repeated updates, existing config, key restrictions, permissions, and failure preservation. They use fake ADB and never access hardware or modify your real SSH config.

`-P SCRIPTDIR` lets ShellCheck resolve shared helpers relative to each script. `bash -n` checks one script per invocation; additional filenames are script arguments. The loop checks all shell files.

On Windows, run Bash suites from a disposable repository copy inside the WSL Linux filesystem, not `/mnt/c`, to verify POSIX permissions. Use LF-only driver scripts. PowerShell does not expand wildcards for native commands; when running the Windows ShellCheck executable, pass an explicit file list:

```powershell
$shellFiles = @(Get-ChildItem *.sh, board/*.sh, host/*.sh, tests/*.sh | Resolve-Path -Relative)
shellcheck -P SCRIPTDIR @shellFiles
```

All test keys, SSH directories, request files, and command fixtures must be disposable. Never use the real user SSH directory or config.

### Windows/WSL check recipe

Run the following from the repository root in PowerShell. Replace `Debian` with an installed WSL distribution. It uses the Windows ShellCheck executable, then copies the repository into a disposable Linux directory for Bash syntax checks and all four mocked Bash suites. The temporary driver is written as LF-only UTF-8 without a BOM; `--exec /bin/bash` avoids dependence on the WSL user's default shell.

```powershell
$shellFiles = @(Get-ChildItem *.sh, board/*.sh, host/*.sh, tests/*.sh | Resolve-Path -Relative)
shellcheck.exe -P SCRIPTDIR @shellFiles
if ($LASTEXITCODE -ne 0) { throw 'ShellCheck failed.' }

$wslDistribution = 'Debian'
$checkScript = Join-Path ([IO.Path]::GetTempPath()) ('board-check-' + [guid]::NewGuid().ToString('N') + '.sh')
$driver = @'
#!/usr/bin/env bash
set -eu
source_repo=$1
check_repo=$(mktemp -d /tmp/arduino-board-checks.XXXXXXXX)
trap 'rm -rf -- "$check_repo"' EXIT
cp -a "$source_repo/." "$check_repo/"
cd "$check_repo"
for script in *.sh board/*.sh host/*.sh tests/*.sh; do
  bash -n "$script"
done
bash tests/test-reset-arduino-board.sh
bash tests/test-board-scripts.sh
bash tests/test-board-request.sh
bash tests/test-board-host.sh
'@
[IO.File]::WriteAllText($checkScript, $driver.Replace("`r", ''), [Text.UTF8Encoding]::new($false))
try {
    $sourceRepoLinux = (& wsl.exe -d $wslDistribution --exec wslpath -u ((Get-Location).Path)).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve repository path.' }
    $checkScriptLinux = (& wsl.exe -d $wslDistribution --exec wslpath -u $checkScript).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve driver path.' }
    & wsl.exe -d $wslDistribution --exec /bin/bash $checkScriptLinux $sourceRepoLinux
    if ($LASTEXITCODE -ne 0) { throw 'WSL Bash checks failed.' }
} finally {
    Remove-Item -LiteralPath $checkScript
}
```

After it passes, run both Windows host-suite commands above, one at a time. For documentation-only edits, parse the relevant examples and check links/anchors plus `git diff --check`; execute this recipe when validating script changes or the recipe itself. This recipe and the host harnesses use mocks and disposable keys, not connected boards or real user SSH configuration.

## Verification evidence

Full first-use provisioning passed on an UNO Q with App CLI/daemon `0.14.1` on November 23, 2026. The setup script at the recorded revision rejected unsafe/mismatched passwords, set a generated Linux password, created SSH host keys, enabled SSH/Avahi, and passed fresh sudo and loopback SSH authentication. Wi-Fi was skipped in that earlier run, so `setup-network` remained absent then. See the [verification record](verification.md) for exact conditions and results.

The Windows launcher later passed a real unattended setup preserving all settings under PowerShell 5.1, and rejected an unconfirmed reset under PowerShell 7. Both runs returned the expected JSON and exit codes, removed uploaded files, and preserved hostname, keyboard configuration, password-aging metadata, saved network profiles, setup markers, and service states. The board was already provisioned, with Wi-Fi configured before these checks. Native Debian mocked launcher tests passed; native Linux/macOS USB end-to-end checks and unattended Wi-Fi/password/reset mutations remain unverified.

Earlier checks that preserved board settings passed over ADB on these boards:

| Board | Model | App CLI / daemon |
| --- | --- | --- |
| `mnx-21q-mino` | VENTUNO Q | 0.14.1 |
| `mnx-unoq-mufi` | UNO Q | 0.13.0 |

Checked required tools/API access, syntax, the hardware-free tests, interactive cancellation, and SSH rejection (simulated SSH environment in an ADB PTY). A uniquely named temporary API property was created, read, deleted through the reset helper, and deleted again to verify absent-key handling.

Before/after checks confirmed unchanged setup flags, Wi-Fi profile UUIDs/types, hostname, keyboard, password-aging metadata, and SSH/Avahi enabled/active states. Temporary properties and test files were removed. Actual Wi-Fi deletion, service shutdown, and hostname/keyboard changes were deliberately not exercised.
