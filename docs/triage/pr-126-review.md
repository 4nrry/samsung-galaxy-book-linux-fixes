# PR #126 review — "Add end-to-end installer for OV02C10 camera + speakers (Galaxy Book4 Ultra 960XGL)"

VERDICT: **CHANGES REQUESTED** on `ce3af3f` (1 blocker). No merge, no release.

**Status (2026-10-22):** REQUEST_CHANGES review drafted below, not posted yet.
The latest release is still v0.3.91. Nothing from this PR ships as it stands.
v0.3.92 would only follow a separate change on `main`, for example the
Electron/Teams wording or snap checks in `camera-relay doctor`, if @revolte's
answers show a real gap.

Reviewed: 2026-10-22. Author: **@revolte**, who wrote the #123 tutorial; this
is their first PR. Head `ce3af3f`, 1 commit, branch based on `main` `f1cf84c`,
`MERGEABLE`, no CI, no prior comments or reviews. One new file,
`webcam-fix-libcamera/install-ov02c10-camera.sh` +209/−0, mode `100644`.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/126>

## What the PR does

It's a wrapper that turns the #123 tutorial (also pasted as HTML into #123,
comment 6354465346) into a script.

- **Pre-flight (L32–36):** `need_cmd` for sudo, curl, git, dkms and make.
- **Fetch (L16–47):** clones the repo into `~/samsung-galaxy-book-linux-fixes`,
  or runs `git pull --ff-only` if it's already there.
- **Step 1 (L52–57):** runs `webcam-fix-libcamera/install.sh` from that clone.
- **Step 2 (L62–75):** adds the user to `video` and writes
  `/etc/udev/rules.d/99-ipu6-camera.rules` (video4linux, `intel-ipu6-isys` and
  `ipu-psys*` → `GROUP="video"`, `0660`), then `udevadm trigger`.
- **Step 3 (L80–85):** `sudo ./install.sh` in `speaker-fix/`.
- **Step 4 (L90–123):** for snap Chromium, Brave and Firefox, runs
  `snap connect <snap>:camera` and pre-seeds the portal PermissionStore
  (`devices`/`camera`) with `yes` for `chromium` and `com.brave.Browser`.
- **Step 5 (L128–149):** for snap teams-for-linux, connects `camera` and
  *overwrites* `config.json` with
  `electronCLIFlags: [["enable-features","WebRtcPipeWireCamera,WebRTCPipeWireCapturer"]]`.
- **Verify (L154–170):** `cam -l | grep "Internal front camera"` and
  `aplay -l | grep card`, then a closing text with flag reminders and an
  initramfs hook for `ipu6epmtl_fw.bin.zst`.

