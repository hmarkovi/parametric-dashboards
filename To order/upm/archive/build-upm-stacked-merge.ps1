param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [string]$DescriptionXlsx = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep\NVL_C_B0_4P+8E_ARIES.xlsx",
    [string]$RealCsv = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep\2026_nvls Parametric query SORT.csv",
    [string]$RequiredUpmsXlsx = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Analysis\NVLS Astep Bstep\required UPMS.xlsx"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Text {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Get-FirstExistingColumnName {
    param(
        [string[]]$CandidateNames,
        [string[]]$AvailableNames
    )

    foreach ($c in $CandidateNames) {
        $m = $AvailableNames | Where-Object { $_.ToLowerInvariant() -eq $c.ToLowerInvariant() } | Select-Object -First 1
        if ($m) { return $m }
    }
    return $null
}

function Import-ExcelSheetRows {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SheetName
    )

    $excel = $null
    $workbook = $null
    $sheet = $null
    $range = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        $workbook = $excel.Workbooks.Open($Path)
        $sheet = $workbook.Worksheets.Item($SheetName)
        $range = $sheet.UsedRange

        $rowCount = [int]$range.Rows.Count
        $colCount = [int]$range.Columns.Count
        if ($rowCount -lt 2 -or $colCount -lt 1) {
            return @()
        }

        $headers = @()
        for ($c = 1; $c -le $colCount; $c++) {
            $h = Normalize-Text $sheet.Cells.Item(1, $c).Text
            if ([string]::IsNullOrWhiteSpace($h)) {
                $h = "COL_$c"
            }
            $headers += $h
        }

        $out = New-Object System.Collections.Generic.List[object]
        for ($r = 2; $r -le $rowCount; $r++) {
            $o = [ordered]@{}
            for ($c = 1; $c -le $colCount; $c++) {
                $o[$headers[$c - 1]] = Normalize-Text $sheet.Cells.Item($r, $c).Text
            }
            $out.Add([pscustomobject]$o)
        }

        return @($out)
    }
    finally {
        if ($workbook) { $workbook.Close($false) }
        if ($excel) { $excel.Quit() }
        if ($range) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($range) }
        if ($sheet) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
        if ($workbook) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
    }
}

function Import-ExcelAllSheets {
    param([Parameter(Mandatory = $true)][string]$Path)

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    try {
        $workbook = $excel.Workbooks.Open($Path)
        $result = @{}

        foreach ($sheet in $workbook.Worksheets) {
            $sheetName = [string]$sheet.Name
            $range = $null

            try {
                $range = $sheet.UsedRange
                $raw = $range.Value2

                if ($null -eq $raw) {
                    $result[$sheetName] = @()
                    continue
                }

                $rowCount = $raw.GetLength(0)
                $colCount = $raw.GetLength(1)
                if ($rowCount -lt 2) {
                    $result[$sheetName] = @()
                    continue
                }

                $headers = @()
                for ($c = 1; $c -le $colCount; $c++) {
                    $h = Normalize-Text $raw[1, $c]
                    if ([string]::IsNullOrWhiteSpace($h)) {
                        $h = "COL_$c"
                    }
                    $headers += $h
                }

                $rows = New-Object System.Collections.Generic.List[object]
                for ($r = 2; $r -le $rowCount; $r++) {
                    $o = [ordered]@{}
                    for ($c = 1; $c -le $colCount; $c++) {
                        $o[$headers[$c - 1]] = Normalize-Text $raw[$r, $c]
                    }
                    $rows.Add([pscustomobject]$o)
                }
                $result[$sheetName] = @($rows)
            }
            catch {
                Write-Warning ("Skipping non-tabular or unreadable sheet '{0}' in {1}: {2}" -f $sheetName, $Path, $_.Exception.Message)
                $result[$sheetName] = @()
            }
            finally {
                if ($range) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($range) }
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet)
            }
        }

        return $result
    }
    finally {
        if ($workbook) { $workbook.Close($false) }
        $excel.Quit()
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
    }
}

