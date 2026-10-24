<#
.SYNOPSIS
Check whether the NVLAX62A0H25 5AM automation completed successfully and trigger a recovery run if it did not.

.DESCRIPTION
Performs a midday validation for the NVLAX daily workflow. It checks the output share for fresh status,
UPS VF, ILAS, and merged-output artifacts, and flags the run if any expected artifact is stale or missing.
If validation fails, it calls the production NVLAX recovery script to fill the missing-day gap.

The watchdog matches the current production NVLAX defaults:
- ProgramPattern: NVLAX62A0H25*
- LastNDaysTestEnd: 7
- OutputDirectory: \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Weekly data pull",
    [string]$ProgramPattern = "NVLAX62A0H25*",
    [int]$LastNDaysTestStart = 0,
    [int]$LastNDaysTestEnd = 7,
    [int]$AquaPullTimeoutSeconds = 1800,
    [int]$AquaPullPollSeconds = 10,
    [double]$FreshnessThresholdHours = 12,
    [string]$RecoveryScriptPath = "",
    [string]$IlasScriptPath = "",
    [string]$MergeScriptPath = "",
    [switch]$DryRun,
    [switch]$SkipRecovery
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-WarningLogEntry {
    param(
        [string]$LogPath,
        [string]$Message,
        [string]$FailureType,
        [string]$CheckTime,
        [bool]$RecoveryTriggered
    )

    $line = @(
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"),
        $FailureType,
        $CheckTime,
        $RecoveryTriggered,
        $Message
    ) -join " | "

    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Test-FileIsFresh {
    param(
        [System.IO.FileInfo]$File,
        [datetime]$Cutoff
    )

    if ($null -eq $File) {
        return $false
    }

    return $File.LastWriteTime -ge $Cutoff
}

function Test-DirectoryIsFresh {
    param(
        [System.IO.DirectoryInfo]$Directory,
        [datetime]$Cutoff
    )

    if ($null -eq $Directory) {
        return $false
    }

    return $Directory.LastWriteTime -ge $Cutoff
}

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($RecoveryScriptPath)) {
    $RecoveryScriptPath = Join-Path $scriptDir "aqua_nvlax_weekly_pull.ps1"
}
if ([string]::IsNullOrWhiteSpace($IlasScriptPath)) {
    $scriptsRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent
    $IlasScriptPath = Join-Path $scriptsRoot "parametric-analysis\ilas\aqua_nvlax_ilas_vmin_analysis.ps1"
}
if ([string]::IsNullOrWhiteSpace($MergeScriptPath)) {
    $scriptsRoot = Split-Path (Split-Path $scriptDir -Parent) -Parent
    $MergeScriptPath = Join-Path $scriptsRoot "utility\merge-ilas-into-upsvf.ps1"
}

if (-not (Test-Path -LiteralPath $RecoveryScriptPath)) {
    throw "Recovery script not found: $RecoveryScriptPath"
}
if (-not (Test-Path -LiteralPath $IlasScriptPath)) {
    throw "ILAS script not found: $IlasScriptPath"
}
if (-not (Test-Path -LiteralPath $MergeScriptPath)) {
    throw "Merge script not found: $MergeScriptPath"
}

$checkTime = Get-Date
$cutoff = $checkTime.AddHours(-$FreshnessThresholdHours)
$statusCsvPath = Join-Path $OutputDirectory "Weekly_Run_Status.csv"
$watchdogAuditCsv = Join-Path $OutputDirectory "NVLAX_daily_watchdog_audit.csv"
$watchdogWarningLog = Join-Path $OutputDirectory ("NVLAX_daily_watchdog_warning_{0}.log" -f $checkTime.ToString("yyyyMMdd_HHmmss"))

$failureType = "SUCCESS"
$missingArtifacts = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $failureType = "automation"
    $missingArtifacts.Add("OutputDirectoryMissing")
    $notes.Add("Output directory does not exist: $OutputDirectory")
}
else {
    $items = Get-ChildItem -LiteralPath $OutputDirectory -Force -ErrorAction SilentlyContinue
    if ($null -eq $items -or $items.Count -eq 0) {
        $failureType = "automation"
        $missingArtifacts.Add("OutputDirectoryEmpty")
        $notes.Add("Output directory exists but contains no files.")
    }
}

$statusFileExists = Test-Path -LiteralPath $statusCsvPath
if (-not $statusFileExists) {
    $failureType = "automation"
    $missingArtifacts.Add("Weekly_Run_Status.csv")
    $notes.Add("Status CSV is missing from the output directory.")
}

