# PR #116 review — "camera-relay-systray: replace the 5s poll with an inotify state watch"

VERDICT: **READY TO MERGE** on `4c932ff` (no blockers; findings 1–5 are non-blocking)

**Status (2026-10-18):** approve with a thank-you, merge with a merge commit
(like #114 and #115), then fix finding 1 ourselves on `main` and release as
**v0.3.84** (latest is v0.3.83). See the Outcome at the end.

Reviewed: 2026-10-18. Author: **@lautalom** (Lautaro Lombardi), their third PR
in a row after #112 and #115. Head `4c932ff` (2 commits: `c91fb9f`, `4c932ff`),
branch based on `4b2395a`. `MERGEABLE` / `CLEAN`, and `git merge-tree` against
current `main` (`edbebe2`, which includes #115) is clean too. No CI, no prior
comments or reviews. Maintainer edits allowed.
1 file: `camera-relay/camera-relay-systray.py` +63/−4.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/116>

## What the PR does

Drops the tray's fixed 5 s `camera-relay status --json` poll (a bash script plus
a subprocess every tick, and an icon that lagged up to 5 s behind a change).
Instead (L101–147):

- One `Gio.File.monitor_directory` on `$XDG_RUNTIME_DIR`, kept on
  `self._runtime_monitor`.
- `_on_runtime_event` filters by basename against `WATCH_FILES`
  (`camera-relay-state`, `camera-relay.pid`).
- `_deferred_poll` runs one status sync 250 ms after the first event of a burst
  and ignores further events until it has run.
- A 60 s safety-net poll stays (`FALLBACK_POLL_INTERVAL`). If the monitor can't
  be created, the second commit keeps the old 5 s poll
  (`UNWATCHED_POLL_INTERVAL`) and prints a line to stderr.

It doesn't depend on #115 (`status-watch`): the tray reads the runtime files
directly.

## What I verified

Research ran on copies in a scratch dir. The repo and the installed tray were
not touched. On this card I re-checked the line numbers below against
`git show pr-116:…` and ran `python3 -m py_compile` on the PR copy (passes).

| # | Check | Result |
|---|---|---|
| 1 | Dependencies | None added. `Gio` comes from the same PyGObject/GLib typelibs `Gtk` already needs; no ctypes, no third-party library. `install.sh`, `uninstall.sh`, the READMEs and the NixOS modules need no change: no doc mentions the 5 s poll, and Nix doesn't ship the systray. |
| 2 | **Paths match the relay** | `PID_FILE` and `STATE_CACHE` are `$XDG_RUNTIME_DIR/…` (`camera-relay/camera-relay:18-22`). The only exception is `$RUNTIME_DIRECTORY`, which only the Nix unit sets, and Nix has no tray. All writers (L856–857, 888–889, 931–932, 985/989) and removers (L962, 1029, and `is_running`'s stale `rm` at L238) are in that directory. |
| 3 | Main loop | The monitor is created before the first poll, so there's no gap at startup. The callback runs on the GTK main loop. `_pending_poll_source` is cleared *before* `_poll_status`, so a transition during a sync schedules a new one. |
| 4 | Watched dir missing / recreated | `$XDG_RUNTIME_DIR` exists for the whole session. A directory monitor doesn't need the files to exist, so a relay that's stopped at tray startup is fine. If the dir is missing, `monitor_directory` raises, the `except` catches it, and the tray falls back to the 5 s poll. |
| 5 | File descriptors | One inotify instance, referenced on `self._runtime_monitor` (L119). The reference is needed, because a monitor that gets garbage-collected stops firing. The single-instance flock prevents duplicate trays. |
| 6 | **Event types** | Gio directory monitor on GLib 2.88 against the relay's exact write pattern: `echo x > f` on an existing file → `changed`, `changes-done-hint`; new file → `created`, `changed`, `changes-done-hint`; `rm` → `deleted`. All events of one write arrived within ~1 ms. The relay never renames these files, so `IN_MOVED_TO` doesn't matter. |
| 7 | Empty-file race (N3 from #115) | The tray can't hit it in practice: the status subprocess runs 250 ms after the *first* event of a write that finishes in under 1 ms, so it reads a complete file. |
| 8 | Tray backends (#114) | Ayatana / AppIndicator / `Gtk.StatusIcon` selection is untouched. The watch is set up after whichever backend was chosen, and `_poll_status` already handles all three. |
| 9 | Persistent toggles | `enable-persistent` runs `systemctl enable`, then restart / `--now`, which writes the pid file. `disable-persistent` runs `disable --now`, which removes the files. Either way the watch fires *after* `is-enabled` has changed, so the persistent label updates without the old poll. |
| 10 | Mergeable | `MERGEABLE` / `CLEAN` on GitHub, and `git merge-tree` against `edbebe2` has no conflicts. |

## Findings

All non-blocking.

**1. Not introduced here, but it defeats the PR's goal: the persistent-toggle
poll never stops.** `camera-relay-systray.py:296` (`_on_persistent_toggle`)
and `:323` (`_show_persistent_warning`) call
`GLib.timeout_add(1000, self._poll_status)`, and `_poll_status` returns `True`
(L245, "keep polling"). So every persistent toggle starts a 1 s poll that runs
forever. After one toggle the tray spawns a bash subprocess every second, which
is worse than the old 5 s poll. It's the same on `main` (L237/L264). Fix: make
both calls one-shot, e.g. `lambda: self._poll_status() and False`. Don't reuse
`_poll_returns_false`, which clears the debounce id. Don't reuse
`_poll_status_once` (L274) either: it also calls `item_toggle.set_sensitive(True)`,
which could re-enable start/stop while a start/stop action is still running. We
fix this ourselves on `main` after the merge.

**2. Wording.** The docstring at L113 says `` `cat > file` ``, but the relay
writes with `echo … >`. The comment at L52–53 says the paths are the same as
`STATE_CACHE` / `PID_FILE` without mentioning the `$RUNTIME_DIRECTORY` (Nix)
exception. Neither affects behaviour.

**3. Style.** `_pending_poll_source` is read through `getattr(…, None)` (L140)
and never set in `__init__`. Setting `self._pending_poll_source = None` in
`__init__` would be clearer.

**4. Accepted trade-off: SIGKILL with no restart.** If the relay is killed with
SIGKILL (e.g. by the OOM killer) and nothing restarts it, the stale pid file
triggers no event, so the tray shows "running" for up to 60 s instead of 5 s.
In persistent mode systemd restarts the relay, which writes the pid file and
fires the watch.

**5. Note only: the debounce is leading-edge.** It acts on the first event and
ignores the rest for 250 ms. That's fine, because a whole write burst takes
under 1 ms.

## GitHub review comment (APPROVE)

> Thanks a lot @lautalom, and that's three in a row after #112 and #115. Really appreciate it!
>
> This is a clean change. It adds no dependencies: `Gio` comes from the same PyGObject/GLib bindings the tray already loads for `Gtk`. If the directory watch can't start, it falls back to the old 5 s poll (thanks for the second commit). It also matches how the relay actually writes its files. `camera-relay` keeps the state and pid files in `$XDG_RUNTIME_DIR` and rewrites them in place with `echo … >`. A Gio directory monitor sees each write as `created`/`changed`/`changes-done-hint` within about a millisecond, and `rm` as `deleted`. So one sync 250 ms after the first event reads a complete file, and the persistent label updates too, because the watch fires after `is-enabled` has already changed.
>
> We'll push a small follow-up on `main` ourselves. The two persistent-toggle handlers have always used `GLib.timeout_add(1000, self._poll_status)`, and `_poll_status` returns `True`, so after one toggle the tray polls every second forever. That predates your PR, but it undoes the saving you just made, so we'll make those calls one-shot. We'll also fold in two small nits: the docstring says `cat > file` where the relay uses `echo … >`, and `_pending_poll_source` should be set to `None` in `__init__` instead of read through `getattr`.
>
> Merging now. It'll go out in the next release. Thanks again!

## Follow-up on `main`

1. Finding 1: make the persistent-toggle polls at L296 / L323 one-shot.
2. Findings 2 and 3: docstring wording, and `self._pending_poll_source = None` in `__init__`.
3. Release **v0.3.84** covering #116 and the follow-up (check `gh release list` first).
