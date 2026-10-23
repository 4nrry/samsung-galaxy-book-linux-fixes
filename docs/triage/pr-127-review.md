# PR #127 review — "docs: Add Snap browser and Teams for Linux camera notes"

VERDICT: **MERGED** 2026-10-23 as `4894977` (head `7cf9687`). No release (README only).

**Status (2026-10-23, round 2):** @revolte pushed `4a64548`, which addressed all six
findings below. It had one new defect: the ```` ```bash ```` fence around the `jq`
command was never closed, so GitHub rendered lines 446–481 (the note, the whole
"Snap browsers" section and the start of "Chromium can't use the V4L2 relay")
as one code block. Andy pushed a one-line fix to the contributor's branch
(`7cf9687`, maintainerCanModify) after checking it with the `gh api /markdown`
render. Approve review 5634194107 thanked revolte and told them about the edit.
Merged as a merge commit, which closed the PR. Round 1 CHANGES_REQUESTED review
5631375717 is kept below.

**Follow-up DONE (v0.3.92, `2062dfe`):** the "PipeWire camera isn't wired into
Electron" wording is corrected in both installers, `camera-relay doctor`, both
webcam READMEs (plus an Electron row in each compatibility table) and the
`chromium-pipewire-camera.sh` comment. electron#45058 was actually closed as
*completed* (the reporter confirmed `appendSwitch("enable-features",
"WebRtcPipeWireCamera")` detects the camera), not "unimplemented".

Reviewed: 2026-10-23. Author: **@revolte**. This is the docs-only replacement for
#126, which they closed. Head `bfbde1b`, 1 commit, `MERGEABLE`/`CLEAN`, no CI.
One file, `webcam-fix-libcamera/README.md` +35/−0, appended after "Related Resources".
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/127>

## Key finding: Teams reached the relay through PipeWire

In #126, revolte reported that Teams lists the camera as **`Camera Relay (V4L2)`** and
concluded that Teams uses the relay over V4L2, so our Electron wording was right.
The name shows the opposite:

- WirePlumber's `scripts/monitors/v4l2/name-node.lua` sets
  `node.description = device.description .. " (V4L2)"`. So `Camera Relay (V4L2)`
  is the relay loopback *as a PipeWire node*. It was checked against the installed
  WirePlumber 0.5.13.
- Over plain V4L2, Chromium/Electron would use the card name `Camera Relay`. It
  would also filter it out, because `exclusive_caps=0` advertises capture and output.
- So the teams-for-linux Electron honours `--enable-features=WebRtcPipeWireCamera`
  (set through `electronCLIFlags`). README L174–176 and L544–548 and `install.sh`
  L2333–2334 ("switch does not help — PipeWire camera is not wired into
  Electron") are wrong, at least for teams-for-linux. **Follow-up on `main`
  (Andy promised it in #126):** fix that wording. That would be v0.3.92.
- My #126 reply ("relay and PipeWire camera have different names") caused the
  misreading. The review says so.

## Other findings

1. **Snap tip is backwards.** A `-` in **Notes** = auto-connected, which is healthy. An
   unconnected plug shows `-` in **Slot**. Verified with `snap connections firefox`
   on this machine (`alsa … - -` vs `camera … :camera -`).
2. "Firefox and Brave usually auto-connect": revolte's own re-test showed Chromium
   auto-connects too.
3. **`libcamerify` fallback can't work for the snap.** `snap-confine` has file
   capabilities (`getcap`: `cap_sys_admin,…=p`), so AT_SECURE is set → glibc strips
   `LD_PRELOAD`. Also, the snap base has no host `v4l2-compat.so`. Off-snap, it would
   compete with the relay for libcamera. Ubuntu packaging: `libcamerify` ∈
   `libcamera-tools`, `v4l2-compat.so` ∈ `libcamera-v4l2` (checked with `dpkg -c` on 0.7.0-1ubuntu2).
4. Says "merge with `jq`" but shows `nano` plus a bare JSON snippet. Suggested a
   tested `jq` one-liner (empty file, `{}`, and a config with other string/array
   flags all handled). Non-snap path: `~/.config/teams-for-linux/config.json`.
5. Placement: appended after Related Resources with no blank line before `##`.
   Asked for `###` sections under Troubleshooting.

