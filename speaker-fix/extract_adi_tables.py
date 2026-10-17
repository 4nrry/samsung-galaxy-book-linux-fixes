#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build max98390-galaxybook.bin from the user's own Windows amp driver.

The Galaxy Book4 Ultra (codec SUBSYS 144D:C1D8) Windows driver ADIAmpDriver.sys
(Analog Devices 1.0.0.44) initialises each MAX98390 with a per-amp register table
and loads one DSM coefficient table per amp pair. This script reads those tables
from the .sys on the user's Windows partition so no vendor binary is redistributed.

Usage:
    python3 extract_adi_tables.py /mnt/windows/Windows/System32/DriverStore/FileRepository/adiampdriver.inf_amd64_*/ADIAmpDriver.sys
    sudo install -m 644 max98390-galaxybook.bin /lib/firmware/

Output format (little endian), parsed by max98390_hda_windows.c:
    "M98W", u16 version (1), u16 n_amps
    n_amps x { u16 n, n x { u16 reg, u16 val } }          per-amp byte registers
    u16 n_dsm, n_dsm x { u16 n, n x { u16 reg, u16 0, u32 val } }   DSM words
    u8 dsm_index[n_amps]                                   which DSM each amp gets
Amp index follows the I2C address order of the driver: 0x38, 0x39, 0x3C, 0x3D.
"""
import hashlib
import struct
import sys

KNOWN = {
    # sha256 of ADIAmpDriver.sys 1.0.0.44 -> table offsets for project C1D8
    "b24fa0920808d3aa846a5afd973663242fce81d84d13f4836aff95f23ddb8b8e": {
        "amps": [(0x9B10, 35), (0x9BF0, 35), (0x9BA0, 17), (0x9C80, 17)],  # 0x38 0x39 0x3C 0x3D
        "dsm": [(0x9CD0, 95), (0x9FD0, 40)],                                # pair A (0x38/0x39), pair B
        "dsm_index": [0, 0, 1, 1],
    },
}

# Registers that must differ between the left (slot 0) and right (slot 1) amp of a pair.
SLOT_REGS = {0x201B: (0x01, 0x02), 0x201D: (0x01, 0x02), 0x201F: (0xFE, 0xFD), 0x2021: (0x00, 0x01)}


def byte_table(b, off, n):
    t = [struct.unpack_from("<HH", b, off + 4 * i) for i in range(n)]
    if struct.unpack_from("<HH", b, off + 4 * n) != (0, 0):
        raise SystemExit(f"byte table at 0x{off:X} is not zero-terminated")
    for reg, val in t:
        if not (0x2000 <= reg <= 0x24FF and val <= 0xFF):
            raise SystemExit(f"implausible entry {reg:#x}={val:#x} at 0x{off:X}")
    return t


def dsm_table(b, off, n):
    t = []
    for i in range(n):
        reg, pad, val = struct.unpack_from("<HHI", b, off + 8 * i)
        if pad != 0 or not (0x2100 <= reg <= 0x23FF) or reg % 4:
            raise SystemExit(f"implausible DSM entry {reg:#x} at 0x{off + 8 * i:X}")
        t.append((reg, val))
    return t


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "max98390-galaxybook.bin"
    b = open(path, "rb").read()
    digest = hashlib.sha256(b).hexdigest()
    if digest not in KNOWN:
        raise SystemExit(f"unknown ADIAmpDriver.sys (sha256 {digest}); offsets only verified for "
                         "1.0.0.44 / b24fa092…. Do not guess: report the version.")
    k = KNOWN[digest]
    amps = [byte_table(b, o, n) for o, n in k["amps"]]
    dsms = [dsm_table(b, o, n) for o, n in k["dsm"]]

    # Sanity: L/R amps of each pair must be configured for different TDM slots.
    for idx, t in enumerate(amps):
        side = idx % 2
        regs = dict(t)
        for reg, vals in SLOT_REGS.items():
            if regs.get(reg) != vals[side]:
                raise SystemExit(f"amp {idx}: {reg:#x}={regs.get(reg)} (expected {vals[side]:#x})")

    blob = bytearray(b"M98W") + struct.pack("<HH", 1, len(amps))
    for t in amps:
        blob += struct.pack("<H", len(t)) + b"".join(struct.pack("<HH", r, v) for r, v in t)
    blob += struct.pack("<H", len(dsms))
    for t in dsms:
        blob += struct.pack("<H", len(t)) + b"".join(struct.pack("<HHI", r, 0, v) for r, v in t)
    blob += bytes(k["dsm_index"])
    open(out, "wb").write(blob)
    print(f"wrote {out} ({len(blob)} bytes): amps={[len(t) for t in amps]} "
          f"dsm={[len(t) for t in dsms]} sha256={hashlib.sha256(blob).hexdigest()[:16]}…")


if __name__ == "__main__":
    main()
