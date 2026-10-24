#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PrimaryCsv,

    [Parameter(Mandatory = $true)]
    [string]$SecondaryCsv,

    [string]$OutputCsv = "",
    [string]$IlasOutputDirectory = "",
    [string]$IlasScriptPath = "",
    [string]$ExistingIlasSummaryCsv = "",
    [string]$ProgramPattern = "NVLAX6*",
    [int]$LastNDaysTestEnd = 7,
    [int]$AquaPullTimeoutSeconds = 7200,
    [int]$AquaPullPollSeconds = 20,
    [switch]$ReuseMergedCsv,
    [switch]$SkipIlas
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

function Get-FirstExistingColumnName {
    param(
        [string[]]$CandidateNames,
        [string[]]$AvailableNames
    )

    foreach ($candidate in $CandidateNames) {
        if ($AvailableNames -contains $candidate) {
            return $candidate
        }
    }

    return $null
}

function Convert-ToMergeToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return $Value.Trim().ToUpperInvariant()
}

function Get-MergeKey {
    param(
        [string]$VisualId,
        [string]$LotFromFs
    )

    return ('{0}||{1}' -f (Convert-ToMergeToken -Value $VisualId), (Convert-ToMergeToken -Value $LotFromFs))
}

function Get-CanonicalColumnKey {
    param([string]$ColumnName)

    if ([string]::IsNullOrWhiteSpace($ColumnName)) {
        return ''
    }

    $trimmed = $ColumnName.Trim()
    $upper = $trimmed.ToUpperInvariant()

    $vminVerbose = [regex]::Match($upper, 'UPSVFPASSFLOW_[A-Z0-9.]+_CLASSHOT_(?<Tail>ORIGINAL|[A-Z0-9-]+_[0-9]+(?:\.[0-9]+)?_[0-9]+)$')
    if ($vminVerbose.Success) {
        return 'UPSVFHOT|{0}' -f $vminVerbose.Groups['Tail'].Value
    }

    $vminSimple = [regex]::Match($upper, '^UPSVF-HOT_(?<Tail>ORIGINAL|[A-Z0-9-]+_[0-9]+(?:\.[0-9]+)?_[0-9]+)$')
    if ($vminSimple.Success) {
        return 'UPSVFHOT|{0}' -f $vminSimple.Groups['Tail'].Value
    }

    $siccVerbose = [regex]::Match($upper, 'PP_SICC_[A-Z0-9.]+_CLASSHOT_(?<Domain>.+)_(?<Metric>VALUE|VOLTAGE|TEMPERATURE)$')
    if ($siccVerbose.Success) {
        return 'SICC|{0}|{1}' -f $siccVerbose.Groups['Domain'].Value, $siccVerbose.Groups['Metric'].Value
    }

    $siccSimple = [regex]::Match($upper, '^SICC-[A-Z0-9.]+_(?<Domain>.+)_(?<Metric>VALUE|VOLTAGE|TEMPERATURE)$')
    if ($siccSimple.Success) {
        return 'SICC|{0}|{1}' -f $siccSimple.Groups['Domain'].Value, $siccSimple.Groups['Metric'].Value
    }

    return ($upper -replace '[^A-Z0-9]+', '')
}

function New-TextFieldParser {
    param([string]$Path)

    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path)
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    return $parser
}

function Write-CsvRow {
    param(
        [System.IO.StreamWriter]$Writer,
        [object[]]$Values
    )

    $builder = New-Object System.Text.StringBuilder
    for ($index = 0; $index -lt $Values.Count; $index++) {
        if ($index -gt 0) {
            [void]$builder.Append(',')
        }

        $text = if ($null -eq $Values[$index]) { '' } else { [string]$Values[$index] }
        if ($text.IndexOfAny(@([char]',', [char]'"', [char]"`r", [char]"`n")) -ge 0) {
            [void]$builder.Append('"')
            [void]$builder.Append($text.Replace('"', '""'))
            [void]$builder.Append('"')
        }
        else {
            [void]$builder.Append($text)
        }
    }

    $Writer.WriteLine($builder.ToString())
}

function Resolve-IlasScriptPath {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return $ConfiguredPath
    }

    $scriptsRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $candidatePaths = @(
        (Join-Path $scriptsRoot 'Scripts\parametric-analysis\ilas\aqua_nvlax_ilas_vmin_analysis.ps1'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'parametric-analysis\ilas\aqua_nvlax_ilas_vmin_analysis.ps1')
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    throw 'Could not resolve aqua_nvlax_ilas_vmin_analysis.ps1'
}

