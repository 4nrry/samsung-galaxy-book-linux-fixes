# OLED Screen Modes & ICC Color Profiles (Galaxy Book4 Ultra `SDC4188`)

On Windows, Samsung Settings provides a **Screen mode** selector (**AMOLED Native / Vivid**, **Natural (sRGB)**, **DCI-P3**, **AdobeRGB**, and **Auto**) along with **Color tone** and **HDR+**.

Reverse engineering of Samsung's `ColorEngine.exe` (`SamsungColorEngineService`) on the **Galaxy Book4 Ultra (`NP960XGL`, 16" 2880×1800 120 Hz OLED panel `SDC4188` / `ATNA60CL07-0`)** shows that **none of the screen modes use ACPI, firmware, DPCD, or DDC/CI**. Instead, switching modes on Windows simply swaps the display's active ICC profile via Windows Color System (`WcsSetDefaultColorProfile` / `ColorProfileSetDisplayDefaultAssociation`).

Because modern Linux Wayland compositors (such as **KDE Plasma 6 / KWin** and **GNOME / Mutter**) support per-output ICC color management, all four gamut modes can be reproduced natively on Linux using standard open-source ICC profiles generated from the panel's chromaticity coordinates.

---

## 1. Checking Your Panel ID on Linux

The default profile coordinates in [`docs/gen_icc.py`](gen_icc.py) target the 16" 2880×1800 Samsung OLED panel **`SDC4188`** (`ATNA60CL07-0`) used in the Galaxy Book4 Ultra (`NP960XGL`).

You can verify your panel's EDID manufacturer/product ID and model string without root privileges:

```bash
python3 -c '
import glob
for p in sorted(glob.glob("/sys/class/drm/card*-eDP-*/edid")):
    e = open(p, "rb").read()
    if len(e) >= 128:
        mfg = (e[8] << 8) | e[9]
        cid = "".join(chr(((mfg >> s) & 0x1f) + 64) for s in (10, 5, 0))
        prod = e[10] | (e[11] << 8)
        print(f"{p}: {cid}{prod:04X}")
'
```

On the Galaxy Book4 Ultra, this prints:
```text
/sys/class/drm/card1-eDP-1/edid: SDC4188
```

> **Other Galaxy Book OLED panels:** Passing `--edid` to `gen_icc.py` reads the R/G/B primaries and native white point directly from `/sys/class/drm/card*-eDP-*/edid` (bytes `0x19–0x22`), allowing you to generate `-edid.icc` profiles from your own panel's EDID block.

---

## 2. Generating the ICC Profiles

[`docs/gen_icc.py`](gen_icc.py) uses `liblcms2` (`liblcms2.so.2`, installed by default on KDE Plasma and GNOME desktops) via Python's built-in `ctypes` module — no third-party Python packages (`numpy`, `pip`) or proprietary vendor files are required.

```bash
python3 docs/gen_icc.py ~/.local/share/icc --edid
```

This creates two sets of four ICCv2 profiles in `~/.local/share/icc/`:

| Profile | Equivalent Samsung Mode | Description |
|---|---|---|
| **`sdc4188-vivid.icc`** | **AMOLED Native (Vivid)** | Identity gamut mapping (`P = sRGB`). Delivers the panel's full native wide gamut (wider than DCI-P3), matching `Color profile: None` while keeping a selectable `.icc` file. |
| **`sdc4188-natural.icc`** | **Natural (sRGB)** | Maps standard sRGB desktop content accurately onto the OLED panel's native primaries, eliminating oversaturation in web/video/UI content. |
| **`sdc4188-p3.icc`** | **DCI-P3** | Emulates a DCI-P3 display on the desktop (`P = M_sRGB · inv(M_P3) · N`). Balanced vibrant colors without oversaturating skin tones—ideal for games and media. |
| **`sdc4188-adobergb.icc`** | **AdobeRGB** | Emulates the AdobeRGB (1998) gamut (`P = M_sRGB · inv(M_AdobeRGB) · N`), expanding greens and cyans for photography workflows. |

### Default Set (`sdc4188-*.icc`) vs. EDID Set (`sdc4188-*-edid.icc`)

- **`sdc4188-*.icc` (Recommended — matches Windows):** Uses the primary coordinates from Samsung's factory characterization with a standard **D65 (`6500 K`)** white point `(0.3127, 0.3290)`. White balance remains neutral and matches Windows 11.
- **`sdc4188-*-edid.icc`:** Uses the nominal 10-bit chromaticity coordinates stored in the panel's hardware EDID, which declares a cooler native white point of `(0.3047, 0.3213)` (`~7000 K`). Because the compositor adapts the declared `~7000 K` panel white to D65, these profiles produce a noticeably warmer/more yellow white point (identical to selecting `Built-in` in KDE Plasma 6).

---

## 3. Applying Profiles on Linux

### KDE Plasma 6 (Wayland)

**Via System Settings (GUI):**
1. Open **System Settings → Display & Monitor → Display Configuration**.
2. Set **Color profile** to **`ICC profile`**.
3. Click the folder icon on the **ICC profile** path field that appears below and select one of the generated files from `~/.local/share/icc/` (press `Ctrl+H` in the file dialog if `.local` is hidden), then click **Apply**.

> **Other KDE Display Settings on `SDC4188`:**
> - **Refresh rate:** `120.00 Hz` (matches Windows `SEC_Mon.inf` `EnableBoostRefreshRateByDefault=1`).
> - **Adaptive sync:** `Never` on the desktop prevents OLED VRR gamma flicker on dark grey backgrounds.
> - **Color accuracy:** `Prefer color accuracy` prevents near-black banding on OLED gradients; switch to `Prefer efficiency` on battery or during fullscreen 3D gaming on the dGPU to reduce iGPU compositor load.
> - **Limit color resolution to:** `12 bits per color` (or `10 bits`).

