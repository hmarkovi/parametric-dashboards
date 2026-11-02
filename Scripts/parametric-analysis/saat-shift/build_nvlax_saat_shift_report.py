#!/usr/bin/env python
"""NVLAX SAAT UPSVF Vmin week-to-week shift analysis.

Reads the per-test-program organized files (By-Class-TP-final), joins per-unit HW attributes
(AQUA pull, optional TRACE export) and writes a self-contained interactive HTML report that
flags statistically significant Vmin shifts, dates them, and attributes them to hardware.

Statistics (all on unit-level Vmin in mV, 10 mV quantization -> rank-based tests):
  * Week-to-week and baseline comparisons: Mann-Whitney U + trimmed-mean shift, BH-FDR.
  * Change point: scan statistic on the time-ordered series with a block permutation test
    (units sharing a test end time are permuted together -> respects lot clustering).
  * Trend over weekly medians: Mann-Kendall (Kendall tau) + Theil-Sen slope.
  * HW attribution: per-level residual (vs the weekly median) Mann-Whitney vs the rest,
    Kruskal-Wallis per factor, level mix and within-level shift before/after the change point.
A series is flagged only when q < alpha AND |shift| >= --min-shift-mv.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import sys
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from scipy import stats

DEFAULT_DATA_DIR = r"R:\Products\NVL\NVL-AX\Weekly data pull\By-Class-TP-final"
DEFAULT_OUT_DIR = r"R:\Products\NVL\NVL-AX\Weekly data pull\SAAT_shift_analysis"
TOKEN_RE = re.compile(r"UPSVFPASSFLOW_(?P<domain>[A-Za-z0-9]+)_CLASSHOT_SAAT_(?P<freq>\d+(?:\.\d+)?)_(?P<idx>\d+)$")
TIME_COL = "LOTS End Date Time_CLASSHOT"
PROG_COL = "Program Name_CLASSHOT"
HW_RENAME = {
    "Testing_Entity": "Machine",
    "Unit_Tester_ID": "Tester",
    "Tester_Interface_Unit_ID": "Interface_Unit",
    "Socket_ID": "Socket",
}
EPOCH = pd.Timestamp("1970-01-01", tz="UTC")
NON_HW_FACTORS = {"Lot", "Program"}
# Sort UPM used to normalize each domain's Vmin (same convention as the NVLH starting-point analysis).
UPM_BY_DOMAIN = {
    "U1PU2": "TPI_UPM::UPM_X_SCREEN_K_START_X_X_X_X_FEM_CALC_UPM_FEM_ULVT_FULLDIE_PDK0P9_0950MV_SORT_U1.U2",
}


# ----------------------------------------------------------------------------- statistics
def bh(pvalues) -> np.ndarray:
    p = np.asarray(pvalues, float)
    q = np.full_like(p, np.nan)
    ok = ~np.isnan(p)
    pv = p[ok]
    n = len(pv)
    if n == 0:
        return q
    order = np.argsort(pv)
    ranked = pv[order] * n / (np.arange(n) + 1)
    ranked = np.minimum.accumulate(ranked[::-1])[::-1]
    out = np.empty(n)
    out[order] = np.minimum(ranked, 1.0)
    q[ok] = out
    return q


def mwu_p(a: np.ndarray, b: np.ndarray) -> float:
    if len(a) < 2 or len(b) < 2:
        return float("nan")
    if np.ptp(np.concatenate([a, b])) == 0:
        return 1.0
    try:
        return float(stats.mannwhitneyu(a, b, alternative="two-sided", method="asymptotic").pvalue)
    except ValueError:
        return float("nan")


def hl_shift(a: np.ndarray, b: np.ndarray, rng: np.random.Generator | None = None, cap: int = 0) -> float:
    """Shift estimate (b - a) as the difference of 10%-trimmed means.

    Medians / Hodges-Lehmann collapse to multiples of the 10 mV quantization step; trimmed means stay
    robust to outliers while resolving sub-step shifts.
    """
    if len(a) == 0 or len(b) == 0:
        return float("nan")
    return float(stats.trim_mean(b, 0.1) - stats.trim_mean(a, 0.1))


def change_point(t_ms: np.ndarray, x: np.ndarray, min_n: int, n_perm: int, rng: np.random.Generator):
    """Single mean-shift change point; block permutation (blocks = identical end time)."""
    order = np.argsort(t_ms, kind="stable")
    t = t_ms[order]
    y = x[order]
    n = len(y)
    _, starts = np.unique(t, return_index=True)
    if len(starts) < 4 or n < 2 * min_n:
        return None
    sd = float(y.std())
    if sd == 0:
        return None
    ends = list(starts[1:]) + [n]
    blocks = [y[s:e] for s, e in zip(starts, ends)]

    def scan(arrs):
        xx = np.concatenate(arrs)
        cs = np.cumsum(xx)
        sizes = np.cumsum([len(a) for a in arrs])[:-1]
        ok = (sizes >= min_n) & (n - sizes >= min_n)
        if not ok.any():
            return -1.0, -1
        k = sizes[ok]
        m1 = cs[k - 1] / k
        m2 = (cs[-1] - cs[k - 1]) / (n - k)
        z = np.abs(m1 - m2) / (sd * np.sqrt(1.0 / k + 1.0 / (n - k)))
        j = int(np.argmax(z))
        return float(z[j]), int(np.flatnonzero(ok)[j])

    obs, block_j = scan(blocks)
    if block_j < 0:
        return None
    exceed = 0
    for _ in range(n_perm):
        perm = rng.permutation(len(blocks))
        stat, _ = scan([blocks[i] for i in perm])
        if stat >= obs:
            exceed += 1
    p = (1 + exceed) / (1 + n_perm)
    cut = int(starts[block_j + 1])
    before, after = y[:cut], y[cut:]
    return {
        "p": p,
        "z": obs,
        "split_ms": int(t[cut]),
        "last_before_ms": int(t[cut - 1]),
        "n_before": int(len(before)),
        "n_after": int(len(after)),
        "median_before": float(np.median(before)),
        "median_after": float(np.median(after)),
        "shift_mv": hl_shift(before, after, rng),
    }


# ----------------------------------------------------------------------------- per-series analysis
def analyze_series(df: pd.DataFrame, factors: list[str], cfg: dict, rng: np.random.Generator) -> dict:
    """df columns: t_ms, mv, wk (monday str), wk_label, plus factor columns (strings)."""
    df = df.sort_values("t_ms").reset_index(drop=True)
    mv = df["mv"].to_numpy(float)
    wk = df["wk"].to_numpy()
    weeks = sorted(df["wk"].unique())
    label_of = dict(zip(df["wk"], df["wk_label"]))

    wk_stats = []
    groups = {}
    for w in weeks:
        g = mv[wk == w]
        groups[w] = g
        wk_stats.append({
            "wk": w, "label": label_of[w], "n": int(len(g)), "median": float(np.median(g)),
            "mean": float(g.mean()), "std": float(g.std()),
            "q1": float(np.percentile(g, 25)), "q3": float(np.percentile(g, 75)),
            "valid": bool(len(g) >= cfg["min_n"]),
        })
    valid = [s["wk"] for s in wk_stats if s["valid"]]

    def pair_test(kind, a, b):
        ga, gb = groups[a], groups[b]
        return {
            "kind": kind, "wk_a": a, "wk_b": b, "label_a": label_of[a], "label_b": label_of[b],
            "n_a": int(len(ga)), "n_b": int(len(gb)),
            "median_a": float(np.median(ga)), "median_b": float(np.median(gb)),
            "shift_mv": hl_shift(ga, gb, rng), "p": mwu_p(ga, gb), "q": float("nan"), "flag": False,
        }

    tests = [pair_test("consecutive", a, b) for a, b in zip(valid[:-1], valid[1:])]
    tests += [pair_test("baseline", valid[0], b) for b in valid[2:]] if len(valid) > 2 else []

    cp = change_point(df["t_ms"].to_numpy(np.int64), mv, cfg["min_n"], cfg["n_perm"], rng)
    if cp is not None:
        cp["q"] = float("nan")
        cp["flag"] = False

    trend = None
    if len(valid) >= 4:
        x = np.arange(len(valid), dtype=float)
        med = np.array([np.median(groups[w]) for w in valid])
        tau, p = stats.kendalltau(x, med)
        slope = stats.theilslopes(med, x)[0]
        trend = {"tau": float(tau), "p": float(p), "slope_mv_per_week": float(slope), "n_weeks": len(valid)}

    # HW attribution: residual vs weekly median
    week_med = {w: np.median(groups[w]) for w in weeks}
    resid = mv - np.array([week_med[w] for w in wk])
    cut_ms = cp["split_ms"] if cp else None
    t_ms = df["t_ms"].to_numpy(np.int64)
    levels = {}
    hw_rows = []
    kw = {}
    for f in factors:
        col = df[f].fillna("(unknown)").astype(str)
        cats = sorted(col.unique())
        levels[f] = cats
        codes = col.map({c: i for i, c in enumerate(cats)}).to_numpy(int)
        df[f + "__i"] = codes
        eligible = [i for i in range(len(cats)) if (codes == i).sum() >= cfg["hw_min_n"] and cats[i] != "(unknown)"]
        if len(eligible) >= 2:
            try:
                h, pk = stats.kruskal(*[resid[codes == i] for i in eligible])
                kw[f] = {"p": float(pk), "eps2": float(max(0.0, (h - len(eligible) + 1) / (len(resid) - len(eligible))))}
            except ValueError:
                pass
        for i in eligible:
            m = codes == i
            lev, rest = resid[m], resid[~m]
            row = {
                "factor": f, "level": cats[i], "n": int(m.sum()),
                "resid_mv": hl_shift(rest, lev, rng), "p": mwu_p(lev, rest), "q": float("nan"), "flag": False,
                "n_before": None, "n_after": None, "share_before": None, "share_after": None, "level_shift_mv": None,
                "step_mv": None, "step_p": None, "step_q": float("nan"), "step_ms": None, "step_flag": False,
            }
            if f not in NON_HW_FACTORS:
                # residual vs the weekly median of all OTHER units (avoids diluting the level's own shift)
                rest_med = {w: (np.median(mv[(wk == w) & ~m]) if ((wk == w) & ~m).sum() >= 5 else week_med[w]) for w in np.unique(wk[m])}
                lev_r = mv[m] - np.array([rest_med[w] for w in wk[m]])
                scp = change_point(t_ms[m], lev_r, cfg["hw_step_min"], cfg["hw_perm"], rng)
                if scp is not None:
                    row.update({"step_mv": scp["shift_mv"], "step_p": scp["p"], "step_ms": scp["split_ms"]})
            if cut_ms is not None:
                b = m & (t_ms < cut_ms)
                a = m & (t_ms >= cut_ms)
                nb_all, na_all = (t_ms < cut_ms).sum(), (t_ms >= cut_ms).sum()
                row["n_before"], row["n_after"] = int(b.sum()), int(a.sum())
                row["share_before"] = float(b.sum() / nb_all) if nb_all else None
                row["share_after"] = float(a.sum() / na_all) if na_all else None
                if b.sum() >= 5 and a.sum() >= 5:
                    row["level_shift_mv"] = hl_shift(mv[b], mv[a], rng)
            hw_rows.append(row)

    scope = {}
    if cp is not None:
        for f in factors:
            rows = [r for r in hw_rows if r["factor"] == f and r["level_shift_mv"] is not None]
            if rows:
                sign = math.copysign(1.0, cp["shift_mv"]) if cp["shift_mv"] else 1.0
                hit = sum(1 for r in rows if r["level_shift_mv"] * sign >= 0.5 * abs(cp["shift_mv"]))
                scope[f] = {"levels_shifted": hit, "levels_tested": len(rows)}
    return {"weeks": wk_stats, "tests": tests, "cp": cp, "trend": trend, "hw": hw_rows,
            "kw": kw, "levels": levels, "scope": scope, "df": df}


def apply_flags(results: list[dict], cfg: dict) -> None:
    for basis in sorted({r["basis"] for r in results}):
        _apply_flags([r for r in results if r["basis"] == basis], cfg)


def _apply_flags(results: list[dict], cfg: dict) -> None:
    alpha, thr = cfg["alpha"], cfg["min_shift_mv"] - 1e-9
    for kind in ("consecutive", "baseline"):
        items = [t for r in results for t in r["tests"] if t["kind"] == kind]
        for t, q in zip(items, bh([t["p"] for t in items])):
            t["q"] = float(q)
            t["flag"] = bool(q < alpha and abs(t["shift_mv"]) >= thr)
    cps = [r["cp"] for r in results if r["cp"] is not None]
    for c, q in zip(cps, bh([c["p"] for c in cps])):
        c["q"] = float(q)
        c["flag"] = bool(q < alpha and abs(c["shift_mv"]) >= thr)
    hws = [h for r in results for h in r["hw"]]
    for h, q in zip(hws, bh([h["p"] for h in hws])):
        h["q"] = float(q)
        h["flag"] = bool(q < alpha and abs(h["resid_mv"]) >= thr)
    steps = [h for h in hws if h["step_p"] is not None]
    for h, q in zip(steps, bh([h["step_p"] for h in steps])):
        h["step_q"] = float(q)
        h["step_flag"] = bool(q < alpha and abs(h["step_mv"]) >= thr)
    for h in hws:
        # effective shift = the step if the level has a flagged step, else the all-period offset
        h["eff_mv"] = h["step_mv"] if h["step_flag"] else h["resid_mv"]
        h["flag"] = bool(h["flag"] or h["step_flag"])


# ----------------------------------------------------------------------------- data loading
def load_long(data_dir: str) -> tuple[pd.DataFrame, list[dict]]:
    frames, quality = [], []
    for path in sorted(glob.glob(os.path.join(data_dir, "NVLAX*.csv"))):
        tp = os.path.splitext(os.path.basename(path))[0]
        header = pd.read_csv(path, nrows=0).columns.tolist()
        tokens = {c: TOKEN_RE.search(c) for c in header}
        tokens = {c: m for c, m in tokens.items() if m and "SAAT" in c}
        if not tokens or TIME_COL not in header or "VISUAL_ID" not in header:
            continue
        upm_cols = sorted({UPM_BY_DOMAIN[m["domain"]] for m in tokens.values() if m["domain"] in UPM_BY_DOMAIN} & set(header))
        keep = ["VISUAL_ID", TIME_COL] + [c for c in ("LOTFROMFS", PROG_COL) if c in header] + list(tokens) + upm_cols
        raw = pd.read_csv(path, usecols=keep, low_memory=False)
        raw["t"] = pd.to_datetime(raw[TIME_COL], utc=True, errors="coerce")
        raw = raw.dropna(subset=["t"])
        for col, m in tokens.items():
            vals = pd.to_numeric(raw[col], errors="coerce")
            blank, nonpos = int(vals.isna().sum()), int((vals <= 0).sum())
            ok = vals.notna() & (vals > 0)
            upm_col = UPM_BY_DOMAIN.get(m["domain"])
            upm = pd.to_numeric(raw[upm_col], errors="coerce") if upm_col in raw else pd.Series(np.nan, index=raw.index)
            quality.append({"tp": tp, "token": col, "rows": int(len(raw)), "blank": blank, "nonpositive": nonpos})
            part = pd.DataFrame({
                "tp": tp, "token": col, "domain": m["domain"], "freq": float(m["freq"]),
                "vid": raw.loc[ok, "VISUAL_ID"].astype(str).str.strip(),
                "lot": raw.loc[ok, "LOTFROMFS"].astype(str) if "LOTFROMFS" in raw else "(unknown)",
                "program": raw.loc[ok, PROG_COL].astype(str) if PROG_COL in raw else "(unknown)",
                "t": raw.loc[ok, "t"], "mv": vals[ok] * 1000.0, "upm": upm[ok],
            })
            frames.append(part)
    if not frames:
        raise SystemExit(f"No SAAT UPSVF columns found in {data_dir}")
    long = pd.concat(frames, ignore_index=True)
    long = long.drop_duplicates(subset=["tp", "token", "vid", "t"], keep="first")
    return long, quality


def join_hw(long: pd.DataFrame, hw_csv: str | None, extra_csv: str | None, out_dir: str) -> tuple[pd.DataFrame, list[str], str]:
    factors = ["Lot", "Program"]
    long = long.rename(columns={"lot": "Lot", "program": "Program"})
    note = "no HW file"
    if hw_csv is None:
        found = sorted(glob.glob(os.path.join(out_dir, "HW_attributes_*.csv")))
        hw_csv = found[-1] if found else None
    long["t"] = long["t"].astype("datetime64[ns, UTC]")
    long = long.sort_values("t").reset_index(drop=True)
    if hw_csv and os.path.isfile(hw_csv):
        hw = pd.read_csv(hw_csv, low_memory=False).rename(columns=HW_RENAME)
        hw["End_Date_Time"] = pd.to_datetime(hw["End_Date_Time"], utc=True, errors="coerce").astype("datetime64[ns, UTC]")
        hw = hw.dropna(subset=["End_Date_Time"]).sort_values("End_Date_Time")
        cols = [c for c in HW_RENAME.values() if c in hw.columns]
        hw = hw[["Visual_ID", "End_Date_Time"] + cols]
        hw["Visual_ID"] = hw["Visual_ID"].astype(str).str.strip()
        long = pd.merge_asof(long, hw, left_on="t", right_on="End_Date_Time", left_by="vid", right_by="Visual_ID",
                             direction="nearest", tolerance=pd.Timedelta(hours=12))
        long = long.drop(columns=["End_Date_Time", "Visual_ID"])
        for c in cols:
            long[c] = long[c].apply(lambda x: str(int(x)) if isinstance(x, float) and x == x and x == int(x) else x)
        factors = [c for c in ("Machine", "Tester", "Interface_Unit", "Socket") if c in cols] + factors
        note = os.path.basename(hw_csv)
    if extra_csv and os.path.isfile(extra_csv):
        extra = pd.read_csv(extra_csv, low_memory=False)
        key = next((c for c in extra.columns if c.lower().replace("_", "") in ("visualid", "unitid")), None)
        if key:
            extra[key] = extra[key].astype(str).str.strip()
            extra = extra.drop_duplicates(subset=[key]).rename(columns={key: "vid"})
            new_cols = [c for c in extra.columns if c != "vid" and c not in long.columns]
            long = long.merge(extra[["vid"] + new_cols], on="vid", how="left")
            factors = [c for c in new_cols] + factors
            note += f" + {os.path.basename(extra_csv)}"
    return long, factors, note


def add_time_cols(long: pd.DataFrame) -> pd.DataFrame:
    long["t_ms"] = ((long["t"] - EPOCH) // pd.Timedelta(milliseconds=1)).astype("int64")
    naive = long["t"].dt.tz_localize(None)
    monday = (naive.dt.normalize() - pd.to_timedelta(naive.dt.weekday, unit="D"))
    long["wk"] = monday.dt.strftime("%Y-%m-%d")
    iso = monday.dt.isocalendar()
    long["wk_label"] = iso["year"].astype(str) + "-WW" + iso["week"].astype(str).str.zfill(2)
    return long


# ----------------------------------------------------------------------------- orchestration
def sanitize(o):
    if isinstance(o, dict):
        return {k: sanitize(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [sanitize(v) for v in o]
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (float, np.floating)):
        return None if (math.isnan(o) or math.isinf(o)) else float(o)
    if isinstance(o, np.bool_):
        return bool(o)
    return o


def normalize_to_upm(long: pd.DataFrame, min_fit_n: int = 30) -> dict:
    """Add `mv_norm` = Vmin corrected to the series' median UPM.

    One pooled linear fit Vmin = a*UPM + b per (test program, token), pooled over all weeks and all HW so
    that a HW or time shift is not absorbed by the fit. mv_norm = mv - a*(UPM - UPM_median).
    Units whose UPM is a robust outlier (> 5 sigma) are left out of the normalized basis.
    """
    long["mv_norm"] = np.nan
    # Elastomer-monitoring metric from the MPE decks: Vmin / FEM (speed), reported x1000 (1.03 V/FEM = 1030)
    long["mv_ratio"] = np.where(long["upm"] > 0.5, long["mv"] / long["upm"], np.nan)
    fits = {}
    for (tp, token), g in long.groupby(["tp", "token"], sort=False):
        g = g.dropna(subset=["upm"])
        if len(g) < min_fit_n:
            continue
        x, y = g["upm"].to_numpy(float), g["mv"].to_numpy(float)
        mad = 1.4826 * np.median(np.abs(x - np.median(x)))
        keep = np.abs(x - np.median(x)) <= 5 * mad if mad > 0 else np.ones(len(x), bool)
        if keep.sum() < min_fit_n or np.ptp(x[keep]) == 0:
            continue
        for _ in range(2):
            slope, icpt = np.polyfit(x[keep], y[keep], 1)
            res = y - (slope * x + icpt)
            sd = 1.4826 * np.median(np.abs(res[keep] - np.median(res[keep])))
            keep = keep & (np.abs(res) <= 3 * sd) if sd > 0 else keep
        ref = float(np.median(x[keep]))
        r2 = float(np.corrcoef(x[keep], y[keep])[0, 1] ** 2)
        ok = np.abs(x - np.median(x)) <= 5 * mad if mad > 0 else np.ones(len(x), bool)
        idx = g.index[ok]
        long.loc[idx, "mv_norm"] = long.loc[idx, "mv"] - slope * (long.loc[idx, "upm"] - ref)
        fits[(tp, token)] = {"slope": float(slope), "r2": r2, "upm_ref": ref, "n_fit": int(keep.sum())}
    return fits


def run_analysis(long: pd.DataFrame, factors: list[str], cfg: dict, seed: int = 12345, bases=("raw", "upm", "ratio")):
    rng = np.random.default_rng(seed)
    series, skipped = [], []
    for basis in bases:
        col = {"raw": "mv", "upm": "mv_norm", "ratio": "mv_ratio"}[basis]
        if col not in long:
            continue
        for (tp, token), g in long.dropna(subset=[col]).groupby(["tp", "token"], sort=True):
            if len(g) < 2 * cfg["min_n"]:
                skipped.append({"tp": tp, "token": token, "basis": basis, "reason": f"only {len(g)} units (< {2 * cfg['min_n']})"})
                continue
            g = g.copy()
            g["mv"] = g[col]
            res = analyze_series(g, factors, cfg, rng)
            res.update({"tp": tp, "token": token, "basis": basis, "domain": g["domain"].iloc[0], "freq": float(g["freq"].iloc[0])})
            series.append(res)
    apply_flags(series, cfg)
    return series, skipped


def alarm_line(long: pd.DataFrame, freq: float, basis: str, cfg: dict) -> dict | None:
    """Vmin/FEM alarm line per frequency, pooled over all NVLAX programs.

    baseline = 25th percentile of weekly per-TIU median Vmin/FEM (TIUs with >= min_n units that week); this
    matches the level of the freshest (low-spread) TIUs. alarm = baseline + alarm_offset (the ~40 mV median rise
    that the MPE elastomer decks associate with halved top-frequency pass rate).
    """
    if cfg.get("alarm_offset") is None:
        return None
    d = long[(long["freq"] == freq) & long["mv_ratio"].notna() & long["Interface_Unit"].notna()] if "Interface_Unit" in long else None
    if d is None or d.empty:
        return None
    wk_label = d["t"].dt.strftime("%G-W%V")
    g = d.groupby([d["Interface_Unit"], wk_label])["mv_ratio"].agg(["median", "count"])
    g = g[g["count"] >= cfg["min_n"]]["median"]
    if len(g) < 8:
        return None
    base = float(g.quantile(0.25))
    return {"baseline": base, "line": base + cfg["alarm_offset"], "offset": cfg["alarm_offset"],
            "n_tiu_weeks": int(len(g)), "pct_above": float((g > base + cfg["alarm_offset"]).mean() * 100)}


def build_view(long: pd.DataFrame, factors: list[str]) -> dict:
    """Compact unit-level Vmin/FEM dataset for the descriptive (no thresholds) portrayal section."""
    d = long[long["mv_ratio"].notna()].sort_values("t_ms").reset_index(drop=True)
    freqs = sorted(d["freq"].unique().tolist())
    tps = sorted(d["tp"].unique().tolist())
    weeks = d[["wk", "wk_label"]].drop_duplicates().sort_values("wk")
    wk_idx = {w: i for i, w in enumerate(weeks["wk"])}
    out = {"freqs": freqs, "tps": tps, "weeks": weeks["wk_label"].tolist(),
           "t": d["t_ms"].tolist(), "r": d["mv_ratio"].round(1).tolist(),
           "raw": d["mv"].round(1).tolist(),
           "f": d["freq"].map({f: i for i, f in enumerate(freqs)}).tolist(),
           "p": d["tp"].map({p: i for i, p in enumerate(tps)}).tolist(),
           "w": d["wk"].map(wk_idx).tolist(), "lv": {}, "names": {}}
    for f in factors:
        if f not in d:
            continue
        col = d[f].fillna("(unknown)").astype(str)
        cats = sorted(col.unique())
        out["names"][f] = cats
        out["lv"][f] = col.map({c: i for i, c in enumerate(cats)}).tolist()
    return out


def build_payload(series, skipped, quality, factors, hw_note, cfg, long, fits):
    q_lookup = {(q["tp"], q["token"]): q for q in quality}
    out_series, flags = [], []
    for sid, r in enumerate(series):
        df = r["df"]
        basis = r["basis"]
        weeks_idx = {s["wk"]: i for i, s in enumerate(r["weeks"])}
        progs = (df.sort_values("t_ms").groupby("Program")["t_ms"].min().sort_values())
        tester_cov = float(df["Tester"].notna().mean()) if "Tester" in df else None
        suspects = sorted([h for h in r["hw"] if h["flag"]], key=lambda h: -abs(h["eff_mv"]))
        sus_txt = ", ".join(
            f"{h['factor']}={h['level']} ({h['step_mv']:+.1f} mV step {datetime.fromtimestamp(h['step_ms'] / 1000, tz=timezone.utc):%Y-%m-%d})"
            if h["step_flag"] else f"{h['factor']}={h['level']} ({h['resid_mv']:+.1f} mV)" for h in suspects[:3])
        item = {
            "sid": sid, "tp": r["tp"], "token": r["token"], "freq": r["freq"], "domain": r["domain"], "basis": basis,
            "alarm": alarm_line(long, r["freq"], basis, cfg) if basis == "ratio" else None,
            "norm": fits.get((r["tp"], r["token"])),
            "n": int(len(df)), "weeks": r["weeks"], "tests": r["tests"], "cp": r["cp"], "trend": r["trend"],
            "hw": r["hw"], "kw": r["kw"], "scope": r["scope"], "levels": r["levels"],
            "progs": [{"name": n, "first_ms": int(t)} for n, t in progs.items()],
            "hw_cov": tester_cov,
            "u": {"t": df["t_ms"].tolist(), "v": df["mv"].round(1).tolist(),
                  "w": [weeks_idx[w] for w in df["wk"]],
                  "f": {f: df[f + "__i"].tolist() for f in factors}},
        }
        out_series.append(item)
        for t in r["tests"]:
            if t["flag"]:
                flags.append({"sid": sid, "tp": r["tp"], "token": r["token"], "freq": r["freq"], "basis": basis,
                              "type": "Week-to-week" if t["kind"] == "consecutive" else "Drift vs first week",
                              "when": f"{t['label_a']} -> {t['label_b']}", "when_sort": t["wk_b"],
                              "shift_mv": t["shift_mv"], "q": t["q"], "n_a": t["n_a"], "n_b": t["n_b"], "suspects": sus_txt})
        c = r["cp"]
        if c and c["flag"]:
            when = datetime.fromtimestamp(c["split_ms"] / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
            flags.append({"sid": sid, "tp": r["tp"], "token": r["token"], "freq": r["freq"], "basis": basis, "type": "Change point",
                          "when": when, "when_sort": when, "shift_mv": c["shift_mv"], "q": c["q"],
                          "n_a": c["n_before"], "n_b": c["n_after"], "suspects": sus_txt})
    flags.sort(key=lambda f: -abs(f["shift_mv"]))

    board = {}
    for sid, r in enumerate(series):
        for h in r["hw"]:
            key = (r["basis"], h["factor"], h["level"])
            b = board.setdefault(key, {"basis": r["basis"], "factor": h["factor"], "level": h["level"], "series_tested": 0, "series_flagged": 0,
                                       "n": 0, "resid_sum": 0.0, "worst": 0.0, "worst_series": ""})
            b["series_tested"] += 1
            b["n"] += h["n"]
            if h["flag"]:
                b["series_flagged"] += 1
                b["resid_sum"] += h["eff_mv"]
                if abs(h["eff_mv"]) > abs(b["worst"]):
                    b["worst"] = h["eff_mv"]
                    b["worst_series"] = f"{r['tp']} / {r['freq']:.3f}"
    leaderboard = sorted([dict(b, mean_resid=(b["resid_sum"] / b["series_flagged"]) if b["series_flagged"] else 0.0)
                          for b in board.values() if b["series_flagged"]],
                         key=lambda b: (-b["series_flagged"], -abs(b["worst"])))

    dq = []
    analysed = {(r["tp"], r["token"]) for r in series if r["basis"] == "raw"}
    skipped_map = {(s["tp"], s["token"]): s["reason"] for s in skipped if s["basis"] == "raw"}
    kept = long.groupby(["tp", "token"]).size().to_dict()
    cov = long.groupby(["tp", "token"])["Tester"].apply(lambda s: float(s.notna().mean())).to_dict() if "Tester" in long else {}
    for (tp, token), q in sorted(q_lookup.items()):
        n_valid_weeks = 0
        for r in series:
            if r["tp"] == tp and r["token"] == token and r["basis"] == "raw":
                n_valid_weeks = sum(1 for w in r["weeks"] if w["valid"])
        fit = fits.get((tp, token)) or {}
        dq.append({"tp": tp, "token": token, "rows": q["rows"], "blank": q["blank"], "nonpositive": q["nonpositive"],
                   "kept": int(kept.get((tp, token), 0)), "valid_weeks": n_valid_weeks,
                   "hw_cov": cov.get((tp, token)), "upm_r2": fit.get("r2"), "upm_slope": fit.get("slope"),
                   "status": "analysed" if (tp, token) in analysed else skipped_map.get((tp, token), "no data")})
    return sanitize({
        "meta": {"generated": datetime.now().strftime("%Y-%m-%d %H:%M"), "hw_source": hw_note, "factors": factors,
                 "cfg": cfg, "n_series": len(series), "n_flags": len(flags),
                 "t_min": int(long["t_ms"].min()), "t_max": int(long["t_ms"].max())},
        "series": out_series, "flags": flags, "leaderboard": leaderboard[:60], "dq": dq,
        "view": build_view(long, factors),
    })


def write_csvs(payload: dict, out_dir: str) -> None:
    pd.DataFrame(payload["flags"]).to_csv(os.path.join(out_dir, "saat_shift_flags.csv"), index=False)
    weeks, hws = [], []
    for s in payload["series"]:
        for w in s["weeks"]:
            weeks.append({"tp": s["tp"], "token": s["token"], "basis": s["basis"], **w})
        for h in s["hw"]:
            hws.append({"tp": s["tp"], "token": s["token"], "basis": s["basis"], **h})
    pd.DataFrame(weeks).to_csv(os.path.join(out_dir, "saat_shift_weekly_stats.csv"), index=False)
    pd.DataFrame(hws).to_csv(os.path.join(out_dir, "saat_shift_hw_attribution.csv"), index=False)


def render_html(payload: dict, out_path: str) -> None:
    from plotly.offline import get_plotlyjs
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "saat_shift_template.html"), encoding="utf-8") as fh:
        template = fh.read()
    data = json.dumps(payload, separators=(",", ":"), allow_nan=False).replace("</", "<\\/")
    html = template.replace("/*__PLOTLY__*/", get_plotlyjs()).replace("/*__DATA__*/", data)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(html)


# ----------------------------------------------------------------------------- self test
def selftest() -> int:
    rng = np.random.default_rng(7)
    cfg = {"min_n": 15, "n_perm": 300, "hw_min_n": 10, "hw_step_min": 8, "hw_perm": 300, "alpha": 0.05, "min_shift_mv": 10.0}
    testers = ["T1", "T2", "T3", "T4"]
    start = pd.Timestamp("2026-09-07", tz="UTC")

    def make(tp, shift_all=0.0, shift_t3=0.0, step_week=4):
        rows = []
        for w in range(8):
            for lot in range(5):
                t = start + pd.Timedelta(days=7 * w + lot, hours=3)
                lot_eff = rng.normal(0, 3)
                for _ in range(30):
                    tester = testers[int(rng.integers(0, 4))]
                    v = 700 + lot_eff + rng.normal(0, 15)
                    if w >= step_week:
                        v += shift_all + (shift_t3 if tester == "T3" else 0.0)
                    rows.append((tp, "tok", "U1PU2", 3.6, f"V{len(rows)}", f"L{w}{lot}", "P1", t,
                                 round(v / 10) * 10.0, tester))
        return rows
    rows = make("A_global15", 15) + make("B_global5", 5) + make("C_none") + make("D_t3_30", 0, 30)
    long = pd.DataFrame(rows, columns=["tp", "token", "domain", "freq", "vid", "Lot", "Program", "t", "mv", "Tester"])
    long = add_time_cols(long)
    series, _ = run_analysis(long, ["Tester", "Lot"], cfg, bases=("raw",))
    by_tp = {r["tp"]: r for r in series}
    ok = True

    def check(name, cond):
        nonlocal ok
        print(f"{'PASS' if cond else 'FAIL'}  {name}")
        ok &= cond
    a, b, c, d = (by_tp[k] for k in ("A_global15", "B_global5", "C_none", "D_t3_30"))
    cp_week = datetime.fromtimestamp(a["cp"]["split_ms"] / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    check(f"15 mV global step flagged by change point near week 5 (split {cp_week})", a["cp"]["flag"] and "2026-10-0" in cp_week)
    check("15 mV step flagged week-to-week", any(t["flag"] for t in a["tests"] if t["kind"] == "consecutive"))
    check("5 mV global step NOT flagged", not b["cp"]["flag"] and not any(t["flag"] for t in b["tests"]))
    check("no-shift series NOT flagged", not c["cp"]["flag"] and not any(t["flag"] for t in c["tests"]))
    t3 = [h for h in d["hw"] if h["factor"] == "Tester" and h["level"] == "T3"][0]
    check(f"T3-only shift attributed to T3 (resid {t3['resid_mv']:+.1f} mV)", t3["flag"] and t3["resid_mv"] > 0)

    # UPM normalization: silicon speed (UPM) drives most of the Vmin spread; a 10 mV shift on tester T2 only.
    rows = []
    for w in range(8):
        for lot in range(5):
            t = start + pd.Timedelta(days=7 * w + lot, hours=3)
            for _ in range(30):
                tester = testers[int(rng.integers(0, 4))]
                upm = rng.normal(100, 10)
                v = 700 - 4.0 * (upm - 100) + rng.normal(0, 4)
                if w >= 4 and tester == "T2":
                    v += 10
                rows.append(("E_upm", "tok", "U1PU2", 3.6, f"E{len(rows)}", f"L{w}{lot}", "P1", t, v, upm, tester))
    le = pd.DataFrame(rows, columns=["tp", "token", "domain", "freq", "vid", "Lot", "Program", "t", "mv", "upm", "Tester"])
    le = add_time_cols(le)
    fits = normalize_to_upm(le)
    ser, _ = run_analysis(le, ["Tester", "Lot"], cfg, bases=("raw", "upm"))
    raw_e = next(s for s in ser if s["basis"] == "raw")
    upm_e = next(s for s in ser if s["basis"] == "upm")
    t2r = [h for h in raw_e["hw"] if h["factor"] == "Tester" and h["level"] == "T2"][0]
    t2u = [h for h in upm_e["hw"] if h["factor"] == "Tester" and h["level"] == "T2"][0]
    check(f"UPM fit slope recovered ({fits[('E_upm', 'tok')]['slope']:.2f} vs -4, r2 {fits[('E_upm', 'tok')]['r2']:.2f})",
          abs(fits[("E_upm", "tok")]["slope"] + 4.0) < 0.5)
    check(f"T2 10 mV step missed on raw (step q {t2r['step_q']:.3g}) but flagged after UPM normalization (step q {t2u['step_q']:.3g}, {t2u['step_mv']:+.1f} mV)",
          (not t2r["step_flag"]) and t2u["step_q"] < 0.05 and 7.0 <= t2u["step_mv"] <= 13.0)
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    ap.add_argument("--output-dir", default=DEFAULT_OUT_DIR)
    ap.add_argument("--hw-csv", default=None, help="HW attribute CSV from pull_nvlax_hw_attributes.py (default: latest in output dir)")
    ap.add_argument("--extra-hw-csv", default=None, help="Optional TRACE export keyed by VISUAL_ID (Cell, Personality Card, TIU, ...)")
    ap.add_argument("--min-n", type=int, default=15, help="min units per week / per series half")
    ap.add_argument("--hw-min-n", type=int, default=10, help="min units per HW level")
    ap.add_argument("--hw-step-min", type=int, default=8, help="min units on each side of a per-HW-level step")
    ap.add_argument("--hw-perm", type=int, default=300, help="permutations for per-HW-level step test")
    ap.add_argument("--alarm-offset", type=float, default=None, help="Optional: draw a Vmin/FEM alarm line = baseline + this (x1000 units). Off by default.")
    ap.add_argument("--alpha", type=float, default=0.05)
    ap.add_argument("--min-shift-mv", type=float, default=10.0)
    ap.add_argument("--n-perm", type=int, default=1000)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    cfg = {"min_n": args.min_n, "n_perm": args.n_perm, "hw_min_n": args.hw_min_n, "hw_step_min": args.hw_step_min,
           "hw_perm": args.hw_perm, "alpha": args.alpha, "min_shift_mv": args.min_shift_mv, "alarm_offset": args.alarm_offset}
    os.makedirs(args.output_dir, exist_ok=True)
    long, quality = load_long(args.data_dir)
    long, factors, hw_note = join_hw(long, args.hw_csv, args.extra_hw_csv, args.output_dir)
    long = add_time_cols(long)
    fits = normalize_to_upm(long)
    print(f"{len(long)} unit-token rows, {long.groupby(['tp', 'token']).ngroups} series, HW source: {hw_note}, UPM-normalized series: {len(fits)}")
    series, skipped = run_analysis(long, factors, cfg)
    payload = build_payload(series, skipped, quality, factors, hw_note, cfg, long, fits)
    write_csvs(payload, args.output_dir)
    out_html = os.path.join(args.output_dir, f"NVLAX_SAAT_Vmin_shift_{datetime.now():%Y%m%d}.html")
    render_html(payload, out_html)
    print(f"{payload['meta']['n_flags']} flagged shifts in {payload['meta']['n_series']} analysed series -> {out_html}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
