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
