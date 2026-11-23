#!/usr/bin/env bash
# Host transport tests use a fake adb; no hardware is accessed.
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077
mkdir "$work/bin" "$work/board" "$work/repo with spaces" "$work/repo with spaces/board" "$work/repo with spaces/host" "$work/another directory" "$work/board-home"
# shellcheck disable=SC2016 # Replace literal variable references only in the disposable fixture.
sed 's|configure_board_ssh "$HOME/.ssh"|configure_board_ssh "$HOST_TEST_WORK/ssh"|' "$root/board-host.sh" >"$work/repo with spaces/board-host.sh"
cp "$root"/board/*.sh "$work/repo with spaces/board/"
# shellcheck disable=SC2016 # Keep prompt defaults inside the disposable fixture too.
sed 's/\$HOME/$HOST_TEST_WORK/g' "$root/host/board-ssh.sh" >"$work/repo with spaces/host/board-ssh.sh"
export HOST_TEST_WORK="$work"
cat >"$work/bin/adb" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$HOST_TEST_WORK/log"
if [[ "${1:-}" == devices ]]; then
  printf 'List of devices attached\nSERIAL device\n'
  [[ "${HOST_CASE:-}" != multiple ]] || echo 'SECOND device'
  exit 0
fi
[[ "${1:-}" == -s && "${2:-}" == SERIAL ]] || exit 77
shift 2
case "$1" in
  get-state) echo device ;;
  push)
    [[ "${HOST_CASE:-}" != upload ]] || exit 9
    cp "$2" "$HOST_TEST_WORK/board/${3##*/}" ;;
  shell)
    shift
    case "$1" in
      tr*)
        if [[ "${HOST_CASE:-}" == unsupported ]]; then echo arduino,imola-evil; else echo arduino,imola; fi ;;
      mktemp)
        if [[ "${HOST_CASE:-}" == badtemp ]]; then echo '/tmp/untrusted;command'; else echo /tmp/arduino-board-tools.TEST123; fi ;;
      sha256sum)
        if [[ "${HOST_CASE:-}" == hash ]]; then echo broken
        elif command -v sha256sum >/dev/null; then sha256sum "$HOST_TEST_WORK/board/${2##*/}"
        else shasum -a 256 "$HOST_TEST_WORK/board/${2##*/}"; fi ;;
      hostname) if [[ "${HOST_CASE:-}" == badhostname ]]; then echo 'bad name'; else echo test-board; fi ;;
      arduino-app-cli) if [[ "${HOST_CASE:-}" == sshdisabled ]]; then echo disabled; else echo enabled; fi ;;
      -T)
        if [[ "${3:-}" == -c ]]; then
          cat >"$HOST_TEST_WORK/public-received"
          [[ "${HOST_CASE:-}" != sshkeyfail ]] || exit 13
          source "$HOST_TEST_WORK/board/board-common.sh"
          id() { if [[ "$1" == -un ]]; then echo arduino; else command id "$@"; fi; }
          getent() { printf 'arduino:x:1000:1000::%s:/bin/bash\n' "$HOST_TEST_WORK/board-home"; }
          install_ssh_key <"$HOST_TEST_WORK/public-received"
          exit $?
        fi
        cat >"$HOST_TEST_WORK/input-received"
        [[ "${HOST_CASE:-}" != timeout ]] || exec sleep 10
        [[ "${HOST_CASE:-}" != empty ]] || exit 0
        case "${HOST_CASE:-}" in
          badresult) echo '{"version":1,"operation":"setup","status":"unknown"}'; exit 0 ;;
          badarray) echo '{"version":1,"operation":"setup","status":"ok","stage":"complete","completed":"hostname","skipped":[]}'; exit 0 ;;
          badstage) echo '{"version":1,"operation":"setup","status":"ok","stage":"credentials","completed":[],"skipped":[]}'; exit 0 ;;
        esac
        if [[ "${HOST_CASE:-}" == workerfail || "${HOST_CASE:-}" == cleanup || "${HOST_CASE:-}" == interrupted ]]; then
          echo '{"version":1,"operation":"setup","status":"error","stage":"credentials","completed":["hostname"],"skipped":[]}'
          [[ "${HOST_CASE:-}" != interrupted ]] || exit 143
          exit 3
        fi
        echo '{"version":1,"operation":"setup","status":"ok","stage":"complete","completed":["hostname"],"skipped":["network"]}' ;;
      -tt) echo 'Interactive wizard'; exit 4 ;;
      rm|rmdir) [[ "${HOST_CASE:-}" != cleanup ]] ;;
      *) exit 78 ;;
    esac ;;
  *) exit 79 ;;
