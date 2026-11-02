"""Independent validator for the per-test-program weekly cleanup.

Rebuilds, from scratch and with its own code, what every retained By-Class-TP CSV must contain
and compares it with what the cleanup engine wrote:

    expected[tp] = baseline[tp]  (pre-merge retained rows, optional)
                   overlaid by every source Vmin_YYYYMMDD.csv in date order
                   (same VISUAL_ID + LOTFROMFS: newest non-empty cell wins, empty cells filled from older rows;
                    different LOTFROMFS: separate rows)

Checks (any failure -> exit code 1):
  * every source/baseline row key exists in the retained file, with no duplicate keys
  * every source/baseline column exists in the retained file
  * every non-empty expected cell equals the retained cell (no lost, changed or emptied values)
  * with a baseline: no retained cell is non-empty where the expected cell is empty (no unexplained values), no unexplained rows
  * no '~' placeholders in AT_REF columns (SUMMARY-RESULTS excluded)
  * program name -> retained file mapping, checked independently (longest retained-file-stem prefix vs engine regex)
  * no source row with a blank program name or blank VISUAL_ID + LOTFROMFS (nothing silently dropped)
  * per (TP, lot) accounting: unique source units vs retained rows

Usage:
  python validate_weekly_cleanup.py --retained-dir DIR --sources FILE [FILE ...]
        [--baseline-dir DIR] [--report report.json] [--label NAME]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

import numpy as np
import pandas as pd

TP_REGEX = re.compile(r"^([A-Z0-9]+H\d{2}[A-Z]\d)")
VID_CANDIDATES = ("VISUAL_ID", "VisualID", "Visual_ID")
LOT_CANDIDATES = ("LOTFROMFS", "LotFromFs", "Lot_From_FS", "LOT")
PROG_CANDIDATES = ("Program Name_CLASSHOT", "PROGRAM NAME_CLASSHOT")
MAX_SAMPLES = 15


def first_col(columns, candidates):
    for c in candidates:
        if c in columns:
            return c
    return None


def engine_key(program: str) -> str:
    p = str(program).strip().upper()
    m = TP_REGEX.match(p)
    return m.group(1) if m else p


def read_csv(path: str) -> pd.DataFrame:
    return pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[], encoding="utf-8-sig", low_memory=False)


def add_key(df: pd.DataFrame, vid_col: str, lot_col: str) -> pd.DataFrame:
    df = df.copy()
    df["_k"] = df[vid_col].str.strip().str.upper() + "||" + df[lot_col].str.strip().str.upper()
    return df


def collapse(df: pd.DataFrame) -> pd.DataFrame:
    """Rows -> one row per key; newest (last) non-empty cell wins. Result indexed by _k, empty cells are NaN."""
    df = df.replace("", np.nan)
    if df["_k"].duplicated().any():
        return df.groupby("_k", sort=False).last()
    return df.set_index("_k")


def overlay(old: pd.DataFrame | None, new: pd.DataFrame) -> pd.DataFrame:
    if old is None:
        return new
    return new.combine_first(old)


class Report:
    def __init__(self, label: str):
        self.label = label
        self.failures: list[dict] = []
        self.warnings: list[dict] = []
        self.per_tp: list[dict] = []
        self.lots: list[dict] = []

    def fail(self, tp: str, check: str, detail, count: int = 1):
        self.failures.append({"tp": tp, "check": check, "count": count, "detail": detail})

    def warn(self, tp: str, check: str, detail, count: int = 1):
        self.warnings.append({"tp": tp, "check": check, "count": count, "detail": detail})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--retained-dir", required=True)
    ap.add_argument("--baseline-dir", default=None, help="pre-merge retained files (snapshot / safety backup)")
    ap.add_argument("--sources", nargs="*", default=[], help="source Vmin_YYYYMMDD.csv files")
    ap.add_argument("--report", default=None, help="JSON report path (a .lots.csv is written next to it)")
    ap.add_argument("--label", default="validation")
    args = ap.parse_args()

    rep = Report(args.label)
    retained_files = {os.path.basename(f)[:-4]: f for f in glob.glob(os.path.join(args.retained_dir, "*.csv"))}
    baseline_files = {}
    if args.baseline_dir:
        baseline_files = {os.path.basename(f)[:-4]: f for f in glob.glob(os.path.join(args.baseline_dir, "*.csv"))}
    stems = sorted(set(retained_files) | set(baseline_files), key=len, reverse=True)

    # Dates sort lexicographically in Vmin_YYYYMMDD.csv, so name order == date order (oldest -> newest).
    sources = sorted(args.sources, key=lambda p: os.path.basename(p))

    expected: dict[str, pd.DataFrame] = {}
    expected_headers: dict[str, list[str]] = {}
    source_units: dict[tuple[str, str], set[str]] = {}
    tp_has_source: set[str] = set()

    def note_headers(tp: str, cols):
        lst = expected_headers.setdefault(tp, [])
        seen = set(lst)
        for c in cols:
            if c not in ("_k", "_tp") and c not in seen:
                lst.append(c)
                seen.add(c)

    # Baseline first (oldest data).
    for tp, path in baseline_files.items():
        df = read_csv(path)
        vid, lot = first_col(df.columns, VID_CANDIDATES), first_col(df.columns, LOT_CANDIDATES)
        if vid is None or lot is None:
            rep.fail(tp, "baseline_missing_key_columns", os.path.basename(path))
            continue
        note_headers(tp, df.columns)
        expected[tp] = collapse(add_key(df, vid, lot))

    # Sources, oldest -> newest.
    for src in sources:
        name = os.path.basename(src)
        df = read_csv(src)
        vid, lot = first_col(df.columns, VID_CANDIDATES), first_col(df.columns, LOT_CANDIDATES)
        prog = first_col(df.columns, PROG_CANDIDATES)
        if vid is None or lot is None or prog is None:
            rep.fail("*", "source_missing_required_columns", name)
            continue
        if len(set(df.columns)) != len(df.columns):
            rep.warn("*", "source_duplicate_headers", name)

        programs = df[prog].str.strip()
        blank_prog = programs == ""
        key_blank = (df[vid].str.strip() == "") & (df[lot].str.strip() == "")
        if blank_prog.any():
            rep.fail("*", "source_blank_program_rows", {"file": name, "sample_lots": sorted(set(df.loc[blank_prog, lot]))[:MAX_SAMPLES]}, int(blank_prog.sum()))
        if (key_blank & ~blank_prog).any():
            rep.fail("*", "source_blank_key_rows", name, int((key_blank & ~blank_prog).sum()))

        df = add_key(df, vid, lot)
        df["_tp"] = programs.map(engine_key)
        df = df[~blank_prog & ~key_blank]

        for tp, g in df.groupby("_tp", sort=False):
            # Independent mapping: longest retained/baseline file stem that prefixes the raw program name.
            raw_programs = programs.loc[g.index].str.upper().unique()
            for rp in raw_programs:
                independent = next((s for s in stems if rp.startswith(s)), None)
                if independent is not None and independent != tp:
                    rep.fail(tp, "tp_mapping_mismatch", {"file": name, "program": rp, "engine_key": tp, "independent_key": independent})

            tp_has_source.add(tp)
            note_headers(tp, g.columns)
            lots_here = g["_k"].str.split("||", regex=False).str[1]
            for lot_name, keys in g["_k"].groupby(lots_here):
                source_units.setdefault((tp, lot_name), set()).update(keys)
            expected[tp] = overlay(expected.get(tp), collapse(g.drop(columns=["_tp"])))
        del df

    has_baseline = args.baseline_dir is not None

    for tp in sorted(expected):
        exp = expected[tp]
        exp_headers = expected_headers.get(tp, [])
        entry = {"tp": tp, "expected_rows": int(len(exp)), "retained_rows": None, "status": "OK"}
        rep.per_tp.append(entry)

        path = retained_files.get(tp)
        if path is None:
            rep.fail(tp, "retained_file_missing", f"{tp}.csv", int(len(exp)))
            entry["status"] = "FAIL"
            continue
        ret_df = read_csv(path)
        vid, lot = first_col(ret_df.columns, VID_CANDIDATES), first_col(ret_df.columns, LOT_CANDIDATES)
        if vid is None or lot is None:
            rep.fail(tp, "retained_missing_key_columns", f"{tp}.csv")
            entry["status"] = "FAIL"
            continue
        ret_df = add_key(ret_df, vid, lot)
        entry["retained_rows"] = int(len(ret_df))
        before_fail = len(rep.failures)

        dups = ret_df["_k"].duplicated(keep="first")
        if dups.any():
            rep.fail(tp, "retained_duplicate_keys", ret_df.loc[dups, "_k"].head(MAX_SAMPLES).tolist(), int(dups.sum()))
        ret = ret_df[~dups].set_index("_k")

        # Headers.
        missing_headers = [c for c in exp_headers if c not in ret.columns]
        if missing_headers:
            rep.fail(tp, "columns_missing_in_retained", missing_headers[:MAX_SAMPLES], len(missing_headers))
        extra_headers = [c for c in ret.columns if c not in set(exp_headers)]
        if extra_headers:
            (rep.fail if has_baseline else rep.warn)(tp, "columns_not_explained_by_sources", extra_headers[:MAX_SAMPLES], len(extra_headers))

        # Rows.
        missing_keys = exp.index.difference(ret.index)
        if len(missing_keys):
            rep.fail(tp, "rows_missing_in_retained", list(missing_keys[:MAX_SAMPLES]), int(len(missing_keys)))
        extra_keys = ret.index.difference(exp.index)
        if len(extra_keys):
            (rep.fail if has_baseline else rep.warn)(tp, "rows_not_explained_by_sources", list(extra_keys[:MAX_SAMPLES]), int(len(extra_keys)))

        # Cells.
        common = exp.index.intersection(ret.index)
        cols = [c for c in exp.columns if c in ret.columns]
        if len(common) and cols:
            a = exp.reindex(index=common, columns=cols).fillna("").values.astype(object)
            b = ret.loc[common, cols].values.astype(object)
            lost_or_changed = (a != "") & (a != b)
            if lost_or_changed.any():
                per_col = lost_or_changed.sum(axis=0)
                bad_cols = np.nonzero(per_col)[0]
                samples = []
                for ci in bad_cols[:MAX_SAMPLES]:
                    ri = int(np.nonzero(lost_or_changed[:, ci])[0][0])
                    samples.append({"column": cols[ci], "cells": int(per_col[ci]), "key": common[ri], "expected": str(a[ri, ci])[:80], "retained": str(b[ri, ci])[:80]})
                kind_empty = int(((a != "") & (b == "") & lost_or_changed).sum())
                rep.fail(tp, "cells_lost_or_changed", {"columns": int(len(bad_cols)), "cells_emptied": kind_empty, "samples": samples}, int(lost_or_changed.sum()))
            if has_baseline:
                unexplained = (a == "") & (b != "")
                if unexplained.any():
                    per_col = unexplained.sum(axis=0)
                    bad_cols = np.nonzero(per_col)[0]
                    rep.fail(tp, "retained_cells_not_explained_by_sources", [{"column": cols[ci], "cells": int(per_col[ci])} for ci in bad_cols[:MAX_SAMPLES]], int(unexplained.sum()))

        # '~' placeholders in at-ref columns.
        tilde = 0
        for c in ret.columns:
            if "AT_REF" in c.upper() and "SUMMARY-RESULTS" not in c.upper():
                tilde += int(ret[c].str.contains("~", regex=False).sum())
        if tilde:
            rep.fail(tp, "tilde_in_at_ref_columns", "'~' placeholder values present", tilde)

        if len(rep.failures) > before_fail:
            entry["status"] = "FAIL"

        # Lot accounting for lots that appear in sources.
        ret_lots = ret.index.to_series().str.split("||", regex=False).str[1].value_counts()
        for (stp, lot_name), keys in sorted(source_units.items()):
            if stp != tp:
                continue
            in_ret = int(ret_lots.get(lot_name, 0))
            present = int(sum(1 for k in keys if k in ret.index))
            rep.lots.append({"tp": tp, "lot": lot_name, "source_units": len(keys), "source_units_in_retained": present, "retained_rows_for_lot": in_ret, "status": "OK" if present == len(keys) else "FAIL"})
        del ret_df, ret, exp

    # Sources with a TP that has no expected frame cannot happen (every source TP creates one); retained TPs not in scope are untouched.
    passed = not rep.failures
    summary = {
        "label": rep.label,
        "passed": passed,
        "failure_count": len(rep.failures),
        "warning_count": len(rep.warnings),
        "sources": [os.path.basename(s) for s in sources],
        "baseline_dir": args.baseline_dir,
        "retained_dir": args.retained_dir,
        "per_tp": rep.per_tp,
        "failures": rep.failures,
        "warnings": rep.warnings,
        "lot_accounting": rep.lots,
    }

    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump(summary, fh, indent=2, default=str)
        if rep.lots:
            pd.DataFrame(rep.lots).to_csv(os.path.splitext(args.report)[0] + ".lots.csv", index=False)

    print(f"[{rep.label}] TP files checked: {len(rep.per_tp)}  failures: {len(rep.failures)}  warnings: {len(rep.warnings)}")
    for e in rep.per_tp:
        print(f"  {e['tp']:24} expected={e['expected_rows']:6} retained={e['retained_rows']}  {e['status']}")
    for f in rep.failures[:40]:
        print(f"  FAIL {f['tp']} {f['check']} x{f['count']}: {str(f['detail'])[:200]}")
    for w in rep.warnings[:10]:
        print(f"  WARN {w['tp']} {w['check']} x{w['count']}: {str(w['detail'])[:200]}")
    print("RESULT: " + ("ALL OK" if passed else "FAILED"))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
