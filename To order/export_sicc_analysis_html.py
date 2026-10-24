from __future__ import annotations

import argparse
import html
from pathlib import Path

import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export the generated SICC analysis artifacts to a readable HTML report.")
    parser.add_argument(
        "--analysis-dir",
        default=r"R:\Products\NVL\NVL-AX\Weekly data pull\2026_43_Cross_product_SICC_analysis",
        help="Directory containing normalized summary, comments, and plot artifacts.",
    )
    parser.add_argument(
        "--output-html",
        default=r"R:\Products\NVL\NVL-AX\Weekly data pull\2026_43_Cross_product_SICC_analysis.html",
        help="Target HTML report path.",
    )
    return parser.parse_args()


def dataframe_to_html_table(frame: pd.DataFrame, title: str) -> str:
    if frame.empty:
        return f"<section><h2>{html.escape(title)}</h2><p>No rows.</p></section>"

    columns = list(frame.columns)
    thead = "".join(f"<th>{html.escape(str(column))}</th>" for column in columns)
    rows = []
    for _, row in frame.iterrows():
        cells = []
        for column in columns:
            value = row[column]
            if pd.isna(value):
                rendered = ""
            else:
                rendered = str(value)
            cells.append(f"<td>{html.escape(rendered)}</td>")
        rows.append("<tr>" + "".join(cells) + "</tr>")

    return (
        f"<section><h2>{html.escape(title)}</h2>"
        f"<div class='table-wrap'><table><thead><tr>{thead}</tr></thead><tbody>{''.join(rows)}</tbody></table></div></section>"
    )


def build_plot_cards(plot_index: pd.DataFrame, analysis_dir: Path) -> str:
    if plot_index.empty:
        return "<section><h2>Plots</h2><p>No plots found.</p></section>"

    cards = []
    for _, row in plot_index.sort_values(["canonical_domain", "measure_type"]).iterrows():
        image_path = Path(row["image_path"])
        relative_path = image_path.relative_to(analysis_dir.parent)
        title = f"{row['canonical_domain']} - {row['measure_type']}"
        subtitle = f"points: {row['point_count']}, visuals: {row['visual_count']}"
        cards.append(
            "<article class='plot-card'>"
            f"<h3>{html.escape(title)}</h3>"
            f"<p>{html.escape(subtitle)}</p>"
            f"<img src='{html.escape(relative_path.as_posix())}' alt='{html.escape(title)}' />"
            "</article>"
        )

    return f"<section><h2>Plots</h2><div class='plot-grid'>{''.join(cards)}</div></section>"


def main() -> int:
    args = parse_args()
    analysis_dir = Path(args.analysis_dir)
    output_html = Path(args.output_html)

    summary_wide = pd.read_csv(analysis_dir / "normalized_sicc_summary_wide.csv")
    summary_long = pd.read_csv(analysis_dir / "normalized_sicc_summary.csv")
    comments_path = analysis_dir / "comments.csv"
    comments = pd.read_csv(comments_path) if comments_path.exists() and comments_path.stat().st_size > 0 else pd.DataFrame()
    plot_index = pd.read_csv(analysis_dir / "plot_index.csv")

    html_parts = [
        "<!doctype html>",
        "<html><head><meta charset='utf-8' />",
        "<title>Cross Product SICC Analysis</title>",
        "<style>",
        "body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1f2937;background:#f8fafc}",
        "h1,h2,h3{margin:0 0 12px 0}",
        "section{background:white;border:1px solid #dbe3ef;border-radius:10px;padding:16px;margin-bottom:18px}",
        ".table-wrap{overflow:auto}",
        "table{border-collapse:collapse;width:100%;font-size:12px}",
        "th,td{border:1px solid #d9e1eb;padding:6px 8px;text-align:left;white-space:nowrap}",
        "th{background:#eff6ff;position:sticky;top:0}",
        ".plot-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(560px,1fr));gap:18px}",
        ".plot-card img{width:100%;height:auto;border:1px solid #d9e1eb;border-radius:8px;background:white}",
        ".plot-card p{margin:0 0 10px 0;color:#475569;font-size:12px}",
        "</style></head><body>",
        "<h1>Cross Product SICC Analysis</h1>",
        "<p>Generated from 2026_43 Cross product SICC analysis source. Summary table is editable in CSV form and presented here as HTML for readability.</p>",
        dataframe_to_html_table(summary_wide, "Wide Summary Table"),
        dataframe_to_html_table(summary_long, "Detailed Summary Table"),
        dataframe_to_html_table(comments, "Comments"),
        build_plot_cards(plot_index, analysis_dir),
        "</body></html>",
    ]

    output_html.write_text("".join(html_parts), encoding="utf-8")
    print(f"HTML report: {output_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())