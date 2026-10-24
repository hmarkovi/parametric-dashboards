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

## Scheduled automation

Use the task registration script below to set the recurring Thursday runner:

`Scripts/data-pulling/weekly-aqua-pull/register_nvlax_weekly_thursday_cleanup_task.ps1`

## Fast prompt

Use this single prompt:

`Use nvlax-weekly-pilot-cleanup: clean and segment the weekly NVLAX data in R:\Products\NVL\NVL-AX\Weekly data pull into By-Class-TP-final files with manifests and Thursday 05:00 scheduling.`
