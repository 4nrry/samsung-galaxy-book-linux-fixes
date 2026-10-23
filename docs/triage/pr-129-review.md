# PR #129 review — "docs: Add performance modes guide and diagnostic script for Galaxy Book laptops"

VERDICT: **CHANGES REQUESTED** — not merged.

**Status (2026-10-23):** REQUEST_CHANGES review posted on head `f1b7fac`:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/129#pullrequestreview-5635165812>
(review 5635165812). Latest release is still v0.3.92.

Author: **@4nrry** (Anrry Petrin, NP960XGL-XG1BR — same author as #77/#128). 1 commit,
`MERGEABLE`/`CLEAN`, not a draft, no CI. +248/−0:

- `README.md` +8: new "Performance Modes & Power Limits" entry under "What's Included"
- `docs/performance-modes.md` +119: profile → `CSXI` → DTT/NPCF/EC, thermald MMIO RAPL, nvidia-powerd Dynamic Boost, EC registers
- `docs/check-performance.sh` +121 (mode 755): unprivileged diagnostic

## What was verified (on Andy's NP960XGL-XG1US, Ubuntu 26.04.1, kernel 7.0.0-38)

Ran the PR's script from a scratch copy (it only reads sysfs / systemctl / nvidia-smi).

- **The numbers corroborate.** `balanced`: MMIO RAPL long_term 40 W / short_term 64 W /
  peak_power 200 W, MSR RAPL PL1 200 W / PL2 115 W, `INTC1042:00/odvp0` = 2, EPP
  `balance_performance` — identical to the PR's table.
- thermald runs `--systemd --dbus-enable --adaptive` on Ubuntu.
- `bash -n` OK. shellcheck isn't installed here.

## Requested changes

1. **Doubled systemctl output.** `systemctl is-active X || echo inactive` — `is-active` prints
   `inactive` and exits 3, so the output is `inactive\ninactive` (reproduced). Same for
   `is-enabled`. Fix: `VAR=$(systemctl is-active X 2>/dev/null) || true`; a missing unit gives
   empty stdout from `is-enabled` → `${VAR:-not-found}`. Snippet tested.
2. **nvidia-smi failure shown as GPU model.** Driver installed but not loaded (Andy's case:
   no `nvidia` module, dGPU `D3cold`): nvidia-smi prints its error on **stdout**, exit 9;
   `head -n1` keeps it, pipefail fires `|| echo "NVIDIA GPU"` → garbage GPU model + power
   limits (reproduced). Fix: `if GPU_NAME=$(nvidia-smi …); then …; else "driver not loaded"`.
3. **Wrong advice when nvidia-powerd is enabled but failed.** Ubuntu's
   `nvidia-kernel-common-580` postinst runs `deb-systemd-helper enable nvidia-powerd.service`
   (`preset: enabled`). Andy's unit is enabled, exited `status=1/FAILURE` at boot (driver not
   loaded); the script still says `sudo systemctl enable --now nvidia-powerd`. Split
   not-enabled vs enabled-but-inactive.
4. **`power-saver` is not a `platform_profile` value** — it's the PPD name.
   `platform_profile_choices` here = `quiet balanced performance`; `0x0A` = `quiet`.
5. **`samsung-galaxybook` is in mainline**, not out-of-tree
   (`kernel/drivers/platform/x86/samsung-galaxybook.ko.zst` on Ubuntu 7.0).
6. **"disabled by default on Ubuntu, Fedora, Debian"** is wrong for Ubuntu (see 3). The
   postinst's "remove in trixie" comment hints the packaging is Debian-derived, so Debian may
   enable it too — only Ubuntu was checked.

Optional: the "55 W in all profiles" vs 20 W power-saver clamp wording; warn when thermald
isn't active (the MMIO heading says "applied by thermald"); nvidia-smi wakes a D3cold dGPU.

## Next step

When the author pushes, re-run the script on Andy's machine (same model, driver-not-loaded
case exercises 1–3) and re-check the doc wording. Docs + an unprivileged script only, so
merging alone needs no release tag; bundle into the next tag.
