"""Daily NVLAX parametric report: rebuild the aggregate HTML from every available data source, without double counting.

Data base (both are read on every run):
    <root>\\By-Class-TP-final\\*.csv      the per-Class-TP files organised by the weekly cleanup (oldest rank)
    <root>\\Vmin_YYYYMMDD.csv            the daily pulls not yet organised (newer; ascending date, the latest file ranks highest)

Rows are keyed by VISUAL_ID + LOTFROMFS (the key of the weekly merge engine and of the Parquet store).  A key present in several
sources collapses to ONE row: the newest source wins cell by cell, empty cells are filled from older rows (store.upsert).
The merged table is verified (unique keys, no source key lost), written to <out-dir>\\Vmin_ByClassTP_ALL_<YYYYMMDD>.csv, the HTML is
built from it with build_parametric_tabs.py, and only after a successful build the older Vmin_ByClassTP_ALL_* artifacts are removed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import warnings
from pathlib import Path

import pandas as pd

warnings.simplefilter("ignore", pd.errors.PerformanceWarning)

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_parametric_tabs as builder  # noqa: E402
import weekly_parquet_store as store  # noqa: E402

DEFAULT_ROOT = Path(r"R:\Products\NVL\NVL-AX\Weekly data pull")
DAILY_RX = re.compile(r"Vmin_\d{8}\.csv")
ALL_PREFIX = "Vmin_ByClassTP_ALL_"


def collect_sources(root: Path, csv_dir: Path) -> list[Path]:
    """Oldest rank first: per-TP files (by modification time), then the daily root pulls (by date in the name)."""
    per_tp = sorted(csv_dir.glob("*.csv"), key=lambda p: (p.stat().st_mtime, p.name))
    daily = sorted((p for p in root.glob("Vmin_*.csv") if DAILY_RX.fullmatch(p.name)), key=lambda p: p.name)
    return per_tp + daily


def read_source(path: Path) -> tuple[pd.DataFrame | None, str]:
    """Report columns of one CSV, normalised like the Parquet ingest.  (None, reason) when the file cannot be used."""
    if path.stat().st_size == 0:
        return None, "empty file"
    header = builder.read_header(path)
    if "VISUAL_ID" not in header:
        return None, "no VISUAL_ID column"
    try:
        d = builder.discover(header)
    except SystemExit as exc:
        return None, str(exc)
    cols = [c for c in header if c in d.usecols or c in store.KEY_COLS]
    str_cols = store.string_columns(cols, d)
    df = pd.read_csv(path, usecols=cols, dtype={c: str for c in cols if c in str_cols}, low_memory=False)
    df = store.normalize(df, str_cols)
    return df[df["VISUAL_ID"].notna()], ""


def merge_sources(sources: list[Path]) -> tuple[pd.DataFrame, list[dict]]:
    merged: pd.DataFrame | None = None
    seen: set[str] = set()
    log: list[dict] = []
    for path in sources:
        df, why = read_source(path)
        if df is None:
            print(f"SKIP {path.name}: {why}")
            log.append({"source": path.name, "rows": 0, "new_keys": 0, "skipped": why})
            continue
        keys = store.make_key(df)
        dup_inside = int(keys.duplicated().sum())
        new_keys = int(keys[~keys.isin(seen)].nunique())
        already = int(keys.nunique()) - new_keys
        seen.update(keys)
        merged = store.upsert(merged, df)
        log.append({"source": path.name, "rows": len(df), "new_keys": new_keys, "skipped": ""})
        print(f"{path.name}: rows={len(df)} new keys={new_keys} already present={already}"
              f"{f' duplicate rows inside file={dup_inside}' if dup_inside else ''}")
    if merged is None or merged.empty:
        raise SystemExit("No usable rows in any source.")
    expected = seen
    final_keys = store.make_key(merged)
    if final_keys.duplicated().any():
        raise SystemExit("Verification failed: duplicate VISUAL_ID+LOTFROMFS keys remain after the merge.")
    if set(final_keys) != expected:
        raise SystemExit("Verification failed: merged table keys differ from the union of the source keys.")
    return merged, log


def write_csv_atomic(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    df.to_csv(tmp, index=False)
    os.replace(tmp, path)


def remove_older_artifacts(out_dir: Path, keep_stem: str, keep_previous: int) -> None:
    stems = sorted({re.match(rf"({re.escape(ALL_PREFIX)}\d{{8}})", p.name).group(1)
                    for p in out_dir.iterdir() if re.match(rf"{re.escape(ALL_PREFIX)}\d{{8}}", p.name)})
    older = [s for s in stems if s < keep_stem]
    drop = older[:-keep_previous] if keep_previous > 0 else older
    for stem in drop:
        for p in (out_dir / f"{stem}.csv", out_dir / f"{stem}_parametric_tabs"):
            if p.is_dir():
                shutil.rmtree(p)
            elif p.exists():
                p.unlink()
        print(f"removed older artifacts: {stem}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(DEFAULT_ROOT), help="Weekly data pull folder (holds the daily Vmin_YYYYMMDD.csv).")
    ap.add_argument("--csv-dir", default="", help="Per-TP CSV folder. Default: <root>\\By-Class-TP-final.")
    ap.add_argument("--out-dir", default="", help="Default: <root>\\By-Class-TP-final_ALL.")
    ap.add_argument("--max-units", type=int, default=None, help="Passed to build_parametric_tabs.py.")
    ap.add_argument("--keep-previous", type=int, default=0, help="Older Vmin_ByClassTP_ALL_* generations to keep (default 0: only the latest).")
    ap.add_argument("--refresh-tp", action="store_true", help="Refresh TP_characterization.csv first (the daily 06:30 task normally does this).")
    ap.add_argument("--no-build", action="store_true", help="Only merge and write the CSV.")
    args = ap.parse_args()

    root = Path(args.root)
    csv_dir = Path(args.csv_dir) if args.csv_dir else root / "By-Class-TP-final"
    out_dir = Path(args.out_dir) if args.out_dir else root / "By-Class-TP-final_ALL"
    sources = collect_sources(root, csv_dir)
    if not sources:
        raise SystemExit(f"No CSV found in {csv_dir} or {root}.")
    print(f"{len(sources)} source file(s): {sum(1 for p in sources if p.parent == csv_dir)} per-TP + "
          f"{sum(1 for p in sources if p.parent == root)} daily")

    merged, log = merge_sources(sources)
    stem = f"{ALL_PREFIX}{dt.date.today():%Y%m%d}"
    csv_path = out_dir / f"{stem}.csv"
    write_csv_atomic(merged, csv_path)
    print(f"merged: {len(merged)} unique VISUAL_ID+LOTFROMFS rows, {merged.shape[1]} columns -> {csv_path}")
    if args.no_build:
        return 0

    if args.refresh_tp:
        store.refresh_tp_characterization()
    cmd = [sys.executable, str(HERE / "build_parametric_tabs.py"), "--input-csv", str(csv_path),
           "--tp-characterization", str(root / "TP_characterization.csv")]
    if args.max_units is not None:
        cmd += ["--max-units", str(args.max_units)]
    rc = subprocess.call(cmd)
    html = out_dir / f"{stem}_parametric_tabs" / f"{stem}_parametric_tabs.html"
    if rc or not html.exists():
        print(f"ERROR: report build failed (exit {rc}); the previous report is kept.", file=sys.stderr)
        return rc or 1
    print(f"report: {html}")
    remove_older_artifacts(out_dir, stem, args.keep_previous)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
