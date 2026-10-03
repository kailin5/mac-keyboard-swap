#!/bin/bash
# Test suite. Uses the real `defaults` and PlistBuddy against a throwaway preferences
# domain, and a fake hidutil (test/stubs) so no real keyboard mapping is touched.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KBSWAP="$ROOT/bin/kbswap"
DOMAIN=dev.kbswap.test

VID=1133 PID=50475
KEY="com.apple.keyboard.modifiermapping.$VID-$PID-0"
SWAP="30064771298 30064771299
30064771299 30064771298
30064771302 30064771303
30064771303 30064771302"

pass=0 fail=0 WORK=""

setup() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/kbswap-test.XXXXXX")
  export KBSWAP_DOMAIN=$DOMAIN KBSWAP_STATE_DIR="$WORK/state" STUB_DIR="$WORK"
  export STUB_VID=$VID STUB_PID=$PID STUB_CONNECTED=1
  export PATH="$ROOT/test/stubs:$PATH"
  defaults -currentHost delete "$DOMAIN" >/dev/null 2>&1 || true
}
teardown() {
  defaults -currentHost delete "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}

# saved mapping for KEY as sorted "src dst" lines (identity entries dropped)
saved() {
  defaults -currentHost export "$DOMAIN" - 2>/dev/null > "$WORK/d.plist" || return 0
  /usr/libexec/PlistBuddy -x -c "Print :$KEY" "$WORK/d.plist" 2>/dev/null | awk '
    /MappingSrc</ { k = "s"; next } /MappingDst</ { k = "d"; next }
    /<integer>/ { v = $0; gsub(/.*<integer>|<\/integer>.*/, "", v); if (k == "s") s = v; else d = v }
    /<\/dict>/ { if (s != d) print s, d }' | sort
}
live() { grep -o '"HIDKeyboardModifierMappingSrc":[0-9]*,"HIDKeyboardModifierMappingDst":[0-9]*' "$WORK/live" 2>/dev/null \
           | awk -F'[:,]' '{ print $2, $4 }' | sort; }

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

t() { # run one test function in a fresh environment
  setup; "$1"; teardown
}

# --- tests ----------------------------------------------------------------------

test_enable_saves_and_applies() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  check "enable: saved" "$SWAP" "$(saved)"
  check "enable: live" "$SWAP" "$(live)"
  check "enable: managed" "$VID-$PID" "$(cat "$KBSWAP_STATE_DIR/managed")"
}

test_enable_accepts_hex_and_is_idempotent() {
  "$KBSWAP" enable 0x46d:0xc52b >/dev/null
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  check "hex id: saved" "$SWAP" "$(saved)"
  check "idempotent: one managed entry" "1" "$(wc -l < "$KBSWAP_STATE_DIR/managed" | tr -d ' ')"
}

test_enable_disconnected_saves_only() {
  STUB_CONNECTED=0 "$KBSWAP" enable "$VID:$PID" >/dev/null
  check "disconnected: saved" "$SWAP" "$(saved)"
  check "disconnected: no live set" "" "$(live)"
}

test_disable_removes() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  "$KBSWAP" disable "$VID:$PID" >/dev/null
  check "disable: saved gone" "" "$(saved)"
  check "disable: live cleared" "" "$(live)"
  check "disable: unmanaged" "" "$(cat "$KBSWAP_STATE_DIR/managed")"
}

test_refuses_custom_mapping_without_force() {
  defaults -currentHost write "$DOMAIN" "$KEY" '<array><dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771300</integer></dict></array>'
  "$KBSWAP" enable "$VID:$PID" >/dev/null 2>&1
  check "custom: exit non-zero" "1" "$?"
  check "custom: untouched" "30064771129 30064771300" "$(saved)"
}

test_force_backs_up_and_disable_restores() {
  defaults -currentHost write "$DOMAIN" "$KEY" '<array><dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771300</integer></dict></array>'
  "$KBSWAP" enable "$VID:$PID" --force >/dev/null
  check "force: swapped" "$SWAP" "$(saved)"
  "$KBSWAP" disable "$VID:$PID" >/dev/null
  check "restore: saved" "30064771129 30064771300" "$(saved)"
  check "restore: live" "30064771129 30064771300" "$(live)"
}

test_disable_unmanaged_refused() {
  "$KBSWAP" disable "$VID:$PID" >/dev/null 2>&1
  check "disable unmanaged: exit non-zero" "1" "$?"
}

test_doctor() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  "$KBSWAP" doctor >/dev/null
  check "doctor: healthy" "0" "$?"
  rm -f "$WORK/live"
  "$KBSWAP" doctor >/dev/null
  check "doctor: detects inactive swap" "1" "$?"
  "$KBSWAP" apply >/dev/null
  "$KBSWAP" doctor >/dev/null
  check "doctor: apply fixes it" "0" "$?"
}

test_list_shows_keyboard() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  out=$("$KBSWAP" list)
  case "$out" in *"$VID:$PID"*"Test Keyboard"*"Alt/Win swapped, managed by kbswap"*) r=ok ;; *) r="$out" ;; esac
  check "list" "ok" "$r"
}

test_uninstall() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  "$KBSWAP" uninstall >/dev/null
  check "uninstall: saved gone" "" "$(saved)"
  check "uninstall: state dir gone" "no" "$([ -d "$KBSWAP_STATE_DIR" ] && echo yes || echo no)"
}

test_dry_run_changes_nothing() {
  "$KBSWAP" --dry-run enable "$VID:$PID" >/dev/null
  check "dry-run: nothing saved" "" "$(saved)"
  check "dry-run: nothing live" "" "$(live)"
}

test_list_plain() {
  "$KBSWAP" enable "$VID:$PID" >/dev/null
  check "list --plain" "$(printf "%s\t%s\t%s\t%s" "$VID:$PID" USB swapped "Test Keyboard")" "$("$KBSWAP" list --plain)"
}

test_install_script_with_ids() {
  KBSWAP_BIN_DIR="$WORK/bin" "$ROOT/install.sh" "$VID:$PID" >/dev/null
  check "install: binary" "yes" "$([ -x "$WORK/bin/kbswap" ] && echo yes || echo no)"
  check "install: enabled" "$SWAP" "$(saved)"
}

test_bad_id() {
  "$KBSWAP" enable nonsense >/dev/null 2>&1
  check "bad id: exit non-zero" "1" "$?"
}

for f in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do t "$f"; done
echo "$pass passed, $fail failed"
[ $fail = 0 ]
