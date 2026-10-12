# PR #110 review — "build-patched-libcamera: review follow-ups from #109"

VERDICT: READY TO MERGE — approved (not merged in this pass)

Reviewed: 2026-10-11. Author: **@david-bartlett** (David Bartlett, also #107 and
#109). Head `5905fcc` (1 commit), base `main` at `f857aab` (current tip, so no
merge-tree check needed), `MERGEABLE` / `CLEAN`, no CI, no prior comments or
reviews. Follow-up to the optional nits N1–N3 in `pr-109-review.md`, opened
unprompted the day after #109 merged.
1 file: `webcam-fix-book5/libcamera-bayer-fix/build-patched-libcamera.sh`
+16/−8.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/110>

## What the PR does

1. **N1, Koji download:** `curl -fL --retry 3` → `curl -fsSL --connect-timeout 20 --retry 3`.
2. **N2, unchecked `mv`:** the final `mv "$prepped_src" "$BUILD_DIR/libcamera"`
   in `prepare_srpm_source()` is now `if ! mv …; then error …; return 1; fi`.
3. **N3, "Check your network" on the wrong failure:** the hint moves onto the
   download error (`Could not download the libcamera source RPM (…). Check your
   network.`); the closing `die` becomes `Could not prepare the Fedora libcamera
   source RPM (see the error above). Nothing was changed.`
4. **Step 1 messages:** both "libcamera not found" `die`s (version detection,
   `find_libcamera_libs`) now say to run `install.sh` or install libcamera from
   the package manager, then re-run.
5. **Step 9 rewrite:** the old check was
   `find "$LIBCAMERA_LIB_DIR" -name 'libcamera.so.*' -newer "$BACKUP_DIR"`. The
   new one touches `$BUILD_DIR/.install-start` at the top of step 8 and runs
   `find -H "$LIBCAMERA_LIB_DIR" -name 'libcamera.so.*' -type f -cnewer "$BUILD_DIR/.install-start"`.
   Success message: `Verified: <lib> was installed by this run.`

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | File mode | `git ls-tree` on the head: `100755`. Diff header `index 51a1b1c..394dce0 100755`, no mode change. |
| 2 | curl flags | `-s` drops the progress meter, `-S` keeps the one-line error, `-f`/`-L` unchanged. Connect timeout (exit 28) is a transient error for `--retry`, so the worst case is about 4 × 20 s plus backoff, not a hang. `--connect-timeout` only bounds the connect phase (see O1). The `\|\| { rm -f …; warn …; }` fallback is unchanged. |
| 3 | `mv` error propagation | `prepare_srpm_source` is called from `if ! prepare_srpm_source`, so errexit is off inside it; the explicit `if ! mv; then error; return 1; fi` is the right fix and reaches the existing `rm -rf "$BUILD_DIR"; die` caller. |
| 4 | "(see the error above)" is true | Every `return 1` in `prepare_srpm_source` (not an RPM; download; unpack; no spec; `rpmbuild -bp`; tree not found; `mv`) prints an `error` line first. "Check your network" now only appears on the download failure. |
| 5 | Step 1 messages | Both paths `die` before step 2, so nothing is created. Reachable only by running the script directly: `install.sh` installs libcamera first on Fedora/Ubuntu/Arch. Wording note in O2. |
| 6 | **Old step 9 was always false** | Confirmed. The built library's mtime is its step-6 link time; step 7 then writes `$BACKUP_DIR/version`, so the backup dir is always newer, and `cp -a` / meson's `shutil.copy2` both preserve mtime. In the scratch test below the old `find` matched in **0 of 6** scenarios, including all real installs. |
| 7 | **New step 9 in a scratch tree**, run on tmpfs and on ext4 (`/var/tmp`), Fedora-style layout `lib64 -> usr/lib64` with the `libcamera.so → .so.0.7 → .so.0.7.2` symlink chain | `cp -a` into `/usr/lib64` → found. `cp -a` with libdir `/lib64` (symlink start point) → found, so `-H` is needed and works. `shutil.copy2` (what meson install uses) → found. No install → not found. Only the soname symlink re-created (what `ldconfig` does) → not found, so `-type f` correctly stops a symlink from "verifying". Missing marker → empty, no error (`2>/dev/null \|\| true`). Tight `touch marker; cp -a` loop with no gap, 200 iterations each on tmpfs and ext4: **0 false negatives** (kernel `CONFIG_HZ=1000`). |
| 8 | Where `LIBCAMERA_LIB_DIR` points | It can come from `ldd qcam` (Fedora prints `/lib64/…`, a symlink start point; Ubuntu prints `/lib/x86_64-linux-gnu/…`, where the symlink is a parent component and resolves without `-H`) or from the `/usr/local/…` → `/usr/lib` probe list. `detect_build_options` derives the meson prefix/libdir from the same variable, so full installs land in the dir step 9 searches. |
| 9 | Libraries-only path (unknown distros, openSUSE) | `cp -a` onto an existing target truncates and rewrites it, so the ctime changes and step 9 verifies it. The `INSTALLED_COUNT=0` fallback full-installs into the same prefix. |
| 10 | Marker lifetime | It lives in `$BUILD_DIR`, removed by the existing `rm -rf "$BUILD_DIR"` after step 9 and by the `rm -rf`/`mkdir` at the top of step 3. A failure in step 8 (e.g. `ninja install` under `pipefail`) leaves the build dir behind as it already did; no new files outside `$BUILD_DIR`. |
| 11 | Other distros | Steps 1 and 9 are shared, and are covered by rows 5–9. The other hunks are inside `prepare_srpm_source` / the Fedora branch. |
| 12 | `bash -n` | Passes on `main` and on the head. |
| 12 | shellcheck (`koalaman/shellcheck:stable`) | `main` 6 → head 6, same set (ignoring line numbers). **No new findings.** |
| 13 | Cost of the recursive `find` | No `-maxdepth`, as before. A full scan of `/usr/lib/x86_64-linux-gnu` (17,690 files) with no match takes 0.02 s. |
| — | Tests | No suite covers `webcam-fix-book5`. I didn't compile or install libcamera; the author reports full runs on Fedora 45, Ubuntu 26.04.1 and CachyOS, each ending in `Verified:`, plus the forced-failure and no-libcamera cases. |

