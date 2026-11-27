#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Explicit unattended interface. Input is literal key=value text, never shell code.
set -Eeuo pipefail
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH
source "$(dirname "${BASH_SOURCE[0]}")/board-common.sh"

operation="${1:-}"
stage=validate
completed=()
skipped=()
status=error

emit_result() {
  local code=$? item separator=''
  trap - EXIT
  [[ "$operation" == setup || "$operation" == reset ]] || operation=unknown
  printf '{"version":1,"operation":"%s","status":"%s","stage":"%s","completed":[' "$operation" "$status" "$stage"
  for item in "${completed[@]}"; do printf '%s"%s"' "$separator" "$item"; separator=,; done
  printf '],"skipped":['
  separator=''
  for item in "${skipped[@]}"; do printf '%s"%s"' "$separator" "$item"; separator=,; done
  printf ']}\n'
  exit "$code"
}
trap emit_result EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

reject() { echo "$1" >&2; exit 2; }
[[ $# == 1 && ( "$operation" == setup || "$operation" == reset ) ]] || reject 'Usage: board-request.sh setup|reset < private-request-file'

declare -A request=()
# Bound bytes before parsing, regardless of the caller's text locale.
if LC_ALL=C IFS= read -r -d '' -n 65537 payload; then reject 'Request must be at most 64 KiB and contain no NUL bytes.'; fi
payload="${payload%$'\n'}"
exec 3<<<"$payload"
IFS= read -r header <&3 || reject 'Missing request header.'
header="${header%$'\r'}"
[[ "$header" == ARDUINO_BOARD_REQUEST_V1 ]] || reject 'Unsupported request version.'
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ "$line" == *=* && "$line" != *$'\r'* ]] || reject 'Each request line must contain a key and literal value.'
  key="${line%%=*}"
  case "$key" in
    hostname|keyboard|wifi|ssid|wifi_password|linux_password|new_password|current_password|network_mode|delete_wifi|confirm) ;;
    *) reject 'Unknown request key.' ;;
  esac
  [[ ! -v "request[$key]" ]] || reject 'Duplicate request key.'
  request["$key"]="${line#*=}"
done <&3
exec 3<&-
unset line payload
for key in hostname keyboard network_mode; do [[ -v "request[$key]" ]] || reject 'Missing required request key.'; done
validate_hostname "${request[hostname]}" "$operation" || reject 'Invalid hostname.'
validate_keyboard "${request[keyboard]}" || reject 'Invalid keyboard layout code.'

if [[ "$operation" == setup ]]; then
  for key in wifi linux_password; do [[ -v "request[$key]" ]] || reject 'Missing required setup choice.'; done
  [[ "${request[wifi]}" == keep || "${request[wifi]}" == connect ]] || reject 'wifi must be keep or connect.'
  [[ "${request[linux_password]}" == keep || "${request[linux_password]}" == set ]] || reject 'linux_password must be keep or set.'
  [[ "${request[network_mode]}" == keep || "${request[network_mode]}" == enable ]] || reject 'network_mode must be keep or enable.'
  [[ ! -v request[delete_wifi] && ! -v request[confirm] ]] || reject 'Reset choices are not valid for setup.'
  if [[ "${request[wifi]}" == connect ]]; then
    [[ -n "${request[ssid]:-}" && -v request[wifi_password] ]] || reject 'Wi-Fi connection requires ssid and wifi_password (empty for an open network).'
  else
    [[ ! -v request[ssid] && ! -v request[wifi_password] ]] || reject 'Wi-Fi credentials require wifi=connect.'
  fi
  if [[ "${request[linux_password]}" == set ]]; then
    password_is_valid "${request[new_password]:-}" || reject 'Invalid new Linux password.'
    [[ "${request[network_mode]}" == enable ]] || reject 'Setting a Linux password requires network_mode=enable, matching initial setup.'
  else
    [[ ! -v request[new_password] ]] || reject 'new_password requires linux_password=set.'
  fi
else
  [[ "${request[confirm]:-}" == RESET ]] || reject 'Unattended reset requires confirm=RESET.'
  [[ "${request[network_mode]}" == keep || "${request[network_mode]}" == disable ]] || reject 'network_mode must be keep or disable.'
  [[ "${request[delete_wifi]:-}" == no || "${request[delete_wifi]:-}" == yes ]] || reject 'delete_wifi must be no or yes.'
  for key in wifi ssid wifi_password linux_password new_password; do
    [[ ! -v "request[$key]" ]] || reject 'Setup choices are not valid for reset.'
  done
