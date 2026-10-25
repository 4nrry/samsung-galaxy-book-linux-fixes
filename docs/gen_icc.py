#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate Galaxy Book4 Ultra (Samsung OLED SDC4188) "Screen mode" ICC profiles
for KDE Plasma 6 (KWin per-output color profile) and GNOME/colord, from the panel's primaries.

On Windows, Samsung's ColorEngine only swaps the monitor's ICC profile:
  Vivid (AMOLED native) -> no correction       => on Linux: no profile (or sdc4188-vivid.icc)
  Natural (sRGB)        -> sRGB emulation      => on Linux: native panel profile (sdc4188-natural.icc)
  P3 / AdobeRGB         -> treat desktop RGB as P3 / AdobeRGB (sdc4188-p3.icc / sdc4188-adobergb.icc)
KWin assumes desktop content is sRGB and maps it through the output profile,
so an "emulation" profile P must satisfy  inv(P) * M_sRGB = inv(N) * M_target,
i.e.  P = M_sRGB * inv(M_target) * N   (N = native panel RGB->XYZ).

Uses liblcms2 through ctypes (installed by default with KDE/GNOME). No numpy needed.
Usage:  python3 docs/gen_icc.py [outdir] [--edid [PATH]]
"""
import ctypes
import ctypes.util
import os
import sys

D65 = (0.3127, 0.3290)
GAMMA = 2.2  # Samsung's SDC4188*.icm use curv gamma 2.199 on all channels

# Native panel primaries (xy), from the rXYZ/gXYZ/bXYZ tags of SDC4188.icm adapted to D65.
# Re-measure with a colorimeter for a per-unit profile if available.
NATIVE = ((0.680, 0.320), (0.231, 0.725), (0.136, 0.047))
SRGB = ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060))
P3 = ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060))
ADOBE = ((0.640, 0.330), (0.210, 0.710), (0.150, 0.060))


def xy_to_XYZ(x, y):
    return (x / y, 1.0, (1.0 - x - y) / y)


def inv3(m):
    a, b, c = m[0]
    d, e, f = m[1]
    g, h, i = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]


def mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def rgb_to_xyz(prims, white=D65):
    """RGB->XYZ matrix (columns = primaries' XYZ), normalized so RGB(1,1,1) = white with Y=1."""
    cols = [xy_to_XYZ(*p) for p in prims]
    m = [[cols[c][r] for c in range(3)] for r in range(3)]
    w = xy_to_XYZ(*white)
    mi = inv3(m)
    s = [sum(mi[r][k] * w[k] for k in range(3)) for r in range(3)]
    return [[m[r][c] * s[c] for c in range(3)] for r in range(3)]


def matrix_to_prims(m):
    out = []
    for c in range(3):
        X, Y, Z = m[0][c], m[1][c], m[2][c]
        t = X + Y + Z
        out.append((X / t, Y / t))
    return tuple(out)


class xyY(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("Y", ctypes.c_double)]


class xyYTriple(ctypes.Structure):
    _fields_ = [("Red", xyY), ("Green", xyY), ("Blue", xyY)]


def load_lcms():
    name = ctypes.util.find_library("lcms2") or "liblcms2.so.2"
    lib = ctypes.CDLL(name)
    lib.cmsBuildGamma.restype = ctypes.c_void_p
    lib.cmsBuildGamma.argtypes = [ctypes.c_void_p, ctypes.c_double]
    lib.cmsCreateRGBProfile.restype = ctypes.c_void_p
    lib.cmsCreateRGBProfile.argtypes = [ctypes.POINTER(xyY), ctypes.POINTER(xyYTriple),
                                        ctypes.c_void_p * 3]
    lib.cmsMLUalloc.restype = ctypes.c_void_p
    lib.cmsMLUalloc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.cmsMLUsetASCII.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
                                   ctypes.c_char_p]
    lib.cmsWriteTag.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]
    lib.cmsSaveProfileToFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.cmsCloseProfile.argtypes = [ctypes.c_void_p]
    lib.cmsFreeToneCurve.argtypes = [ctypes.c_void_p]
    lib.cmsMLUfree.argtypes = [ctypes.c_void_p]
    return lib


