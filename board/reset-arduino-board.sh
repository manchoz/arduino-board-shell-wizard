#!/usr/bin/env bash
# Reset App Lab onboarding on official Uno Q / Ventuno Q images, not the OS image.
set -Eeuo pipefail
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH
source "$(dirname "${BASH_SOURCE[0]}")/board-common.sh"

ask_yes_no() {
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

main() {
  trap 'echo "Reset stopped after an error; some settings may already have changed. Fix the error and rerun." >&2' ERR
  local cli CLI connections wifi_uuids reset_wifi=false reset_network=false
  local board_name keyboard_layout confirmation property

  if [[ ! -t 0 ]]; then
    echo 'Run from an interactive board console or USB/ADB terminal.' >&2
    return 1
  fi
  if [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]]; then
    echo 'Do not reset over SSH: use a local console or USB/ADB connection.' >&2
    return 1
  fi
  verify_board
  cli="$(command -v arduino-app-cli || true)"
  CLI="$cli"
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
  validate_hostname "$board_name" reset
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
  configure_keyboard "$keyboard_layout"
  configure_hostname "$board_name"
  for property in setup-board-name setup-keyboard-name setup-network setup-credentials; do
    clear_setup_property "$property"
  done
  if [[ "$reset_network" == true ]]; then
    # Matches Arduino's DisableNetworkMode; do not remove keys or weaken SSH policy.
    disable_network_mode
  fi
  # Do this last: deleting an active Wi-Fi profile can disconnect the board.
  if [[ "$reset_wifi" == true ]]; then
    delete_wifi_profiles "$wifi_uuids"
  fi
  printf '\n%s\n' 'Setup reset complete. Reconnect/reopen App Lab, or run bash setup-arduino-board.sh.' \
    'The existing Linux password still works; setup-arduino-board.sh offers to change it.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