## Findings

### Blocking

None.

### Non-blocking (mentioned in the review as optional; no follow-up needed)

**O1. `--connect-timeout` doesn't cover a stalled transfer.** A connection that
opens and then stops sending still waits forever. `--max-time 300` or
`--speed-limit 1024 --speed-time 30` would bound it. The SRPM is small and this
is the fallback after dnf, so it's unlikely.

**O2. "libcamera is not installed." is firmer than the check.** Step 1 only
asks pkg-config, `dpkg -l 'libcamera*'` (`libcamera0*`), `rpm -q libcamera` and
`pacman -Q libcamera`. A libcamera that is installed but none of those see (for
example a source build in `/usr/local` on Fedora, whose pkgconf path doesn't
include `/usr/local/lib64/pkgconfig`) gets told to install it. "Could not detect
an installed libcamera." would say only what the script knows. The
`find_libcamera_libs` message ("Cannot find libcamera.so.") is fine as is.

**O3 (note only). The `find` still recurses.** As with the old check, there's
no `-maxdepth 1`, so a `libcamera.so.*` file in a subdirectory whose ctime
changed during step 8 would also count. In the scratch tree a `chmod` on
`usr/lib64/sub/libcamera.so.9` did count. Nothing real lives there, so this is
theoretical; `-maxdepth 1` would make "installed by this run" exact.

## GitHub review (posted 2026-10-11 as APPROVE, review id 5485653386)

<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/110#pullrequestreview-5485653386>

> Thanks David! Following up on the #109 nits without being asked, and fixing
> the step 9 check while you were in there, is much appreciated. That's two
> careful PRs in two days.
>
> What I checked (I have no Book5 hardware, so this is static review plus a
> scratch test of the step 9 logic):
>
> - **N1–N3:** `-fsSL --connect-timeout 20 --retry 3` is right (`-S` keeps the
>   error line, and a connect timeout is retried). The `if ! mv …; return 1` is
>   the correct fix given errexit is off under `if !`. "Check your network" now
>   only shows on the download failure, and every `return 1` in
>   `prepare_srpm_source` prints its own error first, so "(see the error above)"
>   is true on every path.
> - **Step 9:** I rebuilt a Fedora-style tree (`lib64 -> usr/lib64`, with the
>   `.so → .so.0.7 → .so.0.7.2` chain) on tmpfs and on ext4. The old
>   `-newer "$BACKUP_DIR"` check matched in none of the cases, which confirms
>   your diagnosis. The new one finds the library after both `cp -a` and
>   `shutil.copy2` (what meson install uses), including when the start point is
>   the `/lib64` symlink. It stays silent when nothing was installed or only the
>   soname symlink changed, so `-type f` is doing its job. A tight
>   `touch marker; cp -a` loop gave 0 misses in 200 runs on each filesystem.
>   The marker lives in `$BUILD_DIR`, so the existing cleanup removes it.
> - **Static:** mode stays `100755`, `bash -n` passes, and shellcheck has the
>   same 6 findings before and after.
>
> Two optional thoughts, not blocking:
> - `--connect-timeout` doesn't cover a connection that opens and then stalls.
>   `--max-time 300` (or `--speed-limit`/`--speed-time`) would cover that if you
>   ever touch it again.
> - "libcamera is not installed." is a bit firmer than step 1 can know. It
>   only asks pkg-config/dpkg/rpm/pacman, so for example a `/usr/local` source
>   build on Fedora would be told to install it. "Could not detect an installed
>   libcamera." would hedge that.
>
> Approving. Thanks again!

## Housekeeping

- Head re-checked just before approving: still `5905fcc`, `MERGEABLE` / `CLEAN`,
  0 comments, 0 reviews.
- The head was fetched into `refs/remotes/pr/110` (never checked out over
  `main`), deleted afterwards. The scratch tree and harness lived only in the
  session scratchpad and a `/var/tmp` dir that was removed.
- **Not merged** in this pass; merge + release are a separate step.
