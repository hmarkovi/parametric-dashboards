#!/usr/bin/env python
"""Pull per-unit HW attributes (tester / interface unit / socket) for NVLAX units from AQUA.

Reads VISUAL_ID from the organized By-Class-TP-final CSVs, queries the AQUA UNITS_LIST
analysis in batches of Visual IDs, keeps the CLASSHOT sub-flow rows of operation 6248 and
writes one HW attribute CSV keyed on Visual_ID + End_Date_Time.

This is a standalone pull. It does not touch the daily 5AM automation.

HW fields available from AQUA UNITS_LIST:
  Testing_Entity            -> Machine (tester host)
  Unit_Tester_ID            -> HDMT tester id
  Tester_Interface_Unit_ID  -> interface unit (load board / TIU)
  Socket_ID                 -> socket
Personality Card, Actuation Pan and Cell are not returned by UNITS_LIST; they need a TRACE export.
"""
from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
from datetime import datetime

import pandas as pd

DEFAULT_DATA_DIR = r"R:\Products\NVL\NVL-AX\Weekly data pull\By-Class-TP-final"
DEFAULT_OUT_DIR = r"R:\Products\NVL\NVL-AX\Weekly data pull\SAAT_shift_analysis"
DEFAULT_EXE = os.path.join(os.environ.get("LOCALAPPDATA", ""), "NVLAX", "AquaCmdLine", "AquaCmdLine.exe")
HW_COLUMNS = [
    "Visual_ID", "Lot", "End_Date_Time", "Program_Name", "Testing_Entity",
    "Unit_Tester_ID", "Tester_Interface_Unit_ID", "Socket_ID",
]


def collect_visual_ids(data_dir: str) -> list[str]:
    vids: set[str] = set()
    for path in sorted(glob.glob(os.path.join(data_dir, "NVLAX*.csv"))):
        frame = pd.read_csv(path, usecols=["VISUAL_ID"], low_memory=False)
        vids.update(frame["VISUAL_ID"].dropna().astype(str).str.strip())
    return sorted(vids)


def run_batch(exe: str, server: str, vids: list[str], raw_path: str, timeout_s: int) -> None:
    command = [
        exe, "-aquaserver", server, "-outputfilename", raw_path,
        "-analysisType", "UNITS_LIST", "-visualIds", ",".join(vids), "-operations", "6248",
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout_s, check=False)
    if result.returncode != 0 or not os.path.isfile(raw_path):
        raise RuntimeError(f"AQUA batch failed (rc={result.returncode}): {result.stdout[-400:]} {result.stderr[-400:]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--aqua-exe", default=DEFAULT_EXE)
    parser.add_argument("--aqua-server", default="GER")
    parser.add_argument("--batch-size", type=int, default=400)
    parser.add_argument("--timeout-s", type=int, default=1800)
    args = parser.parse_args()

    if not os.path.isfile(args.aqua_exe):
        print(f"AquaCmdLine not found: {args.aqua_exe}", file=sys.stderr)
        return 2

    raw_dir = os.path.join(args.out_dir, "_hw_raw")
    os.makedirs(raw_dir, exist_ok=True)

    vids = collect_visual_ids(args.data_dir)
    batches = [vids[i:i + args.batch_size] for i in range(0, len(vids), args.batch_size)]
    print(f"{len(vids)} Visual IDs, {len(batches)} batches")

    frames = []
    for index, batch in enumerate(batches, start=1):
        raw_path = os.path.join(raw_dir, f"units_list_batch_{index:03d}.csv")
        if not (os.path.isfile(raw_path) and os.path.getsize(raw_path) > 0):
            print(f"[{index}/{len(batches)}] pulling {len(batch)} units", flush=True)
            run_batch(args.aqua_exe, args.aqua_server, batch, raw_path, args.timeout_s)
        else:
            print(f"[{index}/{len(batches)}] reuse {raw_path}", flush=True)
        frames.append(pd.read_csv(raw_path, low_memory=False))

    raw = pd.concat(frames, ignore_index=True)
    mask = (raw["SubFlowStep"].astype(str).str.upper() == "CLASSHOT") & (raw["Operation"].astype(str) == "6248")
    hw = raw.loc[mask].copy()
    hw["End_Date_Time"] = pd.to_datetime(hw["End_Date_Time"], utc=True, errors="coerce")
    hw = hw.sort_values(["Visual_ID", "End_Date_Time", "Unit_Testing_Seq_Key"])
    hw = hw.drop_duplicates(subset=["Visual_ID", "End_Date_Time"], keep="last")
    hw = hw[HW_COLUMNS]

    out_csv = os.path.join(args.out_dir, f"HW_attributes_{datetime.now():%Y%m%d}.csv")
    hw.to_csv(out_csv, index=False)
    coverage = hw["Unit_Tester_ID"].notna().mean() if len(hw) else 0.0
    print(f"Wrote {len(hw)} rows to {out_csv}; Unit_Tester_ID coverage {coverage:.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
