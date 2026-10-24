<#
.SYNOPSIS
Create Windows Task Scheduler task to run weekly NVLH UPSVF+ILAS automation every Sunday at 5:00 AM.

.DESCRIPTION
Sets up a recurring scheduled task that:
1. Runs aqua_nvlh_weekly_pull.ps1 every Sunday at 5:00 AM
2. Logs output to Weekly Run Status and logs files
3. Ensures only CLASSHOT opergroup data is included
4. Removes test names ending in "_it" or "_scrb" during ILAS processing
5. Merges ILAS columns back to UPSVF output with atomic file replacement

.NOTES
Requires administrator privileges.
Task name: "NVL UPSVF Weekly Pull"
Trigger: Every Sunday at 5:00 AM
Action: PowerShell script execution with ILAS analysis and merge
#>

# Requires administrator to run
#Requires -RunAsAdministrator

param(
    [string]$WeeklyScriptPath = "C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\data-pulling\weekly-aqua-pull\aqua_nvlh_weekly_pull.ps1",
    [string]$IlasScriptPath = "C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\parametric-analysis\ilas\aqua_nvlh_ilas_vmin_analysis.ps1",
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs",
    [string]$TaskName = "NVL UPSVF Weekly Pull",
    [string]$TaskDescription = "Weekly UPSVF pull from AQUA with ILAS analysis and column merge (Sunday 5:00 AM)"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Setting up Windows Task Scheduler for weekly NVLH UPSVF+ILAS automation..."

# Verify scripts exist
if (-not (Test-Path -LiteralPath $WeeklyScriptPath)) {
    throw "Weekly script not found: $WeeklyScriptPath"
}
if (-not (Test-Path -LiteralPath $IlasScriptPath)) {
    throw "ILAS script not found: $IlasScriptPath"
}

# Check if task already exists and remove it
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

# Create task trigger: Every Sunday at 5:00 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "05:00"

# Build PowerShell command
$psCmd = @"
`$ErrorActionPreference = 'Stop'
`$logPath = '{0}'
`$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
`$logFile = `$logPath + '\Weekly_Run_Log_' + `$timestamp + '.log'
try {{
    & '{1}' -OutputDirectory '{0}' -IlasScriptPath '{2}' -KeepCleanCsvArtifact 2>&1 | Tee-Object -FilePath `$logFile
    exit `$LASTEXITCODE
}} catch {{
    Add-Content -LiteralPath `$logFile -Value ("ERROR: `$_`r`n" + `$_.ScriptStackTrace)
    exit 1
}}
"@ -f $OutputDirectory, $WeeklyScriptPath, $IlasScriptPath

# Create action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NoExit -Command `"$psCmd`""

# Create task settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Register the task
$task = Register-ScheduledTask `
    -TaskName $TaskName `
    -Trigger $trigger `
    -Action $action `
    -Settings $settings `
    -Description $TaskDescription `
    -RunLevel Highest

Write-Host ""
Write-Host "Task created successfully!"
Write-Host ""
Write-Host "Task Details:"
Write-Host "  Name: $($task.TaskName)"
Write-Host "  Description: $($task.Description)"
Write-Host "  Trigger: Every Sunday at 5:00 AM"
Write-Host "  Status: $(if ($task.State -eq 'Ready') { 'Ready' } else { 'Not Ready' })"
Write-Host ""
Write-Host "Weekly automation will:"
Write-Host "  1. Pull UPSVF from AQUA (last 7 days)"
Write-Host "  2. Filter by operations 6248 (CLASSHOT)"
Write-Host "  3. Remove test names ending in '_it' or '_scrb' from ILAS data"
Write-Host "  4. Merge ILAS Vmin/Setter/MaxDTS_C/LP columns into UPSVF"
Write-Host ""
Write-Host "Output location: $OutputDirectory"
Write-Host ""
Write-Host "Logs will be saved as: Weekly_Run_Log_yyyyMMdd_HHmmss.log"
