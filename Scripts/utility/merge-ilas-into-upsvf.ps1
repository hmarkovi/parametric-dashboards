#requires -Version 5.1
<#
.SYNOPSIS
Merge ILAS summary data into UPSVF clean CSV, preserving all UPSVF rows.

.DESCRIPTION
Loads ILAS Summary CSV and UPSVF clean CSV, merges ILAS columns by normalized 
VISUAL_ID||LOTFROMFS key. All UPSVF rows preserved in output; ILAS columns 
populated only for matching keys. Unmatched rows have empty ILAS columns.

.PARAMETER UpsvfCleanCsv
Path to UPSVF clean CSV (must have VISUAL_ID, LOTFROMFS columns)

.PARAMETER IlasSummaryCsv
Path to ILAS Summary CSV (must have VisualID, LotFromFs columns and data columns to merge)

.PARAMETER OutputCsv
Path to write merged output (all UPSVF rows + ILAS columns)

.EXAMPLE
.\merge-ilas-into-upsvf.ps1 `
  -UpsvfCleanCsv "R:\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30N00S623_WW25_2026_clean.csv" `
  -IlasSummaryCsv "C:\validation\ILAS_Vmin_Summary_WW25_2026.csv" `
  -OutputCsv "R:\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30N00S623_WW25_2026_merged.csv"
#>

param(
    [Parameter(Mandatory=$true)]
    [string] $UpsvfCleanCsv,

    [Parameter(Mandatory=$true)]
    [string] $IlasSummaryCsv,

    [Parameter(Mandatory=$true)]
    [string] $OutputCsv
)

$ErrorActionPreference = "Stop"

Write-Host "=== UPSVF + ILAS Merge ===" -ForegroundColor Green
Write-Host "UPSVF CSV: $UpsvfCleanCsv"
Write-Host "ILAS CSV:  $IlasSummaryCsv"
Write-Host "Output:    $OutputCsv"
Write-Host ""

# Validate input files
if (-not (Test-Path -LiteralPath $UpsvfCleanCsv -PathType Leaf)) {
    throw "UPSVF file not found: $UpsvfCleanCsv"
}
if (-not (Test-Path -LiteralPath $IlasSummaryCsv -PathType Leaf)) {
    throw "ILAS file not found: $IlasSummaryCsv"
}

# ===== LOAD ILAS SUMMARY =====
Write-Host "Loading ILAS Summary..." -ForegroundColor Cyan
$ilasRows = @(Import-Csv -LiteralPath $IlasSummaryCsv)
Write-Host "ILAS Summary rows: $($ilasRows.Count)"

# Detect ILAS ID columns
$ilasFirstRow = $ilasRows[0]
$vidCol = $null
$lotCol = $null

foreach ($prop in $ilasFirstRow.PSObject.Properties.Name) {
    if ($prop -eq "VisualID" -or $prop -eq "VISUAL_ID" -or $prop -eq "Visual_ID") {
        $vidCol = $prop
    }
    if ($prop -eq "LotFromFs" -or $prop -eq "LOTFROMFS" -or $prop -eq "Lot_From_FS") {
        $lotCol = $prop
    }
}

if (-not $vidCol) {
    throw "ILAS Summary: Could not find Visual ID column. Found: $($ilasFirstRow.PSObject.Properties.Name -join ', ')"
}
if (-not $lotCol) {
    throw "ILAS Summary: Could not find LotFromFs column. Found: $($ilasFirstRow.PSObject.Properties.Name -join ', ')"
}

Write-Host "ILAS VisualID column: '$vidCol', LotFromFs column: '$lotCol'"

# Build ILAS lookup: key = "VID||LOT", value = full row object
$ilasLookup = @{}
$ilasDataColumns = @()

foreach ($row in $ilasRows) {
    $vid = [string]($row.$vidCol).Trim().ToUpperInvariant()
    $lot = [string]($row.$lotCol).Trim().ToUpperInvariant()
    $key = "$vid||$lot"
    
    if (-not $ilasLookup.ContainsKey($key)) {
        $ilasLookup[$key] = $row
    }
}

# Detect data columns (all except ID columns)
if ($ilasDataColumns.Count -eq 0) {
    foreach ($col in $ilasFirstRow.PSObject.Properties.Name) {
        if ($col -ne $vidCol -and $col -ne $lotCol) {
            $ilasDataColumns += $col
        }
    }
}

Write-Host "ILAS unique keys: $($ilasLookup.Count)"
Write-Host "ILAS data columns to merge: $($ilasDataColumns.Count)"
Write-Host ""

# ===== LOAD UPSVF CLEAN =====
Write-Host "Loading UPSVF Clean..." -ForegroundColor Cyan
$upsvfRows = @(Import-Csv -LiteralPath $UpsvfCleanCsv)
Write-Host "UPSVF rows: $($upsvfRows.Count)"

# Detect UPSVF ID columns
$upsvfFirstRow = $upsvfRows[0]
$upsvfVidCol = $null
$upsvfLotCol = $null

foreach ($prop in $upsvfFirstRow.PSObject.Properties.Name) {
    if ($prop -eq "VISUAL_ID" -or $prop -eq "VisualID" -or $prop -eq "Visual_ID") {
        $upsvfVidCol = $prop
    }
    if ($prop -eq "LOTFROMFS" -or $prop -eq "LotFromFs" -or $prop -eq "Lot_From_FS") {
        $upsvfLotCol = $prop
    }
}

if (-not $upsvfVidCol) {
    throw "UPSVF: Could not find Visual ID column. Found: $($upsvfFirstRow.PSObject.Properties.Name | Select-Object -First 10 | ForEach-Object { "'$_'" } | Join-String -Separator ', ')"
}
if (-not $upsvfLotCol) {
    throw "UPSVF: Could not find LotFromFs column. Found: $($upsvfFirstRow.PSObject.Properties.Name | Select-Object -First 10 | ForEach-Object { "'$_'" } | Join-String -Separator ', ')"
}

Write-Host "UPSVF VisualID column: '$upsvfVidCol', LotFromFs column: '$upsvfLotCol'"
Write-Host ""

# ===== MERGE =====
Write-Host "Merging..." -ForegroundColor Cyan
$matchCount = 0
$noMatchCount = 0
# Stream rows to Export-Csv to avoid large in-memory growth from "$mergedRows += ...".
$mergedRowCount = 0

$upsvfRows |
    ForEach-Object {
        $row = $_
        $vid = [string]($row.$upsvfVidCol).Trim().ToUpperInvariant()
        $lot = [string]($row.$upsvfLotCol).Trim().ToUpperInvariant()
        $key = "$vid||$lot"

        # Keep original UPSVF columns first, then append ILAS_* columns.
        $mergedMap = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $mergedMap[$prop.Name] = $prop.Value
        }

        if ($ilasLookup.ContainsKey($key)) {
            $ilasRow = $ilasLookup[$key]
            foreach ($col in $ilasDataColumns) {
                $mergedMap["ILAS_$col"] = $ilasRow.$col
            }
            $matchCount++
        }
        else {
            foreach ($col in $ilasDataColumns) {
                $mergedMap["ILAS_$col"] = ""
            }
            $noMatchCount++
        }

        $mergedRowCount++
        [pscustomobject]$mergedMap
    } |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Matched rows with ILAS data: $matchCount"
Write-Host "Unmatched rows (ILAS columns empty): $noMatchCount"
Write-Host "Total merged rows: $mergedRowCount"
Write-Host ""

# ===== WRITE OUTPUT =====
Write-Host "Writing merged CSV..." -ForegroundColor Cyan

$outputFile = Get-Item -LiteralPath $OutputCsv
$sizeMB = [math]::Round($outputFile.Length / 1MB, 2)
Write-Host "Saved: $OutputCsv"
Write-Host "Size: $sizeMB MB"
Write-Host "Modified: $($outputFile.LastWriteTime)"
Write-Host ""
Write-Host "[OK] Merge complete" -ForegroundColor Green
