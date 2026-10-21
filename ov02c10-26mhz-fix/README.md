# OV02C10 26 MHz Clock Fix (DKMS)

**Test fix** for Samsung Galaxy Book 3/4 models where the OV02C10 camera sensor
fails to probe with:

```
ov02c10 i2c-OVTI02C1:00: error -EINVAL: external clock 26000000 is not supported
```

## What this fixes

The upstream kernel's `ov02c10` driver only accepts a 19.2 MHz external clock.
Some IPU6 boards provide 26 MHz instead. This DKMS module patches the driver to
accept both frequencies.

Based on the patch from:
https://lore.kernel.org/linux-media/CAKP_te-WT+HTEyhSvQ3snEOaTp5B1OUL18JjuzO238=_fTOuXQ@mail.gmail.com/

The 26 MHz clock is a **per-board property, not a platform property** — it shows
up on both Raptor Lake and Meteor Lake IPU6. Confirmed affected models:

- Galaxy Book4 Pro **940XGK** — Raptor Lake, subsystem ID `0x144dca07`
- Galaxy Book4 Ultra **NP960XGL-XG1BR** — Meteor Lake IPU6 `8086:7d19`
- Galaxy Book3 Pro 14" **940XFG** — Raptor Lake IPU6 `8086:a75d`, NixOS,
  kernel 7.2.4-cachyos — **fix confirmed working**
  ([#95](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/95))
- Book3/Book4 Ultra Raptor Lake variants

**It is not even model-determined.** Note the full SKU on the Book4 Ultra entry
above — a different **960XGL** board (Meteor Lake IPU6 `8086:7d19`, same model
designation) runs the stock in-tree `ov02c10` with no clock error at all, and
does **not** need this fix. Two boards of the same model on the same platform
can disagree, so treat the list above as "these were seen affected", never as
"this model is affected".

So don't decide by platform, and don't decide by model: check `dmesg` for the
error above. That is exactly what `webcam-fix-libcamera/install.sh` does — it
greps for the clock rejection and offers this fix, regardless of which IPU6
generation or model the board is.

## Requirements

- Linux kernel with in-tree `ov02c10` driver (kernel 6.8+, tested up to 7.2.4)
- `dkms` and kernel headers (the install script will try to install these)
- Samsung Galaxy Book with IPU6 + OV02C10 sensor rejecting the 26 MHz clock
  (Raptor Lake or Meteor Lake — confirm in `dmesg`, see above)

## Secure Boot

If Secure Boot is **enabled** (common on Ubuntu/Zorin out of the box), an
unsigned DKMS module is silently rejected by the kernel, which then loads the
distro-signed *in-tree* driver — and that one still rejects the 26 MHz clock.
The result looks like "I ran the fix and rebooted but the camera still doesn't
work". `install.sh` now detects this: it configures DKMS to sign the module
with a MOK key and queues the key for enrollment. **You must complete the blue
MOK Manager enrollment screen on the next reboot** (enter the one-time password
you set), otherwise the patched driver will never load. Alternatively, disable
Secure Boot in the BIOS.

## A note on `clk_freq`

If you see `ov02c10: unknown parameter 'clk_freq' ignored` in `dmesg`, that is
**not** the cause of the failure — this driver (and the upstream one) has no
`clk_freq` module parameter. It comes from a stale
`/etc/modprobe.d/*.conf` left over from an older community workaround.
`install.sh` automatically comments it out (with a `.bak` backup).

**On NixOS?** Don't run the installer — use
[`../nixos/ov02c10-26mhz-fix.nix`](../nixos/ov02c10-26mhz-fix.nix) and set
`hardware.samsungGalaxyBook.ov02c10ClockFix.enable = true;`. See
[`../nixos/README.md`](../nixos/README.md).

## Install

```bash
sudo bash install.sh
```

## Verify

After installing, check that the driver loaded without the clock error:

```bash
dmesg | grep -i ov02c10
```

You should no longer see `external clock 26000000 is not supported`. On a
26 MHz board you should instead see one line like:

```
ov02c10 i2c-OVTI02C1:00: 26000000Hz clock (not 19200000Hz): sensor runs fast; advertising link_freq=541666666 pixel_rate=216666666 and padding vts to ... for ~30fps
```

If that line is missing `link_freq=`, the installed module predates v0.3.89 —
re-run `sudo bash install.sh`.

## Uninstall

```bash
sudo bash uninstall.sh
```

This removes the DKMS module and restores the stock kernel driver.

## How it works

The patched driver makes three changes to the stock one. The last two only
apply on a 26 MHz board — on a 19.2 MHz board the driver behaves exactly like
the stock one.

1. **Accept the 26 MHz clock** in `ov02c10_probe()`:

   ```c
   // Stock driver:
   if (freq != OV02C10_MCLK)  // OV02C10_MCLK = 19200000

   // Patched driver:
   if (freq != OV02C10_MCLK_19_2MHZ && freq != OV02C10_MCLK_26MHZ)
   ```

   This is the exact same fix proposed in the upstream kernel mailing list
   patch. It does **not** re-time the sensor's PLL (nobody has the datasheet),
   so on a 26 MHz board the whole sensor clock tree runs 26/19.2 ≈ 1.354× fast.

2. **Correct `pixel_rate` and pad the frame** ([#71](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/71)).
   The driver advertises the real pixel rate (~217 MPix/s instead of 160) so
   libcamera's AGC computes real exposure times, and pads the frame with
   vertical blanking so it runs at ~30 fps instead of ~40.7.

3. **Correct the CSI-2 link frequency** ([#123](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/123)).
   The driver advertises the real link frequency (~542 MHz instead of 400).
   IPU6 programs its CSI-2 receiver timing from this value — and on Meteor Lake
   also the PHY frequency band — so the stale 400 MHz value can leave the link
   unstable. The firmware still declares 400 MHz, so the probe-time firmware
   check keeps matching 400 MHz.

## Troubleshooting

### `csi2-N error: Frame sync error` on a 26 MHz board

A single `Frame sync error` logged once each time the stream starts — about
250-300 ms after `camera-relay` logs `Client connected` — is normal and
harmless. It was measured on an NP960XGL-XG1BR with both the old 400 MHz and
the corrected ~542 MHz link frequency, with none during streaming and a
correct image at 30 fps
([#123](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes/issues/123)).
Only errors that keep appearing while the camera is streaming need the steps
below.

If `dmesg` keeps showing `csi2-4 error: Frame sync error` (or another
`csi2-N`) during capture, check the `Verify` line above. If it doesn't show
`link_freq=`, your installed module still reports the stale 400 MHz link
frequency — re-run `sudo bash install.sh` and reboot. If the line is correct
and the errors continue, see the Frame sync section of the
[webcam-fix troubleshooting](../webcam-fix/README.md#intermittent-black-frames--frame-sync-error)
(IVSC boot race).
