# ADB setup for Windows, macOS, and Linux

Return to the [quick start](../README.md#host-launchers) after configuring your terminal. Host commands run from the repository root.

## Reuse ADB installed by Arduino

ADB may already be available after launching **App Lab** or installing the **Arduino Q Boards** core for Uno Q / Ventuno Q in the Arduino IDE. These copies are not necessarily on your terminal's `PATH`. If `adb version` already works, you can use that installation.

The default executable locations are:

| Host | Bundled ADB executable |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Arduino15\packages\arduino\tools\adb\<version>\adb.exe` |
| macOS | `~/Library/Arduino15/packages/arduino/tools/adb/<version>/adb` |
| Linux | `~/.arduino15/packages/arduino/tools/adb/<version>/adb` |

These use the standard [Arduino15 folder locations](https://support.arduino.cc/hc/en-us/articles/360018448279-Open-the-Arduino15-folder). Replace `<version>` with the installed tool version; the examples below use `32.0.0`. If you customized Arduino CLI's `directories.data`, look under that directory's `packages/arduino/tools/adb/<version>` instead. App Lab's copy becomes available after its startup tool initialization succeeds.

On **Windows**, invoke the executable by its full path, then add its directory to the current PowerShell session's `PATH`:

```powershell
$adbDir = Join-Path $env:LOCALAPPDATA 'Arduino15\packages\arduino\tools\adb\32.0.0'
& (Join-Path $adbDir 'adb.exe') version
$env:PATH = "$adbDir;$env:PATH"
Get-Command adb -CommandType Application
adb version
```

On **Linux**, use Bash or zsh:

```sh
adb_dir="$HOME/.arduino15/packages/arduino/tools/adb/32.0.0"
"$adb_dir/adb" version
export PATH="$adb_dir:$PATH"
command -v adb
adb version
```

On **macOS**, use its Arduino15 location:

```sh
adb_dir="$HOME/Library/Arduino15/packages/arduino/tools/adb/32.0.0"
"$adb_dir/adb" version
export PATH="$adb_dir:$PATH"
command -v adb
adb version
```

The `PATH` changes apply to this terminal session and its child processes. Run the [host launchers](../README.md#host-launchers) from the same terminal so they find the selected ADB copy.

## Linux prerequisites

If you need a separate ADB installation, on Debian or Ubuntu install ADB and the USB-device rules:

```sh
sudo apt-get update
sudo apt-get install adb android-sdk-platform-tools-common
adb version
```

If you use bundled ADB, install only the USB-device rules with `sudo apt-get install android-sdk-platform-tools-common`.

The [Debian ADB package](https://packages.debian.org/trixie/adb) supplies the client. For another Linux distribution, use its ADB package or Google's Platform-Tools download. If `adb devices -l` reports `no permissions`, check your distribution's USB-device rules and group access. [Google's Ubuntu USB setup](https://developer.android.com/studio/run/device) uses the `plugdev` group; if your user is missing from that group, run `sudo usermod -aG plugdev "$(id -un)"`, then log out and back in and reconnect the board. Installing rules alone does not replace the group-membership step on Ubuntu.

## macOS prerequisites

If you need a separate ADB installation and use Homebrew, install its [Android Platform-Tools cask](https://formulae.brew.sh/cask/android-platform-tools):

```sh
brew install --cask android-platform-tools
adb version
```

Alternatively, use Google's macOS Platform-Tools download. macOS does not require an additional ADB USB driver; see [Google's USB host setup](https://developer.android.com/studio/run/device). Use Terminal with Bash or zsh for the host commands below. The setup script itself runs with the board's Bash and installed Linux tools.

## Other installation options

If you need a separate installation, [Google's SDK Platform-Tools downloads](https://developer.android.com/tools/releases/platform-tools) provide ADB for Windows, Linux, and macOS without requiring Android Studio. If you extract that download, add its `platform-tools` directory to your host's `PATH`.

## Multiple connected devices

If more than one ADB device is ready, the launcher stops and asks you to select one explicitly. List devices in either terminal:

```sh
adb devices -l
```

Replace `YOUR_DEVICE_SERIAL` with the intended board's serial from an entry listed as `device`. On **Windows**, add `-Serial`:

```powershell
.\board-host.ps1 -Operation setup -Serial YOUR_DEVICE_SERIAL
.\board-host.ps1 -Operation reset -Serial YOUR_DEVICE_SERIAL
```

On **Linux or macOS**, add `--serial`:

```sh
bash ./board-host.sh setup --serial YOUR_DEVICE_SERIAL
bash ./board-host.sh reset --serial YOUR_DEVICE_SERIAL
```

The same serial options apply when requesting the optional SSH step. After selection, the launcher uses that serial for all ADB commands.

## Optional OpenSSH client

The host needs the OpenSSH client commands `ssh` and `ssh-keygen`. On Debian/Ubuntu, install `openssh-client` if they are missing. macOS supplies them; for Windows, see Microsoft's [OpenSSH key authentication guidance](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement).
