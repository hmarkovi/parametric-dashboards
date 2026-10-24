<#
.SYNOPSIS
Register a 13:00 daily watchdog task for the NVLAX62A0H25 automation.

.DESCRIPTION
Creates or updates a scheduled task that validates whether the 05:00 NVLAX recovery job produced fresh
status, Vmin, ILAS, and merged output artifacts. If the run is stale or missing, the watchdog triggers the
manual recovery script automatically.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "NVLAX62A0H25 Daily Health Check 1300",
    [string]$TaskDescription = "Daily NVLAX62A0H25 health check and recovery trigger (13:00)",
    [string]$RunScriptPath = "",
    [string]$RunTime = "13:00",
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull",
    [string]$ProgramPattern = "NVLAX62A0H25*",
    [int]$LastNDaysTestStart = 0,
    [int]$LastNDaysTestEnd = 7,
    [int]$AquaPullTimeoutSeconds = 1800,
    [int]$AquaPullPollSeconds = 10,
    [double]$FreshnessThresholdHours = 12,
    [ValidateSet("Interactive", "S4U")]
    [string]$LogonType = "Interactive"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($LogonType -eq "S4U") {
    throw "S4U logon cannot access the network resources required by the NVLAX watchdog and recovery flow. Use Interactive while the user session stays logged in, or register the task manually with stored credentials."
}

if ($TaskName -match ":") {
    throw "Task name '$TaskName' is invalid for Windows Task Scheduler. Remove characters such as ':' from the task name and keep the trigger time in the schedule instead."
}

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($RunScriptPath)) {
    $RunScriptPath = Join-Path $scriptDir "watch_nvlax62a0h25_daily_health.ps1"
}

if (-not (Test-Path -LiteralPath $RunScriptPath)) {
    throw "Watchdog script not found: $RunScriptPath"
}

try {
    Unblock-File -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
    Unblock-File -LiteralPath $RunScriptPath -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "Could not unblock one or more scripts (continuing): $($_.Exception.Message)"
}

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$scriptDirectory = Split-Path -Path $RunScriptPath -Parent

$legacyTaskNames = @(
    "Aqua NVLAX Weekly Pull",
    "NVLAX UPSVF Weekly Pull"
)
foreach ($legacyTaskName in $legacyTaskNames) {
    $legacyTask = Get-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Write-Warning "Removing legacy NVLAX task: $legacyTaskName"
        Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false | Out-Null
    }
}

$argumentParts = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $RunScriptPath),
    "-OutputDirectory", ('"{0}"' -f $OutputDirectory),
    "-ProgramPattern", ('"{0}"' -f $ProgramPattern),
    "-LastNDaysTestStart", [string]$LastNDaysTestStart,
    "-LastNDaysTestEnd", [string]$LastNDaysTestEnd,
    "-AquaPullTimeoutSeconds", [string]$AquaPullTimeoutSeconds,
    "-AquaPullPollSeconds", [string]$AquaPullPollSeconds,
    "-FreshnessThresholdHours", [string]$FreshnessThresholdHours
)

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument ($argumentParts -join " ") `
    -WorkingDirectory $scriptDirectory

$trigger = New-ScheduledTaskTrigger -Daily -At $RunTime

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $currentIdentity `
    -LogonType $LogonType `
    -RunLevel Highest

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$task = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $TaskDescription

Write-Host "Scheduled task registered: $($task.TaskName)"
Write-Host "Run time: $RunTime daily"
Write-Host "Watchdog script: $RunScriptPath"
Write-Host "Output directory: $OutputDirectory"
Write-Host "Program filter: $ProgramPattern"
Write-Host "Lookback: LastNDaysTestStart=$LastNDaysTestStart, LastNDaysTestEnd=$LastNDaysTestEnd"
Write-Host "Freshness threshold: $FreshnessThresholdHours hours"
Write-Host "Logon type: $LogonType"
