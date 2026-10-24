<#
.SYNOPSIS
Remove legacy split-brain NVLAX tasks and leave only the canonical daily automation and watchdog.

.DESCRIPTION
This script unregisters all legacy NVLAX schedule entries that create ambiguity or multiple active
pipelines. After cleanup, the single supported NVLAX flow is:
  - 05:00 daily production job: NVLAX62A0H25 Daily Full Analysis 5AM
  - 13:00 daily watchdog: NVLAX62A0H25 Daily Health Check 1300
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$legacyTaskNames = @(
    "Aqua NVLAX Weekly Pull",
    "NVLAX UPSVF Weekly Pull"
)

foreach ($taskName in $legacyTaskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Removing legacy task: $taskName"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
    }
    else {
        Write-Host "No legacy task found: $taskName"
    }
}

Write-Host "Legacy NVLAX split-brain tasks removed."
Write-Host "Canonical daily automation remains authoritative: NVLAX62A0H25 Daily Full Analysis 5AM"
Write-Host "Canonical watchdog remains authoritative: NVLAX62A0H25 Daily Health Check 1300"
