# Hardware verification record

This record describes completed tests. It is a reference for future runs, not a promise that every image version behaves identically. Follow [README.md](../README.md) for interactive use and [AGENTS.md](../AGENTS.md) for agent procedures.

## UNO Q first-use provisioning

| Item | Recorded value |
| --- | --- |
| Host/session test date | November 23, 2026 |
| Board clock during the test | November 9, 2026, approximately 10:11–10:12 UTC |
| Board | Arduino UNO Q, ADB serial `3734093419` |
| Device-tree identity | `arduino,imola` |
| Image | Debian GNU/Linux 13 (trixie) |
| App CLI / daemon | `0.14.1` / `0.14.1` |
| Script revision | `8e0fc4e8c90e5df368246d8ace5bdb8b82ceec8c` |
| Setup script SHA-256 | `c7afd91dea56aa93cc6c704c2014d5d3a36b12d560110b6d376d09766cc6eb2b` |
| Connection | USB/ADB, forced board PTY with `shell -tt` |

The board clock was behind the host/session date. No clock correction was performed, so the password-change date reported by `chage` is November 9, 2026.

### Initial state and selected inputs

The board's hostname was `uno-q`, keyboard layout was `us`, and the `arduino` user had UID 1000. Password-aging output required the password to be changed. All four setup properties were absent, SSH/Avahi were disabled and inactive, and SSH public host keys were absent. There were loopback and Docker bridge profiles, with no saved Wi-Fi profiles.

The installed password helper used bare `read` and passed the UID 1000 user's password to `chpasswd`. Sudo allowed the full helper path without password authentication. The CLI's Docker/sudo prerequisite checks passed, and its data/apps directories were writable.

The local and uploaded setup-script hashes matched. The production script was launched unchanged. Hostname and keyboard inputs were blank, Wi-Fi was skipped, and a generated valid Linux password was entered after the rejection checks. First-use password setup automatically enabled Network Mode.

### Results

| Check | Result |
| --- | --- |
| Supported-board check | Passed on the real board. |
| Non-interactive setup | Original script rejected a non-PTY ADB invocation. |
| Password rejection | Backslashes, leading whitespace, trailing whitespace, and mismatched confirmation were rejected. After each rejection the password still required changing, the credentials flag was absent, and Network Mode remained disabled. |
| Password handoff | The real image helper set the generated password; setup completed with exit status 0. |
| Password-aging state | Password no longer required changing; password expiry and inactivity were `never`. |
| Fresh sudo authentication | Generated password supplied through stdin to `sudo -k -S -p '' /usr/bin/id -u`; returned `0`. |
| SSH initialization | RSA, ECDSA, and ED25519 public host-key files were created by OpenSSH reconfiguration. |
| Network Mode | CLI reported `enabled`; SSH and Avahi were both `enabled` and `active`. TCP port 22 was listening. |
| SSH password authentication | Loopback SSH with public-key authentication disabled returned user ID `1000`. |
| Setup markers | Hostname, keyboard, and credentials GET requests returned HTTP 200 with raw `done`. Wi-Fi marker remained HTTP 404 with an empty body. |
| Preserved settings | Hostname, full keyboard configuration, and saved connection UUIDs/types matched the initial snapshot. |
| CLI prerequisites and directories | Docker/sudo checks passed after provisioning; data/apps directories remained writable. |
| Cleanup and credentials | Board script copies and temporary SSH known-hosts file were removed. The host test driver was removed. The password was retained outside the repository under an ACL restricted to its owner; the saved report was checked for password leakage. |

The new Network Mode confirmation function was also exercised separately on the board with real Bash `read`: blank/`y`/`yes` approved, `n`/`no` declined, mixed case worked, and invalid input/end of input stopped the function. This did not change services. The full first-use setup followed the automatic-enable branch, so it did not display that confirmation prompt.

During SSH initialization, debconf reported unavailable Dialog, Readline, and Teletype frontends before falling back to Noninteractive. OpenSSH still generated its keys, setup returned success, and the service/authentication checks passed.

### Limits

Actual Wi-Fi connection, saved Wi-Fi deletion, external SSH access, Bonjour discovery from another computer, and hardware reset/service shutdown were not tested in this run. The later Wi-Fi procedure in the README follows the setup script's existing flow; it is not a completed Wi-Fi smoke test. New hostname and keyboard values were not applied. The board was left provisioned.

Provisioning was driven from a Windows host. Native Linux/macOS USB/ADB host workflows are documented in the README but were not exercised end to end in this hardware run.

## Host launchers and unattended requests

