import csv
import math
import os
from collections import Counter, defaultdict

INPUT_CSV = r"R:\Products\PTL\PTLP12Xe\Analysis\2026_31_PTLP_DRACO_process analysis.csv"
OUT_DIR = os.path.join(os.path.dirname(__file__), "output", "focused_bin_model_gt100")
os.makedirs(OUT_DIR, exist_ok=True)

GROUP_COL_CANDIDATES = ["group_type", "Group Type", "Group", "DLCP_Group"]
BIN_COL = "FUNCTIONAL_BIN_CLASSHOT"

DRACO_GT3K = "DRACO>3K"
POR_GT3K = "POR>3K"


class RunningStats:
    __slots__ = ("n", "sum", "sumsq")

    def __init__(self):
        self.n = 0
        self.sum = 0.0
        self.sumsq = 0.0

    def add(self, x):
        self.n += 1
        self.sum += x
        self.sumsq += x * x

    def mean(self):
        return self.sum / self.n if self.n else float("nan")

    def var_sample(self):
        if self.n < 2:
            return float("nan")
        num = self.sumsq - (self.sum * self.sum) / self.n
        return max(0.0, num / (self.n - 1))


def to_float(v):
    if v is None:
        return None
    s = str(v).strip()
    if s == "":
        return None
    s = s.replace(",", "")
    try:
        return float(s)
    except ValueError:
        return None


def parse_functional_bin(v):
    x = to_float(v)
    if x is None:
        return None
    return int(round(x))


def canonical_group(v):
    raw = (v or "").strip()
    s = raw.lower().replace("_", "").replace(" ", "")

    if "draco" in s and ">3k" in s:
        return "DRACO>3K"
    if "draco" in s and "<3k" in s:
        return "DRACO<3K"
    if "por" in s and ">3k" in s:
        return "POR>3K"
    if "por" in s and "<3k" in s:
        return "POR<3K"

    return raw if raw else "<UNKNOWN>"


def is_requested_feature(col):
    return (
        col in {"SORT_LOT_U1", "SORT_X_U1", "SORT_Y_U1"}
        or col.startswith("VA-IN-NA-GSDS_D_S::UPSVFPASSFLOW_CLASSHOT_")
        or col.startswith("VA-IN-NA-GSDS_D_S::SICC_CLASSHOT_")
    )


def cohen_d(sa, sb):
    if sa.n < 2 or sb.n < 2:
        return float("nan")

    ma = sa.mean()
    mb = sb.mean()
    va = sa.var_sample()
    vb = sb.var_sample()

    denom = sa.n + sb.n - 2
    if denom <= 0:
        return float("nan")

    pooled_var = ((sa.n - 1) * va + (sb.n - 1) * vb) / denom
    if pooled_var <= 0:
        return 0.0

    return (ma - mb) / math.sqrt(pooled_var)


def point_biserial(sa, sb):
    n1 = sa.n
    n0 = sb.n
    n = n1 + n0
    if n1 < 2 or n0 < 2:
        return float("nan")

    m1 = sa.mean()
    m0 = sb.mean()

    sum_all = sa.sum + sb.sum
    sumsq_all = sa.sumsq + sb.sumsq
    ss = sumsq_all - (sum_all * sum_all) / n
    if n < 2 or ss <= 0:
        return 0.0

    s = math.sqrt(ss / (n - 1))
    if s == 0:
        return 0.0

    return ((m1 - m0) / s) * math.sqrt((n1 * n0) / (n * n))


