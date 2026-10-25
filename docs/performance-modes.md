# Performance Modes & Power Limits on Samsung Galaxy Book Laptops

This document details the reverse engineering, hardware power limits, and driver integration for performance modes on Samsung Galaxy Book laptops, specifically verified on the **Galaxy Book4 Ultra (NP960XGL)** with Intel Meteor Lake and NVIDIA GeForce RTX 4070 Laptop GPU.

A read-only diagnostic tool is provided:
```bash
./docs/check-performance.sh
```

---

## 1. How Platform Profiles Work on Samsung Hardware

On Samsung Galaxy Book laptops, changing the performance mode in Windows (via Samsung Settings or Fn+F11) or in Linux (via `powerprofilesctl set <profile>` or writing to `/sys/firmware/acpi/platform_profile`) executes an ACPI method call:

```asl
\_SB.SCAI.CSXI(0x91, 0x51, 0x03, <mode_value>)
```

This updates the internal firmware variable `PRF3` / `PFMD` and triggers three simultaneous actions:

1. **DTT (Intel Dynamic Tuning Technology):** `CHOV(0, mode)` writes `ODV0`, emits `Notify(\_SB.IETM, 0x88)` (ODVP changed), and sets `EC.DTTR = 1`.
2. **NVIDIA dGPU (NVPCF / Dynamic Boost):** Configures AC TGP offset (`ACBT`), target CPU power budget (`ATPP`), and Dynamic Boost min/max (`AMIT`/`AMAT`), emitting `Notify(\_SB.NPCF, 0xC0)` to the dGPU device.
3. **Embedded Controller (EC):** `CMDD(0xEE, [0x80, mode])` selects the corresponding fan curve table.

### Mode Mapping

On this model, `/sys/firmware/acpi/platform_profile_choices` exposes `quiet balanced performance`. Userspace tools such as `power-profiles-daemon` (`powerprofilesctl`) map `quiet` to `power-saver`:

| Linux `platform_profile` | `powerprofilesctl` Profile | Samsung Mode (Firmware `ODVP0`) | Samsung Name | Windows Equivalent |
|---|---|---|---|---|
| **`performance`** | **`performance`** | `21` (`0x15`) | High / Performance | Best Performance (aggressive EPP) |
| **`balanced`** | **`balanced`** | `2` (`0x02`) | Optimized / Balanced | Balanced |
| **`quiet`** | **`power-saver`** | `10` (`0x0A`) | Quiet / Low Noise | Balanced (quiet fan curve) |

The mainline `samsung-galaxybook` kernel driver (`drivers/platform/x86/samsung-galaxybook.c`) exposes `/sys/firmware/acpi/platform_profile` and calls `CSXI` with these exact values.

---

## 2. CPU Power Limits (DTT, GDDV, and `thermald`)

In Windows, CPU power limits (PL1/PL2/PL4) are managed by Intel DTT / IPF drivers reading the DataVault (`GDDV`).

On Linux, the standard thermal daemon (`thermald`) in `--adaptive` mode handles this:

1. It reads the compressed DataVault from `/sys/bus/platform/devices/INTC1042:00/data_vault` (an LZMA-compressed ESIF v2 `dptf` table containing 109 keys including `APAT`, `APCT`, `PSVT`, `ITMT`, and `PPCC`).
2. When the user switches platform profile, `odvp0` changes, and `thermald` writes the corresponding PL1 and PL2 limits to **MMIO RAPL** (`/sys/devices/virtual/powercap/intel-rapl-mmio/intel-rapl-mmio:0/`).

> [!NOTE]
> `/sys/class/powercap/intel-rapl:0/` reflects **MSR RAPL** registers, which remain at the factory base ceiling (`PL1 = 200 W`, `PL2 = 115 W`).
> However, on Intel mobile processors, the Power Control Unit (PCU) strictly enforces **`min(MSR, MMIO)`**. Because `thermald --adaptive` writes to MMIO RAPL, the limits are actively enforced by hardware within ~4 seconds of profile switching.

### Measured Power Limits on Galaxy Book4 Ultra (AC Power)