function Parse-UpmColumn {
    param([Parameter(Mandatory = $true)][string]$ColumnName)

    $upmId = ""
    if ($ColumnName -match '^UPM_(\d{4})_') {
        $upmId = $Matches[1]
    }

    $upper = $ColumnName.ToUpperInvariant()
    $classType = ""
    if ($upper.Contains('DPM')) { $classType = 'DPM' }
    elseif ($upper.Contains('TPM')) { $classType = 'TPM' }
    elseif ($upper.Contains('MPM')) { $classType = 'MPM' }

    $lib = ""
    $stdCell = ""
    foreach ($t in ($ColumnName -split '_')) {
        $tu = $t.ToUpperInvariant()
        $mToken = [regex]::Match($tu, '^(DPM|TPM|MPM)(H\d+P\d+)(ULVLL|ULVT|LVT)?([A-Z0-9]+)$')
        if ($mToken.Success) {
            $classType = $mToken.Groups[1].Value
            $lib = $mToken.Groups[2].Value
            if ($mToken.Groups[4].Success) {
                $stdCell = $mToken.Groups[4].Value
            }
            break
        }
    }

    $vtType = ""
    foreach ($vt in @('ULVLL', 'ULVT', 'LVT')) {
        if ($upper.Contains($vt)) {
            $vtType = $vt
            break
        }
    }

    $coreHint = ""
    foreach ($t in ($ColumnName -split '_')) {
        if ($t.ToUpperInvariant().Contains('CORE')) {
            $coreHint = $t
            break
        }
    }

    $voltageMv = ""
    foreach ($t in ($ColumnName -split '_')) {
        if ($t -match '^\d{3,4}$') {
            $voltageMv = $Matches[0]
            break
        }
    }

    $site = ""
    $parts = $ColumnName -split '_'
    for ($i = $parts.Count - 1; $i -ge 0; $i--) {
        if ($parts[$i] -match '^U\d+\.U\d+$') {
            $site = $parts[$i].ToUpperInvariant()
            break
        }
    }

    return [pscustomobject]@{
        ColumnName = $ColumnName
        UpmId      = $upmId
        ClassType  = $classType
        Lib        = $lib
        StdCell    = $stdCell
        VtType     = $vtType
        CoreHint   = $coreHint
        VoltageMv  = $voltageMv
        Site       = $site
    }
}

function Build-DescriptionRows {
    param([object[]]$Rows)

    $out = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($r in $Rows) {
        $props = $r.PSObject.Properties.Name
        $blob = (($props | ForEach-Object { Normalize-Text $r.$_ }) -join ' ').ToUpperInvariant()

        $upmId = ""
        if ($blob -match 'UPM_(\d{4})') {
            $upmId = $Matches[1]
        }
        elseif ($blob -match '\b(\d{4})\b') {
            $upmId = $Matches[1]
        }

        $classType = ""
        if ($blob.Contains('DPM')) { $classType = 'DPM' }
        elseif ($blob.Contains('MPM')) { $classType = 'MPM' }

        $vtType = ""
        foreach ($vt in @('ULVLL', 'ULVT', 'LVT')) {
            if ($blob.Contains($vt)) {
                $vtType = $vt
                break
            }
        }

        $raw = [ordered]@{}
        foreach ($p in $props) {
            $raw[$p] = Normalize-Text $r.$p
        }

        $out.Add([pscustomobject]@{
            Index     = $idx
            Blob      = $blob
            UpmId     = $upmId
            ClassType = $classType
            VtType    = $vtType
            Raw       = [pscustomobject]$raw
        })

        $idx++
    }

    return @($out)
}

function Get-BestDescriptionMatch {
    param(
        [Parameter(Mandatory = $true)]$ParsedUpm,
        [Parameter(Mandatory = $true)][object[]]$DescriptionRows
    )

    $best = $null
    $bestScore = -1

    foreach ($dr in $DescriptionRows) {
        $score = 0
        if ($ParsedUpm.UpmId -and $dr.UpmId -eq $ParsedUpm.UpmId) { $score += 60 }
        if ($ParsedUpm.ClassType -and $dr.ClassType -eq $ParsedUpm.ClassType) { $score += 10 }
        if ($ParsedUpm.VtType -and $dr.VtType -eq $ParsedUpm.VtType) { $score += 10 }
        if ($ParsedUpm.CoreHint -and $dr.Blob.Contains($ParsedUpm.CoreHint.ToUpperInvariant())) { $score += 6 }
        if ($ParsedUpm.Site -and $dr.Blob.Contains($ParsedUpm.Site.ToUpperInvariant())) { $score += 4 }
        if ($ParsedUpm.VoltageMv -and $dr.Blob.Contains($ParsedUpm.VoltageMv)) { $score += 4 }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $dr
        }
    }

    return [pscustomobject]@{ Match = $best; Score = $bestScore }
}

