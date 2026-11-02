#requires -Version 5.1

param(
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-H\Weekly Runs",
    [string[]]$WorkWeeks = @("WW33_2026", "WW34_2026", "WW35_2026"),
    [int]$MaxWorkWeeks = 3,
    [string]$RetainedFolderName = "By-Class-TP-final",
    [string]$ManifestFolderName = "pilot_cleanup_manifests",
    [switch]$DeleteOriginals,
    [switch]$SkipValidation,
    [string]$PythonExe = "",
    [string]$ValidatorPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-IsoWeekYear {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )

    $isoWeekType = [type]::GetType("System.Globalization.ISOWeek")
    if ($isoWeekType) {
        return [pscustomobject]@{
            Week = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
            Year = [System.Globalization.ISOWeek]::GetYear($Date)
        }
    }

    $calendar = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $dateForWeek = $Date
    if ($Date.DayOfWeek -eq [System.DayOfWeek]::Monday -or
        $Date.DayOfWeek -eq [System.DayOfWeek]::Tuesday -or
        $Date.DayOfWeek -eq [System.DayOfWeek]::Wednesday) {
        $dateForWeek = $Date.AddDays(3)
    }

    return [pscustomobject]@{
        Week = $calendar.GetWeekOfYear($dateForWeek, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        Year = $dateForWeek.Year
    }
}

function Get-WeekKey {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )

    $iso = Get-IsoWeekYear -Date $Date
    return ('WW{0}_{1}' -f $iso.Week, $iso.Year)
}

function Get-DateTokenInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $patterns = @(
        '^Vmin_(?<Date>\d{8})\.csv$',
        '^Vmin_(?<Date>\d{8})_clean\.csv$',
        '^_raw_(?<Date>\d{8})_\d+\.csv$',
        '^_ilas_weekly_(?<Date>\d{8})_\d+$'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Name, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            continue
        }

        $dateToken = $match.Groups['Date'].Value
        $parsedDate = [datetime]::ParseExact($dateToken, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
        return [pscustomobject]@{
            DateToken = $dateToken
            Date = $parsedDate
            WeekKey = Get-WeekKey -Date $parsedDate
        }
    }

    return $null
}

function Normalize-ClassTpKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramName
    )

    $trimmed = $ProgramName.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    $match = [regex]::Match($trimmed, '^(?<Key>[A-Z0-9]+H\d{2}[A-Z]\d)')
    if ($match.Success) {
        return $match.Groups['Key'].Value
    }

    return $trimmed
}

function Get-FirstExistingColumnName {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CandidateNames,
        [Parameter(Mandatory = $true)]
        [string[]]$AvailableNames
    )

    foreach ($candidate in $CandidateNames) {
        if ($AvailableNames -contains $candidate) {
            return $candidate
        }
    }

    return $null
}

function ConvertTo-CellMap {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row
    )

    # Ordinal (case-sensitive) map so columns are never merged by accident.
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    foreach ($property in $Row.PSObject.Properties) {
        $map[$property.Name] = [string]$property.Value
    }

    return $map
}

function New-RowFromHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Headers,
        [Parameter(Mandatory = $true)]
        [object]$SourceRow
    )

    $map = [ordered]@{}
    if ($SourceRow -is [System.Collections.IDictionary]) {
        foreach ($header in $Headers) {
            if ($SourceRow.ContainsKey($header)) {
                $map[$header] = $SourceRow[$header]
            }
            else {
                $map[$header] = ''
            }
        }
    }
    else {
        foreach ($header in $Headers) {
            $property = $SourceRow.PSObject.Properties[$header]
            if ($null -ne $property) {
                $map[$header] = $property.Value
            }
            else {
                $map[$header] = ''
            }
        }
    }

    return [pscustomobject]$map
}