These checks ran on November 23, 2026, after the host launchers and shared board operations were added. The working tree was uncommitted, based on revision `8e0fc4e8c90e5df368246d8ace5bdb8b82ceec8c`. This run does not repeat the first-use password test above.

| Item | Recorded value |
| --- | --- |
| Host | Windows, Windows PowerShell 5.1 and PowerShell 7 |
| Board | Arduino UNO Q, ADB serial `3734093419`, identity `arduino,imola` |
| Image / board Bash | Debian 13.7 / Bash `5.2.37` |
| App CLI / daemon | `0.14.1` / `0.14.1` |
| Initial clocks | Host November 23, 2026, 13:52 CET; board November 23, 2026, 12:52 UTC |
| Initial settings | Hostname `mnx-unoq-ebba`, keyboard `it`, UID 1000 user `arduino` |
| Initial password state | Last changed November 23, 2026; password expiry and inactivity `never` |
| Initial networking | Network Mode enabled; SSH/Avahi enabled and active; one Wi-Fi profile, a bridge, and a loopback profile |
| Initial setup markers | All four returned raw `done` with HTTP 200 |

The board's settings had changed since the earlier first-use test. A fresh snapshot was used, and no earlier credentials were reused. Host request files and reports were written outside the repository in a directory restricted to the current account before any files were created inside it.

### Tested file hashes

The launcher verified every uploaded board file against its local SHA-256 hash. These hashes identify the tested working-tree files:

| File | SHA-256 |
| --- | --- |
| `board-host.ps1` | `89fd2749009648d8f1ba6cd550ff42e2f915ad88c48abc901eff8118ed8e08bc` |
| `board-host.sh` | `5ee78190ddfb2e53efc92deac38004ac518284eec45bf698f3ea024004dd7b94` |
| `board-common.sh` | `3c410c1c7c9a216efaa9943b2b0a9c0a93cd5c62bf5c1c8a6b40a2bb09dcdce5` |
| `board-request.sh` | `ff41f0ae8a4b74a67984d6ed31498a7383818de88ccf3985586d5aec291e1e32` |
| `setup-arduino-board.sh` | `7072e6dcc7c2f2f50473d56bf6e7b6231c230043c47d7602d08f7c91e4d254b8` |
| `reset-arduino-board.sh` | `d213fdc3587b2e7ca3bcd5beb5885836b3127822651582a56d27b96f66dc9187` |

### Results

| Check | Result |
| --- | --- |
| Real unattended setup, PowerShell 5.1 | A request with empty hostname/keyboard, `wifi=keep`, `linux_password=keep`, and `network_mode=keep` returned exit 0 and JSON status `ok`, stage `complete`, completed `["verify"]`, and all five setting steps skipped. |
| Real reset rejection, PowerShell 7 | A reset request with empty hostname/keyboard, `network_mode=keep`, `delete_wifi=no`, and `confirm=CANCEL` returned exit 2 and JSON status `error`, stage `validate`, with empty completed/skipped arrays. No configuration was attempted. |
| Preserved state | Snapshots after each launch matched the initial hostname, complete keyboard configuration, password-aging output, connection UUIDs/types, setup-property values/statuses, and Network Mode/service states. Setup rewrote already-completed hostname/keyboard/credentials markers to the same values. |
| Cleanup | No `arduino-board-tools.*` directories existed before or after either launch. Uploaded script copies were removed. |
| CLI prerequisites | Real board Docker and sudo-rule checks passed. |
| Native Linux mocks | All four Bash suites and per-file syntax checks passed under Debian through WSL. These used fake ADB, not WSL USB access. |
| Windows mocks | The unchanged production launcher passed the complete fake-ADB suite under PowerShell 5.1 and 7. Coverage included an early stdin rejection, invalid JSON shape/status, unsafe request ACLs, missing explicit serial, upload/hash failures, timeout, partial results, cleanup failure, and human terminal selection/exit status. |
| Static/documentation checks | ShellCheck `0.11.0`, PowerShell parser checks, documentation example syntax, local links, Markdown fences, and `git diff --check` passed. |

### Limits

No password was changed, no Wi-Fi connection was attempted, no saved profile was deleted, and no service was shut down in this run. Unattended first-use provisioning, Wi-Fi connection, and confirmed reset mutations are covered by mocks but remain unverified on hardware. The historical first-use result above applies to the earlier interactive script revision.

Native Linux/macOS USB/ADB end-to-end launches, macOS's supplied Bash 3.2 runtime, external SSH access, and Bonjour discovery were not tested here. The Bash launcher was checked with native Debian Bash; macOS compatibility is an implementation target, not a completed macOS hardware test.

## Review fixes

