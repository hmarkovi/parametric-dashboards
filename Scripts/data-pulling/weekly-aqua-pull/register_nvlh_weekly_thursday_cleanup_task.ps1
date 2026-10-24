#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$TaskName = "NVLH Weekly Cleanup Thu 05:00",
    [string]$TaskDescription = "Thursday cleanup and Class-TP segregation for NVLH weekly data",
    [string]$RunScriptPath = "",
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-H\Weekly Runs",
    [string[]]$WorkWeeks = @("WW33_2026", "WW34_2026", "WW35_2026"),
    [int]$MaxWorkWeeks = 3,
    [string]$RetainedFolderName = "By-Class-TP-final",
    [string]$ManifestFolderName = "pilot_cleanup_manifests",
    [string]$RunTime = "05:00",
    [ValidateSet("Interactive", "S4U")]
    [string]$LogonType = "S4U"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($RunScriptPath)) {
    $RunScriptPath = Join-Path $scriptDir "start_nvlh_weekly_pilot_cleanup.ps1"
}

if (-not (Test-Path -LiteralPath $RunScriptPath -PathType Leaf)) {
    throw "Run script not found: $RunScriptPath"
}

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$legacyTaskNames = @(
    "NVLH Weekly Cleanup Thu 05:00",
    "NVLH Weekly Pilot Cleanup",
    "Aqua NVLH Weekly Pull"
)
foreach ($legacyTaskName in $legacyTaskNames) {
    $legacyTask = Get-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Write-Warning "Removing legacy task: $legacyTaskName"
        Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false | Out-Null
    }
}

$argumentString = @"
-NoProfile -ExecutionPolicy Bypass -Command "& '$RunScriptPath' -WeeklyRunsDir '$WeeklyRunsDir' -MaxWorkWeeks $MaxWorkWeeks -RetainedFolderName '$RetainedFolderName' -ManifestFolderName '$ManifestFolderName'"
"@

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $argumentString `
    -WorkingDirectory (Split-Path -Path $RunScriptPath -Parent)

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At $RunTime

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $currentIdentity `
    -LogonType $LogonType `
    -RunLevel Highest

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $TaskDescription | Out-Null

Write-Host "Scheduled task registered: $TaskName"
Write-Host "Schedule: Thursday $RunTime"
Write-Host "Run script: $RunScriptPath"
Write-Host "Weekly root: $WeeklyRunsDir"
Write-Host "Retained folder: $RetainedFolderName"
Write-Host "Manifest folder: $ManifestFolderName"