with open(INPUT_CSV, "r", newline="", encoding="utf-8-sig") as f:
    reader = csv.reader(f)
    headers = next(reader)
    col_to_idx = {name: idx for idx, name in enumerate(headers)}

    group_col = next((c for c in GROUP_COL_CANDIDATES if c in col_to_idx), None)
    missing = []
    if group_col is None:
        missing.append("group_type/Group Type")
    if BIN_COL not in col_to_idx:
        missing.append(BIN_COL)
    if missing:
        raise RuntimeError("Missing required columns: " + ", ".join(missing))

    group_idx = col_to_idx[group_col]
    bin_idx = col_to_idx[BIN_COL]

    feature_cols = [c for c in headers if is_requested_feature(c)]
    feature_idxs = [(c, col_to_idx[c]) for c in feature_cols]

    group_total = Counter()
    group_bin100 = Counter()
    group_bingt100 = Counter()
    group_gt100_bins = defaultdict(Counter)

    global_gt100_bins = Counter()

    draco_gt100_bins = Counter()
    por_gt100_bins = Counter()

    feat_non100 = {c: RunningStats() for c in feature_cols}
    feat_100 = {c: RunningStats() for c in feature_cols}

    feat_draco_gt100 = {c: RunningStats() for c in feature_cols}
    feat_por_gt100 = {c: RunningStats() for c in feature_cols}

    total_rows = 0
    used_rows = 0

    for row in reader:
        total_rows += 1
        if total_rows % 20000 == 0:
            print(f"Processed rows: {total_rows}", flush=True)

        if group_idx >= len(row) or bin_idx >= len(row):
            continue

        g = canonical_group(row[group_idx])
        b = parse_functional_bin(row[bin_idx])
        if b is None:
            continue

        used_rows += 1
        group_total[g] += 1

        if b == 100:
            group_bin100[g] += 1
        elif b > 100:
            group_bingt100[g] += 1
            group_gt100_bins[g][b] += 1
            global_gt100_bins[b] += 1

            if g == DRACO_GT3K:
                draco_gt100_bins[b] += 1
            elif g == POR_GT3K:
                por_gt100_bins[b] += 1

        else:
            continue

        for col, idx in feature_idxs:
            if idx >= len(row):
                continue
            v = to_float(row[idx])
            if v is None:
                continue

            if b > 100:
                feat_non100[col].add(v)
                if g == DRACO_GT3K:
                    feat_draco_gt100[col].add(v)
                elif g == POR_GT3K:
                    feat_por_gt100[col].add(v)
            elif b == 100:
                feat_100[col].add(v)

# 1) Group-level abundance summary.
abundance_rows = []
for g in sorted(group_total.keys()):
    t = group_total[g]
    c100 = group_bin100[g]
    cgt = group_bingt100[g]
    abundance_rows.append(
        {
            "group_type": g,
            "total_with_numeric_bin": t,
            "functional_bin_100_count": c100,
            "functional_bin_gt100_count": cgt,
            "functional_bin_100_pct": (c100 / t) if t else float("nan"),
            "functional_bin_gt100_pct": (cgt / t) if t else float("nan"),
            "gt100_to_100_ratio": (cgt / c100) if c100 else float("nan"),
            "unique_gt100_bins": len(group_gt100_bins[g]),
        }
    )

# 2) Top gt100 bins per group.
global_gt100_total = sum(global_gt100_bins.values())
top_bins_rows = []
for g in sorted(group_gt100_bins.keys()):
    g_total = group_bingt100[g]
    if g_total == 0:
        continue
    for b, c in group_gt100_bins[g].most_common(25):
        p_group = c / g_total
        p_global = (global_gt100_bins[b] / global_gt100_total) if global_gt100_total else float("nan")
        lift = (p_group / p_global) if p_global and not math.isnan(p_global) else float("nan")
        top_bins_rows.append(
            {
                "group_type": g,
                "functional_bin": b,
                "count": c,
                "pct_within_group_gt100": p_group,
                "global_gt100_pct": p_global,
                "lift_vs_global": lift,
            }
        )

# 3) Bin-identity differences DRACO>3K vs POR>3K among gt100.
d_total = sum(draco_gt100_bins.values())
p_total = sum(por_gt100_bins.values())
all_bins = set(draco_gt100_bins.keys()) | set(por_gt100_bins.keys())

