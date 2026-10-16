# PR #114 review — "Camera Relay tray: prefer Ayatana AppIndicator so the hover tooltip works."

VERDICT: CHANGES REQUESTED (one small item: the hint-text change the PR describes isn't in the commit)

Reviewed: 2026-10-16. Author: **@david-bartlett** (David Bartlett, also #107,
#109, #110, #111, and issue #113). Head `5c1e60d` (1 commit), branch
`camera-relay-systray-tooltip-fix`, based on `339d800` (current `main`).
`MERGEABLE` / `CLEAN`, no CI, no prior comments or reviews.
1 file: `camera-relay/camera-relay-systray.py` +4/−4, mode stays `100755`.
Fixes #113, follow-up to #112.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/114>

## What the PR does

Swaps the order of the two AppIndicator imports (lines 37–47), so the script
tries `AyatanaAppIndicator3` first and falls back to the legacy Canonical
`AppIndicator3`. Before, the legacy library was tried first and Ayatana was the fallback.

Why it matters (issue #113): when both libraries are installed, the tray always
loaded the legacy one. That can happen on Fedora (Remmina and yumex-updater pull in
`libappindicator-gtk3`) and on Arch (`libappindicator`). The legacy library doesn't
publish `ToolTip` on the StatusNotifierItem, so Plasma showed no hover text,
even though #112 set `Title` correctly. libayatana-appindicator ≥ 0.6.0 publishes
`ToolTip` from the title.

The PR description and issue #113 also say the missing-library hint now suggests
the Ayatana library. **That change isn't in the commit** (see C1).

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | Syntax | `python3 -m py_compile` on the PR version (`git show pr-114:…`): OK. |
| 2 | **Fallback logic, all four library combinations** | I ran the PR's import block (and `main`'s, for comparison) against a stub `gi` that makes `require_version` raise `ValueError` for a namespace that isn't installed, as real PyGObject does. Results: **Ayatana only** → Ayatana on both. **Legacy only** → legacy on both. **Both** → `main` loads legacy, **PR loads Ayatana** (the intended change). **Neither** → `USE_APPINDICATOR = False` on both, so the `Gtk.StatusIcon` fallback runs. Only the "both" case changes. |
| 3 | Real PyGObject (this machine: Ayatana 0.5.94 only, no legacy typelib) | The import block loads `gi.repository.AyatanaAppIndicator3`, `USE_APPINDICATOR = True`, and `Indicator.set_title` exists. |
| 4 | End-to-end run | I ran a copy of the PR script with `RELAY_CMD` pointed at a nonexistent path and `XDG_RUNTIME_DIR` set to a scratch dir, under `dbus-run-session -- xvfb-run`. The SNI at `/org/ayatana/NotificationItem/camera_relay` showed `Id = 'camera-relay'`, `Title = 'Camera Relay'`, `Status = 'Active'`. `ToolTip` reported "No such property", which matches the PR's note that 0.5.94 doesn't publish it. Only the usual deprecation warnings appeared, nothing new. Andy's running tray wasn't touched. |
| 5 | Other references to the module name | The `as AppIndicator3` alias keeps every later use the same: `Indicator.new`, `IndicatorCategory.HARDWARE`, `IndicatorStatus.ACTIVE`, `set_title`, `set_menu`, `set_icon`. Ayatana's GIR has all of them (#112's review confirmed `set_title`; #3 above re-checked it). Nothing else in the repo imports either namespace. I grepped `*.sh`, `*.py`, `*.nix` and `*.md`, and the Nix files don't reference the systray. |
| 6 | Installers vs. the preferred library | Both `webcam-fix-libcamera/install.sh:2016-2035` and `webcam-fix-book5/install.sh:1187-1206` install **only** the Ayatana binding: `gir1.2-ayatanaappindicator3-0.1` (apt), `libayatana-appindicator-gtk3` (dnf), `libayatana-appindicator` (pacman). So the PR makes the script prefer the library we actually install. |
| 7 | Uninstallers find the tray | `webcam-fix-libcamera/uninstall.sh:108` and `webcam-fix-book5/uninstall.sh:200` use `pkill -f "camera-relay-systray.py"`, which matches on the command line. The PR doesn't change the script name, the `.desktop` `Exec=`, the lock file, the indicator Id or the D-Bus path, so they're unaffected. |
| 8 | Hint text vs. installers | **Mismatch, unchanged by the PR**: lines 69–71 still say `Install gnome-shell-extension-appindicator (GNOME) or libappindicator-gtk3 (KDE/other).` See C1. |
| — | Not tested | Plasma hover with libayatana 0.6.0 and the "both installed" case on real hardware: no such session here. The author covered both on Fedora 45 and CachyOS, plus Ubuntu 26.04 GNOME (Ayatana only, unchanged). |

## Findings

### Changes requested

**C1. The hint-text change described in the PR isn't in the commit.**
The PR body says *"The hint shown when no indicator library is found now
suggests the Ayatana library instead of `libappindicator-gtk3`"*, and #113
asks for the same change. But the diff is just the 4-line import swap, and
`camera-relay-systray.py:68-73` on the PR head is identical to `main`:

```python
"camera-relay-systray: AppIndicator3 not available. "
"Install gnome-shell-extension-appindicator (GNOME) or "
"libappindicator-gtk3 (KDE/other).",
```

It looks like that hunk was never staged. Suggested replacement, matching the
installers (#6). It also fixes the "or": this message prints only when the
*Python binding* is missing, which is the case on GNOME too, and the
extension alone doesn't provide it.

```python
"camera-relay-systray: AppIndicator3 not available. "
"Install the Ayatana AppIndicator library "
"(gir1.2-ayatanaappindicator3-0.1 / libayatana-appindicator-gtk3 / "
"libayatana-appindicator); on GNOME also gnome-shell-extension-appindicator.",
```

The exact wording is up to David. What matters is that it names the Ayatana packages.

*If Andy would rather not have a round-trip for a string:* the import swap is
correct and safe on its own, so the alternative is to merge as-is and fix the
hint in a follow-up commit on `main`. In that case, use the "merge as-is" draft
below.

### Non-blocking (optional)

**N1. Comment on line 35.** `# Try AppIndicator3 (GNOME with extension, KDE, others)`
could now say "Prefer Ayatana AppIndicator, fall back to legacy AppIndicator3"
to match the new order. Cosmetic. Worth including only if David is pushing C1 anyway.

## Draft GitHub review comment (CHANGES REQUESTED)

> Thanks so much @david-bartlett, both for tracking this down in #113 and for the fix. The write-up was excellent. Spotting that the legacy library never publishes `ToolTip` with both installed was a great catch, and the test matrix across Fedora 45, CachyOS (both library combinations, plus an in-place install) and Ubuntu 26.04 GNOME is exactly what this kind of change needs. Thank you for being so thorough!
>
> I checked the import fallback with a stubbed `gi` for all four cases (Ayatana only, legacy only, both, neither). Only "both" changes, and it now picks Ayatana, as intended. "Neither" still falls through to `Gtk.StatusIcon`. I also ran the PR script on a private D-Bus session (Ayatana 0.5.94): `Id`, `Title` and the object path are unchanged, and `ToolTip` is absent, as you noted for 0.5.94. The uninstallers' `pkill -f camera-relay-systray.py` is unaffected.
>
> One thing before I merge: the description says the "no indicator library" hint now suggests Ayatana, but that hunk didn't make it into the commit. Lines 69–71 still say `libappindicator-gtk3 (KDE/other)`. Could you push it? Something along these lines would match what the installers install:
>
> ```python
> "camera-relay-systray: AppIndicator3 not available. "
> "Install the Ayatana AppIndicator library "
> "(gir1.2-ayatanaappindicator3-0.1 / libayatana-appindicator-gtk3 / "
> "libayatana-appindicator); on GNOME also gnome-shell-extension-appindicator.",
> ```
>
> (Use whatever wording you like. Dropping the "or" is deliberate: GNOME needs the library too, not just the extension.) If you're touching the file anyway, the comment above the imports could also say it prefers Ayatana now. That's optional.
>
> Thanks again, really appreciate it!

## Draft merge comment (if Andy merges as-is and fixes the hint himself)

> Thanks so much @david-bartlett, both for tracking this down in #113 and for the fix. The write-up was excellent, and the test matrix across Fedora 45, CachyOS (both library combinations, plus an in-place install) and Ubuntu 26.04 GNOME made this an easy review. Thank you for being so thorough!
>
> I checked the import fallback with a stubbed `gi` for all four cases (Ayatana only, legacy only, both, neither). Only "both" changes, and it now picks Ayatana. I also ran it on a private D-Bus session, where `Id`, `Title` and the object path are unchanged and the uninstallers still find the tray.
>
> The hint-text hunk mentioned in the description didn't make it into the commit, so I'll update that line on `main` myself. Merging, thanks again!