$latestStatus = $null
if ($statusFileExists) {
    $statusRows = @(Import-Csv -LiteralPath $statusCsvPath)
    if ($statusRows.Count -gt 0) {
        $latestStatus = $statusRows | Sort-Object { [datetime]::Parse($_.RunTimestamp) } | Select-Object -Last 1
        $latestStatusTimestamp = [datetime]::Parse($latestStatus.RunTimestamp)
        if ($latestStatusTimestamp -lt $cutoff) {
            $failureType = "stale_run"
            $missingArtifacts.Add("StatusStale")
            $notes.Add("Latest status entry is older than $FreshnessThresholdHours hours.")
        }

        if ($latestStatus.IlasStatus -eq "FAILED") {
            $failureType = "merge"
            $missingArtifacts.Add("IlasStatusFailed")
            $notes.Add("Latest status shows ILAS failed: $($latestStatus.IlasMessage)")
        }

        if ($latestStatus.IlasStatus -eq "WAITING_FOR_DATA") {
            $failureType = "merge"
            $missingArtifacts.Add("IlasWaitingForData")
            $notes.Add("Latest status shows ILAS data is still unavailable.")
        }
    }
    else {
        $failureType = "automation"
        $missingArtifacts.Add("StatusCsvEmpty")
        $notes.Add("Status CSV exists but contains no rows.")
    }
}

$vminFiles = @()
if (Test-Path -LiteralPath $OutputDirectory) {
    $vminFiles = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter "Vmin_*.csv" -ErrorAction SilentlyContinue)
}
$freshVmin = $false
$latestVmin = $null
if ($vminFiles.Count -gt 0) {
    $latestVmin = $vminFiles | Sort-Object LastWriteTime | Select-Object -Last 1
    $freshVmin = Test-FileIsFresh -File $latestVmin -Cutoff $cutoff
    if (-not $freshVmin) {
        $failureType = "automation"
        $missingArtifacts.Add("VminStale")
        $notes.Add("No fresh Vmin CSV exists in the output directory within the last $FreshnessThresholdHours hours.")
    }
}
else {
    $failureType = "automation"
    $missingArtifacts.Add("VminCsvMissing")
    $notes.Add("No Vmin CSV file exists in the output directory.")
}

$ilasDirectories = @()
if (Test-Path -LiteralPath $OutputDirectory) {
    $ilasDirectories = @(Get-ChildItem -LiteralPath $OutputDirectory -Directory -Filter "_ilas_weekly_*" -ErrorAction SilentlyContinue)
}
$freshIlas = $false
$latestIlasDir = $null
if ($ilasDirectories.Count -gt 0) {
    $latestIlasDir = $ilasDirectories | Sort-Object LastWriteTime | Select-Object -Last 1
    $freshIlas = Test-DirectoryIsFresh -Directory $latestIlasDir -Cutoff $cutoff
    if (-not $freshIlas) {
        $failureType = "automation"
        $missingArtifacts.Add("IlasDirectoryStale")
        $notes.Add("No fresh ILAS directory exists in the output directory within the last $FreshnessThresholdHours hours.")
    }
}
else {
    $failureType = "automation"
    $missingArtifacts.Add("IlasDirectoryMissing")
    $notes.Add("No _ilas_weekly_* directory exists in the output directory.")
}

$finalMergedCsvPath = $null
if ($latestStatus -and -not [string]::IsNullOrWhiteSpace($latestStatus.FinalOutputCsvPath)) {
    $finalMergedCsvPath = $latestStatus.FinalOutputCsvPath
    if (-not (Test-Path -LiteralPath $finalMergedCsvPath)) {
        $failureType = "merge"
        $missingArtifacts.Add("FinalMergedCsvMissing")
        $notes.Add("Final merged CSV path recorded in status is missing: $finalMergedCsvPath")
    }
}
else {
    $failureType = "merge"
    $missingArtifacts.Add("FinalMergedCsvMissing")
    $notes.Add("No final merged CSV path was recorded in the latest status row.")
}

$failureClass = if ($failureType -eq "SUCCESS") { "SUCCESS" } else { $failureType }
$recoveryExecuted = $false
$recoveryResult = "NOT_RUN"
$recoveryMessage = ""

