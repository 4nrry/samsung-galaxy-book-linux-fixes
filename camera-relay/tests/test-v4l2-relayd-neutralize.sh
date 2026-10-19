#!/usr/bin/env bash
# Regression tests for neutralising v4l2-relayd in the webcam installers and
# restoring it on uninstall (issues #54, #123).
#
# install.sh used to stop, disable and mask only the bare v4l2-relayd.service.
# Instances of the template — v4l2-relayd@intel-ipu.service from Intel's IPU6
# tutorials, v4l2-relayd@default.service from our own legacy webcam-fix/ —
# never matched, stayed enabled, grabbed v4l2loopback at boot and left the
# relay black.
#
# Now both installers list the bare service plus every loaded or enabled
# instance (v4l2_relayd_units), mask each one and record its prior state
# (mask_v4l2_relayd_units), and both uninstallers restore exactly that list
# (restore_v4l2_relayd_units). What has to hold:
#   1. The two installers' helpers, and the two uninstallers' restore, are
#      byte-identical — they are copies, and drift is how one half regresses.
#   2. An instance is found whether it is only loaded (list-units) or only
#      enabled (a .wants symlink — enabled but never started is not loaded),
#      and one reported by both sources is masked once.
#   3. The template v4l2-relayd@.service is never masked: that would block
#      every instance, including one started after going back to webcam-fix/.
#   4. A re-run doesn't record an already-masked unit, which would log
#      "masked" as its prior state and lose the real one.
#   5. Uninstall unmasks every listed unit, re-enables only those recorded
#      enabled, and falls back to the old bare-service guess when the list
#      doesn't name it (installs from before the list existed).
#
# The functions are extracted with sed and run against stub systemctl/sudo in a
# stub-only PATH, with a fake /etc/systemd/system and list file under a temp
# dir, so they need no root and touch no system state.
#
# Usage: ./test-v4l2-relayd-neutralize.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_LC="$ROOT/webcam-fix-libcamera/install.sh"
INSTALL_B5="$ROOT/webcam-fix-book5/install.sh"
UNINSTALL_LC="$ROOT/webcam-fix-libcamera/uninstall.sh"
UNINSTALL_B5="$ROOT/webcam-fix-book5/uninstall.sh"
PASS=0
FAIL=0

ok()  { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad() { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "test-v4l2-relayd-neutralize"

extract() { sed -n "/^$1()/,/^}/p" "$2"; }

UNITS_SRC=$(extract v4l2_relayd_units "$INSTALL_LC")
MASK_SRC=$(extract mask_v4l2_relayd_units "$INSTALL_LC")
RESTORE_SRC=$(extract restore_v4l2_relayd_units "$UNINSTALL_LC")

for v in UNITS_SRC MASK_SRC RESTORE_SRC; do
    if [[ -z "${!v//[[:space:]]/}" ]]; then
        bad "$v could not be extracted — tests cannot run"
        echo; echo "$PASS passed, $FAIL failed"
        exit 1
    fi
done

# ── 1. The copies match ──────────────────────────────────────────────────────
echo
echo "copies"

same() {
    local fn="$1" a="$2" b="$3"
    if [[ "$(extract "$fn" "$a")" == "$(extract "$fn" "$b")" ]]; then
        ok "$fn is identical in $(basename "$(dirname "$a")") and $(basename "$(dirname "$b")")"
    else
        bad "$fn differs between $a and $b"
    fi
}
same v4l2_relayd_units "$INSTALL_LC" "$INSTALL_B5"
same mask_v4l2_relayd_units "$INSTALL_LC" "$INSTALL_B5"
same restore_v4l2_relayd_units "$UNINSTALL_LC" "$UNINSTALL_B5"

for f in "$INSTALL_LC" "$INSTALL_B5"; do
    name=$(basename "$(dirname "$f")")/install.sh
    src=$(cat "$f")
    if grep -qF 'RELAYD_UNITS=$(v4l2_relayd_units)' <<< "$src" \
       && grep -qF 'mask_v4l2_relayd_units "$RELAYD_UNITS"' <<< "$src"; then
        ok "$name: the neutralise block uses both helpers"
    else
        bad "$name: the neutralise block doesn't call the helpers"
    fi
done
for f in "$UNINSTALL_LC" "$UNINSTALL_B5"; do
    name=$(basename "$(dirname "$f")")/uninstall.sh
    calls=$(grep -c '^restore_v4l2_relayd_units$' "$f" || true)
    if [[ "$calls" == 1 ]]; then
        ok "$name: calls the restore once"
    else
        bad "$name: calls the restore $calls times"
    fi
done

# ── Stubs ────────────────────────────────────────────────────────────────────
# systemctl logs its argv and answers from the STUB_* variables:
#   STUB_UNIT_FILES  list-unit-files output
#   STUB_LIST_UNITS  list-units output — only for the exact query the helper
#                    makes, so a changed query fails here instead of passing
#   STUB_ENABLED     "<unit> <state>" lines for is-enabled (default: disabled)
# sudo logs "sudo <argv>" and runs it, so install/tee/rm act on the temp list.
make_bin() {
    local bindir="$TMP/bin-$RANDOM$RANDOM" t
    mkdir -p "$bindir"
    cat > "$bindir/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$STUB_LOG"
case "$1" in
    list-unit-files) printf '%s\n' "${STUB_UNIT_FILES:-}" ;;
    list-units)
        [ "$*" = "list-units --all --plain --no-legend v4l2-relayd@*.service" ] \
            && printf '%s\n' "${STUB_LIST_UNITS:-}" ;;
    is-enabled)
        s=$(printf '%s\n' "${STUB_ENABLED:-}" | awk -v u="$2" '$1 == u { print $2 }')
        echo "${s:-disabled}"
        [ "${s:-disabled}" = enabled ] || exit 1 ;;
