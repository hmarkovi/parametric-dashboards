<#
.SYNOPSIS
Register a daily 5AM scheduled task for the NVLAX62A0H25 full UPSVF+ILAS analysis.

.DESCRIPTION
Creates or updates a Task Scheduler entry that runs the dedicated NVLAX62A0H25 wrapper
every day at 05:00 using the current interactive user context so network shares remain available.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "NVLAX62A0H25 Daily Full Analysis 5AM",
    [string]$TaskDescription = "Daily NVLAX62A0H25 UPSVF + ILAS full analysis (05:00)",
    [string]$RunScriptPath = "",
    [string]$RunTime = "05:00",
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull",
    [string]$ProgramPattern = "NVLAX62A0H25*",
    [int]$LastNDaysTestStart = 0,
    [int]$LastNDaysTestEnd = 7,
    [int]$AquaPullTimeoutSeconds = 1800,
    [int]$AquaPullPollSeconds = 10,
    [switch]$KeepCleanCsvArtifact,
    [ValidateSet("Interactive", "S4U")]
    [string]$LogonType = "Interactive"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($LogonType -eq "S4U") {
    throw "S4U logon cannot access the network resources required by the NVLAX automation (Aqua shares and output share). Use Interactive while the user session stays logged in, or register the task manually with stored credentials."
}

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($RunScriptPath)) {
    $RunScriptPath = Join-Path $scriptDir "run_nvlax62a0h25_daily_full_analysis.ps1"
}

if (-not (Test-Path -LiteralPath $RunScriptPath)) {
    throw "Run script not found: $RunScriptPath"
}

try {
    Unblock-File -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
    Unblock-File -LiteralPath $RunScriptPath -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "Could not unblock one or more scripts (continuing): $($_.Exception.Message)"
}

$scriptDirectory = Split-Path -Path $RunScriptPath -Parent
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

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
    "-AquaPullPollSeconds", [string]$AquaPullPollSeconds
)
if ($KeepCleanCsvArtifact) {
    $argumentParts += "-KeepCleanCsvArtifact"
}

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
Write-Host "Run script: $RunScriptPath"
Write-Host "Output directory: $OutputDirectory"
Write-Host "Program filter: $ProgramPattern"
Write-Host "Date filter: LastNDaysTestStart=$LastNDaysTestStart"
Write-Host "Aqua timeout: $AquaPullTimeoutSeconds seconds"
Write-Host "Aqua poll: $AquaPullPollSeconds seconds"
Write-Host "Logon type: $LogonType"