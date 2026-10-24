from __future__ import annotations

import argparse
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


SICC_COLUMN = "SICC-U1PU5_IA00-V1_value"
UPM_COLUMN = "UPM_0107_DPMH156P48ULVTINVD4_FULLDIE_0950_MED_SORT_U1.U5"
PRODUCT_COLUMN = "prod"
PROCESS_TARGET = 0.95
PRESI_TARGET = 2.5

PRODUCT_COLORS = {
    "NVLAX": "#e84a5f",
    "NVLHX": "#2ca02c",
    "NVLS7": "#3b6eea",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render the reference-style Core raw SICC plot.")
    parser.add_argument(
        "--input-csv",
        default=r"R:\Products\NVL\NVL-AX\Weekly data pull\2026_41_NVLS_NVLHX_data_comper.csv",
        help="CSV that contains the exact raw Core SICC and UPM columns from the example graph.",
    )
    parser.add_argument(
        "--output-png",
        default=r"R:\Products\NVL\NVL-AX\Weekly data pull\core_raw_sicc_reference.png",
        help="Output PNG path.",
    )
    return parser.parse_args()


def fit_ln_curve(frame: pd.DataFrame) -> dict[str, float] | None:
    x = frame["upm_fem_cdie"].to_numpy(dtype=float)
    y = frame["sicc_value"].to_numpy(dtype=float)
    mask = np.isfinite(x) & np.isfinite(y) & (x > 0.0)
    if int(mask.sum()) < 3:
        return None
    x = x[mask]
    y = y[mask]
    design = np.column_stack([np.log(x), np.ones(x.shape[0])])
    coefficients, _, _, _ = np.linalg.lstsq(design, y, rcond=None)
    slope = float(coefficients[0])
    intercept = float(coefficients[1])
    postsi_value = float(slope * math.log(PROCESS_TARGET) + intercept)
    return {
        "slope_ln": slope,
        "intercept": intercept,
        "postsi_value": postsi_value,
        "x_min": float(np.min(x)),
        "x_max": float(np.max(x)),
    }


def main() -> int:
    args = parse_args()
    input_csv = Path(args.input_csv)
    output_png = Path(args.output_png)

    frame = pd.read_csv(input_csv, low_memory=False, usecols=[PRODUCT_COLUMN, SICC_COLUMN, UPM_COLUMN])
    frame = frame.rename(columns={PRODUCT_COLUMN: "product", SICC_COLUMN: "sicc_value", UPM_COLUMN: "upm_raw"})
    frame["product"] = frame["product"].astype(str).str.strip().str.upper()
    frame["sicc_value"] = pd.to_numeric(frame["sicc_value"], errors="coerce")
    frame["upm_raw"] = pd.to_numeric(frame["upm_raw"], errors="coerce")
    frame = frame.dropna(subset=["product", "sicc_value", "upm_raw"])
    frame = frame[(frame["sicc_value"] > 0.0) & (frame["upm_raw"] > 0.0)]
    frame["upm_fem_cdie"] = frame["upm_raw"] / 10000.0
    frame = frame[frame["product"].isin(PRODUCT_COLORS.keys())]

    fig, ax = plt.subplots(figsize=(11.1, 8.4), constrained_layout=True)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("#fbfbfa")
    ax.grid(True, which="major", axis="both", color="#cfcfcf", linewidth=0.6, alpha=0.8)
    ax.minorticks_on()
    ax.grid(True, which="minor", axis="x", color="#e7e7e7", linewidth=0.45, alpha=0.9)
    ax.set_axisbelow(True)

    fit_annotations = []
    plot_x_min = 0.873
    plot_x_max = 0.992
    line_x = np.linspace(plot_x_min, plot_x_max, 400)
    for product in ["NVLAX", "NVLHX", "NVLS7"]:
        product_frame = frame[frame["product"] == product].copy()
        if product_frame.empty:
            continue
        color = PRODUCT_COLORS[product]
        ax.scatter(
            product_frame["upm_fem_cdie"],
            product_frame["sicc_value"],
            s=4,
            marker="s",
            color=color,
            alpha=0.28,
            linewidths=0.0,
            label=product,
        )
        fit = fit_ln_curve(product_frame)
        if fit is None:
            continue
        line_y = fit["slope_ln"] * np.log(line_x) + fit["intercept"]
        ax.plot(line_x, line_y, color=color, linewidth=1.8)
        ax.axhline(fit["postsi_value"], color=color, linewidth=0.8, alpha=0.9)
        fit_annotations.append((product, fit["postsi_value"], color))

    ax.axvline(PROCESS_TARGET, color="#404040", linestyle="--", linewidth=1.6)
    ax.text(PROCESS_TARGET, 1.02, "Process target=0.95", transform=ax.get_xaxis_transform(), ha="center", va="bottom", fontsize=14)

    ax.text(0.896, PRESI_TARGET + 0.005, "PreSi target =2.5A", fontsize=14, color="#333333")

    for product, postsi_value, color in sorted(fit_annotations, key=lambda item: item[1], reverse=True):
        label = f"{product} PostSi={postsi_value:.3f}" if product == "NVLAX" else f"{product} PostSi={postsi_value:.2f}"
        ax.text(0.878, postsi_value, label, color=color, fontsize=12.5, ha="right", va="center")

    ax.set_xlim(plot_x_min, plot_x_max)
    ax.set_ylim(1.0, 4.0)
    ax.set_xticks([0.88, 0.90, 0.92, 0.95, 0.98])
    ax.set_xticklabels(["0.88", "0.9", "0.92", "0.95", "0.98"], fontsize=12)
    ax.set_yticks([2.0, 3.0, 4.0])
    ax.tick_params(axis="y", labelsize=12)
    ax.set_xlabel("UPM FEM CDIE", fontsize=14)
    ax.set_ylabel("SICC-U1PU5_IA00-V1_value", fontsize=14)
    ax.set_title(
        "Bivariate Fit of SICC-U1PU5_IA00-V1_value By\nTransform[UPM_0107_DPMH156P48ULVTINVD4_FULLDIE_0950_MED_SORT_U1.U5]",
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

    print(f"Rows used: {frame.shape[0]}")
    print(f"Output PNG: {output_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())