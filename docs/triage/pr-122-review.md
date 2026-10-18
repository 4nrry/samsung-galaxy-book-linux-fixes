# PR #122 review — "speaker-fix: load `i2c-dev` before probing for extra amplifiers"

VERDICT: **READY TO MERGE** on `66a127f` (no blockers, no requested changes) → **APPROVED, MERGED as `dc5ab2f`** (see Outcome at the end)

**Status (2026-10-18):** approved with a thank-you (review 5564857979) and
merged with a merge commit as `dc5ab2f`, like #114–#117 and #121. #120
auto-closed. Released as **v0.3.88** on `main`.

Reviewed: 2026-10-18. Author: **@david-bartlett** (David Bartlett), after
#107, #109, #110, #121 and the #111 presets. Head `66a127f`, 1 file, +2/−0:
`speaker-fix/max98390-hda-i2c-setup.sh`. `MERGEABLE` / `CLEAN` against `main`
`50fc4b7` (v0.3.87). No CI, no prior comments or reviews. Branch base is
`4b2395a`, but the script has not changed on `main` since then. Fixes #120
("speaker-fix doesn't enable all speakers on Debian / MX Linux (`i2c-dev` not
loaded)"), opened by the same author.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/122>

## What the PR does

Two lines at the top of `find_present_addrs()`:

```bash
# i2cget needs /dev/i2c-N; some distros (e.g. Debian/MX) don't load i2c-dev by default
[ -e "/dev/i2c-$bus" ] || modprobe i2c-dev 2>/dev/null || true
```

On MX Linux 25.3 and Debian 13 the kernel has `CONFIG_I2C_CHARDEV=m` and
nothing loads it, so `/dev/i2c-N` doesn't exist, every `i2cget` probe fails
silently, the script logs "No additional amplifiers found" and only the
ACPI-created `0x38` amp (left side) works. With the node present the line is a
no-op.

## What I verified

| # | Check | Result |
|---|---|---|
| 1 | Runs as root | `max98390-hda-i2c-setup.service` is a system unit (`Type=oneshot`, no `User=`), `ExecStart=/usr/local/sbin/max98390-hda-i2c-setup.sh start`. |
| 2 | `set -e` / pipefail | Neither is set (script lines 1–9). `\|\| true` is harmless and matches the existing `… 2>/dev/null \|\| true` style in the script. |
| 3 | `modprobe` on PATH | systemd's default PATH includes `/usr/sbin`; Debian 13, MX and Fedora are usr-merged. The author's test runs confirm it. |
| 4 | Race with udev | None. `modprobe` returns after `i2c-dev` has attached to every existing adapter, and devtmpfs creates `/dev/i2c-N` itself; udev only adjusts group/mode later. Root can open the 0600 node. |
| 5 | Call sites | `find_present_addrs` is called once (`:83`, `start` path) for the single bus `find_i2c_bus` returns. `stop` never touches i2c tools. |
| 6 | Other copies of the probe | `nixos/samsung-speaker-fix.nix` has its own probe but already loads `i2c-dev` via `boot.kernelModules`. No other script uses `i2cget`/`i2cset`/`i2cdetect` (remaining hits are tester instructions in `docs/triage/`). `speaker-fix-940xfg` reaches its amps through the codec, not the host I2C bus. |
| 7 | Installer / uninstaller | `speaker-fix/install.sh` already installs i2c-tools and copies the script to `/usr/local/sbin`; existing users pick up the fix by re-running it. The PR leaves no file behind, so `uninstall.sh` needs no change. |
| 8 | Syntax | `bash -n` passes on the PR head's script. (shellcheck isn't installed on this box.) |
| 9 | Hardware | Not tested here. The author reports a Book5 Pro 940XHA (4 × MAX98390) on Fedora 45 (`i2c-dev` already loaded, unchanged), MX Linux 25.3 liquorix 7.2.6 and Debian 13.7 with Secure Boot on (loaded by the new line, 3 extra amps found, both sides), and Ubuntu 26.04.1 (`CONFIG_I2C_CHARDEV=y`, unchanged). |

## Findings

None block the merge.

**1. Alternative considered, not recommended:** adding `i2c-dev` to
`/etc/modules-load.d/max98390-hda.conf` (written by `install.sh`, removed by
`uninstall.sh` and `max98390-hda-check-upstream.sh`). It would work, since the
unit is `After=systemd-modules-load.service`, but it loads the module on every
system permanently and still needs a reinstall. Loading only when the node is
missing is better.

**2. Not the cause of #100.** That reporter is on Fedora with a stock kernel
and no speaker-fix; the firmware leaves three amps off there. #100 stays open.

**3. No tests requested.** The repo has no speaker-fix tests (the only
`test-*.sh` covers libcamera).

## GitHub review comment (APPROVE)

> Thanks a lot @david-bartlett! The write-up in #120 made this an easy review: with `CONFIG_I2C_CHARDEV=m` and nothing loading `i2c-dev`, there's no `/dev/i2c-N`, every `i2cget` probe fails quietly, and the script only ever sees the ACPI `0x38` amp. Loading the module only when the node is missing is the right shape. It's a no-op on Fedora and Ubuntu, leaves nothing behind for the uninstaller to clean up, and is better than adding `i2c-dev` to `modules-load.d` for everyone. The four-distro test matrix (Fedora 45, MX Linux 25.3, Debian 13.7 with Secure Boot on, Ubuntu 26.04.1 with it built in) is really appreciated.
>
> I also checked the other places that could need the same fix: the NixOS module already loads `i2c-dev` through `boot.kernelModules`, and nothing else in the repo probes the host I2C bus, so this covers it.
>
> Merging now. It'll go out as v0.3.88, and existing Debian/MX users just need to re-run `sudo bash speaker-fix/install.sh` (or `sudo modprobe i2c-dev && sudo systemctl restart max98390-hda-i2c-setup.service`). Thanks again!

## Outcome

**Outcome (2026-10-18):** Head re-confirmed as `66a127f`, `MERGEABLE` / `CLEAN`,
just before approving. APPROVE review posted using the comment above, unchanged:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/122#pullrequestreview-5564857979>
(review 5564857979). Merged with a merge commit (`--match-head-commit 66a127f`)
as `dc5ab2f` at 20:44:12Z. #120 auto-closed via "Fixes #120" at 20:44:13Z.
After the merge, `find_present_addrs()` on `main` has the `modprobe i2c-dev`
line and the script passes `bash -n`.

Released as **v0.3.88**, titled "speaker-fix enables all amplifiers on
Debian / MX Linux (loads i2c-dev)". The notes tell existing Debian/MX users to
re-run `sudo bash speaker-fix/install.sh`, or
`sudo modprobe i2c-dev && sudo systemctl restart max98390-hda-i2c-setup.service`:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.88>.

No separate comment on #120: David filed both the issue and the PR, and the
approve review already names v0.3.88 and the re-install step.
