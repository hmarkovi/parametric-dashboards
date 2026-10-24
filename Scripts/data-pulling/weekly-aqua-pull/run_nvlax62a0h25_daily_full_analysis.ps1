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
    [switch]$KeepCleanCsvArtifact
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