function Get-IlasSummaryPath {
    param([string]$DirectoryPath)

    $summary = Get-ChildItem -LiteralPath $DirectoryPath -Filter 'ILAS_Vmin_Summary_*.csv' -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $summary) {
        throw "No ILAS_Vmin_Summary_*.csv found in $DirectoryPath"
    }

    return $summary.FullName
}

function Get-HeaderInfo {
    param([string]$Path)

    $parser = New-TextFieldParser -Path $Path
    try {
        if ($parser.EndOfData) {
            throw "CSV is empty: $Path"
        }

        $headers = $parser.ReadFields()
        if ($null -eq $headers -or $headers.Count -eq 0) {
            throw "Could not read header from $Path"
        }

        $visualIdColumn = Get-FirstExistingColumnName -CandidateNames @('VISUAL_ID', 'Visual ID', 'VisualId', 'VISUALID', 'VID') -AvailableNames $headers
        $lotColumn = Get-FirstExistingColumnName -CandidateNames @('LOTFROMFS', 'LotFromFs', 'LOT', 'Lot', 'SortLot', 'SORT_LOT', 'LATO_LOT') -AvailableNames $headers

        if ([string]::IsNullOrWhiteSpace($visualIdColumn)) {
            throw "Could not find Visual ID column in $Path"
        }
        if ([string]::IsNullOrWhiteSpace($lotColumn)) {
            throw "Could not find lot/class-lot column in $Path"
        }

        $visualIdIndex = [Array]::IndexOf($headers, $visualIdColumn)
        $lotIndex = [Array]::IndexOf($headers, $lotColumn)

        return [pscustomobject]@{
            Headers = $headers
            VisualIdColumn = $visualIdColumn
            VisualIdIndex = $visualIdIndex
            LotColumn = $lotColumn
            LotIndex = $lotIndex
        }
    }
    finally {
        $parser.Close()
    }
}

function Import-SecondaryLookup {
    param(
        [string]$Path,
        [object]$HeaderInfo
    )

    $lookup = @{}
    $rowCount = 0

    $parser = New-TextFieldParser -Path $Path
    try {
        [void]$parser.ReadFields()
        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            if ($null -eq $fields) {
                continue
            }

            $rowCount++
            $visualId = if ($HeaderInfo.VisualIdIndex -lt $fields.Count) { [string]$fields[$HeaderInfo.VisualIdIndex] } else { '' }
            $lot = if ($HeaderInfo.LotIndex -lt $fields.Count) { [string]$fields[$HeaderInfo.LotIndex] } else { '' }
            $key = Get-MergeKey -VisualId $visualId -LotFromFs $lot

            if ([string]::IsNullOrWhiteSpace($key.Replace('||', ''))) {
                continue
            }

            if ($lookup.ContainsKey($key)) {
                throw "Duplicate merge key in secondary CSV: $key"
            }

            $lookup[$key] = $fields
        }
    }
    finally {
        $parser.Close()
    }

    return [pscustomobject]@{
        Lookup = $lookup
        RowCount = $rowCount
    }
}

function Build-SecondaryMapping {
    param(
        [string[]]$PrimaryHeaders,
        [string[]]$SecondaryHeaders
    )

    $outputHeaders = New-Object System.Collections.Generic.List[string]
    $headerIndexMap = @{}
    $canonicalToOutput = @{}

    for ($index = 0; $index -lt $PrimaryHeaders.Count; $index++) {
        $header = [string]$PrimaryHeaders[$index]
        $outputHeaders.Add($header)
        if (-not $headerIndexMap.ContainsKey($header)) {
            $headerIndexMap[$header] = $index
        }

        $canonical = Get-CanonicalColumnKey -ColumnName $header
        if (-not [string]::IsNullOrWhiteSpace($canonical) -and -not $canonicalToOutput.ContainsKey($canonical)) {
            $canonicalToOutput[$canonical] = $index
        }
    }

    $secondaryToOutput = New-Object 'System.Int32[]' $SecondaryHeaders.Count
    $mappedAliasCount = 0
    $secondaryOnlyCount = 0

    for ($index = 0; $index -lt $SecondaryHeaders.Count; $index++) {
        $header = [string]$SecondaryHeaders[$index]
        if ($headerIndexMap.ContainsKey($header)) {
            $secondaryToOutput[$index] = [int]$headerIndexMap[$header]
            continue
        }

        $canonical = Get-CanonicalColumnKey -ColumnName $header
        if (-not [string]::IsNullOrWhiteSpace($canonical) -and $canonicalToOutput.ContainsKey($canonical)) {
            $secondaryToOutput[$index] = [int]$canonicalToOutput[$canonical]
            $mappedAliasCount++
            continue
        }

        $newIndex = $outputHeaders.Count
        $outputHeaders.Add($header)
        $headerIndexMap[$header] = $newIndex
        if (-not [string]::IsNullOrWhiteSpace($canonical) -and -not $canonicalToOutput.ContainsKey($canonical)) {
            $canonicalToOutput[$canonical] = $newIndex
        }
        $secondaryToOutput[$index] = $newIndex
        $secondaryOnlyCount++
    }

    return [pscustomobject]@{
        OutputHeaders = @($outputHeaders)
        SecondaryToOutput = $secondaryToOutput
        MappedAliasCount = $mappedAliasCount
        SecondaryOnlyCount = $secondaryOnlyCount
    }
}

