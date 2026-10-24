---
name: nvlax-daily-watchdog
description: Validate the daily NVLAX 5AM automation, check same-day freshness, and trigger the manual recovery run when UPSVF, ILAS, or merged-output artifacts are stale or missing.
---

## Purpose

Use this skill when the NVLAX daily automation is expected to complete at 05:00 and should be validated again at 13:00.

This watchdog ensures the pipeline is healthy before the team relies on the output. It checks whether the run produced:
- a fresh `Weekly_Run_Status.csv`
- a fresh `Vmin_*.csv`
- a fresh `_ilas_weekly_*` directory
- a final merged CSV path that still exists

## Scope

This skill applies to the active NVLAX daily automation path only.

It covers:
- validating the 5AM data pull output directory
- comparing timestamps against the freshness threshold
- reading the latest status row in `Weekly_Run_Status.csv`
- identifying whether the issue is automation, merge, or Aqua outage-related
- triggering the manual recovery script when the daily run is stale or incomplete

## Guardrails

1. Do not treat historical files as success if they are older than the allowed threshold.
2. The watchdog must fail when the output directory is missing, empty, stale, or a final merged CSV is missing.
3. The recovery trigger must use the NVLAX62A0H25 production defaults already in use by the daily automation.
4. Every failure should generate both:
   - a machine-readable CSV audit row
   - a human-readable warning log entry
5. Recovery should be automatic for production use, but the log must clearly show the reason and the result.

## Key Parameters

- OutputDirectory: `R:\Products\NVL\NVL-AX\Weekly data pull`
- ProgramPattern: `NVLAX62A0H25*`
- LastNDaysTestEnd: `7`
- LastNDaysTestStart: `0`
- FreshnessThresholdHours: `12` (default midday check after a 05:00 run)

## Expected Output Signals

The watchdog counts the run as healthy only if it sees all of the following:
- `Weekly_Run_Status.csv` exists and is fresh
- `Vmin_*.csv` exists and is fresh
- `_ilas_weekly_*` directory exists and is fresh
- final merged CSV recorded in the status row still exists
- the latest status row does not show `FAILED`

## Recovery Trigger

When validation fails, trigger the production recovery script:

```powershell
.\watch_nvlax62a0h25_daily_health.ps1 `
  -OutputDirectory "R:\Products\NVL\NVL-AX\Weekly data pull" `
  -ProgramPattern "NVLAX62A0H25*" `
  -LastNDaysTestStart 0 `
  -LastNDaysTestEnd 7 `
  -FreshnessThresholdHours 12
```

This recovery path should call the same script used by the daily NVLAX automation, not a newer or unrelated query strategy.

## Validation and Logging

The watchdog writes:
- CSV audit log: `NVLAX_daily_watchdog_audit.csv`
- Warning log: `NVLAX_daily_watchdog_warning_YYYYMMDD_HHmmss.log`

The CSV records the exact verification results, including the failure class, timestamp, freshness status, and whether recovery was executed.

## Failure Classes

- `automation`: output directory missing, empty, or no fresh artifacts
- `merge`: status or final output indicates the merge did not complete
- `aqua_outage`: no fresh result arrived from AQUA within the threshold
- `stale_run`: the current run is older than the allowed freshness window

## Example Run

```powershell
& "Scripts\data-pulling\weekly-aqua-pull\watch_nvlax62a0h25_daily_health.ps1" `
  -OutputDirectory "R:\Products\NVL\NVL-AX\Weekly data pull" `
  -ProgramPattern "NVLAX62A0H25*" `
  -LastNDaysTestStart 0 `
  -LastNDaysTestEnd 7 `
  -FreshnessThresholdHours 12
```

This should be run daily at 13:00 using the scheduled task registration helper.
