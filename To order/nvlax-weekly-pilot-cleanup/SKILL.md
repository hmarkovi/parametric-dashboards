---
name: nvlax-weekly-pilot-cleanup
description: Clean and segment the weekly NVLAX data in R:\Products\NVL\NVL-AX\Weekly data pull into Class-TP-specific retained CSVs and manifest records, mirroring the NVLH cleanup flow.
---

## Purpose

Use this skill to run the NVLAX weekly cleanup and program-segmentation flow for the directory `R:\Products\NVL\NVL-AX\Weekly data pull`.

This is the NVLAX-specific mirror of the weekly cleanup logic already implemented in `Scripts/data-pulling/weekly-aqua-pull/start_nvlh_weekly_pilot_cleanup.ps1`.

## Scope

This skill includes:
- scanning the weekly NVLAX root for final weekly CSVs and raw/ILAS artifacts
- selecting the most recent work weeks in the root folder
- grouping rows by normalized Class TP key
- merging rows into retained per-program CSVs under `By-Class-TP-final`
- writing JSON manifests under `By-Class-TP-final\pilot_cleanup_manifests`
- optionally deleting original weekly source files after retention

This skill does not include:
- creating new weekly AQUA pulls
- DTS report generation
- original NVLH schedule logic

## Entry point

`Scripts/data-pulling/weekly-aqua-pull/start_nvlax_weekly_pilot_cleanup.ps1`

## Default settings

- WeeklyRunsDir: `R:\Products\NVL\NVL-AX\Weekly data pull`
- RetainedFolderName: `By-Class-TP-final`
- ManifestFolderName: `pilot_cleanup_manifests`
- MaxWorkWeeks: `3`
- Schedule: every Thursday at `05:00`

## Example

```powershell
& ".\Scripts\data-pulling\weekly-aqua-pull\start_nvlax_weekly_pilot_cleanup.ps1" `
  -WeeklyRunsDir "R:\Products\NVL\NVL-AX\Weekly data pull" `
  -WorkWeeks @("WW33_2026", "WW34_2026", "WW35_2026") `
  -MaxWorkWeeks 3 `
  -RetainedFolderName "By-Class-TP-final" `
  -ManifestFolderName "pilot_cleanup_manifests"
```

## Merge policy (per-cell, never whole-row)

- Row key = `VISUAL_ID` + `LOTFROMFS` (upper-cased, trimmed). A different `LOTFROMFS` is a different row: both are kept.
- Same key: the newest non-empty cell wins; empty cells are filled from older rows. Cells whose value changes are listed in `pilot_cleanup_manifests\WWnn_YYYY_conflicts.csv` (ClassTp, Key, Column, OlderValue, NewerValue).
- Weeks are always merged oldest to newest, daily files in date order.
- Headers are the union of the retained file and every contributing source file (not only the first row).
- Rows with a blank program name, an unmapped program or a blank key are never dropped silently: they are listed under `SkippedRows` in the week manifest and fail validation.

## Mandatory validation (data-integrity gate)

After each week's merge the engine runs `Scripts/data-pulling/weekly-aqua-pull/validate_weekly_cleanup.py` (Python, independent of the engine code):
- expected = pre-merge retained snapshot overlaid with the week's source files in date order; retained must match it exactly
- no row or column missing, no duplicate keys, no non-empty cell lost, emptied or changed, no unexplained row or value, no `~` in AT_REF columns
- independent program -> file mapping check (longest retained-file-stem prefix vs engine regex)
- per (TP, lot) accounting in `WWnn_YYYY_validation.lots.csv`; full result in `WWnn_YYYY_validation.json`
- `-DeleteOriginals` only deletes a week's originals when its validation passed; `-SkipValidation` together with `-DeleteOriginals` is refused

Full audit of the whole retained folder against archived originals and a pre-merge backup:

```powershell
python validate_weekly_cleanup.py --retained-dir "<root>\By-Class-TP-final" --baseline-dir "<root>\_organize_safety_backup_*\By-Class-TP-final" --report "<root>\audit.json" --sources <all Vmin_YYYYMMDD.csv in date order>
```

Exit code 0 = ALL OK. Always report the validator result with any cleanup run.

## Rebuild / recovery

Stage the pre-merge retained files in `<staging>\By-Class-TP-final`, copy the original `Vmin_YYYYMMDD.csv` files to `<staging>`, run the entry point with `-WeeklyRunsDir <staging>` (no `-DeleteOriginals`), check the validator output, then swap the staged retained files into the real folder (keep the old ones as backup).

## Scheduled automation

Use the task registration script below to set the recurring Thursday runner:

`Scripts/data-pulling/weekly-aqua-pull/register_nvlax_weekly_thursday_cleanup_task.ps1`

## Parquet store and single HTML report (opt-in)

Add `-UpdateParquetStore` to the entry point (after the cleanup and validation) to run `Scripts/parametric-analysis/parametric-tabs/weekly_parquet_store.py run`:
- `ingest`: each retained per-TP CSV is upserted into `<root>\Parquet_store\parquet\TP=<csv stem>\data.parquet` (reduced columns, all TPs, zstd). Same key rule as above (`VISUAL_ID` + `LOTFROMFS`, newest non-empty cell wins). A CSV is skipped when its size and mtime are unchanged. Writes are atomic and verified (all keys present) before the partition is replaced.
- `retention`: the 3-WW window is counted from the TP's last update (last changed ingest). Report only by default; `weekly_parquet_store.py retention --apply` deletes a CSV only if the Parquet partition is verified, holds every CSV key, and the TP is not in `--keep-forever` (default `25E`).
- `report`: one HTML for all TPs (`build_parametric_tabs.py --input-parquet`). Plots use a deterministic fair-share sample capped by `-ParquetMaxUnits` (default 15000); overview counts, flow matrix and limiter use all units. The footer and TP labels state when sampling applied.
- Drill-down to raw per-unit columns is a reserved placeholder (`weekly_parquet_store.py drilldown`), not defined yet.

## Fast prompt

Use this single prompt:

`Use nvlax-weekly-pilot-cleanup: clean and segment the weekly NVLAX data in R:\Products\NVL\NVL-AX\Weekly data pull into By-Class-TP-final files with manifests and Thursday 05:00 scheduling.`