function Write-FullOuterMergedCsv {
    param(
        [string]$PrimaryPath,
        [object]$PrimaryHeaderInfo,
        [hashtable]$SecondaryLookup,
        [object]$SecondaryHeaderInfo,
        [int[]]$SecondaryToOutput,
        [string[]]$OutputHeaders,
        [string]$OutputPath
    )

    $consumedSecondaryKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $seenPrimaryKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $writer = New-Object System.IO.StreamWriter($OutputPath, $false, [System.Text.UTF8Encoding]::new($false))
    $primaryRowCount = 0
    $matchedRowCount = 0
    $conflictCount = 0

    try {
        Write-CsvRow -Writer $writer -Values $OutputHeaders

        $parser = New-TextFieldParser -Path $PrimaryPath
        try {
            [void]$parser.ReadFields()
            while (-not $parser.EndOfData) {
                $fields = $parser.ReadFields()
                if ($null -eq $fields) {
                    continue
                }

                $primaryRowCount++
                $rowOut = New-Object string[] $OutputHeaders.Count

                for ($index = 0; $index -lt $PrimaryHeaderInfo.Headers.Count; $index++) {
                    if ($index -lt $fields.Count) {
                        $rowOut[$index] = [string]$fields[$index]
                    }
                    else {
                        $rowOut[$index] = ''
                    }
                }

                $visualId = if ($PrimaryHeaderInfo.VisualIdIndex -lt $fields.Count) { [string]$fields[$PrimaryHeaderInfo.VisualIdIndex] } else { '' }
                $lot = if ($PrimaryHeaderInfo.LotIndex -lt $fields.Count) { [string]$fields[$PrimaryHeaderInfo.LotIndex] } else { '' }
                $key = Get-MergeKey -VisualId $visualId -LotFromFs $lot

                if (-not [string]::IsNullOrWhiteSpace($key.Replace('||', ''))) {
                    if (-not $seenPrimaryKeys.Add($key)) {
                        throw "Duplicate merge key in primary CSV: $key"
                    }
                }

                if ($SecondaryLookup.ContainsKey($key)) {
                    $matchedRowCount++
                    [void]$consumedSecondaryKeys.Add($key)
                    $secondaryFields = [string[]]$SecondaryLookup[$key]

                    for ($secondaryIndex = 0; $secondaryIndex -lt $SecondaryHeaderInfo.Headers.Count; $secondaryIndex++) {
                        $outIndex = $SecondaryToOutput[$secondaryIndex]
                        $secondaryValue = if ($secondaryIndex -lt $secondaryFields.Count) { [string]$secondaryFields[$secondaryIndex] } else { '' }
                        if ([string]::IsNullOrWhiteSpace($secondaryValue)) {
                            continue
                        }

                        $currentValue = [string]$rowOut[$outIndex]
                        if ([string]::IsNullOrWhiteSpace($currentValue)) {
                            $rowOut[$outIndex] = $secondaryValue
                        }
                        elseif ($currentValue -cne $secondaryValue) {
                            $conflictCount++
                        }
                    }
                }

                Write-CsvRow -Writer $writer -Values $rowOut
            }
        }
        finally {
            $parser.Close()
        }

        $secondaryOnlyRowCount = 0
        foreach ($entry in $SecondaryLookup.GetEnumerator()) {
            $key = [string]$entry.Key
            if ($consumedSecondaryKeys.Contains($key)) {
                continue
            }

            $secondaryOnlyRowCount++
            $rowOut = New-Object string[] $OutputHeaders.Count
            $secondaryFields = [string[]]$entry.Value
            for ($secondaryIndex = 0; $secondaryIndex -lt $SecondaryHeaderInfo.Headers.Count; $secondaryIndex++) {
                $outIndex = $SecondaryToOutput[$secondaryIndex]
                if ($secondaryIndex -lt $secondaryFields.Count) {
                    $rowOut[$outIndex] = [string]$secondaryFields[$secondaryIndex]
                }
            }

            Write-CsvRow -Writer $writer -Values $rowOut
        }

        return [pscustomobject]@{
            PrimaryRowCount = $primaryRowCount
            MatchedRowCount = $matchedRowCount
            SecondaryOnlyRowCount = $secondaryOnlyRowCount
            ConflictCount = $conflictCount
            OutputRowCount = $primaryRowCount + $secondaryOnlyRowCount
        }
    }
    finally {
        $writer.Dispose()
    }
}

