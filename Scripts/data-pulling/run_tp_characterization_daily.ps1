param(
    [string]$Python = 'C:\Users\hmarkovi\AppData\Local\Programs\Python\Python312\python.exe',
    [string]$OutDir = 'R:\Products\NVL\NVL-AX\Weekly data pull',
    [switch]$Register,
    [string]$At = '06:30'
)

$script = Join-Path $PSScriptRoot '..\parametric-analysis\parametric-tabs\build_tp_characterization.py'
$taskName = 'NVLAX_TP_Characterization_Daily'

if ($Register) {
    $self = (Resolve-Path $MyInvocation.MyCommand.Path).Path
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "Registered '$taskName' daily at $At (runs as current user, only when logged on)."
    return
}

$logDir = Join-Path $OutDir 'TP_characterization_logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir ("tp_characterization_{0:yyyyMMdd}.log" -f (Get-Date))
# --refresh re-parses every TP so Atlas dates and fuse folder dates stay current.
& $Python $script --refresh --out-dir $OutDir *>&1 | Tee-Object -FilePath $log
exit $LASTEXITCODE
