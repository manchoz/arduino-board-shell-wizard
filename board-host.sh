#!/usr/bin/env bash
# Host launcher; compatible with macOS's supplied Bash 3.2.
set -u
operation=setup
serial=''
request_file=''
machine=false
ssh_key=''
ssh_host=''
ssh_requested=false
timeout=120
board_temp=''
stage=arguments

usage() { echo 'Usage: bash board-host.sh setup|reset [--serial SERIAL] [--request-file PRIVATE_FILE] [--timeout SECONDS] [--ssh-key PUBLIC_KEY] [--ssh-host HOST_OR_IP]'; }
failure() {
  echo "$1" >&2
  if [[ "$machine" == true ]]; then
    if [[ "$stage" == ssh && -n "${result:-}" ]]; then
      result="${result/\"status\":\"ok\"/\"status\":\"error\"}"
      result="${result/\"stage\":\"complete\"/\"stage\":\"ssh\"}"
      printf '%s\n' "$result"
    else
      printf '{"version":1,"operation":"%s","status":"error","stage":"%s","completed":[],"skipped":[]}\n' "$operation" "$stage"
    fi
  fi
  exit "${2:-2}"
}
if [[ "${1:-}" == --help ]]; then usage; exit 0; fi
[[ "${1:-}" == setup || "${1:-}" == reset ]] || { usage >&2; exit 2; }
operation="$1"; shift
while (( $# )); do
  case "$1" in
    --serial|--request-file|--timeout|--ssh-key|--ssh-host)
      [[ "$1" != --request-file ]] || machine=true
      (( $# >= 2 )) || failure 'Missing argument value.'
      case "$1" in --serial) serial="$2" ;; --request-file) request_file="$2" ;; --timeout) timeout="$2" ;; --ssh-key) ssh_key="$2"; ssh_requested=true ;; --ssh-host) ssh_host="$2" ;; esac
      shift 2 ;;
    *) failure 'Unknown launcher option.' ;;
  esac