function Update-CsvWithIlasSummary {
    param(
        [string]$MergedCsvPath,
        [string]$IlasSummaryCsvPath
    )

    $ilasLookup = @{}
    $ilasRows = @(Import-Csv -LiteralPath $IlasSummaryCsvPath)
    if ($ilasRows.Count -eq 0) {
        throw "ILAS summary CSV is empty: $IlasSummaryCsvPath"
    }

    $ilasHeaders = @($ilasRows[0].PSObject.Properties.Name)
    $ilasHeaderInfo = [pscustomobject]@{
        VisualIdColumn = (Get-FirstExistingColumnName -CandidateNames @('VisualID', 'VISUAL_ID', 'Visual ID', 'VisualId', 'VISUALID', 'VID') -AvailableNames $ilasHeaders)
        LotColumn = (Get-FirstExistingColumnName -CandidateNames @('LotFromFs', 'LOTFROMFS', 'LOT', 'Lot', 'SortLot', 'SORT_LOT', 'LATO_LOT') -AvailableNames $ilasHeaders)
    }
    if ([string]::IsNullOrWhiteSpace($ilasHeaderInfo.VisualIdColumn) -or [string]::IsNullOrWhiteSpace($ilasHeaderInfo.LotColumn)) {
        throw "ILAS summary must contain VisualID and LotFromFs columns."
    }

    $ilasDataColumns = @($ilasHeaders | Where-Object { $_ -ne $ilasHeaderInfo.VisualIdColumn -and $_ -ne $ilasHeaderInfo.LotColumn })
    foreach ($row in $ilasRows) {
        $visualId = [string]$row.$($ilasHeaderInfo.VisualIdColumn)
        $lot = [string]$row.$($ilasHeaderInfo.LotColumn)
        $key = Get-MergeKey -VisualId $visualId -LotFromFs $lot
        if ([string]::IsNullOrWhiteSpace($key.Replace('||', ''))) {
            continue
        }

        $ilasLookup[$key] = $row
    }

        $mergedHeaderInfo = Get-HeaderInfo -Path $MergedCsvPath
        $updatedHeaders = New-Object System.Collections.Generic.List[string]
        $headerIndex = @{}

        for ($index = 0; $index -lt $mergedHeaderInfo.Headers.Count; $index++) {
            $header = [string]$mergedHeaderInfo.Headers[$index]
            $updatedHeaders.Add($header)
            if (-not $headerIndex.ContainsKey($header)) {
                $headerIndex[$header] = $index
            }
        }

        $ilasColumnToOutput = @{}
        foreach ($ilasColumn in $ilasDataColumns) {
            $targetHeader = 'ILAS_{0}' -f $ilasColumn
            if (-not $headerIndex.ContainsKey($targetHeader)) {
                $headerIndex[$targetHeader] = $updatedHeaders.Count
                $updatedHeaders.Add($targetHeader)
            }
            $ilasColumnToOutput[$ilasColumn] = [int]$headerIndex[$targetHeader]
        }

        $tempPath = '{0}.ilas.tmp' -f $MergedCsvPath
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        $writer = New-Object System.IO.StreamWriter($tempPath, $false, [System.Text.UTF8Encoding]::new($false))
        $updatedRowCount = 0
        $matchedRowCount = 0
        try {
            Write-CsvRow -Writer $writer -Values @($updatedHeaders)

            $mergedParser = New-TextFieldParser -Path $MergedCsvPath
            try {
                [void]$mergedParser.ReadFields()
                while (-not $mergedParser.EndOfData) {
                    $fields = $mergedParser.ReadFields()
                    if ($null -eq $fields) {
                        continue
                    }

                    $updatedRowCount++
                    $rowOut = New-Object string[] $updatedHeaders.Count
                    for ($index = 0; $index -lt $mergedHeaderInfo.Headers.Count; $index++) {
                        if ($index -lt $fields.Count) {
                            $rowOut[$index] = [string]$fields[$index]
                        }
                    }

                    $visualId = if ($mergedHeaderInfo.VisualIdIndex -lt $fields.Count) { [string]$fields[$mergedHeaderInfo.VisualIdIndex] } else { '' }
                    $lot = if ($mergedHeaderInfo.LotIndex -lt $fields.Count) { [string]$fields[$mergedHeaderInfo.LotIndex] } else { '' }
                    $key = Get-MergeKey -VisualId $visualId -LotFromFs $lot

                    if ($ilasLookup.ContainsKey($key)) {
                        $matchedRowCount++
                        $ilasRow = $ilasLookup[$key]
                        foreach ($ilasColumn in $ilasDataColumns) {
                            $ilasValue = [string]$ilasRow.$ilasColumn
                            if ([string]::IsNullOrWhiteSpace($ilasValue)) {
                                continue
                            }

                            $targetIndex = [int]$ilasColumnToOutput[$ilasColumn]
                            $rowOut[$targetIndex] = $ilasValue
                        }
                    }

                    Write-CsvRow -Writer $writer -Values $rowOut
                }
            }
            finally {
                $mergedParser.Close()
            }
        }
        finally {
            $writer.Dispose()
        }

        Move-Item -LiteralPath $tempPath -Destination $MergedCsvPath -Force

        return [pscustomobject]@{
            UpdatedRowCount = $updatedRowCount
            IlasMatchedRowCount = $matchedRowCount
            IlasKeyCount = $ilasLookup.Count
            AddedIlasColumnCount = $ilasDataColumns.Count
        }
}