bin_diff_rows = []
bin_diff_shared_rows = []
bin_diff_exclusive_rows = []
eps = 1e-12
for b in sorted(all_bins):
    cd = draco_gt100_bins[b]
    cp = por_gt100_bins[b]

    pd = (cd / d_total) if d_total else 0.0
    pp = (cp / p_total) if p_total else 0.0

    log2_lift = math.log((pd + eps) / (pp + eps), 2)

    a = cd
    b_not = max(0, d_total - cd)
    c = cp
    d_not = max(0, p_total - cp)
    odds_ratio = ((a + 0.5) * (d_not + 0.5)) / ((b_not + 0.5) * (c + 0.5))

    bin_diff_rows.append(
        {
            "functional_bin": b,
            "draco_gt100_count": cd,
            "por_gt100_count": cp,
            "draco_gt100_pct": pd,
            "por_gt100_pct": pp,
            "log2_lift_draco_over_por": log2_lift,
            "odds_ratio_draco_over_por": odds_ratio,
            "abs_log2_lift": abs(log2_lift),
        }
    )

    total_bin = cd + cp
    if cd > 0 and cp > 0 and total_bin >= 15:
        bin_diff_shared_rows.append(
            {
                "functional_bin": b,
                "draco_gt100_count": cd,
                "por_gt100_count": cp,
                "draco_gt100_pct": pd,
                "por_gt100_pct": pp,
                "log2_lift_draco_over_por": log2_lift,
                "odds_ratio_draco_over_por": odds_ratio,
                "abs_log2_lift": abs(log2_lift),
            }
        )

    if (cd == 0) ^ (cp == 0):
        present_count = cd if cd > 0 else cp
        if present_count >= 20:
            bin_diff_exclusive_rows.append(
                {
                    "functional_bin": b,
                    "present_in": DRACO_GT3K if cd > 0 else POR_GT3K,
                    "present_count": present_count,
                    "draco_gt100_count": cd,
                    "por_gt100_count": cp,
                }
            )

bin_diff_rows.sort(key=lambda r: (r["abs_log2_lift"], r["draco_gt100_count"] + r["por_gt100_count"]), reverse=True)
bin_diff_shared_rows.sort(key=lambda r: r["abs_log2_lift"], reverse=True)
bin_diff_exclusive_rows.sort(key=lambda r: r["present_count"], reverse=True)

# 4) Feature influence for gt100 vs 100.
feature_bin_rows = []
for col in feature_cols:
    sn = feat_non100[col]
    s1 = feat_100[col]
    if sn.n < 100 or s1.n < 100:
        continue
    d = cohen_d(sn, s1)
    rpb = point_biserial(sn, s1)
    feature_bin_rows.append(
        {
            "feature": col,
            "n_gt100": sn.n,
            "n_100": s1.n,
            "mean_gt100": sn.mean(),
            "mean_100": s1.mean(),
            "mean_delta_gt100_minus_100": sn.mean() - s1.mean(),
            "cohen_d": d,
            "abs_cohen_d": abs(d) if not math.isnan(d) else float("nan"),
            "point_biserial_gt100_vs_100": rpb,
            "abs_point_biserial_gt100_vs_100": abs(rpb) if not math.isnan(rpb) else float("nan"),
        }
    )

feature_bin_rows.sort(key=lambda r: (r["abs_point_biserial_gt100_vs_100"], r["abs_cohen_d"]), reverse=True)

# 5) Feature influence for group differentiation within gt100 (DRACO>3K vs POR>3K).
feature_group_rows = []
for col in feature_cols:
    sd = feat_draco_gt100[col]
    sp = feat_por_gt100[col]
    # Keep sparse-but-real slices because some high-signal bins have limited DRACO coverage.
    if sd.n < 8 or sp.n < 100:
        continue
    d = cohen_d(sd, sp)
    rpb = point_biserial(sd, sp)
    feature_group_rows.append(
        {
            "feature": col,
            "n_draco_gt100": sd.n,
            "n_por_gt100": sp.n,
            "mean_draco_gt100": sd.mean(),
            "mean_por_gt100": sp.mean(),
            "mean_delta_draco_minus_por": sd.mean() - sp.mean(),
            "cohen_d": d,
            "abs_cohen_d": abs(d) if not math.isnan(d) else float("nan"),
            "point_biserial_draco_vs_por_in_gt100": rpb,
            "abs_point_biserial_draco_vs_por_in_gt100": abs(rpb) if not math.isnan(rpb) else float("nan"),
        }
    )

