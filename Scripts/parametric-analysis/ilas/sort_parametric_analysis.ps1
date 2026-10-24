<#
.SYNOPSIS
Sort parametric analysis entry script.

.DESCRIPTION
Current implementation runs Step-1 raw Vmin extraction.
Future steps (SICC and Cdyn) should be added here.
#>

param(
    [string]$InputCsvPath = "R:\Products\NVL\NVL-AX\Analysis\2026_31_NVLAX_first hub sort data.csv",
    [string]$OutputDirectory = "R:\Products\NVL\NVL-AX\Analysis\Sort data analysis"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vminStepScript = Join-Path $scriptDir "sort_parametric_analysis_vmin_raw.ps1"

if (-not (Test-Path -LiteralPath $vminStepScript)) {
    throw "Required step script not found: $vminStepScript"
}

& $vminStepScript -InputCsvPath $InputCsvPath -OutputDirectory $OutputDirectory
