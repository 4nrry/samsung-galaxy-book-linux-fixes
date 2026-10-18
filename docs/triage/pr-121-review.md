# PR #121 review — "build-patched-libcamera.sh: pick the newest installed libcamera on Debian/Ubuntu"

VERDICT: **READY TO MERGE** on `f128abe` (no blockers; findings 1–4 are notes) → **APPROVED, MERGED as `461852f`** (see Outcome at the end)

**Status (2026-10-18):** approved with a thank-you (review 5564751634) and
merged with a merge commit as `461852f`, like #114–#117. #119 auto-closed.
Released as **v0.3.86** on `461852f`.

Reviewed: 2026-10-18. Author: **@david-bartlett** (David Bartlett), after
#107, #109, #110 and the #111 presets. Head `f128abe`, 1 file, +2/−2:
`webcam-fix-book5/libcamera-bayer-fix/build-patched-libcamera.sh`.
`MERGEABLE` / `CLEAN` against `main` `c209c34` (v0.3.85). No CI, no prior
comments or reviews. Fixes #119 ("webcam-fix-book5 builds the wrong libcamera
version on Debian / MX Linux"), opened by the same author.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/121>

## What the PR does

Both `dpkg` version checks in `build-patched-libcamera.sh` change from
`head -1` to `sort -V | tail -1`:

- `:147`, in `--uninstall` (`CURRENT_VERSION`, used for the stale-backup check);
- `:264`, in `detect_libcamera_version` (`LIBCAMERA_VERSION`, the version that
  gets built).

