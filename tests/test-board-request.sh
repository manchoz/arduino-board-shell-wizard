#!/usr/bin/env bash
# Test the real unattended worker with harmless board command mocks.
# shellcheck disable=SC2016 # Test passwords deliberately contain literal dollar signs.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work
mkdir "$work/device-tree"
printf 'arduino,imola\0' >"$work/device-tree/compatible"
sed "s|/proc/device-tree|$work/device-tree|g" board/board-common.sh >"$work/board-common.sh"
cp board/board-request.sh "$work/board-request.sh"
unset SSH_CONNECTION SSH_CLIENT SSH_TTY
fail() { echo "FAIL: $*" >&2; exit 1; }
record() { printf '%s\n' "$*" >>"$work/commands"; }
arduino-app-cli() {
  record "cli $*"
  [[ "$*" != "${FAIL_COMMAND:-none}" ]] || return 9
  case "$*" in
    'system network-mode status') echo disabled ;;
    'config get --format json') printf '{\n"data": "%s",\n"apps": "%s"\n}\n' "$work" "$work" ;;
  esac
}
chage() { echo "Last password change : ${PASSWORD_STATE:-Jan 01, 2026}"; }
curl() {
  record "curl $*"
  [[ "$*" != *"${FAIL_PROPERTY:-never-match}"* ]] || return 7
  [[ "$*" != *'--request DELETE'* ]] || printf 204
}
sudo() {
  record "sudo $*"
  [[ "$*" != "${FAIL_SUDO:-none}" ]] || return 5
  if [[ "$*" == *arduino-passwd* || "$*" == *' -S '* || "${1:-}" == -S ]]; then
    local value
    IFS= read -r value || return 1
    printf '%s' "$value" >"$work/password"
    touch "$work/authorized"
  elif [[ "$*" == '-n -v' ]]; then
    [[ -f "$work/authorized" ]] || return 1
  fi
}
nmcli() {
  record "nmcli $*"
  case "$*" in
    '-t -f UUID,TYPE connection show') printf '%s\n' 'wired:802-3-ethernet' 'wifi:802-11-wireless' 'vpn:vpn' ;;
    '--ask --wait 30 device wifi connect '* )
      local value
      IFS= read -r value || return 1
      printf '%s' "$value" >"$work/wifi-password" ;;
  esac
}
systemctl() { fail 'Unprivileged service change'; }
dpkg-reconfigure() { fail 'Unprivileged SSH initialization'; }
export -f record arduino-app-cli chage curl sudo nmcli systemctl dpkg-reconfigure fail
base=$'ARDUINO_BOARD_REQUEST_V1\nhostname=\nkeyboard=\nwifi=keep\nlinux_password=keep\nnetwork_mode=keep\n'
run() {
  : >"$work/commands"
  rm -f "$work/authorized"
  printf '%s' "$input" >"$work/input"
  bash "$work/board-request.sh" "${operation:-setup}" <"$work/input" >"$work/output" 2>"$work/error"
}
no_changes() { ! grep -Eq -- '--request (PUT|DELETE)|arduino-passwd|^sudo .* (systemctl|nmcli) |^cli system (keyboard |set-name )|^nmcli radio' "$work/commands" || fail 'Rejected request changed board state'; }
input=$base
run || fail 'Valid keep request failed'
grep -q '"status":"ok"' "$work/output" || fail 'Missing success result'
[[ $(wc -l <"$work/output") == 1 ]] || fail 'Result contains extra output'
! grep -q 'setup-network' "$work/commands" || fail 'Skipped Wi-Fi marker was written'

prefix="${base}current_password="
for size in 65536 65537; do
  printf -v padding '%*s' "$((size - ${#prefix} - 1))" ''
  input="$prefix${padding// /x}"$'\n'
  code=0
  run || code=$?
  if (( size == 65536 )); then
    (( code == 0 )) || fail 'Request at the byte limit was rejected'
  else
    [[ "$code" == 2 && ! -s "$work/commands" ]] || fail 'Oversized request reached board commands'
    grep -q '"stage":"validate"' "$work/output" || fail 'Oversized request was not rejected during validation'
  fi
done
utf8_locale=$(locale -a | awk 'tolower($0) ~ /utf-?8/ && !found { print; found=1 }')
[[ -n "$utf8_locale" ]] || fail 'The byte-limit test needs an installed UTF-8 locale'
for characters in 20000 40000; do
  printf -v padding '%*s' "$characters" ''
  padding="${padding// /$'\303\251'}"
  input="$prefix$padding"$'\n'
  code=0
  LC_ALL="$utf8_locale" run || code=$?
  if (( characters == 20000 )); then
    (( code == 0 )) || fail 'Valid UTF-8 request was rejected'
    [[ $(cat "$work/password") == "$padding" ]] || fail 'UTF-8 password bytes changed'
  else
    [[ "$code" == 2 && ! -s "$work/commands" ]] || fail 'UTF-8 request bypassed the byte limit'
  fi
