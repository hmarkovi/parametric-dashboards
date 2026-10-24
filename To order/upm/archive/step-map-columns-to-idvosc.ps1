param(
    [string]$RelevantColsCsv = 'R:\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep\upm_relevant_columns_detected.csv',
    [string]$AriesXlsx       = '\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep\NVL_C_B0_4P+8E_ARIES.xlsx',
    [string]$OutputDir       = 'R:\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Step A: Loading relevant UPM column list from checkpoint..."
if (-not (Test-Path -LiteralPath $RelevantColsCsv)) { throw "Relevant columns file not found: $RelevantColsCsv" }

$upmCols = Import-Csv -LiteralPath $RelevantColsCsv
Write-Host ("  Loaded {0} relevant UPM columns." -f $upmCols.Count)

# Index by UPM ID for cross-match
$byUpmId = @{}
foreach ($row in $upmCols) {
    $id = $row.UpmId.Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    if (-not $byUpmId.ContainsKey($id)) { $byUpmId[$id] = [System.Collections.Generic.List[object]]::new() }
    $byUpmId[$id].Add($row)
}
Write-Host ("  Unique UPM IDs in column list: {0}" -f $byUpmId.Count)

Write-Host "Step B: Reading IDV Osc tab from ARIES workbook..."
$excel    = $null
$workbook = $null
$sheet    = $null
$range    = $null
$idvRows  = [System.Collections.Generic.List[pscustomobject]]::new()

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Open($AriesXlsx)
    $sheet    = $workbook.Worksheets.Item('IDV Osc')
    $range    = $sheet.UsedRange

    $rowCount = [int]$range.Rows.Count
    $colCount = [int]$range.Columns.Count
    Write-Host ("  IDV Osc sheet: {0} rows x {1} cols" -f $rowCount, $colCount)

    $headers = @()
    for ($c = 1; $c -le $colCount; $c++) {
        $h = ([string]$sheet.Cells.Item(1, $c).Text).Trim()
        $headers += if ([string]::IsNullOrWhiteSpace($h)) { "COL_$c" } else { $h }
    }

    for ($r = 2; $r -le $rowCount; $r++) {
        $o = [ordered]@{}
        for ($c = 1; $c -le $colCount; $c++) {
            $o[$headers[$c-1]] = ([string]$sheet.Cells.Item($r, $c).Text).Trim()
        }
        $idvRows.Add([pscustomobject]$o)
    }
    Write-Host ("  Loaded {0} IDV Osc data rows." -f $idvRows.Count)
}
finally {
    if ($workbook) { $workbook.Close($false) }
    if ($excel)    { $excel.Quit() }
    if ($range)    { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($range) }
    if ($sheet)    { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
    if ($workbook) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
    if ($excel)    { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
}

# Save raw IDV Osc table
$idvRawPath = Join-Path $OutputDir 'idvosc_raw_table.csv'
$idvRows | Export-Csv -LiteralPath $idvRawPath -NoTypeInformation -Encoding UTF8
Write-Host "  IDV Osc raw table saved: $idvRawPath"

# Build IDV Osc index keyed by Description Tag (COL_6) - the actual match key
# COL_6 contains e.g. "DPMH156P48ULVTINVD2" which maps to class+lib+VT+stdcell in the UPM column name
$idvByTag  = @{}   # key = COL_6 uppercased (exact match)
$idvAllRows = @()
$ri = 0
foreach ($r in $idvRows) {
    $tag = ([string]$r.'COL_6').Trim().ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($tag)) {
        if (-not $idvByTag.ContainsKey($tag)) { $idvByTag[$tag] = $r }
    }
    $idvAllRows += [pscustomobject]@{ RowIndex=$ri; Tag=$tag; Raw=$r }
    $ri++
}
Write-Host ("  IDV Osc description tags indexed: {0} unique tags." -f $idvByTag.Count)

Write-Host "Step C: Cross-matching UPM columns to IDV Osc rows..."
$matchedRows   = [System.Collections.Generic.List[pscustomobject]]::new()
$unmatchedRows = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($col in $upmCols) {
    # Build the tag string the same way IDV Osc stores it: CLASS + LIB + VT + STDCELL (no separators, uppercase)
    $tag = ($col.ClassType + $col.Lib + $col.VtType + $col.StdCell).ToUpperInvariant()

    $matchedIdv = $null
    $matchScore = 0

    # 1. Exact tag match
    if ($idvByTag.ContainsKey($tag)) {
        $matchedIdv = $idvByTag[$tag]
        $matchScore = 100
    }

    # 2. Fallback: tag without VT (some entries may not embed VT in tag)
    if (-not $matchedIdv) {
        $tagNoVt = ($col.ClassType + $col.Lib + $col.StdCell).ToUpperInvariant()
        if ($idvByTag.ContainsKey($tagNoVt)) {
            $matchedIdv = $idvByTag[$tagNoVt]
            $matchScore = 80
        }
    }

    # 3. Fallback: scan all tags for best substring match
    if (-not $matchedIdv) {
        $best = $null; $bestScore = -1
        foreach ($ir in $idvAllRows) {
            $score = 0
            if ($ir.Tag -and $col.ClassType -and $ir.Tag.Contains($col.ClassType)) { $score += 20 }
            if ($ir.Tag -and $col.VtType    -and $ir.Tag.Contains($col.VtType))    { $score += 20 }
            if ($ir.Tag -and $col.StdCell   -and $ir.Tag.Contains($col.StdCell.ToUpperInvariant())) { $score += 40 }
            if ($score -gt $bestScore) { $bestScore = $score; $best = $ir }
        }
        if ($best -and $bestScore -ge 60) { $matchedIdv = $best.Raw; $matchScore = $bestScore }
    }

    if ($matchedIdv) {
        $o = [ordered]@{
            UPM_COLUMN     = $col.ColumnName
            UPM_ID         = $col.UpmId
            UPM_CLASS      = $col.ClassType
            UPM_VT         = $col.VtType
            UPM_LIB        = $col.Lib
            UPM_STDCELL    = $col.StdCell
            IDVOSC_TAG_KEY = $tag
            MATCH_SCORE    = $matchScore
        }
        foreach ($p in $matchedIdv.PSObject.Properties.Name) {
            $o["IDVOSC_$p"] = $matchedIdv.$p
        }
        $matchedRows.Add([pscustomobject]$o)
    } else {
        $unmatchedRows.Add([pscustomobject]@{
            UPM_COLUMN     = $col.ColumnName
            UPM_ID         = $col.UpmId
            UPM_CLASS      = $col.ClassType
            UPM_VT         = $col.VtType
            UPM_LIB        = $col.Lib
            UPM_STDCELL    = $col.StdCell
            IDVOSC_TAG_KEY = $tag
        })
    }
}

$matchedPath   = Join-Path $OutputDir 'upm_column_to_idvosc_mapping.csv'
$unmatchedPath = Join-Path $OutputDir 'upm_column_idvosc_unmatched.csv'

$matchedRows   | Export-Csv -LiteralPath $matchedPath   -NoTypeInformation -Encoding UTF8
$unmatchedRows | Export-Csv -LiteralPath $unmatchedPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host ("Done. Matched: {0}  Unmatched: {1}" -f $matchedRows.Count, $unmatchedRows.Count)
Write-Host "- IDV Osc raw table:     $idvRawPath"
Write-Host "- Column->IDV mapping:   $matchedPath"
Write-Host "- Unmatched columns:     $unmatchedPath"