function Get-RequiredUpmRules {
    param([string]$Path)

    $rules = New-Object System.Collections.Generic.List[object]

    $excel = $null
    $workbook = $null
    $sheet = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        $workbook = $excel.Workbooks.Open($Path)
        $sheet = $workbook.Worksheets.Item('Sheet1')
        $used = $sheet.UsedRange
        $rowCount = $used.Rows.Count

        for ($r = 2; $r -le $rowCount; $r++) {
            $type = (Normalize-Text $sheet.Cells.Item($r, 1).Text).ToUpperInvariant()
            $lib = (Normalize-Text $sheet.Cells.Item($r, 2).Text).ToUpperInvariant()
            $stdCell = (Normalize-Text $sheet.Cells.Item($r, 3).Text).ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($lib) -or [string]::IsNullOrWhiteSpace($stdCell)) {
                continue
            }

            $rules.Add([pscustomobject]@{
                UpmType = $type
                Lib = $lib
                StdCell = $stdCell
            })
        }
    }
    finally {
        if ($workbook) { $workbook.Close($false) }
        if ($excel) { $excel.Quit() }
        if ($sheet) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
        if ($workbook) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
    }

    $outRules = @()
    foreach ($rule in $rules) {
        $outRules += $rule
    }
    return $outRules
}

function Test-IsRequiredUpm {
    param(
        $ParsedUpm,
        [object[]]$RequiredRules
    )

    $type = Normalize-Text $ParsedUpm.ClassType
    $lib = (Normalize-Text $ParsedUpm.Lib).ToUpperInvariant()
    $stdCell = (Normalize-Text $ParsedUpm.StdCell).ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($lib) -or [string]::IsNullOrWhiteSpace($stdCell)) {
        return $false
    }

    $isListed = $false
    foreach ($rr in $RequiredRules) {
        if ($rr.UpmType -ne $type) { continue }
        if ($rr.Lib -ne $lib) { continue }
        if ($stdCell -eq $rr.StdCell -or $stdCell.StartsWith($rr.StdCell)) {
            $isListed = $true
            break
        }
    }

    if (-not $isListed) { return $false }

    # User-requested relevance rule:
    # - DPM: ULVT / ULVLL / LVT
    # - MPM: LVT only
    if ($type -eq 'DPM') {
        if (@('ULVT', 'ULVLL', 'LVT') -contains $ParsedUpm.VtType) {
            return $true
        }
        return $false
    }

    if ($type -eq 'MPM') {
        if ($ParsedUpm.VtType -eq 'LVT') {
            return $true
        }
        return $false
    }

    # TPM and other classes are excluded from final relevant UPM set.
    return $false
}

function Get-VoltageTargetsFromDescription {
    param($RawDesc)

    $props = @($RawDesc.PSObject.Properties.Name)
    $target1V = ""
    $other = [ordered]@{}

    if ($props.Count -ge 25) {
        $yCol = $props[24]
        $target1V = Normalize-Text $RawDesc.$yCol
    }

    foreach ($p in $props) {
        $val = Normalize-Text $RawDesc.$p
        if ([string]::IsNullOrWhiteSpace($val)) { continue }

        $up = $p.ToUpperInvariant().Replace(' ', '')
        if (-not $target1V -and ($up.Contains('1V') -or $up.Contains('1.0V') -or $up.Contains('1000MV') -or $up -eq '1000')) {
            $target1V = $val
        }

        $m = [regex]::Match($p, '(?<!\d)(\d(?:\.\d+)?\s*V|\d{3,4}\s*mV|\d{3,4})(?!\d)', 'IgnoreCase')
        if ($m.Success) {
            $k = $m.Groups[1].Value.Replace(' ', '')
            if ($k -ne '1V' -and $k -ne '1.0V' -and $k -ne '1000' -and $k.ToLowerInvariant() -ne '1000mv') {
                $other[$k] = $val
            }
        }
    }

    return [pscustomobject]@{
        Target1V = $target1V
        OtherJson = (ConvertTo-Json $other -Compress)
        OtherCount = $other.Count
    }
}

