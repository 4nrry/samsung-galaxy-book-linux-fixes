# PR #117 review — "camera-relay-gst: add --pw-publish — publish the camera as a native PipeWire source"

VERDICT: **READY TO MERGE** on `e2b7341` (no blockers; finding 1 is a nit, 2–3 are notes) → **APPROVED, MERGED as `2929af2`** (see Outcome at the end)

**Status (2026-10-18):** approved with a thank-you (review 5564610666) and
merged with a merge commit as `2929af2`, like #114–#116. Finding 1 fixed on
`main` in `f6eae08`, released as **v0.3.85** on `f6eae08`.

Reviewed: 2026-10-18. Author: **@lautalom** (Lautaro Lombardi), their fourth PR
in a row after #112, #115 and #116. Head `e2b7341` (2 commits: `4b80b4f`, and
`e2b7341`, which is authored as "Claude" from their own session), branch based
on `4b2395a`. `MERGEABLE` / `CLEAN`, and `git merge-tree` against current
`main` (`ccbd177`, which includes #116 and its follow-up) is clean too. No CI,
no prior comments or reviews.
3 files, +128/−16: `camera-relay/camera-relay`, `camera-relay/camera-relay-gst.c`,
`camera-relay/tests/test-launcher-validation.sh`.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/117>

The author also opened issue #118 ("PipeWire holding the loopback open keeps
the camera streaming"). That is separate and not part of this PR.

## What the PR does

Adds an opt-in `--pw-publish` flag to the setgid launcher.

- **Script side** (`camera-relay/camera-relay:48-55`, in `build_launcher_args`):
  `RELAY_PW_PUBLISH=1` in the service environment appends `--pw-publish`.
  `build_launcher_args` is called on all three start paths (background start
  L605, foreground start L868, on-demand daemon L952).
- **Launcher side** (`camera-relay/camera-relay-gst.c`): with the flag, the
  pipeline forks after the caps step:

  ```
  … ! caps ! tee name=relayed ! queue ! <v4l2sink|fdsink> … sync=false
      relayed. ! queue max-size-buffers=3 leaky=downstream !
        pipewiresink mode=provide
          stream-properties=props,media.class=(string)Video/Source,node.name=(string)camera-relay
          sync=false
  ```

  It also adds `XDG_RUNTIME_DIR=/run/user/<getuid()>` to the rebuilt
  environment, only when the flag is on, so `pipewiresink` can find the
  session socket.
- `TAIL_SLOTS` goes from 9 to 24 to fit the longer tail.
- Without the flag, the pipeline and the environment are byte-for-byte the
  same as before. A new test checks that.

## What I verified

On a `git archive` copy of `pr-117` in the scratchpad. The repo and the
installed relay were not touched.

| # | Check | Result |
|---|---|---|
| 1 | `camera-relay/tests/test-launcher-validation.sh` | **33/33 pass**, including the 3 new `--pw-publish` checks and the ASan sweep over all four sink paths (v4l2/fd × with/without `--pw-publish`). |
| 2 | Mutation: `TAIL_SLOTS` 24 → 23 | Caught: `--v4l2-sink with 16 filters — sanitizer report` (32 passed, 1 failed). The second commit switched the sweep to the stubbed launcher; before that, without `gst-launch-1.0` installed, the real launcher died before building the tail and the sweep tested nothing. |
| 3 | `TAIL_SLOTS` count | Tail is 22 tokens + NULL = 23, +1 because one `append_color_filter` loop step adds two entries = **24**. Correct. |
| 4 | `env[12]` / `buf[6]` | At most 9 entries + NULL in the setgid build, 11 on Nix with the user-cache entries. `buf` use is at most 5. In bounds. |
| 5 | Compile | Clean with `gcc -Wall -Wextra`, and with `-DCAMERA_RELAY_USER_CACHE` (the Nix build). `bash -n camera-relay/camera-relay` passes. |
| 6 | NixOS `substituteInPlace` (`nixos/webcam-fix-book5.nix:227-245`) | All five `--replace-fail` targets are still present verbatim in the PR's `camera-relay-gst.c`, so the Nix build still patches. |
| 7 | `pipewiresink` properties | `mode=provide` and `stream-properties` both exist (GStreamer 1.28.2). |
| 8 | `XDG_RUNTIME_DIR` | Built from `getuid()`, never read from the caller. The test confirms a caller's `XDG_RUNTIME_DIR=/tmp/evil` does not get through. |
| 9 | Loopback can't stall | The PipeWire branch queue is `leaky=downstream` with `max-size-buffers=3`, so a missing or stalled PipeWire consumer drops frames on that branch instead of blocking the tee. |
| 10 | Style | Matches the existing `[[ … ]] && LAUNCHER_ARGS+=` pattern and the comment density of the launcher. |
| 11 | Hardware | Not tested here (no Book3 hardware). The author reports a Book3 Pro: 30 fps on both the PipeWire node and `/dev/video0`, no freeze with or without a PipeWire reader. |

## Findings

None block the merge.

**1. Nit: the tighter colour-filter limit applies to everyone, not just
`--pw-publish` users.** `TAIL_SLOTS` went from 9 to 24 for all builds, so
with `MAX_ARGS 64` (`camera-relay-gst.c:54`) and a 10-slot head,
`RELAY_COLOR_FILTER` now gets 30 argv slots instead of 45. Real filters use
about 5 tokens, so nobody is affected. Follow-up on `main`: raise `MAX_ARGS`
to 79 so the old limit comes back.

**2. Note only, not new exposure.** With the flag on, libpipewire may read
`$HOME/.config/pipewire/client.conf`, and in the setgid build `HOME` is
`/var/cache/camera-relay` (mode 2770, group-writable). Group members can
already plant a bad `gst-registry.bin` in that same directory, so the trust
boundary doesn't change.

**3. Note: undocumented, like the other relay settings.** Neither
`RELAY_PW_PUBLISH` nor `RELAY_COLOR_FILTER` is in `camera-relay/README.md`;
both are documented only in comments in the script. The NixOS module doesn't
expose the flag. The author already lists the limitations in the PR: in
on-demand mode the node only exists while something reads the loopback, and
Chrome shows two cameras.

## GitHub review comment (APPROVE)

> Thanks a lot @lautalom, that's four in a row after #112, #115 and #116. Really appreciate it!
>
> This is a nice, careful change. It's opt-in: without `RELAY_PW_PUBLISH=1` the launcher builds exactly the same pipeline and environment as before, and the new test checks that. The leaky queue on the PipeWire branch means a missing or stalled PipeWire consumer drops frames on that branch instead of blocking the tee and freezing the loopback. `XDG_RUNTIME_DIR` is built from the real uid instead of being taken from the caller, which is the right call for a setgid binary. Switching the argv-boundary sweep to the stubbed launcher is a real fix too: before, the sweep could pass without building the tail at all. With it, `TAIL_SLOTS` set one short is caught under ASan (we checked by setting it to 23).
>
> One small follow-up we'll do on `main` ourselves: `TAIL_SLOTS` going from 9 to 24 applies to every build, so `RELAY_COLOR_FILTER` now gets 30 argv slots instead of 45. Real filters use about 5, so nobody is affected, but we'll raise `MAX_ARGS` to bring the old limit back.
>
> Merging now. It'll go out in the next release. Thanks again!

## Follow-up on `main`

1. Finding 1: raise `MAX_ARGS` in `camera-relay/camera-relay-gst.c:54` from 64
   to 79, then re-run `camera-relay/tests/test-launcher-validation.sh`.
2. Optional: document `RELAY_PW_PUBLISH` (and `RELAY_COLOR_FILTER`) in
   `camera-relay/README.md`.
3. Release **v0.3.85** covering #117 and the follow-up (check
   `gh release list` first; v0.3.84 is the latest).

