# Manual transfer and local-console use

For automatic transfer verification and cleanup, use the [host launchers](../README.md#host-launchers). This guide covers manual setup, reset, and removal of uploaded scripts. See [ADB prerequisites](adb.md) and the [interactive usage guide](usage.md) for wizard choices, Wi-Fi, and checks.

Run host commands from the **repository root**, with ADB on your terminal's `PATH`. Choose the intended board's serial from an entry listed as `device` by `adb devices -l`. All manual ADB commands after discovery must use that serial, even with one connected board.

## Setup over USB/ADB

### Windows PowerShell

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

### Linux and macOS Bash or zsh

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

Use an interactive board terminal for password entry. Upload the script before launching it; piping the script into `bash -s` does not provide the required terminal. Keep the host terminal open to reuse its serial and temporary-directory variables for a later Wi-Fi run, reset, or cleanup.

## Local board console

From a local board console, with the setup script and shared helper already copied into the current directory, run:

```bash
bash setup-arduino-board.sh
```

Keep `board-common.sh` beside the script when using manual transfer or a local console. The host launchers transfer it automatically. If the repository is on the board, run `bash board/setup-arduino-board.sh` from its root instead.

## Reset setup

Use a local board console or USB/ADB terminal. SSH sessions are rejected because resetting network access can disconnect you. Close App Lab during reset, then reconnect/reopen it afterward. See the [reset choices and precautions](usage.md#reset-setup) before proceeding.

For a reset-only run, perform the device-listing, serial-assignment, and temporary-directory-creation steps from the [setup examples](#setup-over-usbadb), then use the reset transfers below. The examples reuse `$boardSerial`/`$boardTemp` in PowerShell and `$board_serial`/`$board_temp` in Bash or zsh.

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

## Cleanup

After finishing with manually uploaded copies, remove them from the same **PowerShell** session:

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

If the board directory has already been removed, its script copies need no further cleanup. If you lost the terminal session, obtain the serial and original directory name again before cleanup. Use a directory reported by the launcher or retained from your manual transfer; creating a fresh directory does not remove older copies.
