# Canonical NVLAX Automation

This is the canonical NVLAX automation.

## Active automation

- 05:00 daily production job: `NVLAX62A0H25 Daily Full Analysis 5AM`
- 13:00 daily watchdog: `NVLAX62A0H25 Daily Health Check 1300`
- Output directory: `R:\Products\NVL\NVL-AX\Weekly data pull`

## Rules

1. There must be exactly one active NVLAX automation flow in Task Scheduler.
2. The daily 05:00 job is the production source of truth.
3. The watchdog is the health monitor and recovery trigger.
4. No legacy or duplicate weekly NVLAX schedules may be created or kept active.
5. Any older NVLAX task registration scripts are deprecated and must not be used.

## Canonical scripts

- `register_nvlax62a0h25_daily_5am_task.ps1`
- `run_nvlax62a0h25_daily_full_analysis.ps1`
- `watch_nvlax62a0h25_daily_health.ps1`
- `register_nvlax62a0h25_daily_1300_watchdog_task.ps1`

## Deprecated scripts

The following scripts are intentionally deprecated because they create split-brain behavior or duplicate NVLAX automation:

- `register_aqua_nvlax_weekly_task.ps1`
- `schedule-nvlax-weekly-run.ps1`

These files must not be used for active scheduling.