**Via Command Line (`kscreen-doctor`):**
```bash
# Find your internal panel output name (usually eDP-1)
kscreen-doctor -o

# Switch to Natural (sRGB)
kscreen-doctor output.eDP-1.iccprofile."$HOME/.local/share/icc/sdc4188-natural.icc"

# Switch to DCI-P3
kscreen-doctor output.eDP-1.iccprofile."$HOME/.local/share/icc/sdc4188-p3.icc"

# Switch to AdobeRGB
kscreen-doctor output.eDP-1.iccprofile."$HOME/.local/share/icc/sdc4188-adobergb.icc"

# Switch to Vivid (AMOLED Native) via ICC file or by clearing the profile
kscreen-doctor output.eDP-1.iccprofile."$HOME/.local/share/icc/sdc4188-vivid.icc"
# or:
kscreen-doctor output.eDP-1.iccprofile.""
```

### GNOME (Wayland / X11)
1. Open **Settings → Color**.
2. Select the built-in OLED display, click **Add profile → Import file…**, and choose the desired `.icc` file from `~/.local/share/icc/`.

---

## 4. How Samsung's `ColorEngine` Works on Windows

Static analysis of `ColorEngine.exe` (`C:\Program Files\Samsung\ColorEngine\ColorEngine.exe`) and its configuration files (`C:\ProgramData\ColorMode\CeData\Intel*.ini`) reveals the following architecture:

| Windows Mode (`ColorModeValue`) | Internal Enum | Action Taken by `ColorEngine.exe` |
|---|---|---|
| `0` (**Auto**) | `MODE_AUTO` | Associates `SDC4188Settings.icm` (no `MHC2` tag) and switches CSC matrices per active foreground app (`IntelConfigs.ini`). |
| `1` (**DCI-P3**) | `MODE_P3` | Associates `SDC4188P.icm` (contains `MHC2` 3×4 gamut matrix + identity 1D LUT). |
| `2` (**AMOLED Native / Vivid**) | `MODE_AMOLED_NATIVE` | Default factory mode. Associates base `SDC4188.icm` (no `MHC2` tag -> uncalibrated native panel gamut). |
| `3` (**AdobeRGB**) | `MODE_ADOBERGB` | Associates `SDC4188A.icm` (contains `MHC2` 3×4 gamut matrix + identity 1D LUT). |
| `5` (**Natural / sRGB**) | `MODE_NATURAL` | Associates `SDC4188S.icm` (contains `MHC2` 3×4 gamut matrix + identity 1D LUT). |

### Panel Native Primaries (`SDC4188`)
The native panel colorants adapted to D65 `(0.3127, 0.3290)` with tone response curve $\gamma = 2.2$ (`2.199` across R, G, B) are:
- **Red:** $(x, y) = (0.680, 0.320)$
- **Green:** $(x, y) = (0.231, 0.725)$
- **Blue:** $(x, y) = (0.136, 0.047)$

### Emulation Matrix Derivation for KWin
KWin assumes untagged desktop applications are sRGB ($M_{\text{sRGB}}$) and transforms pixel linear RGB to the panel using $\text{inv}(P) \cdot M_{\text{sRGB}}$, where $P$ is the RGB$\rightarrow$XYZ matrix of the assigned output ICC profile.

To emulate a target color space $M_{\text{target}}$ (such as sRGB, DCI-P3, or AdobeRGB) on a panel whose physical RGB$\rightarrow$XYZ matrix is $N$, the hardware needs to apply $\text{inv}(N) \cdot M_{\text{target}}$. Equating the two gives the synthetic ICC profile matrix $P$:

$$P = M_{\text{sRGB}} \cdot M_{\text{target}}^{-1} \cdot N$$

- For **Natural (sRGB)** ($M_{\text{target}} = M_{\text{sRGB}}$): $P = N$ (the panel's true native primaries).
- For **Vivid (AMOLED Native)** ($M_{\text{target}} = N$): $P = M_{\text{sRGB}}$ (identity mapping in KWin).
- For **DCI-P3** and **AdobeRGB**: `gen_icc.py` computes $P$, extracts its synthetic $(x, y)$ primaries while preserving the white point ($P \cdot [1,1,1]^T = N \cdot [1,1,1]^T$), and writes a standard matrix/TRC ICC profile via `liblcms2`.

### Notes on Color Tone and HDR+
- **Color Tone (Cool / Warm):** In Windows, `ColorEngine.exe` applies diagonal RGB multipliers (`ColortoneValue` `0..4`) by uploading a $17 \times 17 \times 17$ 3D LUT via Intel IGCL (`ctlPixelTransformationSetConfig`). On Linux, equivalent warm color temperature adjustments are natively handled by KDE **Night Light** or GNOME **Night Light**.
- **HDR+ (`ModuleHdrPlus`):** Windows "HDR+" is not HDR10; it enables **Intel LACE** (*Local Adaptive Contrast Enhancement*, hardware block controlled via IGCL `ctlSetLACEConfig`) combined with a partial-saturation 3D LUT (`IntelConfigsV4.ini [HDRPLUS]`). The upstream Linux `i915`/`xe` kernel drivers do not expose a uAPI for Intel LACE. For true HDR10 content on Linux, enable the **High Dynamic Range (HDR)** toggle in KDE Plasma 6 / GNOME display settings.
