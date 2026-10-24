---
name: nvlax-dts-weekly-analysis
description: Build an NVLAX DTS HTML report from a merged weekly CSV, grouped by official released Class test program with a dropdown selector and per-domain DTS plots.
---

## Purpose

Use this skill to generate DTS analysis from an existing merged weekly NVLAX CSV that already contains `ILAS_*` columns.

## Scope

This skill includes:
- reading an existing weekly CSV such as `R:\Products\NVL\NVL-AX\Weekly data pull\Vmin_20260927.csv`
- extracting Class TP from `Program Name_CLASSHOT` or equivalent Class program column
- filtering to officially released Class TPs only
- converting `ILAS_*_MaxDTS_C`, `ILAS_*_Setter`, and `ILAS_*_LP` columns into long-form DTS observations
- grouping DTS by Class TP, domain, frequency, module, and core
- generating an offline HTML report with a dropdown to select the Class TP
- generating side CSV artifacts and `run_manifest.json`

This skill does not include:
- running the weekly AQUA pull
- generating PNG output
- PowerPoint generation

## Released Class TP rule

Only official released Class TPs are included.

Current rule:
- extract the Class TP key from the full program name
- keep only officially released keys for the product family
- current NVLAX allowlist includes `25C00`, `25D00`, `25D10`, `25E00`
- example excluded: `25D01`
- if a new released key is approved, add it to the product allowlist before rerunning the report

If a row does not match the rule, the program is excluded from the report and recorded in the filtered-program artifact.

## Inputs

- merged weekly CSV path
- optional output directory
- optional output HTML path

## Output behavior

- one HTML report with a dropdown for released Class TP selection
- one report section per domain for the active Class TP
- y-axis: DTS temperature from ILAS
- x-axis: combined `Frequency | Module | Core`
- violation summary sorted with above-`100C` medians ahead of below-`100C` medians
- violation summary table trimmed to the preferred five frequencies when present: `1.2`, `2.8`, `3.8`, `4.3`, `4.6`

## Side artifacts

- `dts_temperature_points_*.csv`
- `dts_temperature_bucket_summary_*.csv`
- `dts_temperature_violations_*.csv`
- `dts_filtered_programs_*.csv`
- `run_manifest.json`

## Script entry point

`Scripts/parametric-analysis/ilas/build-nvlax-dts-weekly-html.ps1`

## Example

```powershell
& ".\Scripts\parametric-analysis\ilas\build-nvlax-dts-weekly-html.ps1" `
  -InputCsvPath "R:\Products\NVL\NVL-AX\Weekly data pull\Vmin_20260927.csv"
```

## Fast prompt

Use this single prompt:

`Use nvlax-dts-weekly-analysis: build DTS HTML analysis for R:\Products\NVL\NVL-AX\Weekly data pull\Vmin_20260927.csv`