function Get-ExtraFreqTargets {
    param(
        [string]$UpmId,
        [hashtable]$AllSheets
    )

    if ([string]::IsNullOrWhiteSpace($UpmId)) {
        return '{}'
    }

    $result = [ordered]@{}

    foreach ($sheetName in $AllSheets.Keys) {
        if ($sheetName.ToLowerInvariant() -eq 'idv osc') { continue }
        $rows = @($AllSheets[$sheetName])
        if ($rows.Count -eq 0) { continue }

        $headers = @($rows[0].PSObject.Properties.Name)
        $candidateCols = @($headers | Where-Object {
            $u = $_.ToUpperInvariant()
            $u.Contains('TARGET') -or $u.Contains('FREQ') -or $u.Contains('GHZ') -or $u.Contains('OSC')
        })
        if ($candidateCols.Count -eq 0) { continue }

        foreach ($r in $rows) {
            $blob = (($headers | ForEach-Object { Normalize-Text $r.$_ }) -join ' ').ToUpperInvariant()
            if (-not $blob.Contains($UpmId)) { continue }

            foreach ($cc in $candidateCols) {
                $vv = Normalize-Text $r.$cc
                if (-not [string]::IsNullOrWhiteSpace($vv)) {
                    $result["$sheetName::$cc"] = $vv
                }
            }
        }
    }

    return (ConvertTo-Json $result -Compress)
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $RealCsv)) { throw "Real CSV not found: $RealCsv" }
if (-not (Test-Path -LiteralPath $DescriptionXlsx)) { throw "Description XLSX not found: $DescriptionXlsx" }
if (-not (Test-Path -LiteralPath $RequiredUpmsXlsx)) { throw "Required UPMs XLSX not found: $RequiredUpmsXlsx" }

Write-Host "Pre-step: loading required UPM rules for early column filtering..."
$requiredRules = @(Get-RequiredUpmRules -Path $RequiredUpmsXlsx)
if ($requiredRules.Count -eq 0) { throw "No required UPM rules were found in $RequiredUpmsXlsx" }

Write-Host "Loading real UPM CSV..."
$rawRowCount = 0
$visualIdColumn = $null
$sortColumns = @()
$allUpmColumns = @()
$upmColumns = @()
$selectedUpms = @()

$dedupMap = @{}
$relevantColsPath = Join-Path $OutputDir 'upm_relevant_columns_detected.csv'

Write-Host "Step 1/5: deduplicating to one row per Visual ID while preserving distinct UPM values..."
$reader = $null
$columns = @()