The four review findings were fixed and checked locally on November 23, 2026. These results identify the later files; the hardware results above apply to their recorded hashes. The follow-up used board/ADB mocks and made no board-setting changes.

| Regression | Completed result |
| --- | --- |
| Empty request path | Bash and PowerShell 5.1/7 returned exit 2 with a JSON `arguments` error before any ADB call. |
| Capitalized PowerShell operations | `Setup` and `Reset` completed mocked unattended launches with lowercase operation results under 5.1/7. A human `Reset` launch selected `reset-arduino-board.sh`. |
| Byte limit | A 65,536-byte request succeeded; 65,537 bytes were rejected at validation before board commands. Under an installed UTF-8 locale, a request containing 40,000 two-byte characters was rejected, while 20,000 characters were accepted and preserved literally. |
| Timeout versus termination | The Bash launcher preserved worker exit 143 and its partial JSON result. A watchdog deadline returned 124; ordinary success and worker failures retained their exit codes. |
| Full checks | All four Bash suites and per-file syntax checks passed under native Debian through WSL. The Windows host suite passed under PowerShell 5.1 and 7. ShellCheck, PowerShell syntax, documentation examples/local links/fences, and diff checks passed. |

| File | SHA-256 after the fixes |
| --- | --- |
| `board-host.ps1` | `6413a6d51cffe046aa38bab8e7c5fb3f4b0cecd9ea3e0c9b8182aedf2036e0fa` |
| `board-host.sh` | `3aa92121fbd801ff7802da543692020bc27e38aebd29cc459e6d0da2cf57601d` |
| `board-request.sh` | `633fc47d560f26e4efe2b428c8858f3cc75e1f88da94df7342039d8fd58eb7fe` |

Native macOS/USB checks and live unattended Wi-Fi/password/confirmed-reset mutations remain unverified.

## Other completed checks

ShellCheck `0.11.0`, per-file Bash syntax checks, and both mocked test suites passed locally. Both test suites passed under Debian Bash and Git Bash. Mocked tests perform no real API requests or board-setting changes.

Earlier checks preserved board settings on `mnx-21q-mino` (Ventuno Q, CLI/daemon `0.14.1`) and `mnx-unoq-mufi` (UNO Q, CLI/daemon `0.13.0`). They checked tooling/API access, syntax, mocked tests, interactive reset cancellation, and simulated SSH-session rejection. A uniquely named temporary API property was created/read/deleted, then deleted again to verify absent-key handling; it was removed afterward.

The earlier checks confirmed unchanged setup flags, saved connection UUIDs/types, hostname, keyboard, password-aging metadata, and SSH/Avahi enabled/active state. They did not exercise actual Wi-Fi deletion, service shutdown, or hostname/keyboard changes. The full provisioning result above applies to the tested UNO Q image; full first-use provisioning on Ventuno Q remains unverified here.

## Repository layout checks

On November 23, 2026, the board tools moved into `board/` and all test suites into `tests/`. All four board files retained their pre-move SHA-256 hashes.

All four Bash suites and per-file syntax checks passed under native Debian through WSL. The Windows host suite passed against PowerShell 5.1 and 7. Host fixtures used the new layout, repository paths containing spaces, and another working directory. ShellCheck with `-P SCRIPTDIR`, PowerShell 5.1 syntax, 19 documentation examples, local links, Markdown fences, script paths, and diff checks passed.

| File | SHA-256 after the layout change |
| --- | --- |
| `board-host.ps1` | `57c5fb2e6bad1bce8a6ce1bf3e2a6aaeb250d98bc12eae416b81a3032ff9ca0c` |
| `board-host.sh` | `5da0951a8935c1f8b2ea69143e521f25c561e3144d7cc55cfb964da14b41ccf7` |

These checks used mocked ADB. Live hardware and native macOS were not exercised.

## Optional SSH key and host alias

On November 23, 2026, the host launchers gained an optional final SSH step after successful setup. It uses an existing public key, installs it for `arduino` through ADB, and manages a board-name alias in the host SSH config. Host helpers live in `host/`; the existing four-file board upload includes the installer in `board/board-common.sh`.

All four Bash suites and per-file syntax checks passed under Debian through WSL. The Bash host suite was rerun after its macOS-compatible mock hash fallback was added. The full Windows host suite passed under PowerShell 5.1 and 7. Final SSH config regressions were then exercised separately with a disposable copy of the same suite, including boards named `host` and existing managed aliases sharing the board-name prefix.

