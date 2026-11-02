#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-AX\Weekly data pull",
    [string[]]$WorkWeeks = @("WW33_2026", "WW34_2026", "WW35_2026"),
    [int]$MaxWorkWeeks = 3,
    [string]$RetainedFolderName = "By-Class-TP-final",
    [string]$ManifestFolderName = "pilot_cleanup_manifests",
    [switch]$DeleteOriginals,
    [switch]$SkipValidation,
    [string]$PythonExe = "",
    [switch]$UpdateParquetStore,
    [int]$ParquetMaxUnits = 15000
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
    -DeleteOriginals:$DeleteOriginals `
    -SkipValidation:$SkipValidation `
    -PythonExe $PythonExe

if ($UpdateParquetStore) {
    # Post-organization step (opt-in): ingest per-TP CSVs into the Parquet store, report retention (no deletion), build the single HTML.
    $py = if ($PythonExe) { $PythonExe } else { "python" }
    $storeScript = Join-Path $scriptDir "..\..\parametric-analysis\parametric-tabs\weekly_parquet_store.py"
    $csvDir = Join-Path $WeeklyRunsDir $RetainedFolderName
    $store = Join-Path $WeeklyRunsDir "Parquet_store"
    Write-Host "Updating Parquet store: $store" -ForegroundColor Cyan
    & $py $storeScript run --csv-dir $csvDir --store $store --max-units $ParquetMaxUnits
    if ($LASTEXITCODE -ne 0) { throw "Parquet store update failed (exit $LASTEXITCODE)" }
}