if ($failureType -ne "SUCCESS") {
    if (-not $DryRun -and -not $SkipRecovery) {
        $recoveryExecuted = $true
        $recoveryMessage = "Triggered recovery script: $RecoveryScriptPath"
        $recoveryArgs = @(
            "-OutputDirectory", $OutputDirectory,
            "-ProgramPattern", $ProgramPattern,
            "-LastNDaysTestStart", [string]$LastNDaysTestStart,
            "-LastNDaysTestEnd", [string]$LastNDaysTestEnd,
            "-AquaPullTimeoutSeconds", [string]$AquaPullTimeoutSeconds,
            "-AquaPullPollSeconds", [string]$AquaPullPollSeconds,
            "-IlasScriptPath", $IlasScriptPath,
            "-MergeScriptPath", $MergeScriptPath
        )

        try {
            & $RecoveryScriptPath @recoveryArgs
            $recoveryResult = "SUCCESS"
        }
        catch {
            $recoveryResult = "FAILED"
            $recoveryMessage = $_.Exception.Message
            $notes.Add("Recovery trigger raised an exception: $recoveryMessage")
        }
    }
    else {
        $recoveryResult = "SKIPPED"
        $recoveryMessage = "DryRun or SkipRecovery set; no recovery script executed."
    }
}

if (-not (Test-Path -Path $OutputDirectory)) {
    $notes.Add("Unable to write warning log because the output directory was missing.")
}
else {
    $warningLines = @(
        "NVLAX Daily Watchdog Check",
        "Time: $checkTime",
        "OutputDirectory: $OutputDirectory",
        "FailureClass: $failureClass",
        "FreshnessThresholdHours: $FreshnessThresholdHours",
        "StatusCsvPath: $statusCsvPath",
        "RecoveryScriptPath: $RecoveryScriptPath",
        "RecoveryExecuted: $recoveryExecuted",
        "RecoveryResult: $recoveryResult",
        "MissingArtifacts: $($missingArtifacts -join '; ')",
        "Notes: $($notes -join '; ')"
    )
    Add-Content -LiteralPath $watchdogWarningLog -Value ($warningLines -join [Environment]::NewLine) -Encoding UTF8
}

$auditRow = [pscustomobject]@{
    CheckTimestamp = $checkTime.ToString("yyyy-MM-dd HH:mm:ss zzz")
    Status = if ($failureType -eq "SUCCESS") { "SUCCESS" } else { "FAILURE" }
    FailureType = $failureClass
    OutputDirectory = $OutputDirectory
    FreshnessThresholdHours = $FreshnessThresholdHours
    StatusCsvPresent = $statusFileExists
    StatusCsvLastWriteTime = if ($statusFileExists) { (Get-Item -LiteralPath $statusCsvPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss zzz") } else { "" }
    LatestStatusRunTimestamp = if ($latestStatus) { $latestStatus.RunTimestamp } else { "" }
    LatestStatusIlasStatus = if ($latestStatus) { $latestStatus.IlasStatus } else { "" }
    VminCsvPresent = ($vminFiles.Count -gt 0)
    LatestVminCsv = if ($latestVmin) { $latestVmin.FullName } else { "" }
    LatestVminLastWriteTime = if ($latestVmin) { $latestVmin.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss zzz") } else { "" }
    IlasDirectoryPresent = ($ilasDirectories.Count -gt 0)
    LatestIlasDirectory = if ($latestIlasDir) { $latestIlasDir.FullName } else { "" }
    LatestIlasLastWriteTime = if ($latestIlasDir) { $latestIlasDir.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss zzz") } else { "" }
    FinalMergedCsvPresent = if ($finalMergedCsvPath) { (Test-Path -LiteralPath $finalMergedCsvPath) } else { $false }
    FinalMergedCsvPath = if ($finalMergedCsvPath) { $finalMergedCsvPath } else { "" }
    MissingArtifacts = ($missingArtifacts -join '; ')
    RecoveryTriggered = $recoveryExecuted
    RecoveryResult = $recoveryResult
    Notes = ($notes -join '; ')
}

if (Test-Path -LiteralPath $watchdogAuditCsv) {
    $auditRow | Export-Csv -LiteralPath $watchdogAuditCsv -Append -NoTypeInformation
}
else {
    $auditRow | Export-Csv -LiteralPath $watchdogAuditCsv -NoTypeInformation
}

Write-Host "NVLAX daily watchdog check complete."
Write-Host "Status: $($auditRow.Status)"
Write-Host "FailureType: $($auditRow.FailureType)"
Write-Host "Audit CSV: $watchdogAuditCsv"
Write-Host "Warning log: $watchdogWarningLog"

if ($failureType -ne "SUCCESS") {
    Write-Warning "NVLAX daily automation validation failed. Recovery executed: $recoveryExecuted. Result: $recoveryResult"
    exit 1
}

Write-Host "NVLAX daily automation validation passed."
exit 0