done
[[ "$timeout" =~ ^[1-9][0-9]{0,3}$ ]] || failure 'Timeout must be 1-9999 seconds.'
[[ -z "$serial" || "$serial" =~ ^[A-Za-z0-9._:-]+$ ]] || failure 'Invalid ADB serial.'
[[ -z "$ssh_host" || "$ssh_requested" == true ]] || failure '--ssh-host requires --ssh-key.'
[[ -z "$ssh_host" || "$ssh_host" =~ ^[A-Za-z0-9:][A-Za-z0-9._:-]*$ ]] || failure 'Invalid SSH hostname or IP address.'
[[ "$ssh_requested" != true || ( "$operation" == setup && -n "$ssh_key" ) ]] || failure '--ssh-key requires setup and a public-key file path.'
if [[ "$machine" == true ]]; then
  [[ -n "$request_file" ]] || failure 'A request file path is required.'
  [[ -n "$serial" ]] || failure 'Unattended runs require an explicit --serial.'
  [[ -f "$request_file" && -r "$request_file" && ! -L "$request_file" ]] || failure 'Request must be a readable regular file.'
  metadata=$(stat -c '%a %u %s' -- "$request_file" 2>/dev/null) || metadata=$(stat -f '%Lp %u %z' "$request_file" 2>/dev/null) || failure 'Could not check request permissions.'
  read -r permissions owner size <<<"$metadata"
  if [[ "$owner" != "$(id -u)" ]] || (( (8#$permissions & 077) != 0 || size > 65536 )); then
    failure 'Request must belong to you, have owner-only permissions, and be at most 64 KiB.'
  fi
fi
command -v adb >/dev/null || failure 'ADB is missing; install Platform-Tools.'
root=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || failure 'Could not locate board scripts.'
# shellcheck source=host/board-ssh.sh
source "$root/host/board-ssh.sh" || failure 'Could not load host SSH tools.'
if [[ "$ssh_requested" == true ]]; then read_ssh_key "$ssh_key" || failure 'SSH public-key validation failed.'; fi

# Bound transport commands without requiring GNU timeout on macOS.
run_adb() (
  exec 3<&0
  adb "$@" <&3 &
  child=$!
  trap 'kill "$child" 2>/dev/null; exit 130' INT
  trap 'kill "$child" 2>/dev/null; exit 143' TERM
  (
    sleep "$timeout" & sleeper=$!
    trap 'kill "$sleeper" 2>/dev/null; exit 1' TERM INT
    wait "$sleeper"
    kill "$child" 2>/dev/null
  ) >/dev/null 2>&1 & timer=$!
  wait "$child"
  code=$?
  kill "$timer" 2>/dev/null
  # Only the watchdog reaching its deadline counts as a timeout.
  if wait "$timer" 2>/dev/null; then code=124; fi
  return "$code"
)
# shellcheck disable=SC2329 # Called by the EXIT trap.
cleanup() {
  code=$?
  trap - EXIT
  if [[ -n "$board_temp" ]]; then
    if ! run_adb -s "$serial" shell "rm -f -- $board_temp/board-common.sh $board_temp/board-request.sh $board_temp/setup-arduino-board.sh $board_temp/reset-arduino-board.sh && rmdir -- $board_temp" </dev/null >/dev/null 2>&1; then
      echo "Cleanup failed; board temporary directory: $board_temp. Configuration was not rolled back." >&2
    fi
  fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stage=device
if [[ -z "$serial" ]]; then
  devices=$(run_adb devices -l </dev/null) || failure 'Could not list ADB devices.'
  count=0
  while read -r candidate state rest; do
    if [[ "$state" == device ]]; then serial="$candidate"; count=$((count + 1)); fi
  done <<<"$devices"
  (( count == 1 )) || failure 'Connect exactly one device, or select it with --serial.'
fi
[[ "$serial" =~ ^[A-Za-z0-9._:-]+$ ]] || failure 'Invalid device serial.'
state=$(run_adb -s "$serial" get-state </dev/null) || failure 'Selected device is unavailable.'
[[ "${state%$'\r'}" == device ]] || failure 'Selected device is not ready.'
identity=$(run_adb -s "$serial" shell 'tr "\000" "\n" < /proc/device-tree/compatible' </dev/null) || failure 'Could not identify the selected board.'
identity="${identity//$'\r'/}"
grep -qxE 'arduino,(imola|monza)' <<<"$identity" || failure 'Selected device is not an official Uno Q or Ventuno Q.'

stage=upload
board_temp=$(run_adb -s "$serial" shell mktemp -d /tmp/arduino-board-tools.XXXXXX </dev/null) || failure 'Could not create a board temporary directory.'
board_temp="${board_temp%$'\r'}"
[[ "$board_temp" =~ ^/tmp/arduino-board-tools\.[A-Za-z0-9]+$ ]] || { board_temp=''; failure 'Unexpected board temporary directory.'; }
local_files=() remote_files=() hashes=()
for name in board-common.sh board-request.sh setup-arduino-board.sh reset-arduino-board.sh; do
  [[ -f "$root/board/$name" ]] || failure 'A board script is missing.'
  if command -v sha256sum >/dev/null; then
    hash=$(sha256sum "$root/board/$name") || failure 'Could not hash a board script.'
  else
    hash=$(shasum -a 256 "$root/board/$name") || failure 'SHA-256 tooling is missing.'
  fi
  hash="${hash%% *}"
  local_files+=("$root/board/$name")
  remote_files+=("$board_temp/$name")
  hashes+=("$hash")
done
run_adb -s "$serial" push "${local_files[@]}" "$board_temp/" </dev/null >/dev/null || failure 'Board script upload failed.'
remote_hashes=$(run_adb -s "$serial" shell sha256sum "${remote_files[@]}" </dev/null) || failure 'Could not verify uploaded scripts.'
index=0
while IFS= read -r remote_hash; do
  (( index < ${#remote_files[@]} )) || failure 'Unexpected uploaded script hash results.'
  [[ "${remote_hash%$'\r'}" == "${hashes[$index]}  ${remote_files[$index]}" ]] || failure 'Uploaded script hash or path mismatch.'
  index=$((index + 1))
done <<<"$remote_hashes"
(( index == ${#remote_files[@]} )) || failure 'Missing uploaded script hash results.'

stage=transport
if [[ "$machine" == true ]]; then
  result=$(run_adb -s "$serial" shell -T bash "$board_temp/board-request.sh" "$operation" <"$request_file")
  code=$?
  # The worker emits this fixed JSON shape; validate it without a host JSON dependency.
  item='"(hostname|keyboard|wifi|credentials|network|flags|verify)"'
  list="\\[($item(,$item)*)?\\]"
  pattern='^\{"version":1,"operation":"'"$operation"'","status":"(ok|error)","stage":"(validate|preflight|hostname|keyboard|wifi|credentials|network|flags|verify|complete)","completed":'"$list"',"skipped":'"$list"'\}$'
  if [[ ! "$result" =~ $pattern ]] || { [[ "${BASH_REMATCH[1]}" == ok ]] && [[ "${BASH_REMATCH[2]}" != complete ]]; }; then
    (( code != 0 )) || code=1
    failure 'No valid board result was received; inspect board state before retrying.' "$code"
  fi
  if (( code != 0 )) && [[ "$result" == *'"status":"ok"'* ]]; then failure 'Transport failed after a board result; inspect state before retrying.' "$code"; fi
  if (( code == 0 )) && [[ "$result" == *'"status":"error"'* ]]; then code=1; fi
else
  # Inherit the terminal directly; never capture or pipe password prompts.
  adb -s "$serial" shell -tt bash "$board_temp/$operation-arduino-board.sh"
  code=$?
fi
if (( code == 0 )) && [[ "$operation" == setup ]]; then
  if [[ "$ssh_requested" != true && "$machine" != true && -t 0 ]] && offer_ssh_key; then ssh_requested=true; fi
  if [[ "$ssh_requested" == true ]]; then
    stage=ssh
    read_ssh_key "$ssh_key" || failure 'Board setup completed; SSH public-key validation failed.' 1
    configure_board_ssh "$HOME/.ssh" "$ssh_host" || failure 'Board setup completed; SSH integration failed. Inspect state before retrying.' 1
  fi
fi
[[ "$machine" != true ]] || printf '%s\n' "$result"
exit "$code"
