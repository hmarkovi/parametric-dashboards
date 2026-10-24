#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-AX\Weekly data pull",
    [string[]]$WorkWeeks = @("WW33_2026", "WW34_2026", "WW35_2026"),
    [int]$MaxWorkWeeks = 3,
    [string]$RetainedFolderName = "By-Class-TP-final",
    [string]$ManifestFolderName = "pilot_cleanup_manifests",
    [switch]$DeleteOriginals
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$engineScript = Join-Path $scriptDir "start_nvlh_weekly_pilot_cleanup.ps1"

if (-not (Test-Path -LiteralPath $engineScript -PathType Leaf)) {
    throw "Engine cleanup script not found: $engineScript"
}

Write-Host "Running NVLAX weekly pilot cleanup engine" -ForegroundColor Cyan
Write-Host "Root: $WeeklyRunsDir"
Write-Host "WorkWeeks: $($WorkWeeks -join ', ')"

& $engineScript `
    -WeeklyRunsDir $WeeklyRunsDir `
    -WorkWeeks $WorkWeeks `
    -MaxWorkWeeks $MaxWorkWeeks `
    -RetainedFolderName $RetainedFolderName `
    -ManifestFolderName $ManifestFolderName `
    -DeleteOriginals:$DeleteOriginals
