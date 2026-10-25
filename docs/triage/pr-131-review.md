# PR #131 review — "docs: Add OLED screen mode ICC profile generator and guide (SDC4188)"

VERDICT: **MERGED** 2026-10-25 (4247877) on head `d164aa2`; approve review 5645859216:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/131#pullrequestreview-5645859216>

Author: **@4nrry** (Anrry Petrin, NP960XGL-XG1BR — same author as #77/#128/#129). 1 commit,
`CONFLICTING` only because #129's README entry landed in the same spot; resolved locally by keeping
both (Performance Modes, then Screen Modes). +350/−0:

- `README.md` +7: "OLED Screen Modes & ICC Profiles" entry under "What's Included"
- `docs/gen_icc.py` +208 (mode 755): ctypes/liblcms2 ICC generator, `--edid` reads eDP EDID
- `docs/screen-modes.md` +135: ColorEngine reverse engineering, KDE/GNOME setup, KWin emulation math

## What was verified (on Andy's NP960XGL-XG1US, Ubuntu 26.04.1, kernel 7.0, KWin 6.6.6)

- Same panel: `--edid` finds `card1-eDP-1`, prints `SDC4188 (ATNA60CL07-0)`, EDID white
  `(0.3047, 0.3213)` as the doc says. All 8 profiles written, exit 0.
- Math, KWin model sRGB → `inv(P)` → panel `N`: default (D65) set is exact — written p3/adobergb
  matrices equal `P = S·inv(T)·N` to 1e-15, emitted sRGB white = D65.
- Profiles NOT switched on Andy's display; MHC2 comparison not checkable (no Samsung .icm here).

## Non-blocking nits posted (for a follow-up PR from the author)

1. Files are ICC **v4.4** (header `04400000`), not "ICCv2" as README/guide say.
2. `-edid` set: `P*[1,1,1] = N*[1,1,1]` only holds for a D65 panel white. P's white is
   (0.3057, 0.3219)/(0.3058, 0.3216) vs panel (0.3047, 0.3213); writing with panel white rescales
   the primaries (matrix off by ≤0.007), and sRGB white lands at ≈(0.314, 0.330).
3. GNOME untested? Older Mutter only applied `vcgt`; these profiles have none.
4. `sdc4188-*` names / "Galaxy Book4 Ultra" labels on other panels; raw traceback if lcms2
   missing; `cmsSaveProfileToFile` return unchecked.

No release tag: docs + an optional userspace script only; bundle into the next tag (main now has
#129 + #131 unreleased since v0.3.93).