The PR description includes useful 26 MHz results from @revolte's board, on
Ubuntu 26.04 with 7.0.0-38: `link_freq=541666666`, one Frame sync error at
stream start, none during streaming, 30.08 fps. That matches @4nrry's
NP960XGL-XG1BR (#123, 6319696718) and answers the "does the count rise
*during* streaming" question asked in #123 (6321800190). It's a second
confirmation of v0.3.89+ on 26 MHz hardware.

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | udev ordering and override | `man udev`: all rules files are "collectively sorted and processed in lexicographic order, regardless of the directories"; `=` assigns and only `:=` locks a value. `74-camera-relay-mc-nodes.rules` (`webcam-fix-libcamera/install.sh:1611-1648`) sets `GROUP="camera-relay"` with plain `=`, so a later `99-` `GROUP="video"` wins. The `setfacl -b` RUN still strips the ACL, but group `video` with `0660` makes the nodes openable for any `video` member, which the desktop user is (`install.sh:1408-1414`). **Blocker confirmed.** |
| 2 | `cam -l` Permission denied is by design | `webcam-fix-libcamera/README.md:372-387` ("Too many "ipu6" entries in camera list"): "`cam` and `qcam` can no longer open the camera as your user… `camera-relay-gst --list-cameras`". |
| 3 | The other two udev lines | On this (legacy-stack) machine `/dev/ipu-psys0` exists with `SUBSYSTEM=intel-ipu6-psys`, from the out-of-tree `intel_ipu6_psys` module. There's no `intel-ipu6-isys` subsystem, and ISYS capture nodes are `video4linux`. The libcamera stack has no PSYS node (`README.md:298-323`). Einstein's "mainline has no ipu-psys node" is right for this stack. Corrected wording: the node only exists with `intel-ipu6-dkms`. |
| 4 | Portal snap app ID | xdg-desktop-portal 1.21.1 (the version installed here), `src/xdp-app-info-snap.c:257`: `snap_id = g_strconcat ("snap.", snap_name, NULL)` passed as the app-info `id`. `src/xdp-permissions.c` looks up `xdp_app_info_get_id (app_info)` in the table, so `chromium` / `com.brave.Browser` never match a snap caller. `com.brave.Browser` is Brave's Flathub ID (`flathub/com.brave.Browser`). **Confirmed.** |
| 5 | `WebRTCPipeWireCapturer` | Chromium `content/public/common/content_features.cc` at 100.0.4896.0, 120.0.6099.0 and 130.0.6723.0: "Controls whether the PipeWire support for screen capturing is enabled on the Wayland display server", enabled by default since 120 and gone from that file by 140.0.7339.0. Screen capture, not camera. **But** teams-for-linux `app/startup/commandLine.js` `#configureWayland` appends `enable-features=WebRTCPipeWireCapturer` only when no `enable-features` is set, and warns if one is set without it. So including it in the PR's list is **correct**. Einstein's "unrelated" framing is dropped from the public review. The config format (`[name, value]` pairs) matches `addElectronCLIFlags`. |
| 6 | Browser flag already handled | `camera-relay/chromium-pipewire-camera.sh:135-163` walks `~/.config`, `~/snap/*/current/.config` and `~/.var/app/*/config` for Chrome, Chromium, Brave and others, with a running-browser guard (`:177-210`). Called from `install.sh:2143`. **Confirmed.** |
| 7 | Pre-flight vs. fresh install | `ov02c10-26mhz-fix/install.sh:37-44` installs dkms. `install.sh:1893` installs `v4l2loopback-dkms`. `apt-cache depends dkms` → `make`, `build-essential`. `curl` and `TARBALL_URL` appear nowhere else in the script. **Confirmed.** |
| 8 | speaker-fix under `set -e` | `speaker-fix/install.sh:63-70` exits 1 without a MAX98390 unless `--force`. The step runs as a `( … )` subshell under `set -euo pipefail` → aborts the wrapper. `speaker-fix/README.md:29` lists the Book4 Ultra. **Confirmed.** |
| 9 | Electron wording the Teams claim touches | `install.sh:2333-2334`, `README.md:174-176` and `README.md:546` say PipeWire camera "is not wired into Electron". It's unresolved, so it goes in as a question, not a claim. |
| 10 | Initramfs hint | Running the closing text's hook commands with `sudo` stubbed out: `warning: here-document at line 1 delimited by end-of-file (wanted 'HOOK')`. The indented terminator never closes it. Our installer adds only `mei-vsc`, `mei-vsc-hw`, `ivsc-ace` and `ivsc-csi` to `/etc/initramfs-tools/modules` (`install.sh:508-513`), not `intel-ipu6`. |
| 11 | Prior asks (#123, all 14 comments) | Teams, firmware dmesg and snap connects were never asked. The libcamera version and logs (6255118212), Mesa-pinned `cam` and Frame sync counts (6276841671, 6276952127), `modinfo -n ipu_bridge` and rotation (6301860153) and `pw-cli` on the libcamera node (6321800190) were asked before. None are repeated. The rotation problem was resolved by revolte's snapshot restore (6311919051). |

## Findings

**B1. BLOCKER: step 2 makes the raw IPU6 nodes openable again** (L69–75). See
check 1. It brings back the spurious "ipu6" entries in Firefox, Zoom and OBS,
the problem that `74-camera-relay-mc-nodes.rules` and `camera-relay doctor`'s
`MC nodes` line exist to prevent. The `cam -l` "Permission denied" that
motivated it is intended (check 2). Drop the step. On revolte's machine:
remove the file, reboot, and the doctor should report `MC nodes: hidden`.

**F2 (medium)**, L71–72: the other two rules are no-ops on the libcamera stack
(check 3).

**F3 (medium)**, L64–67: duplicates `install.sh:1408-1414`.

**F4 (medium)**, L16–47: clones a second copy and runs `main` from it, even
from inside a checkout. Should use `SCRIPT_DIR`. `TARBALL_URL` is dead.

**F5 (medium)**, L32–36: `need_cmd dkms` / `make` / `curl` stop the script on
a fresh install that the chained installers would handle (check 7).

**F6 (medium)**, L97–100 / L110–113: the portal pre-seed writes app IDs that
are never looked up (check 4). It would grant the camera silently even if the
IDs were right, and every failure is hidden by `2>/dev/null || true`. The
`snap disconnect` before the connect (L95) does nothing useful.

**F7 (low)**, L101 / L114 / the closing text: the flag reminders are out of
date (check 6).

**F8 (medium)**, L133–144: overwrites `config.json` instead of merging; the
backup doesn't keep other settings in effect. Including
`WebRTCPipeWireCapturer` is correct (check 5, which corrects Einstein's
finding 8).

**F9 (low)**, L80–85: speaker-fix aborts the whole run on a non-MAX98390
machine, and nothing checks DMI (check 8).

**F10 (low)**, L154–170: `aplay -l | grep card` matches any card, HDMI
included. `cam -l` as the user only passes *because of* B1.

**F11 (low)**: mode `100644`, no trailing newline, no README pointer. It's
Ubuntu-only and snap-only. The initramfs hint at L189–203 is broken as printed
(check 10), and if the firmware race is real, the fix belongs in `install.sh`.

Not raised publicly: with `pipefail`, the `… | grep -q` conditions (L64, L157,
L165) can in theory read SIGPIPE as "no match". With output this small it's
very unlikely, so it isn't worth the noise.

## Questions for @revolte

1. Teams camera: through PipeWire or the relay? If PipeWire, `install.sh:2333`
   and `README.md:174` need correcting.
2. Was `ipu6epmtl_fw.bin` "Direct firmware load failed" real? Asks for dmesg
   and `lsinitramfs`, since our installer doesn't put `intel-ipu6` in the
   initramfs.
3. Were the snap `camera` connects actually needed?

## GitHub review comment (CHANGES REQUESTED)

> Thanks a lot for this, @revolte, and for turning your #123 tutorial into something others can run. The results in the description are really useful too. `link_freq=541666666` with one Frame sync error at stream start, none while streaming, and 30.08 fps matches what @4nrry saw on the same model, so that settles the question I asked in #123. Thank you.
>
> I can't merge the script as it stands, though. Most of what it does is already done by `webcam-fix-libcamera/install.sh`, and step 2 undoes something that installer does on purpose. Details below.
>
> **Blocker: step 2 makes the raw IPU6 nodes visible to apps again**
>
> `install.sh` writes `/etc/udev/rules.d/74-camera-relay-mc-nodes.rules`. That rule moves the ~48 raw IPU6 capture nodes (the ones flagged `V4L2_CAP_IO_MC`) out of `video` into a `camera-relay` group with no members, and strips their session ACL. Those nodes aren't usable cameras on their own, and while your desktop user can open them, apps that walk `/dev/video*` (Firefox, Zoom, OBS) list them as a row of broken "ipu6" cameras. See [Too many "ipu6" entries in camera list](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/tree/main/webcam-fix-libcamera#too-many-ipu6-entries-in-camera-list).
>
> `99-ipu6-camera.rules` (L69–75) runs after it (udev processes all rules files in lexical order) and has `SUBSYSTEM=="video4linux", GROUP="video"`. A plain `=` overrides the earlier assignment, so every node goes back to `video`, which your user is in. The `Permission denied` from `cam -l` that motivated this step is the intended result. The same README section covers it: run `camera-relay-gst --list-cameras`, which holds the group, instead of plain `cam`. Please drop step 2 entirely.
>
> If the rule is still on your machine: `sudo rm /etc/udev/rules.d/99-ipu6-camera.rules`, reboot, and `camera-relay doctor` should then report `MC nodes: hidden from this session OK`.
>
> **Other points** (line numbers are in `install-ov02c10-camera.sh`)
>
> 1. **L71–72.** The other two udev lines can't match anything on this stack. `intel-ipu6-isys` isn't a udev subsystem (ISYS nodes are `video4linux`), and `/dev/ipu-psys*` only exists with the out-of-tree `intel-ipu6-dkms` PSYS module. The libcamera stack doesn't use that module, and the README recommends not installing it.
> 2. **L64–67.** `install.sh` already adds you to `video`.
> 3. **L16–47.** The script clones a second copy into `~/samsung-galaxy-book-linux-fixes` and runs whatever is on `main` there, even when you start it from inside a checkout. It should use its own directory instead (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`). `TARBALL_URL` and `curl` are never used.
> 4. **L32–36.** On a really fresh Ubuntu, `need_cmd dkms` and `need_cmd make` stop the script before it starts. The chained installers install dkms themselves (dkms pulls in make), so these checks block the fresh-install case the script is meant for.
> 5. **L97–100 and L110–113, portal pre-seed.** I don't think these entries are ever read. xdg-desktop-portal looks permissions up by the app ID it derives for the caller. For a snap that ID is `snap.<instance-name>` (`g_strconcat ("snap.", snap_name, NULL)` in `src/xdp-app-info-snap.c`), so `snap.chromium` and `snap.brave`, not `chromium`. `com.brave.Browser` is Brave's Flatpak ID. Even with the right IDs, I'd rather not grant camera access silently on someone's behalf. With every call ending in `2>/dev/null || true`, a failure is invisible either way. If the portal dialog really hangs on 26.04, I'd like to understand that separately.
> 6. **L101, L114, closing text.** The `chrome://flags` / `brave://flags` reminders are no longer needed. `install.sh` already turns on `WebRtcPipeWireCamera` in the `Local State` of Chrome, Chromium and Brave, including snap and Flatpak profiles (`camera-relay/chromium-pipewire-camera.sh`). It skips any browser that is running at the time, and `camera-relay doctor` shows the state per browser.
> 7. **L133–144, Teams.** This replaces the user's entire `config.json`. There's a backup, but every other setting is lost. Please merge into it instead (e.g. with `jq`). Listing `WebRTCPipeWireCapturer` is right, by the way: teams-for-linux only adds it for Wayland screen sharing when `enable-features` isn't already set, so leaving it out would break screen sharing.
> 8. **L80–85, speaker fix.** `speaker-fix` is the right fix for the 960XGL. But it exits with an error when no MAX98390 is detected, and under `set -e` that stops every step after it. Nothing checks the model, either, even though the script is named for one (`/sys/class/dmi/id/product_name`).
> 9. **Verify section (L154–170).** `aplay -l | grep card` passes for any card, HDMI included, so it doesn't show the speakers work. With step 2 gone, `cam -l` as your user is expected to fail. `camera-relay status` / `camera-relay doctor` are the checks to use.
> 10. **Housekeeping.** The file is committed as `100644`, not executable, and has no newline at the end. Nothing in the README points to it. The initramfs hint at the end (L193–203) doesn't work if someone pastes it as printed. The closing `    HOOK` is indented, so it never ends the heredoc, and the `chmod`/`update-initramfs`/`reboot` lines get swallowed into the hook file. The `#!/bin/sh` line also gets the indentation.
>
> **What I'd suggest**
>
> The parts that are new here are worth keeping: the snap `camera` interface connections and a Teams config that *merges*. The smallest way to land them would be README sections in `webcam-fix-libcamera/README.md` ("Snap browsers" and "Teams for Linux"), or a much smaller PR that only adds those. I'm happy to help shape either.
>
> **A few questions, since your setup is the first report of these:**
>
> 1. **Teams:** did the camera come through PipeWire or through the relay? Our installer and README currently say the PipeWire camera isn't wired into Electron. If Teams picked it up through PipeWire with that config, those docs are wrong and I'd like to fix them. A screenshot of the device list in Teams' settings, or `wpctl status` during a call, would tell us.
> 2. **IPU6 firmware:** did you actually hit `Direct firmware load for intel/ipu/ipu6epmtl_fw.bin failed`? If so, please post `sudo dmesg | grep -iE "ipu6|firmware"` and `lsinitramfs /boot/initrd.img-$(uname -r) | grep -iE "ipu6|ipu/"`. Our installer only adds the IVSC modules to the initramfs, not `intel-ipu6`, so I'd like to see how it got there. If it's real, the fix belongs in `install.sh`.
> 3. **Snap connections:** were the `snap connect …:camera` steps actually needed for Chromium and Firefox, or were they already connected? `snap connections chromium | grep camera` shows it.
>
> Thanks again. This is a really useful set of field notes from a fresh 26.04 install.

## Outcome

Pending: review not posted yet.