esac
exit 0
EOF
    cat > "$bindir/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF
    chmod +x "$bindir/systemctl" "$bindir/sudo"
    for t in awk sort grep cat install tee rm rmdir; do
        ln -s "$(command -v "$t")" "$bindir/$t"
    done
    echo "$bindir"
}

BIN=$(make_bin)
ETC="$TMP/etc-systemd"
LIST="$TMP/var-lib/camera-relay/v4l2-relayd-masked"
LOG="$TMP/log"

reset() {
    rm -rf "$ETC" "$TMP/var-lib" "$LOG"
    mkdir -p "$ETC/multi-user.target.wants"
    : > "$LOG"
    STUB_UNIT_FILES="cups.service                 enabled  enabled"
    STUB_LIST_UNITS=""
    STUB_ENABLED=""
}

# run <fn source> <call...> → the function's stdout, under the installers'
# `set -e` plus pipefail, with nothing but the stubs on PATH.
run() {
    local src="$1"; shift
    (
        set -euo pipefail
        PATH="$BIN"
        export STUB_LOG="$LOG" STUB_UNIT_FILES STUB_LIST_UNITS STUB_ENABLED
        SYSTEMD_ETC="$ETC"
        RELAYD_MASKED_LIST="$LIST"
        eval "$src"
        "$@"
    ) 2>/dev/null
}

units() { run "$UNITS_SRC" v4l2_relayd_units; }
mask()  { run "$MASK_SRC" mask_v4l2_relayd_units "$1" > /dev/null; }

logged()     { grep -qxF -- "$1" "$LOG"; }
not_logged() { ! grep -qF -- "$1" "$LOG"; }
list_is()    { [[ "$(cat "$LIST" 2>/dev/null)" == "$1" ]]; }
want() {
    local name="$1" got="$2" expected="$3"
    if [[ "$got" == "$expected" ]]; then ok "$name"
    else bad "$name — got: $(tr '\n' '|' <<< "$got")"; fi
}

# ── 2. Finding and masking ───────────────────────────────────────────────────
echo
echo "install"

reset
STUB_UNIT_FILES="v4l2-relayd.service          enabled  enabled
cups.service                 enabled  enabled"
STUB_ENABLED="v4l2-relayd.service enabled"
got=$(units)
want "bare service only → listed" "$got" "v4l2-relayd.service"
mask "$got"
if logged "sudo systemctl stop v4l2-relayd.service" \
   && logged "sudo systemctl disable v4l2-relayd.service" \
   && logged "sudo systemctl mask v4l2-relayd.service" \
   && list_is "v4l2-relayd.service enabled"; then
    ok "bare service stopped, disabled, masked and recorded enabled"
else
    bad "bare service not neutralised/recorded — list: $(cat "$LIST" 2>/dev/null)"
fi

reset
ln -s /usr/lib/systemd/system/v4l2-relayd@.service \
    "$ETC/multi-user.target.wants/v4l2-relayd@intel-ipu.service"
