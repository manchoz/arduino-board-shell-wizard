# Arduino board setup / setup reset

Run these scripts **on an official Arduino Uno Q or Ventuno Q Linux image**, not on your PC.

```bash
bash setup-arduino-board.sh
bash reset-arduino-board.sh
```

## Setup reset

Use a local board console or a USB/ADB terminal. SSH sessions are rejected because resetting network access can disconnect you. Close App Lab during the reset, then reconnect/reopen it afterward.

The reset script:

- Clears only `setup-board-name`, `setup-keyboard-name`, `setup-network`, and `setup-credentials` through the local App CLI API. Already-absent flags are accepted.
- Offers a replacement hostname and keyboard layout; blank keeps the current value. The setup script never recorded the original image defaults, so the reset does not guess them.
- Optionally masks/disables/stops SSH and Bonjour/Avahi, following Arduino's Network Mode reset. Answer **yes** to undo Network Mode setup.
- Optionally deletes **all** saved NetworkManager Wi-Fi profiles and their stored passwords, including the active profile. Ethernet/VPN profiles are left alone. Answer **yes** to forget Wi-Fi setup.
- Requires the exact confirmation `RESET` before applying changes.

Apps, user files, installed software, SSH keys, and the current Linux password are preserved. This is **not a factory restore**, and it does not reset microcontroller firmware.

Clearing the credentials flag does not expire or restore the Linux password. App Lab may still detect that the password is already set. To change it during setup, run `setup-arduino-board.sh` and accept its password-change prompt. Keeping the password avoids lockout and an insecure shared default password.

### Password helper compatibility

The setup script calls `sudo /usr/local/bin/arduino-passwd` explicitly, so it does not require `/usr/local/bin` in sudo's `secure_path`. It also queries `chage` in the C locale because it parses English field names. Neither script modifies sudoers or expires the account.

New passwords must have at least eight characters, must not contain `arduino` (case-insensitive) or backslashes, and must not start/end with whitespace. The installed helper uses bare `read`, which can alter backslashes and edge whitespace; setup rejects those passwords rather than silently changing them.

Setup verifies the device-tree identity before making changes. Its Network Mode prompt accepts blank/`y`/`yes` as approval and `n`/`no` as refusal; invalid input or a failed read stops setup. All setup API requests have a five-second connection timeout and a thirty-second total timeout.

On `mufi`, App Lab's bare `sudo arduino-passwd` call failed because sudo's search path omitted `/usr/local/bin`. This is a separate installed App Lab/CLI issue, not a consequence of resetting setup flags. Use the setup script to change the password without changing sudoers. Expiring the account alone does not fix command lookup; if it was already expired, use interactive `passwd` over USB/ADB to recover.

If a command fails, the reset stops; earlier changes are not rolled back. Correct the error and rerun. Deleting Wi-Fi profiles cannot recover their saved passwords; have them available before confirming. The installed App CLI daemon must support `DELETE /v1/properties/{key}`.

## Hardware-free checks

```bash
shellcheck setup-arduino-board.sh reset-arduino-board.sh test-reset-arduino-board.sh test-board-scripts.sh
bash -n setup-arduino-board.sh reset-arduino-board.sh test-reset-arduino-board.sh test-board-scripts.sh
bash test-reset-arduino-board.sh
bash test-board-scripts.sh
```

These check Wi-Fi profile selection, property-delete responses/errors, supported-board checks, password rejection/handoff, Network Mode confirmation (including invalid input/EOF), non-interactive rejection, and reset cancellation/confirmed mutation order. The control-flow tests use disposable script copies with device-tree fixtures and the TTY check bypassed; console rejection is checked against the original scripts. Input and board commands are mocked. They do not change board settings or make real HTTP requests.

## Board smoke-test results

Non-destructive checks passed over ADB on both boards:

| Board | Model | App CLI / daemon |
| --- | --- | --- |
| `mnx-21q-mino` | VENTUNO Q | 0.14.1 |
| `mnx-unoq-mufi` | UNO Q | 0.13.0 |

Checked required tools/API access, syntax, the hardware-free tests, interactive cancellation, and SSH rejection (simulated SSH environment in an ADB PTY). A uniquely named temporary API property was created, read, deleted through the reset helper, and deleted again to verify absent-key handling.

Before/after checks confirmed unchanged setup flags, Wi-Fi profile UUIDs/types, hostname, keyboard, password-aging metadata, and SSH/Avahi enabled/active states. Temporary properties and test files were removed. Actual Wi-Fi deletion, service shutdown, and hostname/keyboard changes were deliberately not exercised.
