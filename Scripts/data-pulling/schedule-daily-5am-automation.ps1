<#
.SYNOPSIS
Schedule NVLH parallel UPSVF+ILAS daily automation to run at 5am every morning.

.DESCRIPTION
Creates or updates a Windows Task Scheduler task that runs the parallel orchestrator
at 5:00 AM every day. Output is saved to configured weekly runs directory.

.NOTES
Requires: Administrator privileges
Run this once to set up the recurring 5am schedule.
#>

param(
    [string]$TaskName = "NVLH-Parametric-Daily-5am",
    [string]$TaskDescription = "Daily NVLH UPSVF+ILAS parametric analysis (5am)",
    [string]$OrchestratorScript = "C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\data-pulling\weekly-aqua-pull\run_upsvf_ilas_parallel.ps1",
    [string]$OutputDirectory = "R:\Products\NVL\NVL-H\Weekly Runs",
    [string]$VpoList = "6248_CLASSHOT",
    [int]$LastNDaysTestEnd = 1,
    [string]$RunTime = "05:00:00"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check if running as administrator
$isAdmin = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -contains [System.Security.Principal.SecurityIdentifier]"S-1-5-32-544"
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges. Please run as administrator."
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NVLH Daily 5am Automation Task Scheduler Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify orchestrator script exists
if (-not (Test-Path -LiteralPath $OrchestratorScript)) {
    Write-Error "Orchestrator script not found: $OrchestratorScript"
    exit 1
}

Write-Host "Task Name: $TaskName" -ForegroundColor Green
Write-Host "Run Time: $RunTime (daily)" -ForegroundColor Green
Write-Host "Orchestrator: $OrchestratorScript" -ForegroundColor Green
Write-Host "Output Dir: $OutputDirectory" -ForegroundColor Green
Write-Host "VPO List: $VpoList" -ForegroundColor Green
Write-Host "Last N Days: $LastNDaysTestEnd" -ForegroundColor Green
Write-Host ""

# Create the action: PowerShell command with parameters
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument @"
-NoProfile -NoExit -File "$OrchestratorScript" -OutputDirectory "$OutputDirectory" -VpoList "$VpoList" -LastNDaysTestEnd $LastNDaysTestEnd -AutoDiscoverVpos:$false
"@

# Create the trigger: Daily at specified time
$trigger = New-ScheduledTaskTrigger `
    -Daily `
    -At $RunTime

# Create task settings (run with highest privileges, run even if user not logged in)
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RunWithoutNetwork:$false `
    -MultipleInstances IgnoreNew

# Create the principal (run as SYSTEM)
$principal = New-ScheduledTaskPrincipal `
    -UserID "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Check if task already exists and delete it
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task: $TaskName" -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Start-Sleep -Seconds 2
}

# Register the new task
Write-Host "Creating scheduled task..." -ForegroundColor Cyan
$task = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $TaskDescription `
    -ErrorAction Stop

Write-Host "Task created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Task Details:" -ForegroundColor Cyan
Write-Host "  Name: $($task.TaskName)"
Write-Host "  Path: $($task.TaskPath)"
Write-Host "  State: $($task.State)"
Write-Host "  Next Run: $($task.Triggers[0])"
Write-Host ""
Write-Host "To verify task:" -ForegroundColor Yellow
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Select-Object State, LastRunTime, NextRunTime"
Write-Host ""
Write-Host "To manually run the task now:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
