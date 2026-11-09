#!/usr/bin/env bash
# Exercise script control flow with board/input fixtures and harmless command mocks.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export work
mkdir "$work/device-tree"
# Substitute hardware paths and the TTY check only in disposable copies.
# Non-interactive rejection is checked against the unmodified scripts separately.
for name in setup reset; do
  sed -e "s|/proc/device-tree|$work/device-tree|g" -e 's/\[\[ ! -t 0 \]\]/false/' \
    "$name-arduino-board.sh" >"$work/$name.sh"
done
printf 'Test board\0' >"$work/device-tree/model"
unset SSH_CONNECTION SSH_CLIENT SSH_TTY

fail() { echo "FAIL: $*" >&2; exit 1; }
record() { printf '%s\n' "$*" >>"$work/commands"; }
read() {
  local argument prompted=false
  for argument do
    [[ "$argument" != -p ]] || prompted=true
  done
  if [[ "$prompted" == false ]]; then
    builtin read -r "$@"
    return
  fi
  local variable="${*: -1}" value=''
  case "$variable" in
    board_name) [[ "$scenario" != reset* ]] || value='test-board' ;;
    keyboard_layout) [[ "$scenario" != reset* ]] || value='us' ;;
    confirmation) value="$TEST_CONFIRMATION" ;;
    answer)
      value=n
      if [[ "$*" == *'[Y/n]'* ]]; then
        [[ "$TEST_ANSWER" != EOF ]] || return 1
        value="$TEST_ANSWER"
      elif [[ "$scenario" == reset* ]]; then
        value=y
      fi ;;
    new_password)
      password_reads=$(( ${password_reads:-0} + 1 ))
      if (( password_reads == 1 )); then value="$TEST_BAD_PASSWORD"; else value='valid-pass-8'; fi ;;
    confirm_password)
      # The script under test assigns new_password through this mock.
      # shellcheck disable=SC2154
      value="$new_password" ;;
    network_password) value='valid-pass-8' ;;
    *) fail "Unexpected read: $*" ;;
  esac
  printf -v "$variable" '%s' "$value"
}
arduino-app-cli() {
  record "cli $*"
  case "$*" in
    version) echo 'test version' ;;
    'system keyboard') echo 'current layout: us' ;;
    'system network-mode status') echo disabled ;;
    'config get --format json') printf '{\n"data": "%s",\n"apps": "%s"\n}\n' "$work" "$work" ;;
  esac
}
nmcli() {
  record "nmcli $*"
  if [[ "$*" == '-t -f UUID,TYPE connection show' ]]; then
    printf '%s\n' 'wired-uuid:802-3-ethernet' 'wifi-uuid:802-11-wireless' 'vpn-uuid:vpn' 'other-wifi-uuid:wifi'
  fi
}
chage() {
  if [[ "$scenario" == password ]]; then
    echo 'Last password change : password must be changed'
  else
    echo 'Last password change : Jan 01, 2026'
  fi
}
curl() {
  record "curl $*"
  [[ "$*" == *'--connect-timeout 5 --max-time 30'* ]] || fail 'HTTP timeouts missing'
  [[ "$*" != *'--request DELETE'* ]] || printf 204
}
sudo() {
  record "sudo $*"
  if [[ "$1" == /usr/local/bin/arduino-passwd || "$1" == -S ]]; then
    local password
    IFS= builtin read -r password
    [[ "$password" == valid-pass-8 ]] || fail 'Wrong password sent to sudo/helper'
    record "password $password"
  fi
}
systemctl() { fail 'Unprivileged service mutation'; }
dpkg-reconfigure() { fail 'Unprivileged SSH reconfiguration'; }
export -f record read arduino-app-cli nmcli chage curl sudo systemctl dpkg-reconfigure fail
export scenario TEST_ANSWER TEST_CONFIRMATION TEST_BAD_PASSWORD

run() {
  : >"$work/commands"
  bash "$work/$1.sh" </dev/null >"$work/output" 2>&1
}
scenario=setup
TEST_ANSWER=n
: >"$work/commands"
if bash ./setup-arduino-board.sh </dev/null >"$work/output" 2>&1; then
  fail 'Non-interactive setup accepted'