| Check | Completed result |
| --- | --- |
| Public-key validation | Disposable Ed25519 keys were validated by the real OpenSSH tools. Private-key and malformed-key inputs were rejected before ADB; CRLF public keys were accepted. Only normalized public key type/data reached mocked ADB stdin. |
| Client config | Real `ssh -G -T -F` resolved the board hostname, `arduino` user, and selected identity. Existing unrelated host settings and global compression defaults retained their effect. Fresh configs, IP overrides, repeated updates, and separate aliases passed. |
| Board installer | Bash mocks invoked the real installer against a disposable board home. Repeated runs avoided duplicate keys, existing key restrictions were preserved, malformed keys and root installation were rejected, and symlinked authorized-key files were refused. |
| Host failures | Disabled Network Mode, invalid board hostnames, key transport failure, explicit alias conflicts, and malformed configs returned SSH errors while preserving config contents. Machine results retained completed board actions and emitted one JSON object. Bash also rejected a symlinked host config. |
| Permissions and cleanup | Linux SSH directory/file permissions were 700/600. Windows fresh and replaced config files had current-user-only access rules. Repeated Windows updates passed without administrator elevation. Temporary config/public-key files were removed. |
| Static/docs | ShellCheck, Bash and PowerShell parsing, 21 documentation examples, local links, Markdown fences, and diff/whitespace checks passed. |

| File | SHA-256 after SSH integration |
| --- | --- |
| `board-host.ps1` | `0af23a4ef74a4a753661b0f4eea16197f577db99d231c115fc71e9eb111f9ef2` |
| `board-host.sh` | `b1ff06ff598e6e03c71124c38c0ba315e8cb19dcb9cdd678c10fbaafd4e6f70f` |
| `host/board-ssh.ps1` | `f243702dc682c87b1e8f71469b73d78c2806c6e74948755a0999eff8b506b82f` |
| `host/board-ssh.sh` | `275816b4483890bce19a65a083244e7ae2a7ba2377a815911c0fe8d400024a12` |
| `board/board-common.sh` | `c5c271571f4f6c94deacfc3a0b7a9fa6076ae24a7d519d1d7897c49a1a0f80ae` |
| `tests/test-board-host.ps1` | `55f2fd5675556aefed04c32f22d897836a687fde208777def54a6d36d93419c7` |
| `tests/test-board-host.sh` | `6cd1cec37e669fbaf4d50b17ad92ffe88d2b30d5eea41d98fe0c5620cb1b2397` |

These checks used temporary keys/configs and mocked ADB. No key was installed on the connected board, and the real host SSH config was not changed. Native macOS/Bash 3.2, live ADB key installation, external key authentication, and `.local` discovery remain unverified for this feature.

## SSH review fixes

The three SSH review findings were fixed and checked locally on November 23, 2026. The results below identify the updated helpers and regression suites; earlier hardware results apply to their recorded revisions.

| Regression | Completed result |
| --- | --- |
| Windows SSH directory | A disposable directory with an explicit, inheritable `Everyone: FullControl` grant became protected with only current-user, inheritable FullControl access under PowerShell 5.1 and 7. The helper protects the directory before creating temporary files. Repeated updates and fresh configs passed without elevation; config files remained restricted to the current user. |
| Conflicting SSH defaults | Real `ssh -G -T -F` resolved the board alias to port 22 with public-key authentication enabled under Debian and both Windows shells. An unrelated host retained port 2222 and disabled public-key authentication from the original config. |
| Bash confirmation | `y`, `Y`, and all eight case variations of `yes` accepted the SSH offer and retained the chosen key and blank address. Blank, negative, invalid, and EOF answers declined it. The helper used a disposable home fixture. |
| Full checks | All four Bash suites and per-file syntax checks passed under Debian through WSL. Both Windows host suites passed. ShellCheck, PowerShell parsing, 20 shell/PowerShell documentation examples plus one JSON example, local links, Markdown fences, LF shell-file checks, and tracked/untracked whitespace checks passed. |

| File | SHA-256 after SSH review fixes |
| --- | --- |
| `host/board-ssh.ps1` | `021d123b954c2a0550c10a32d7d02523e697b819c2fb930eb311dc40cc96029b` |
| `host/board-ssh.sh` | `8bfc78dbb0ecd94aefc9249ba753478d6d3db4772e95319dc51d18e31907583c` |
| `tests/test-board-host.ps1` | `cc5310af16a86fa93bec1cd4a39fa21cd8fbf3ee227a85ed905ccbd5eaef1149` |
| `tests/test-board-host.sh` | `709617f16863dce99970f7af451cd5ca3aa0388faed479cd72783630b5d4609f` |

These checks used mocked ADB and disposable keys/configs. The connected board and real host SSH config were not changed. Native macOS/Bash 3.2, live ADB key installation, external SSH key authentication, and `.local` discovery remain unverified.
