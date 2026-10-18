# PR #115 review — "camera-relay: add status-watch — event-driven JSON status feed"

VERDICT: CHANGES REQUESTED on `b24eb60` → **READY on `a712d6f`, MERGED, released as v0.3.83** (see Re-check at the end)

**Status (2026-10-18):** REQUEST_CHANGES review posted on head `b24eb60` using the
draft below, unchanged:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/115#pullrequestreview-5563830467>
(review 5563830467). @lautalom pushed `a712d6f` with F1 and N1–N4 fixed. It was
re-checked, approved, merged as `6ebbac2` and released as v0.3.83 (see the
Outcome line at the end). N5 (the test) is still ours to add on `main`.

Reviewed: 2026-10-18. Author: **@lautalom** (Lautaro Lombardi). Head `b24eb60`
(2 commits: `93902c8`, `b24eb60`), branch `camera-relay-status-watch`, based on
`4b2395a` (current `main`). `MERGEABLE` / `CLEAN`, no CI, no prior comments or
reviews. Maintainer edits allowed.
1 file: `camera-relay/camera-relay` +61/−0.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/115>

## What the PR does

Adds `camera-relay status-watch` (`cmd_status_watch`, new lines 1083–1140, plus
one `usage()` line and one `case` arm). It loops every 0.5 s and prints the
same JSON object that `status --json` prints, but only when that line differs
from the last one it printed. So a consumer gets one line on startup and then
one line per change to `running`, `persistent`, `camera`, `device` or `state`.

How each tick stays cheap:

- `running`: `is_running` on every tick.
- `persistent`: `is_persistent` (`systemctl --user is-enabled`) only on a
  running/stopped transition and every 10 ticks (~5 s).
- `camera` / `device`: read from `$CAMERA_CACHE` / `$DEVICE_CACHE` on every tick.
  It falls back to a live `detect_camera_name` / `detect_loopback_device` probe,
  which is re-run only on a running/stopped transition. This fixes the first
  commit's bug where the device was pinned before the first `start` (which loads
  v4l2loopback) and stayed "(not loaded)" forever.
- `state`: read from `$STATE_CACHE`, using the same rule as `cmd_status`: empty
  means "stopped", and not running always means "stopped".
- The line is built with `printf -v` and the same backslash escaping that
  `cmd_status` uses.

Intended consumers (from the PR body): desktop bars and scripts. The tray
change in #116 watches the runtime files directly and doesn't depend on this PR.

## What I verified

Research ran on copies in a scratch dir. The repo and the installed relay were
not touched. I re-ran #1 and #3 myself on this card against `git show pr-115:…`.

| # | Check | Result |
|---|---|---|
| 1 | Syntax | `bash -n` passes. |
| 2 | shellcheck 0.11.0 | The only new finding against `main` is **SC2006** at the help line (F1). |
| 3 | `camera-relay help` | **Broken**, see F1. |
| 4 | **Output vs `status --json`** | Scratch harness with fake runtime files and stubbed `systemctl`, `pw-cli` and `cam`, so the real launcher never opened the camera. Stepped through stopped → idle → streaming → persistent on → pid killed → state file removed. Every line was byte-identical to `status --json` at that moment, including the `\\_SB_.PC00.LNK0` backslash escaping. No duplicate lines in steady state. |
| 5 | Persistent flag | Re-checked on start/stop and every 10 ticks. In the harness a persistent toggle showed up within 5 s. |
| 6 | Camera/loopback caches | Read every tick and re-probed on start/stop. A watcher started before the first `start` picks up the device after it. |
| 7 | `set -e` / `pipefail` | Every read is guarded (`\|\| true`, `&&`). The `(( tick % 10 == 0 ))` inside `\|\|` and the `$running \|\|` tests can't trip `set -e`. |
| 8 | Exit | SIGTERM → rc 143. It creates no files, so there is nothing to clean up. |
| 9 | SIGPIPE | `status-watch \| head -1` exits 141 on the next write after `head` closes. No watcher is left behind. |
| 10 | Installers / packaging | Nothing new to copy. Both installers copy the whole script (`webcam-fix-libcamera/install.sh:2002`, `webcam-fix-book5/install.sh:1173`), and so does the Nix build (`nixos/webcam-fix-book5.nix:268`). No new dependencies: the loop uses `read`, `printf -v`, `sleep` and `kill`. |
| 11 | Docs | Neither README documents `status --json` (`webcam-fix-libcamera/README.md:70` lists only `status`), so no README change is needed. |

## Findings

### Changes requested