esac
MOCK
chmod +x "$work/bin/adb"
export PATH="$work/bin:$PATH"
printf 'ARDUINO_BOARD_REQUEST_V1\r\nhostname=\r\npassword=fixture-$;\\"\r\n' >"$work/input"
fail() { echo "FAIL: $*" >&2; exit 1; }
permissions() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
run() {
  : >"$work/log"
  (cd "$work/another directory"; bash "$work/repo with spaces/board-host.sh" "$@") >"$work/output" 2>"$work/error"
}
run setup --serial SERIAL --request-file "$work/input" || fail 'Host launch failed'
cmp "$work/input" "$work/input-received" || fail 'Request bytes changed'
! grep -q 'fixture-' "$work/log" "$work/output" "$work/error" || fail 'Request secret leaked'
[[ $(grep -c 'shell sha256sum' "$work/log") == 4 ]] || fail 'Uploaded scripts were not verified'
grep -q 'shell rmdir' "$work/log" || fail 'Cleanup missing'
code=0
run setup --serial SERIAL --request-file '' || code=$?
[[ "$code" == 2 && ! -s "$work/log" ]] || fail 'Empty request path reached ADB'
grep -q '"stage":"arguments"' "$work/output" || fail 'Empty request path did not return a validation result'
for HOST_CASE in multiple unsupported badtemp upload hash empty badresult badarray badstage timeout; do
  export HOST_CASE
  if [[ "$HOST_CASE" == multiple ]]; then
    if run setup; then fail 'Multiple devices accepted'; fi
    ! grep -q mktemp "$work/log" || fail 'Ambiguous board was written'
  else
    code=0
    run setup --serial SERIAL --request-file "$work/input" --timeout 1 || code=$?
    (( code != 0 )) || fail "$HOST_CASE was accepted"
    [[ "$HOST_CASE" != timeout || "$code" == 124 ]] || fail 'Deadline did not return timeout status'
    [[ $(wc -l <"$work/output") == 1 ]] || fail 'Failure did not produce one result'
    grep -q '"status":"error"' "$work/output" || fail 'Missing error result'
  fi
done
for HOST_CASE in workerfail cleanup interrupted; do
  export HOST_CASE
  code=0
  run setup --serial SERIAL --request-file "$work/input" || code=$?
  expected=3
  [[ "$HOST_CASE" != interrupted ]] || expected=143
  [[ "$code" == "$expected" ]] || fail 'Worker exit status was masked'
  grep -q '"completed":\["hostname"\]' "$work/output" || fail 'Worker partial result was lost'