fi

stage=preflight
verify_board >/dev/null 2>&1 || reject 'Unsupported or unidentified board.'
[[ -z "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" || "$operation" != reset ]] || reject 'Reset requires USB/ADB or a local board console.'
CLI="$(command -v arduino-app-cli)" || reject 'arduino-app-cli is missing.'
for key in nmcli chage sudo systemctl dpkg-reconfigure curl; do command -v "$key" >/dev/null || reject 'A required board tool is missing.'; done
curl --fail --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null http://127.0.0.1:8800/v1/properties 2>/dev/null || reject 'Board API is unavailable.'
network_mode="$("$CLI" system network-mode status)" || reject 'Could not determine Network Mode.'
[[ "$network_mode" == enabled || "$network_mode" == disabled ]] || reject 'Unknown Network Mode state.'
if [[ "$operation" == setup ]]; then
  state="$(password_state)" || reject 'Could not determine password state.'
  [[ "$state" != 'password must be changed' || "${request[linux_password]}" == set ]] || reject 'First-use provisioning requires linux_password=set.'
  if [[ "${request[network_mode]}" == enable && "$network_mode" != enabled && "${request[linux_password]}" == keep ]]; then
    [[ -n "${request[current_password]:-}" ]] || reject 'Enabling Network Mode requires the current Linux password.'
  fi
else
  profiles="$(nmcli -t -f UUID,TYPE connection show)" || reject 'Could not list network profiles.'
  wifi_uuids="$(wifi_profile_uuids <<<"$profiles")"
fi
if [[ -n "${request[current_password]:-}" ]]; then
  printf '%s\n' "${request[current_password]}" | sudo -k -S -p '' -v >/dev/null 2>&1 || reject 'Sudo authentication failed.'
fi
if [[ "$operation" == reset && ( "${request[network_mode]}" == disable || "${request[delete_wifi]}" == yes || -n "${request[hostname]}${request[keyboard]}" ) ]]; then
  sudo -n -v >/dev/null 2>&1 || reject 'Reset needs current_password or an existing sudo authorization.'
fi

apply() {
  stage="$1"; shift
  "$@" >/dev/null 2>&1 || { echo "Board operation failed at $stage; inspect state before retrying." >&2; exit 1; }
}
if [[ "$operation" == setup ]]; then steps=(hostname keyboard); else steps=(keyboard hostname); fi
for stage in "${steps[@]}"; do
  apply "$stage" "configure_$stage" "${request[$stage]}"
  if [[ "$operation" == setup ]]; then
    if [[ "$stage" == hostname ]]; then key=setup-board-name; else key=setup-keyboard-name; fi
    apply "$stage" set_setup_done "$key"
  fi
  if [[ -z "${request[$stage]}" ]]; then skipped+=("$stage"); else completed+=("$stage"); fi
done

if [[ "$operation" == setup ]]; then
  if [[ "${request[wifi]}" == connect ]]; then
    apply wifi nmcli radio wifi on
    apply wifi connect_wifi "${request[ssid]}" "${request[wifi_password]}"
    apply wifi set_setup_done setup-network
    completed+=(wifi)
  else skipped+=(wifi); fi
  if [[ "${request[linux_password]}" == set ]]; then
    apply credentials set_linux_password "${request[new_password]}" unattended
    completed+=(credentials)
  else skipped+=(credentials); fi
  apply credentials set_setup_done setup-credentials
  if [[ "${request[network_mode]}" == enable && "$network_mode" != enabled ]]; then
    apply network enable_network_mode "${request[new_password]:-${request[current_password]:-}}"
    completed+=(network)
  else skipped+=(network); fi
  apply verify verify_configuration
  completed+=(verify)
else
  for key in setup-board-name setup-keyboard-name setup-network setup-credentials; do apply flags clear_setup_property "$key"; done
  completed+=(flags)
  if [[ "${request[network_mode]}" == disable ]]; then
    apply network disable_network_mode; completed+=(network)
  else skipped+=(network); fi
  if [[ "${request[delete_wifi]}" == yes ]]; then
    apply wifi delete_wifi_profiles "$wifi_uuids"; completed+=(wifi)
  else skipped+=(wifi); fi
fi
unset request
status=ok
stage=complete