function Merge-RowsIntoRetainedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputCsvPath,
        [Parameter(Mandatory = $true)]
        [object[]]$IncomingRows,
        [Parameter(Mandatory = $true)]
        [string]$VisualIdColumn,
        [Parameter(Mandatory = $true)]
        [string]$LotColumn,
        [Parameter(Mandatory = $true)]
        [System.Collections.IList]$DecisionLog,
        [string[]]$IncomingHeaders = @(),
        [System.Collections.IList]$ConflictLog = $null,
        [System.Collections.IList]$SkippedLog = $null,
        [string]$ClassTp = ''
    )

    $existingRows = @()
    $existingHeaders = @()
    if (Test-Path -LiteralPath $OutputCsvPath -PathType Leaf) {
        $existingRows = @(Import-Csv -LiteralPath $OutputCsvPath)
        if ($existingRows.Count -gt 0) {
            $existingHeaders = @($existingRows[0].PSObject.Properties.Name)
        }
    }

    # Header union: retained headers + headers of EVERY contributing source file (not only the first row),
    # so a column that exists in any daily file can never be dropped.
    $incomingHeaderList = @($IncomingHeaders)
    if ($incomingHeaderList.Count -eq 0 -and $IncomingRows.Count -gt 0) {
        $incomingHeaderList = @($IncomingRows[0].PSObject.Properties.Name)
    }

    $headers = New-Object System.Collections.Generic.List[string]
    $headerSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($header in @($existingHeaders + $incomingHeaderList)) {
        if ($headerSeen.Add($header)) {
            $headers.Add($header) | Out-Null
        }
    }

    $rowByKey = @{}
    $keyOrder = New-Object System.Collections.Generic.List[string]
    $stats = [ordered]@{ DuplicateKeys = 0; MergedKeys = 0; FilledCells = 0; OverwrittenCells = 0; SkippedRows = 0 }

    # Existing (older) rows first; a repeated key inside the retained file is merged with the same rule.
    # Incoming rows arrive in ascending file-date order, so a later row is always newer than an earlier one.
    $allSources = New-Object System.Collections.Generic.List[object]
    foreach ($row in $existingRows) { $allSources.Add([pscustomobject]@{ Row = $row; Origin = 'retained' }) | Out-Null }
    foreach ($row in $IncomingRows) { $allSources.Add([pscustomobject]@{ Row = $row; Origin = 'incoming' }) | Out-Null }

    foreach ($entry in $allSources) {
        $row = $entry.Row
        $vid = ([string]$row.$VisualIdColumn).Trim().ToUpperInvariant()
        $lot = ([string]$row.$LotColumn).Trim().ToUpperInvariant()
        $key = ('{0}||{1}' -f $vid, $lot)
        if ([string]::IsNullOrWhiteSpace($key.Replace('||', ''))) {
            $stats.SkippedRows++
            if ($null -ne $SkippedLog) {
                $SkippedLog.Add([pscustomobject]@{ ClassTp = $ClassTp; Origin = $entry.Origin; Reason = 'BlankVisualIdAndLot' }) | Out-Null
            }
            continue
        }

        if (-not $rowByKey.ContainsKey($key)) {
            $rowByKey[$key] = $row
            $keyOrder.Add($key) | Out-Null
            continue
        }

        # Same VISUAL_ID + LOTFROMFS: newest non-empty cell wins, empty cells are filled from older values.
        # A different LOTFROMFS produces a different key, so both rows are kept.
        $stats.DuplicateKeys++
        $current = $rowByKey[$key]
        if ($current -isnot [System.Collections.IDictionary]) {
            $current = ConvertTo-CellMap -Row $current
            $rowByKey[$key] = $current
        }

        $filled = 0
        $overwritten = 0
        foreach ($property in $row.PSObject.Properties) {
            $newValue = [string]$property.Value
            if ($newValue.Length -eq 0) {
                continue
            }

            $name = $property.Name
            $oldValue = ''
            if ($current.ContainsKey($name)) {
                $oldValue = [string]$current[$name]
            }

            if ($oldValue.Length -eq 0) {
                $current[$name] = $newValue
                $filled++
            }
            elseif ($oldValue -cne $newValue) {
                if ($null -ne $ConflictLog) {
                    $ConflictLog.Add([pscustomobject]@{
                        ClassTp = $ClassTp
                        Key = $key
                        Column = $name
                        OlderValue = $oldValue
                        NewerValue = $newValue
                    }) | Out-Null
                }
                $current[$name] = $newValue
                $overwritten++
            }
        }

        if (($filled + $overwritten) -gt 0) {
            $stats.MergedKeys++
            $stats.FilledCells += $filled
            $stats.OverwrittenCells += $overwritten
            $DecisionLog.Add([pscustomobject]@{
                Key = $key
                Action = 'MergedNewestWins'
                FilledEmptyCells = $filled
                OverwrittenCells = $overwritten
            }) | Out-Null
        }
    }

    $localTempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ([System.Guid]::NewGuid().ToString() + '.csv'))
    try {
        & {
            foreach ($key in $keyOrder) {
                New-RowFromHeaders -Headers $headers.ToArray() -SourceRow $rowByKey[$key]
            }
        } | Export-Csv -LiteralPath $localTempPath -NoTypeInformation -Encoding UTF8
        Copy-Item -LiteralPath $localTempPath -Destination $OutputCsvPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $localTempPath) {
            Remove-Item -LiteralPath $localTempPath -Force -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]@{
        HeaderCount = $headers.Count
        RowCount = $keyOrder.Count
        DuplicateKeys = $stats.DuplicateKeys
        MergedKeys = $stats.MergedKeys
        FilledCells = $stats.FilledCells
        OverwrittenCells = $stats.OverwrittenCells
        SkippedRows = $stats.SkippedRows
    }
}