try {
    $reader = New-Object System.IO.StreamReader($RealCsv)
    if ($reader.EndOfStream) { throw "Real CSV has no rows." }

    $headerLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($headerLine)) { throw "Real CSV header is empty." }
    $columns = @($headerLine.Split(','))
    if ($columns.Count -eq 0) { throw "Real CSV header is empty." }

    $visualIdColumn = Get-FirstExistingColumnName -CandidateNames @('Visual ID', 'VISUAL_ID', 'VisualId', 'VISUALID', 'VID', 'VisualID') -AvailableNames $columns
    if (-not $visualIdColumn) { throw "Could not find Visual ID column in real CSV." }
    $visualIdIndex = [array]::IndexOf($columns, $visualIdColumn)

    $sortColumns = @('SORT_LOT_U1.U5', 'SORT_WAFER_U1.U5', 'SORT_X_U1.U5', 'SORT_Y_U1.U5') | Where-Object { $columns -contains $_ }
    $sortIndexMap = @{}
    foreach ($sc in $sortColumns) { $sortIndexMap[$sc] = [array]::IndexOf($columns, $sc) }

    $allUpmColumns = @($columns | Where-Object { $_.ToUpperInvariant().StartsWith('UPM_') })
    if ($allUpmColumns.Count -eq 0) { throw "No UPM_* columns found in real CSV." }

    $parsedAllUpms = @($allUpmColumns | ForEach-Object { Parse-UpmColumn -ColumnName $_ })
    $selectedUpms = @($parsedAllUpms | Where-Object { Test-IsRequiredUpm -ParsedUpm $_ -RequiredRules $requiredRules })
    $upmColumns = @($selectedUpms | Select-Object -ExpandProperty ColumnName)
    if ($upmColumns.Count -eq 0) {
        throw "No relevant UPM columns remained after required-column filtering."
    }

    # Write the detected relevant columns immediately so progress is visible even if later steps abort.
    @($selectedUpms | Select-Object ColumnName,UpmId,ClassType,Lib,StdCell,VtType,CoreHint,VoltageMv,Site) |
        Export-Csv -LiteralPath $relevantColsPath -NoTypeInformation -Encoding UTF8

    $upmIndexMap = @{}
    foreach ($uc in $upmColumns) { $upmIndexMap[$uc] = [array]::IndexOf($columns, $uc) }

    Write-Host ("Detected UPM columns: total={0}, relevant={1}" -f $allUpmColumns.Count, $upmColumns.Count)

    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($null -eq $line) { continue }
        $fields = @($line.Split(','))

        $rawRowCount++
        if (($rawRowCount % 5000) -eq 0) {
            Write-Host ("Step 1 progress: processed {0} rows, unique Visual IDs so far: {1}" -f $rawRowCount, $dedupMap.Count)
        }

        if ($fields.Count -le $visualIdIndex) { continue }
        $vid = Normalize-Text $fields[$visualIdIndex]
        if ([string]::IsNullOrWhiteSpace($vid)) { continue }

        if (-not $dedupMap.ContainsKey($vid)) {
            $sortMap = @{}
            foreach ($sc in $sortColumns) { $sortMap[$sc] = '' }
            $dedupMap[$vid] = [pscustomobject]@{
                VisualId = $vid
                SortValues = $sortMap
                UpmValues = @{}
            }
        }

        $entry = $dedupMap[$vid]

        foreach ($sc in $sortColumns) {
            $scIndex = $sortIndexMap[$sc]
            if ($scIndex -lt 0 -or $fields.Count -le $scIndex) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$entry.SortValues[$sc])) {
                $sv = Normalize-Text $fields[$scIndex]
                if (-not [string]::IsNullOrWhiteSpace($sv)) { $entry.SortValues[$sc] = $sv }
            }
        }

        foreach ($uc in $upmColumns) {
            $ucIndex = $upmIndexMap[$uc]
            if ($ucIndex -lt 0 -or $fields.Count -le $ucIndex) { continue }
            $uv = Normalize-Text $fields[$ucIndex]
            if ([string]::IsNullOrWhiteSpace($uv)) { continue }

            if (-not $entry.UpmValues.ContainsKey($uc)) {
                $entry.UpmValues[$uc] = $uv
                continue
            }

            $existing = $entry.UpmValues[$uc]
            if ($existing -is [string]) {
                if ($existing -ne $uv) {
                    $hs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
                    [void]$hs.Add($existing)
                    [void]$hs.Add($uv)
                    $entry.UpmValues[$uc] = $hs
                }
            }
            else {
                [void]$existing.Add($uv)
            }
        }
    }
}
finally {
    if ($reader) { $reader.Close() }
}

if ($rawRowCount -eq 0) { throw "Real CSV has no data rows." }
Write-Host ("Step 1 complete: processed {0} rows, unique Visual IDs: {1}" -f $rawRowCount, $dedupMap.Count)

# --- File paths (defined early so checkpoint writes can use them) ---
$dedupPath    = Join-Path $OutputDir 'upm_real_deduplicated_by_visual_id.csv'
$conflictPath = Join-Path $OutputDir 'upm_dedup_conflicts.csv'
$mappingPath  = Join-Path $OutputDir 'upm_column_to_idvosc_mapping.csv'
$stackedPath  = Join-Path $OutputDir 'upm_stacked_merged.csv'
$summaryPath  = Join-Path $OutputDir 'upm_stacked_summary.txt'

# --- Stream-write dedup CSV directly from $dedupMap (no wide PSCustomObject array) ---
Write-Host "Writing deduplicated table to CSV..."
$conflictRows = New-Object System.Collections.Generic.List[object]
$dedupRowCount = 0

$dedupHeaderCols = @($visualIdColumn) + $sortColumns + $upmColumns
$dedupHeaderLine = ($dedupHeaderCols | ForEach-Object { '"' + $_.Replace('"','""') + '"' }) -join ','

$dedupWriter    = New-Object System.IO.StreamWriter($dedupPath,    $false, [System.Text.Encoding]::UTF8)
$conflictWriter = New-Object System.IO.StreamWriter($conflictPath, $false, [System.Text.Encoding]::UTF8)

