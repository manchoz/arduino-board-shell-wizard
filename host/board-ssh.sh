#!/usr/bin/env bash
# Host SSH integration; compatible with Bash 3.2.
# shellcheck disable=SC2034,SC2154 # Globals are shared with the sourcing launcher.

read_ssh_key() {
  local path="$1" key
  [[ "$path" != \~/* ]] || path="$HOME/${path#\~/}"
  if ! command -v ssh >/dev/null || ! command -v ssh-keygen >/dev/null; then echo 'Install the OpenSSH client to configure SSH.' >&2; return 1; fi
  [[ -f "$path" && -r "$path" ]] || { echo 'Choose a readable SSH public-key file.' >&2; return 1; }
  if LC_ALL=C IFS= read -r -d '' -n 16385 key <"$path"; then
    echo 'Choose one public key of at most 16 KiB, without NUL bytes.' >&2; return 1
  fi
  key="${key%$'\n'}"; key="${key%$'\r'}"
  [[ "$key" != *$'\n'* && "$key" != *$'\r'* && "$key" =~ ^([A-Za-z0-9@._+-]+)[[:space:]]+([A-Za-z0-9+/]+={0,3})([[:space:]].*)?$ ]] || {
    echo 'Choose a single OpenSSH public key, without authorized_keys options.' >&2; return 1;
  }
  ssh_public_key="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  ssh-keygen -l -f "$path" >/dev/null 2>&1 || { echo 'Invalid SSH public key.' >&2; return 1; }
  ssh_identity="$(cd -P -- "$(dirname -- "$path")" && pwd)/$(basename -- "$path")" || return 1
  [[ "$ssh_identity" != *.pub || ! -f "${ssh_identity%.pub}" ]] || ssh_identity="${ssh_identity%.pub}"
}

offer_ssh_key() {
  local answer default_key='' name
  IFS= read -r -p 'Install your SSH public key and configure ssh <board-name>? [y/N] ' answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || return 1
  for name in id_ed25519.pub id_rsa.pub; do
    if [[ -f "$HOME/.ssh/$name" ]]; then default_key="$HOME/.ssh/$name"; break; fi
  done
  IFS= read -r -p "Public-key file${default_key:+ [$default_key]}: " ssh_key || return 1
  ssh_key="${ssh_key:-$default_key}"
  IFS= read -r -p 'SSH address (blank uses the board hostname with .local): ' ssh_host || return 1
}

configure_board_ssh() (
  local ssh_dir="$1" address="$2" name mode config input temp='' body='' identity begin end
  mode=$(run_adb -s "$serial" shell arduino-app-cli system network-mode status </dev/null) || return 1
  [[ "${mode%$'\r'}" == enabled ]] || { echo 'SSH configuration requires enabled Network Mode; rerun setup to enable it.' >&2; return 1; }
  name=$(run_adb -s "$serial" shell hostname </dev/null) || return 1
  name="${name%$'\r'}"
  [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || { echo 'Invalid board hostname.' >&2; return 1; }
  [[ -n "$address" ]] || address="$name.local"
  [[ "$address" =~ ^[A-Za-z0-9:][A-Za-z0-9._:-]*$ ]] || { echo 'SSH address must be a hostname or IP address.' >&2; return 1; }
  identity="$ssh_identity"
  [[ "$identity" != *$'\n'* && "$identity" != *$'\r'* && "$identity" != *"\${"* ]] || return 1
  identity="${identity//\\/\\\\}"; identity="${identity//\"/\\\"}"; identity="${identity//%/%%}"
  config="$ssh_dir/config"
  [[ ! -L "$ssh_dir" && ! -L "$config" && ( ! -e "$config" || -f "$config" ) ]] || {
    echo 'SSH config must be a regular file in a non-symlinked .ssh directory.' >&2; return 1;
  }
  umask 077
  mkdir -p -- "$ssh_dir" || return 1
  chmod 700 "$ssh_dir" || return 1
  temp=$(mktemp "$ssh_dir/config.arduino.XXXXXX") || return 1
  body=$(mktemp "$ssh_dir/config.arduino.XXXXXX") || { rm -f -- "$temp"; return 1; }
  trap 'rm -f -- "$temp" "$body"' EXIT
  begin="# BEGIN arduino-board-tools $name"; end="# END arduino-board-tools $name"
  input=/dev/null
  [[ ! -e "$config" ]] || input="$config"
  awk -v begin="$begin" -v end="$end" -v alias="$name" '
    { line = $0; sub(/\r$/, "", line) }
    line == begin { if (inside || seen++) exit 2; inside = 1; next }
    line == end { if (!inside) exit 2; inside = 0; next }
    inside { next }
    {
      check = line; sub(/#.*/, "", check); gsub(/=/, " ", check); gsub(/"/, "", check)
      sub(/^[[:space:]]+/, "", check); n = split(check, fields, /[[:space:]]+/)
      if (tolower(fields[1]) == "host") for (j = 2; j <= n; j++) if (tolower(fields[j]) == tolower(alias)) conflict = 1
      print
    }
    END { if (inside || conflict) exit 2 }
  ' "$input" >"$body" || { echo 'An unmanaged SSH alias or malformed managed block conflicts with this board.' >&2; return 1; }
  printf '%s\nHost %s\n    HostName %s\n    Port 22\n    User arduino\n    PubkeyAuthentication yes\n    IdentityFile "%s"\n    IdentitiesOnly yes\nHost *\n%s\n' "$begin" "$name" "$address" "$identity" "$end" >"$temp" || return 1
  cat "$body" >>"$temp" || return 1
  ssh -G -T -F "$temp" "$name" >/dev/null 2>&1 || { echo 'SSH rejected the proposed config; existing config was preserved.' >&2; return 1; }
  printf '%s\n' "$ssh_public_key" | run_adb -s "$serial" shell -T bash -c "'source \"$board_temp/board-common.sh\"; install_ssh_key'" >/dev/null || return 1
  mv -f -- "$temp" "$config" || { echo 'Public key was installed, but host SSH config could not be saved.' >&2; return 1; }
  echo "SSH configured: ssh $name (requires network access to $address)." >&2
)