| `platform_profile` (`powerprofilesctl`) | `odvp0` | CPU PL1 (`MMIO`) | CPU PL2 (`MMIO`) | CPU PL4 (`MMIO`) | CPU EPP | Thermal Target (`PSVT SNS1`) |
|---|---|---|---|---|---|---|
| **`performance`** (`performance`) | `21` (`0x15`) | **70 W** | **95 W** | **200 W** | `performance` | **64.0 °C** |
| **`balanced`** (`balanced`) | `2` (`0x02`) | **40 W** | **64 W** | **200 W** | `balance_performance` | **56.0 °C** |
| **`quiet`** (`power-saver`) | `10` (`0x0A`) | **20–25 W** | **30 W** | **135–200 W** | `power` | **55.0 °C** |

---

## 3. Discrete GPU & Dynamic Boost (`nvidia-powerd`)

On Galaxy Book models equipped with NVIDIA discrete graphics (e.g., RTX 4070 Laptop GPU on Book4 Ultra), the base TGP is **55.00 W**.

To reach the full 80 W TGP available in Windows, the system requires **`nvidia-powerd.service`**.

### The Dynamic Boost Mechanism (`\_SB.NPCF`)

When `platform_profile` changes, the ACPI method `\_SB.NPCF` updates the power parameters:
- **`performance` (`0x15`):** AC TGP offset `ACBT = +10 W`, target CPU budget `ATPP = 35 W`, max Dynamic Boost `AMAT = +15 W`.
- **`balanced` (`0x02`):** `ACBT = 0 W`, `ATPP = 20 W`, max Dynamic Boost `AMAT = +10 W`.
- **`quiet` / `power-saver` (`0x0A`):** Disables Dynamic Boost (`DBAC = 1`) and sends EC D-notify `0xD4`, clamping the GPU to **20.00 W**.

The NVIDIA power daemon (`nvidia-powerd`) continuously computes the enforced power limit:
$$\text{Enforced Power Limit} = 55\text{ W} + \text{ACBT} + \text{clamp}(\text{ATPP} - P_{\text{CPU}},\; \text{AMIT},\; \text{AMAT})$$

### The 55 W Cap Problem on Linux

On some distributions, `nvidia-powerd.service` is installed by the NVIDIA driver packages but not enabled by default; on others (e.g. Ubuntu), it is enabled by package presets but can still be inactive if the NVIDIA kernel module was not loaded at boot.

- **Without `nvidia-powerd` active:** The GPU does not apply Dynamic Boost or profile transitions; in our measurements on the Book4 Ultra, `nvidia-smi` remained at the **55.00 W** base TGP across all three profiles (`performance`, `balanced`, and `quiet`).
- **With `nvidia-powerd` active:**
  - Idle in `performance` mode: `Current Power Limit: 65.00 W` (55 W base + 10 W offset).
  - Under heavy GPU load with CPU idle / blocking sync: Enforced limit scales up to **77.22 W – 80.00 W** (measured drawing **72.90 W @ 2355 MHz** on RTX 4070).
  - Under mixed load (CPU drawing ~29 W): Enforced limit scales to $65 + (35 - 29.1) \approx \mathbf{70.90\text{ W}}$.
  - In `quiet` (`power-saver`) mode: Enforced limit drops to **20.00 W**.

### Enabling `nvidia-powerd`

If `nvidia-powerd` is not enabled:
```bash
sudo systemctl enable --now nvidia-powerd
```

Verify with:
```bash
systemctl status nvidia-powerd
nvidia-smi -q -d POWER
```

---

## 4. Embedded Controller (EC) Register Verification

The EC RAM on the Galaxy Book4 Ultra maps registers controlling thermal notifications and fan states:

- **`LINX` (offset `0x75`):** Read as `0x00`. If this bit were set, Linux would block power notifications (`DNTF`) to the GPU. Confirming it is `0x00` verifies that GPU power notifications are fully functional.
- **`DTTR` (offset `0x77`):** Read as `0x01` (DTT mode active).
- **`OPST` (offset `0x82`):** Read as `0x02` (bit 1 active).

---

## 5. Diagnostic Tool

Run the read-only diagnostic script included in this repository to inspect your active profile, CPU limits, EPP, and GPU state (note that querying `nvidia-smi` briefly wakes the dGPU if it is suspended in `D3cold`):

```bash
./docs/check-performance.sh
```
