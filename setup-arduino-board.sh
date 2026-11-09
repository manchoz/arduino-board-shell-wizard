#!/usr/bin/env bash
# Interactive App Lab-style first setup for official Arduino Uno Q / Ventuno Q images.
# Uses only the board's installed command-line tools; no external language libraries.
set -Eeuo pipefail

# Interactive shells may omit sbin directories from PATH, but Debian's
# dpkg-reconfigure lives in /usr/sbin (sudo's secure_path includes it).
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH

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
if ! curl --fail --silent --show-error --output /dev/null http://127.0.0.1:8800/v1/properties; then
  echo 'Arduino App CLI daemon API is not reachable on 127.0.0.1:8800.' >&2
  exit 1
fi

set_setup_done() {
  curl --fail --silent --show-error --output /dev/null --request PUT \
    --data-binary 'done' "http://127.0.0.1:8800/v1/properties/$1"
}

password_is_valid() {
  local password="$1" trimmed="${1#"${1%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  (( ${#trimmed} >= 8 )) && [[ "${password,,}" != *arduino* ]]
}

if password_is_valid '        ' || ! password_is_valid 'valid-pass-8' || password_is_valid 'arduino123'; then
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
  read -r -p "$prompt [Y/n] " answer
  [[ ! "$answer" =~ ^[Nn]([Oo])?$ ]]
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
if [[ -n "$board_name" ]]; then
  if [[ ! "$board_name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
    echo 'Hostname must be 1-63 letters, digits, or hyphens, and start/end with a letter or digit.' >&2
    exit 1
  fi
  normalized_name="$(printf '%s' "$board_name" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
  if [[ "$normalized_name" == 'unoq' ]]; then
    echo 'Choose a name other than unoq.' >&2
    exit 1
  fi
  "$CLI" system set-name "$board_name"
fi
set_setup_done setup-board-name

keyboard_state="$("$CLI" system keyboard)"
current_layout="$(awk -F': ' '$1 == "current layout" {print $2}' <<<"$keyboard_state")"
read -r -p "Keyboard layout code (blank to keep ${current_layout:-current}): " keyboard_layout
if [[ -n "$keyboard_layout" ]]; then
  "$CLI" system keyboard "$keyboard_layout"
fi
set_setup_done setup-keyboard-name

# App Lab offers a Wi-Fi setup step, but lets the user skip it.
if nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status | awk -F: '$2 == "wifi" && $3 == "connected" { found=1 } END { exit !found }'; then
  echo 'Wi-Fi is already connected.'
  if ask_yes_no 'Change/connect to a different Wi-Fi network?'; then
    nmcli device wifi list
    read -r -p 'Wi-Fi SSID: ' ssid
    [[ -n "$ssid" ]] || { echo 'SSID cannot be empty.' >&2; exit 1; }
    nmcli --ask device wifi connect "$ssid"
    set_setup_done setup-network
  fi
else
  if ask_yes_no 'Configure Wi-Fi now? (you can skip this, as in App Lab)'; then
    nmcli radio wifi on
    nmcli device wifi list
    read -r -p 'Wi-Fi SSID: ' ssid
    [[ -n "$ssid" ]] || { echo 'SSID cannot be empty.' >&2; exit 1; }
    # nmcli prompts for the Wi-Fi password; it is not placed in argv or this script.
    nmcli --ask device wifi connect "$ssid"
    set_setup_done setup-network
  fi
fi

# App Lab asks for a Linux password on first setup. The image marks this state in
# `chage` as "password must be changed". Permit an explicit password change too.
chage_output="$(LC_ALL=C chage -l arduino)"
last_password_change="$(awk -F: '$1 ~ /^[[:space:]]*Last password change[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' <<<"$chage_output")"
if [[ -z "$last_password_change" ]]; then
  echo 'Could not determine the arduino account password state.' >&2
  exit 1
fi
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
    IFS= read -r -s -p 'New Linux password (minimum 8 non-edge-whitespace characters; must not contain "arduino"): ' new_password
    printf '\n'
    IFS= read -r -s -p 'Confirm new Linux password: ' confirm_password
    printf '\n'
    if ! password_is_valid "$new_password"; then
      echo 'Password must contain at least 8 non-edge-whitespace characters and not contain "arduino".' >&2
    elif [[ "$new_password" != "$confirm_password" ]]; then
      echo 'Passwords do not match.' >&2
    else
      break
    fi
    unset new_password confirm_password
  done

  # Use the full helper path: sudo's secure_path may omit /usr/local/bin.
  printf '%s\n' "$new_password" | sudo /usr/local/bin/arduino-passwd
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
    network_setup='set -ex
systemctl unmask ssh.service
systemctl unmask avahi-daemon.service
dpkg-reconfigure openssh-server
systemctl enable --now avahi-daemon.service
systemctl enable --now ssh.service'
    if ! printf '%s\n' "$network_password" | sudo -S -p '' sh -c "$network_setup"; then
      unset network_password
      echo 'Failed to enable App Lab Network Mode.' >&2
      exit 1
    fi
    unset network_password
  fi
else
  echo 'App Lab Network Mode is already enabled.'
fi

printf '\n%s\n' 'Verifying App Lab prerequisites and CLI configuration...'
"$CLI" system check
config_json="$("$CLI" config get --format json)"
data_dir="$(printf '%s\n' "$config_json" | sed -n 's/^[[:space:]]*"data":[[:space:]]*"\([^"]*\)".*/\1/p')"
apps_dir="$(printf '%s\n' "$config_json" | sed -n 's/^[[:space:]]*"apps":[[:space:]]*"\([^"]*\)".*/\1/p')"
for dir in "$data_dir" "$apps_dir"; do
  if [[ -z "$dir" || ! -d "$dir" || ! -w "$dir" ]]; then
    echo "Arduino App CLI config directory is missing or not writable: ${dir:-<unset>}" >&2
    exit 1
  fi
done
printf 'Arduino App CLI data directory: %s (writable)\n' "$data_dir"
printf 'Arduino App CLI apps directory: %s (writable)\n' "$apps_dir"
printf '%s\n' "$config_json"

printf '\nNetwork mode: %s\n' "$("$CLI" system network-mode status)"
printf 'Bonjour hostname: %s.local\n' "$(hostname)"
printf 'SSH target: arduino@%s.local\n' "$(hostname)"
printf '\n%s\n' 'Board setup complete; App Lab setup-completion properties were updated.'
