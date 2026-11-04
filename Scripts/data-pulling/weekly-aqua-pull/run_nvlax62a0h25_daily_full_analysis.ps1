<#
.SYNOPSIS
Run the daily full NVLAX62A0H25 UPSVF+ILAS analysis with fixed production defaults.

.DESCRIPTION
Wrapper around aqua_nvlax_weekly_pull.ps1 that uses the current NVLAX UPSVF+ILAS infrastructure
with the requested production filters:
- Program filter: NVLAX62A0H25*
- Date filter: last 4 days Test Start
- Output share: R:\Products\NVL\NVL-AX\Weekly data pull

The final output CSV contains the UPSVF Vmin data plus merged ILAS DTS and limiter analysis columns.
#>

param(
    [string]$ProgramPattern = "NVLAX62A0H25*",
    [int]$LastNDaysTestStart = 0,
    [int]$LastNDaysTestEnd = 7,
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull",
    [int]$AquaPullTimeoutSeconds = 1800,
    [int]$AquaPullPollSeconds = 10,
    [string]$WeeklyScriptPath = "",
    [string]$IlasScriptPath = "",
    [string]$MergeScriptPath = "",
    [switch]$KeepCleanCsvArtifact,
    # After a successful pull, rebuild the aggregate parametric HTML from By-Class-TP-final + the daily Vmin_YYYYMMDD.csv files.
    [switch]$SkipReport,
    [string]$Python = "C:\Users\hmarkovi\AppData\Local\Programs\Python\Python312\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent

if ([string]::IsNullOrWhiteSpace($WeeklyScriptPath)) {
    $WeeklyScriptPath = Join-Path $scriptDir "aqua_nvlax_weekly_pull.ps1"
}
if ([string]::IsNullOrWhiteSpace($IlasScriptPath)) {
    $IlasScriptPath = Join-Path $scriptsRoot "parametric-analysis\ilas\aqua_nvlax_ilas_vmin_analysis.ps1"
}
if ([string]::IsNullOrWhiteSpace($MergeScriptPath)) {
    $MergeScriptPath = Join-Path $scriptsRoot "utility\merge-ilas-into-upsvf.ps1"
}

if (-not (Test-Path -LiteralPath $WeeklyScriptPath)) {
    throw "Weekly script not found: $WeeklyScriptPath"
}
if (-not (Test-Path -LiteralPath $IlasScriptPath)) {
    throw "ILAS script not found: $IlasScriptPath"
}
if (-not (Test-Path -LiteralPath $MergeScriptPath)) {
    throw "Merge script not found: $MergeScriptPath"
}

& $WeeklyScriptPath `
    -ProgramPattern $ProgramPattern `
    -LastNDaysTestStart $LastNDaysTestStart `
    -LastNDaysTestEnd $LastNDaysTestEnd `
    -OutputDirectory $OutputDirectory `
    -AquaPullTimeoutSeconds $AquaPullTimeoutSeconds `
    -AquaPullPollSeconds $AquaPullPollSeconds `
    -IlasScriptPath $IlasScriptPath `
    -MergeScriptPath $MergeScriptPath `
    -KeepCleanCsvArtifact:$KeepCleanCsvArtifact

# The pull succeeded (a failure above throws and skips this step). A report failure never fails the pull.
if (-not $SkipReport) {
    $ErrorActionPreference = "Continue"
    try {
        # Mapped drive letters do not exist in a non-interactive logon session; the report builder reads PreSi models from R:.
        $shares = @{ 'R' = '\\ger\ec\proj\ha\mmgbd\MMGBD_PSA'; 'I' = '\\ger\ec\proj\mdl\ha\intel' }
        foreach ($d in $shares.Keys) {
            if (-not (Test-Path "${d}:\")) { net use "${d}:" $shares[$d] /persistent:no | Out-Null }
        }
        $reportScript = Join-Path $scriptsRoot "parametric-analysis\parametric-tabs\build_daily_report.py"
        $logDir = Join-Path $OutputDirectory "Daily_report_logs"
        New-Item -ItemType Directory -Force $logDir | Out-Null
        $log = Join-Path $logDir ("daily_report_{0:yyyyMMdd}.log" -f (Get-Date))
        $env:PYTHONIOENCODING = "utf-8"
        & $Python $reportScript --root $OutputDirectory 2>&1 | Tee-Object -FilePath $log -Append | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-Warning "Daily parametric report failed (exit $LASTEXITCODE); see $log" }
        Get-ChildItem -LiteralPath $logDir -Filter "daily_report_*.log" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Daily parametric report step failed: $($_.Exception.Message)"
    }
}
