# PR #133 review — "feat(speaker-fix): optional Windows-matching MAX98390 init for Book4 Ultra"

VERDICT: **CHANGES REQUESTED** on head `64b33ee`; review 5659451001:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/133#pullrequestreview-5659451001>

Author: **@4nrry** (NP960XGL, same author as #77/#128/#129/#131/#132). 1 commit, +323/−11, MERGEABLE.
Adds `extract_adi_tables.py` (builds `/lib/firmware/max98390-galaxybook.bin` from the user's own
`ADIAmpDriver.sys` 1.0.0.44, sha-pinned) and `max98390_hda_windows.c` (loads it at probe, per-amp
byte table + per-pair DSM words, falls back to Redrix blobs when absent / `windows_tuning=0`).

## Verified

- Builds clean on 7.0.0-38-generic; Nix module uses the Makefile so it picks up the new object.
- Script on a synthetic `.sys` at the PR's offsets → 1522 bytes, amps 35/35/17/17, dsm 95/40.
- `m98w_parse()` userspace port under ASan/UBSan: right tables for idx 0–3, all truncations
  rejected, 200k mutations → no OOB.
- Resume re-runs init with fw held (#98 path covered). Amps end enabled after init — same as the
  built-in path (`max98390_configure_high_pass_filter` writes 0x203A=0x81, 0x23FF=0x01).
- Andy's machine is `0x144dc1d8` but has no NTFS partition → not run against the real `.sys`.

## Asked

1. **Blocking:** README glob `adiampdriver.inf_amd64_*/ADIAmpDriver.sys` + `argv[2]` = output →
   with two DriverStore versions the 2nd driver file is overwritten by the blob (reproduced).
   Fix: all args are candidate inputs, pick the KNOWN sha, fixed output / `-o`; README `-o ro`.
2. **Should:** script checks codec Subsystem Id `0x144dc1d8` (`--force` escape) — kernel applies
   the file on any model.
3. Nits: playback_hook order change touches the default path too; NixOS needs `hardware.firmware`.

Side note for #93: Windows itself sets tweeter `0x23BA=0x8D` on the Ultra (woofers `0x94`, not our
`0xA0`), which weakens the R3 "driver attenuates tweeters" idea, at least on this model.