done

for input in "$base"$'hostname=again\n' "$base"$'unexpected=1\n' "${base/network_mode=keep/network_mode=maybe}" "${base/hostname=/hostname=bad name}"; do
  if run; then fail 'Invalid request accepted'; fi
  no_changes
  grep -q '"stage":"validate"' "$work/output" || fail 'Validation stage missing'
done
input=$base
printf '%s\0' "$input" >"$work/nul-input"
if bash "$work/board-request.sh" setup <"$work/nul-input" >"$work/output" 2>"$work/error"; then fail 'NUL accepted'; fi
export PASSWORD_STATE='password must be changed'
if run; then fail 'First-use password was silently kept'; fi
no_changes
input=${base/linux_password=keep/linux_password=set}
input=${input/network_mode=keep/network_mode=enable}
input+=$'new_password=valid-$pass:";=9\n'
run || fail 'First-use provisioning failed'
[[ $(cat "$work/password") == 'valid-$pass:";=9' ]] || fail 'Linux password was altered'
! grep -Fq 'valid-$pass' "$work/commands" || fail 'Password reached command arguments'
! grep -Fq 'valid-$pass' "$work/output" "$work/error" || fail 'Password reached output'
grep -q '"credentials","network","verify"' "$work/output" || fail 'Password/network completion missing'
unset PASSWORD_STATE

input=${base/wifi=keep/wifi=connect}
input+=$'ssid=cafe $(touch SHOULD_NOT_EXIST) " \\ =\nwifi_password=  wifi\\pass-$=  \n'
run || fail 'Wi-Fi request failed'
[[ $(cat "$work/wifi-password") == '  wifi\pass-$=  ' ]] || fail 'Wi-Fi password was altered'
[[ ! -e SHOULD_NOT_EXIST ]] || fail 'Request was evaluated as shell code'
! grep -Fq 'wifi\pass' "$work/commands" "$work/output" "$work/error" || fail 'Wi-Fi password leaked'

input=${base/hostname=/hostname=test-board}
input=${input/keyboard=/keyboard=us}
export FAIL_COMMAND='system keyboard us'
if run; then fail 'Board command failure ignored'; fi
grep -q '"stage":"keyboard","completed":\["hostname"\]' "$work/output" || fail 'Partial progress missing'
! grep -q setup-credentials "$work/commands" || fail 'Execution continued after failure'
unset FAIL_COMMAND
export FAIL_PROPERTY=setup-board-name
if run; then fail 'Property failure ignored'; fi
grep -q '"stage":"hostname"' "$work/output" || fail 'Property failure stage missing'
unset FAIL_PROPERTY

operation=reset
input=$'ARDUINO_BOARD_REQUEST_V1\nhostname=\nkeyboard=\nnetwork_mode=keep\ndelete_wifi=no\nconfirm=CANCEL\n'
if run; then fail 'Reset without RESET accepted'; fi
no_changes
input=${input/confirm=CANCEL/confirm=RESET}
run || fail 'Flags-only reset failed'
[[ $(grep -c -- '--request DELETE' "$work/commands") == 4 ]] || fail 'Reset cleared wrong flags'
input=$'ARDUINO_BOARD_REQUEST_V1\nhostname=test-board\nkeyboard=us\nnetwork_mode=disable\ndelete_wifi=yes\nconfirm=RESET\ncurrent_password=valid-pass-8\n'
run || fail 'Authorized reset failed'
grep -E '^sudo |--request DELETE|^cli system (keyboard |set-name )' "$work/commands" >"$work/mutations"
[[ $(sed -n '3p' "$work/mutations") == 'cli system keyboard us' ]] || fail 'Reset keyboard order changed'
[[ $(sed -n '4p' "$work/mutations") == 'cli system set-name test-board' ]] || fail 'Reset hostname order changed'
[[ $(tail -n 1 "$work/mutations") == 'sudo -n nmcli connection delete uuid wifi' ]] || fail 'Wi-Fi deletion was not last or included another connection type'
export FAIL_SUDO='-n systemctl mask ssh.service avahi-daemon.service'
if run; then fail 'Service failure ignored'; fi
! grep -q 'connection delete' "$work/commands" || fail 'Wi-Fi deleted after service failure'
unset FAIL_SUDO
input=${input/current_password=valid-pass-8/current_password=}
if run; then fail 'Reset without sudo authorization accepted'; fi
no_changes
printf '%s\n' 'Unattended board checks passed.'