**F1. The backticks in the new help line run `status` as a command.**
`usage()` prints through `cat <<EOF` with an unquoted delimiter
(`camera-relay/camera-relay:1959` on the PR head, `:1900` on `main`). So the
new line 1969

```
  status-watch          Stream one `status --json` line per state change
```

is a command substitution. Running the PR copy:

```
$ ./camera-relay help 2>err.txt | grep status-watch
  status-watch          Stream one  line per state change
$ cat err.txt
./camera-relay: line 1959: status: command not found
```

shellcheck flags it as SC2006. `bash -n` can't catch it. Fix: drop the
backticks, e.g.

```
  status-watch          Stream status --json lines, one per change
```

### Non-blocking (optional)

**N1. Consumer list in the comment.** The block comment says "bars, scripts,
this package's own tray" and the first commit message says "the systray (next
change)". The PR body and #116 (open, head `4c932ff`) say the tray watches the
runtime files directly. Suggest dropping "this package's own tray". Neither PR
depends on the other.

**N2. "Effectively free" is strong.** Measured at about 0.9% of one core (18
CPU ticks per 20 s, with a stub `systemctl`; the real one costs more every 5 s).
One `status --json` costs about 20 ms CPU, so the old 5 s poll used about 0.4%.
Still cheap, just not free.

**N3. Torn state-file read.** The relay rewrites `$STATE_CACHE` with
`echo … >` (`camera-relay/camera-relay:856`, `:889`, `:932`, `:985`, `:989`),
which truncates the file first. A tick that reads it in that instant prints a
one-off `"running":true … "state":"stopped"` line, where `status --json` would
print `"state":""` (its `cat` succeeds on the empty file). Rare, but it's the
one place the "byte-compatible" claim doesn't hold. Fix: when running and the
read is empty, keep the last state instead of using "stopped".

**N4. A closed pipe is noticed only on the next write.** `| head -1` blocks
until the next change, and a watcher whose reader has died stays alive until
then. Normal for a stream, but worth a line in the comment or the help.

**N5. No test.** A `camera-relay/tests/test-status-watch.sh` modelled on the
harness (stubbed `systemctl`/`pw-cli`, temporary `XDG_RUNTIME_DIR`, compare
each line against `status --json`) would fit the existing `test-*.sh` set. We
could add it after merge.

### Already known, not this PR

On NixOS inside the service, `PID_FILE` uses `XDG_RUNTIME_DIR` while the caches
use `RUNTIME_DIRECTORY`. `status-watch` inherits that mismatch exactly as
`cmd_status` does. This is the deferred R-N1 item from #102, for
@ang3lo-azevedo's follow-up PR.

## Draft GitHub review comment (CHANGES REQUESTED)

