#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Exercise script control flow with board/input fixtures and harmless command mocks.
# shellcheck disable=SC2032 # sudo is a test function that intercepts privileged commands.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export work
mkdir "$work/device-tree"
# Substitute hardware paths and the TTY check only in disposable copies.
# Non-interactive rejection is checked against the unmodified scripts separately.
for name in setup reset; do
  sed -e "s|/proc/device-tree|$work/device-tree|g" -e 's/\[\[ ! -t 0 \]\]/false/' \
    "board/$name-arduino-board.sh" >"$work/$name.sh"
done
sed "s|/proc/device-tree|$work/device-tree|g" board/board-common.sh >"$work/board-common.sh"
mkdir "$work/privileged"
for mock_command in systemctl dpkg-reconfigure; do
  cat >"$work/privileged/$mock_command" <<'MOCK'
#!/usr/bin/env bash
record() { printf '%s\n' "$*" >>"$work/commands"; }
if IFS= builtin read -r value; then record "stdin-leak $value"; fi
record "privileged ${0##*/} $*"
MOCK
  chmod +x "$work/privileged/$mock_command"
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
    board_name)
      [[ "$scenario" != reset* ]] || value='test-board'
      [[ "$scenario" != reset-hostname ]] || value='bad name'
      [[ "$scenario" != reset-eof ]] || return 1 ;;
    keyboard_layout)
      [[ "$scenario" != reset* ]] || value='us'
      [[ "$scenario" != *-keyboard ]] || value="$TEST_KEYBOARD" ;;
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
    'system network-mode status')
      if [[ "$scenario" == password-enabled ]]; then echo enabled; else echo disabled; fi ;;
    'system check')
      [[ "$scenario" != password-enabled || ! -v network_password ]] || return 7 ;;
    'config get --format json')
      if [[ "$scenario" == compact-json ]]; then
        printf '{"data":"%s","apps":"%s"}\n' "$work" "$work"
      else
        printf '{\n"data": "%s",\n"apps": "%s"\n}\n' "$work" "$work"
      fi ;;
  esac
}
nmcli() {
  record "nmcli $*"
  if [[ "$*" == '-t -f UUID,TYPE connection show' ]]; then
    printf '%s\n' 'wired-uuid:802-3-ethernet' 'wifi-uuid:802-11-wireless' 'vpn-uuid:vpn' 'other-wifi-uuid:wifi'
  fi
}
chage() {
  if [[ "$scenario" == password* ]]; then
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
  if [[ "$*" == *' sh -c '* ]]; then
    local password fresh=false
    if [[ "$1" == -k ]]; then fresh=true; shift; fi
    [[ $# == 6 && "$1" == -S && "$2" == -p && -z "$3" && "$4" == sh && "$5" == -c ]] || fail 'Unexpected Network Mode sudo arguments'
    # Cached credentials leave stdin untouched unless -k forces authentication.
    if [[ "$fresh" == true && "${TEST_SUDO_NOPASSWD:-false}" != true ]]; then
      IFS= builtin read -r password || return 1
      [[ "$password" == valid-pass-8 ]] || fail 'Wrong password sent to sudo/helper'
      record "password $password"
    fi
    shift 3
    PATH="$work/privileged:$PATH" "$@"
    return
  fi
  if [[ "$1" == /usr/local/bin/arduino-passwd || "$1" == -S || ( "$1" == -k && "${2:-}" == -S ) ]]; then
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
# shellcheck source=../board/board-common.sh
source "$work/board-common.sh"
export TEST_SUDO_NOPASSWD
for TEST_SUDO_NOPASSWD in false true; do
  : >"$work/commands"
  enable_network_mode 'valid-pass-8' >"$work/output" 2>&1 || fail 'Network Mode privileged commands failed'
  ! grep -q '^stdin-leak ' "$work/commands" || fail 'Linux password leaked to a Network Mode command'
  if [[ "$TEST_SUDO_NOPASSWD" == false ]]; then
    grep -q '^password valid-pass-8$' "$work/commands" || fail 'Cached sudo credentials bypassed password authentication'
  fi
  grep '^privileged ' "$work/commands" >"$work/actual" || fail 'Network Mode commands did not run'
  printf '%s\n' \
    'privileged systemctl unmask ssh.service' \
    'privileged systemctl unmask avahi-daemon.service' \
    'privileged dpkg-reconfigure openssh-server' \
    'privileged systemctl enable --now avahi-daemon.service' \
    'privileged systemctl enable --now ssh.service' >"$work/expected"
  diff -u "$work/expected" "$work/actual" || fail 'Network Mode command order changed'
done
unset TEST_SUDO_NOPASSWD
scenario=setup
TEST_ANSWER=n
: >"$work/commands"
if bash ./board/setup-arduino-board.sh </dev/null >"$work/output" 2>&1; then
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
    grep -Eq '^sudo (-k )?-S ' "$work/commands" || fail 'Approval did not enable Network Mode'
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
  'sudo -n systemctl mask ssh.service avahi-daemon.service' \
  'sudo -n systemctl disable --now avahi-daemon.service' \
  'sudo -n systemctl disable --now ssh.service' \
  'sudo -n nmcli connection delete uuid wifi-uuid' \
  'sudo -n nmcli connection delete uuid other-wifi-uuid' >"$work/expected"
diff -u "$work/expected" "$work/actual" || fail 'Reset mutation sequence changed'

# Check each consistency regression independently so all failures are visible.
regression_failed=false
TEST_ANSWER=n
export TEST_KEYBOARD
for scenario in setup-keyboard reset-keyboard; do
  (
    for TEST_KEYBOARD in 'us intl' 'us;de' 'us/de'; do
      if run "${scenario%%-*}"; then fail 'Invalid wizard keyboard accepted'; fi
      grep -q 'Invalid keyboard layout code' "$work/output" || fail 'Keyboard rejection diagnostic missing'
      ! grep -Eq '^sudo |--request DELETE|^cli system keyboard ' "$work/commands" || fail 'Invalid keyboard reached mutations'
    done
  ) || regression_failed=true
done
for scenario in reset-hostname reset-eof; do
  (
    if run reset; then fail 'Invalid/failed reset input accepted'; fi
    ! grep -q 'some settings may already have changed' "$work/output" || fail 'Reset warned about mutations before confirmation'
    ! grep -Eq '^sudo |--request DELETE|^cli system (set-name|keyboard )' "$work/commands" || fail 'Reset mutated before confirmation'
  ) || regression_failed=true
done
scenario='password-enabled'
(
  TEST_BAD_PASSWORD=short
  run setup || fail 'Linux password copy remained when Network Mode was already enabled'
  grep -q '^sudo /usr/local/bin/arduino-passwd$' "$work/commands" || fail 'Password change was skipped'
  ! grep -Eq '^sudo (-k )?-S ' "$work/commands" || fail 'Already enabled Network Mode was changed'
) || regression_failed=true
scenario=compact-json
(
  TEST_ANSWER=n
  run setup || fail 'Compact CLI configuration JSON rejected'
) || regression_failed=true
[[ "$regression_failed" == false ]] || fail 'Board consistency regressions failed'
printf '%s\n' 'Board script control-flow checks passed.'
