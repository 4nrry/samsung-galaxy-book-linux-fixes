# PR #128 review — "webcam-fix-libcamera: Add opt-in factory CCM tuning for OV02C10 (KBFC645)"

VERDICT: **READY TO MERGE**, but the PR is still a **draft**, so it was not merged.

**Status (2026-10-23):** APPROVE review posted on head `e4b45e4`:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/128#pullrequestreview-5633842305>
(review 5633842305). `gh pr merge` was refused ("Pull Request is still a draft"). I
did not flip it with `gh pr ready`, because that would override the author's own
"not done yet" signal. A follow-up comment asks them to mark it ready:
<https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/pull/128#issuecomment-6373715218>.
The latest release is still v0.3.91.

Reviewed: 2026-10-23. Author: **@4nrry** (Anrry Petrin, NP960XGL-XG1BR, the 26 MHz
board from #77). Head `e4b45e4`, 1 commit, `MERGEABLE`, no CI. +470/−0:

- `webcam-fix-libcamera/README.md` +23: new "Factory colour calibration (KBFC645
  module, opt-in)" section
- `webcam-fix-libcamera/tools/aiqb_to_libcamera.py` +292 (GPL-2.0-or-later, the same as the repo)
- `webcam-fix-libcamera/tools/NOTES-aiqb-format.md` +84
- `webcam-fix-libcamera/tuning/ov02c10-kbfc645.yaml` +71 (CC0, the same as the stock file)

`install.sh`, `tune-ccm.sh` and the stock `ov02c10.yaml` are untouched. The tuning is
strictly opt-in: the user copies it by hand.

## What was verified

- **The parser works on real Intel files.** It ran against the three public OV02C10
  `.aiqb` files at `/etc/camera/ipu6epmtl/` (`1BG203N3`, `1SG204N3`, `CIFME14`, from
  ipu6-camera-bins). The record walk ends exactly on the AIQB chunk boundary. Black
  level ≈ 64.7 (10-bit), record 25 CCMs with CTs 2224–6503 K, the record 15 locus, and
  LSC grids with centre = 1.00 and corners of 3.5–5.9× all decode sensibly. `--dump`
  works. With `--ccm-strength 0.45 --wb-gains 1.03,0.89,0.94` the output parses with
  PyYAML. The KBFC645 `.aiqb` itself is not available here.
- **The shipped YAML matches the documented formula.** Every row sums to
  1.03 / 0.89 / 0.94 (±0.0001), which is the trim × (blend of rows that each sum to 1).
  The CTs ascend (2669, 3556, 3816, 4503, 5892).
- **The algorithm list matches the stock file:** `BlackLevel` 4096, `Awb`, `Ccm`,
  `Agc`. There is no `Adjust`/`Lut`, so the libcamera version requirement (≥0.5) is
  unchanged.
- **The precedent is real.** libcamera patchwork 26643 is "[v2,3/9] ipa: simple: data:
  Add OV01A10 tuning file", CC0-1.0, derived from an `.aiqb`.

## Open question for the author (asked in the review)

**How does a user tell they have KBFC645?** The module name comes from the sensor's
ACPI `_DSM`, GUID `822ace8f-2814-4174-a56b-5f029fe079ee`, function 1:
`\_SB.PC00.LNK0._DSM` returns `ToString` of the NVS bytes `L0M0..L0MF` (DSDT on Andy's
NP960XGL-XG1US). These live in GNVS at `0x681D7000`, and `/dev/mem` is blocked by
Secure Boot lockdown. So Andy's own module is **unknown**. If the author has an easy
check (Windows Device Manager, the INF), add it to the README section.

## Follow-ups to apply on `main` after the merge (promised in the review)

1. **The section is in the wrong place.** It was inserted between "Desaturated,
   green-tinted or purple image (colour tuning)" and "Editing `ov02c10.yaml` has no
   effect". The first section ends "see the next entry first", which now points at the
   KBFC645 section. Move the new section below "Editing … has no effect".
2. **Missing `cd`.** The `cp tuning/…` and `cp ov02c10.yaml …` commands are
   cwd-relative. Add `cd webcam-fix-libcamera` first, the same as the `tune-ccm.sh`
   instructions.
3. **Explain what undoes the opt-in.** Re-running `install.sh` (every update, step
   11/14 copies the stock `ov02c10.yaml` into both dirs) or `tune-ccm.sh` silently puts
   the stock file back. Add a one-line note to re-copy the opt-in afterwards.
4. **`--lsc-json --lsc-ratio` gives a bare `KeyError: 33`** on files without record 33
   (reproduced on `1SG204N3` and `CIFME14`). Make it a `SystemExit` with a clear
   message in `lens_shading()`.

No release is needed for the merge alone. This is opt-in docs + a tool, and installed
behaviour doesn't change. Bundle it into the next tag (v0.3.92, with the #127 Electron
wording fix).