> Thanks a lot @lautalom! This is a really nice addition. Bars and scripts no longer have to fork `status --json` on a timer, and the second commit's fixes are spot on, especially reading the camera/device caches each tick so a watcher started before the first `start` no longer shows "(not loaded)" forever.
>
> I ran the PR copy in a scratch harness: fake runtime files, stubbed `systemctl`/`pw-cli`/`cam`, so the real relay never opened the camera. I stepped it through stopped → idle → streaming → persistent on → pid killed → state file removed. **Every line was byte-identical to `status --json` at that moment**, including the `\\_SB_.PC00.LNK0` escaping, and there were no duplicate lines in steady state. That backs up your Book Pro 3 testing. A persistent toggle showed up within ~5 s, the caches were re-probed on start/stop, every read is safe under `set -e`/`pipefail`, SIGTERM exits 143 and `| head -1` exits 141 without leaving a watcher behind. The installers and the Nix build already copy the whole script, so nothing else needs to change.
>
> **One thing to fix before I merge.** `usage()` prints through `cat <<EOF` with an unquoted delimiter, so the backticks in the new help line are a command substitution and `camera-relay help` tries to run `status`:
>
> ```
> $ camera-relay help | grep status-watch
>   status-watch          Stream one  line per state change
> ```
> ```
> stderr: ./camera-relay: line 1959: status: command not found
> ```
>
> (shellcheck flags it as SC2006. It's the only new shellcheck finding against `main`.) Dropping the backticks fixes it, e.g.:
>
> ```
>   status-watch          Stream status --json lines, one per change
> ```
>
> **Optional, fine to merge without any of these:**
>
> - **N1:** the code comment lists "this package's own tray" as a consumer, but your PR description (and #116) say the tray watches the runtime files directly. Maybe drop that phrase so the comment matches.
> - **N2:** "effectively free" is a little strong. I measured about 0.9% of one core with a stub `systemctl` (the real one costs a bit more every 5 s), versus about 0.4% for the old 5 s `status --json` poll. Still cheap, just not free.
> - **N3:** the relay rewrites the state file with `echo … >`, which empties it for an instant. A tick that lands in that window prints a one-off `"running":true … "state":"stopped"` line, where `status --json` would print `"state":""`. Rare, and the only spot where "byte-compatible" doesn't strictly hold. Keeping the last state on an empty read would close it.
> - **N4:** like any stream, the watcher only notices a closed pipe on its next write, so `| head -1` blocks until the next change. Maybe worth a line in the comment.
> - **N5:** a `camera-relay/tests/test-status-watch.sh` (stubbed `systemctl`/`pw-cli`, temporary `XDG_RUNTIME_DIR`, compare each line against `status --json`) would fit the existing `test-*.sh` set. Happy to add that after merge if you'd rather not.
>
> Once the help line is fixed I'll merge and cut a release. Thanks again, really appreciate it!

## Next step on re-check

When @lautalom pushes the F1 fix:

1. `git fetch origin pull/115/head:pr-115` and confirm only the help line changed (`git diff b24eb60..pr-115`).
2. `bash -n`, and shellcheck with no SC2006 at the help line.
3. `camera-relay help | grep status-watch` shows the full sentence, with nothing on stderr.
4. Approve, merge, close, thank them in a comment, then release **v0.3.83**
   (`gh release create` on the merge commit) with notes describing
   `camera-relay status-watch`.
5. Optional follow-ups on `main`: N5 test, N3 empty-read fix, N1 comment.

## Re-check (2026-10-18): head `a712d6f`, verdict READY

@lautalom pushed `a712d6f` "camera-relay: status-watch review fixes" on top of
`b24eb60` and listed each fix in a comment (16:28Z). The commit touches only
`camera-relay/camera-relay` (+21/−9 over `b24eb60`; +73/−0 for the whole PR
against `main`). Research ran on copies in a scratch dir; I re-ran R1, R2 and R10
myself on this card against `git show a712d6f:…`.

| # | Check | Result |
|---|---|---|
| R1 | **F1 resolved** | `camera-relay help \| grep status-watch` prints `  status-watch          Stream status --json lines, one per change`, and stderr is 0 bytes. The only backticks left near it are in a code comment (line 1091), which is not in the heredoc. |
| R2 | Syntax | `bash -n` passes. |
| R3 | shellcheck 0.11.0 | 2 findings on the PR, 2 on `main`, same list, so the SC2006 at the help line is gone. |
| R4 | N1 | The comment no longer names the tray as a consumer and says it watches the runtime files directly. |
| R5 | N2 | Reworded to "Cheap at half-second cadence, though not free (about 1% of one core)". This run measured 17 CPU ticks per 10 s (18 per 20 s last time), so roughly 1–2% under harness noise; "about 1%" is fair. |
| R6 | N3 | New `prev_state`: if the state file exists but reads empty, the watcher keeps the previous state. A missing file still reports `stopped`, the same as `status --json`. Harness: emptied the file for 1.2 s while "streaming". The watcher printed nothing and kept `streaming`, while `status --json` at that moment printed `"state":""`. This is now the one place the two outputs deliberately differ. |
| R7 | N4 | A comment now says a closed reader is noticed only on the next write, so `\| head -1` blocks until the next change. |
| R8 | Harness re-run | Five transitions (stopped, idle, streaming, persistent on, pid killed) gave exactly five lines, each byte-identical to `status --json` at that step, including the `\\_SB_.PC00.LNK0` escaping. Removing the state file afterwards gave no extra line. |
| R9 | Unchanged behaviour | Persistent flag shows up within 5 s; SIGTERM → rc 143; `status-watch \| head -1` exits 141 on the next change. |
| R10 | File mode | Still `100755`. |
| R11 | Mergeable | `MERGEABLE` / `CLEAN`; a trial merge onto `origin/main` had no conflicts. `main` had only this review's two docs commits (`1fef553`, `ec3eb48`) past the PR's base. No CI. |
| R12 | N5 | No test added; left to us after merge, as offered. |

No new findings.

**Outcome (2026-10-18):** APPROVE review posted on `a712d6f`
(<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/115#pullrequestreview-5564025724>,
review 5564025724), replacing the CHANGES_REQUESTED review 5563830467. Merged with
a merge commit as `6ebbac2`. The PR fixes no issue, so nothing else closed. Tagged
`v0.3.83` on `6ebbac2` and released:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.83>.
Thank-you comment:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/115#issuecomment-6252809247>.
Open follow-up: N5, `camera-relay/tests/test-status-watch.sh`.
