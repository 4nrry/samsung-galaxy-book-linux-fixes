# EasyEffects Presets for Galaxy Book Speakers (MAX98390)

The [speaker fix](../) gets all four speakers working, but out of the box they sound **thinner, flatter and quieter than on Windows** (see [Sound Quality & EQ](../README.md#sound-quality--eq)). These [EasyEffects](https://github.com/wwmm/easyeffects) output presets bring the sound closer to Windows (Dolby Atmos). They work entirely in software, so nothing in the driver changes, and they're optional.

There are four speaker presets in two sounds, plus one for headphones:

| Preset | Sound | Good for |
|---|---|---|
| **`GalaxyBook-Speakers-Warm`** | Closest to Windows/Dolby: fuller lower mids, softer treble | Pop, rap, some rock |
| **`GalaxyBook-Speakers-Warm-Loud`** | Same as Warm, about 5 dB louder (+4 dB limiter input) | As above, when Warm isn't loud enough |
| **`GalaxyBook-Speakers-Clear`** | Brighter, clearer mids and treble | Vocals, oldies, some rock |
| **`GalaxyBook-Speakers-Clear-Loud`** | Same as Clear, louder (+5 dB limiter input), with a retuned bass guard that keeps it clean at high volume | As above, when Clear isn't loud enough |
| **`GalaxyBook-Headphones`** | Gentle lift for the lows and low mids | Any headphones (wired or Bluetooth) — **not** the speakers |

Which one is "best" is a matter of taste, so try both sounds. The speaker presets have a 120 Hz high-pass and big boosts tuned for these small speakers, so they sound wrong on headphones; use [Autoload](#switch-presets-automatically-speakers-vs-headphones) to switch for you.

To check which speaker preset is loaded: **Effects → Limiter → input gain** shows **0 dB** for Warm and Clear, **+4 dB** for Warm-Loud and **+5 dB** for Clear-Loud. The Clear presets have 8 EQ bands; the Warm presets have 6.

## Tested on

| Laptop | Who | OS / EasyEffects |
|---|---|---|
| Galaxy Book5 Pro 14" (`940XHA`, subsystem `0x144dca08`) | [@david-bartlett](https://github.com/david-bartlett) | Fedora 45, EasyEffects 8.2.8 |
| Galaxy Book4 (`960XGL`, subsystem `0x144dc1d8`) | [@Andycodeman](https://github.com/Andycodeman) | Ubuntu, EasyEffects 8.1.2 |

The Warm preset was measured on the Book5 Pro 14". Other Book4/Book5 models with MAX98390 amps will probably benefit too, but the EQ won't match them exactly. Check your model's subsystem ID with:

```bash
grep -m1 "Subsystem Id" /proc/asound/card0/codec#0
```

## Install

You need the [speaker fix](../) installed and EasyEffects (native package or Flatpak):

```bash
# Ubuntu / Debian
sudo apt install easyeffects

# Fedora
sudo dnf install easyeffects

# Arch / CachyOS / Manjaro
sudo pacman -S easyeffects

# Flatpak (any distro)
flatpak install flathub com.github.wwmm.easyeffects
```

### With the script

Download and install in one step — no git required, and **no `sudo`** (presets live in your home folder):

```bash
curl -sL https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/archive/refs/heads/main.tar.gz | tar xz && cd samsung-galaxy-book-linux-fixes-main/speaker-fix/easyeffects-presets && ./install-presets.sh
```

**Already cloned?** `cd speaker-fix/easyeffects-presets && ./install-presets.sh`

The script copies the five presets into every EasyEffects preset folder that applies on your system (native EasyEffects 8+, the old EasyEffects 7 folder if it's still in use, and the Flatpak). It won't overwrite a preset of the same name that you've changed; run it with `--force` to replace it (your version is kept as `<name>.json.bak`). It doesn't load a preset or change your Autoload rules.

To remove them again: `./install-presets.sh --uninstall` (only removes the presets if you haven't changed them).

### By hand

Copy the `GalaxyBook-*.json` files into your EasyEffects output preset folder:

| EasyEffects | Folder |
|---|---|
| Native, version 8+ | `~/.local/share/easyeffects/output/` |
| Native, version 7.x | `~/.config/easyeffects/output/` |
| Flatpak | `~/.var/app/com.github.wwmm.easyeffects/data/easyeffects/output/` |

Or use **Presets → Output → Import** in EasyEffects and select the files.

### Then

Quit EasyEffects completely (tray icon → **Quit**) and start it again, then pick a preset in **Presets → Output**.

## Switch presets automatically (speakers vs headphones)

EasyEffects applies the loaded preset to **every** output. Use **Autoload** so the speaker preset only loads on the built-in speakers and the headphone preset on your headphones:

1. Open **Presets → Autoload**.
2. In **Device**, choose your built-in **Speaker** output (e.g. "Core Ultra 200V Series Processors HD Audio Speaker" on a Book5 Pro), not one of the HDMI / DisplayPort entries. The list is truncated, so widen the window if needed.
3. In **Local preset**, choose the speaker preset you like (e.g. `GalaxyBook-Speakers-Warm-Loud`), then click **Create**.
4. Check the new rule. Its **Device** line must end in `…Speaker__sink`. If it ends in `HDMI1__sink` (or similar), delete it and repeat step 2.
5. Connect your headphones, then repeat steps 2–3 with the headphone device and `GalaxyBook-Headphones`. Do this for each pair of headphones you use (wired and Bluetooth show up as separate devices).
6. **Fallback Preset:** this applies to every output *without* a rule. Turn it off, or set it to an empty "Flat" preset, so HDMI and other outputs play unprocessed.
7. Quit EasyEffects completely (tray icon → **Quit**) and start it again.

The fields at the top of the Autoload tab are only the form for creating a new rule. They don't show which preset is active.

## Plugins needed

The presets use these EasyEffects effects:

| Effect | Plugin | Used by |
|---|---|---|
| Stereo Tools, Bass Enhancer | Calf | Speaker presets |
| Exciter | Calf | Headphones |
| Equalizer, Compressor, Multiband Compressor, Limiter | LSP | All |
| Autogain | built into EasyEffects | Headphones |

LSP usually comes with the EasyEffects package. Calf often doesn't — if EasyEffects shows an effect as **"Not Available"**, install Calf as described in the [speaker-fix README](../README.md#improving-sound-quality-with-easyeffects).

## Loudness

Linux's volume slider is scaled differently from Windows' (on Linux, 50% is about −18 dB; on Windows, about −10 dB), and Dolby's leveller lifts quiet passages, so Windows sounds louder at the same percentage. For more range:

```bash
amixer -c0 sset Speaker 100%     # codec Speaker control defaults to ~92% (-5 dB)
```

Then use a **Loud** preset and/or your desktop's "Raise maximum volume" / over-amplification option. The limiter at the end of each speaker preset stops this from clipping.

## How they were made

- **Warm** was made from scratch by [@david-bartlett](https://github.com/david-bartlett): he recorded the speakers on Windows (Dolby on) and on Linux (speaker fix, no EasyEffects) playing pink noise and a song, and turned the difference into an EQ, then added a compressor, stereo widening, bass enhancement, a 120 Hz high-pass and a multiband "bass guard" against rattle. The full write-up is in [`GalaxyBook-Speakers-Warm-Design.md`](GalaxyBook-Speakers-Warm-Design.md).
- **Clear** combines Warm with Andy's `Book4-Middle-A` tweak (more mids and treble, louder), with the extra gain moved **before** the bass guard so loud, bass-heavy tracks don't rattle.
- **Headphones** is Andy's preset, based on JackHack96's *Advanced Auto Gain* with only the EQ changed: the 113–358 Hz boosts reduced from +4 dB to +1–2 dB, and the 0.7–1.8 kHz cuts softened.

Discussion and the original files: [#111](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111).

## Version history

The presets were renamed when they were added here; the settings are unchanged.

| Here | Earlier name in #111 |
|---|---|
| `GalaxyBook-Speakers-Warm` | `GalaxyBook5Pro-Windows-like-v2.3` / `GalaxyBook5Pro-Warm-2.3` |
| `GalaxyBook-Speakers-Warm-Loud` | `GalaxyBook5Pro-Windows-like-v2.3-Loud` / `GalaxyBook5Pro-Warm-Loud-2.3` |
| `GalaxyBook-Speakers-Clear` | `GalaxyBook5Pro-Windows-like-v2.4` / `GalaxyBook5Pro-Clear-2.4` |
| `GalaxyBook-Speakers-Clear-Loud` | `GalaxyBook5Pro-Windows-like-v2.4-Loud` / `GalaxyBook5Pro-Clear-Loud-2.4` |
| `GalaxyBook-Headphones` | `Headphones` |

- **v2.3 (Warm):** David's measured Windows-like preset.
- **v2.4 (Clear):** keeps the tone and loudness of `Book4-Middle-A`, but adds its extra gain before the bass guard instead of at the limiter (where it pushed the guarded bass back up and made the speakers rattle at high volume).

## Credits

- **[@david-bartlett](https://github.com/david-bartlett)** — `GalaxyBook-Speakers-Warm`, `-Warm-Loud`, `-Clear`, `-Clear-Loud` and the [design document](GalaxyBook-Speakers-Warm-Design.md) ([#111](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/111))
- **[@Andycodeman](https://github.com/Andycodeman)** — `GalaxyBook-Headphones`, the `Book4-Middle-A` tweak that Clear builds on, and the install script
- **[JackHack96](https://github.com/JackHack96/EasyEffects-Presets)** — `GalaxyBook-Headphones` is a modified version of *Advanced Auto Gain* from [JackHack96/EasyEffects-Presets](https://github.com/JackHack96/EasyEffects-Presets), Copyright (c) 2018 Matteo Iervasi, used under the MIT License. The full license text is in [`LICENSE-JackHack96`](LICENSE-JackHack96).