## Review comment (as posted)

Thanks @revolte, for following through and turning #126 into a focused docs PR so quickly, and for checking the Teams device name. That answer turned out to be more useful than either of us thought (see the Teams section below).

I can't merge it quite yet. One instruction points the wrong way, and the Teams fallback won't work for the snap. Both are quick fixes.

**Snap browsers**

1. **The `-` check is reversed.** In `snap connections`, a `-` in the **Notes** column is what a *healthy* auto-connection looks like. That's what your Chromium shows now, with the camera working. An unconnected plug shows `-` in the **Slot** column instead. Here's Firefox on my machine:

    ```
    Interface  Plug             Slot             Notes
    alsa       firefox:alsa     -                -        ← not connected
    camera     firefox:camera   :camera          -        ← connected (auto)
    ```

    As written, the tip tells everyone whose camera works to run `snap connect`. Suggested wording: *"If the `camera` line shows `-` in the **Slot** column (or no `camera` line at all), connect it: `sudo snap connect chromium:camera`."*
2. **The closing note.** Your re-test showed Chromium auto-connects too, so "Firefox and Brave usually auto-connect" makes Chromium sound like the exception. I'd drop the note, or say all three auto-connect and this is only for recovery.

**Teams for Linux**

3. **This one's on me.** In #126 I said the relay and the PipeWire camera would have different names in Teams. That was only half right. `Camera Relay (V4L2)` is the name **WirePlumber** gives the relay when it publishes it into PipeWire. Its v4l2 monitor appends ` (V4L2)` to every node description (`scripts/monitors/v4l2/name-node.lua`). Over plain V4L2, Electron would see the card name `Camera Relay`, and it would filter it out anyway, because the relay reports capture *and* output (same filter as Chrome). So Teams reached the relay **through PipeWire**, and your `WebRtcPipeWireCamera` flag is what made that work. That means:
    - Your opening line ("needs to be configured to use the PipeWire camera stack") is right, and so is putting the `enable-features` merge first.
    - Our README and `install.sh` are wrong to say the switch can't help Electron apps, at least for teams-for-linux. I'll fix that wording myself in a follow-up, as promised. You don't need to change anything about it here. Could you just drop the "no changes needed to the Electron wording" line from the PR description?
4. **Please remove the `libcamerify` fallback.** It can't work with the snap:
    - `snap run` goes through `snap-confine`, which runs with elevated file capabilities. So glibc strips `LD_PRELOAD` before Teams starts.
    - Even if it got through, the snap runs on its own base, where the host's `v4l2-compat.so` doesn't exist.
    - On a non-snap install, it would have Teams open libcamera directly and compete with the relay for the sensor.
    - Small extra point: on Ubuntu, `libcamerify` is in `libcamera-tools`, but the library it preloads is in `libcamera-v4l2`.

    Since the PipeWire route is what worked for you, the section doesn't need a fallback.
5. **Show the `jq` merge, not just mention it.** The text says to merge with `jq` but then opens `nano`. Something like this keeps every other setting and existing flag, and swaps in the `enable-features` entry (I tested it against an empty file, `{}`, and a config with other flags):

    ```bash
    f=~/snap/teams-for-linux/current/.config/teams-for-linux/config.json
    mkdir -p "$(dirname "$f")"; [ -s "$f" ] || echo '{}' > "$f"
    jq '.electronCLIFlags = [(.electronCLIFlags // [])[] | select((type == "array" and .[0] == "enable-features") | not)] + [["enable-features", "WebRtcPipeWireCamera,WebRTCPipeWireCapturer"]]' \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    ```

    It's worth one line saying that if you already had features in `enable-features`, you should add them to that list. Also, for the deb/rpm/AppImage builds the file is `~/.config/teams-for-linux/config.json`.

**Placement**

6. Both sections are appended after **Related Resources** at the very end, and `## Snap Browsers` has no blank line after the last list item. Could they go under **Troubleshooting** as `###` sections instead? For example, *"Snap browsers don't see the camera"* next to the Firefox portal entry, and *"Microsoft Teams (teams-for-linux)"* right after *"Chromium can't use the V4L2 relay"*, since it's the Electron case of that problem.

Thanks again. The Teams result is a real finding, and it corrects something we had wrong.
