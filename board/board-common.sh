#!/usr/bin/env bash
# Board operations shared by the interactive wizards and the unattended worker.

verify_board() {
  local compatible
  [[ -r /proc/device-tree/compatible ]] || { echo 'Cannot identify an official Uno Q / Ventuno Q board.' >&2; return 1; }
  compatible="$(tr '\000' '\n' </proc/device-tree/compatible)"
  grep -qxE 'arduino,(imola|monza)' <<<"$compatible" || {
    echo 'This script only supports official Uno Q / Ventuno Q boards.' >&2; return 1;
  }
}

validate_hostname() {
  [[ -z "$1" ]] && return 0
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || {
    echo 'Hostname must be 1-63 letters, digits, or hyphens, and start/end with a letter or digit.' >&2; return 1;
  }
  local normalized="${1,,}"
  if [[ "${2:-setup}" == setup && "${normalized//-/}" == unoq ]]; then
    echo 'Choose a name other than unoq.' >&2; return 1
  fi
}

configure_hostname() { [[ -z "$1" ]] || "$CLI" system set-name "$1"; }
configure_keyboard() { [[ -z "$1" ]] || "$CLI" system keyboard "$1"; }

password_is_valid() {
  local password="$1" trimmed="${1#"${1%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  # shortcut: arduino-passwd uses bare read; reject altered input until the image helper preserves it.
  (( ${#password} >= 8 )) && [[ "$password" == "$trimmed" && "$password" != *\\* && "${password,,}" != *arduino* ]]
}

password_state() {
  local output state
  output="$(LC_ALL=C chage -l arduino)" || return
  state="$(awk -F: '$1 ~ /^[[:space:]]*Last password change[[:space:]]*$/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' <<<"$output")"
  [[ -n "$state" ]] || { echo 'Could not determine the arduino account password state.' >&2; return 1; }
  printf '%s\n' "$state"
}

set_linux_password() {
  if [[ "${2:-interactive}" == unattended ]]; then
    printf '%s\n' "$1" | sudo -n /usr/local/bin/arduino-passwd
  else
    printf '%s\n' "$1" | sudo /usr/local/bin/arduino-passwd
  fi
}

install_ssh_key() (
  local key key_type key_blob account_home ssh_dir authorized status
  if LC_ALL=C IFS= read -r -d '' -n 16385 key; then
    echo 'SSH public key must be at most 16 KiB and contain no NUL bytes.' >&2; return 1
  fi
  key="${key%$'\n'}"; key="${key%$'\r'}"
  [[ -n "$key" && "$key" != *$'\n'* && "$key" != *$'\r'* ]] || return 1
  read -r key_type key_blob _ <<<"$key"
  [[ "$key_type" =~ ^[A-Za-z0-9@._+-]+$ && "$key_blob" =~ ^[A-Za-z0-9+/]+={0,3}$ ]] || return 1
  printf '%s %s\n' "$key_type" "$key_blob" | ssh-keygen -l -f /dev/stdin >/dev/null 2>&1 || return 1
  [[ "$(id -un)" == arduino ]] || { echo 'SSH keys must be installed as arduino.' >&2; return 1; }
  account_home="$(getent passwd arduino | cut -d: -f6)" || return 1
  [[ "$account_home" == /* && -d "$account_home" ]] || return 1
  ssh_dir="$account_home/.ssh"; authorized="$ssh_dir/authorized_keys"
  [[ ! -L "$ssh_dir" && ! -L "$authorized" && ( ! -e "$authorized" || -f "$authorized" ) ]] || {
    echo 'SSH directory and authorized_keys must not be symlinks or special files.' >&2; return 1;
  }
  umask 077
  mkdir -p -- "$ssh_dir" || return 1
  chmod 700 "$ssh_dir" || return 1
  [[ -e "$authorized" ]] || : >"$authorized" || return 1
  chmod 600 "$authorized" || return 1
  # Preserve restrictions on an already authorized key, including entries with options.
  if awk -v type="$key_type" -v blob="$key_blob" '
    /^[[:space:]]*#/ { next }
    { for (i = 1; i < NF; i++) if ($i == type && $(i + 1) == blob) found = 1 }
    END { exit !found }
  ' "$authorized"; then return 0; else status=$?; fi
  [[ "$status" == 1 ]] || return 1
  printf '\n%s %s\n' "$key_type" "$key_blob" >>"$authorized"
)

connect_wifi() {
  if (( $# == 1 )); then
    nmcli --ask device wifi connect "$1"
  else
    # nmcli reads the password from stdin; keep literal Wi-Fi characters out of argv.
    printf '%s\n' "$2" | nmcli --ask --wait 30 device wifi connect "$1"
  fi
}

enable_network_mode() {
  local commands='set -ex
systemctl unmask ssh.service
systemctl unmask avahi-daemon.service
dpkg-reconfigure openssh-server
systemctl enable --now avahi-daemon.service
systemctl enable --now ssh.service'
  printf '%s\n' "$1" | sudo -S -p '' sh -c "$commands"
}

set_setup_done() {
  curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
    --output /dev/null --request PUT --data-binary 'done' "http://127.0.0.1:8800/v1/properties/$1"
}

clear_setup_property() {
  local status
  status="$(curl --silent --show-error --connect-timeout 5 --max-time 30 \
    --output /dev/null --write-out '%{http_code}' --request DELETE "http://127.0.0.1:8800/v1/properties/$1")" || return
  case "$status" in
    204|404) ;;
    *) printf 'Could not reset %s (HTTP %s).\n' "$1" "$status" >&2; return 1 ;;
  esac
}

wifi_profile_uuids() {
  local uuid type
  while IFS=: read -r uuid type; do
    if [[ "$type" == 802-11-wireless || "$type" == wifi ]]; then printf '%s\n' "$uuid"; fi
  done
}

disable_network_mode() {
  sudo -n systemctl mask ssh.service avahi-daemon.service || return
  sudo -n systemctl disable --now avahi-daemon.service || return
  sudo -n systemctl disable --now ssh.service
}

delete_wifi_profiles() {
  local uuid
  while IFS= read -r uuid; do
    [[ -z "$uuid" ]] || sudo -n nmcli connection delete uuid "$uuid" || return
  done <<<"$1"
}

verify_configuration() {
  local config_json data_dir apps_dir dir
  "$CLI" system check || return
  config_json="$("$CLI" config get --format json)" || return
  data_dir="$(sed -n 's/^[[:space:]]*"data":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$config_json")"
  apps_dir="$(sed -n 's/^[[:space:]]*"apps":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$config_json")"
  for dir in "$data_dir" "$apps_dir"; do
    [[ -n "$dir" && -d "$dir" && -w "$dir" ]] || {
      echo "Arduino App CLI config directory is missing or not writable: ${dir:-<unset>}" >&2; return 1;
    }
  done
  printf 'Arduino App CLI data directory: %s (writable)\n' "$data_dir"
  printf 'Arduino App CLI apps directory: %s (writable)\n%s\n' "$apps_dir" "$config_json"
}