function Get-PilotInventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $items = Get-ChildItem -LiteralPath $Directory -Force
    $inventory = @{}

    foreach ($item in $items) {
        $info = Get-DateTokenInfo -Name $item.Name
        if ($null -eq $info) {
            continue
        }

        if (-not $inventory.ContainsKey($info.WeekKey)) {
            $inventory[$info.WeekKey] = [ordered]@{
                Finals = New-Object System.Collections.Generic.List[object]
                CleanFiles = New-Object System.Collections.Generic.List[object]
                RawFiles = New-Object System.Collections.Generic.List[object]
                IlasDirectories = New-Object System.Collections.Generic.List[object]
            }
        }

        $bucket = $inventory[$info.WeekKey]
        if ($item.PSIsContainer) {
            if ($item.Name -like '_ilas_weekly_*') {
                $bucket.IlasDirectories.Add($item) | Out-Null
            }
            continue
        }

        if ($item.Name -match '^Vmin_\d{8}\.csv$') {
            $bucket.Finals.Add($item) | Out-Null
            continue
        }

        if ($item.Name -match '^Vmin_\d{8}_clean\.csv$') {
            $bucket.CleanFiles.Add($item) | Out-Null
            continue
        }

        if ($item.Name -match '^_raw_\d{8}_\d+\.csv$') {
            $bucket.RawFiles.Add($item) | Out-Null
        }
    }

    return $inventory
}

if (-not (Test-Path -LiteralPath $WeeklyRunsDir -PathType Container)) {
    throw "WeeklyRunsDir not found: $WeeklyRunsDir"
}

$selectedWeeks = @($WorkWeeks | Select-Object -First $MaxWorkWeeks)
if ($selectedWeeks.Count -eq 0) {
    throw 'At least one work-week must be provided.'
}

# "Newest wins" is only correct when weeks are merged oldest -> newest, regardless of the order passed in.
$selectedWeeks = @($selectedWeeks | Sort-Object -Property @{ Expression = {
    if ($_ -match '^WW(?<w>\d+)_(?<y>\d{4})$') { ([int]$Matches['y'] * 100) + [int]$Matches['w'] } else { 999999 }
} })

