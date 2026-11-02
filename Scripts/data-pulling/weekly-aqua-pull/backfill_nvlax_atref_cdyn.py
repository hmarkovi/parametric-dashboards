#!/usr/bin/env python3
"""Backfill NVLAX SICC / CDYN "at ref" values into already pulled weekly data.

Targets (default):
  <root>\\By-Class-TP-final\\*.csv                 (per-TP final tables)
  <root>\\Vmin_YYYYMMDD.csv                        (daily/weekly pulls in the root folder)

What it does
  1. Inventories VISUAL_ID + LOTFROMFS of every target file (only those two columns are read).
  2. Pulls VA-NA-*-SICC_TESTER_AT_REF / VA-NA-*-SICC_SYSTEM_AT_REF / VA-NA-*-CDYN_AT_REF from AQUA,
     lot by lot-chunk (same report / operation as the weekly pull, no date filter).
  3. Collapses each '~' concatenated value ("2.2818~2.2818~...") to ONE number
     (same rule as Scripts/data-pulling/weekly-aqua-pull/nvlax_atref_helpers.ps1).
     Mixed / non-numeric cells: first numeric value is used and noted in AtRef_Parse_Comment.
  4. Writes the numeric columns (+ AtRef_Parse_Comment) into every target file by (VISUAL_ID, LOTFROMFS),
     drops the empty legacy 'VA-NA-SUMMARY-RESULTS[*::SICC_*_AT_REF]*' columns, replaces the file atomically.

Idempotent: re-running updates values in place; a one-time backup is kept in <root>\\_atref_backfill_backup.

Examples
  python backfill_nvlax_atref_cdyn.py --whatif
  python backfill_nvlax_atref_cdyn.py --only-file NVLAX62A0H25D1.csv
  python backfill_nvlax_atref_cdyn.py
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

csv.field_size_limit(2**31 - 1)

DEFAULT_ROOT = r"\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull"
DEFAULT_AQUA_UNC = r"\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe"

AT_REF_RX = re.compile(
    r"^VA-NA-(?P<domain>[A-Za-z0-9_]+)-(?P<measure>SICC_TESTER_AT_REF|SICC_SYSTEM_AT_REF|CDYN_AT_REF)(?P<suffix>_CLASSHOT)?$"
)
LEGACY_RX = re.compile(r"^VA-NA-SUMMARY-RESULTS\[[A-Za-z0-9_]+::SICC_(SYSTEM|TESTER)_AT_REF\](_CLASSHOT)?$")
COMMENT_COL = "AtRef_Parse_Comment"
VID_CANDIDATES = ("VISUAL_ID", "Visual ID", "VisualId", "VISUALID", "VID")
LOT_CANDIDATES = ("LOTFROMFS", "Lot", "LOT")
EXCLUDED_NAME_RX = re.compile(r"(_clean|_DTS|_merged|_ups_full_data|_health|_work|_Status)", re.IGNORECASE)


# --------------------------------------------------------------------------- collapse rule
def collapse_cell(text: str) -> tuple[str, str]:
    """Return (value, status). Status: empty|scalar|collapsed|mixed_segments|partial_non_numeric|non_numeric."""
    if text is None or text.strip() == "":
        return "", "empty"
    segments = [s.strip() for s in text.split("~") if s.strip() != ""]
    if not segments:
        return "", "empty"
    numbers: list[float] = []
    first_text = None
    non_numeric = 0
    for seg in segments:
        try:
            num = float(seg)
        except ValueError:
            non_numeric += 1
            continue
        if math.isnan(num) or math.isinf(num):
            non_numeric += 1
            continue
        if first_text is None:
            first_text = seg
        numbers.append(num)
    if not numbers:
        return "", "non_numeric"
    if non_numeric:
        return first_text, "partial_non_numeric"
    if len(numbers) == 1:
        return first_text, "scalar"
    ref = numbers[0]
    tol = max(1e-9, abs(ref) * 1e-6)
    if max(abs(n - ref) for n in numbers) <= tol:
        return first_text, "collapsed"
    return first_text, "mixed_segments"


def build_comment(flags: dict[str, list[str]]) -> str:
    parts = []
    for status in sorted(flags):
        note = "left empty" if status == "non_numeric" else "first value used"
        parts.append(f"{status} ({note}): {', '.join(flags[status])}")
    return " | ".join(parts)


def add_flag(flags: dict[str, list[str]], status: str, col: str) -> None:
    if status in ("mixed_segments", "partial_non_numeric", "non_numeric"):
        flags.setdefault(status, []).append(col)


# --------------------------------------------------------------------------- helpers
def log(msg: str) -> None:
    print(f"[{datetime.now():%H:%M:%S}] {msg}", flush=True)


def has_bom(path: Path) -> bool:
    with open(path, "rb") as fh:
        return fh.read(3) == b"\xef\xbb\xbf"


def open_read(path: Path):
    return open(path, "r", encoding="utf-8-sig", errors="surrogateescape", newline="")


def open_write(path: Path, bom: bool = False):
    return open(path, "w", encoding="utf-8-sig" if bom else "utf-8", errors="surrogateescape", newline="")


def norm_key(vid: str, lot: str | None) -> tuple[str, str]:
    return (vid.strip().upper(), (lot or "").strip().upper())


def pick(header: list[str], candidates) -> int | None:
    for cand in candidates:
        if cand in header:
            return header.index(cand)
    return None


def discover_targets(root: Path, only_file: str | None) -> list[Path]:
    files: list[Path] = []
    by_tp = root / "By-Class-TP-final"
    if by_tp.is_dir():
        files += sorted(p for p in by_tp.glob("*.csv") if not p.name.endswith(".bak"))
    files += sorted(p for p in root.glob("Vmin_*.csv") if re.fullmatch(r"Vmin_\d{8}\.csv", p.name))
    if only_file:
        files = [p for p in files if p.name.lower() == only_file.lower()]
    return [p for p in files if not EXCLUDED_NAME_RX.search(p.name)]


# --------------------------------------------------------------------------- inventory
def inventory(files: list[Path]) -> tuple[dict[Path, dict], set[str]]:
    info: dict[Path, dict] = {}
    lots: set[str] = set()
    for path in files:
        with open_read(path) as fh:
            reader = csv.reader(fh)
            header = next(reader)
            vid_i = pick(header, VID_CANDIDATES)
            lot_i = pick(header, ("LOTFROMFS",))
            rows = keys = 0
            if vid_i is None:
                info[path] = {"rows": 0, "units": 0, "error": "no VISUAL_ID column"}
                log(f"inventory {path.name}: no VISUAL_ID column (will be skipped)")
                continue
            seen = set()
            for row in reader:
                if len(row) <= vid_i:
                    continue
                rows += 1
                lot = row[lot_i] if lot_i is not None and len(row) > lot_i else ""
                seen.add(norm_key(row[vid_i], lot))
                if lot.strip():
                    lots.add(lot.strip())
            info[path] = {
                "rows": rows,
                "units": len(seen),
                "has_lot": lot_i is not None,
                "has_atref": any(AT_REF_RX.match(c) for c in header),
                "legacy": sum(1 for c in header if LEGACY_RX.match(c)),
                "error": "",
            }
        log(f"inventory {path.name}: rows={info[path]['rows']} units={info[path]['units']} "
            f"lot_col={info[path].get('has_lot')} atref_cols_present={info[path].get('has_atref')} "
            f"legacy_cols={info[path].get('legacy')}")
    return info, lots


# --------------------------------------------------------------------------- AQUA pull
def resolve_aqua_exe(requested: str) -> str:
    local = os.environ.get("LOCALAPPDATA")
    if local:
        cached = Path(local) / "NVLAX" / "AquaCmdLine" / "AquaCmdLine.exe"
        if cached.exists():
            return str(cached)
    return requested


def wait_stable(path: Path, timeout: int, poll: int = 5, stable_checks: int = 2) -> bool:
    deadline = time.time() + timeout
    last, stable = -1, 0
    while time.time() < deadline:
        if path.exists():
            size = path.stat().st_size
            if size > 0 and size == last:
                stable += 1
                if stable >= stable_checks:
                    return True
            else:
                stable, last = 0, size
        time.sleep(poll)
    return False


def pull_chunk(args, lots: list[str], out_file: Path) -> bool:
    """Run AQUA for one lot chunk. Returns True when an output file was written, False when AQUA
    completed with no result at all (lots outside the report scope / no data)."""
    cmd = [
        args.aqua_exe, "-aquaserver", args.aqua_server, "-reportpath", args.report_path,
        "-outputfilename", str(out_file), "-programNames", args.program_pattern,
        "-operations", args.operations, "-dataSampling", str(args.aqua_max_rows),
        "-lots", ",".join(lots),
    ]
    for attempt in (1, 2):
        if out_file.exists():
            out_file.unlink()
        log_file = out_file.with_suffix(".aqua.log")
        started = time.time()
        with open(log_file, "w", encoding="utf-8", errors="replace") as lf:
            proc = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
            next_beat = started + 120
            while True:
                try:
                    proc.wait(timeout=5)
                    break
                except subprocess.TimeoutExpired:
                    pass
                now = time.time()
                if now - started > args.timeout:
                    proc.kill()
                    break
                if now >= next_beat:
                    size = out_file.stat().st_size if out_file.exists() else 0
                    log(f"  ...AQUA running {int(now - started)}s, output={size} bytes")
                    next_beat = now + 120
        tail = log_file.read_text(encoding="utf-8", errors="replace").strip()[-300:]
        if proc.returncode == 0 and "completed without any result" in tail.lower() and not out_file.exists():
            log(f"  AQUA: report completed without any result for this chunk ({int(time.time() - started)}s)")
            return False
        if proc.returncode == 0 and wait_stable(out_file, 120):
            return True
        log(f"AQUA attempt {attempt} failed (exit={proc.returncode}, {int(time.time() - started)}s): {tail}")
    raise RuntimeError(f"AQUA pull failed for lots {lots[:3]}... -> {out_file}")


def load_chunk(raw_file: Path) -> tuple[list[str], dict[tuple[str, str], dict], int]:
    """Read only key + at-ref columns from a raw AQUA file and collapse them.

    Returns (at_ref column names, {key: {"values": {col: val}, "comment": str}}, raw_row_count).
    """
    with open_read(raw_file) as fh:
        reader = csv.reader(fh)
        header = next(reader)
        vid_i = pick(header, VID_CANDIDATES)
        lot_i = pick(header, LOT_CANDIDATES)
        if vid_i is None:
            raise RuntimeError(f"No VISUAL_ID column in {raw_file}")
        cols = [(i, c) for i, c in enumerate(header) if AT_REF_RX.match(c) or LEGACY_RX.match(c)]
        if not any(AT_REF_RX.match(c) for _, c in cols):
            # AQUA omits a column when no unit in the pull has a value, so lots without at-ref data
            # legitimately return none. Treat as an empty chunk; build_lookup aborts if every chunk is empty.
            raw_rows = sum(1 for _ in reader)
            log(f"  no VA-NA-*_AT_REF columns in this chunk ({raw_rows} raw rows): lots have no at-ref data")
            return [], {}, raw_rows
        result: dict[tuple[str, str], dict] = {}
        raw_rows = 0
        for row in reader:
            raw_rows += 1
            if len(row) <= vid_i:
                continue
            lot = row[lot_i] if lot_i is not None and len(row) > lot_i else ""
            values: dict[str, str] = {}
            flags: dict[str, list[str]] = {}
            for i, col in cols:
                val, status = collapse_cell(row[i] if len(row) > i else "")
                values[col] = val
                add_flag(flags, status, col)
            entry = {"values": values, "comment": build_comment(flags),
                     "score": sum(1 for v in values.values() if v != "")}
            key = norm_key(row[vid_i], lot)
            prev = result.get(key)
            if prev is None or entry["score"] >= prev["score"]:
                result[key] = entry
    colnames = [c for _, c in cols]
    return colnames, result, raw_rows


def build_lookup(args, lots: list[str], work: Path):
    """Pull + collapse per lot chunk, caching each collapsed chunk (resumable)."""
    lookup: dict[tuple[str, str], dict] = {}
    columns: list[str] = []
    chunks = [lots[i:i + args.lots_per_chunk] for i in range(0, len(lots), args.lots_per_chunk)]
    for n, chunk in enumerate(chunks, 1):
        tag = hashlib.sha1(",".join(chunk).encode("utf-8")).hexdigest()[:10]
        cache = work / f"chunk_{tag}_lookup.csv"
        if cache.exists() and not args.refresh:
            with open_read(cache) as fh:
                rd = csv.reader(fh)
                header = next(rd)
                cols = header[2:-1]
                for row in rd:
                    lookup[(row[0], row[1])] = {"values": dict(zip(cols, row[2:-1])), "comment": row[-1], "score": 0}
            for c in cols:
                if c not in columns:
                    columns.append(c)
            log(f"chunk {n}/{len(chunks)}: reused cache ({len(chunk)} lots)")
            continue
        raw_dir = Path(os.environ.get("TEMP", ".")) / "atref_backfill_raw"
        raw_dir.mkdir(parents=True, exist_ok=True)
        raw = raw_dir / f"chunk_{tag}_raw.csv"
        log(f"chunk {n}/{len(chunks)}: pulling {len(chunk)} lot(s) from AQUA")
        got_file = pull_chunk(args, chunk, raw)
        if got_file:
            cols, part, raw_rows = load_chunk(raw)
        else:
            cols, part, raw_rows = [], {}, 0
        if raw_rows >= args.aqua_max_rows:
            log(f"WARNING chunk {n}: {raw_rows} rows reached -dataSampling cap {args.aqua_max_rows}; "
                f"use a smaller --lots-per-chunk")
        with open_write(cache) as fh:
            wr = csv.writer(fh, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
            wr.writerow(["VISUAL_ID", "LOTFROMFS", *cols, COMMENT_COL])
            for (vid, lot), e in part.items():
                wr.writerow([vid, lot, *[e["values"].get(c, "") for c in cols], e["comment"]])
        lookup.update(part)
        for c in cols:
            if c not in columns:
                columns.append(c)
        if not args.keep_raw:
            raw.unlink(missing_ok=True)
        log(f"chunk {n}/{len(chunks)}: raw rows={raw_rows}, units with at-ref data={len(part)}")
    return columns, lookup


# --------------------------------------------------------------------------- merge
def merge_file(path: Path, columns: list[str], lookup, args, backup_dir: Path) -> dict:
    rep = {"file": path.name, "rows": 0, "matched_rows": 0, "unmatched_rows": 0, "columns_added": 0,
           "columns_updated": 0, "legacy_dropped": 0, "comment_rows": 0, "status": ""}

    with open_read(path) as fh:
        reader = csv.reader(fh)
        header = next(reader)
        vid_i = pick(header, VID_CANDIDATES)
        lot_i = pick(header, ("LOTFROMFS",))
        if vid_i is None:
            rep["status"] = "SKIPPED: no VISUAL_ID column"
            return rep
        legacy_idx = [i for i, c in enumerate(header) if LEGACY_RX.match(c)]
        legacy_has_data = {i: False for i in legacy_idx}
        if legacy_idx:
            for row in reader:
                for i in legacy_idx:
                    if len(row) > i and row[i].strip() != "":
                        legacy_has_data[i] = True

    drop_idx = {i for i in legacy_idx if not legacy_has_data[i]}
    existing_targets = {c: header.index(c) for c in columns if c in header}
    existing_other_atref = [(i, c) for i, c in enumerate(header)
                            if (AT_REF_RX.match(c) or LEGACY_RX.match(c)) and i not in drop_idx and c not in columns]
    new_cols = [c for c in columns if c not in header]
    comment_i = header.index(COMMENT_COL) if COMMENT_COL in header else None
    new_header = [c for i, c in enumerate(header) if i not in drop_idx] + new_cols
    if comment_i is None:
        new_header.append(COMMENT_COL)
    rep["columns_added"] = len(new_cols) + (1 if comment_i is None else 0)
    rep["columns_updated"] = len(existing_targets)
    rep["legacy_dropped"] = len(drop_idx)

    tmp = path.with_name(path.name + ".atref_tmp")
    keep_idx = [i for i in range(len(header)) if i not in drop_idx]
    collapse_in_place = [(i, header[i]) for c, i in existing_targets.items()] + existing_other_atref

    with open_read(path) as src, open_write(tmp, bom=has_bom(path)) as dst:
        reader = csv.reader(src)
        next(reader)
        writer = csv.writer(dst, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
        writer.writerow(new_header)
        width = len(header)
        for row in reader:
            if len(row) < width:
                row = row + [""] * (width - len(row))
            rep["rows"] += 1
            lot = row[lot_i] if lot_i is not None else ""
            entry = lookup.get(norm_key(row[vid_i], lot))

            # collapse values already present in the file ('~' strings from an interim pull)
            flags: dict[str, list[str]] = {}
            for i, col in collapse_in_place:
                if "~" in row[i]:
                    val, status = collapse_cell(row[i])
                    row[i] = val
                    add_flag(flags, status, col)
            comment = build_comment(flags)

            if entry is not None:
                rep["matched_rows"] += 1
                for col, i in existing_targets.items():
                    val = entry["values"].get(col, "")
                    if val != "":
                        row[i] = val
                comment = entry["comment"] if entry["comment"] else comment
                appended = [entry["values"].get(c, "") for c in new_cols]
            else:
                rep["unmatched_rows"] += 1
                appended = [""] * len(new_cols)

            if comment_i is not None:
                if comment or entry is not None:
                    row[comment_i] = comment
            if comment:
                rep["comment_rows"] += 1
            out = [row[i] for i in keep_idx] + appended
            if comment_i is None:
                out.append(comment)
            writer.writerow(out)

    if rep["rows"] == 0 or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        rep["status"] = "SKIPPED: empty output"
        return rep

    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / (f"{path.parent.name}__{path.name}.bak" if path.parent.name == "By-Class-TP-final"
                           else f"{path.name}.bak")
    try:
        if not args.no_backup and not backup.exists():
            shutil.copy2(path, backup)
        os.replace(tmp, path)
    except PermissionError as exc:
        tmp.unlink(missing_ok=True)
        rep["status"] = f"SKIPPED: locked ({exc})"
        return rep
    rep["status"] = "UPDATED"
    return rep


# --------------------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--only-file", help="Only process this file name (in By-Class-TP-final or root)")
    ap.add_argument("--whatif", action="store_true", help="Inventory + plan only: no AQUA pull, no file writes")
    ap.add_argument("--refresh", action="store_true", help="Ignore cached per-chunk lookups and re-pull")
    ap.add_argument("--keep-raw", action="store_true", help="Keep raw AQUA chunk files")
    ap.add_argument("--no-backup", action="store_true")
    ap.add_argument("--lots-per-chunk", type=int, default=25)
    ap.add_argument("--aqua-exe", default=DEFAULT_AQUA_UNC)
    ap.add_argument("--aqua-server", default="GER")
    ap.add_argument("--report-path", default=r"hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12")
    ap.add_argument("--program-pattern", default="NVLAX6*")
    ap.add_argument("--operations", default="6248")
    ap.add_argument("--aqua-max-rows", type=int, default=150000)
    ap.add_argument("--timeout", type=int, default=1800, help="Seconds to wait for each AQUA output file")
    args = ap.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        log(f"Root folder not found: {root}")
        return 2
    files = discover_targets(root, args.only_file)
    if not files:
        log("No target files found.")
        return 2
    log(f"{len(files)} target file(s):")
    info, lots = inventory(files)
    lot_list = sorted(lots)
    log(f"Unique lots to pull: {len(lot_list)} (chunks of {args.lots_per_chunk})")

    if args.whatif:
        log("WHATIF: stopping before AQUA pull / file writes.")
        return 0

    args.aqua_exe = resolve_aqua_exe(args.aqua_exe)
    log(f"AQUA exe: {args.aqua_exe}")
    work = root / "_atref_backfill_work"
    work.mkdir(exist_ok=True)

    columns, lookup = build_lookup(args, lot_list, work)
    log(f"Lookup: {len(lookup)} unit(s), {len(columns)} at-ref column(s)")
    if not columns:
        log("No at-ref columns obtained; aborting.")
        return 3
    # VISUAL_ID-only fallback for files without a LOTFROMFS column / rows with an empty lot.
    for (vid, _lot), entry in list(lookup.items()):
        lookup.setdefault((vid, ""), entry)

    backup_dir = root / "_atref_backfill_backup"
    report = []
    for path in files:
        log(f"merging {path.name}")
        try:
            rep = merge_file(path, columns, lookup, args, backup_dir)
        except Exception as exc:  # keep going with other files
            rep = {"file": path.name, "status": f"FAILED: {exc}"}
        log(f"  -> {rep}")
        report.append(rep)

    fields = ["file", "rows", "matched_rows", "unmatched_rows", "columns_added", "columns_updated",
              "legacy_dropped", "comment_rows", "status"]
    report_path = root / "atref_backfill_report.csv"
    with open_write(report_path) as fh:
        wr = csv.DictWriter(fh, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
        wr.writeheader()
        for rep in report:
            wr.writerow({k: rep.get(k, "") for k in fields})
    log(f"Report: {report_path}")
    return 0 if all(r.get("status") == "UPDATED" for r in report) else 1


if __name__ == "__main__":
    sys.exit(main())