if (-not (Test-Path -LiteralPath $PrimaryCsv -PathType Leaf)) {
    throw "PrimaryCsv not found: $PrimaryCsv"
}
if (-not (Test-Path -LiteralPath $SecondaryCsv -PathType Leaf)) {
    throw "SecondaryCsv not found: $SecondaryCsv"
}

$primaryFile = Get-Item -LiteralPath $PrimaryCsv
if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
    $primaryBase = [System.IO.Path]::GetFileNameWithoutExtension($PrimaryCsv)
    $secondaryBase = [System.IO.Path]::GetFileNameWithoutExtension($SecondaryCsv)
    $OutputCsv = Join-Path $primaryFile.DirectoryName ('{0}__merged_with__{1}.csv' -f $primaryBase, $secondaryBase)
}

if ([string]::IsNullOrWhiteSpace($IlasOutputDirectory)) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $IlasOutputDirectory = Join-Path $primaryFile.DirectoryName ('_ilas_merge_{0}' -f $timestamp)
}

if (-not (Test-Path -LiteralPath $IlasOutputDirectory)) {
    New-Item -ItemType Directory -Path $IlasOutputDirectory | Out-Null
}

Write-Host '=== NVLAX weekly full-outer merge ===' -ForegroundColor Green
Write-Host "Primary CSV:   $PrimaryCsv"
Write-Host "Secondary CSV: $SecondaryCsv"
Write-Host "Output CSV:    $OutputCsv"
Write-Host "ILAS output:   $IlasOutputDirectory"
Write-Host "ILAS summary:  $ExistingIlasSummaryCsv"
Write-Host "Reuse merged:  $($ReuseMergedCsv.IsPresent)"
Write-Host ''

