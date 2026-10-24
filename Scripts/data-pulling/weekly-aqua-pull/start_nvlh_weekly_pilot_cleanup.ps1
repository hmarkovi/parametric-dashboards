#requires -Version 5.1

param(
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-H\Weekly Runs",
    [string[]]$WorkWeeks = @("WW33_2026", "WW34_2026", "WW35_2026"),
    [int]$MaxWorkWeeks = 3,
    [string]$RetainedFolderName = "By-Class-TP-final",
    [string]$ManifestFolderName = "pilot_cleanup_manifests",
    [switch]$DeleteOriginals
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

function Get-RowCompletenessScore {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row
    )

    $nonEmptyCount = 0
    $ilasNonEmptyCount = 0

    foreach ($property in $Row.PSObject.Properties) {
        $value = [string]$property.Value
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $nonEmptyCount++
        if ($property.Name -like 'ILAS_*') {
            $ilasNonEmptyCount++
        }
    }

    return ($ilasNonEmptyCount * 1000) + $nonEmptyCount
}

function New-RowFromHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Headers,
        [Parameter(Mandatory = $true)]
        [psobject]$SourceRow
    )

    $map = [ordered]@{}
    foreach ($header in $Headers) {
        $property = $SourceRow.PSObject.Properties[$header]
        if ($null -ne $property) {
            $map[$header] = $property.Value
        }
        else {
            $map[$header] = ''
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
        [System.Collections.IList]$DecisionLog
    )

    $existingRows = @()
    $existingHeaders = @()
    if (Test-Path -LiteralPath $OutputCsvPath -PathType Leaf) {
        $existingRows = @(Import-Csv -LiteralPath $OutputCsvPath)
        if ($existingRows.Count -gt 0) {
            $existingHeaders = @($existingRows[0].PSObject.Properties.Name)
        }
    }

    $incomingHeaders = @()
    if ($IncomingRows.Count -gt 0) {
        $incomingHeaders = @($IncomingRows[0].PSObject.Properties.Name)
    }

    $headers = New-Object System.Collections.Generic.List[string]
    $headerSeen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($header in @($existingHeaders + $incomingHeaders)) {
        if ($headerSeen.Add($header)) {
            $headers.Add($header) | Out-Null
        }
    }

    $rowByKey = @{}
    $keyOrder = New-Object System.Collections.Generic.List[string]

    foreach ($row in $existingRows) {
        $key = ('{0}||{1}' -f ([string]$row.$VisualIdColumn).Trim().ToUpperInvariant(), ([string]$row.$LotColumn).Trim().ToUpperInvariant())
        if (-not $rowByKey.ContainsKey($key)) {
            $rowByKey[$key] = $row
            $keyOrder.Add($key) | Out-Null
        }
    }

    foreach ($row in $IncomingRows) {
        $key = ('{0}||{1}' -f ([string]$row.$VisualIdColumn).Trim().ToUpperInvariant(), ([string]$row.$LotColumn).Trim().ToUpperInvariant())
        if ([string]::IsNullOrWhiteSpace($key.Replace('||', ''))) {
            continue
        }

        if (-not $rowByKey.ContainsKey($key)) {
            $rowByKey[$key] = $row
            $keyOrder.Add($key) | Out-Null
            continue
        }

        $existingRow = $rowByKey[$key]
        $existingScore = Get-RowCompletenessScore -Row $existingRow
        $incomingScore = Get-RowCompletenessScore -Row $row
        if ($incomingScore -gt $existingScore) {
            $rowByKey[$key] = $row
            $DecisionLog.Add([pscustomobject]@{
                Key = $key
                Action = 'ReplacedWithMoreCompleteIncoming'
                ExistingScore = $existingScore
                IncomingScore = $incomingScore
            }) | Out-Null
        }
        else {
            $DecisionLog.Add([pscustomobject]@{
                Key = $key
                Action = 'KeptExisting'
                ExistingScore = $existingScore
                IncomingScore = $incomingScore
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
        DeleteCandidates = New-Object System.Collections.Generic.List[string]
        ClassTpRowCounts = New-Object System.Collections.Generic.List[object]
    }

    $weekRowsByTp = @{}
    $weekSourceFilesByTp = @{}

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
                continue
            }

            if (-not $weekRowsByTp.ContainsKey($tpKey)) {
                $weekRowsByTp[$tpKey] = New-Object System.Collections.Generic.List[object]
                $weekSourceFilesByTp[$tpKey] = New-Object 'System.Collections.Generic.HashSet[string]'
            }

            $weekRowsByTp[$tpKey].Add($row) | Out-Null
            [void]$weekSourceFilesByTp[$tpKey].Add($file.Name)
        }

        $weekManifest.DeleteCandidates.Add($file.FullName) | Out-Null
    }

    foreach ($tpKey in ($weekRowsByTp.Keys | Sort-Object)) {
        $retainedCsvPath = Join-Path $retainedRoot ('{0}.csv' -f $tpKey)
        $incomingRows = $weekRowsByTp[$tpKey].ToArray()
        Write-Host ('Writing {0} rows to {1}' -f $incomingRows.Count, (Split-Path $retainedCsvPath -Leaf))
        $mergeResult = Merge-RowsIntoRetainedFile -OutputCsvPath $retainedCsvPath -IncomingRows $incomingRows -VisualIdColumn $visualIdColumn -LotColumn $lotColumn -DecisionLog $weekManifest.DuplicateDecisions
        $weekManifest.RetainedFilesTouched.Add((Split-Path $retainedCsvPath -Leaf)) | Out-Null
        $weekManifest.ClassTpRowCounts.Add([pscustomobject]@{
            ClassTp = $tpKey
            SourceFiles = @($weekSourceFilesByTp[$tpKey] | Sort-Object)
            SourceRowCount = $incomingRows.Count
            RetainedRowCount = $mergeResult.RowCount
            HeaderCount = $mergeResult.HeaderCount
        }) | Out-Null
    }

    foreach ($helper in @($cleanFiles + $rawFiles + $ilasDirectories)) {
        $weekManifest.DeleteCandidates.Add($helper.FullName) | Out-Null
    }

    $manifestPath = Join-Path $manifestRoot ('{0}.json' -f $weekKey)
    [pscustomobject]$weekManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    if ($DeleteOriginals.IsPresent) {
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
        DeletedOriginals = $DeleteOriginals.IsPresent
        ManifestPath = $manifestPath
    }) | Out-Null
}

$summaryPath = Join-Path $manifestRoot 'pilot_summary.json'
$pilotSummary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ('Pilot summary written to {0}' -f $summaryPath) -ForegroundColor Green