feature_group_rows.sort(key=lambda r: (r["abs_point_biserial_draco_vs_por_in_gt100"], r["abs_cohen_d"]), reverse=True)

# Write outputs.
abundance_csv = os.path.join(OUT_DIR, "bin_abundance_by_group.csv")
top_bins_csv = os.path.join(OUT_DIR, "top_gt100_bins_by_group.csv")
bin_diff_csv = os.path.join(OUT_DIR, "gt100_bin_identity_diff_draco_vs_por.csv")
bin_diff_shared_csv = os.path.join(OUT_DIR, "gt100_bin_identity_diff_draco_vs_por_shared.csv")
bin_diff_exclusive_csv = os.path.join(OUT_DIR, "gt100_bin_identity_exclusive_draco_vs_por.csv")
feature_bin_csv = os.path.join(OUT_DIR, "feature_influence_gt100_vs_100.csv")
feature_group_csv = os.path.join(OUT_DIR, "feature_influence_grouptype_within_gt100.csv")
summary_txt = os.path.join(OUT_DIR, "focused_model_summary.txt")

with open(abundance_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "group_type",
            "total_with_numeric_bin",
            "functional_bin_100_count",
            "functional_bin_gt100_count",
            "functional_bin_100_pct",
            "functional_bin_gt100_pct",
            "gt100_to_100_ratio",
            "unique_gt100_bins",
        ],
    )
    w.writeheader()
    w.writerows(abundance_rows)

with open(top_bins_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "group_type",
            "functional_bin",
            "count",
            "pct_within_group_gt100",
            "global_gt100_pct",
            "lift_vs_global",
        ],
    )
    w.writeheader()
    w.writerows(top_bins_rows)

with open(bin_diff_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "functional_bin",
            "draco_gt100_count",
            "por_gt100_count",
            "draco_gt100_pct",
            "por_gt100_pct",
            "log2_lift_draco_over_por",
            "odds_ratio_draco_over_por",
            "abs_log2_lift",
        ],
    )
    w.writeheader()
    w.writerows(bin_diff_rows)

with open(bin_diff_shared_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "functional_bin",
            "draco_gt100_count",
            "por_gt100_count",
            "draco_gt100_pct",
            "por_gt100_pct",
            "log2_lift_draco_over_por",
            "odds_ratio_draco_over_por",
            "abs_log2_lift",
        ],
    )
    w.writeheader()
    w.writerows(bin_diff_shared_rows)

with open(bin_diff_exclusive_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "functional_bin",
            "present_in",
            "present_count",
            "draco_gt100_count",
            "por_gt100_count",
        ],
    )
    w.writeheader()
    w.writerows(bin_diff_exclusive_rows)

with open(feature_bin_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "feature",
            "n_gt100",
            "n_100",
            "mean_gt100",
            "mean_100",
            "mean_delta_gt100_minus_100",
            "cohen_d",
            "abs_cohen_d",
            "point_biserial_gt100_vs_100",
            "abs_point_biserial_gt100_vs_100",
        ],
    )
    w.writeheader()
    w.writerows(feature_bin_rows)

with open(feature_group_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "feature",
            "n_draco_gt100",
            "n_por_gt100",
            "mean_draco_gt100",
            "mean_por_gt100",
            "mean_delta_draco_minus_por",
            "cohen_d",
            "abs_cohen_d",
            "point_biserial_draco_vs_por_in_gt100",
            "abs_point_biserial_draco_vs_por_in_gt100",
        ],
    )
    w.writeheader()
    w.writerows(feature_group_rows)

