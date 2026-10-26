#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate Galaxy Book4 Ultra (Samsung OLED SDC4188) and generic EDID "Screen mode"
ICCv4 profiles for KDE Plasma 6 (KWin per-output color profile) and GNOME/colord.

On Windows, Samsung's ColorEngine only swaps the monitor's ICC profile:
  Vivid (AMOLED native) -> no correction       => on Linux: no profile (or *-vivid.icc)
  Natural (sRGB)        -> sRGB emulation      => on Linux: native panel profile (*-natural.icc)
  P3 / AdobeRGB         -> treat desktop RGB as P3 / AdobeRGB (*-p3.icc / *-adobergb.icc)
KWin assumes desktop content is sRGB and maps it through the output profile,
so an "emulation" profile P must satisfy  inv(P) * M_sRGB = inv(N) * M_target,
i.e.  P = M_sRGB * inv(M_target) * N   (N = native panel RGB->XYZ).

Uses liblcms2 through ctypes (installed by default with KDE/GNOME). No numpy needed.
Usage:  python3 docs/gen_icc.py [outdir] [--edid [PATH]] [--edid-d65] [--no-default]
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


def matrix_to_prims_and_white(m):
    """Extract primary (x, y) coordinates and the white point (x, y) of M*[1,1,1]."""
    out = []
    for c in range(3):
        X, Y, Z = m[0][c], m[1][c], m[2][c]
        t = X + Y + Z
        out.append((X / t, Y / t))
    wX, wY, wZ = sum(m[0]), sum(m[1]), sum(m[2])
    wt = wX + wY + wZ
    return tuple(out), (wX / wt, wY / wt)


class xyY(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double), ("Y", ctypes.c_double)]


class xyYTriple(ctypes.Structure):
    _fields_ = [("Red", xyY), ("Green", xyY), ("Blue", xyY)]


def load_lcms():
    name = ctypes.util.find_library("lcms2") or "liblcms2.so.2"
    try:
        lib = ctypes.CDLL(name)
    except OSError as e:
        raise SystemExit(f"liblcms2 not found ({e}); install liblcms2-2 / lcms2")
    lib.cmsBuildGamma.restype = ctypes.c_void_p
    lib.cmsBuildGamma.argtypes = [ctypes.c_void_p, ctypes.c_double]
    lib.cmsCreateRGBProfile.restype = ctypes.c_void_p
    lib.cmsCreateRGBProfile.argtypes = [ctypes.POINTER(xyY), ctypes.POINTER(xyYTriple),
                                        ctypes.c_void_p * 3]
    lib.cmsMLUalloc.restype = ctypes.c_void_p
    lib.cmsMLUalloc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.cmsMLUsetASCII.restype = ctypes.c_int
    lib.cmsMLUsetASCII.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p,
                                   ctypes.c_char_p]
    lib.cmsWriteTag.restype = ctypes.c_int
    lib.cmsWriteTag.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]
    lib.cmsSaveProfileToFile.restype = ctypes.c_int
    lib.cmsSaveProfileToFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.cmsCloseProfile.restype = ctypes.c_int
    lib.cmsCloseProfile.argtypes = [ctypes.c_void_p]
    lib.cmsFreeToneCurve.argtypes = [ctypes.c_void_p]
    lib.cmsMLUfree.argtypes = [ctypes.c_void_p]
    return lib


def read_edid(path):
    """Return (primaries, white, panel_id, model_str, gamma) from an EDID 1.x base block."""
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
    g_raw = e[0x17]
    gamma = (g_raw + 100) / 100.0 if g_raw != 0xFF else GAMMA
    return ((v[0], v[1]), (v[2], v[3]), (v[4], v[5])), (v[6], v[7]), panel_id, model_str, gamma


def find_edid():
    import glob
    for pat in ("/sys/class/drm/card*-eDP-*/edid", "/sys/class/drm/card*-*/edid"):
        for p in sorted(glob.glob(pat)):
            try:
                with open(p, "rb") as f:
                    if len(f.read()) >= 128:
                        return p
            except OSError:
                pass
    raise SystemExit("no EDID found under /sys/class/drm; pass a path to --edid")