STUB_UNIT_FILES="v4l2-relayd@.service         indirect enabled"
STUB_ENABLED="v4l2-relayd@intel-ipu.service enabled"
got=$(units)
want "@intel-ipu enabled but not loaded → found via .wants" "$got" "v4l2-relayd@intel-ipu.service"
mask "$got"
if logged "sudo systemctl mask v4l2-relayd@intel-ipu.service" \
   && list_is "v4l2-relayd@intel-ipu.service enabled"; then
    ok "@intel-ipu masked and recorded enabled"
else
    bad "@intel-ipu not masked/recorded — list: $(cat "$LIST" 2>/dev/null)"
fi

# Started by the legacy webcam-fix/ watchdog, never enabled. A failed unit gets
# a "●" in front of its name on some systemd versions even with --plain.
reset
STUB_UNIT_FILES="v4l2-relayd@.service         indirect enabled"
STUB_LIST_UNITS="v4l2-relayd@default.service loaded active running v4l2-relayd daemon"
got=$(units)
want "@default active (list-units only) → found" "$got" "v4l2-relayd@default.service"
mask "$got"
if logged "sudo systemctl stop v4l2-relayd@default.service" \
   && logged "sudo systemctl mask v4l2-relayd@default.service" \
   && list_is "v4l2-relayd@default.service disabled"; then
    ok "@default stopped, masked and recorded disabled"
else
    bad "@default not neutralised/recorded — list: $(cat "$LIST" 2>/dev/null)"
fi

reset
STUB_LIST_UNITS="● v4l2-relayd@default.service loaded failed failed v4l2-relayd daemon"
want "a failed instance's ● marker is skipped" "$(units)" "v4l2-relayd@default.service"

reset
ln -s /usr/lib/systemd/system/v4l2-relayd@.service \
    "$ETC/multi-user.target.wants/v4l2-relayd@intel-ipu.service"
STUB_UNIT_FILES="v4l2-relayd.service          enabled  enabled
v4l2-relayd@.service         indirect enabled"
STUB_LIST_UNITS="v4l2-relayd@intel-ipu.service loaded active running v4l2-relayd daemon
v4l2-relayd@default.service loaded inactive dead v4l2-relayd daemon"
STUB_ENABLED="v4l2-relayd.service enabled
v4l2-relayd@intel-ipu.service enabled"
got=$(units)
want "both sources de-duplicated, bare first" "$got" \
    $'v4l2-relayd.service\nv4l2-relayd@default.service\nv4l2-relayd@intel-ipu.service'
mask "$got"
masks=$(grep -c '^sudo systemctl mask v4l2-relayd@intel-ipu.service$' "$LOG" || true)
want "an instance reported twice is masked once" "$masks" "1"
want "each unit recorded once with its own state" "$(cat "$LIST" 2>/dev/null)" \
    $'v4l2-relayd.service enabled\nv4l2-relayd@default.service disabled\nv4l2-relayd@intel-ipu.service enabled'

# The template alone is what the legacy webcam-fix/ leaves when nothing is
# running. A .wants entry named after the template itself must not leak through.
reset
ln -s /usr/lib/systemd/system/v4l2-relayd@.service \
    "$ETC/multi-user.target.wants/v4l2-relayd@.service"
STUB_UNIT_FILES="v4l2-relayd@.service         indirect enabled"
got=$(units)
want "template only → nothing listed" "$got" ""
mask "$got"
if not_logged "mask" && not_logged "sudo"; then
    ok "template only → nothing masked, template untouched"
else
    bad "template only still made calls: $(tr '\n' '|' < "$LOG")"
fi

reset
got=$(units)
want "no v4l2-relayd at all → nothing listed" "$got" ""
mask "$got"
if not_logged "sudo" && [[ ! -e "$LIST" ]]; then
    ok "no v4l2-relayd → no sudo calls, no list file"
else
    bad "no v4l2-relayd still acted: $(tr '\n' '|' < "$LOG")"
fi

# Re-run: install.sh masked it last time. Recording it again would store
# "masked" (here: "disabled") as its prior state and lose "enabled".
reset
mkdir -p "${LIST%/*}"
echo "v4l2-relayd@intel-ipu.service enabled" > "$LIST"
STUB_LIST_UNITS="v4l2-relayd@intel-ipu.service masked inactive dead v4l2-relayd@intel-ipu.service"
STUB_ENABLED="v4l2-relayd@intel-ipu.service masked"
mask "$(units)"
if not_logged "sudo" && list_is "v4l2-relayd@intel-ipu.service enabled"; then
    ok "re-run skips an already-masked unit and keeps its recorded state"
