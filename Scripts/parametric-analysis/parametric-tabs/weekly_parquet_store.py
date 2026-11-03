"""Weekly Parquet store for the NVLAX parametric report.

Layout (store root, e.g. R:\\Products\\NVL\\NVL-AX\\Weekly data pull\\Parquet_store):
    parquet/TP=<csv stem>/data.parquet   one partition per per-Class-TP CSV (report columns only, one row per VisualID+lot)
    manifest.json                        per-TP bookkeeping (source CSV, last update, rows, unmapped tokens, verification)
    reports/                             HTML reports built from the store

Subcommands
    ingest     CSVs of --csv-dir -> store.  A CSV is re-ingested only when its size/mtime changed; the partition is upserted
               (newest non-empty cell wins, empty cells are filled from older rows, a different lot keeps both rows), so a CSV
               that is later deleted never removes data from the store.
    retention  Lists CSVs whose last update is older than --weeks (default 3).  Report only; --apply deletes a CSV and only when
               the Parquet partition holds every key of the CSV and the TP is not in the keep-forever list.
    report     Builds the single HTML (all TPs) from the store with build_parametric_tabs.py.
    run        ingest + retention report + report.
    status     Prints the manifest summary.
    drilldown  Reserved (concept to be defined): per-unit raw-column drill-down.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_parametric_tabs as builder  # noqa: E402  (column discovery shared with the report)

DEFAULT_CSV_DIR = Path(r"R:\Products\NVL\NVL-AX\Weekly data pull\By-Class-TP-final")
DEFAULT_STORE = Path(r"R:\Products\NVL\NVL-AX\Weekly data pull\Parquet_store")
DEFAULT_RETENTION_WEEKS = 3
KEEP_FOREVER_DEFAULT: list[str] = []  # TP tokens whose CSV is never deleted; to be defined by the owner
KEY_COLS = ("VISUAL_ID", "LOTFROMFS")  # same key as the weekly merge engine
STALE_LOCK_SECONDS = 6 * 3600


# ------------------------------------------------------------------ store helpers
def part_path(store: Path, tp: str) -> Path:
    return store / "parquet" / f"TP={tp}" / "data.parquet"


def load_manifest(store: Path) -> dict:
    path = store / "manifest.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"version": 1, "tps": {}}


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def save_manifest(store: Path, manifest: dict) -> None:
    manifest["updated"] = dt.datetime.now().isoformat(timespec="seconds")
    atomic_write_text(store / "manifest.json", json.dumps(manifest, indent=1, sort_keys=True))


@contextlib.contextmanager
def store_lock(store: Path):
    store.mkdir(parents=True, exist_ok=True)
    lock = store / ".lock"
    if lock.exists() and time.time() - lock.stat().st_mtime > STALE_LOCK_SECONDS:
        lock.unlink()
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise SystemExit(f"Store is locked by another run ({lock}). Remove the file if no run is active.")
    try:
        os.write(fd, f"{os.getpid()} {dt.datetime.now().isoformat()}".encode())
        os.close(fd)
        yield
    finally:
        with contextlib.suppress(FileNotFoundError):
            lock.unlink()


def make_key(df: pd.DataFrame) -> pd.Series:
    key = df["VISUAL_ID"].astype(str).str.strip().str.upper()
    if "LOTFROMFS" in df:
        key = key + "||" + df["LOTFROMFS"].fillna("").astype(str).str.strip().str.upper()
    return key


def string_columns(cols: list[str], d) -> set[str]:
    s = {c for c in cols if c.endswith("_Setter") or c.endswith("_LP")}
    s.update(c for c in (d.prog_col, d.vid_col, d.lot_col, *KEY_COLS) if c)
    return s


def normalize(df: pd.DataFrame, str_cols: set[str]) -> pd.DataFrame:
    """String columns stay strings (empty -> NaN); the others become float64 when every non-empty cell is numeric."""
    for c in df.columns:
        if c in str_cols:
            df[c] = df[c].astype("string").str.strip().replace("", pd.NA).astype(object)
            continue
        if df[c].dtype == object or str(df[c].dtype).startswith("string"):
            conv = pd.to_numeric(df[c], errors="coerce")
            df[c] = conv if conv.notna().sum() >= df[c].notna().sum() else df[c].astype("string").astype(object)
        elif df[c].dtype != "float64":
            df[c] = df[c].astype("float64")
    return df


def upsert(old: pd.DataFrame | None, new: pd.DataFrame) -> pd.DataFrame:
    """Newest non-empty cell wins; empties are filled from older rows; the key is VisualID + lot."""
    if old is None or old.empty:
        merged = new.copy()
    else:
        for c in set(old.columns) & set(new.columns):  # a column that changed type between ingests is kept as string
            if (old[c].dtype == object) != (new[c].dtype == object):
                old[c] = old[c].astype("string").astype(object)
                new[c] = new[c].astype("string").astype(object)
        merged = pd.concat([old, new], ignore_index=True)
    merged = merged.assign(_key=make_key(merged))
    merged = merged[merged["VISUAL_ID"].notna()]
    merged = merged.groupby("_key", sort=False).last()  # last() skips empty cells: newest non-empty wins
    return merged.reset_index(drop=True)


def part_keys(store: Path, tp: str) -> set[str]:
    import pyarrow.parquet as pq
    part = part_path(store, tp)
    names = pq.read_schema(part).names
    return set(make_key(pd.read_parquet(part, columns=[c for c in KEY_COLS if c in names])))


def csv_keys(csv_path: Path) -> set[str]:
    header = builder.read_header(csv_path)
    cols = [c for c in KEY_COLS if c in header]
    if "VISUAL_ID" not in cols:
        return set()
    df = pd.read_csv(csv_path, usecols=cols, dtype=str, low_memory=False)
    df = df[df["VISUAL_ID"].notna()]
    return set(make_key(df))


# ------------------------------------------------------------------ ingest
def ingest_one(csv_path: Path, store: Path, entry: dict | None) -> dict | None:
    tp = csv_path.stem
    stat = csv_path.stat()
    if stat.st_size == 0:
        return {"status": "skipped-empty", "source": str(csv_path)}
    if entry and entry.get("source_size") == stat.st_size and entry.get("source_mtime") == stat.st_mtime and \
            part_path(store, tp).exists():
        return None  # unchanged
    header = builder.read_header(csv_path)
    if "VISUAL_ID" not in header:
        return {"status": "error: no VISUAL_ID column", "source": str(csv_path)}
    try:
        d = builder.discover(header)
    except SystemExit as exc:
        return {"status": f"error: {exc}", "source": str(csv_path)}
    cols = [c for c in header if c in d.usecols or c in KEY_COLS]
    str_cols = string_columns(cols, d)
    new = pd.read_csv(csv_path, usecols=cols, dtype={c: str for c in cols if c in str_cols}, low_memory=False)
    new = normalize(new, str_cols)
    new = new[new["VISUAL_ID"].notna()]
    part = part_path(store, tp)
    old = pd.read_parquet(part) if part.exists() else None
    merged = upsert(old, new)

    part.parent.mkdir(parents=True, exist_ok=True)
    tmp = part.with_name("data.parquet.tmp")
    merged.to_parquet(tmp, engine="pyarrow", compression="zstd", index=False)
    back = pd.read_parquet(tmp, columns=[c for c in KEY_COLS if c in merged.columns])
    expected = set(make_key(merged))
    verified = len(back) == len(merged) and set(make_key(back)) == expected and csv_keys(csv_path) <= expected
    if not verified:
        tmp.unlink()
        return {"status": "error: Parquet verification failed (partition not replaced)", "source": str(csv_path)}
    os.replace(tmp, part)
    return {
        "status": "ingested", "source": str(csv_path), "source_size": stat.st_size, "source_mtime": stat.st_mtime,
        "last_update": dt.datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),  # 3-WW retention clock
        "ingested": dt.datetime.now().isoformat(timespec="seconds"),
        "rows": int(len(merged)), "columns": int(merged.shape[1]), "csv_columns": len(header),
        "programs": sorted(merged[d.prog_col].dropna().unique().tolist()) if d.prog_col in merged else [],
        "bytes": part.stat().st_size, "verified": True, "unmapped": d.unmapped,
    }


def cmd_ingest(args) -> int:
    csv_dir, store = Path(args.csv_dir), Path(args.store)
    with store_lock(store):
        manifest = load_manifest(store)
        changed = 0
        for csv_path in sorted(csv_dir.glob("*.csv")):
            tp = csv_path.stem
            res = ingest_one(csv_path, store, manifest["tps"].get(tp))
            if res is None:
                print(f"{tp}: unchanged")
                continue
            if res["status"] == "ingested":
                manifest["tps"][tp] = res
                changed += 1
                print(f"{tp}: ingested rows={res['rows']} cols={res['columns']}/{res['csv_columns']} {res['bytes'] / 1e6:.1f} MB")
            else:
                prev = manifest["tps"].get(tp, {})
                manifest["tps"][tp] = {**prev, "last_status": res["status"]}
                print(f"{tp}: {res['status']}")
            save_manifest(store, manifest)
        print(f"ingest done: {changed} TP partition(s) updated")
    return 0


# ------------------------------------------------------------------ retention
def retention_report(store: Path, csv_dir: Path, weeks: int, keep: list[str], apply: bool) -> list[dict]:
    manifest = load_manifest(store)
    now = dt.datetime.now()
    rows = []
    for tp, e in sorted(manifest["tps"].items()):
        src = Path(e.get("source", csv_dir / f"{tp}.csv"))
        if not src.exists() or "last_update" not in e:
            continue
        age_days = (now - dt.datetime.fromisoformat(e["last_update"])).days
        row = {"tp": tp, "csv": str(src), "last_update": e["last_update"], "age_days": age_days, "action": "keep (within window)"}
        if age_days > weeks * 7:
            if any(tok.upper() in tp.upper() for tok in keep):
                row["action"] = "keep (keep-forever program)"
            elif not e.get("verified") or not part_path(store, tp).exists():
                row["action"] = "keep (Parquet not verified)"
            elif not csv_keys(src) <= part_keys(store, tp):
                row["action"] = "keep (CSV has keys missing from Parquet)"
            elif apply:
                src.unlink()
                row["action"] = "DELETED"
            else:
                row["action"] = "eligible for deletion (report only)"
        rows.append(row)
    return rows


def cmd_retention(args) -> int:
    rows = retention_report(Path(args.store), Path(args.csv_dir), args.weeks, args.keep_forever, args.apply)
    for r in rows:
        print(f"{r['tp']}: last update {r['last_update']} ({r['age_days']} d) -> {r['action']}")
    if not rows:
        print("no CSV with a recorded last update")
    return 0


# ------------------------------------------------------------------ report / status / drilldown
def build_report(store: Path, max_units: int | None) -> int:
    cmd = [sys.executable, str(HERE / "build_parametric_tabs.py"), "--input-parquet", str(store)]
    if max_units is not None:
        cmd += ["--max-units", str(max_units)]
    return subprocess.call(cmd)


def cmd_report(args) -> int:
    return build_report(Path(args.store), args.max_units)


def cmd_status(args) -> int:
    manifest = load_manifest(Path(args.store))
    total = 0
    for tp, e in sorted(manifest["tps"].items()):
        total += e.get("rows", 0)
        print(f"{tp}: rows={e.get('rows')} last_update={e.get('last_update')} verified={e.get('verified')} {e.get('last_status', '')}")
    print(f"{len(manifest['tps'])} TP(s), {total} units; manifest updated {manifest.get('updated')}")
    return 0


def cmd_drilldown(args) -> int:
    print("Drill-down is reserved: the per-unit raw-column view is not defined yet. "
          "The Parquet partitions keep the report columns only; the full raw columns stay in the per-TP CSV while it is retained.")
    return 0


def cmd_run(args) -> int:
    rc = cmd_ingest(args)
    if rc:
        return rc
    cmd_retention(args)
    return build_report(Path(args.store), args.max_units)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, fn in (("ingest", cmd_ingest), ("retention", cmd_retention), ("report", cmd_report), ("run", cmd_run),
                     ("status", cmd_status), ("drilldown", cmd_drilldown)):
        p = sub.add_parser(name)
        p.add_argument("--csv-dir", default=str(DEFAULT_CSV_DIR))
        p.add_argument("--store", default=str(DEFAULT_STORE))
        p.add_argument("--weeks", type=int, default=DEFAULT_RETENTION_WEEKS, help="retention window counted from the TP's last update")
        p.add_argument("--keep-forever", nargs="*", default=KEEP_FOREVER_DEFAULT, help="program tokens whose CSV is never deleted")
        p.add_argument("--apply", action="store_true", help="retention: actually delete eligible CSVs (default is report only)")
        p.add_argument("--max-units", type=int, default=None, help="report: cap on plotted units (see build_parametric_tabs.py)")
        p.set_defaults(fn=fn)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
