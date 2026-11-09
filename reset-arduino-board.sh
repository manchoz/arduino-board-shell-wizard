#!/usr/bin/env bash
# Reset App Lab onboarding on official Uno Q / Ventuno Q images, not the OS image.
set -Eeuo pipefail
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH

ask_yes_no() {
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

wifi_profile_uuids() {
  local uuid type
  while IFS=: read -r uuid type; do
    if [[ "$type" == '802-11-wireless' || "$type" == 'wifi' ]]; then
      printf '%s\n' "$uuid"
    fi
  done
}

clear_setup_property() {
  local status
  # An absent property is already reset; other HTTP errors must not be ignored.
  status="$(curl --silent --show-error --connect-timeout 5 --max-time 30 \
    --output /dev/null --write-out '%{http_code}' --request DELETE \
    "http://127.0.0.1:8800/v1/properties/$1")" || return
  case "$status" in
    204|404) ;;
    *) printf 'Could not reset %s (HTTP %s).\n' "$1" "$status" >&2; return 1 ;;
  esac
}

main() {
  trap 'echo "Reset stopped after an error; some settings may already have changed. Fix the error and rerun." >&2' ERR
  local cli compatible connections wifi_uuids reset_wifi=false reset_network=false
  local board_name keyboard_layout confirmation uuid property

  if [[ ! -t 0 ]]; then
    echo 'Run from an interactive board console or USB/ADB terminal.' >&2
    return 1
  fi
  if [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]]; then
    echo 'Do not reset over SSH: use a local console or USB/ADB connection.' >&2
    return 1
  fi
  if [[ ! -r /proc/device-tree/compatible ]]; then
    echo 'Cannot identify an official Uno Q / Ventuno Q board.' >&2
    return 1
  fi
  compatible="$(tr '\000' '\n' </proc/device-tree/compatible)"
  if ! grep -qxE 'arduino,(imola|monza)' <<<"$compatible"; then
    echo 'This script only supports official Uno Q / Ventuno Q boards.' >&2
    return 1
  fi
  cli="$(command -v arduino-app-cli || true)"
  [[ -n "$cli" ]] || { echo 'arduino-app-cli is missing.' >&2; return 1; }
  for command in nmcli sudo systemctl curl; do
    command -v "$command" >/dev/null || { echo "Required command not found: $command" >&2; return 1; }
  done
  curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
    --output /dev/null http://127.0.0.1:8800/v1/properties

  printf '%s\n' 'Arduino App Lab setup reset (NOT a factory restore)' \
    'Apps, files, installed software, SSH keys, and the current Linux password will be preserved.' \
    'Only the four setup flags written by setup-arduino-board.sh will be cleared.' \
    'Clearing the credentials flag does not restore first-use password state.' \
    'Use a local console or USB/ADB; Wi-Fi removal and Network Mode reset can disconnect network access.'
  printf 'Current hostname: %s\n' "$(hostname)"
  # The setup script did not record image defaults, so do not invent them.
  read -r -p 'Replacement hostname (blank to keep current): ' board_name
  if [[ -n "$board_name" && ! "$board_name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
    echo 'Hostname must be 1-63 letters, digits, or hyphens, and start/end with a letter or digit.' >&2
    return 1
  fi
  "$cli" system keyboard
  read -r -p 'Replacement keyboard layout code (blank to keep current): ' keyboard_layout
  if ask_yes_no 'Disable Network Mode (SSH + Bonjour/Avahi)?'; then
    reset_network=true
  fi
  connections="$(nmcli -t -f UUID,TYPE connection show)"
  wifi_uuids="$(wifi_profile_uuids <<<"$connections")"
  if [[ -n "$wifi_uuids" ]]; then
    nmcli -f NAME,UUID,TYPE connection show
    if ask_yes_no 'Delete ALL saved Wi-Fi profiles, including their passwords?'; then
      reset_wifi=true
    fi
  fi
  printf '\nNetwork Mode reset: %s\nDelete Wi-Fi profiles: %s\n' "$reset_network" "$reset_wifi"
  read -r -p 'Type RESET to apply the setup reset: ' confirmation
  if [[ "$confirmation" != 'RESET' ]]; then
    echo 'Cancelled; nothing changed.'
    return 0
  fi

  # Authenticate before any changes that need root or could disconnect access.
  if [[ "$reset_wifi" == true || "$reset_network" == true || -n "$board_name$keyboard_layout" ]]; then
    sudo -v
  fi
  [[ -z "$keyboard_layout" ]] || "$cli" system keyboard "$keyboard_layout"
  [[ -z "$board_name" ]] || "$cli" system set-name "$board_name"
  for property in setup-board-name setup-keyboard-name setup-network setup-credentials; do
    clear_setup_property "$property"
  done
  if [[ "$reset_network" == true ]]; then
    # Matches Arduino's DisableNetworkMode; do not remove keys or weaken SSH policy.
    sudo systemctl mask ssh.service avahi-daemon.service
    sudo systemctl disable --now avahi-daemon.service
    sudo systemctl disable --now ssh.service
  fi
  # Do this last: deleting an active Wi-Fi profile can disconnect the board.
  if [[ "$reset_wifi" == true ]]; then
    while IFS= read -r uuid; do
      sudo nmcli connection delete uuid "$uuid"
    done <<<"$wifi_uuids"
  fi
  printf '\n%s\n' 'Setup reset complete. Reconnect/reopen App Lab, or run bash setup-arduino-board.sh.' \
    'The existing Linux password still works; setup-arduino-board.sh offers to change it.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