try {
    $dedupWriter.WriteLine($dedupHeaderLine)
    $conflictWriter.WriteLine('"VisualID","UPM_COLUMN","DistinctValueCount","DistinctValues"')

    foreach ($entry in $dedupMap.Values) {
        $vals = @($entry.VisualId)
        foreach ($sc in $sortColumns) { $vals += [string]$entry.SortValues[$sc] }

        foreach ($uc in $upmColumns) {
            if (-not $entry.UpmValues.ContainsKey($uc)) {
                $vals += ''
                continue
            }
            $stored = $entry.UpmValues[$uc]
            if ($stored -is [string]) {
                $vals += $stored
            } else {
                $avals = @($stored)
                if ($avals.Count -le 1) {
                    $vals += if ($avals.Count -eq 1) { $avals[0] } else { '' }
                } else {
                    $joined = $avals -join ' | '
                    $vals += $joined
                    $conflictWriter.WriteLine(('"' + $entry.VisualId.Replace('"','""') + '","' + $uc.Replace('"','""') + '",' + $avals.Count + ',"' + $joined.Replace('"','""') + '"'))
                }
            }
        }
        $dedupWriter.WriteLine(($vals | ForEach-Object { '"' + ([string]$_).Replace('"','""') + '"' }) -join ',')
        $dedupRowCount++
    }
}
finally {
    $dedupWriter.Close()
    $conflictWriter.Close()
}
Write-Host ("Deduplicated table written: {0} rows -> {1}" -f $dedupRowCount, $dedupPath)

# --- Step 2: Build IDV Osc mapping (small table, safe in memory) ---
Write-Host "Step 2/5: building UPM<->IDV Osc mapping..."
$idvRows = Import-ExcelSheetRows -Path $DescriptionXlsx -SheetName 'IDV Osc'
if ($idvRows.Count -eq 0) { throw "IDV Osc sheet is empty or unreadable." }
$descRows = Build-DescriptionRows -Rows $idvRows

Write-Host "Step 3/5: using pre-filtered required UPM columns..."
$allSheets = Import-ExcelAllSheets -Path $DescriptionXlsx

$mappingRows = New-Object System.Collections.Generic.List[object]
$matchLookup = @{}

foreach ($pu in $selectedUpms) {
    $matchRes = Get-BestDescriptionMatch -ParsedUpm $pu -DescriptionRows $descRows
    $m = $matchRes.Match
    $score = [int]$matchRes.Score
    $matched = $false

    if ($m -and $score -ge 60) {
        $matched = $true
        $matchLookup[$pu.ColumnName] = [pscustomobject]@{
            Score = $score
            Index = $m.Index
            Raw   = $m.Raw
        }
    }

    $mappingRows.Add([pscustomobject]@{
        UPM_COLUMN       = $pu.ColumnName
        UPM_ID           = $pu.UpmId
        UPM_CLASS        = $pu.ClassType
        UPM_VT           = $pu.VtType
        UPM_CORE_HINT    = $pu.CoreHint
        UPM_VOLTAGE_MV   = $pu.VoltageMv
        UPM_SITE         = $pu.Site
        MATCHED          = $matched
        MATCH_SCORE      = $score
        IDVOSC_ROW_INDEX = if ($m) { $m.Index } else { '' }
    })
}

@($mappingRows) | Export-Csv -LiteralPath $mappingPath -NoTypeInformation -Encoding UTF8
Write-Host "Mapping table written: $mappingPath"

# Build IDVOSC extra column names (from first matched entry)
$idvoscExtraCols = @()
foreach ($key in $matchLookup.Keys) {
    $idvoscExtraCols = @($matchLookup[$key].Raw.PSObject.Properties.Name | ForEach-Object { "IDVOSC_$_" })
    break
}

# --- Step 4+5: Stream-write stacked CSV directly from $dedupMap (no wide array) ---
Write-Host "Step 4/5 and 5/5: streaming stacked output..."
$stackedCols = @('Visual_ID','SORT_LOT_U1.U5','SORT_WAFER_U1.U5','SORT_X_U1.U5','SORT_Y_U1.U5',
    'UPM_COLUMN','UPM_VALUE','UPM_ID','UPM_CLASS','UPM_VT','UPM_CORE_HINT','UPM_VOLTAGE_MV','UPM_SITE',
    'MATCH_SCORE','TARGET_1V','TARGET_OTHER_VOLTAGES_JSON','EXTRA_FREQ_TARGETS_JSON') + $idvoscExtraCols
