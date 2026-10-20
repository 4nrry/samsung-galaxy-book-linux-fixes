# PR #124 review — "camera-relay-monitor: let STREAMON decide on v4l2loopback 0.13+ (#118)"

VERDICT: **READY TO MERGE** on `53b54c8` (no blockers, no requested changes) → **APPROVED, MERGED as `be70ad7`** (see Outcome at the end)

**Status (2026-10-20):** approved with a thank-you (review 5593270121) and
merged with a merge commit as `be70ad7`, like #114–#117, #121 and #122. #118
auto-closed. Review nits 1 and 2 fixed on `main` in `02eb997`. Released as
**v0.3.91**.

Reviewed: 2026-10-20. Author: **@lautalom** (Lautaro Lombardi), the 5th PR
after #112, #115, #116 and #117. Head `53b54c8`, 2 commits (`92497ef`,
`53b54c8`), +101/−22 in `camera-relay/camera-relay-monitor.c` and
`camera-relay/camera-relay`. Based on `main` `5e397bd` (v0.3.90),
`MERGEABLE` / `CLEAN`. No CI, no prior comments or reviews. Fixes #118
("PipeWire holding the loopback open keeps the camera streaming with no app"),
opened by the same author.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/124>

## What the PR does

It follows the direction agreed in #118
([issuecomment-6255070866](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/118#issuecomment-6255070866))
point by point:

- **v4l2loopback 0.13+:** a new `count_readers()` returns `reader_streaming`
  only, so STREAMON/STREAMOFF alone decide whether a reader exists. An fd that
  is merely open (PipeWire's suspended mirror node after a failed start, a
  scanner probing formats) no longer starts the pipeline or keeps it alive.
- **0.12.x and no events:** unchanged; still `count_other_openers()` from
  `/proc` plus `streaming`.
- **PipeWire:** not special-cased. When a browser really uses the camera
  through it, PipeWire issues STREAMON like any other reader.
- **`camera-relay doctor`:** a new `list_loopback_holders` lists the processes
  holding the loopback and marks the relay's own.
- The monitor logs readers/streaming when it stops the pipeline.

The author tested all four cases we asked for: the original bug, a live browser
call through PipeWire, a plain camera app, and the 0.12.x path. Two caveats:
the 0.12 case ran with events forced off on a 0.15.4 kernel rather than on
real 0.12 hardware, and the browser call lasted only about 7 s.

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | `count_readers()` at every call site | IDLE event path, IDLE poll fallback, RELAY idle check, post-stop restart check. With `usage_authoritative` set each returns `reader_streaming`; otherwise `count_other_openers()+streaming`. On 0.12 `note_usage_event` only records the NEW event, so `streaming` stays 0 and the old `clients>0 \|\| reader_streaming` / `count+reader_streaming` expressions give the same result as before. The pure `/proc` path (no events) is untouched. |
| 2 | PR #105 ordering rules | `_NEW` is subscribed before `_OLD`; `reader_streaming = 0` happens before the re-subscribe; `usage_authoritative` is recomputed after it. A failed re-subscribe sets `event_type=0` and falls back to `/proc`. |
| 3 | Kernel side | Checked in the v4l2loopback source (local 0.15.3, upstream v0.13.0, v0.13.2, v0.14.0). 0.14+ queues the usage event on STREAMON, STREAMOFF, `close()` (via REQBUFS(0)→streamoff) and `read()` I/O (`start_fileio`→streamon), so a reader that crashes still clears `streaming`. The queue holds one element and each new event replaces the old one, so draining always gives the latest state. |
| 4 | 10 s "never saw a client" rule | Still correct. On 0.13+ it only fires if the reader stops streaming before the first ~1 s check. |
| 5 | Build and tests | `gcc -Wall -Wextra` builds with no warnings, `bash -n` passes, all 13 suites in `camera-relay/tests/` pass on the PR tree (launcher-validation 33/33, monitor-exit-propagation 5/5). |
| 6 | Doctor | `list_loopback_holders` under `set -euo pipefail` on this machine printed `4592 camera-relay-mo (camera-relay)`, rc=0. It uses `find -lname`, not lsof/fuser, so there is no "tool missing" case. A missing PID file is handled by `read … \|\| true`. |
| 7 | Installers | Nothing to change. `webcam-fix-book5/install.sh`, `webcam-fix-libcamera/install.sh` and `nixos/webcam-fix-book5.nix` all compile the monitor from source, so users get the fix by re-running the installer (or rebuilding on NixOS) after a tagged release. |

## Findings

None block the merge.

**1. Doctor can abort in a rare race** (`camera-relay/camera-relay:275` on the
PR tree). `ppid=$(awk … "/proc/$ppid/status")` exits 2 if the process exits
between `find` and `awk`. Under `set -e` that aborts the subshell, and with
pipefail `list_loopback_holders | sed` (`:1467`) then aborts the whole doctor
report. Fix: `|| ppid=""`. → **Fixed in `02eb997`.**

**2. 0.13.0–0.13.x only: readers using `read()` I/O never fire the event**
(`camera-relay-monitor.c:295`). Those versions only queue it from
`vidioc_streamon`, so such a reader would no longer start the relay; 0.14+ is
fine. Mainstream readers (GStreamer, ffmpeg, Chromium, OBS, PipeWire) use mmap,
so this is documentation only. → Not changed in code.

**3. Stale comment** (`camera-relay-monitor.c:593`): "Verify via /proc —
PipeWire briefly opens…" no longer describes the 0.13+ path. Cosmetic.
→ **Fixed in `02eb997`.**

**4. Truncated names in doctor:** `/proc/PID/comm` cuts names to 15 characters
(`camera-relay-mo`). Cosmetic and acceptable. → Left as is.

## GitHub review comment (APPROVE)

> Thanks @lautalom — this is exactly the direction we agreed in #118, and it's clean. Approving.
>
> **What I checked**
> - `count_readers()` at all its call sites (IDLE event path, IDLE poll fallback, RELAY idle check, post-stop restart check). With `usage_authoritative` set it returns `reader_streaming`; otherwise it returns `count_other_openers() + streaming`, and on 0.12 `streaming` stays 0, so the old expressions give the same result as before. The /proc-only path (no events) is untouched.
> - The PR #105 ordering rules still hold: `_NEW` is subscribed before `_OLD`, `reader_streaming = 0` happens before the re-subscribe, and `usage_authoritative` is recomputed afterwards. A failed re-subscribe falls back to /proc.
> - Kernel side, against v4l2loopback 0.13.0 / 0.13.2 / 0.14.0 / 0.15.3: on 0.14+ the usage event fires on STREAMON, STREAMOFF, `close()` and `read()` I/O, so a crashed reader still clears `streaming`. The queue holds one element, so draining always gives the latest state.
> - `gcc -Wall -Wextra` builds with no warnings, `bash -n` passes, and all 13 suites in `camera-relay/tests/` pass on this tree.
> - `camera-relay doctor` lists the holder correctly under `set -euo pipefail`.
>
> **Optional follow-up nits (none blocking):**
> 1. `camera-relay:275`: if a holder exits between `find` and `awk`, the `awk … /proc/$ppid/status` call fails, and under `set -e` plus pipefail that aborts the whole doctor report. `|| ppid=""` fixes it.
> 2. `camera-relay-monitor.c:593`: the "Verify via /proc — PipeWire briefly opens…" comment no longer describes the 0.13+ path.
> 3. Only on 0.13.x: readers that use `read()` I/O never fire the event, because those versions queue it only from `vidioc_streamon`. Mainstream readers all use mmap, so a note in a comment is enough.
>
> One request: when you get a chance, could you confirm that a longer browser call (a few minutes rather than ~7 s) keeps the relay up and then stops it cleanly afterwards?
>
> That's your fifth merged PR here (#112, #115, #116, #117 and now #124). Thank you!

## Outcome

**Outcome (2026-10-20):** Head re-confirmed as `53b54c8`, `MERGEABLE` /
`CLEAN`, just before approving. APPROVE review posted using the comment above:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/124#pullrequestreview-5593270121>
(review 5593270121, 23:56:05Z). Merged with a merge commit
(`--match-head-commit 53b54c8`) as `be70ad7` at 23:56:10Z. #118 auto-closed
via "Fixes #118" at 23:56:12Z.

Follow-up on `main`: `02eb997` "fix: Harden doctor holder walk and refresh the
0.13+ comment (#118)" fixes nits 1 and 2 of the posted review (findings 1 and
3 above). Before the fix, a stubbed `awk` that exits 2 made the doctor report
stop after "open by:" with rc=2; after it, the report completes with rc=0.
`gcc -Wall -Wextra` is clean, `bash -n` passes, all 13 `camera-relay/tests/`
suites pass, and `camera-relay doctor` on this machine lists
`4592 camera-relay-mo (camera-relay)` with rc=0. Review nit 3 (0.13.x
`read()` I/O) is not in a code comment yet.

Released as **v0.3.91**, titled "camera-relay stops when PipeWire only holds
the loopback open (#118)". The notes tell existing users to re-run the webcam
installer (NixOS: rebuild) and say the `systemctl --user restart pipewire`
workaround is no longer needed:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.91>.

Still open: lautalom's confirmation of a multi-minute browser call.
