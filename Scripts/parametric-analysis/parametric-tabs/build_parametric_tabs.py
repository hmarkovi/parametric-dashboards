"""Build a self-contained 3-tab HTML (Vmin / SICC / DTS) from a merged weekly NVLAX CSV.

Tokens are discovered from the CSV header (no config file).  Vmin and SICC are modelled
against the relevant UPM column per power-unit (PU) group; anything that cannot be mapped
is reported in the "Unmapped / ambiguous tokens" section instead of being guessed.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import importlib.util
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
DTS_HELPERS_PATH = HERE.parent / "ilas" / "build-nvlax-dts-matplotlib.py"
TEMPLATE_PATH = HERE / "report_template.html"
WEEKLY_DIR = Path(r"R:\Products\NVL\NVL-AX\Weekly data pull")

# Official released NVLAX Class programs (same list the 5AM DTS automation uses).
OFFICIAL_TP_TOKENS = {"25C00", "25D00", "25D10", "25E00", "25G00", "25H00"}
STANDARD_TP_RX = re.compile(r"(\d{2}[A-Z]\d0)S\d+$", re.IGNORECASE)

PROGRAM_COL_CANDIDATES = ["Program Name_CLASSHOT", "Program Name", "PROGRAM_NAME"]
VID_COL_CANDIDATES = ["VISUAL_ID", "Visual ID", "VisualId"]
LOT_COL_CANDIDATES = ["Lot_CLASSHOT", "LOTFROMFS", "Lot"]

VMIN_RX = re.compile(
    r"UPSVFPASSFLOW_(?P<pu>U1PU\d+)_CLASSHOT_(?P<dom>[A-Za-z0-9]+)_(?P<f>\d+(?:\.\d+)?)_(?P<core>\d+)$"
)
DTS_RX = re.compile(
    r"^ILAS_(?P<Domain>.+?)_(?P<Corner>FMIN|F\d+)(?:_Flow(?P<Flow>[^_]+))?_Freq(?P<Freq>[0-9]+(?:\.[0-9]+)?)_C(?P<CoreIndex>\d+)_MaxDTS_C$"
)
ILAS_VMIN_RX = re.compile(
    r"^ILAS_(?P<Domain>.+?)_(?P<Corner>FMIN|F\d+)(?:_Flow(?P<Flow>[^_]+))?_Freq(?P<Freq>[0-9]+(?:\.[0-9]+)?)_C(?P<CoreIndex>\d+)_Vmin$"
)
# Setter tail after the frequency token (plist / content), e.g. ..._F1_1200_SLC_DRG_LLH -> SLC_DRG_LLH
SETTER_PLIST_RX = re.compile(r"_(?:FMIN|F\d+)_(?:\d{3,4}|X)(?:_(?P<pl>.+))?$")
BIN_COL_CANDIDATES = ["INTERFACE_BIN_CLASSHOT", "INTERFACE_BIN"]
UPM_OVERVIEW = [("GT", "U1PU4"), ("HUB", "U1PU2"), ("Cdie", "U1PU5")]
SICC_ATREF_RX = re.compile(r"^VA-NA-SUMMARY-RESULTS\[(?P<dom>[A-Za-z0-9_]+)::SICC_(?P<m>SYSTEM|TESTER)_AT_REF\]_CLASSHOT$")
# Current AQUA tokens (one collapsed numeric value per unit): VA-NA-<domain>-SICC_(SYSTEM|TESTER)_AT_REF[_CLASSHOT]
SICC_ATREF_NEW_RX = re.compile(r"^VA-NA-(?P<dom>[A-Za-z0-9_]+)-SICC_(?P<m>SYSTEM|TESTER)_AT_REF(?:_CLASSHOT)?$")
SICC_RAW_RX = re.compile(
    r"PP_SICC_(?P<pu>U1PU\d+)_CLASSHOT_(?P<dom>[A-Za-z0-9]+)-V(?P<v>\d+)_(?P<field>Value|Voltage|Temperature)$"
)

# PU group -> UPM rule.  Sources: build-vmin-starting-point.ps1 (UPM seed) verified against CSV headers.
UPM_RULES = {
    "U1PU5": {
        "die": "CDIE (CPU)",
        "candidates": ["UPM_0107_DPMH156P48ULVTINVD4_FULLDIE_0950_MED_SORT_U1.U5"],
        "target": 0.95,
        "divisor": 9154.0,
    },
    "U1PU2": {
        "die": "HUB / SA",
        "candidates": ["TPI_UPM::UPM_X_SCREEN_K_START_X_X_X_X_FEM_CALC_UPM_FEM_LVT_ATOMALL_PDK0P9_0950MV_SORT_U1.U2"],
        "target": 0.9,
        "divisor": None,  # column is already a normalised FEM value
    },
    "U1PU4": {
        "die": "GT",
        "candidates": ["UPM_2007_DPMH130P48ULVTINVD4_FULLDIE_0950_MED_SORT_U1.U4"],
        "target": 0.98,
        "divisor": 7694.0,  # GT speed target (MHz) from the manual rollup deck
    },
}
FAMILY_TO_PU = {"Core": "U1PU5", "Atom": "U1PU5", "Ring": "U1PU5", "GT": "U1PU4", "SA": "U1PU2"}

# Domains of the SICC PreSi table:
# (table domain, raw token regex, at-ref token regex, pooled label or None for a single token, PreSi SICC row or None)
# Raw tokens come from PP_SICC_*_CLASSHOT_<token>-Vn_Value, at-ref tokens from VA-NA-SUMMARY-RESULTS[<token>::SICC_*_AT_REF].
# The PreSi row is the 'Class Hot / SICC' row label of the PreSi Parameters file; None = no PreSi target known.
SICC_TABLE_DOMAINS = [
    ("Core", r"IA\d+", r"IAA\d+", "IA* (all cores)", "Core"),
    ("Ring", r"CCF", r"CCFA", None, "Ring"),
    ("Atom", r"AT\d+", r"ATA\d+", "AT* (all atoms)", "AtomQuad"),
    ("SA-Atom", r"SAAT", r"LPATOMB", None, "LP ATOM"),
    ("NPU", r"SANPU", r"NPU", None, "VPU"),
    ("GT", r"GT", r"GT", None, "GT"),
    ("SAHUB", r"SAHUB", None, None, "SA Total"),
    ("SA", r"SA", None, None, None),
    ("DE", None, r"DE", None, "DE"),
    ("Media", None, r"MEDIA", None, "Media"),
    ("IPU", None, r"IPU", None, None),
]
PRESI_ROW_ALIAS = {"Cclk": "SAC"}  # PreSi row name -> CSV domain name
PRESI_MODELS_DIR = Path(r"R:\Products\NVL\NVL-AX\PreSi models")  # the latest .xlsx in this folder is the PreSi VF model
PRESI_PARAMS_DIR = PRESI_MODELS_DIR / "PreSi Parameters"  # the latest file in this folder holds the PreSi SICC / CDYN parameters
S2T_STATIC_TOL = 1e-3  # System/Tester ratio counts as one static value when (max - min) <= tol * |median|

# PostSi CSV domain token -> PreSi domain name (source: 'PreSi to PostSi name dictionary.xls')
POSTSI_TO_PRESI = {
    "AT": "AT", "CCF": "CCF", "CR": "CR", "CRFCT": "CR", "GT": "GT", "GTVPG": "GT", "SAAT": "SAAT", "SAC": "SAC",
    "SACD": "SACD", "SADPU": "SADPU", "SAIOC": "SAN", "SAME": "SAME", "SAN": "SAN", "SAPS": "SAPS", "SAQ": "SAQ",
}
# Domains that are not analysed (SADPU is the relevant domain for Vmin, SICC and DTS).
EXCLUDED_DOMAINS = {"SAVPU"}

DEFAULT_MAX_UNITS = 15000  # per-unit points embedded in the page (about 2.4 KB per unit); beyond this a fair-share sample is plotted
PARQUET_PART_GLOB = "parquet/TP=*/data.parquet"  # layout written by weekly_parquet_store.py

MIN_FIT_POINTS = 5
WEAK_R2 = 0.10
VMIN_VALID = (0.2, 1.8)
UPM_SIGMA = 3.0


def load_dts_helpers():
    spec = importlib.util.spec_from_file_location("dts_helpers", DTS_HELPERS_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["dts_helpers"] = module
    spec.loader.exec_module(module)
    return module


def read_header(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return next(csv.reader(handle))


def first_existing(candidates: list[str], columns: set[str]) -> str | None:
    for item in candidates:
        if item in columns:
            return item
    return None


def parquet_parts(root: Path) -> list[Path]:
    parts = sorted(root.glob(PARQUET_PART_GLOB))
    if not parts:
        raise SystemExit(f"No Parquet partitions ({PARQUET_PART_GLOB}) under {root}")
    return parts


def parquet_header(parts: list[Path]) -> list[str]:
    import pyarrow.parquet as pq
    header: dict[str, None] = {}
    for p in parts:
        for name in pq.read_schema(p).names:
            header.setdefault(name, None)
    return list(header)


def load_parquet(parts: list[Path], usecols: set[str]) -> pd.DataFrame:
    """Read only the report columns of every TP partition; a column missing in a partition is empty there."""
    import pyarrow.parquet as pq
    frames = []
    for p in parts:
        cols = [c for c in pq.read_schema(p).names if c in usecols]
        frames.append(pq.read_table(p, columns=cols).to_pandas())
    return pd.concat(frames, ignore_index=True) if len(frames) > 1 else frames[0]


def parquet_manifest_unmapped(root: Path, current: list[dict]) -> list[dict]:
    """Unmapped-token entries recorded at ingest time (they describe columns that are not stored in the Parquet)."""
    path = root / "manifest.json"
    if not path.exists():
        return []
    have = {(u["family"], u["token"]) for u in current}
    best: dict[tuple, dict] = {}
    for tp in json.loads(path.read_text(encoding="utf-8")).get("tps", {}).values():
        for u in tp.get("unmapped", []):
            key = (u["family"], u["token"])
            if key not in have and (key not in best or u.get("count", 0) > best[key].get("count", 0)):
                best[key] = u
    return list(best.values())


def fair_share_quota(counts: dict[str, int], cap: int) -> dict[str, int]:
    """Water-filling: small programs keep every unit, the remaining budget is split evenly over the larger ones."""
    quota, remaining = {}, cap
    ordered = sorted(counts, key=lambda k: (counts[k], k))
    for i, name in enumerate(ordered):
        quota[name] = min(counts[name], remaining // (len(ordered) - i))
        remaining -= quota[name]
    return quota


def sample_mask(df: pd.DataFrame, vid_col: str, lot_col: str | None, prog_col: str, quota: dict[str, int]) -> np.ndarray:
    """Deterministic sample: within a program the units with the lowest hash of VisualID|lot are kept (stable between runs)."""
    key = df[vid_col].astype(str)
    if lot_col:
        key = key + "|" + df[lot_col].astype(str)
    h = pd.util.hash_pandas_object(key, index=False).to_numpy()
    keep = np.zeros(len(df), dtype=bool)
    prog = df[prog_col].to_numpy()
    for name, q in quota.items():
        idx = np.where(prog == name)[0]
        if len(idx) <= q:
            keep[idx] = True
        else:
            keep[idx[np.argsort(h[idx], kind="stable")[:q]]] = True
    return keep


def sicc_family(token: str) -> str:
    t = token.upper()
    if re.match(r"^(IA|CR|CORE)", t):
        return "Core"
    if t.startswith("LPAT") or re.match(r"^(DE|IPU|MEDIA|NPU)", t):
        return "SA"
    if t.startswith("AT"):
        return "Atom"
    if t.startswith("CCF"):
        return "Ring"
    if t.startswith("GT"):
        return "GT"
    if t.startswith("SA"):
        return "SA"
    return "Other"


def tp_tag(program: str) -> str:
    match = STANDARD_TP_RX.search(program)
    if not match:
        return "other"
    return "official" if match.group(1).upper() in OFFICIAL_TP_TOKENS else "standard-name"


def finite(series: pd.Series) -> np.ndarray:
    return pd.to_numeric(series, errors="coerce").to_numpy(dtype=float)


def r(value: float, nd: int = 5):
    if value is None or not np.isfinite(value):
        return None
    return round(float(value), nd)


def linfit(x: np.ndarray, y: np.ndarray):
    if x.size < MIN_FIT_POINTS or np.ptp(x) < 1e-9:
        return None
    slope, intercept = np.polyfit(x, y, 1)
    resid = y - (slope * x + intercept)
    ss_tot = float(((y - y.mean()) ** 2).sum())
    r2 = 1.0 - float((resid ** 2).sum()) / ss_tot if ss_tot > 0 else float("nan")
    return float(slope), float(intercept), r2


def read_xlsx_rows(path: Path) -> list[dict[str, str]]:
    """Rows of the first sheet as {column letter: text} without openpyxl."""
    import xml.etree.ElementTree as ET
    import zipfile
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as z:
        shared = [("".join(t.text or "" for t in si.iter(f"{{{ns['m']}}}t")))
                  for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns)]
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    rows = []
    for row in sheet.iter(f"{{{ns['m']}}}row"):
        cells = {}
        for c in row.findall("m:c", ns):
            v = c.find("m:v", ns)
            if v is None:
                continue
            cells[re.match(r"[A-Z]+", c.get("r")).group(0)] = shared[int(v.text)] if c.get("t") == "s" else v.text
        rows.append(cells)
    return rows


def latest_presi_params(folder: Path) -> Path:
    """Most recently modified .csv / .xlsx in the PreSi Parameters folder (Excel lock files ignored)."""
    files = [p for p in list(folder.glob("*.csv")) + list(folder.glob("*.xlsx")) if not p.name.startswith("~$")]
    if not files:
        raise FileNotFoundError(f"no .csv / .xlsx in {folder}")
    return max(files, key=lambda p: p.stat().st_mtime)


def _param_grid(path: Path) -> list[dict[int, str]]:
    """Rows of a parameter file as {column index: text}."""
    if path.suffix.lower() == ".csv":
        with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
            return [{i: v for i, v in enumerate(row) if v.strip()} for row in csv.reader(handle)]
    def col_index(letters: str) -> int:
        n = 0
        for ch in letters:
            n = n * 26 + ord(ch) - 64
        return n - 1
    return [{col_index(k): v for k, v in cells.items() if str(v).strip()} for cells in read_xlsx_rows(path)]


def read_presi_sicc(path: Path) -> tuple[dict[str, dict], str]:
    """PreSi 'Class Hot / SICC' rows of the latest NVL-AX model column.

    Returns ({row label: {"v1": 0.7V/100C [A], "v2": 0.95V/100C [A]}}, model column name).  The model column is the
    'NVL-AX ... YYwwWW' header with the newest week.  The 0.95V line of a row inherits the label of its 0.7V line.
    """
    grid = _param_grid(path)
    best = None
    for row in grid[:8]:
        for idx, text in row.items():
            name = " ".join(text.split())
            m = re.search(r"NVL-AX\b.*?(\d{2})ww(\d{2})", name, re.IGNORECASE)
            if m and (best is None or (int(m[1]), int(m[2])) > best[0]):
                best = ((int(m[1]), int(m[2])), idx, name)
    if best is None:
        raise ValueError("no 'NVL-AX ... <yy>ww<ww>' model column found")
    _, col, col_name = best
    num = re.compile(r"^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)")
    out: dict[str, dict] = {}
    param, domain, in_sicc = "", "", False
    for row in grid:
        if row.get(1, "").strip():
            param = row[1].strip()
            in_sicc = param == "SICC"
        if not in_sicc:
            continue
        vm = re.search(r"(\d+(?:\.\d+)?)\s*V", row.get(4, ""))
        if not vm:
            continue
        volt = float(vm[1])
        if volt < 0.8 and row.get(2, "").strip():
            domain = " ".join(row[2].split())
        if not domain:
            continue
        nm = num.match(row.get(col, ""))
        out.setdefault(domain, {"v1": None, "v2": None})["v1" if volt < 0.8 else "v2"] = float(nm[1]) if nm else None
    return out, col_name


def read_presi_vf(path: Path) -> dict[str, list[list[float]]]:
    """PreSi VF model: columns B (domain token) / C (freq GHz) / D (Vmin V), sorted by frequency."""
    out: dict[str, list[list[float]]] = defaultdict(list)
    for cells in read_xlsx_rows(path):
        if not all(k in cells for k in "BCD"):
            continue
        try:
            point = [round(float(cells["C"]), 4), round(float(cells["D"]), 4)]
        except ValueError:
            continue  # header row
        out[cells["B"].strip().upper()].append(point)
    return {k: sorted(v) for k, v in out.items()}


def latest_presi_model(folder: Path) -> Path:
    """Most recently modified .xlsx in the PreSi models folder (Excel lock files ignored)."""
    files = [p for p in folder.glob("*.xlsx") if not p.name.startswith("~$")]
    if not files:
        raise FileNotFoundError(f"no .xlsx in {folder}")
    return max(files, key=lambda p: p.stat().st_mtime)


def resolve_upm(pu: str, header: set[str]):
    """Return (rule-with-column or None, note)."""
    rule = UPM_RULES.get(pu)
    if rule is None:
        return None, f"no UPM rule defined for {pu}"
    hits = [c for c in rule["candidates"] if c in header]
    if len(hits) == 1:
        return {**rule, "col": hits[0]}, ""
    suffix = "SORT_U1." + pu.replace("U1PU", "U")
    near = sorted(c for c in header if "UPM" in c.upper() and c.endswith(suffix) and "950" in c.upper())
    note = f"expected UPM column not in CSV ({rule['candidates'][0]})"
    if near:
        note += "; candidates NOT used: " + "; ".join(near[:6])
    return None, note


def parse_args_and_paths():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input-csv", default="", help="Merged weekly CSV. Default: latest Vmin_YYYYMMDD.csv in the weekly folder.")
    ap.add_argument("--input-parquet", default="", help="Parquet store root (see weekly_parquet_store.py); all TPs in the store are reported. Overrides --input-csv.")
    ap.add_argument("--max-units", type=int, default=DEFAULT_MAX_UNITS,
                    help="Cap on units embedded in the page for the per-unit plots/fits (fair share per program, deterministic sample). "
                         "Overview counts, flow matrix and limiter tabs always use every unit. 0 = no cap.")
    ap.add_argument("--output-dir", default="", help="Default: <input stem>_parametric_tabs next to the CSV (Parquet: <store>/reports/...).")
    ap.add_argument("--program", default="", help="Optional exact program name filter (validation).")
    ap.add_argument("--official-tps", default="", help="Comma list of extra official TP tokens, e.g. 25G00,25H00.")
    args = ap.parse_args()

    OFFICIAL_TP_TOKENS.update(t.strip().upper() for t in args.official_tps.split(",") if t.strip())

    if args.input_parquet:
        input_csv = Path(args.input_parquet) / f"Vmin_ALL_{dt.date.today():%Y%m%d}"  # label only; no such file
        default_out = Path(args.input_parquet) / "reports" / f"{input_csv.name}_parametric_tabs"
    elif args.input_csv:
        input_csv = Path(args.input_csv)
        default_out = input_csv.parent / f"{input_csv.stem}_parametric_tabs"
    else:
        found = sorted(WEEKLY_DIR.glob("Vmin_[0-9]" * 1 + "*.csv"))
        found = [p for p in found if re.fullmatch(r"Vmin_\d{8}\.csv", p.name)]
        if not found:
            raise SystemExit(f"No Vmin_YYYYMMDD.csv found in {WEEKLY_DIR}")
        input_csv = found[-1]
        default_out = input_csv.parent / f"{input_csv.stem}_parametric_tabs"
    out_dir = Path(args.output_dir) if args.output_dir else default_out
    out_dir.mkdir(parents=True, exist_ok=True)
    return args, input_csv, out_dir


def discover(header: list[str]) -> SimpleNamespace:
    """Parse the column names: which columns are charted, UPM resolution, unmapped tokens, and the minimal column set (`usecols`)
    the report needs.  Shared with the Parquet ingest so the stored columns always match what the report reads."""
    hset = set(header)
    prog_col = first_existing(PROGRAM_COL_CANDIDATES, hset)
    vid_col = first_existing(VID_COL_CANDIDATES, hset)
    lot_col = first_existing(LOT_COL_CANDIDATES, hset)
    if not (prog_col and vid_col):
        raise SystemExit("Program-name / Visual-ID column not found.")

    unmapped: list[dict] = []
    vmin_cols = []  # (col, pu, dom_token, freq, core)
    vmin_orig = 0
    vmin_other = []
    for c in header:
        if "UPSVFPASSFLOW" not in c:
            continue
        m = VMIN_RX.search(c)
        if m:
            vmin_cols.append((c, m["pu"], m["dom"].upper(), float(m["f"]), int(m["core"])))
        elif c.endswith("_Original"):
            vmin_orig += 1
        else:
            vmin_other.append(c)
    n_vmin_all = len(vmin_cols)
    vmin_cols = [t for t in vmin_cols if t[2] not in EXCLUDED_DOMAINS]
    excluded_cols = n_vmin_all - len(vmin_cols)
    if vmin_orig:
        unmapped.append({"family": "Vmin", "token": "UPSVFPASSFLOW_*_CLASSHOT_Original", "count": vmin_orig,
                         "reason": "packed raw string (by design not parsed)", "examples": ""})
    if vmin_other:
        unmapped.append({"family": "Vmin", "token": "UPSVFPASSFLOW_* (unparsed)", "count": len(vmin_other),
                         "reason": "name does not match the Vmin pattern", "examples": "; ".join(vmin_other[:3])})

    dts_cols = [(c, DTS_RX.match(c)) for c in header if c.startswith("ILAS_") and c.endswith("_MaxDTS_C")]
    ilas_cols = []
    bad_ilas = []
    for c in header:
        if c.startswith("ILAS_") and c.endswith("_Vmin"):
            m = ILAS_VMIN_RX.match(c)
            if not m:
                bad_ilas.append(c)
            elif not re.match(r"(%s)\d*$" % "|".join(EXCLUDED_DOMAINS), m["Domain"].upper()):
                ilas_cols.append((c, m))
    if bad_ilas:
        unmapped.append({"family": "Limiter", "token": "ILAS_*_Vmin (unparsed)", "count": len(bad_ilas),
                         "reason": "name does not match the ILAS pattern; not used by Module Pareto / Limiting Pattern / Flow Matrix",
                         "examples": "; ".join(bad_ilas[:3])})
    bin_col = first_existing(BIN_COL_CANDIDATES, hset)
    bad_dts = [c for c, m in dts_cols if m is None]
    dts_cols = [(c, m) for c, m in dts_cols if m]
    n_dts_all = len(dts_cols)
    dts_cols = [(c, m) for c, m in dts_cols if not re.match(r"(%s)\d*$" % "|".join(EXCLUDED_DOMAINS), m["Domain"].upper())]
    excluded_cols += n_dts_all - len(dts_cols)
    if excluded_cols:
        unmapped.append({"family": "All", "token": ", ".join(sorted(EXCLUDED_DOMAINS)), "count": excluded_cols,
                         "reason": "domain not analysed by design (SADPU is the relevant domain)", "examples": ""})
    if bad_dts:
        unmapped.append({"family": "DTS", "token": "ILAS_*_MaxDTS_C (unparsed)", "count": len(bad_dts),
                         "reason": "name does not match the DTS pattern", "examples": "; ".join(bad_dts[:3])})

    sicc_atref = []  # (col, token, measure)
    sicc_atref_legacy = []  # old VA-NA-SUMMARY-RESULTS[...] names; only used when no new-style column exists for the same series
    sicc_raw = []    # (col, pu, token, v)
    sicc_sort = 0
    sicc_other = []
    for c in header:
        if "SICC" not in c.upper():
            continue
        m = SICC_ATREF_NEW_RX.match(c)
        if m:
            sicc_atref.append((c, m["dom"].upper(), m["m"].lower() + "_at_ref"))
            continue
        m = SICC_ATREF_RX.match(c)
        if m:
            sicc_atref_legacy.append((c, m["dom"].upper(), m["m"].lower() + "_at_ref"))
            continue
        m = SICC_RAW_RX.search(c)
        if m:
            if m["field"] == "Value":
                sicc_raw.append((c, m["pu"], m["dom"].upper(), int(m["v"])))
            continue  # Voltage / Temperature companions are not charted
        if "PTH_POWER" in c or "PC_SORT" in c or "SORT_U1" in c:
            sicc_sort += 1
        else:
            sicc_other.append(c)
    _new_series = {(t, m) for _, t, m in sicc_atref}
    sicc_atref += [x for x in sicc_atref_legacy if (x[1], x[2]) not in _new_series]
    if sicc_sort:
        unmapped.append({"family": "SICC", "token": "PTH_POWER*::...SICC... (raw SORT)", "count": sicc_sort,
                         "reason": "SORT-side raw SICC is not charted in this version", "examples": ""})
    if sicc_other:
        unmapped.append({"family": "SICC", "token": "SICC* (other)", "count": len(sicc_other),
                         "reason": "name does not match a known SICC pattern", "examples": "; ".join(sicc_other[:3])})

    # UPM resolution per PU group in use
    used_pus = sorted({p for _, p, *_ in vmin_cols} | {p for _, p, *_ in sicc_raw} |
                      {FAMILY_TO_PU[sicc_family(t)] for _, t, _ in sicc_atref if sicc_family(t) in FAMILY_TO_PU})
    upm_info: dict[str, dict | None] = {}
    upm_status = []
    for pu in used_pus:
        rule, note = resolve_upm(pu, hset)
        upm_info[pu] = rule
        upm_status.append({"pu": pu, "die": UPM_RULES.get(pu, {}).get("die", "?"),
                           "column": rule["col"] if rule else None, "available": bool(rule), "note": note})
        if not rule:
            unmapped.append({"family": "UPM", "token": f"{pu} UPM", "count": 1,
                             "reason": "UPM unavailable -> Vmin uses 'Median-based; UPM unavailable', SICC has no UPM fit. " + note,
                             "examples": ""})
        elif UPM_RULES[pu].get("alt_note"):
            unmapped.append({"family": "UPM", "token": rule["col"], "count": 1, "reason": UPM_RULES[pu]["alt_note"], "examples": ""})

    # ------------------------------------------------------------------ load
    usecols = {vid_col, prog_col}
    if lot_col:
        usecols.add(lot_col)
    usecols.update(c for c, *_ in vmin_cols)
    usecols.update(c for c, *_ in sicc_atref)
    usecols.update(c for c, *_ in sicc_raw)
    usecols.update(rule["col"] for rule in upm_info.values() if rule)
    if bin_col:
        usecols.add(bin_col)
    for c, _ in ilas_cols:
        usecols.add(c)
        for suffix in ("_Setter", "_LP"):
            sib = c[: -len("_Vmin")] + suffix
            if sib in hset:
                usecols.add(sib)
    for c, _ in dts_cols:
        usecols.add(c)
        for suffix in ("_Setter", "_LP"):
            sib = c.replace("_MaxDTS_C", suffix)
            if sib in hset:
                usecols.add(sib)
    return SimpleNamespace(**locals())


def main() -> int:
    args, input_csv, out_dir = parse_args_and_paths()
    dts_helpers = load_dts_helpers()
    use_parquet = bool(args.input_parquet)

    # ------------------------------------------------------------------ discovery + load
    if use_parquet:
        pq_parts = parquet_parts(Path(args.input_parquet))
        header = parquet_header(pq_parts)
    else:
        header = read_header(input_csv)
    d = discover(header)
    hset, prog_col, vid_col, lot_col, bin_col = d.hset, d.prog_col, d.vid_col, d.lot_col, d.bin_col
    unmapped, vmin_cols, ilas_cols, dts_cols = d.unmapped, d.vmin_cols, d.ilas_cols, d.dts_cols
    sicc_atref, sicc_raw, upm_info, upm_status = d.sicc_atref, d.sicc_raw, d.upm_info, d.upm_status
    if use_parquet:
        df = load_parquet(pq_parts, d.usecols)
        unmapped.extend(parquet_manifest_unmapped(Path(args.input_parquet), unmapped))
    else:
        text_cols = {c: str for c in d.usecols if c.endswith(("_Setter", "_LP"))}  # keep leading zeros of LP / setter tokens
        df = pd.read_csv(input_csv, usecols=sorted(d.usecols), dtype=text_cols, low_memory=False)
    total_rows = len(df)
    df[prog_col] = df[prog_col].fillna("").astype(str).str.strip()
    df = df[(df[prog_col] != "") & (df[prog_col].str.lower() != "nan")]
    if args.program:
        df = df[df[prog_col].str.upper() == args.program.strip().upper()]
    df = df.reset_index(drop=True)
    if df.empty:
        raise SystemExit("No rows left after program filtering.")
    n = len(df)

    prog_counts = df[prog_col].value_counts()
    order = sorted(prog_counts.index, key=lambda p: ({"official": 0, "standard-name": 1, "other": 2}[tp_tag(p)], -prog_counts[p], p))
    programs = [{"name": p, "units": int(prog_counts[p]), "tag": tp_tag(p)} for p in order]
    pidx = {p["name"]: i for i, p in enumerate(programs)}
    prog_of_row = df[prog_col].map(pidx).to_numpy()
    selections = ["ALL"] + [str(i) for i in range(len(programs))]

    def sel_mask(sel: str) -> np.ndarray:
        return np.ones(n, dtype=bool) if sel == "ALL" else prog_of_row == int(sel)

    # UPM series (normalised, outlier-filtered over full population)
    upm_series: dict[str, dict] = {}
    for pu, rule in upm_info.items():
        if not rule:
            continue
        raw = finite(df[rule["col"]])
        x = raw / rule["divisor"] if rule["divisor"] else raw
        ok = np.isfinite(x)
        med, sd = (float(np.median(x[ok])), float(np.std(x[ok]))) if ok.any() else (float("nan"), float("nan"))
        lo, hi = med - UPM_SIGMA * sd, med + UPM_SIGMA * sd
        keep = ok & (x >= lo) & (x <= hi)
        upm_series[pu] = {"x": np.where(keep, x, np.nan), "col": rule["col"], "target": rule["target"],
                          "lo": lo, "hi": hi, "excluded": int(ok.sum() - keep.sum()), "valid": int(ok.sum())}

    # Per-unit plots / fits use a deterministic fair-share sample when the population exceeds --max-units;
    # unit counts, flow matrix and limiter analysis below are always computed on every unit.
    for p in programs:
        p["shown"] = p["units"]
    full_state = None
    if args.max_units and n > args.max_units:
        quota = fair_share_quota({p["name"]: p["units"] for p in programs}, args.max_units)
        keep_rows = sample_mask(df, vid_col, lot_col, prog_col, quota)
        full_state = (df, n, prog_of_row)
        df = df[keep_rows].reset_index(drop=True)
        n = len(df)
        prog_of_row = prog_of_row[keep_rows]
        for up in upm_series.values():
            up["x"] = up["x"][keep_rows]
        for i, p in enumerate(programs):
            p["shown"] = int((prog_of_row == i).sum())

    # ------------------------------------------------------------------ Vmin
    dom_display = {}
    vmin_groups: dict[str, dict] = defaultdict(lambda: {"pu": None, "tokens": set(), "series": defaultdict(list)})
    for col, pu, tok, freq, core in vmin_cols:
        disp = dts_helpers.resolve_domain_name(tok)
        g = vmin_groups[disp]
        if g["pu"] not in (None, pu):
            unmapped.append({"family": "Vmin", "token": f"{disp}", "count": 1,
                             "reason": f"domain spans multiple PU groups ({g['pu']}, {pu}); using first", "examples": col})
            continue
        g["pu"] = pu
        g["tokens"].add(tok)
        g["series"][(freq, core)].append(col)

    vmin_json = {}
    vmin_rows = []
    no_presi: list[str] = []
    presi_model_name = ""
    try:
        presi_path = latest_presi_model(PRESI_MODELS_DIR)
        presi_model_name = presi_path.stem
        presi_vf = read_presi_vf(presi_path)
    except Exception as exc:  # workbook optional
        presi_vf = {}
        unmapped.append({"family": "Vmin", "token": "PreSi VF model", "count": 1,
                         "reason": f"PreSi VF model not loaded ({type(exc).__name__}); no PreSi line on the VF curve", "examples": ""})
    for disp in sorted(vmin_groups):
        g = vmin_groups[disp]
        pu = g["pu"]
        up = upm_series.get(pu)
        rule = UPM_RULES.get(pu, {})
        freqs = sorted({f for f, _ in g["series"]})
        cores = sorted({c for _, c in g["series"]})
        dom = {"pu": pu, "die": rule.get("die", "?"), "tokens": sorted(g["tokens"]),
               "upm": up["col"] if up else None, "target": rule.get("target"),
               "freqs": freqs, "cores": cores, "rows": {s: [] for s in selections}, "pts": {}}
        for (freq, core), cols in sorted(g["series"].items()):
            y = np.full(n, np.nan)
            for c in cols:
                v = finite(df[c])
                y = np.where(np.isfinite(y), y, v)
            y = np.where((y > VMIN_VALID[0]) & (y < VMIN_VALID[1]), y, np.nan)
            ok_y = np.isfinite(y)
            if up:
                ok = ok_y & np.isfinite(up["x"])
            else:
                ok = ok_y
            dom["pts"][f"{freq}|{core}"] = [
                [r(up["x"][i], 5) if up else None, r(y[i], 4), int(prog_of_row[i])] for i in np.where(ok)[0]
            ]
            for sel in selections:
                m = sel_mask(sel) & ok
                cnt = int(m.sum())
                if cnt == 0:
                    continue
                row = {"f": freq, "c": core, "n": cnt}
                fit = linfit(up["x"][m], y[m]) if up else None
                if fit:
                    a, b, r2 = fit
                    xs = up["x"][m]
                    weak = bool(np.isfinite(r2) and r2 < WEAK_R2)
                    row.update(slope=r(a, 5), icpt=r(b, 5), r2=r(r2, 4),
                               v=r(float(np.median(y[m])), 4) if weak else r(a * up["target"] + b, 4),
                               meth=f"Median (weak R2 < {WEAK_R2:g})" if weak else "UPM fit",
                               extrap=False if weak else bool(up["target"] < xs.min() or up["target"] > xs.max()))
                else:
                    row.update(slope=None, icpt=None, r2=None, v=r(float(np.median(y[m])), 4),
                               meth="Median-based; UPM unavailable" if not up else "Median-based; too few points for UPM fit",
                               extrap=False)
                dom["rows"][sel].append(row)
                vmin_rows.append({"Selection": "ALL" if sel == "ALL" else programs[int(sel)]["name"], "Domain": disp, "PU": pu,
                                  "FreqGHz": freq, "Core": core, "N": cnt, "Slope": row["slope"], "Intercept": row["icpt"],
                                  "R2": row["r2"], "VminAtTarget": row["v"], "Method": row["meth"], "Extrapolated": row["extrap"],
                                  "UPMColumn": dom["upm"] or "", "Target": dom["target"]})
        dom.pop("rows")  # fits are recomputed in the page for the selected programs
        for tok in sorted(g["tokens"]):
            pre = POSTSI_TO_PRESI.get(tok)
            if pre and presi_vf.get(pre):
                dom["presi"], dom["presiToken"] = presi_vf[pre], pre
                break
        else:
            no_presi.append(disp)
        vmin_json[disp] = dom

    # ------------------------------------------------------------------ SICC
    sicc_json = {"measures": {}, "series": {}}
    sicc_rows = []
    series_defs = []  # (key, token, measure, col, pu)
    for col, tok, meas in sicc_atref:
        fam = sicc_family(tok)
        pu = FAMILY_TO_PU.get(fam)
        series_defs.append((col, tok, meas, pu))
    for col, pu, tok, v in sicc_raw:
        series_defs.append((col, tok, f"raw_V{v}", pu))
    labels = {"system_at_ref": "SICC system at ref", "tester_at_ref": "SICC tester at ref"}
    for _, _, meas, _ in series_defs:
        labels.setdefault(meas, f"SICC raw class {meas.split('_')[1]} (Value)")
    sicc_json["measures"] = {k: labels[k] for k in sorted({m for _, _, m, _ in series_defs})}
    empty_sicc: list[str] = []
    no_upm_rule: dict[str, list[str]] = {}
    def build_sicc_entry(label, meas, fam, pu, y, up_x, prow):
        """y / up_x / prow are already filtered to valid points (up_x may be None)."""
        up = upm_series.get(pu) if pu else None
        target = up["target"] if up else None
        entry = {"token": label, "measure": meas, "family": fam, "pu": pu, "upm": bool(up), "target": target,
                 "d": [[r(y[i], 5), int(prow[i]), r(up_x[i], 5) if up_x is not None else None] for i in range(len(y))],
                 "fits": {}}
        for sel in selections:
            m = np.ones(len(y), dtype=bool) if sel == "ALL" else (prow == int(sel))
            cnt = int(m.sum())
            if cnt == 0:
                continue
            vals = y[m]
            stat = {"n": cnt, "med": r(float(np.median(vals)), 5), "p5": r(float(np.quantile(vals, 0.05)), 5),
                    "p95": r(float(np.quantile(vals, 0.95)), 5)}
            if up_x is not None:
                fit = linfit(up_x[m], np.log(vals))
                if fit:
                    a, b, r2 = fit
                    stat.update(a=r(a, 5), b=r(b, 5), r2=r(r2, 4), at=r(math.exp(a * target + b), 5),
                                extrap=bool(target < up_x[m].min() or target > up_x[m].max()))
            entry["fits"][sel] = stat
            sicc_rows.append({"Selection": "ALL" if sel == "ALL" else programs[int(sel)]["name"], "Measure": meas, "Token": label,
                              "Family": fam, "PU": pu or "", "N": cnt, "Median": stat["med"], "P5": stat["p5"],
                              "P95": stat["p95"], "FitA": stat.get("a"), "FitB": stat.get("b"), "FitR2": stat.get("r2"),
                              "SICCAtUPMTarget": stat.get("at"), "Extrapolated": stat.get("extrap")})
        sicc_json["series"][f"{meas}|{label}"] = entry
        return entry

    pool_src: dict[tuple, list] = defaultdict(list)  # (deck domain, measure) -> [(y, x, prow)]
    for col, tok, meas, pu in series_defs:
        y = finite(df[col])
        y = np.where(y > 0, y, np.nan)
        up = upm_series.get(pu) if pu else None
        ok = np.isfinite(y) & (np.isfinite(up["x"]) if up else True)
        if not np.isfinite(y).any():
            empty_sicc.append(col)
            continue
        if not ok.any():
            continue
        if pu is None:
            no_upm_rule.setdefault(sicc_family(tok), []).append(f"{tok}/{meas}")
        idx = np.where(ok)[0]
        ux = up["x"][idx] if up else None
        build_sicc_entry(tok, meas, sicc_family(tok), pu, y[idx], ux, prog_of_row[idx])
        for dom_name, raw_rx, ref_rx, _, _ in SICC_TABLE_DOMAINS:
            rx = raw_rx if meas.startswith("raw_") else ref_rx
            if rx and ux is not None and re.fullmatch(rx, tok):
                pool_src[(dom_name, meas)].append((y[idx], ux, prog_of_row[idx], pu, tok))

    # pooled series (Core / Atom) and the per-domain "raw / tester / system @ UPM target vs PreSi target" table
    pooled_label = {d[0]: d[3] for d in SICC_TABLE_DOMAINS if d[3]}
    deck_entry: dict[tuple, dict] = {}
    for (deck, meas), parts in pool_src.items():
        if deck in pooled_label and len(parts) > 1:
            deck_entry[(deck, meas)] = build_sicc_entry(
                pooled_label[deck], meas, sicc_family(parts[0][4]), parts[0][3], np.concatenate([p[0] for p in parts]),
                np.concatenate([p[1] for p in parts]), np.concatenate([p[2] for p in parts]))
        else:
            deck_entry[(deck, meas)] = sicc_json["series"][f"{meas}|{parts[0][4]}"]

    # PreSi SICC targets: latest file of the PreSi Parameters folder, newest NVL-AX model column
    presi_rows: dict[str, dict] = {}
    sicc_json["presiSrc"] = None
    try:
        presi_path = latest_presi_params(PRESI_PARAMS_DIR)
        presi_rows, presi_col = read_presi_sicc(presi_path)
        sicc_json["presiSrc"] = {"file": presi_path.name, "column": presi_col}
    except Exception as exc:  # file optional
        unmapped.append({"family": "SICC", "token": "PreSi Parameters file", "count": 1,
                         "reason": f"PreSi SICC targets not loaded ({type(exc).__name__}: {exc}); table has no PreSi target", "examples": ""})
    sicc_json["targetDefs"] = []
    for name, _, _, _, prow in SICC_TABLE_DOMAINS:
        keys = {m: f"{m}|{deck_entry[(name, m)]['token']}" for m in ("raw_V1", "tester_at_ref", "system_at_ref")
                if (name, m) in deck_entry}
        if not keys:
            continue
        target = (presi_rows.get(prow) or {}).get("v1") if prow else None
        sicc_json["targetDefs"].append({"domain": name, "presiRow": prow, "presi": target, "keys": keys})
        if target is None:
            unmapped.append({"family": "SICC", "token": name, "count": 1,
                             "reason": "no PreSi SICC V1 target (no mapped row or empty value); excluded from the PreSi target table",
                             "examples": prow or ""})
    sicc_json["presiRows"] = [{"row": row, "alias": PRESI_ROW_ALIAS.get(row), "v1": vals["v1"], "v2": vals["v2"]}
                              for row, vals in presi_rows.items()]

    # S2T multiplier: System at ref / Tester at ref per unit, summarised per at-ref domain and test program
    s2t_cols: dict[str, dict[str, str]] = defaultdict(dict)
    for col, tok, meas in sicc_atref:
        s2t_cols[tok][meas] = col
    s2t_rows = []
    for tok in sorted(s2t_cols):
        cols = s2t_cols[tok]
        if "system_at_ref" not in cols or "tester_at_ref" not in cols:
            continue
        sys_v, tst_v = finite(df[cols["system_at_ref"]]), finite(df[cols["tester_at_ref"]])
        ok_s2t = np.isfinite(sys_v) & np.isfinite(tst_v) & (sys_v > 0) & (tst_v > 0)
        for pi in range(len(programs)):
            m = ok_s2t & (prog_of_row == pi)
            if not m.any():
                continue
            ratio = sys_v[m] / tst_v[m]
            med, lo, hi = float(np.median(ratio)), float(ratio.min()), float(ratio.max())
            s2t_rows.append({"d": tok, "fam": sicc_family(tok), "p": pi, "n": int(m.sum()), "med": r(med, 5), "min": r(lo, 5),
                             "max": r(hi, 5), "static": bool(hi - lo <= S2T_STATIC_TOL * abs(med))})
    sicc_json["s2t"] = s2t_rows
    # the same multiplier per table domain (tokens of a pooled domain such as Core / Atom are pooled) and test program
    s2t_dom_rows = []
    for dom_name, _, ref_rx, _, _ in SICC_TABLE_DOMAINS:
        if not ref_rx:
            continue
        toks = [t for t in s2t_cols if re.fullmatch(ref_rx, t) and "system_at_ref" in s2t_cols[t] and "tester_at_ref" in s2t_cols[t]]
        for pi in range(len(programs)):
            parts = []
            for t in toks:
                sv, tv = finite(df[s2t_cols[t]["system_at_ref"]]), finite(df[s2t_cols[t]["tester_at_ref"]])
                m = np.isfinite(sv) & np.isfinite(tv) & (sv > 0) & (tv > 0) & (prog_of_row == pi)
                if m.any():
                    parts.append(sv[m] / tv[m])
            if not parts:
                continue
            ratio = np.concatenate(parts)
            med, lo, hi = float(np.median(ratio)), float(ratio.min()), float(ratio.max())
            s2t_dom_rows.append({"dom": dom_name, "p": pi, "n": int(len(ratio)), "med": r(med, 5), "min": r(lo, 5), "max": r(hi, 5),
                                 "static": bool(hi - lo <= S2T_STATIC_TOL * abs(med))})
    sicc_json["s2tDom"] = s2t_dom_rows
    pd.DataFrame([{"Domain": x["d"], "Program": programs[x["p"]]["name"], "N": x["n"], "S2TMedian": x["med"], "S2TMin": x["min"],
                   "S2TMax": x["max"], "Static": x["static"]} for x in s2t_rows],
                 columns=["Domain", "Program", "N", "S2TMedian", "S2TMin", "S2TMax", "Static"]).to_csv(out_dir / "sicc_s2t.csv", index=False)
    for e in sicc_json["series"].values():
        e.pop("fits", None)  # fits are recomputed in the page for the selected programs

    if no_presi:
        unmapped.append({"family": "Vmin", "token": "PreSi VF model", "count": len(no_presi),
                         "reason": f"no matching domain in {presi_model_name or 'the PreSi model'} (via the PreSi to PostSi dictionary); no PreSi line on the VF curve",
                         "examples": "; ".join(no_presi)})

    if empty_sicc:
        unmapped.append({"family": "SICC", "token": "SICC columns with no data", "count": len(empty_sicc),
                         "reason": "columns exist in the header but are empty for the selected rows (not charted)",
                         "examples": "; ".join(empty_sicc[:3])})
    for fam, toks in no_upm_rule.items():
        unmapped.append({"family": "SICC", "token": f"family {fam}", "count": len(toks),
                         "reason": "no UPM rule for this family; distribution only", "examples": "; ".join(toks[:4])})

    # ------------------------------------------------------------------ DTS
    records = []
    for col, m in dts_cols:
        vals = finite(df[col])
        ok = np.isfinite(vals)
        if not ok.any():
            continue
        setter = df[col.replace("_MaxDTS_C", "_Setter")].fillna("").astype(str) if col.replace("_MaxDTS_C", "_Setter") in df else pd.Series([""] * n)
        lp = df[col.replace("_MaxDTS_C", "_LP")].fillna("").astype(str) if col.replace("_MaxDTS_C", "_LP") in df else pd.Series([""] * n)
        token = m["Domain"]
        freq = float(m["Freq"])
        sub = pd.DataFrame({
            "VisualID": df[vid_col].astype(str).to_numpy()[ok],
            "ProgIdx": prog_of_row[ok],
            "Domain": dts_helpers.resolve_domain_name(token),
            "DomainToken": token,
            "Corner": m["Corner"],
            "Flow": m["Flow"],
            "FrequencyGHz": freq,
            "FrequencyLabel": dts_helpers.get_display_frequency_label(freq),
            "CoreIndex": int(m["CoreIndex"]),
            "CoreLabel": f"core{int(m['CoreIndex'])}",
            "Setter": setter.to_numpy()[ok],
            "LimiterPattern": lp.to_numpy()[ok],
            "DtsTemperatureC": np.round(vals[ok], 4),
        })
        sub["Module"] = [dts_helpers.module_token_from_text(s, l) for s, l in zip(sub["Setter"], sub["LimiterPattern"])]
        records.append(sub)
    points_df = pd.concat(records, ignore_index=True) if records else pd.DataFrame()

    dts_json = {}
    dts_summaries = []
    if not points_df.empty:
        for domain, dd in points_df.groupby("Domain", sort=True):
            groups = []
            keyed = dd.groupby(["Corner", "FrequencyLabel", "Module"], sort=False)
            order_keys = sorted(keyed.groups.keys(), key=lambda k: (dts_helpers.corner_order_key(k[0]), float(k[1]),
                                                                    dts_helpers.module_sort_order(k[2]), k[2]))
            for k in order_keys:
                g = keyed.get_group(k)
                groups.append({"c": k[0], "f": k[1], "m": k[2], "v": g["DtsTemperatureC"].round(2).tolist(),
                               "p": g["ProgIdx"].astype(int).tolist()})
            dts_json[domain] = groups
        for sel in selections:
            sub = points_df if sel == "ALL" else points_df[points_df["ProgIdx"] == int(sel)]
            if sub.empty:
                continue
            s = dts_helpers.summarize_points(sub)
            s.insert(0, "Selection", "ALL" if sel == "ALL" else programs[int(sel)]["name"])
            dts_summaries.append(s)

    # ------------------------------------------------------------------ limiter analysis (ILAS) + overview
    # Good unit = interface bin 1 (PAS default).  Without a bin column all rows count.
    s_df, s_n, s_prog = df, n, prog_of_row  # the (possibly sampled) view used for per-unit points
    if full_state:
        df, n, prog_of_row = full_state

    def good_units(frame: pd.DataFrame) -> np.ndarray:
        if bin_col:
            return np.nan_to_num(finite(frame[bin_col]), nan=-1) == 1
        return np.ones(len(frame), dtype=bool)

    good = good_units(df)
    if not bin_col:
        unmapped.append({"family": "Overview", "token": "Interface bin column", "count": 1,
                         "reason": "no INTERFACE_BIN column in the CSV; every row is counted as a good unit", "examples": ""})

    mod_cache: dict[str, str] = {}
    pl_cache: dict[str, str] = {}

    def module_of(setter: str) -> str:
        if setter not in mod_cache:
            mod_cache[setter] = dts_helpers.module_token_from_text(setter, None)
        return mod_cache[setter]

    def plist_of(setter: str) -> str:
        if setter not in pl_cache:
            short = setter.split("::")[-1].strip().upper()
            mm = SETTER_PLIST_RX.search(short)
            pl_cache[setter] = (mm.group("pl") if mm and mm.group("pl") else "(none)")
        return pl_cache[setter]

    def pattern_of(lp: str, core: int) -> str:
        parts = [x.strip() for x in lp.split("^")] if lp else []
        if not parts:
            return "NA"
        k = core if (len(parts) > 2 and core < len(parts)) else 0
        return parts[k] or "NA"

    dom_ix: dict[str, int] = {}
    cor_ix: dict[str, int] = {}
    mod_ix: dict[str, int] = {}
    pl_ix: dict[str, int] = {}
    pat_ix: dict[str, int] = {}
    cell_ix: dict[tuple, int] = {}
    agg: dict[tuple, int] = defaultdict(int)
    tot_agg: dict[tuple, int] = defaultdict(int)
    flow_agg: dict[tuple, list] = {}
    flows_of_base: dict[str, set] = defaultdict(set)
    n_limiter_cols = 0
    for col, m in ilas_cols:
        vm = finite(df[col])
        base_name = col[: -len("_Vmin")]
        sc, lc = base_name + "_Setter", base_name + "_LP"
        token, corner, flow = m["Domain"].upper(), m["Corner"], (m["Flow"] or "")
        freq, core = float(m["Freq"]), int(m["CoreIndex"])
        base = re.sub(r"\d+$", "", token)
        okv = good & np.isfinite(vm)
        if not okv.any():
            continue
        # flow matrix entry: highest frequency per program / domain / flow / corner where any good unit has a Vmin
        for pi in range(len(programs)):
            cnt = int((okv & (prog_of_row == pi)).sum())
            if cnt:
                key = (pi, base, flow, corner)
                cur = flow_agg.get(key)
                if cur is None or freq > cur[0]:
                    flow_agg[key] = [freq, cnt]
                elif freq == cur[0]:
                    cur[1] = max(cur[1], cnt)
                if flow:
                    flows_of_base[base].add(flow)
        if sc not in df:
            continue
        setter = df[sc].fillna("").astype(str).str.strip().to_numpy()
        okl = okv & (setter != "")
        if not okl.any():
            continue
        lp = df[lc].fillna("").astype(str).str.strip().to_numpy() if lc in df else np.array([""] * n)
        n_limiter_cols += 1
        disp = dts_helpers.resolve_domain_name(token)
        di = dom_ix.setdefault(disp, len(dom_ix))
        ci = cor_ix.setdefault(corner, len(cor_ix))
        cell = cell_ix.setdefault((di, ci, freq, flow, core), len(cell_ix))
        for i in np.where(okl)[0]:
            s = setter[i]
            mi = mod_ix.setdefault(module_of(s), len(mod_ix))
            li = pl_ix.setdefault(plist_of(s), len(pl_ix))
            pi_ = pat_ix.setdefault(pattern_of(lp[i], core), len(pat_ix))
            agg[(cell, mi, li, pi_, int(prog_of_row[i]))] += 1
            tot_agg[(cell, int(prog_of_row[i]))] += 1

    def ordered(ix: dict[str, int], keyfn):
        names = sorted(ix, key=keyfn)
        remap = {ix[nm]: k for k, nm in enumerate(names)}
        return names, remap

    dom_names, dom_map = ordered(dom_ix, lambda s: s)
    cor_names, cor_map = ordered(cor_ix, dts_helpers.corner_order_key)
    mod_names, mod_map = ordered(mod_ix, lambda s: (dts_helpers.module_sort_order(s), s))
    pl_names, pl_map = ordered(pl_ix, lambda s: (s == "(none)", s))
    pat_names, pat_map = ordered(pat_ix, lambda s: s)
    cells = [None] * len(cell_ix)
    for (di, ci, freq, flow, core), k in cell_ix.items():
        cells[k] = [dom_map[di], cor_map[ci], freq, flow, core]
    ilas_json = {
        "doms": dom_names, "corners": cor_names, "mods": mod_names, "pls": pl_names, "pats": pat_names, "cells": cells,
        "rows": [[c, mod_map[mi], pl_map[li], pat_map[pi_], p, v] for (c, mi, li, pi_, p), v in agg.items()],
        "tot": [[c, p, v] for (c, p), v in tot_agg.items()],
        "columns": n_limiter_cols,
    }
    lim_df = pd.DataFrame([{"Program": programs[p]["name"], "Domain": dom_names[cells[c][0]], "Corner": cor_names[cells[c][1]],
                            "FrequencyGHz": cells[c][2], "Flow": cells[c][3], "Core": cells[c][4], "Module": mod_names[mod_map[mi]],
                            "Plist": pl_names[pl_map[li]], "LimitingPattern": pat_names[pat_map[pi_]], "Count": v,
                            "UnitsInCell": tot_agg[(c, p)]} for (c, mi, li, pi_, p), v in agg.items()])
    if lim_df.empty:
        unmapped.append({"family": "Limiter", "token": "ILAS Vmin/Setter/LP", "count": 1,
                         "reason": "no ILAS columns with limiter data; Module Pareto and Limiting Pattern are empty", "examples": ""})

    # flow matrix: FMIN columns carry no flow token; they are shown on the domain's flow row when the domain has exactly one flow
    flow_rows = []
    flowless_ambiguous = set()
    for (pi, base, flow, corner), (freq, cnt) in sorted(flow_agg.items()):
        fl = flow
        if not fl:
            if len(flows_of_base.get(base, ())) == 1:
                fl = next(iter(flows_of_base[base]))
            else:
                fl = "-"
                flowless_ambiguous.add(base)
        flow_rows.append([pi, base, fl, corner, freq, cnt])
    merged: dict[tuple, list] = {}
    for pi, base, fl, corner, freq, cnt in flow_rows:
        cur = merged.get((pi, base, fl, corner))
        if cur is None or freq > cur[0]:
            merged[(pi, base, fl, corner)] = [freq, cnt]
    flow_rows = [[*k, *v] for k, v in sorted(merged.items())]

    ovw_upm = {}
    good_s = good if not full_state else good_units(s_df)
    for label, pu in UPM_OVERVIEW:
        up = upm_series.get(pu)
        if not up:
            continue
        okx = good_s & np.isfinite(up["x"])
        ovw_upm[label] = {"pu": pu, "col": up["col"], "target": up["target"], "p": s_prog[okx].astype(int).tolist(),
                          "x": [r(v, 5) for v in up["x"][okx]]}
    overview_json = {
        "binCol": bin_col,
        "units": [{"p": i, "rows": int((prog_of_row == i).sum()), "good": int((good & (prog_of_row == i)).sum())} for i in range(len(programs))],
        "upm": ovw_upm,
        "flow": flow_rows,
        "flowlessAmbiguous": sorted(flowless_ambiguous),
    }

    # ------------------------------------------------------------------ side files
    if not lim_df.empty:
        lim_df.to_csv(out_dir / "vmin_limiter_patterns.csv", index=False)
    pd.DataFrame(vmin_rows).to_csv(out_dir / "vmin_fits.csv", index=False)
    pd.DataFrame(sicc_rows).to_csv(out_dir / "sicc_summary.csv", index=False)
    if dts_summaries:
        pd.concat(dts_summaries, ignore_index=True).to_csv(out_dir / "dts_bucket_summary.csv", index=False)
    if not points_df.empty:
        points_df.drop(columns=["ProgIdx"]).assign(ProgramName=points_df["ProgIdx"].map(lambda i: programs[int(i)]["name"])) \
            .to_csv(out_dir / "dts_points.csv", index=False)
    pd.DataFrame(unmapped).to_csv(out_dir / "unmapped_tokens.csv", index=False)

    if use_parquet:
        src_mtime = max(p.stat().st_mtime for p in pq_parts)
    else:
        src_mtime = input_csv.stat().st_mtime
    status = {
        "input": str(args.input_parquet) if use_parquet else str(input_csv),
        "modified": dt.datetime.fromtimestamp(src_mtime).strftime("%Y-%m-%d %H:%M"),
        "generated": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "rowsTotal": total_rows, "rowsUsed": n, "programFilter": args.program or None,
        "sampled": bool(full_state), "unitsShown": s_n, "maxUnits": args.max_units,
        "partitions": len(pq_parts) if use_parquet else None,
        "columns": {"vmin": len(vmin_cols), "dts": len(dts_cols), "ilasVmin": len(ilas_cols), "siccAtRef": len(sicc_atref), "siccRawValue": len(sicc_raw)},
        "upm": upm_status,
        "upmOutliers": {pu: {"valid": v["valid"], "excluded": v["excluded"], "lo": r(v["lo"], 4), "hi": r(v["hi"], 4)}
                        for pu, v in upm_series.items()},
        "officialTokens": sorted(OFFICIAL_TP_TOKENS),
    }
    data = {"status": status, "presiModel": presi_model_name, "params": {"minFit": MIN_FIT_POINTS, "weakR2": WEAK_R2}, "programs": programs, "vmin": vmin_json,
            "sicc": sicc_json, "dts": dts_json, "ilas": ilas_json, "overview": overview_json, "unmapped": unmapped}

    payload = json.dumps(data, separators=(",", ":"), allow_nan=False).replace("</", "<\\/")
    html = TEMPLATE_PATH.read_text(encoding="utf-8").replace("/*__DATA__*/null", payload)
    html_path = out_dir / f"{input_csv.stem}_parametric_tabs.html"
    html_path.write_text(html, encoding="utf-8")

    manifest = {**status, "outputs": [p.name for p in sorted(out_dir.iterdir())],
                "counts": {"vminDomains": len(vmin_json), "siccSeries": len(sicc_json["series"]),
                           "dtsDomains": len(dts_json), "dtsObservations": int(len(points_df)),
                           "unmappedEntries": len(unmapped)}}
    (out_dir / "run_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest["counts"]))
    print(html_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
