#!/bin/bash
# install-presets.sh
# Copies the GalaxyBook EasyEffects output presets into your EasyEffects
# preset folder(s): native EasyEffects 8+, native EasyEffects 7 (if its old
# folder is in use) and the Flatpak, whichever are present.
#
# It never overwrites a preset you have changed unless you pass --force (the
# old file is then kept as <name>.json.bak). It doesn't change EasyEffects'
# autoload rules or load a preset — it prints how to do that instead.
#
# Usage: ./install-presets.sh [--force | --uninstall]
#   --force      replace differing presets of the same name (backed up as .bak)
#   --uninstall  remove these presets again, if they are unchanged
#
# Run as your normal user, NOT with sudo — presets live in your home folder.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESETS=(
    GalaxyBook-Speakers-Warm.json
    GalaxyBook-Speakers-Warm-Loud.json
    GalaxyBook-Speakers-Clear.json
    GalaxyBook-Speakers-Clear-Loud.json
    GalaxyBook-Headphones.json
)
FLATPAK_ID="com.github.wwmm.easyeffects"

MODE=install
case "${1:-}" in
    "")          ;;
    --force)     MODE=force ;;
    --uninstall) MODE=uninstall ;;
    -h|--help)   sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

echo "=== GalaxyBook EasyEffects Presets ==="
echo ""

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Don't run this with sudo — it would install into root's home folder." >&2
    echo "       Run it as your normal user: ./install-presets.sh" >&2
    exit 1
fi

for p in "${PRESETS[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$p" ]; then
        echo "ERROR: $p not found next to this script ($SCRIPT_DIR)." >&2
        exit 1
    fi
done

# --- Find the preset folders that apply ---
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
FLATPAK_HOME="$HOME/.var/app/$FLATPAK_ID"
TARGETS=()

if command -v easyeffects >/dev/null 2>&1; then
    # EasyEffects 8+ keeps presets in ~/.local/share; 7.x used ~/.config.
    # Only use the old folder if it still exists (8.x moves it on first start).
    TARGETS+=("$DATA_HOME/easyeffects/output")
    [ -d "$CONFIG_HOME/easyeffects/output" ] && TARGETS+=("$CONFIG_HOME/easyeffects/output")
fi
if { command -v flatpak >/dev/null 2>&1 && flatpak info "$FLATPAK_ID" >/dev/null 2>&1; } \
        || [ -d "$FLATPAK_HOME" ]; then
    TARGETS+=("$FLATPAK_HOME/data/easyeffects/output")
    [ -d "$FLATPAK_HOME/config/easyeffects/output" ] && TARGETS+=("$FLATPAK_HOME/config/easyeffects/output")
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    if [ "$MODE" = uninstall ]; then
        echo "EasyEffects not found — nothing to remove."
        exit 0
    fi
    echo "ERROR: EasyEffects is not installed (neither the native package nor the Flatpak)." >&2
    echo "" >&2
    echo "Install it first, then run this script again:" >&2
    echo "  Ubuntu / Debian:          sudo apt install easyeffects" >&2
    echo "  Fedora:                   sudo dnf install easyeffects" >&2
    echo "  Arch / CachyOS / Manjaro: sudo pacman -S easyeffects" >&2
    echo "  Flatpak:                  flatpak install flathub $FLATPAK_ID" >&2
    exit 1
fi

# --- Uninstall ---
if [ "$MODE" = uninstall ]; then
    for dir in "${TARGETS[@]}"; do
        echo "$dir"
        for p in "${PRESETS[@]}"; do
            dst="$dir/$p"
            [ -e "$dst" ] || continue
            if cmp -s "$SCRIPT_DIR/$p" "$dst"; then
                rm -f "$dst"
                if [ -f "$dst.bak" ]; then
                    mv "$dst.bak" "$dst"
                    echo "  removed   ${p%.json} (restored your previous version from .bak)"
                else
                    echo "  removed   ${p%.json}"
                fi
            else
                echo "  kept      ${p%.json} (you have changed it)"
            fi
        done
    done
    echo ""
    echo "=== Uninstall complete ==="
    echo "If one of these presets is set in Presets -> Autoload, remove that rule too."
    exit 0
fi

# --- Install ---
SKIPPED=0
for dir in "${TARGETS[@]}"; do
    echo "$dir"
    mkdir -p "$dir"
    for p in "${PRESETS[@]}"; do
        src="$SCRIPT_DIR/$p"
        dst="$dir/$p"
        if [ ! -e "$dst" ]; then
            cp "$src" "$dst"
            echo "  installed ${p%.json}"
        elif cmp -s "$src" "$dst"; then
            echo "  ok        ${p%.json} (already up to date)"
        elif [ "$MODE" = force ]; then
            cp "$dst" "$dst.bak"
            cp "$src" "$dst"
            echo "  replaced  ${p%.json} (your old version is saved as $p.bak)"
        else
            echo "  skipped   ${p%.json} (a different version is already there)"
            SKIPPED=1
        fi
    done
done

echo ""
echo "=== Install complete ==="
if [ "$SKIPPED" -eq 1 ]; then
    echo ""
    echo "Some presets were skipped because you already have a different file with"
    echo "the same name. To replace them (your versions are kept as .bak), run:"
    echo "  ./install-presets.sh --force"
fi
cat <<'EOF'

Next steps (nothing has been loaded or changed in EasyEffects yet):

  1. Restart EasyEffects (tray icon -> Quit, then start it again) so it sees
     the new presets.
  2. Presets -> Output: load GalaxyBook-Speakers-Warm (or -Clear) to try it.
  3. To switch automatically between speakers and headphones, open
     Presets -> Autoload and add one rule per output device:
       Device = the built-in "Speaker" output -> GalaxyBook-Speakers-Warm-Loud
                (or whichever speaker preset you like best)
       Device = your headphones              -> GalaxyBook-Headphones
     Then turn off the Fallback Preset (or set it to a flat preset) so HDMI and
     other outputs play unprocessed.

The presets need the Calf and LSP plugins. If EasyEffects shows an effect as
"Not Available", see easyeffects-presets/README.md.
EOF
