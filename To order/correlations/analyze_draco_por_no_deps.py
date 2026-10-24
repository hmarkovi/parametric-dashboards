import csv
import math
import os
from collections import Counter, defaultdict

INPUT_CSV = r"R:\Products\PTL\PTLP12Xe\Analysis\2026_31_PTLP_DRACO_process analysis.csv"
OUT_DIR = os.path.join(os.path.dirname(__file__), "output", "draco_vs_por_3k")
os.makedirs(OUT_DIR, exist_ok=True)

GROUP_COL_CANDIDATES = ["group_type", "Group Type", "Group", "DLCP_Group"]
BIN_COL = "FUNCTIONAL_BIN_CLASSHOT"
GROUP_A_LABEL = "DRACO>3K"
GROUP_B_LABEL = "POR>3K"


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

    def std_sample(self):
        v = self.var_sample()
        return math.sqrt(v) if not math.isnan(v) else float("nan")


def normalize_group_label(v):
    s = (v or "").strip().lower().replace("_", "").replace(" ", "")
    if "draco" in s and ">3k" in s:
        return GROUP_A_LABEL
    if "por" in s and ">3k" in s:
        return GROUP_B_LABEL
    return None


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


def cohen_d(sa, sb):
    if sa.n < 2 or sb.n < 2:
        return float("nan")
    ma, mb = sa.mean(), sb.mean()
    va, vb = sa.var_sample(), sb.var_sample()
    denom = sa.n + sb.n - 2
    if denom <= 0:
        return float("nan")
    pooled_var = ((sa.n - 1) * va + (sb.n - 1) * vb) / denom
    if pooled_var <= 0:
        return 0.0
    return (ma - mb) / math.sqrt(pooled_var)


def point_biserial(sa, sb):
    n1, n0 = sa.n, sb.n
    n = n1 + n0
    if n1 < 2 or n0 < 2:
        return float("nan")

    m1, m0 = sa.mean(), sb.mean()
    sum_all = sa.sum + sb.sum
    sumsq_all = sa.sumsq + sb.sumsq
    num = sumsq_all - (sum_all * sum_all) / n
    if n < 2 or num <= 0:
        return 0.0
    s = math.sqrt(num / (n - 1))
    if s == 0:
        return 0.0

    return ((m1 - m0) / s) * math.sqrt((n1 * n0) / (n * n))


def eta_squared(overall_stats, per_bin_stats):
    if overall_stats.n < 3 or len(per_bin_stats) < 2:
        return float("nan")

    grand_mean = overall_stats.mean()
    ss_total = overall_stats.sumsq - (overall_stats.sum * overall_stats.sum) / overall_stats.n
    if ss_total <= 0:
        return 0.0

    ss_between = 0.0
    for st in per_bin_stats.values():
        if st.n == 0:
            continue
        m = st.mean()
        ss_between += st.n * (m - grand_mean) ** 2

    return ss_between / ss_total


def is_requested_feature(col):
    return (
        col in {"SORT_LOT_U1", "SORT_X_U1", "SORT_Y_U1"}
        or col.startswith("VA-IN-NA-GSDS_D_S::UPSVFPASSFLOW_CLASSHOT_")
        or col.startswith("VA-IN-NA-GSDS_D_S::SICC_CLASSHOT_")
    )


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

    group_counts = Counter()
    bin_counts_by_group = defaultdict(Counter)

    grp_a_stats = {c: RunningStats() for c in feature_cols}
    grp_b_stats = {c: RunningStats() for c in feature_cols}

    overall_feature_stats = {c: RunningStats() for c in feature_cols}
    per_bin_feature_stats = {c: defaultdict(RunningStats) for c in feature_cols}

    total_rows = 0
    used_rows = 0

    for row in reader:
        total_rows += 1
        if total_rows % 20000 == 0:
            print(f"Processed rows: {total_rows}", flush=True)

        if group_idx >= len(row):
            continue

        g = normalize_group_label(row[group_idx])
        if g not in (GROUP_A_LABEL, GROUP_B_LABEL):
            continue

        used_rows += 1
        group_counts[g] += 1

        b = "<EMPTY>"
        if bin_idx < len(row):
            b_raw = (row[bin_idx] or "").strip()
            b = b_raw if b_raw else "<EMPTY>"
        bin_counts_by_group[g][b] += 1

        for col, idx in feature_idxs:
            if idx >= len(row):
                continue

            v = to_float(row[idx])
            if v is None:
                continue

            if g == GROUP_A_LABEL:
                grp_a_stats[col].add(v)
            else:
                grp_b_stats[col].add(v)

            overall_feature_stats[col].add(v)
            per_bin_feature_stats[col][b].add(v)