done
unset HOST_CASE
chmod 644 "$work/input"
if run setup --serial SERIAL --request-file "$work/input"; then fail 'Public request file accepted'; fi
[[ ! -s "$work/log" ]] || fail 'Unsafe request reached ADB'
chmod 600 "$work/input"
if run setup --request-file "$work/input"; then fail 'Unattended target was inferred'; fi
[[ ! -s "$work/log" ]] || fail 'Missing serial reached ADB'
code=0
run setup || code=$?
[[ "$code" == 4 ]] || fail 'Interactive status was masked'
grep -q 'shell -tt' "$work/log" || fail 'Human launch did not request a terminal'
ssh-keygen -q -t ed25519 -N '' -f "$work/key with spaces"
(
  # shellcheck source=../host/board-ssh.sh
  source "$work/repo with spaces/host/board-ssh.sh"
  for answer in y Y yes yeS yEs yES Yes YeS YEs YES; do
    printf '%s\n%s\n\n' "$answer" "$work/key with spaces.pub" >"$work/answers"
    offer_ssh_key <"$work/answers" || fail "SSH prompt declined $answer"
    [[ "$ssh_key" == "$work/key with spaces.pub" && -z "$ssh_host" ]] || fail 'SSH prompt lost key or address'
  done
  for answer in '' n no No yess; do
    printf '%s\n' "$answer" >"$work/answers"
    if offer_ssh_key <"$work/answers"; then fail "SSH prompt accepted '$answer'"; fi
  done
  if offer_ssh_key </dev/null; then fail 'SSH prompt accepted EOF'; fi
)
mkdir "$work/ssh"
printf 'Compression yes\nPort 2222\nPubkeyAuthentication no\nHost unrelated\n    HostName keep.example\n    User someone\n' >"$work/ssh/config"
run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub" || fail 'SSH integration failed'
ssh -G -T -F "$work/ssh/config" test-board >"$work/resolved"
grep -Fxq 'hostname test-board.local' "$work/resolved" || fail 'Board SSH hostname missing'
grep -Fxq 'user arduino' "$work/resolved" || fail 'Board SSH user missing'
grep -Fxq 'port 22' "$work/resolved" || fail 'Board inherited a different SSH port'
grep -Fxq 'pubkeyauthentication true' "$work/resolved" || fail 'Board inherited disabled key authentication'
grep -Fxq "identityfile $work/key with spaces" "$work/resolved" || fail 'SSH identity path changed'
ssh -G -T -F "$work/ssh/config" unrelated >"$work/resolved"
grep -Fxq 'user someone' "$work/resolved" || fail 'Unrelated SSH user changed'
grep -Fxq 'compression yes' "$work/resolved" || fail 'Global SSH defaults changed scope'
grep -Fxq 'port 2222' "$work/resolved" || fail 'Unrelated SSH port changed'
grep -Fxq 'pubkeyauthentication false' "$work/resolved" || fail 'Unrelated key authentication changed'
[[ $(permissions "$work/ssh/config") == 600 && $(permissions "$work/board-home/.ssh/authorized_keys") == 600 ]] || fail 'SSH file permissions are unsafe'
run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub" --ssh-host 192.0.2.1 || fail 'Repeated SSH setup failed'
[[ $(grep -c '^# BEGIN arduino-board-tools test-board$' "$work/ssh/config") == 1 ]] || fail 'Duplicate SSH config block'
[[ $(grep -c '^ssh-ed25519 ' "$work/board-home/.ssh/authorized_keys") == 1 ]] || fail 'Duplicate authorized key'
grep -Fq 'HostName 192.0.2.1' "$work/ssh/config" || fail 'SSH address override missing'
! grep -Fq 'BEGIN OPENSSH PRIVATE KEY' "$work/public-received" "$work/log" || fail 'Private key reached ADB'
cp "$work/ssh/config" "$work/good-config"
for HOST_CASE in sshdisabled badhostname sshkeyfail; do
  export HOST_CASE
  if run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub"; then fail "$HOST_CASE was accepted"; fi
  cmp "$work/good-config" "$work/ssh/config" || fail 'Failed SSH integration replaced config'
  grep -q '"stage":"ssh"' "$work/output" || fail 'SSH failure stage missing'
  grep -q '"completed":\["hostname"\],"skipped":\["network"\]' "$work/output" || fail 'SSH failure lost board actions'
  [[ $(wc -l <"$work/output") == 1 ]] || fail 'SSH failure produced multiple JSON results'
