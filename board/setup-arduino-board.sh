#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Interactive App Lab-style first setup for official Arduino Uno Q / Ventuno Q images.
# Uses only the board's installed command-line tools; no external language libraries.
set -Eeuo pipefail

# Interactive shells may omit sbin directories from PATH, but Debian's
# dpkg-reconfigure lives in /usr/sbin (sudo's secure_path includes it).
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH
source "$(dirname "${BASH_SOURCE[0]}")/board-common.sh"

CLI="$(command -v arduino-app-cli || true)"
if [[ -z "$CLI" ]]; then
  echo 'arduino-app-cli is missing; use an official Uno Q / Ventuno Q image.' >&2
  exit 1
fi
for cmd in nmcli chage sudo systemctl dpkg-reconfigure curl; do
  command -v "$cmd" >/dev/null || { echo "Required command not found: $cmd" >&2; exit 1; }
done
if [[ ! -t 0 ]]; then
  echo 'Run this script from an interactive terminal (passwords are entered interactively).' >&2
  exit 1
fi
verify_board
if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
  --output /dev/null http://127.0.0.1:8800/v1/properties; then
  echo 'Arduino App CLI daemon API is not reachable on 127.0.0.1:8800.' >&2
  exit 1
fi

if password_is_valid '        ' || ! password_is_valid 'valid-pass-8' || password_is_valid 'arduino123' \
  || password_is_valid 'valid\pass-8' || password_is_valid ' valid-pass-8' || password_is_valid 'valid-pass-8 '; then
  echo 'Internal password validation check failed.' >&2
  exit 1
fi

ask_yes_no() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ask_yes_no_default_yes() {
  local prompt="$1" answer
  if ! read -r -p "$prompt [Y/n] " answer; then
    echo 'Could not read Network Mode confirmation; stopped.' >&2
    exit 1
  fi
  case "${answer,,}" in
    ''|y|yes) return 0 ;;
    n|no) return 1 ;;
    *) echo 'Answer y/yes, n/no, or leave blank; stopped.' >&2; exit 1 ;;
  esac
}

printf '%s\n' 'Arduino App Lab-style board setup'
if [[ -r /proc/device-tree/model ]]; then
  printf 'Board: '
  tr -d '\000' </proc/device-tree/model
  printf '\n'
fi
printf 'Current hostname: %s\n' "$(hostname)"
printf 'Arduino App CLI: %s\n\n' "$("$CLI" version 2>/dev/null | head -n 1)"

# App Lab's first step configures a hostname and keyboard layout.
read -r -p 'Board hostname (blank to keep current): ' board_name
validate_hostname "$board_name"
configure_hostname "$board_name"
set_setup_done setup-board-name

keyboard_state="$("$CLI" system keyboard)"
current_layout="$(awk -F': ' '$1 == "current layout" {print $2}' <<<"$keyboard_state")"
read -r -p "Keyboard layout code (blank to keep ${current_layout:-current}): " keyboard_layout
validate_keyboard "$keyboard_layout"
configure_keyboard "$keyboard_layout"
set_setup_done setup-keyboard-name

# App Lab offers a Wi-Fi setup step, but lets the user skip it.
if nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status | awk -F: '$2 == "wifi" && $3 == "connected" { found=1 } END { exit !found }'; then
  echo 'Wi-Fi is already connected.'
  if ask_yes_no 'Change/connect to a different Wi-Fi network?'; then
    nmcli device wifi list
    read -r -p 'Wi-Fi SSID: ' ssid
    [[ -n "$ssid" ]] || { echo 'SSID cannot be empty.' >&2; exit 1; }
    connect_wifi "$ssid"
    set_setup_done setup-network
  fi
else
  if ask_yes_no 'Configure Wi-Fi now? (you can skip this, as in App Lab)'; then
    nmcli radio wifi on
    nmcli device wifi list
    read -r -p 'Wi-Fi SSID: ' ssid
    [[ -n "$ssid" ]] || { echo 'SSID cannot be empty.' >&2; exit 1; }
    # nmcli prompts for the Wi-Fi password; it is not placed in argv or this script.
    connect_wifi "$ssid"
    set_setup_done setup-network
  fi
fi

# App Lab asks for a Linux password on first setup. The image marks this state in
# `chage` as "password must be changed". Permit an explicit password change too.
last_password_change="$(password_state)"
needs_password=false
if [[ "$last_password_change" == 'password must be changed' ]]; then
  needs_password=true
  echo 'The arduino account requires its first-use password to be set.'
elif ask_yes_no 'Set/change the arduino Linux password now?'; then
  needs_password=true
fi

network_password=''
if [[ "$needs_password" == true ]]; then
  while true; do
    IFS= read -r -s -p 'New Linux password (minimum 8 characters; no edge whitespace, backslashes, or "arduino"): ' new_password
    printf '\n'
    IFS= read -r -s -p 'Confirm new Linux password: ' confirm_password
    printf '\n'
    if ! password_is_valid "$new_password"; then
      echo 'Password must contain at least 8 characters, no edge whitespace or backslashes, and not contain "arduino".' >&2
    elif [[ "$new_password" != "$confirm_password" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
    unset new_password confirm_password
  done

  # Use the full helper path: sudo's secure_path may omit /usr/local/bin.
  set_linux_password "$new_password"
  set_setup_done setup-credentials
  network_password="$new_password"
  unset new_password confirm_password
else
  set_setup_done setup-credentials
fi

# After a successful first-use password set App Lab enables Network Mode by
# default. Network Mode means SSH + Bonjour/Avahi, not Wi-Fi itself.
network_mode="$("$CLI" system network-mode status)"
if [[ "$network_mode" != 'enabled' ]]; then
  if [[ "$needs_password" == true ]]; then
    enable_network_mode=true
  elif ask_yes_no_default_yes 'Enable App Lab Network Mode (SSH + Bonjour/Avahi)?'; then
    enable_network_mode=true
  else
    enable_network_mode=false
  fi

  if [[ "$enable_network_mode" == true ]]; then
    if [[ "$needs_password" != true ]]; then
      read -r -s -p 'Current arduino Linux password (sudo authentication): ' network_password
      printf '\n'
    fi

    # Mirrors arduino-app-cli/pkg/board.EnableNetworkMode: authenticate sudo
    # with the Linux password, unmask SSH/Avahi, reconfigure OpenSSH, then enable
    # and start both services. No SSH policy is weakened and no key is generated
    # separately; dpkg-reconfigure openssh-server handles OpenSSH initialization.
    if ! enable_network_mode "$network_password"; then
      unset network_password
      echo 'Failed to enable App Lab Network Mode.' >&2
      exit 1
    fi
    unset network_password
  fi
else
  echo 'App Lab Network Mode is already enabled.'
fi
unset network_password

printf '\n%s\n' 'Verifying App Lab prerequisites and CLI configuration...'
verify_configuration

printf '\nNetwork mode: %s\n' "$("$CLI" system network-mode status)"
printf 'Bonjour hostname: %s.local\n' "$(hostname)"
printf 'SSH target: arduino@%s.local\n' "$(hostname)"
printf '\n%s\n' 'Board setup complete; App Lab setup-completion properties were updated.'
