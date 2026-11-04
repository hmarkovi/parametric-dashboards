param(
    [string]$Python = 'C:\Users\hmarkovi\AppData\Local\Programs\Python\Python312\python.exe',
    [string]$OutDir = 'R:\Products\NVL\NVL-AX\Weekly data pull',
    [switch]$Register,
    # With -Register: run whether the user is logged on or not (Windows asks for the password; Task Scheduler stores it).
    [switch]$Unattended,
    [string]$At = '06:30'
)

$script = Join-Path $PSScriptRoot '..\parametric-analysis\parametric-tabs\build_tp_characterization.py'
$taskName = 'NVLAX_TP_Characterization_Daily'

if ($Register) {
    $self = (Resolve-Path $MyInvocation.MyCommand.Path).Path
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    if ($Unattended) {
        # S4U has no network credentials (R:/I: shares fail), so a stored-password logon is required.
        $cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message 'Windows password for the unattended task (stored by Task Scheduler)'
        $settings.WakeToRun = $true
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
            -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Force | Out-Null
        Write-Host "Registered '$taskName' daily at $At (runs whether logged on or not; wakes the PC; password stored)."
    } else {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        Write-Host "Registered '$taskName' daily at $At (runs as current user, only when logged on)."
    }
    return
}

# Mapped drive letters do not exist in a non-interactive logon session: map the shares the job needs when missing.
$shares = @{ 'R' = '\\ger\ec\proj\ha\mmgbd\MMGBD_PSA'; 'I' = '\\ger\ec\proj\mdl\ha\intel' }
foreach ($d in $shares.Keys) {
    if (-not (Test-Path "${d}:\")) { net use "${d}:" $shares[$d] /persistent:no | Out-Null }
}
$logDir = Join-Path $OutDir 'TP_characterization_logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir ("tp_characterization_{0:yyyyMMdd}.log" -f (Get-Date))
# --refresh re-parses every TP so Atlas dates and fuse folder dates stay current.
& $Python $script --refresh --out-dir $OutDir *>&1 | Tee-Object -FilePath $log
exit $LASTEXITCODE
