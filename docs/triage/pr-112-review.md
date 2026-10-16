# PR #112 review — "camera-relay: show "Camera Relay" as the tray item name"

VERDICT: READY TO MERGE

Reviewed: 2026-10-15. Author: **@4nrry** (Anrry Petrin, also #76–#79, #83,
#84, #86, #88, #90, #105). Head `155afdd` (1 commit), branch `fix/systray-title`.
The PR is based on `5a8be0b`, which is behind `main` (`a113b54`), but
`git merge-tree --write-tree main pr/112` merges cleanly, and the merged tree's
diff against `main` is only this file, +5/−0. `MERGEABLE` / `CLEAN`, no CI, no
prior comments or reviews.
1 file: `camera-relay/camera-relay-systray.py` +5/−0, mode stays `100755`.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/112>

## What the PR does

1. Right after `from gi.repository import Gtk, GLib`:
   `GLib.set_prgname("camera-relay")` and `GLib.set_application_name("Camera Relay")`.
2. In the AppIndicator branch of `__init__`: `self.indicator.set_title("Camera Relay")`
   between `Indicator.new(...)` and `set_status(...)`.

The author reports that on Kubuntu/Plasma the StatusNotifierItem now reads
`Title = "Camera Relay"`, `Id = "camera-relay"`. They didn't test GNOME.

## What I verified

All runtime tests used copies of the base and PR scripts in the scratchpad, with
`RELAY_CMD` pointed at a nonexistent path (so `_get_status` takes its
`FileNotFoundError` fallback and nothing calls the real relay). Each copy ran under
`dbus-run-session -- xvfb-run`, with `XDG_RUNTIME_DIR` set to a scratch dir so the
single-instance lock didn't collide with Andy's running tray (pid 370022). His
relay and tray weren't touched.

| # | Check | Result |
|---|---|---|
| 1 | Syntax | `python3 -m py_compile` on the PR version: OK. |
| 2 | **Bug reproduced on `main`** | On the private bus, `org.kde.StatusNotifierItem.Title` at `/org/ayatana/NotificationItem/camera_relay` = **`'camera-relay-systray-base.py'`**, the script filename. That's the bug. libayatana-appindicator falls back to `g_get_application_name()` when no title is set, and that defaults to prgname = `basename(argv[0])`. |
| 3 | **Fixed on the PR** | Same probe: `Title = 'Camera Relay'`, `Id = 'camera-relay'`. `Id` comes from the first argument to `Indicator.new()`, which is unchanged, so the SNI object path and Id are the same as before. |
| 4 | `set_title` availability | It exists on `AyatanaAppIndicator3.Indicator` (local `gir1.2-ayatanaappindicator3-0.1` 0.5.94). The installers install the Ayatana binding on all three distros (`gir1.2-ayatanaappindicator3-0.1`, `libayatana-appindicator-gtk3`, `libayatana-appindicator`), and the Ayatana fork has always had it. The legacy `AppIndicator3` import (tried first) is the Canonical libappindicator, which has had `app_indicator_set_title` since the 12.10 series (2012), older than any distro this repo supports. The call is inside the `if USE_APPINDICATOR:` branch, so it never runs when neither binding imports. |
| 5 | Gtk.StatusIcon fallback | I forced `USE_APPINDICATOR = False` in a copy of the PR script. It starts and prints the usual two fallback messages plus the existing StatusIcon deprecation warnings, with no new errors and no `set_application_name` "called multiple times" warning. The new GLib calls run in both paths. `set_title` is only in the AppIndicator branch. |
| 6 | Placement relative to Gtk init | PyGObject's Gtk 3 override runs `Gtk.init_check()` on import, so prgname is already `basename(argv[0])` before the PR's line. A second `g_set_prgname` just replaces it (GLib 2.88 here; `g_set_prgname_once` is the separate one-shot API), so it's legal. The one visible side effect is on X11: GDK captured the program **class** at init, so a window's `WM_CLASS` becomes mixed. Measured with `xprop` on a `Gtk.MessageDialog` under Xvfb: base `"wmclass.py", "Wmclass.py"`, PR `"camera-relay", "Wmclass.py"`. Harmless, see O1. |
| 7 | Process matching by name | `set_prgname` is an in-process GLib string. It doesn't change `/proc/PID/comm` or `cmdline`. Both stayed `python3` + the script path under the PR, and `pgrep -f camera-relay-systray*.py` still matched. The only process match on the tray is `pkill -f "camera-relay-systray.py"` in `webcam-fix-libcamera/uninstall.sh:108` and `webcam-fix-book5/uninstall.sh:200`, which is `-f` (cmdline) and so unaffected. The `pgrep -x camera-relay-monitor` / `pkill -x` in `webcam-fix-libcamera/install.sh` target a different process. |
| 8 | Lock file, `.desktop`, WM_CLASS consumers | The lock file name is hardcoded (`camera-relay-systray.lock`), not derived from prgname. `camera-relay-systray.desktop` has no `StartupWMClass`. Nothing in the repo (including the Nix files) matches on `WM_CLASS`, prgname or application name (grepped). |
| 9 | Log prefix | GLib/GTK warnings now print as `(camera-relay:PID)` instead of `(camera-relay-systray.py:PID)`. The script's own `print(..., file=sys.stderr)` messages still say `camera-relay-systray:`. Cosmetic only, nothing parses it. |
| — | Not tested | GNOME Shell's AppIndicator extension and a real Plasma panel (no test session here). On GNOME the extension uses `Title` as the accessible name. Before this PR that was the filename, so the change can only help. The author's screenshot covers Plasma. |

## Findings

### Blocking

None.

### Non-blocking (optional, no follow-up needed for this PR)

**O1. Mixed `WM_CLASS` on the tray's dialogs (X11), and the prgname choice.**
`set_prgname` runs after Gtk has initialised, so the persistent-mode and
disable dialogs get `WM_CLASS = "camera-relay", "Camera-relay-systray.py"`. On
Wayland, GTK3 uses prgname as the xdg_toplevel `app_id`, so it's
`camera-relay` there. Neither value matches the desktop-file ID before or after
the PR (`camera-relay-systray.desktop`), so the dialogs show a generic
icon either way, and nothing regresses. If we ever want the dialogs to show the
Camera Relay name and icon in the dock or Alt-Tab, two things would be needed:
`GLib.set_prgname("camera-relay-systray")` to match the `.desktop` ID, and
calling it before `from gi.repository import Gtk` (import GLib first) to keep
the class consistent. **Unverified** on a real GNOME/Plasma session, and outside this PR's scope. Not
worth a round-trip.

### Pre-existing (not caused by this PR, separate follow-up for Andy)

**P1. `pgrep -x camera-relay-monitor` can never match.**
`webcam-fix-libcamera/install.sh:1975` and `:1977` use `pgrep -x` / `pkill -x`
with a 20-character name, but `comm` is truncated to 15 (`camera-relay-mo`).
On this machine, with the monitor running as pid 4856:

```
$ cat /proc/4856/comm
camera-relay-mo
$ pgrep -x camera-relay-monitor
pgrep: pattern that searches for process name longer than 15 characters will result in zero matches
rc=1
```

So the "stop running monitor before replacing binary" block is always
skipped on reinstall: the service isn't stopped and the old monitor keeps
running the old binary until the next restart. `install(1)` unlinks the destination before writing,
so there's no "Text file busy" failure. The block is effectively dead code
rather than a hard error. The fix would be `pgrep -f /usr/local/bin/camera-relay-monitor` (or
`-x camera-relay-mo`). Untouched here, because this card is review-only.

## Draft merge comment (READY TO MERGE)

> Thanks @4nrry! Small change, and it does what it says. I reproduced the bug and checked the fix on a private D-Bus session under Xvfb:
>
> - `main`: the StatusNotifierItem `Title` is the script filename (libayatana falls back to `g_get_application_name()`, which defaults to `argv[0]`)
> - this PR: `Title = "Camera Relay"`, and `Id` / the object path are unchanged
>
> I also forced the `Gtk.StatusIcon` fallback to make sure the new GLib calls don't trip anything there, and confirmed that `set_prgname` doesn't change `comm`/`cmdline`, so the uninstallers' `pkill -f camera-relay-systray.py` still finds the tray.
>
> One small note, nothing to change: because `set_prgname` runs after Gtk has initialised, the dialogs' X11 `WM_CLASS` ends up mixed (`"camera-relay", "Camera-relay-systray.py"`). Nothing matches on it, so it doesn't matter.
>
> Merging. Thanks for the screenshot too!

## Draft change-request comment

Not needed (verdict is READY TO MERGE). If Andy prefers to adopt O1 before
merging, use this:

> Thanks @4nrry, this fixes the tray title. I confirmed `Title` goes from the script filename to "Camera Relay" on a test D-Bus session, and the StatusIcon fallback and the uninstallers' `pkill -f` are unaffected.
>
> One optional tweak before I merge: could you use `GLib.set_prgname("camera-relay-systray")` (matching `camera-relay-systray.desktop`) and move it above `from gi.repository import Gtk` (e.g. `from gi.repository import GLib` first)? Gtk captures the program class when it's imported, so setting the prgname afterwards leaves the dialogs with a mixed `WM_CLASS`. Matching the desktop-file ID should also let GNOME/Plasma show the dialogs with the Camera Relay name and icon. The tray `Title` doesn't depend on this, since `set_title` / `set_application_name` already handle it.

## Merged + released (2026-10-15)

- Approved: <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/112#pullrequestreview-5541554757>
  (the draft merge comment above, without the O1 `WM_CLASS` paragraph).
- Merged as `ca0d0b3` ("Merge pull request #112 from 4nrry/fix/systray-title"), merge commit. PR state `MERGED`.
- Released as **v0.3.80**, "Camera Relay tray icon shows its name, not the script filename", tagged on `ca0d0b3`:
  <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.80>.
  The notes say to re-run the installer or `sudo cp` the script to `/usr/local/share/camera-relay/`, because `git pull` alone doesn't update the installed copy.
- Thank-you comment pointing to the release: <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/112#issuecomment-6205240334>.
- O1 not requested (optional). P1 (`pgrep -x camera-relay-monitor`) left out of the PR and the release. It's still an open follow-up for Andy.

## P1 follow-up (2026-10-15)

P1 is fixed outside the PR, in v0.3.81. Both installers now match the monitor
with `pgrep -f '^/usr/local/bin/camera-relay-monitor( |$)'`. It's anchored
because the unanchored form also matches any process whose command line
mentions the path (it matched the shell running the check). With the block
live, a new problem showed up: `enable-persistent` is a no-op when the unit is
already enabled and hasn't changed, so the relay the block stopped would have
stayed down until the next login. The installers now start it again after
`enable-persistent`. `webcam-fix-book5/install.sh` never had the block at all:
it copied over the running binary with `sudo cp`, which fails with "Text file
busy", and `set -e` then aborted the install. It now uses `install(1)` and the
same stop/restart block.
