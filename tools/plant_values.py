r"""Reads Tier, BaseYield, DiseaseChance and HarvestXpFactor from cooked
FPD_* FarmPlantDataAsset packages (unversioned zen export data, UE 5.6).

Property order (from the exe's reflection data):
  0 DisplayName (Text), 1 Tier (Float), 2 Stages (Array<Object>),
  3 StageDisplayTexts (Array<Text>), 4 BaseYield (UInt32),
  5 DiseaseChance, 6 DiseaseChanceNotPreferred (Float), 7 HarvestableItem,
  8 SeedDropPerHarvestableItem, 9 HarvestVFX, 10 HarvestSFX, 11 PlantableIn,
  12 bIsBerryBush, 13 HarvestXpFactor (Float).
Reads up to BaseYield/DiseaseChance in order; HarvestXpFactor is reported
only when everything between is absent or skippable, else "?".

Usage: python plant_values.py <FPD_*.uasset> [...]
Needs ..\..\Bigger-Buckets\tools\zen_names.py (read-only reuse).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "Bigger-Buckets", "tools"))
from zen_names import names  # noqa: E402


def fragments(b, o):
    present, zero_flagged, idx = [], [], 0
    while True:
        f = struct.unpack_from("<H", b, o)[0]
        o += 2
        skip, has_zero, last, num = f & 0x7F, (f >> 7) & 1, (f >> 8) & 1, f >> 9
        idx += skip
        for _ in range(num):
            present.append(idx)
            if has_zero:
                zero_flagged.append(idx)
            idx += 1
        if last:
            break
    zero = set()
    if zero_flagged:
        n = len(zero_flagged)
        nbytes = 1 if n <= 8 else ((n + 31) // 32) * 4
        mask = int.from_bytes(b[o:o + nbytes], "little")
        o += nbytes
        for i, p in enumerate(zero_flagged):
            if mask >> i & 1:
                zero.add(p)
    return present, zero, o


def fstring(b, o):
    n = struct.unpack_from("<i", b, o)[0]
    o += 4
    if n == 0:
        return "", o
    if n > 0:
        return b[o:o + n - 1].decode("latin-1"), o + n
    n = -n
    return b[o:o + 2 * n - 2].decode("utf-16-le"), o + 2 * n


def ftext(b, o):
    o += 4  # flags
    hist = struct.unpack_from("<b", b, o)[0]
    o += 1
    if hist == 11:  # string table entry
        o += 8
        key, o = fstring(b, o)
        return "ST:" + key, o
    if hist == 0:
        _ns, o = fstring(b, o)
        _key, o = fstring(b, o)
        src, o = fstring(b, o)
        return src, o
    if hist == -1:
        has = b[o]
        o += 4
        if has:
            s, o = fstring(b, o)
            return s, o
        return "", o
    raise ValueError(f"text history {hist}")


def main():
    print(f"{'asset':22} {'name':28} {'tier':>5} {'yield':>5} {'disease':>7} {'xpFactor':>8}")
    for path in sys.argv[1:]:
        b = open(path, "rb").read()
        _nm, hs = names(b)
        present, zero, o = fragments(b, hs)
        v = {}
        try:
            for idx in range(0, 14):
                if idx not in present:
                    continue
                if idx in zero:
                    v[idx] = 0
                    continue
                if idx == 0:
                    v[0], o = ftext(b, o)
                elif idx in (1, 5, 6, 13):
                    v[idx] = round(struct.unpack_from("<f", b, o)[0], 4)
                    o += 4
                elif idx == 2:
                    n = struct.unpack_from("<i", b, o)[0]
                    o += 4 + 4 * n
                    v[2] = n
                elif idx == 3:
                    n = struct.unpack_from("<i", b, o)[0]
                    o += 4
                    for _ in range(n):
                        _t, o = ftext(b, o)
                    v[3] = n
                elif idx == 4:
                    v[4] = struct.unpack_from("<I", b, o)[0]
                    o += 4
                else:
                    break
        except Exception as e:  # noqa: BLE001
            v["err"] = str(e)
        name = os.path.basename(path)
        print(f"{name:22} {str(v.get(0, 'default')):28} {str(v.get(1, 'def')):>5} "
              f"{str(v.get(4, 'def')):>5} {str(v.get(5, 'def')):>7} "
              f"{str(v.get(13, 'def' if 13 not in present else '?')):>8}  present={present}")


if __name__ == "__main__":
    main()
