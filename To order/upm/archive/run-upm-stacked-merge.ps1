param(
    [string]$OutputDir = "",

    [string]$DescriptionXlsx = "\\ger\\ec\\proj\\ha\\mmgbd\\MMGBD_PSA\\Products\\NVL\\NVL-H\\Analysis\\NVLS Astep Bstep\\NVL_C_B0_4P+8E_ARIES.xlsx",
    [string]$RealCsv = "\\ger\\ec\\proj\\ha\\mmgbd\\MMGBD_PSA\\Products\\NVL\\NVL-H\\Analysis\\NVLS Astep Bstep\\2026_nvls Parametric query SORT.csv",
    [string]$RequiredUpmsXlsx = "\\ger\\ec\\proj\\ha\\mmgbd\\MMGBD_PSA\\Products\\NVL\\NVL-H\\Analysis\\NVLS Astep Bstep\\required UPMS.xlsx"
)

$analysisRoot = "\\ger\\ec\\proj\\ha\\mmgbd\\MMGBD_PSA\\Products\\NVL\\NVL-H\\Analysis"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputDir = Join-Path $analysisRoot ("upm_stacked_merge_{0}" -f $stamp)
}

$psScriptPath = Join-Path $PSScriptRoot "build-upm-stacked-merge.ps1"
if (-not (Test-Path -LiteralPath $psScriptPath)) {
    throw "PowerShell script not found: $psScriptPath"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "Running UPM stacked merge pipeline..."
& "$psScriptPath" `
    -DescriptionXlsx "$DescriptionXlsx" `
    -RealCsv "$RealCsv" `
    -RequiredUpmsXlsx "$RequiredUpmsXlsx" `
    -OutputDir "$OutputDir"

if (-not $?) {
    throw "UPM stacked merge pipeline failed."
}

Write-Host "Completed. Outputs are in: $OutputDir"