fi
grep -q 'Run this script from an interactive terminal' "$work/output" || fail 'Missing setup console warning'
[[ ! -s "$work/commands" ]] || fail 'Non-interactive setup reached commands/API'
printf 'arduino,imola\0' >"$work/device-tree/compatible"
run setup || fail 'Supported Uno Q rejected'
printf 'arduino,monza\0' >"$work/device-tree/compatible"
run setup || fail 'Supported Ventuno Q rejected'
printf 'other,board\0' >"$work/device-tree/compatible"
if run setup; then fail 'Unsupported board accepted'; fi
[[ ! -s "$work/commands" ]] || fail 'Unsupported board reached commands/API'
rm "$work/device-tree/compatible"
if run setup; then fail 'Unidentified board accepted'; fi
[[ ! -s "$work/commands" ]] || fail 'Unidentified board reached commands/API'
printf 'arduino,imola\0' >"$work/device-tree/compatible"

for TEST_ANSWER in '' y YES n No maybe EOF; do
  if run setup; then
    [[ "$TEST_ANSWER" != maybe && "$TEST_ANSWER" != EOF ]] || fail 'Invalid/failed confirmation accepted'
  else
    [[ "$TEST_ANSWER" == maybe || "$TEST_ANSWER" == EOF ]] || fail 'Valid confirmation rejected'
  fi
  if [[ "$TEST_ANSWER" == '' || "$TEST_ANSWER" == y || "$TEST_ANSWER" == YES ]]; then
    grep -q '^sudo -S ' "$work/commands" || fail 'Approval did not enable Network Mode'
  elif grep -q '^sudo ' "$work/commands"; then
    fail 'Network Mode enabled without approval'
  fi
done

scenario=password
for TEST_BAD_PASSWORD in 'valid\pass-8' ' valid-pass-8' 'valid-pass-8 ' $'\tvalid-pass-8' 'arduino123' 'short'; do
  run setup || fail 'Password handoff failed'
  grep -q 'Password must contain' "$work/output" || fail 'Unsafe password was not rejected'
  [[ "$(grep -c '^sudo /usr/local/bin/arduino-passwd$' "$work/commands")" == 1 ]] || fail 'Wrong password helper invocation'
  [[ "$(grep -c '^password valid-pass-8$' "$work/commands")" == 2 ]] || fail 'Password not passed intact to helper and sudo'
done

scenario=reset
TEST_CONFIRMATION=CANCEL
run reset || fail 'Cancellation failed'
if grep -Eq '^sudo |--request DELETE|^cli system (set-name|keyboard us)' "$work/commands"; then
  fail 'Reset mutated state before confirmation'
fi
TEST_CONFIRMATION=RESET
run reset || fail 'Confirmed reset failed'
# Comparing the full mutation sequence catches non-Wi-Fi deletions and order changes.
grep -E '^sudo |--request DELETE|^cli system (set-name|keyboard us)' "$work/commands" >"$work/actual"
printf '%s\n' \
  'sudo -v' 'cli system keyboard us' 'cli system set-name test-board' \
  'curl --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null --write-out %{http_code} --request DELETE http://127.0.0.1:8800/v1/properties/setup-board-name' \
  'curl --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null --write-out %{http_code} --request DELETE http://127.0.0.1:8800/v1/properties/setup-keyboard-name' \
  'curl --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null --write-out %{http_code} --request DELETE http://127.0.0.1:8800/v1/properties/setup-network' \
  'curl --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null --write-out %{http_code} --request DELETE http://127.0.0.1:8800/v1/properties/setup-credentials' \
  'sudo systemctl mask ssh.service avahi-daemon.service' \
  'sudo systemctl disable --now avahi-daemon.service' \
  'sudo systemctl disable --now ssh.service' \
  'sudo nmcli connection delete uuid wifi-uuid' \
  'sudo nmcli connection delete uuid other-wifi-uuid' >"$work/expected"
diff -u "$work/expected" "$work/actual" || fail 'Reset mutation sequence changed'
printf '%s\n' 'Board script control-flow checks passed.'
