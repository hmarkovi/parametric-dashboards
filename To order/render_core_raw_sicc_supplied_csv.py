from __future__ import annotations

import argparse
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.ticker import FixedLocator, FuncFormatter


PRODUCT_COLUMN = "Prod"
VISUAL_ID_COLUMN = "VISUAL_ID"
TIMESTAMP_COLUMN = "LOTS End Date Time_classhot"
SICC_COLUMN = "SICC-U1PU5_IA00-V1_value"
UPM_COLUMN = "UPM FEM CDIE"
PROCESS_TARGET = 0.95
PRESI_TARGET = 2.5

PRODUCT_COLORS = {
    "NVLAX": "#e84a5f",
    "NVLHX": "#2ca02c",
    "NVLS7": "#3b6eea",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render the Core raw SICC plot from the supplied 2026_43 CSV.")
    parser.add_argument(
        "--input-csv",
        default=r"R:\Products\NVL\NVL-AX\Analysis\2026_43_Cross product_SICC_analysis.csv",
        help="User-supplied cross-product CSV.",
    )
    parser.add_argument(
        "--output-png",
        default=r"R:\Products\NVL\NVL-AX\Weekly data pull\core_raw_sicc_supplied_csv.png",
        help="Output PNG path.",
    )
    return parser.parse_args()


def fit_log_linear(frame: pd.DataFrame) -> dict[str, float] | None:
    x = frame["upm_value"].to_numpy(dtype=float)
    y = frame["sicc_value"].to_numpy(dtype=float)
    mask = np.isfinite(x) & np.isfinite(y) & (x > 0.0) & (y > 0.0)
    if int(mask.sum()) < 3:
        return None
    x = x[mask]
    y = y[mask]
    design = np.column_stack([np.ones(x.shape[0]), x])
    coefficients, _, _, _ = np.linalg.lstsq(design, np.log(y), rcond=None)
    intercept = float(coefficients[0])
    slope = float(coefficients[1])
    predicted_log = design @ coefficients
    ss_res = float(np.sum((np.log(y) - predicted_log) ** 2))
    ss_tot = float(np.sum((np.log(y) - float(np.mean(np.log(y)))) ** 2))
    r2 = 1.0 if ss_tot <= 1e-12 else 1.0 - (ss_res / ss_tot)
    postsi_value = float(math.exp(intercept + (slope * PROCESS_TARGET)))
    return {
        "intercept_log": intercept,
        "slope_linear": slope,
        "postsi_value": postsi_value,
        "x_min": float(np.min(x)),
        "x_max": float(np.max(x)),
        "r2": r2,
        "count": int(x.shape[0]),
    }


def load_latest_rows(input_csv: Path) -> pd.DataFrame:
    frame = pd.read_csv(
        input_csv,
        low_memory=False,
        usecols=[PRODUCT_COLUMN, VISUAL_ID_COLUMN, TIMESTAMP_COLUMN, SICC_COLUMN, UPM_COLUMN],
    )
    frame[TIMESTAMP_COLUMN] = pd.to_datetime(frame[TIMESTAMP_COLUMN], errors="coerce", utc=True).dt.tz_convert("UTC").dt.tz_localize(None)
    frame[VISUAL_ID_COLUMN] = frame[VISUAL_ID_COLUMN].astype(str).str.strip()
    frame = frame[frame[VISUAL_ID_COLUMN] != ""]
    frame = frame.sort_values([VISUAL_ID_COLUMN, TIMESTAMP_COLUMN], ascending=[True, False], na_position="last")
    frame = frame.drop_duplicates(subset=[VISUAL_ID_COLUMN], keep="first")
    return frame


def main() -> int:
    args = parse_args()
    input_csv = Path(args.input_csv)
    output_png = Path(args.output_png)

    frame = load_latest_rows(input_csv)
    frame = frame.rename(columns={PRODUCT_COLUMN: "product", SICC_COLUMN: "sicc_value", UPM_COLUMN: "upm_value"})
    frame["product"] = frame["product"].astype(str).str.strip().str.upper()
    frame["sicc_value"] = pd.to_numeric(frame["sicc_value"], errors="coerce")
    frame["upm_value"] = pd.to_numeric(frame["upm_value"], errors="coerce")
    frame = frame.dropna(subset=["product", "sicc_value", "upm_value"])
    frame = frame[(frame["sicc_value"] > 0.0) & (frame["upm_value"] > 0.0)]
    frame = frame[frame["product"].isin(PRODUCT_COLORS.keys())]

    fig, ax = plt.subplots(figsize=(11.1, 8.4), constrained_layout=True)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("#fbfbfa")
    ax.grid(True, which="major", axis="both", color="#cfcfcf", linewidth=0.6, alpha=0.8)
    ax.minorticks_on()
    ax.grid(True, which="minor", axis="x", color="#e7e7e7", linewidth=0.45, alpha=0.9)
    ax.set_axisbelow(True)

    plot_x_min = max(0.87, float(frame["upm_value"].min()) - 0.005)
    plot_x_max = min(1.0, float(frame["upm_value"].max()) + 0.005)
    line_x = np.linspace(plot_x_min, plot_x_max, 400)
    fit_annotations: list[tuple[str, float, str]] = []

    for product in ["NVLAX", "NVLHX", "NVLS7"]:
        product_frame = frame[frame["product"] == product].copy()
        if product_frame.empty:
            continue
        color = PRODUCT_COLORS[product]
        ax.scatter(
            product_frame["upm_value"],
            product_frame["sicc_value"],
            s=8,
            marker="s",
            color=color,
            alpha=0.28,
            linewidths=0.0,
            label=product,
        )
        fit = fit_log_linear(product_frame)
        if fit is None:
            continue
        curve_y = np.exp(fit["intercept_log"] + (fit["slope_linear"] * line_x))
        ax.plot(line_x, curve_y, color=color, linewidth=1.8)
        ax.axhline(fit["postsi_value"], color=color, linewidth=0.8, alpha=0.9)
        fit_annotations.append((product, fit["postsi_value"], color))

    ax.axvline(PROCESS_TARGET, color="#404040", linestyle="--", linewidth=1.6)
    ax.text(PROCESS_TARGET, 1.02, "Process target=0.95", transform=ax.get_xaxis_transform(), ha="center", va="bottom", fontsize=14)
    ax.axhline(PRESI_TARGET, color="#505050", linewidth=1.0, alpha=0.85)
    ax.text(plot_x_min + 0.012, PRESI_TARGET + 0.02, "PreSi target =2.5A", fontsize=13.5, color="#333333", ha="left", va="center")

    label_x = plot_x_min + 0.010
    label_offsets = [0.03, 0.0, -0.03]
    for index, (product, postsi_value, color) in enumerate(sorted(fit_annotations, key=lambda item: item[1], reverse=True)):
        label = f"{product} PostSi={postsi_value:.3f}" if product == "NVLAX" else f"{product} PostSi={postsi_value:.2f}"
        y_label = postsi_value + (label_offsets[index] if index < len(label_offsets) else 0.0)
        ax.text(label_x, y_label, label, color=color, fontsize=12.5, ha="left", va="center")

    ax.set_xlim(plot_x_min, plot_x_max)
    y_min = min(1.0, float(frame["sicc_value"].min()) * 0.95)
    y_max = max(4.0, float(frame["sicc_value"].max()) * 1.05)
    ax.set_ylim(y_min, y_max)
    ax.set_yscale("log")
    yticks = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    ax.yaxis.set_major_locator(FixedLocator(yticks))
    ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:g}" if value in yticks else ""))
    ax.set_xlabel("UPM FEM CDIE", fontsize=14)
    ax.set_ylabel(SICC_COLUMN, fontsize=13)
    ax.set_title(
        f"Bivariate Fit of {SICC_COLUMN} By\nUPM FEM CDIE",
        fontsize=17,
        fontweight="bold",
        loc="left",
        pad=14,
    )

    legend = ax.legend(title="prod", loc="upper right", frameon=False, fontsize=12, title_fontsize=12, handlelength=1.2, handletextpad=0.4)
    legend._legend_box.align = "left"
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)

    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=220, bbox_inches="tight")
    plt.close(fig)

    counts = frame.groupby("product").size().to_dict()
    print(f"Rows used: {frame.shape[0]}")
    print(f"Product counts: {counts}")
    print(f"Output PNG: {output_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())