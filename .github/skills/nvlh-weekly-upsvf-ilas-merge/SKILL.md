---
name: nvlh-weekly-upsvf-ilas-merge
description: Run the weekly NVLH Classhot UPSVF automation, conditionally trigger ILAS analysis, and merge ILAS columns directly into the final UPSVF weekly CSV with failure isolation and frequency-scoped ILAS cleanup.
---

## Purpose

Use this skill for end-to-end weekly automation implemented in Scripts/aqua_nvlh_weekly_pull.ps1.

## Scope

This skill covers weekly orchestration and merge behavior only.

It includes:
- Running weekly UPSVF pull/clean/export
- Starting ILAS only after UPSVF output is valid (VisualID + lot/class-lot present)
- Merging ILAS columns into final UPSVF CSV directly (no separate merge table required)
- Prefixing merged columns with ILAS_
- Preserving UPSVF output if ILAS step fails
- Frequency-scoped cleanup: clear ILAS values only for frequencies missing in UPSVF row

## Guardrails

1. If UPSVF output is missing or defective, ILAS step is skipped.
2. If ILAS fails, UPSVF final CSV remains available and is not corrupted.
3. Merge key is VisualID + lot/class-lot.
4. Cleanup is frequency-specific, not full-row deletion.

## Key Parameters

- LastNDaysTestEnd: weekly window (use 7)
- ProgramPattern: NVLHM66*
- SkipIlasStep: optional bypass for baseline UPSVF-only runs
- IlasScriptPath: optional explicit path
- OutputDirectory: use isolated folder for verification runs

## Example Verification Run

PowerShell:

& ".\Scripts\data-pulling\weekly-aqua-pull\aqua_nvlh_weekly_pull.ps1" `
  -OutputDirectory "R:\Products\NVL\NVL-H\Weekly Runs" `
  -LastNDaysTestEnd 7 `
  -ProgramPattern "NVLHM66*"

## Outputs

- Weekly UPSVF CSV: Vmin_<program>_WW<week>_<year>.csv
- Clean UPSVF CSV: Vmin_<program>_WW<week>_<year>_clean.csv
- Weekly run log: Weekly_Run_Log.md
- Weekly health log: Weekly_Run_Health.csv

When ILAS succeeds, final weekly CSV contains ILAS_* columns merged in-place.