$stackedHeader = ($stackedCols | ForEach-Object { '"' + $_.Replace('"','""') + '"' }) -join ','

$stackedWriter = New-Object System.IO.StreamWriter($stackedPath, $false, [System.Text.Encoding]::UTF8)
$stackedRowCount = 0
$otherVoltageRows = 0

try {
    $stackedWriter.WriteLine($stackedHeader)

    foreach ($entry in $dedupMap.Values) {
        $vid = $entry.VisualId
        if ([string]::IsNullOrWhiteSpace($vid)) { continue }

        $sortLot   = [string]$entry.SortValues['SORT_LOT_U1.U5']
        $sortWafer = [string]$entry.SortValues['SORT_WAFER_U1.U5']
        $sortX     = [string]$entry.SortValues['SORT_X_U1.U5']
        $sortY     = [string]$entry.SortValues['SORT_Y_U1.U5']

        foreach ($pu in $selectedUpms) {
            if (-not $entry.UpmValues.ContainsKey($pu.ColumnName)) { continue }
            $stored = $entry.UpmValues[$pu.ColumnName]
            $upmVal = if ($stored -is [string]) { $stored } else { @($stored) -join ' | ' }
            if ([string]::IsNullOrWhiteSpace($upmVal)) { continue }

            $matchScore = ''; $t1v = ''; $tOther = '{}'; $tExtra = '{}'
            $idvoscVals = @($idvoscExtraCols | ForEach-Object { '' })

            if ($matchLookup.ContainsKey($pu.ColumnName)) {
                $mm = $matchLookup[$pu.ColumnName]
                $matchScore = $mm.Score
                $vt = Get-VoltageTargetsFromDescription -RawDesc $mm.Raw
                $t1v = $vt.Target1V; $tOther = $vt.OtherJson
                if ([int]$vt.OtherCount -gt 0) { $otherVoltageRows++ }
                $tExtra = Get-ExtraFreqTargets -UpmId $pu.UpmId -AllSheets $allSheets
                $idvoscVals = @($mm.Raw.PSObject.Properties | ForEach-Object { Normalize-Text $_.Value })
            }

            $rowVals = @($vid, $sortLot, $sortWafer, $sortX, $sortY,
                $pu.ColumnName, $upmVal, $pu.UpmId, $pu.ClassType, $pu.VtType,
                $pu.CoreHint, $pu.VoltageMv, $pu.Site,
                $matchScore, $t1v, $tOther, $tExtra) + $idvoscVals

            $stackedWriter.WriteLine(($rowVals | ForEach-Object { '"' + ([string]$_).Replace('"','""') + '"' }) -join ',')
            $stackedRowCount++
        }
    }
}
finally {
    $stackedWriter.Close()
}
Write-Host ("Stacked output written: {0} rows -> {1}" -f $stackedRowCount, $stackedPath)

$matchedCount   = @($mappingRows | Where-Object { $_.MATCHED }).Count
$unmatchedCount = @($mappingRows | Where-Object { -not $_.MATCHED }).Count

$summaryLines = @(
    'UPM Stacked Merge Summary',
    '=========================',
    "Real rows (raw): $rawRowCount",
    "Unique Visual IDs: $($dedupMap.Count)",
    "Deduplicated rows written: $dedupRowCount",
    "UPM columns total in real data: $($allUpmColumns.Count)",
    "UPM columns selected as relevant: $($selectedUpms.Count)",
    "Matched UPM columns to IDV Osc: $matchedCount",
    "Unmatched UPM columns: $unmatchedCount",
    "Stacked output rows: $stackedRowCount",
    ''
)
$summaryLines += if ($otherVoltageRows -gt 0) {
    'Additional voltage target columns detected in description data.'
} else {
    'No additional voltage target columns detected. Only 1V target populated when available.'
}

Set-Content -LiteralPath $summaryPath -Value ($summaryLines -join [Environment]::NewLine) -Encoding UTF8

Write-Host "Done."
Write-Host "- Deduplicated table: $dedupPath"
Write-Host "- Dedup conflicts:    $conflictPath"
Write-Host "- Relevant UPM cols:  $relevantColsPath"
Write-Host "- UPM mapping table:  $mappingPath"
Write-Host "- Stacked output:     $stackedPath"
Write-Host "- Summary:            $summaryPath"
