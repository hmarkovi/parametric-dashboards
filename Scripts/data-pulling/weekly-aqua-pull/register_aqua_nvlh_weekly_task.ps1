param(
    [string]$TaskName = "Aqua NVLH Weekly Pull",
    [string]$ScriptPath = "C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\data-pulling\weekly-aqua-pull\aqua_nvlh_weekly_pull.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script file not found: $ScriptPath"
}

$scriptDirectory = Split-Path -Path $ScriptPath -Parent

$tz = Get-TimeZone
if ($tz.Id -ne "Israel Standard Time") {
    Write-Warning "Current machine timezone is '$($tz.Id)'. Task Scheduler runs in local machine time."
    Write-Warning "For 05:00 Israel time, set the machine timezone to Israel Standard Time or adjust schedule manually."
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WorkingDirectory $scriptDirectory
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "05:00"
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Weekly AQUA pull and cleaning for NVL-H" -Force | Out-Null

Write-Host "Scheduled task registered: $TaskName"
Write-Host "Schedule: Sunday 05:00 (machine local timezone: $($tz.DisplayName))"
Write-Host "Script: $ScriptPath"
