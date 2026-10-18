#!/usr/bin/env bash
# Regression tests for libcamera version detection in the Book5 bayer fix
# (webcam-fix-book5/libcamera-bayer-fix/build-patched-libcamera.sh and the
# rebuild check in webcam-fix-book5/install.sh).
#
# Detection used to take `pkg-config --modversion libcamera` whenever it gave
# an answer and ask the package manager only when it didn't. On Debian with
# stable's libcamera-dev 0.4.0 still installed next to the 0.7.1 backport,
# pkg-config said 0.4.0 and the bayer fix built v0.4.0 against a 0.7 system
# (the #119 symptom by another route). Dropping pkg-config isn't the answer
# either: it is the only source that sees a /usr/local build, and --uninstall
# only matched its backup because our own full install rewrites the .pc.
#
# Both scripts now take the newer of pkg-config and the package manager
# (libcamera_installed_version) and apply the #71 floor (0.7.0 → 0.7.2,
# floor_libcamera_version) before comparing with the backup. These tests
# drive the real functions and the real --uninstall comparison, extracted
# with sed, against stub pkg-config/dpkg/rpm/pacman in a stub-only PATH, so
# they need no root and touch no system state.
#
# Usage: ./test-libcamera-version-detect.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/webcam-fix-book5/libcamera-bayer-fix/build-patched-libcamera.sh"
INSTALL="$ROOT/webcam-fix-book5/install.sh"
PASS=0
FAIL=0

ok()  { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad() { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "test-libcamera-version-detect ($BUILD)"

extract() { sed -n "/^$1()/,/^}/p" "$2"; }

HELPERS_BUILD="$(extract libcamera_installed_version "$BUILD")
$(extract floor_libcamera_version "$BUILD")"
HELPERS_INSTALL="$(extract libcamera_installed_version "$INSTALL")
$(extract floor_libcamera_version "$INSTALL")"
DETECT_SRC=$(extract detect_libcamera_version "$BUILD")
# The --uninstall version check: from reading the backup's version marker up
# to (not including) the `if $STALE_BACKUP` that acts on the verdict.
UNINSTALL_SRC=$(sed -n '/^    BACKUP_VERSION=\$(cat/,/^    if \$STALE_BACKUP; then$/p' "$BUILD" | sed '$d')

for v in HELPERS_BUILD HELPERS_INSTALL DETECT_SRC UNINSTALL_SRC; do
    if [[ -z "${!v//[[:space:]]/}" ]]; then
        bad "$v could not be extracted — tests cannot run"
        echo; echo "$PASS passed, $FAIL failed"
        exit 1
    fi
done

# make_bin [pm...] → a directory holding pkg-config (always — it exists on any
# system with a dev package, and reports nothing when no libcamera.pc is
# found), the named package managers, and the real tools the helpers call.
# Stubs read the STUB_* variables below.
#   STUB_PC      pkg-config --modversion libcamera ("" = no .pc)
#   STUB_DPKG    version of the installed libcamera0.X runtime package
#   STUB_DEV     version of the installed libcamera-dev package
#   STUB_RPM     rpm -q libcamera ("" = not installed)
#   STUB_PACMAN  pacman -Q libcamera ("" = not installed)
make_bin() {
    local bindir="$TMP/bin-$RANDOM$RANDOM" t pm
    mkdir -p "$bindir"
    cat > "$bindir/pkg-config" <<'EOF'
#!/bin/sh
[ -n "${STUB_PC:-}" ] || exit 1
echo "$STUB_PC"
EOF
    for pm in "$@"; do
        case "$pm" in
            dpkg) cat > "$bindir/dpkg" <<'EOF'
#!/bin/sh
echo "Desired=Unknown/Install/Remove/Purge/Hold"
echo "||/ Name                   Version              Architecture Description"
echo "+++-======================-====================-============-==========="
[ -n "${STUB_DEV:-}" ] && echo "ii  libcamera-dev:amd64    $STUB_DEV  amd64        complex camera support library (development files)"
[ -n "${STUB_DPKG:-}" ] && echo "ii  libcamera0.7:amd64     $STUB_DPKG  amd64        complex camera support library"
exit 0
EOF
            ;;
            rpm) cat > "$bindir/rpm" <<'EOF'
#!/bin/sh
[ -n "${STUB_RPM:-}" ] || { echo "package libcamera is not installed"; exit 1; }
printf '%s' "$STUB_RPM"
EOF
            ;;
            pacman) cat > "$bindir/pacman" <<'EOF'
#!/bin/sh
[ -n "${STUB_PACMAN:-}" ] || { echo "error: package 'libcamera' was not found" >&2; exit 1; }
echo "libcamera $STUB_PACMAN"
EOF
            ;;
        esac
    done
    chmod +x "$bindir/pkg-config" "${@/#/$bindir/}"
    for t in sort tail head grep awk cat; do
        ln -s "$(command -v "$t")" "$bindir/$t"
    done
    echo "$bindir"
}

# detect <pms> → LIBCAMERA_GIT_TAG detect_libcamera_version settles on, or
# "DIE" if it gives up. <pms> is a space-separated list (may be empty).
detect() {
    local bindir
    bindir=$(make_bin $1)
    (
        set -euo pipefail
        PATH="$bindir"
        die()  { echo "DIE"; exit 9; }
        info() { :; }
        warn() { :; }
        eval "$HELPERS_BUILD"
        eval "$DETECT_SRC"
        detect_libcamera_version
        echo "$LIBCAMERA_GIT_TAG"
    ) 2>/dev/null
}