`dpkg -l` lists packages by name, so with both `libcamera0.4` and
`libcamera0.7` installed (Debian 13 stable + `trixie-backports`), `head -1`
returned 0.4.0 and the script built and installed a patched 0.4.0 over the
distro's files. 0.4.0 can't see the IPU7 camera. With one `libcamera0.*`
package installed the result is the same as before.

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | `sort -V` ordering | GNU `sort -V` on real strings: `0.2.0-3fakesync1build1 < 0.4.0-7 < 0.7.1 < 0.7.1-1~bpo13+1 < 0.7.1-1 < 0.10.0-1`. The packages differ by soname (major.minor), so only that part has to compare right. It also covers a future `libcamera0.10`, which `head -1` would get wrong because names sort alphabetically. libcamera packages carry no epoch. `rc` packages are still dropped by `^ii`; multiarch duplicates have the same version. |
| 2 | Matches `install.sh` | `webcam-fix-book5/install.sh:64,79,540` and `webcam-fix-libcamera/install.sh:704` already use `sort -V \| tail -1`. Repo grep for the dpkg `libcamera0 … head -1` pattern: lines 147 and 264 were the only two. The Fedora `rpm -q` lines query one package, so `head -1` is fine there. |
| 3 | `set -euo pipefail` | `sort` and `tail` read all their input, so nothing upstream gets SIGPIPE (the `grep -q` problem doesn't apply). Empty input: empty result, status 0, and `\|\| true` still covers it. |
| 4 | 0.7.2 floor from #71 (`:303-312`) | Runs after detection, so a correctly detected 0.7.0 is still built as v0.7.2. The author's Ubuntu 26.04.1 run confirms it. |
| 5 | Merge state | `MERGEABLE` / `CLEAN`; the diff is exactly the two lines. |
| 6 | Hardware | Not tested here. The author reports MX Linux 25.3 and Debian 13.7 (Secure Boot on) on a Book5 Pro 940XHA with both packages installed: built `0.7.1+dirty`, qcam and camera-relay working with correct colours. Ubuntu 26.04.1 with only `libcamera0.7`: unchanged. |

## Findings

None block the merge.

**1. Ubuntu upgraders benefit too.** Andy's Ubuntu 26.04 box still has
`libcamera0.2 0.2.0-3fakesync1build6` from the 24.04 upgrade next to
`libcamera0.7 0.7.0-1ubuntu2`. The old pipeline returns `0.2.0-…`, the new one
`0.7.0-1ubuntu2`. On that box `pkg-config` (checked first, `:258-260`) masks it
because the patched build's `.pc` file reports 0.7.2. But `install_deps_debian`
(`:317`) doesn't install `libcamera-dev`, so on a first install without it the
dpkg branch runs, and any 24.04 → 26.04 upgrader would have hit #119 too.

**2. Uninstall recovers the #119 state (good side effect).** A Debian user who
installed with the old script has `/var/lib/libcamera-bayer-fix-backup/version`
= `0.4.0`. After this fix `--uninstall` sees 0.7.1, sets `STALE_BACKUP=true`,
skips the restore, removes unowned files and reinstalls the distro libcamera.
That is the right recovery for the overwritten dpkg files. (This holds when
`pkg-config` finds no `libcamera.pc`. If the wrong build left a 0.4.0 `.pc`,
`pkg-config` reports 0.4.0, the backup matches and the normal restore path
puts the original 0.4.0 files back and removes unowned files. Also correct.)

**3. Gap not covered by the PR (follow-up candidate).** If a Debian user has
the stable `libcamera-dev` (0.4.0) installed, `pkg-config` wins at `:260` and
still reports 0.4.0, so the dpkg branch never runs.

**4. Other items in #119 are separate:** the `v4l2loopback-dkms` 0.15.0 build
failure on kernel ≥ 6.19 (0.15.4 works), `v4l-utils` not installed by default
(15 s loopback-format wait), stray IPA `.so` files left in
`…/libcamera/` instead of `…/libcamera/ipa/` by the wrong 0.4.0 build, and
`install.sh` printing "Ubuntu detected" on Debian/MX. Follow-up candidates.

## GitHub review comment (APPROVE)

> Thanks a lot @david-bartlett! The root cause in #119 was spot on and made this an easy review: `dpkg -l` lists by name, so with `libcamera0.4` and `libcamera0.7` both installed `head -1` picks the oldest one. Switching to `sort -V | tail -1` matches what `install.sh` already does, and testing on both MX Linux 25.3 and Debian 13.7 (with Secure Boot on) plus the Ubuntu 26.04.1 check for the single-package case is really appreciated.
>
> This helps Ubuntu users too. A 24.04 → 26.04 upgrade leaves `libcamera0.2` installed next to `libcamera0.7`, and since the build script doesn't install `libcamera-dev`, the dpkg branch runs on a first install and the old code would pick 0.2.0 there. The uninstall path also gets better for anyone who already hit #119: the backup says 0.4.0, the script now sees 0.7.1, so it treats the backup as stale and reinstalls the distro libcamera instead of restoring the wrong files.
>
> One related gap the PR doesn't cover, and doesn't need to: if a Debian user has the stable `libcamera-dev` (0.4.0) installed, `pkg-config` is checked first and still reports 0.4.0. That and the other Debian notes in #119 (`v4l-utils`, the v4l2loopback 0.15.0 build failure, the stray IPA files, "Ubuntu detected") are good follow-up candidates. Thanks for writing them all up.
>
> Merging now. It'll go out in the next release. Thanks again!

## Outcome

**Outcome (2026-10-18):** Head re-confirmed as `f128abe`, `MERGEABLE` / `CLEAN`,
just before approving. APPROVE review posted using the comment above, unchanged:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/121#pullrequestreview-5564751634>
(review 5564751634). Merged with a merge commit (`--match-head-commit f128abe`)
as `461852f` at 20:14:33Z. #119 auto-closed via "Fixes #119" at 20:14:35Z.
After the merge, lines 147 and 264 on `main` use `sort -V | tail -1`, no
dpkg `libcamera0 … head -1` remains, and the script passes `bash -n`.

Released as **v0.3.86** on `461852f`, titled "Book5 webcam fix builds the right
libcamera when several versions are installed". The notes cover the Ubuntu
24.04 → 26.04 case (finding 1), `--uninstall` then `./install.sh` for users
who already have the wrong 0.4.0 build, and finding 3 and the other #119 items
as known gaps:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.86>.

**Still open (follow-up candidates, no issue filed yet):** finding 3
(stale stable `libcamera-dev` makes `pkg-config` win at `:260`), and the #119
Debian items in finding 4 (detect Debian separately from Ubuntu, add
`v4l-utils` to the deps, v4l2loopback ≥ 0.15.4 note, stray IPA files).
