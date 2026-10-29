#!/usr/bin/env python3
"""Merge raw TRACE get_vmin "Final" mode CSVs (one per job x domain pull,
columns: DomainName,VisualId,FlowIndex,FinalFlowIndex,ValueType,CornerName,
CoreNumber,CoreName,Value,Frequency,SetterInstancePath,Pattern,
IsFinalValueForCorner,BaseValue,Ticks) into the VF Curve Optimizer's input
CSV schema (Visual_ID,Test_Name,Core,X_Axis_Value,Frequency_GHz,Vmin_V,
Sweep_Floor_V,At_Sweep_Floor,Notes).

Reduction rules:
- Each (Domain, VisualId, CoreNumber) is kept as its own independent data
  point - cores are NOT reduced/collapsed (Vmin can differ meaningfully
  between cores of the same unit). CCF has a single core (CoreNumber 0).
- Across different job pulls (DOE lots), if the same
  (Domain, VisualId, CoreNumber, Frequency) recurs (overlap/QA points), the
  per-job values are averaged.
- Rows with a blank Value (untested/bypassed corner-core) are skipped.
"""

import argparse
import csv
from collections import defaultdict
from pathlib import Path


def load_raw(csv_path):
    """Returns {(domain, visual_id, core, freq_hz): [value, ...]} - values
    collected within this single file (normally just one, but averaged
    defensively if a corner/core/frequency repeats within one job pull)."""
    per_key = defaultdict(list)
    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            val = (row.get("Value") or "").strip()
            freq_hz = (row.get("Frequency") or "").strip()
            if val == "" or freq_hz == "":
                continue
            key = (row["DomainName"], row["VisualId"], row["CoreNumber"], freq_hz)
            per_key[key].append(float(val))

    return {key: sum(vals) / len(vals) for key, vals in per_key.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw_csvs", nargs="*", default=[], help="Raw get_vmin Final-mode CSV paths (one per job x domain pull)")
    parser.add_argument("--file-list", help="Path to a text file with one raw CSV path per line (alternative to passing them as args)")
    parser.add_argument("-o", "--output", required=True, help="Output CSV path (VF Curve Optimizer schema)")
    args = parser.parse_args()

    raw_csvs = list(args.raw_csvs)
    if args.file_list:
        with open(args.file_list, encoding="utf-8-sig") as f:
            raw_csvs.extend(line.strip() for line in f if line.strip())
    if not raw_csvs:
        parser.error("no raw CSVs given - pass paths as args or via --file-list")

    stage1 = defaultdict(list)  # (domain, visual_id, core, freq_hz) -> [per-job value, ...]
    for path in raw_csvs:
        for key, value in load_raw(path).items():
            stage1[key].append(value)

    rows_out = []
    for (domain, vid, core, freq_hz), vals in stage1.items():
        vmin = sum(vals) / len(vals)
        rows_out.append((domain, vid, core, float(freq_hz) / 1e9, vmin, len(vals)))

    domain_freqs = defaultdict(set)
    for domain, vid, core, freq_ghz, vmin, n in rows_out:
        domain_freqs[domain].add(round(freq_ghz, 4))
    domain_freq_index = {d: {f: i for i, f in enumerate(sorted(fs))} for d, fs in domain_freqs.items()}

    out_path = Path(args.output)
    rows_out.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Visual_ID", "Test_Name", "Core", "X_Axis_Value", "Frequency_GHz", "Vmin_V", "Sweep_Floor_V", "At_Sweep_Floor", "Notes"])
        overlap_count = 0
        for domain, vid, core, freq_ghz, vmin, n in rows_out:
            freq_rounded = round(freq_ghz, 4)
            x = domain_freq_index[domain][freq_rounded]
            notes = ""
            if n > 1:
                overlap_count += 1
                notes = f"averaged across {n} DOE lots"
            writer.writerow([vid, domain, core, x, freq_rounded, round(vmin, 4), "", "False", notes])

    print(f"Wrote {out_path} ({len(rows_out)} rows)")
    for d, fs in sorted(domain_freqs.items()):
        samples = {(vid, core) for domain, vid, core, _, _, _ in rows_out if domain == d}
        print(f"  domain '{d}': {len(samples)} unit-core samples, {len(fs)} distinct frequencies")
    print(f"  {overlap_count} (domain,unit,core,frequency) points were averaged across overlapping DOE lots")


if __name__ == "__main__":
    main()