**Outcome (2026-10-18):** Head re-confirmed as `e2b7341`, `MERGEABLE` / `CLEAN`,
just before approving. APPROVE review posted using the comment above, unchanged:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/117#pullrequestreview-5564610666>
(review 5564610666). Merged with a merge commit (`--match-head-commit e2b7341`)
as `2929af2` at 19:32:16Z. The PR fixes no issue, so nothing else closed; #118
is handled separately.

**Follow-up and release (2026-10-18):** Item 1 done in `f6eae08`: `MAX_ARGS`
64 → 79 (head 10 + filter 45 + `TAIL_SLOTS` 24), with a comment saying so. The
argv-boundary sweep now also leads with a three-slot stage
(`videobalance saturation=1`), because a sweep of two-slot `! videoconvert`
stages only ever stops the guard at one parity. Before tagging:
`camera-relay/tests/test-launcher-validation.sh` 33/33, and clean compiles with
`gcc -Wall -Wextra`, with and without `-DCAMERA_RELAY_USER_CACHE`. Line 54 is
not a `substituteInPlace` target in `nixos/webcam-fix-book5.nix`.
Released as **v0.3.85** on `f6eae08`, titled "Camera relay can publish a
native PipeWire camera node (opt-in)". The notes cover the
`RELAY_PW_PUBLISH=1` drop-in, the author's two known limitations and the
`MAX_ARGS` change:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.85>.
Item 3 is done. Item 2 (README for `RELAY_PW_PUBLISH` and
`RELAY_COLOR_FILTER`) is still open as an optional docs task.