if (-not $ReuseMergedCsv.IsPresent) {
    $primaryHeaderInfo = Get-HeaderInfo -Path $PrimaryCsv
    $secondaryHeaderInfo = Get-HeaderInfo -Path $SecondaryCsv

    Write-Host ('Primary keys:   {0} / {1}' -f $primaryHeaderInfo.VisualIdColumn, $primaryHeaderInfo.LotColumn)
    Write-Host ('Secondary keys: {0} / {1}' -f $secondaryHeaderInfo.VisualIdColumn, $secondaryHeaderInfo.LotColumn)

    $mappingInfo = Build-SecondaryMapping -PrimaryHeaders $primaryHeaderInfo.Headers -SecondaryHeaders $secondaryHeaderInfo.Headers
    Write-Host ('Mapped secondary aliases onto existing columns: {0}' -f $mappingInfo.MappedAliasCount)
    Write-Host ('Secondary-only columns appended:             {0}' -f $mappingInfo.SecondaryOnlyCount)
    Write-Host ('Final output column count:                   {0}' -f $mappingInfo.OutputHeaders.Count)
    Write-Host ''

    $secondaryImport = Import-SecondaryLookup -Path $SecondaryCsv -HeaderInfo $secondaryHeaderInfo
    Write-Host ('Loaded secondary rows: {0}' -f $secondaryImport.RowCount)

    $mergeStats = Write-FullOuterMergedCsv `
        -PrimaryPath $PrimaryCsv `
        -PrimaryHeaderInfo $primaryHeaderInfo `
        -SecondaryLookup $secondaryImport.Lookup `
        -SecondaryHeaderInfo $secondaryHeaderInfo `
        -SecondaryToOutput $mappingInfo.SecondaryToOutput `
        -OutputHeaders $mappingInfo.OutputHeaders `
        -OutputPath $OutputCsv

    Write-Host ''
    Write-Host 'Merge complete.' -ForegroundColor Green
    Write-Host ('Primary rows written:          {0}' -f $mergeStats.PrimaryRowCount)
    Write-Host ('Matched keys:                  {0}' -f $mergeStats.MatchedRowCount)
    Write-Host ('Secondary-only rows appended:  {0}' -f $mergeStats.SecondaryOnlyRowCount)
    Write-Host ('Output rows:                   {0}' -f $mergeStats.OutputRowCount)
    Write-Host ('Non-empty shared-field diffs:  {0}' -f $mergeStats.ConflictCount)
}
elseif (-not (Test-Path -LiteralPath $OutputCsv -PathType Leaf)) {
    throw "ReuseMergedCsv was requested but the merged output does not exist: $OutputCsv"
}
else {
    Write-Host 'Skipping merge stage and reusing existing merged CSV.' -ForegroundColor Cyan
}

$ilasStats = $null
if (-not $SkipIlas.IsPresent) {
    $ilasSummaryPath = $ExistingIlasSummaryCsv
    if ([string]::IsNullOrWhiteSpace($ilasSummaryPath)) {
        $resolvedIlasScriptPath = Resolve-IlasScriptPath -ConfiguredPath $IlasScriptPath
        Write-Host ''
        Write-Host 'Running ILAS extraction for secondary Visual IDs...' -ForegroundColor Cyan
        & $resolvedIlasScriptPath `
            -UpsvfReferenceCsv $SecondaryCsv `
            -OutputDirectory $IlasOutputDirectory `
            -ProgramPattern $ProgramPattern `
            -LastNDaysTestEnd $LastNDaysTestEnd `
            -AquaPullTimeoutSeconds $AquaPullTimeoutSeconds `
            -AquaPullPollSeconds $AquaPullPollSeconds

        $ilasSummaryPath = Get-IlasSummaryPath -DirectoryPath $IlasOutputDirectory
    }
    elseif (-not (Test-Path -LiteralPath $ilasSummaryPath -PathType Leaf)) {
        throw "ExistingIlasSummaryCsv not found: $ilasSummaryPath"
    }

    Write-Host "ILAS summary: $ilasSummaryPath"

    $ilasStats = Update-CsvWithIlasSummary -MergedCsvPath $OutputCsv -IlasSummaryCsvPath $ilasSummaryPath
    Write-Host ('ILAS keys loaded:              {0}' -f $ilasStats.IlasKeyCount)
    Write-Host ('Merged rows updated by ILAS:   {0}' -f $ilasStats.IlasMatchedRowCount)
    Write-Host ('ILAS data columns available:   {0}' -f $ilasStats.AddedIlasColumnCount)
}

$outputFile = Get-Item -LiteralPath $OutputCsv
Write-Host ''
Write-Host ('Final output size MB: {0}' -f [math]::Round($outputFile.Length / 1MB, 2))
Write-Host ('Final output path:    {0}' -f $OutputCsv)