def write_profile(lib, path, prims, desc, white_xy=D65, gamma=GAMMA):
    white = xyY(white_xy[0], white_xy[1], 1.0)
    tri = xyYTriple(*(xyY(x, y, 1.0) for x, y in prims))
    curve = lib.cmsBuildGamma(None, gamma)
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
    ok = lib.cmsSaveProfileToFile(h, path.encode())
    lib.cmsCloseProfile(h)
    lib.cmsFreeToneCurve(curve)
    if not ok:
        raise SystemExit(f"lcms2 failed to save {path}")


def build_set(native, white, prefix, suffix, title, label, gamma=GAMMA):
    """Profiles for one characterization of a display (native primaries + white)."""
    N, S = rgb_to_xyz(native, white), rgb_to_xyz(SRGB)
    # Vivid (T = N) => P = S * inv(N) * N = S (identity gamut mapping in KWin).
    profiles = {
        f"{prefix}-vivid{suffix}.icc":
            (SRGB, D65, f"{title} - Vivid (Native){label}", gamma),
        f"{prefix}-natural{suffix}.icc":
            (native, white, f"{title} - Natural (sRGB){label}", gamma),
    }
    for name, target, tl in (("p3", P3, "P3"), ("adobergb", ADOBE, "AdobeRGB")):
        T = rgb_to_xyz(target)
        P = mul(mul(S, inv3(T)), N)
        # Extract both the synthetic primaries and P*[1,1,1]'s chromaticity so the written
        # profile matches P even when the panel's white point differs from D65.
        p_prims, p_white = matrix_to_prims_and_white(P)
        profiles[f"{prefix}-{name}{suffix}.icc"] = (
            p_prims, p_white, f"{title} - {tl} emulation{label}", gamma
        )
        # Sanity check against MHC2-style 3x3 gamut matrices:
        M = mul(T, inv3(N))
        print(f"{tl}{label}: T*inv(N) = " + " | ".join(" ".join(f"{v:7.4f}" for v in r) for r in M))
    return profiles


def main():
    import argparse
    ap = argparse.ArgumentParser(description="Generate display screen-mode ICCv4 profiles")
    ap.add_argument("outdir", nargs="?", default=".")
    ap.add_argument("--edid", nargs="?", const="auto", metavar="PATH",
                    help="build a set from a display EDID (primaries + native white); "
                         "default: first /sys/class/drm/card*-eDP-*/edid, else any connected display")
    ap.add_argument("--edid-d65", action="store_true",
                    help="use D65 white point with the EDID primaries (recommended for external monitors)")
    ap.add_argument("--no-default", action="store_true",
                    help="skip the default Galaxy Book4 Ultra (SDC4188) factory profile set")
    a = ap.parse_args()
    if a.no_default and not a.edid:
        ap.error("--no-default needs --edid (nothing to generate)")
    os.makedirs(a.outdir, exist_ok=True)
    lib = load_lcms()

    profiles = {}
    if not a.no_default:
        # Default set: primaries from Samsung's SDC4188.icm, white D65 (as Samsung's profile claims).
        profiles.update(build_set(NATIVE, D65, "sdc4188", "", "Galaxy Book4 Ultra OLED", ""))

    if a.edid:
        path = find_edid() if a.edid == "auto" else a.edid
        prims, white, panel_id, model_str, gamma = read_edid(path)
        tag = f"{panel_id} ({model_str})" if model_str else panel_id
        print(f"EDID {path} [{tag}]: primaries={prims} white={white} gamma={gamma}")
        prefix = panel_id.lower()
        if panel_id == "SDC4188":
            title = "Galaxy Book4 Ultra OLED"
            suffix = "-edid-d65" if a.edid_d65 else "-edid"
            label = " [EDID D65]" if a.edid_d65 else " [EDID]"
        else:
            title = f"{panel_id} {model_str}".strip()
            suffix = ""
            label = ""
        use_white = D65 if a.edid_d65 else white
        profiles.update(build_set(prims, use_white, prefix, suffix, title, label, gamma))

    for fname, (prims, white, desc, gamma) in profiles.items():
        path = os.path.join(a.outdir, fname)
        write_profile(lib, path, prims, desc, white, gamma)
        print(f"wrote {path}  white={tuple(round(v, 4) for v in white)} "
              f"primaries={[(round(x, 4), round(y, 4)) for x, y in prims]}")


if __name__ == "__main__":
    main()
