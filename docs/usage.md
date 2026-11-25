# Interactive setup and reset guide

For the launcher commands, see the [quick start](../README.md#host-launchers). Configure your terminal using the [ADB and host prerequisites](adb.md). For local-console use or manual transfers, see the [manual guide](manual-transfer.md).

To supply setup choices through a private file, follow the [request-file templates, storage, and invocation walkthrough](unattended.md#prepare-and-use-a-private-request-file). Use that file with the host launcher directly or pass its path to the provisioning skill.

## Setup

### Setup wizard prompts

| Step | What to enter | Result |
| --- | --- | --- |
| Hostname | Blank keeps the current name; otherwise enter a new name. | Marks the hostname step complete. A new name must be 1–63 letters, digits, or hyphens and start/end with a letter or digit. Names that become `unoq` after removing hyphens and ignoring case are rejected; blank still keeps a factory `uno-q` name. |
| Keyboard | Blank keeps the current layout; otherwise enter a layout code such as `us` or `de`, using only letters, digits, underscores, or hyphens. | Marks the keyboard step complete. |
| Wi-Fi | Answer `y`/`yes` to connect, or blank/`n`/`no` to skip. | `nmcli` prompts for the SSID's password. A successful connection made by the script marks the Wi-Fi step complete. |
| Linux password | On first use, enter and confirm a new password. On later runs, answer `n`/`no` to keep it. | Sets or preserves the `arduino` account password and marks credentials complete. |
| Network Mode | If no password was changed and Network Mode is disabled, choose whether to enable it; blank means yes. | Enables SSH and Bonjour/Avahi if approved. Setting/changing the Linux password enables Network Mode automatically when it is disabled. Already enabled services are left enabled. |

**Wi-Fi and Network Mode are separate.** Wi-Fi connects the board to a wireless network. Network Mode enables SSH and Bonjour/Avahi. Enabling these services with Wi-Fi skipped does not give your PC a network route to the board.

Setup applies changes as it progresses. If a later step fails, earlier changes remain; inspect the board state before rerunning. The final completion message does not imply that a skipped Wi-Fi step was performed.

### Linux password rules

New Linux passwords must have at least eight characters, must not contain `arduino` (case-insensitive) or backslashes, and must not start/end with whitespace. These restrictions apply to the **Linux password**, not the Wi-Fi password.

The Network Mode prompt accepts blank/`y`/`yes` as approval and `n`/`no` as refusal, ignoring case. Invalid input or a failed read at that prompt stops setup.

## Add or change Wi-Fi later

Rerun setup using the [host launcher](../README.md#host-launchers). If you use manually uploaded copies, follow the [manual transfer guide](manual-transfer.md#setup-over-usbadb) and repeat the transfer if those copies were removed.

1. Leave hostname and keyboard blank.
2. Answer **yes** to `Configure Wi-Fi now?`, or to changing the network if Wi-Fi is already connected.
3. Enter the SSID and let `nmcli` prompt interactively for the Wi-Fi password. Do not put the password in a command line.
4. Answer **no** to changing the Linux password.
5. If Network Mode is already enabled, that step is skipped. If it is disabled, choose whether to enable it separately.

Verify the connection on the **board**:

```bash
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status
nmcli -f GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY device show wlan0
```

The Wi-Fi device should be connected. Use the Wi-Fi device name from `device status` if it differs from `wlan0`.

With Network Mode enabled and a reachable network address, connect from your **PC** using `ssh arduino@YOUR_HOSTNAME.local`. Use the board's IP address if `.local` lookup is unavailable. The Linux login password and the Wi-Fi password are separate credentials.

## Check setup results

Run these checks on the **board**, through its console or an interactive ADB shell:

In PowerShell, Bash, or zsh, open that shell with `adb -s YOUR_DEVICE_SERIAL shell -tt`. Replace `YOUR_DEVICE_SERIAL` with the board's serial from an entry listed as `device` by `adb devices -l`.

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

## Reset setup

Use a local board console or a USB/ADB terminal. SSH sessions are rejected because resetting network access can disconnect you. Close App Lab during the reset, then reconnect/reopen it afterward.

Use the [host launcher](../README.md#host-launchers) with the `reset` operation. For manually uploaded copies or a local board console, follow the [manual reset instructions](manual-transfer.md#reset-setup).

The reset script:

- Clears App Lab setup-completion status. Already-cleared status is accepted.
- Offers a replacement hostname and keyboard layout; blank keeps the current value.
- Optionally disables/stops SSH and Bonjour/Avahi. Answer **yes** to undo Network Mode setup.
- Optionally deletes **all** saved NetworkManager Wi-Fi profiles and their stored passwords, including the active profile. Ethernet/VPN profiles are left alone. Answer **yes** to forget Wi-Fi setup.
- Requires the exact confirmation `RESET` before applying changes.

Apps, user files, installed software, SSH keys, and the current Linux password are preserved. This is **not a factory restore**, and it does not reset microcontroller firmware.

Reset does not expire or restore the Linux password. App Lab may still detect that the password is already set. To change it during setup, rerun the setup wizard and accept its password-change prompt. Keeping the password avoids lockout and an insecure shared default password.

If a command fails, the reset stops; earlier changes are not rolled back. Correct the error and rerun. Deleting Wi-Fi profiles cannot recover their saved passwords; have them available before confirming.

## Troubleshooting and cleanup

- **Password step fails:** Keep USB/ADB access and inspect the reported error before retrying. If the account requires a password change, use interactive `passwd` from the board console or USB/ADB shell to recover.
- **Debconf frontend messages during SSH initialization:** These messages can occur during a successful setup. Check the operation's exit status, SSH service state, and whether you can log in.
- **Unexpected password-change date:** Compare `date -u` on the board with your host clock. Password-aging dates use the board's clock.
- **A later setup step fails:** Keep USB/ADB access, inspect the actual settings, and correct the failing step before rerunning.

The host launchers clean up automatically. If you uploaded scripts manually, follow the [manual cleanup instructions](manual-transfer.md#cleanup).

Removing these script copies does not undo provisioning. Keep any generated credentials in a private location outside this repository, with access restricted to their owner.

## Device selection and transport failures

Omitting the serial selects the only ready ADB device. The launcher checks that it is a supported board before continuing. Agents and [unattended runs](unattended.md) must always supply an explicit serial, even with one connected board. Supplying an empty request path is rejected before contacting ADB. Transport commands have a 120-second timeout (`--timeout SECONDS` or `-TimeoutSeconds SECONDS`); human password prompts are not timed out. If an unattended run times out or loses USB, board changes may still have occurred: inspect state before retrying. Launchers never retry configuration automatically.
