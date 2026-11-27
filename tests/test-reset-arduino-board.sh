#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Hardware-free checks; all HTTP requests are mocked.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source ./board/reset-arduino-board.sh

fail() { echo "FAIL: $*" >&2; exit 1; }

actual="$(wifi_profile_uuids <<'EOF'
wired-uuid:802-3-ethernet
wifi-uuid:802-11-wireless
vpn-uuid:vpn
other-wifi-uuid:wifi
EOF
)"
[[ "$actual" == $'wifi-uuid\nother-wifi-uuid' ]] || fail 'Wi-Fi selection included another connection type'
[[ -z "$(wifi_profile_uuids <<<'wired-uuid:802-3-ethernet')" ]] || fail 'No Wi-Fi should produce no UUIDs'

curl() {
  [[ "$*" == *'--request DELETE http://127.0.0.1:8800/v1/properties/setup-network' ]] || fail 'Unexpected API request'
  printf '%s' "$mock_status"
  return "$mock_exit"
}
mock_exit=0
for mock_status in 204 404; do
  clear_setup_property setup-network || fail "HTTP $mock_status should succeed"
done
for mock_status in 400 405 500 200; do
  if clear_setup_property setup-network 2>/dev/null; then
    fail "HTTP $mock_status should fail"
  fi
done
mock_status=000
mock_exit=7
if clear_setup_property setup-network 2>/dev/null; then
  fail 'A transport failure should fail'
fi

ask_yes_no 'test' <<<'yes' >/dev/null || fail 'yes should confirm'
if ask_yes_no 'test' <<<'' >/dev/null; then fail 'Blank should decline'; fi
if ask_yes_no 'test' <<<'no' >/dev/null; then fail 'no should decline'; fi

# This path must exit before checking board tools or changing anything.
if output="$(bash ./board/reset-arduino-board.sh </dev/null 2>&1)"; then
  fail 'Non-interactive execution should fail'
fi
[[ "$output" == *'Run from an interactive board console'* ]] || fail 'Missing console warning'
printf '%s\n' 'Reset script checks passed.'