done
unset HOST_CASE
printf 'Host test-board\n    User another\n' >"$work/ssh/config"
if run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub"; then fail 'Unmanaged alias was replaced'; fi
grep -Fq 'User another' "$work/ssh/config" || fail 'Unmanaged alias changed'
for content in 'NotAnSshOption yes' '# BEGIN arduino-board-tools test-board'; do
  printf '%s\n' "$content" >"$work/ssh/config"
  cp "$work/ssh/config" "$work/bad-config"
  if run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub"; then fail 'Malformed SSH config accepted'; fi
  cmp "$work/bad-config" "$work/ssh/config" || fail 'Malformed config was changed'
  ! grep -q install_ssh_key "$work/log" || fail 'Invalid config reached key installation'
done
rm "$work/ssh/config"
ln -s "$work/good-config" "$work/ssh/config"
if run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub"; then fail 'Symlinked SSH config accepted'; fi
[[ -L "$work/ssh/config" ]] || fail 'SSH config symlink was replaced'
rm "$work/ssh/config"
sed 's/$/\r/' "$work/key with spaces.pub" >"$work/crlf.pub"
run setup --serial SERIAL --request-file "$work/input" --ssh-key "$work/crlf.pub" || fail 'Fresh config or CRLF key failed'
[[ $(permissions "$work/ssh") == 700 && $(permissions "$work/ssh/config") == 600 ]] || fail 'Fresh SSH permissions unsafe'
printf 'ssh-ed25519 invalid\n' >"$work/bad.pub"
for key in '' "$work/key with spaces" "$work/bad.pub"; do
  if run setup --serial SERIAL --request-file "$work/input" --ssh-key "$key"; then fail 'Empty/private SSH key accepted'; fi
  [[ ! -s "$work/log" ]] || fail 'Invalid SSH key reached ADB'
done
if run reset --serial SERIAL --request-file "$work/input" --ssh-key "$work/key with spaces.pub"; then fail 'Reset accepted SSH installation'; fi
[[ ! -s "$work/log" ]] || fail 'Reset SSH option reached ADB'
if run setup --serial SERIAL --request-file "$work/input" --ssh-host 192.0.2.1; then fail 'SSH address accepted without key'; fi
[[ ! -s "$work/log" ]] || fail 'Missing SSH key reached ADB'
[[ -z $(find "$work/ssh" -name '*.arduino.*' -print) ]] || fail 'SSH temporary files left behind'
(
  source "$root/board/board-common.sh"
  id() { if [[ "$1" == -un ]]; then echo arduino; else command id "$@"; fi; }
  getent() { printf 'arduino:x:1000:1000::%s:/bin/bash\n' "$work/board-home"; }
  read -r type blob _ <"$work/key with spaces.pub"
  printf 'restrict %s %s retained\n' "$type" "$blob" >"$work/board-home/.ssh/authorized_keys"
  install_ssh_key <"$work/key with spaces.pub" || fail 'Existing restricted key rejected'
  [[ $(wc -l <"$work/board-home/.ssh/authorized_keys") == 1 ]] || fail 'Key restrictions were bypassed'
  if printf 'ssh-ed25519 invalid\n' | install_ssh_key; then fail 'Malformed board key accepted'; fi
  mv "$work/board-home/.ssh/authorized_keys" "$work/board-authorized"
  ln -s "$work/board-authorized" "$work/board-home/.ssh/authorized_keys"
  if install_ssh_key <"$work/key with spaces.pub"; then fail 'Symlinked authorized_keys accepted'; fi
  [[ $(wc -l <"$work/board-authorized") == 1 ]] || fail 'Symlink target changed'
  id() { echo root; }
  if install_ssh_key <"$work/key with spaces.pub"; then fail 'Key installation as root accepted'; fi
)
printf '%s\n' 'Bash host checks passed.'