with open(summary_txt, "w", encoding="utf-8") as f:
    f.write(f"Input CSV: {INPUT_CSV}\n")
    f.write(f"Total rows scanned: {total_rows}\n")
    f.write(f"Rows used with numeric FUNCTIONAL_BIN_CLASSHOT: {used_rows}\n")
    f.write(f"Detected group column: {group_col}\n")
    f.write(f"Features analyzed: {len(feature_cols)}\n\n")

    f.write("Group abundance snapshot (bin=100 vs bin>100):\n")
    for r in sorted(abundance_rows, key=lambda x: x["total_with_numeric_bin"], reverse=True):
        f.write(
            "  {g}: total={t}, bin100={b100} ({p100:.4%}), bin>100={bg} ({pg:.4%}), ratio={rt:.4f}, unique_gt100_bins={u}\n".format(
                g=r["group_type"],
                t=r["total_with_numeric_bin"],
                b100=r["functional_bin_100_count"],
                p100=r["functional_bin_100_pct"],
                bg=r["functional_bin_gt100_count"],
                pg=r["functional_bin_gt100_pct"],
                rt=r["gt100_to_100_ratio"],
                u=r["unique_gt100_bins"],
            )
        )

    f.write("\nTop 20 shared gt100 bin identity differences (DRACO>3K vs POR>3K):\n")
    shown = 0
    for r in bin_diff_shared_rows:
        f.write(
            "  bin={b}, draco={cd} ({pd:.4%}), por={cp} ({pp:.4%}), log2_lift={lf:.3f}, OR={orv:.3f}\n".format(
                b=r["functional_bin"],
                cd=r["draco_gt100_count"],
                pd=r["draco_gt100_pct"],
                cp=r["por_gt100_count"],
                pp=r["por_gt100_pct"],
                lf=r["log2_lift_draco_over_por"],
                orv=r["odds_ratio_draco_over_por"],
            )
        )
        shown += 1
        if shown >= 20:
            break

    f.write("\nTop 15 exclusive gt100 bins (present in only one group):\n")
    for r in bin_diff_exclusive_rows[:15]:
        f.write(
            "  bin={b}, present_in={pin}, present_count={pc}, draco={cd}, por={cp}\n".format(
                b=r["functional_bin"],
                pin=r["present_in"],
                pc=r["present_count"],
                cd=r["draco_gt100_count"],
                cp=r["por_gt100_count"],
            )
        )

    f.write("\nTop 20 feature influencers for gt100 vs 100:\n")
    for r in feature_bin_rows[:20]:
        f.write(
            "  {ftr}: r_pb={rpb:.4f}, d={d:.4f}, mean_gt100={mg:.4f}, mean_100={m1:.4f}, n=({ng},{n1})\n".format(
                ftr=r["feature"],
                rpb=r["point_biserial_gt100_vs_100"],
                d=r["cohen_d"],
                mg=r["mean_gt100"],
                m1=r["mean_100"],
                ng=r["n_gt100"],
                n1=r["n_100"],
            )
        )

    f.write("\nTop 20 feature influencers for DRACO>3K vs POR>3K within gt100:\n")
    for r in feature_group_rows[:20]:
        f.write(
            "  {ftr}: r_pb={rpb:.4f}, d={d:.4f}, mean_draco={md:.4f}, mean_por={mp:.4f}, n=({nd},{np})\n".format(
                ftr=r["feature"],
                rpb=r["point_biserial_draco_vs_por_in_gt100"],
                d=r["cohen_d"],
                md=r["mean_draco_gt100"],
                mp=r["mean_por_gt100"],
                nd=r["n_draco_gt100"],
                np=r["n_por_gt100"],
            )
        )

print("DONE", flush=True)
print(f"summary: {summary_txt}", flush=True)
print(f"abundance: {abundance_csv}", flush=True)
print(f"top_bins: {top_bins_csv}", flush=True)
print(f"bin_diff: {bin_diff_csv}", flush=True)
print(f"bin_diff_shared: {bin_diff_shared_csv}", flush=True)
print(f"bin_diff_exclusive: {bin_diff_exclusive_csv}", flush=True)
print(f"feature_bin: {feature_bin_csv}", flush=True)
print(f"feature_group: {feature_group_csv}", flush=True)
