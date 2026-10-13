# Issue #111 — EasyEffects presets for MAX98390 speakers

Opened 2026-10-11 by **@david-bartlett**: two EasyEffects output presets
tuned on his Galaxy Book5 Pro 14" (`940XHA`, subsystem `0x144dca08`, Fedora 45,
EasyEffects 8.2.8), `GalaxyBook5Pro-Windows-like-v2.3` and `-v2.3-Loud`
(+4 dB limiter input gain, compressor makeup 7 dB). He asked whether they help
on other Galaxy Book models.
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111>

## Book4-Middle-A preset reply — posted 2026-10-11

- Comment: <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111#issuecomment-6117106506>
- Gist (public): <https://gist.github.com/Andycodeman/57ede8653d942537689c78aaafbc90d8>
  (`Book4-Middle-A.json` + `Headphones.json`; both JSONs are also inline in the
  comment in `<details>` blocks)

Tested by Andy on his Book4 (`960XGL`, subsystem `0x144dc1d8`, Ubuntu,
EasyEffects 8.1.2): v2.3-Loud beat everything he had. `Framework-Philonmetal-Louder`
was louder but too treble-forward; v2.3-Loud the opposite. Middle-A aims between
them. It still distorts on some songs at very high volume.

**Book4-Middle-A** = the v2.3-Loud file with only these changes:

| Field | v2.3-Loud | Middle-A |
|---|---|---|
| EQ `num-bands` | 6 | 9 |
| EQ band6 (L+R) | — | Bell 2 kHz +0.9 dB, Q 1.4 |
| EQ band7 (L+R) | — | Bell 7.5 kHz +1.79 dB, Q 1.3 |
| EQ band8 (L+R) | — | Lo-shelf 110 Hz −6.7 dB, Q 0.71, x2 (keeps deep bass no stronger than v2.3-Loud) |
| Limiter `input-gain` | +4.0 dB | +10.5 dB |
| Limiter `gain-boost` | true | false (ceiling stays at the −1 dBFS threshold) |

Same plugin chain and order: Stereo Tools → Bass Enhancer → Equaliser →
Compressor → Multiband Compressor → Limiter. Andy's figure is "about 4 dB louder".

**Headphones** = Andy's headphone preset (JackHack96 Advanced Auto Gain with
bass/mids toned down; older un-suffixed plugin keys: equalizer → exciter →
autogain → limiter). Autoloaded for headphones, Middle-A for the speakers.

Neither file contains personal paths or usernames (no IRS/convolver file
references), so both were uploaded unmodified. The presets are not in the repo.

Asked David to try Middle-A (and Headphones) on his Book5 Pro and report back.

## Shipped — v0.3.79, 2026-10-12

David agreed to shipping the presets with credit and to the rename
([6131062873](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111#issuecomment-6131062873)).
Provenance ([6131352154](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111#issuecomment-6131352154)):
Warm was made from scratch from Windows-vs-Linux phone recordings (pink noise +
a song) analysed with Claude; Clear = Warm + Book4-Middle-A. He attached the
design doc in
[6132014925](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111#issuecomment-6132014925)
(already uses the new names; nothing personal beyond his phone model, shipped as-is).

- Commit `912875f`: `speaker-fix/easyeffects-presets/` — the 4 speaker presets
  (byte-identical to David's `GalaxyBook5Pro-{Warm,Warm-Loud}-2.3` /
  `{Clear,Clear-Loud}-2.4` attachments, checked with `cmp`),
  `GalaxyBook-Headphones.json` (byte-identical to the gist's `Headphones.json`),
  the design doc, README, `LICENSE-JackHack96` (MIT, Headphones is derived from
  Advanced Auto Gain: only EQ gains changed — 113–358 Hz +4 → +1–2 dB,
  0.7–1.8 kHz cuts softened), and `install-presets.sh` (user-level; native v8
  + old v7 dir if present + Flatpak; skip differing files unless `--force`,
  which keeps `.bak`; `--uninstall` removes unchanged copies and restores `.bak`).
  Not hooked into `speaker-fix/install.sh`.
- speaker-fix README "Improving sound quality with EasyEffects" points to these
  first; JackHack96 kept as the alternative. Top-level README Sound Quality note
  links the folder.
- Release: <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/releases/tag/v0.3.79>
- Thank-you comment: <https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111#issuecomment-6135181113>

Tested the script against temp HOMEs with stubbed `easyeffects`/`flatpak`:
none installed (error, exit 1), native only, Flatpak only (by `flatpak info`
and by `~/.var/app` dir), native + v7 dir + Flatpak, differing file with and
without `--force`, idempotent re-run, uninstall (incl. a user-edited file kept),
root refused; plus the real main-tarball one-liner after push. bash -n and
shellcheck 0.10.0 clean; all 5 JSONs parse.

Issue stays open: David will test Headphones with wired headphones and close it.