if (-not $SkipValidation.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($ValidatorPath)) {
        $ValidatorPath = Join-Path $PSScriptRoot 'validate_weekly_cleanup.py'
    }
    if ([string]::IsNullOrWhiteSpace($PythonExe)) {
        $pythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pythonCmd) { $PythonExe = $pythonCmd.Source }
    }
    if (-not (Test-Path -LiteralPath $ValidatorPath -PathType Leaf)) {
        throw "Validator not found: $ValidatorPath (use -SkipValidation to bypass; -DeleteOriginals is then refused)."
    }
    if ([string]::IsNullOrWhiteSpace($PythonExe) -or -not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
        throw 'Python not found for the validator. Pass -PythonExe or use -SkipValidation (-DeleteOriginals is then refused).'
    }
}
elseif ($DeleteOriginals.IsPresent) {
    throw '-DeleteOriginals requires validation; remove -SkipValidation.'
}

$retainedRoot = Join-Path $WeeklyRunsDir $RetainedFolderName
$manifestRoot = Join-Path $retainedRoot $ManifestFolderName
foreach ($path in @($retainedRoot, $manifestRoot)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

$inventory = Get-PilotInventory -Directory $WeeklyRunsDir
$pilotSummary = New-Object System.Collections.Generic.List[object]

foreach ($weekKey in $selectedWeeks) {
    Write-Host ('=== Processing {0} ===' -f $weekKey) -ForegroundColor Cyan
    if (-not $inventory.ContainsKey($weekKey)) {
        Write-Warning "No inventory items found for $weekKey"
        continue
    }

    $weekBucket = $inventory[$weekKey]
    $finalFiles = @($weekBucket.Finals | Sort-Object Name)
    $cleanFiles = @($weekBucket.CleanFiles | Sort-Object Name)
    $rawFiles = @($weekBucket.RawFiles | Sort-Object Name)
    $ilasDirectories = @($weekBucket.IlasDirectories | Sort-Object Name)

    $weekManifest = [ordered]@{
        WorkWeek = $weekKey
        StartedAt = (Get-Date).ToString('o')
        DeleteOriginals = $DeleteOriginals.IsPresent
        Finals = @($finalFiles | ForEach-Object { $_.Name })
        CleanFiles = @($cleanFiles | ForEach-Object { $_.Name })
        RawFiles = @($rawFiles | ForEach-Object { $_.Name })
        IlasDirectories = @($ilasDirectories | ForEach-Object { $_.Name })
        RetainedFilesTouched = New-Object System.Collections.Generic.List[string]
        SkippedFiles = New-Object System.Collections.Generic.List[string]
        DuplicateDecisions = New-Object System.Collections.Generic.List[object]
        SkippedRows = New-Object System.Collections.Generic.List[object]
        Validation = $null
        DeleteCandidates = New-Object System.Collections.Generic.List[string]
        ClassTpRowCounts = New-Object System.Collections.Generic.List[object]
    }
    $weekConflicts = New-Object System.Collections.Generic.List[object]

    $weekRowsByTp = @{}
    $weekSourceFilesByTp = @{}
    $weekHeadersByTp = @{}
    $weekColumnsByTp = @{}

    foreach ($file in $finalFiles) {
        Write-Host ('Reading {0}' -f $file.Name)
        $rows = @(Import-Csv -LiteralPath $file.FullName)
        if ($rows.Count -eq 0) {
            $weekManifest.SkippedFiles.Add($file.Name) | Out-Null
            continue
        }

        $headers = @($rows[0].PSObject.Properties.Name)
        $visualIdColumn = Get-FirstExistingColumnName -CandidateNames @('VISUAL_ID', 'VisualID', 'Visual_ID') -AvailableNames $headers
        $lotColumn = Get-FirstExistingColumnName -CandidateNames @('LOTFROMFS', 'LotFromFs', 'Lot_From_FS', 'LOT') -AvailableNames $headers
        $programColumn = Get-FirstExistingColumnName -CandidateNames @('Program Name_CLASSHOT', 'PROGRAM NAME_CLASSHOT') -AvailableNames $headers

        if ([string]::IsNullOrWhiteSpace($visualIdColumn) -or [string]::IsNullOrWhiteSpace($lotColumn) -or [string]::IsNullOrWhiteSpace($programColumn)) {
            $weekManifest.SkippedFiles.Add($file.Name) | Out-Null
            continue
        }

        $rowsByTp = @{}
        foreach ($row in $rows) {
            $programName = [string]$row.$programColumn
            $tpKey = Normalize-ClassTpKey -ProgramName $programName
            if ([string]::IsNullOrWhiteSpace($tpKey)) {
                $weekManifest.SkippedRows.Add([pscustomobject]@{
                    File = $file.Name
                    Reason = $(if ([string]::IsNullOrWhiteSpace($programName)) { 'BlankProgramName' } else { 'UnmappedProgramName' })
                    ProgramName = $programName
                    VisualId = [string]$row.$visualIdColumn
                    Lot = [string]$row.$lotColumn
                }) | Out-Null
                continue
            }

            if (-not $weekRowsByTp.ContainsKey($tpKey)) {
                $weekRowsByTp[$tpKey] = New-Object System.Collections.Generic.List[object]
                $weekSourceFilesByTp[$tpKey] = New-Object 'System.Collections.Generic.HashSet[string]'
                $weekHeadersByTp[$tpKey] = New-Object System.Collections.Generic.List[string]
                $weekColumnsByTp[$tpKey] = New-Object 'System.Collections.Generic.HashSet[string]'
            }

            $weekRowsByTp[$tpKey].Add($row) | Out-Null
            if ($weekSourceFilesByTp[$tpKey].Add($file.Name)) {
                # Every contributing file's headers are unioned so no column is lost.
                foreach ($h in $headers) {
                    if ($weekColumnsByTp[$tpKey].Add($h)) {
                        $weekHeadersByTp[$tpKey].Add($h) | Out-Null
                    }
                }
            }
        }

        $weekManifest.DeleteCandidates.Add($file.FullName) | Out-Null
    }

    # Snapshot of the retained files that are about to change; the validator uses it as the baseline.
    $snapshotDir = Join-Path ([System.IO.Path]::GetTempPath()) ('premerge_{0}_{1}' -f $weekKey, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $snapshotDir | Out-Null
    foreach ($tpKey in $weekRowsByTp.Keys) {
        $existingPath = Join-Path $retainedRoot ('{0}.csv' -f $tpKey)
        if (Test-Path -LiteralPath $existingPath -PathType Leaf) {
            Copy-Item -LiteralPath $existingPath -Destination (Join-Path $snapshotDir ('{0}.csv' -f $tpKey)) -Force
        }
    }

    $weekSkippedMergeRows = New-Object System.Collections.Generic.List[object]
    foreach ($tpKey in ($weekRowsByTp.Keys | Sort-Object)) {
        $retainedCsvPath = Join-Path $retainedRoot ('{0}.csv' -f $tpKey)
        $incomingRows = $weekRowsByTp[$tpKey].ToArray()
        Write-Host ('Writing {0} rows to {1}' -f $incomingRows.Count, (Split-Path $retainedCsvPath -Leaf))
        $mergeResult = Merge-RowsIntoRetainedFile -OutputCsvPath $retainedCsvPath -IncomingRows $incomingRows -VisualIdColumn $visualIdColumn -LotColumn $lotColumn -DecisionLog $weekManifest.DuplicateDecisions -IncomingHeaders $weekHeadersByTp[$tpKey].ToArray() -ConflictLog $weekConflicts -SkippedLog $weekSkippedMergeRows -ClassTp $tpKey
        $weekManifest.RetainedFilesTouched.Add((Split-Path $retainedCsvPath -Leaf)) | Out-Null
        $weekManifest.ClassTpRowCounts.Add([pscustomobject]@{
            ClassTp = $tpKey
            SourceFiles = @($weekSourceFilesByTp[$tpKey] | Sort-Object)
            SourceRowCount = $incomingRows.Count
            RetainedRowCount = $mergeResult.RowCount
            HeaderCount = $mergeResult.HeaderCount
            DuplicateKeys = $mergeResult.DuplicateKeys
            FilledEmptyCells = $mergeResult.FilledCells
            OverwrittenCells = $mergeResult.OverwrittenCells
            SkippedRows = $mergeResult.SkippedRows
        }) | Out-Null
    }
    foreach ($skipped in $weekSkippedMergeRows) { $weekManifest.SkippedRows.Add($skipped) | Out-Null }

    foreach ($helper in @($cleanFiles + $rawFiles + $ilasDirectories)) {
        $weekManifest.DeleteCandidates.Add($helper.FullName) | Out-Null
    }

    $conflictsPath = Join-Path $manifestRoot ('{0}_conflicts.csv' -f $weekKey)
    if ($weekConflicts.Count -gt 0) {
        $weekConflicts | Export-Csv -LiteralPath $conflictsPath -NoTypeInformation -Encoding UTF8
    }
    elseif (Test-Path -LiteralPath $conflictsPath) {
        Remove-Item -LiteralPath $conflictsPath -Force
    }
    $weekManifest.ConflictCount = $weekConflicts.Count

    # Independent validation of this week's merge (source files + snapshot -> retained).
    $validationPassed = $true
    if (-not $SkipValidation.IsPresent) {
        $reportPath = Join-Path $manifestRoot ('{0}_validation.json' -f $weekKey)
        $validatorArgs = @($ValidatorPath, '--retained-dir', $retainedRoot, '--baseline-dir', $snapshotDir, '--report', $reportPath, '--label', $weekKey, '--sources')
        $validatorArgs += @($finalFiles | ForEach-Object { $_.FullName })
        Write-Host ('Validating {0}...' -f $weekKey)
        & $PythonExe @validatorArgs
        $validationPassed = ($LASTEXITCODE -eq 0)
        $weekManifest.Validation = [ordered]@{ Passed = $validationPassed; ReportPath = $reportPath }
        if ($validationPassed) {
            Write-Host ('Validation PASSED for {0}' -f $weekKey) -ForegroundColor Green
        }
        else {
            Write-Warning ('Validation FAILED for {0}; see {1}. Originals are NOT deleted.' -f $weekKey, $reportPath)
        }
    }
    Remove-Item -LiteralPath $snapshotDir -Recurse -Force -ErrorAction SilentlyContinue

    $manifestPath = Join-Path $manifestRoot ('{0}.json' -f $weekKey)
    [pscustomobject]$weekManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    if ($DeleteOriginals.IsPresent -and $validationPassed) {
        foreach ($candidate in ($weekManifest.DeleteCandidates | Select-Object -Unique)) {
            if (Test-Path -LiteralPath $candidate) {
                Remove-Item -LiteralPath $candidate -Recurse -Force
            }
        }
    }

    $pilotSummary.Add([pscustomobject]@{
        WorkWeek = $weekKey
        FinalCount = $finalFiles.Count
        CleanCount = $cleanFiles.Count
        RawCount = $rawFiles.Count
        IlasDirCount = $ilasDirectories.Count
        RetainedFilesTouched = (@($weekManifest.RetainedFilesTouched | Select-Object -Unique)).Count
        DeletedOriginals = ($DeleteOriginals.IsPresent -and $validationPassed)
        ValidationPassed = $validationPassed
        Conflicts = $weekConflicts.Count
        ManifestPath = $manifestPath
    }) | Out-Null
}

$summaryPath = Join-Path $manifestRoot 'pilot_summary.json'
$pilotSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ('Pilot summary written to {0}' -f $summaryPath) -ForegroundColor Green