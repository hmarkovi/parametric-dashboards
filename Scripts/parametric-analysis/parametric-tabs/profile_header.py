"""Header-only profile of a weekly NVLAX CSV: counts token families and shows compact samples."""
from __future__ import annotations

import csv
import re
import sys
from collections import Counter

csv.field_size_limit(1 << 30)

path = sys.argv[1] if len(sys.argv) > 1 else r"R:\Products\NVL\NVL-AX\Weekly data pull\Vmin_20261101.csv"
with open(path, newline="", encoding="utf-8-sig") as handle:
    header = next(csv.reader(handle))

print(f"columns: {len(header)}")
families: dict[str, list[str]] = {
    "vmin": [], "sicc": [], "upm": [], "ilas_dts": [], "ilas_other": [], "cdyn": [], "other": [],
}
for col in header:
    u = col.upper()
    if "UPSVF" in u:
        families["vmin"].append(col)
    elif "SICC" in u:
        families["sicc"].append(col)
    elif "UPM" in u:
        families["upm"].append(col)
    elif u.startswith("ILAS_") and u.endswith("_MAXDTS_C"):
        families["ilas_dts"].append(col)
    elif u.startswith("ILAS_"):
        families["ilas_other"].append(col)
    elif "CDYN" in u:
        families["cdyn"].append(col)
    else:
        families["other"].append(col)

for name, cols in families.items():
    print(f"\n== {name}: {len(cols)}")
    for col in cols[:6]:
        print("   ", col)

print("\n== UPM by sort insertion")
ins = Counter((re.search(r"SORT_U1\.U\d+", c) or [""])[0] if re.search(r"SORT_U1\.U\d+", c) else "none" for c in families["upm"])
print(ins.most_common(15))
print("\n== UPM columns NOT starting with UPM_ (or with S2T suffix etc.)")
for c in families["upm"]:
    if not c.startswith("UPM_") or c.endswith("S2T"):
        print("   ", c)
print("\n== UPM name stems")
stem = Counter(re.sub(r"^(?:TPI_UPM::)?UPM_\d*_?", "", c)[:45] for c in families["upm"] if not c.startswith("UPM_09"))
print(len(stem))
for s, n in stem.most_common(40):
    print("   ", n, s)

print("\n== vmin domains")
rx = re.compile(r"UPSVFPASSFLOW(?P<pu>[A-Z0-9]*)_(?P<flow>[A-Z]+)_(?P<dom>[A-Za-z0-9]+)_(?P<f>\d+(?:\.\d+)?)_(?P<i>\d+)$")
dom = Counter()
unmatched = []
for c in families["vmin"]:
    m = rx.search(c)
    if m:
        dom[(m["pu"], m["dom"])] += 1
    else:
        unmatched.append(c)
print(sorted(dom.items()))
print("unmatched vmin:", len(unmatched), unmatched[:8])

print("\n== sicc groups")
print(Counter(re.sub(r"\d+", "#", c)[:70] for c in families["sicc"]).most_common(12))
print("\n== other prefixes")
print(Counter(re.split(r"[_:\-.]", c)[0] for c in families["other"]).most_common(30))
print("\n== ilas_other tails")
print(Counter(re.sub(r"\d+(?:\.\d+)?", "#", c.rsplit("_", 1)[-1]) for c in families["ilas_other"]).most_common(10))
