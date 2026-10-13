# How the GalaxyBook-Speakers-Warm preset was made

`GalaxyBook-Speakers-Warm` and its Loud version were made by recording the laptop's speakers on Windows and on Linux and turning the difference into an EasyEffects preset.

- **Laptop:** Galaxy Book5 Pro 14" (`940XHA`), subsystem ID `0x144dca08`
- **Linux:** Fedora 45, KDE Plasma, PipeWire, EasyEffects 8.2.8, with Andy's `speaker-fix` installed

## 1. Recording setup

- **Phone:** Samsung Galaxy S26 Ultra, held **in landscape** on a **tripod**.
- **Position:** about **40 cm** from the laptop, centred in front of it. The phone, laptop and room were left exactly as they were for both systems; only the OS was changed by rebooting.
- **Microphones:** the phone's **top mic faced the left laptop speaker** and the **bottom mic faced the right**, so the recording's left and right channels matched the laptop's left and right speakers.
- **Recorder settings:** **stereo, 256 kbps** AAC at 48 kHz. A first attempt in mono at 128 kbps was replaced with stereo recordings, so the stereo width could be compared too.
- **Volume:** **50%** on both systems.
- **Windows:** Samsung's normal audio stack, with **Dolby Atmos on**.
- **Linux:** `speaker-fix` only, with **EasyEffects off**, so we were hearing the raw driver.
- **Quiet room:** no other noise, and the phone wasn't touched during a recording.

## 2. What was recorded

Each system was recorded playing the same two things, about a minute each:

1. **A pink-noise test file (58 s):**
   - a short 1 kHz beep, used to line the recordings up
   - 30 s of pink noise from both speakers
   - a short silence
   - 10 s from the left speaker only
   - 10 s from the right speaker only
2. **The same Spotify track,** *Tinie Tempah – Pass Out*, played over the same stretch of the song. Its heavy bass also made it a good test for rattle later on.

That made four recordings:

- `Windows-pink-noise`
- `Linux-pink-noise`
- `Windows-music`
- `Linux-music`

## 3. Comparing the recordings

- The recordings were converted to WAV and lined up: the pink noise by the beep, the music by matching the waveforms.
- Each pair was **level-matched** on the mid-range (300 Hz–3 kHz), so only the *tone* was compared, not the loudness.
- The frequency balance of Windows and Linux was compared across the whole range.
- The pink noise and the music gave matching results. They were combined (60% pink noise, 40% music) into one **correction curve**: what Linux needs to sound like Windows.

The main differences were:

- Linux was missing **lower-mid body** (roughly 200–500 Hz).
- Linux sounded **boxy/honky** around 900 Hz.
- Linux had less **treble and "air"** (roughly 6–16 kHz).
- Windows was **louder and more level**, from Dolby's volume leveller.

## 4. Turning it into a preset

- The correction curve was matched with a few EQ bands: a gentle lift around 240 Hz, a lift below 450 Hz, a cut at 880 Hz, a boost around 9 kHz and a top-end lift above 13 kHz.
- The result was **cross-checked against Samsung's own Dolby tuning** for this model, which is stored on the Windows partition. Its speaker EQ is mild, with no bass boost, which agreed with the recordings, and it limits the 234–844 Hz range at high volume (copied in section 5). No Samsung files are included in the preset.
- Further effects were added to copy what Dolby does:
  - a **compressor** for Dolby's volume leveller
  - **Stereo Tools** for a little extra width
  - a **Bass Enhancer** for the impression of deep bass the speakers can't play

## 5. Listening tests and fixes

- **Rattle on loud, bass-heavy music** was fixed by:
  - a **120 Hz high-pass**: the speakers can't usefully play below this, and energy there only makes the cones rattle
  - moving the **Bass Enhancer before the EQ**
  - adding a **multiband compressor** as a "bass guard", which holds back the bass below 230 Hz at high volume and limits 230–860 Hz the way Samsung's tuning does
- A **Loud** version was made: the same sound, about 5 dB louder, with a limiter at the end to prevent clipping.

## 6. What it can't copy

Windows also runs Maxim's speaker-protection software on the Intel audio DSP, with Samsung's settings for these exact speakers. That's what lets Windows play real bass below 120 Hz. Those settings can't be used on Linux, so **deep bass will always be weaker than on Windows**. The preset gets as close as the speakers safely allow.