def read_edid(path):
    """Return (primaries, white, panel_id, model_str) from an EDID 1.x base block."""
    with open(path, "rb") as f:
        e = f.read()
    if len(e) < 128 or e[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        raise SystemExit(f"{path}: not an EDID")
    mfg = (e[8] << 8) | e[9]
    c1 = chr(((mfg >> 10) & 0x1F) + 64)
    c2 = chr(((mfg >> 5) & 0x1F) + 64)
    c3 = chr((mfg & 0x1F) + 64)
    prod = e[10] | (e[11] << 8)
    panel_id = f"{c1}{c2}{c3}{prod:04X}"
    model_str = ""
    for off in (54, 72, 90, 108):
        blk = e[off:off + 18]
        if blk[:3] == b"\x00\x00\x00" and blk[3] in (0xFC, 0xFE):
            s = blk[5:].decode("latin1", "replace").strip()
            if s:
                model_str = s
    lo1, lo2 = e[0x19], e[0x1A]
    lows = [(lo1 >> 6) & 3, (lo1 >> 4) & 3, (lo1 >> 2) & 3, lo1 & 3,
            (lo2 >> 6) & 3, (lo2 >> 4) & 3, (lo2 >> 2) & 3, lo2 & 3]
    v = [((e[0x1B + i] << 2) | lows[i]) / 1024 for i in range(8)]
    return ((v[0], v[1]), (v[2], v[3]), (v[4], v[5])), (v[6], v[7]), panel_id, model_str


def find_edid():
    import glob
    for p in sorted(glob.glob("/sys/class/drm/card*-eDP-*/edid")):
        try:
            with open(p, "rb") as f:
                if len(f.read()) >= 128:
                    return p
        except OSError:
            pass
    raise SystemExit("no eDP EDID found under /sys/class/drm; pass a path to --edid")


def write_profile(lib, path, prims, desc, white_xy=D65):
    white = xyY(white_xy[0], white_xy[1], 1.0)
    tri = xyYTriple(*(xyY(x, y, 1.0) for x, y in prims))
    curve = lib.cmsBuildGamma(None, GAMMA)
    curves = (ctypes.c_void_p * 3)(curve, curve, curve)
    h = lib.cmsCreateRGBProfile(ctypes.byref(white), ctypes.byref(tri), curves)
    if not h:
        raise SystemExit(f"lcms2 failed to build {path}")
    for sig in (0x64657363, 0x63707274):  # 'desc', 'cprt'
        mlu = lib.cmsMLUalloc(None, 1)
        text = desc if sig == 0x64657363 else "No copyright, generated by gen_icc.py"
        lib.cmsMLUsetASCII(mlu, b"en", b"US", text.encode())
        lib.cmsWriteTag(h, sig, mlu)
        lib.cmsMLUfree(mlu)
    lib.cmsSaveProfileToFile(h, path.encode())
    lib.cmsCloseProfile(h)
    lib.cmsFreeToneCurve(curve)


def build_set(native, white, suffix, label):
    """Profiles for one characterization of the panel (native primaries + white)."""
    N, S = rgb_to_xyz(native, white), rgb_to_xyz(SRGB)
    # Vivid (T = N) => P = S * inv(N) * N = S (identity gamut mapping in KWin).
    profiles = {
        f"sdc4188-vivid{suffix}.icc":
            (SRGB, white, f"Galaxy Book4 Ultra OLED - Vivid (AMOLED native){label}"),
        f"sdc4188-natural{suffix}.icc":
            (native, white, f"Galaxy Book4 Ultra OLED - Natural (sRGB){label}"),
    }
    for name, target, tl in (("p3", P3, "P3"), ("adobergb", ADOBE, "AdobeRGB")):
        T = rgb_to_xyz(target)
        P = mul(mul(S, inv3(T)), N)
        # P keeps the panel's own white (P*[1,1,1] = N*[1,1,1]).
        profiles[f"sdc4188-{name}{suffix}.icc"] = (matrix_to_prims(P), white,
                                                    f"Galaxy Book4 Ultra OLED - {tl} emulation{label}")
        # Sanity check against Samsung's MHC2 matrices:
        # T * inv(N) should be close (not identical: different adaptation/whitepoint handling).
        M = mul(T, inv3(N))
        print(f"{tl}{label}: T*inv(N) = " + " | ".join(" ".join(f"{v:7.4f}" for v in r) for r in M))
    return profiles


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Galaxy Book4 Ultra screen-mode ICC profiles")
    ap.add_argument("outdir", nargs="?", default=".")
    ap.add_argument("--edid", nargs="?", const="auto", metavar="PATH",
                    help="also build a set from the panel EDID (primaries + native white); "
                         "default path: /sys/class/drm/card*-eDP-*/edid")
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    lib = load_lcms()

    # Default set: primaries from Samsung's SDC4188.icm, white D65 (as Samsung's profile claims).
    profiles = build_set(NATIVE, D65, "", "")
    if a.edid:
        path = find_edid() if a.edid == "auto" else a.edid
        prims, white, panel_id, model_str = read_edid(path)
        tag = f"{panel_id} ({model_str})" if model_str else panel_id
        print(f"EDID {path} [{tag}]: primaries={prims} white={white} (Samsung ICC: {NATIVE}, D65)")
        # Note: EDID chromaticity is nominal (10-bit, per model). The two sets bracket the
        # truth; only a colorimeter measurement gives this unit's real primaries and white.
        profiles.update(build_set(prims, white, "-edid", " [EDID]"))

    for fname, (prims, white, desc) in profiles.items():
        path = os.path.join(a.outdir, fname)
        write_profile(lib, path, prims, desc, white)
        print(f"wrote {path}  white={tuple(round(v, 4) for v in white)} "
              f"primaries={[(round(x, 4), round(y, 4)) for x, y in prims]}")


if __name__ == "__main__":
    main()