else
    bad "re-run touched a masked unit — list: $(tr '\n' '|' < "$LIST")"
fi

# ── 3. Restoring ─────────────────────────────────────────────────────────────
echo
echo "uninstall"

restore() { run "$RESTORE_SRC" restore_v4l2_relayd_units > /dev/null; }

reset
mkdir -p "${LIST%/*}"
printf '%s\n' "v4l2-relayd@intel-ipu.service enabled" "v4l2-relayd@default.service disabled" > "$LIST"
restore
if logged "sudo systemctl unmask v4l2-relayd@intel-ipu.service" \
   && logged "sudo systemctl unmask v4l2-relayd@default.service"; then
    ok "every listed unit is unmasked"
else
    bad "not every listed unit unmasked: $(tr '\n' '|' < "$LOG")"
fi
if logged "sudo systemctl enable v4l2-relayd@intel-ipu.service" \
   && not_logged "enable v4l2-relayd@default.service"; then
    ok "only the units recorded enabled are re-enabled"
else
    bad "wrong units re-enabled: $(tr '\n' '|' < "$LOG")"
fi
if not_logged "sudo systemctl unmask v4l2-relayd.service" \
   && not_logged "sudo systemctl enable v4l2-relayd.service"; then
    ok "bare service untouched when it isn't masked"
else
    bad "bare service touched: $(tr '\n' '|' < "$LOG")"
fi
if [[ ! -e "$LIST" && ! -e "${LIST%/*}" ]]; then
    ok "list file and its empty directory removed"
else
    bad "list file or directory left behind"
fi

reset
mkdir -p "${LIST%/*}"
echo "v4l2-relayd.service disabled" > "$LIST"
STUB_ENABLED="v4l2-relayd.service masked"
restore
if logged "sudo systemctl unmask v4l2-relayd.service" \
   && not_logged "enable v4l2-relayd.service"; then
    ok "a listed bare service follows the list, not the old guess"
else
    bad "listed bare service mishandled: $(tr '\n' '|' < "$LOG")"
fi

reset
STUB_ENABLED="v4l2-relayd.service masked"
restore
if logged "sudo systemctl unmask v4l2-relayd.service" \
   && logged "sudo systemctl enable v4l2-relayd.service"; then
    ok "no list file → old bare-service heuristic (masked)"
else
    bad "fallback by is-enabled didn't run: $(tr '\n' '|' < "$LOG")"
fi

reset
ln -s /dev/null "$ETC/v4l2-relayd.service"
restore
if logged "sudo systemctl unmask v4l2-relayd.service"; then
    ok "no list file → old bare-service heuristic (/dev/null symlink)"
else
    bad "fallback by symlink didn't run: $(tr '\n' '|' < "$LOG")"
fi

reset
restore
if not_logged "sudo"; then
    ok "no list file, nothing masked → no calls"
else
    bad "restored something that wasn't masked: $(tr '\n' '|' < "$LOG")"
fi

# Upgrade: an older install masked the bare service without a list, a newer
# one then masked @intel-ipu and skipped the already-masked bare service.
reset
mkdir -p "${LIST%/*}"
echo "v4l2-relayd@intel-ipu.service enabled" > "$LIST"
STUB_ENABLED="v4l2-relayd.service masked"
restore
if logged "sudo systemctl enable v4l2-relayd@intel-ipu.service" \
   && logged "sudo systemctl unmask v4l2-relayd.service" \
   && logged "sudo systemctl enable v4l2-relayd.service"; then
    ok "list without the bare service → bare still restored by the old guess"
else
    bad "upgrade path lost the bare service: $(tr '\n' '|' < "$LOG")"
fi

# Round trip through the real install-side writer.
reset
ln -s /usr/lib/systemd/system/v4l2-relayd@.service \
    "$ETC/multi-user.target.wants/v4l2-relayd@intel-ipu.service"
STUB_LIST_UNITS="v4l2-relayd@default.service loaded active running v4l2-relayd daemon"
STUB_ENABLED="v4l2-relayd@intel-ipu.service enabled"
mask "$(units)"
: > "$LOG"
restore
if logged "sudo systemctl enable v4l2-relayd@intel-ipu.service" \
   && logged "sudo systemctl unmask v4l2-relayd@default.service" \
   && not_logged "enable v4l2-relayd@default.service"; then
    ok "install → uninstall round trip restores exactly the prior states"
else
    bad "round trip wrong: $(tr '\n' '|' < "$LOG")"
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