sep_rows = []
for col in feature_cols:
    sa = grp_a_stats[col]
    sb = grp_b_stats[col]
    if sa.n < 3 or sb.n < 3:
        continue
    ma = sa.mean()
    mb = sb.mean()
    d = cohen_d(sa, sb)
    rpb = point_biserial(sa, sb)
    sep_rows.append(
        {
            "feature": col,
            "n_draco": sa.n,
            "n_por": sb.n,
            "mean_draco": ma,
            "mean_por": mb,
            "mean_delta_draco_minus_por": ma - mb,
            "cohen_d": d,
            "abs_cohen_d": abs(d) if not math.isnan(d) else float("nan"),
            "point_biserial_group": rpb,
            "abs_point_biserial_group": abs(rpb) if not math.isnan(rpb) else float("nan"),
        }
    )

sep_rows.sort(key=lambda x: (x["abs_point_biserial_group"], x["abs_cohen_d"]), reverse=True)

bin_rows = []
for col in feature_cols:
    st = overall_feature_stats[col]
    if st.n < 10:
        continue
    e2 = eta_squared(st, per_bin_feature_stats[col])
    if math.isnan(e2):
        continue
    bin_rows.append(
        {
            "feature": col,
            "n_total": st.n,
            "eta_squared_vs_functional_bin": e2,
        }
    )

bin_rows.sort(key=lambda x: x["eta_squared_vs_functional_bin"], reverse=True)

sep_csv = os.path.join(OUT_DIR, "draco_vs_por_feature_separation.csv")
bin_csv = os.path.join(OUT_DIR, "feature_vs_functional_bin_eta2.csv")
summary_txt = os.path.join(OUT_DIR, "summary.txt")

with open(sep_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "feature",
            "n_draco",
            "n_por",
            "mean_draco",
            "mean_por",
            "mean_delta_draco_minus_por",
            "cohen_d",
            "abs_cohen_d",
            "point_biserial_group",
            "abs_point_biserial_group",
        ],
    )
    w.writeheader()
    w.writerows(sep_rows)

with open(bin_csv, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=["feature", "n_total", "eta_squared_vs_functional_bin"],
    )
    w.writeheader()
    w.writerows(bin_rows)

with open(summary_txt, "w", encoding="utf-8") as f:
    f.write(f"Input CSV: {INPUT_CSV}\n")
    f.write(f"Total rows scanned: {total_rows}\n")
    f.write(f"Rows used (group_type in [{GROUP_A_LABEL}, {GROUP_B_LABEL}]): {used_rows}\n")
    f.write(f"Features analyzed: {len(feature_cols)}\n")
    f.write(f"Detected group column: {group_col}\n\n")

    f.write("Group counts:\n")
    for g in (GROUP_A_LABEL, GROUP_B_LABEL):
        f.write(f"  {g}: {group_counts[g]}\n")

    f.write("\nTop functional bins per group:\n")
    for g in (GROUP_A_LABEL, GROUP_B_LABEL):
        f.write(f"  {g}:\n")
        for b, c in bin_counts_by_group[g].most_common(10):
            f.write(f"    {b}: {c}\n")

    f.write("\nTop 25 DRACO vs POR differentiating features (abs point-biserial):\n")
    for row in sep_rows[:25]:
        f.write(
            "  {feature} | r_pb={rpb:.4f} | d={d:.4f} | "
            "mean_draco={md:.4f} | mean_por={mp:.4f} | n=({nd},{np})\n".format(
                feature=row["feature"],
                rpb=row["point_biserial_group"],
                d=row["cohen_d"],
                md=row["mean_draco"],
                mp=row["mean_por"],
                nd=row["n_draco"],
                np=row["n_por"],
            )
        )

    f.write("\nTop 25 features linked to FUNCTIONAL_BIN_CLASSHOT (eta^2):\n")
    for row in bin_rows[:25]:
        f.write(
            "  {feature} | eta2={eta2:.4f} | n={n}\n".format(
                feature=row["feature"],
                eta2=row["eta_squared_vs_functional_bin"],
                n=row["n_total"],
            )
        )

print("DONE", flush=True)
print(f"summary: {summary_txt}", flush=True)
print(f"sep_csv: {sep_csv}", flush=True)
print(f"bin_csv: {bin_csv}", flush=True)