# uninstall_stale <backup version> <pms> → the STALE_BACKUP the real
# --uninstall comparison reaches ("true" = backup no longer matches).
uninstall_stale() {
    local bindir backup="$TMP/backup-$RANDOM$RANDOM"
    bindir=$(make_bin $2)
    mkdir -p "$backup"
    echo "$1" > "$backup/version"
    (
        set -euo pipefail
        PATH="$bindir"
        BACKUP_DIR="$backup"
        warn() { :; }
        eval "$HELPERS_BUILD"
        eval "$UNINSTALL_SRC"
        echo "$STALE_BACKUP"
    ) 2>/dev/null
}

reset_stubs() { export STUB_PC="" STUB_DPKG="" STUB_DEV="" STUB_RPM="" STUB_PACMAN=""; }

check() {
    local desc="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        ok "$desc → $got"
    else
        bad "$desc: want '$want', got '${got:-<nothing>}'"
    fi
}

# ── 1. The #119 gap and its neighbours ───────────────────────────────────────
echo
echo "detect_libcamera_version"

reset_stubs; STUB_PC=0.4.0 STUB_DEV=0.4.0-3 STUB_DPKG=0.7.1-1~bpo13+1
check "Debian, stale libcamera-dev 0.4.0 + backport 0.7.1" v0.7.1 "$(detect dpkg)"

reset_stubs; STUB_PC=0.7.2 STUB_DPKG=0.7.0-1ubuntu2
check "/usr/local 0.7.2 build over Ubuntu 0.7.0" v0.7.2 "$(detect dpkg)"

reset_stubs; STUB_DPKG=0.7.0-1ubuntu2
check "no .pc, Ubuntu 0.7.0 (floor applies)" v0.7.2 "$(detect dpkg)"

reset_stubs; STUB_PC=0.7.2
check "only a .pc, no package" v0.7.2 "$(detect dpkg)"

reset_stubs; STUB_RPM=0.7.0
check "Fedora rpm 0.7.0" v0.7.2 "$(detect rpm)"

reset_stubs; STUB_PACMAN=0.7.1-1
check "Arch pacman 0.7.1-1" v0.7.1 "$(detect pacman)"

# Fedora packages pacman and Arch packages rpm; an empty probe must not win.
reset_stubs; STUB_RPM=0.7.1
check "Fedora with pacman also installed" v0.7.1 "$(detect "dpkg rpm pacman")"

reset_stubs; STUB_PC="0.6.0+53-f4f8b487-dirty" STUB_DPKG="1:0.5.2-1"
check "git-describe .pc vs epoch'd package" v0.6.0 "$(detect dpkg)"

reset_stubs
check "nothing installed" DIE "$(detect "dpkg rpm pacman")"

# ── 2. --uninstall backup-version check ──────────────────────────────────────
echo
echo "--uninstall backup match"

reset_stubs; STUB_PC=0.4.0 STUB_DEV=0.4.0-3 STUB_DPKG=0.7.1-1~bpo13+1
check "old script built 0.4.0 on Debian 0.7.1 → stale" true "$(uninstall_stale 0.4.0 dpkg)"

reset_stubs; STUB_PC=0.7.2 STUB_DPKG=0.7.0-1ubuntu2
check "Ubuntu 26.04 after a patched install → match" false "$(uninstall_stale 0.7.2 dpkg)"

reset_stubs; STUB_DPKG=0.7.0-1ubuntu2
check "patched .pc gone, Ubuntu 0.7.0 → match via floor" false "$(uninstall_stale 0.7.2 dpkg)"

reset_stubs; STUB_DPKG=0.7.0-1ubuntu2
check "pre-#71 backup recorded 0.7.0 → match" false "$(uninstall_stale 0.7.0 dpkg)"

reset_stubs; STUB_RPM=0.7.1
check "Fedora upgraded 0.7.0 → 0.7.1 since backup → stale" true "$(uninstall_stale 0.7.2 rpm)"

# ── 3. Drift and wiring ──────────────────────────────────────────────────────
# install.sh carries its own copy of the helpers; the two must not drift.
# And a revert to a bare pkg-config probe would leave the helpers orphaned
# while every test above stayed green.
echo
echo "drift and wiring"

if [[ "$HELPERS_BUILD" == "$HELPERS_INSTALL" ]]; then
    ok "helpers in install.sh are byte-identical to build-patched-libcamera.sh"
else
    bad "helpers differ between install.sh and build-patched-libcamera.sh:"
    diff <(echo "$HELPERS_BUILD") <(echo "$HELPERS_INSTALL") | sed 's/^/      /'
fi

for f in "$BUILD" "$INSTALL"; do
    n=$(grep -c 'pkg-config --modversion libcamera' "$f" || true)
    inside=$(extract libcamera_installed_version "$f" | grep -c 'pkg-config --modversion libcamera' || true)
    if [[ "$n" == "1" && "$inside" == "1" ]]; then
        ok "$(basename "$f"): the only pkg-config probe is inside the helper"
    else
        bad "$(basename "$f"): $n pkg-config probe(s), $inside inside the helper"
    fi
done

uses() {
    local desc="$1" pattern="$2" src="$3"
    if grep -qF -- "$pattern" <<< "$src"; then ok "$desc"; else bad "$desc (missing: $pattern)"; fi
}
uses "detect_libcamera_version uses the helper" \
    'LIBCAMERA_VERSION=$(libcamera_installed_version)' "$DETECT_SRC"
uses "--uninstall floors the helper's version" \
    'CURRENT_VERSION=$(floor_libcamera_version "$(libcamera_installed_version)")' "$UNINSTALL_SRC"
uses "install.sh rebuild check floors the helper's version" \
    'CUR_LC_VER=$(floor_libcamera_version "$(libcamera_installed_version)")' "$(cat "$INSTALL")"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
