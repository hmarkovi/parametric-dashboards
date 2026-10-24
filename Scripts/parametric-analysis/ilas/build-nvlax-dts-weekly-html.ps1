#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsvPath,
    [string]$OutputDirectory = "",
    [string]$OutputHtmlPath = "",
    [int]$MaxScatterPointsPerDomain = 1500,
    [int]$MaxBucketsPerDomain = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

$script:PreferredPlotFrequencies = @(1.2, 2.8, 3.8, 4.3, 4.6)
$script:ReleasedClassProgramAllowlists = @{
    'NVLAX' = @('25C00', '25D00', '25D10', '25E00')
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

function Convert-ToDoubleOrNull {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $parsed = 0.0
    if ([double]::TryParse($text.Trim(), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function ConvertTo-HtmlEscaped {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

function ConvertTo-CsvField {
    param([object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ($text.IndexOfAny(@([char]',', [char]'"', [char]"`r", [char]"`n")) -ge 0) {
        return '"{0}"' -f ($text -replace '"', '""')
    }

    return $text
}

function Write-CsvLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.StreamWriter]$Writer,
        [Parameter(Mandatory = $true)]
        [object[]]$Values
    )

    $Writer.WriteLine((@($Values | ForEach-Object { ConvertTo-CsvField -Value $_ }) -join ','))
}

function Get-SafeId {
    param([Parameter(Mandatory = $true)][string]$Value)

    return (($Value -replace '[^A-Za-z0-9]+', '-') -replace '(^-+|-+$)', '').ToLowerInvariant()
}

function Get-QuantileLinear {
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Values,
        [Parameter(Mandatory = $true)]
        [double]$Quantile
    )

    if ($Values.Count -eq 0) { return $null }
    if ($Values.Count -eq 1) { return $Values[0] }

    $sorted = @($Values | Sort-Object)
    $position = ($sorted.Count - 1) * $Quantile
    $lowIndex = [int][math]::Floor($position)
    $highIndex = [int][math]::Ceiling($position)

    if ($lowIndex -eq $highIndex) {
        return $sorted[$lowIndex]
    }

    $weight = $position - $lowIndex
    return $sorted[$lowIndex] + (($sorted[$highIndex] - $sorted[$lowIndex]) * $weight)
}

function Resolve-DomainName {
    param([Parameter(Mandatory = $true)][string]$DomainToken)

    $token = $DomainToken.Trim().ToUpperInvariant()
    $baseToken = ($token -replace '\d+$', '')

    $aliases = @{
        'AT'    = 'Atom'
        'ATOM'  = 'Atom'
        'CR'    = 'Core'
        'CORE'  = 'Core'
        'CCF'   = 'Ring'
        'CLR'   = 'Ring'
        'RING'  = 'Ring'
        'GT'    = 'GT'
        'GTVG'  = 'GTVG'
        'SAAT'  = 'SA-Atom'
        'SAQ'   = 'SAQ'
        'SAC'   = 'SAC'
        'SACD'  = 'SACD'
        'SADPU' = 'SADPU'
        'SAIOC' = 'SAIOC'
        'SAME'  = 'SAME'
        'SAN'   = 'SAN'
        'SAPS'  = 'SAPS'
        'NPU'   = 'NPU'
        'HUB'   = 'HUB'
    }

    if ($aliases.ContainsKey($baseToken)) {
        return $aliases[$baseToken]
    }

    return $baseToken
}

function Get-ClassProgramToken {
    param([string]$ProgramName)

    if ([string]::IsNullOrWhiteSpace($ProgramName)) { return $null }

    $match = [regex]::Match($ProgramName.Trim().ToUpperInvariant(), '(?<tp>\d{2}[A-Z][A-Z0-9]{2})(?=S\d+$|[A-Z]{1,2}\d+$)')
    if ($match.Success) {
        return $match.Groups['tp'].Value
    }

    return $null
}

function Get-ProgramFamily {
    param([string]$ProgramName)

    if ([string]::IsNullOrWhiteSpace($ProgramName)) { return $null }

    $match = [regex]::Match($ProgramName.Trim().ToUpperInvariant(), '^(?<family>[A-Z]+)')
    if ($match.Success) {
        return $match.Groups['family'].Value
    }

    return $null
}

function Get-ReleasedClassProgramToken {
    param([string]$ProgramName)

    if ([string]::IsNullOrWhiteSpace($ProgramName)) { return $null }

    $match = [regex]::Match($ProgramName.Trim().ToUpperInvariant(), '(?<tp>\d{2}[A-Z]\d0)S\d+$')
    if ($match.Success) {
        return $match.Groups['tp'].Value
    }

    return $null
}

function Test-IsReleasedClassProgram {
    param([string]$ProgramName)

    $releasedClassProgramToken = Get-ReleasedClassProgramToken -ProgramName $ProgramName
    if ([string]::IsNullOrWhiteSpace($releasedClassProgramToken)) {
        return $false
    }

    $programFamily = Get-ProgramFamily -ProgramName $ProgramName
    if (-not [string]::IsNullOrWhiteSpace($programFamily) -and $script:ReleasedClassProgramAllowlists.ContainsKey($programFamily)) {
        return $script:ReleasedClassProgramAllowlists[$programFamily] -contains $releasedClassProgramToken
    }

    return $true
}

function Get-PreferredFrequencyOrderIndex {
    param([string]$FrequencyLabel)

    for ($index = 0; $index -lt $script:PreferredPlotFrequencies.Count; $index++) {
        if (('{0:0.0}' -f $script:PreferredPlotFrequencies[$index]) -eq $FrequencyLabel) {
            return $index
        }
    }

    return 999
}

function Test-IsPreferredFrequencyLabel {
    param([string]$FrequencyLabel)

    foreach ($freq in $script:PreferredPlotFrequencies) {
        if (('{0:0.0}' -f $freq) -eq $FrequencyLabel) {
            return $true
        }
    }

    return $false
}

function Get-ModuleToken {
    param(
        [string]$Setter,
        [string]$LimiterPattern
    )

    foreach ($source in @($Setter, $LimiterPattern)) {
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $upper = $source.Trim().ToUpperInvariant()

        $exact = [regex]::Match($upper, '(?<module>(ARR|FUN|SCN)_[A-Z0-9]+(?:_[A-Z0-9]+)?)')
        if ($exact.Success) {
            return $exact.Groups['module'].Value
        }

        if ($upper -match '(^|[^A-Z])(ARR|ARRAY)([^A-Z]|$)') { return 'ARR' }
        if ($upper -match '(^|[^A-Z])(FUN|FUNCTIONAL|SBFT)([^A-Z]|$)') { return 'FUN' }
        if ($upper -match '(^|[^A-Z])(SCN|SCAN|ATSPEED)([^A-Z]|$)') { return 'SCN' }
    }

    return 'UNKNOWN'
}

function Get-ModuleSortOrder {
    param([string]$ModuleName)

    if ([string]::IsNullOrWhiteSpace($ModuleName)) { return 9 }
    $upper = $ModuleName.ToUpperInvariant()

    if ($upper.StartsWith('ARR')) { return 1 }
    if ($upper.StartsWith('FUN')) { return 2 }
    if ($upper.StartsWith('SCN')) { return 3 }
    if ($upper -eq 'UNKNOWN') { return 9 }
    return 5
}

function Get-DisplayFrequencyLabel {
    param([double]$FrequencyGHz)

    return ('{0:0.0}' -f $FrequencyGHz)
}

function ConvertTo-SvgNumber {
    param([double]$Value)

    return $Value.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-ChartGroupSummaries {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$DomainRows
    )

    $grouped = @(
        $DomainRows |
            Group-Object -Property FrequencyLabel, Module |
            Sort-Object {
                $sample = $_.Group | Select-Object -First 1
                '{0:D3}|{1:D2}|{2}' -f (Get-PreferredFrequencyOrderIndex -FrequencyLabel $sample.FrequencyLabel), (Get-ModuleSortOrder -ModuleName $sample.Module), $sample.Module
            }
    )

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($item in $grouped) {
        $sample = $item.Group | Select-Object -First 1
        $values = @($item.Group | ForEach-Object { $_.RawValues } | ForEach-Object { $_ })
        $sortedValues = @($values | Sort-Object)
        $q1 = Get-QuantileLinear -Values $sortedValues -Quantile 0.25
        $median = Get-QuantileLinear -Values $sortedValues -Quantile 0.5
        $q3 = Get-QuantileLinear -Values $sortedValues -Quantile 0.75
        $iqr = $q3 - $q1
        $lowerFence = $q1 - (1.5 * $iqr)
        $upperFence = $q3 + (1.5 * $iqr)
        $inFence = @($sortedValues | Where-Object { $_ -ge $lowerFence -and $_ -le $upperFence })
        $lowerWhisker = if ($inFence.Count -gt 0) { $inFence[0] } else { $sortedValues[0] }
        $upperWhisker = if ($inFence.Count -gt 0) { $inFence[$inFence.Count - 1] } else { $sortedValues[$sortedValues.Count - 1] }
        $outliers = @($sortedValues | Where-Object { $_ -lt $lowerWhisker -or $_ -gt $upperWhisker })
        $coreCoverage = @(
            $item.Group |
                ForEach-Object { ([string]$_.CoreCoverage) -split ';\s*' } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )

        $result.Add([pscustomobject]@{
            ClassTestProgram = $sample.ClassTestProgram
            Domain = $sample.Domain
            FrequencyGHz = $sample.FrequencyGHz
            FrequencyLabel = $sample.FrequencyLabel
            Module = $sample.Module
            BucketLabel = ('{0} | {1}' -f $sample.FrequencyLabel, $sample.Module)
            ObservationCount = $sortedValues.Count
            UnitCount = ($item.Group | Measure-Object -Property UnitCount -Sum).Sum
            CoreCoverage = ($coreCoverage -join '; ')
            CoreCount = $coreCoverage.Count
            MinDtsC = [math]::Round($sortedValues[0], 4)
            P25DtsC = [math]::Round($q1, 4)
            MedianDtsC = [math]::Round($median, 4)
            MeanDtsC = [math]::Round((($sortedValues | Measure-Object -Average).Average), 4)
            P75DtsC = [math]::Round($q3, 4)
            MaxDtsC = [math]::Round($sortedValues[$sortedValues.Count - 1], 4)
            LowerWhiskerDtsC = [math]::Round($lowerWhisker, 4)
            UpperWhiskerDtsC = [math]::Round($upperWhisker, 4)
            DeltaFrom100C = [math]::Round(($median - 100.0), 4)
            Direction = if ($median -gt 100.0) { 'Above' } elseif ($median -lt 100.0) { 'Below' } else { 'OnTarget' }
            SetterSummary = (@(
                $item.Group |
                    ForEach-Object { ([string]$_.SetterSummary) -split ';\s*' } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            ) -join '; ')
            FullProgramNames = (@(
                $item.Group |
                    ForEach-Object { ([string]$_.FullProgramNames) -split ';\s*' } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            ) -join '; ')
            RawValues = $sortedValues
            Outliers = $outliers
        }) | Out-Null
    }

    $preferredMap = @{}
    foreach ($freq in $script:PreferredPlotFrequencies) {
        $preferredMap[('{0:0.0}' -f $freq)] = $true
    }

    $containsPreferred = @($result | Where-Object { $preferredMap.ContainsKey($_.FrequencyLabel) }).Count -gt 0
    if ($containsPreferred) {
        return @($result | Where-Object { $preferredMap.ContainsKey($_.FrequencyLabel) } | Sort-Object FrequencyGHz, @{ Expression = { Get-ModuleSortOrder -ModuleName $_.Module } }, Module)
    }

    return @($result | Sort-Object FrequencyGHz, @{ Expression = { Get-ModuleSortOrder -ModuleName $_.Module } }, Module)
}

function Get-ScientificGroupedBoxplotSvg {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ChartRows,
        [Parameter(Mandatory = $true)]
        [string]$ChartTitle
    )

    if ($ChartRows.Count -eq 0) {
        return "<div class='placeholder'>No DTS observations available for chart.</div>"
    }

    $width = 1680
    $height = 595
    $marginLeft = 96
    $marginRight = 28
    $marginTop = 28
    $marginBottom = 170
    $plotWidth = $width - $marginLeft - $marginRight
    $plotHeight = $height - $marginTop - $marginBottom

    $allValues = @($ChartRows | ForEach-Object { $_.RawValues } | ForEach-Object { $_ })
    $minValue = [math]::Min(90.0, [math]::Floor((($allValues | Measure-Object -Minimum).Minimum) / 5.0) * 5.0)
    $maxValue = [math]::Max(155.0, [math]::Ceiling((($allValues | Measure-Object -Maximum).Maximum) / 5.0) * 5.0)
    if ($maxValue -le $minValue) { $maxValue = $minValue + 10.0 }

    $freqGroups = @($ChartRows | Group-Object -Property FrequencyLabel | Sort-Object { [double]$_.Name })
    $groupCount = [math]::Max($freqGroups.Count, 1)
    $groupWidth = $plotWidth / $groupCount
    $meanPoints = New-Object System.Collections.Generic.List[string]
    $svg = New-Object System.Text.StringBuilder

    $toY = {
        param([double]$value)
        return $marginTop + (($maxValue - $value) / ($maxValue - $minValue) * $plotHeight)
    }

    [void]$svg.AppendLine(("<svg viewBox='0 0 {0} {1}' class='chart-svg scientific-chart' role='img' aria-label='{2}'>" -f $width, $height, (ConvertTo-HtmlEscaped -Text $ChartTitle)))
    [void]$svg.AppendLine("<rect x='0' y='0' width='$width' height='$height' fill='#ffffff' />")

    for ($grid = [int]$minValue; $grid -le [int]$maxValue; $grid += 5) {
        $y = & $toY ([double]$grid)
        $strokeWidth = if (($grid % 10) -eq 0) { 1.2 } else { 0.8 }
        $gridClass = if (($grid % 10) -eq 0) { 'major-grid' } else { 'minor-grid' }
        [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{2}' y2='{1}' class='{3}' stroke-width='{4}' />" -f (ConvertTo-SvgNumber $marginLeft), (ConvertTo-SvgNumber $y), (ConvertTo-SvgNumber ($width - $marginRight)), $gridClass, (ConvertTo-SvgNumber $strokeWidth)))
        if (($grid % 10) -eq 0) {
            [void]$svg.AppendLine(("<text x='{0}' y='{1}' class='axis-label'>{2}</text>" -f (ConvertTo-SvgNumber ($marginLeft - 10)), (ConvertTo-SvgNumber ($y + 4)), $grid))
        }
    }

    [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{0}' y2='{2}' class='axis-line' />" -f (ConvertTo-SvgNumber $marginLeft), (ConvertTo-SvgNumber $marginTop), (ConvertTo-SvgNumber ($height - $marginBottom))))
    [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{2}' y2='{1}' class='axis-line' />" -f (ConvertTo-SvgNumber $marginLeft), (ConvertTo-SvgNumber ($height - $marginBottom)), (ConvertTo-SvgNumber ($width - $marginRight))))

    for ($groupIndex = 0; $groupIndex -lt $freqGroups.Count; $groupIndex++) {
        $freqGroup = $freqGroups[$groupIndex]
        $rows = @($freqGroup.Group | Sort-Object @{ Expression = { Get-ModuleSortOrder -ModuleName $_.Module } }, Module)
        $groupStartX = $marginLeft + ($groupWidth * $groupIndex)
        $groupCenterX = $groupStartX + ($groupWidth / 2.0)
        $boxSpacing = $groupWidth / ([math]::Max($rows.Count, 1) + 1.2)
        $boxWidth = [math]::Min(30, $boxSpacing * 0.46)

        if ($groupIndex -gt 0) {
            [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{0}' y2='{2}' class='group-separator' />" -f (ConvertTo-SvgNumber $groupStartX), (ConvertTo-SvgNumber $marginTop), (ConvertTo-SvgNumber ($height - $marginBottom))))
        }

        [void]$svg.AppendLine(("<text x='{0}' y='{1}' class='freq-label'>{2} GHz</text>" -f (ConvertTo-SvgNumber $groupCenterX), (ConvertTo-SvgNumber ($height - 62)), (ConvertTo-HtmlEscaped -Text $freqGroup.Name)))

        for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
            $row = $rows[$rowIndex]
            $centerX = $groupStartX + ($boxSpacing * ($rowIndex + 1))
            $leftX = $centerX - ($boxWidth / 2.0)
            $rightX = $centerX + ($boxWidth / 2.0)
            $q1Y = & $toY ([double]$row.P25DtsC)
            $medianY = & $toY ([double]$row.MedianDtsC)
            $q3Y = & $toY ([double]$row.P75DtsC)
            $lowerWhiskerY = & $toY ([double]$row.LowerWhiskerDtsC)
            $upperWhiskerY = & $toY ([double]$row.UpperWhiskerDtsC)
            $meanY = & $toY ([double]$row.MeanDtsC)

            [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{0}' y2='{2}' class='box-red' />" -f (ConvertTo-SvgNumber $centerX), (ConvertTo-SvgNumber $lowerWhiskerY), (ConvertTo-SvgNumber $upperWhiskerY)))
            [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{2}' y2='{1}' class='box-red' />" -f (ConvertTo-SvgNumber ($centerX - 9)), (ConvertTo-SvgNumber $lowerWhiskerY), (ConvertTo-SvgNumber ($centerX + 9))))
            [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{2}' y2='{1}' class='box-red' />" -f (ConvertTo-SvgNumber ($centerX - 9)), (ConvertTo-SvgNumber $upperWhiskerY), (ConvertTo-SvgNumber ($centerX + 9))))
            [void]$svg.AppendLine(("<rect x='{0}' y='{1}' width='{2}' height='{3}' class='box-red' fill='none' />" -f (ConvertTo-SvgNumber $leftX), (ConvertTo-SvgNumber $q3Y), (ConvertTo-SvgNumber ($rightX - $leftX)), (ConvertTo-SvgNumber ([math]::Max(1.0, ($q1Y - $q3Y))))))
            [void]$svg.AppendLine(("<line x1='{0}' y1='{1}' x2='{2}' y2='{1}' class='box-median' />" -f (ConvertTo-SvgNumber $leftX), (ConvertTo-SvgNumber $medianY), (ConvertTo-SvgNumber $rightX)))
            [void]$meanPoints.Add(('{0},{1}' -f (ConvertTo-SvgNumber $centerX), (ConvertTo-SvgNumber $meanY)))

            foreach ($outlier in $row.Outliers) {
                $outlierY = & $toY ([double]$outlier)
                [void]$svg.AppendLine(("<circle cx='{0}' cy='{1}' r='2.8' class='outlier-red' />" -f (ConvertTo-SvgNumber $centerX), (ConvertTo-SvgNumber $outlierY)))
            }

            [void]$svg.AppendLine(("<text x='{0}' y='{1}' class='module-label' transform='rotate(28 {0} {1})'>{2}</text>" -f (ConvertTo-SvgNumber ($centerX - 10)), (ConvertTo-SvgNumber ($height - 98)), (ConvertTo-HtmlEscaped -Text $row.Module)))
        }
    }

    if ($meanPoints.Count -gt 1) {
        [void]$svg.AppendLine(("<polyline points='{0}' class='mean-line' />" -f ($meanPoints -join ' ')))
    }
    foreach ($meanPoint in $meanPoints) {
        $parts = $meanPoint -split ','
        [void]$svg.AppendLine(("<circle cx='{0}' cy='{1}' r='3.2' class='mean-marker' />" -f $parts[0], $parts[1]))
    }

    [void]$svg.AppendLine(("<text x='{0}' y='{1}' class='axis-title'>Frequency | Module | Core</text>" -f (ConvertTo-SvgNumber ($marginLeft + ($plotWidth / 2.0) - 96)), (ConvertTo-SvgNumber ($height - 18))))
    [void]$svg.AppendLine(("<text x='{0}' y='{1}' class='axis-title' transform='rotate(-90 {0} {1})'>MaxDTS (C)</text>" -f (ConvertTo-SvgNumber 24), (ConvertTo-SvgNumber ($marginTop + ($plotHeight / 2.0)))))
    [void]$svg.AppendLine("</svg>")
    return $svg.ToString()
}

if (-not (Test-Path -LiteralPath $InputCsvPath)) {
    throw "Input CSV not found: $InputCsvPath"
}

$inputItem = Get-Item -LiteralPath $InputCsvPath
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $inputItem.DirectoryName
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($OutputHtmlPath)) {
    $OutputHtmlPath = Join-Path $OutputDirectory 'DTS Analysis.html'
}

$runStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pointsCsvPath = Join-Path $OutputDirectory ("dts_temperature_points_{0}.csv" -f $runStamp)
$bucketCsvPath = Join-Path $OutputDirectory ("dts_temperature_bucket_summary_{0}.csv" -f $runStamp)
$violationsCsvPath = Join-Path $OutputDirectory ("dts_temperature_violations_{0}.csv" -f $runStamp)
$filteredProgramsCsvPath = Join-Path $OutputDirectory ("dts_filtered_programs_{0}.csv" -f $runStamp)
$manifestPath = Join-Path $OutputDirectory 'run_manifest.json'

$filteredProgramCountMap = @{}
$programInfoMap = @{}
$bucketMap = @{}
$unknownModuleCount = 0
$observationCount = 0
$visualIdColumn = $null
$lotColumn = $null
$programColumn = $null

$parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($InputCsvPath)
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$parser.SetDelimiters(',')
$parser.HasFieldsEnclosedInQuotes = $true
$parser.TrimWhiteSpace = $false

$pointsWriter = $null

try {
    if ($parser.EndOfData) {
        throw "Input CSV is empty: $InputCsvPath"
    }

    $headers = $parser.ReadFields()
    if ($null -eq $headers -or $headers.Count -eq 0) {
        throw "Could not read the CSV header from: $InputCsvPath"
    }

    $columns = @($headers)
    $headerIndex = @{}
    for ($index = 0; $index -lt $columns.Count; $index++) {
        $headerIndex[$columns[$index]] = $index
    }

    $visualIdColumn = Get-FirstExistingColumnName -CandidateNames @('VISUAL_ID', 'Visual ID', 'VisualId', 'VISUALID', 'VID') -AvailableNames $columns
    $lotColumn = Get-FirstExistingColumnName -CandidateNames @('LOTFROMFS', 'Lot_CLASSHOT', 'Lot', 'LOT') -AvailableNames $columns
    $programColumn = Get-FirstExistingColumnName -CandidateNames @('Program Name_CLASSHOT', 'Program Name', 'Program Name_RCS', 'PROGRAM_NAME', 'PROGRAM', 'Program', 'ProgramName') -AvailableNames $columns

    if (-not $visualIdColumn) { throw 'Could not find a visual ID column in the input CSV.' }
    if (-not $lotColumn) { throw 'Could not find a lot column in the input CSV.' }
    if (-not $programColumn) { throw 'Could not find a Class program column in the input CSV.' }

    $visualIdIndex = $headerIndex[$visualIdColumn]
    $lotIndex = $headerIndex[$lotColumn]
    $programIndex = $headerIndex[$programColumn]

    $dtsColumns = @($columns | Where-Object { $_ -like 'ILAS_*_MaxDTS_C' })
    if ($dtsColumns.Count -eq 0) {
        throw 'Could not find any ILAS DTS columns ending in _MaxDTS_C.'
    }

    $prefixPattern = '^ILAS_(?<Domain>.+?)_(?<Corner>FMIN|F\d+)_Flow(?<Flow>[^_]+)_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C(?<CoreIndex>\d+)_MaxDTS_C$'
    $prefixSpecs = New-Object System.Collections.Generic.List[object]
    foreach ($col in $dtsColumns) {
        $match = [regex]::Match($col, $prefixPattern)
        if (-not $match.Success) { continue }

        $setterColumn = ($col -replace '_MaxDTS_C$', '_Setter')
        $lpColumn = ($col -replace '_MaxDTS_C$', '_LP')
        $frequencyValue = [double]::Parse($match.Groups['Freq'].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        $prefixSpecs.Add([pscustomobject]@{
            MaxDtsColumn = $col
            MaxDtsIndex = $headerIndex[$col]
            SetterColumn = $setterColumn
            SetterIndex = if ($headerIndex.ContainsKey($setterColumn)) { $headerIndex[$setterColumn] } else { -1 }
            LpColumn = $lpColumn
            LpIndex = if ($headerIndex.ContainsKey($lpColumn)) { $headerIndex[$lpColumn] } else { -1 }
            DomainToken = $match.Groups['Domain'].Value
            DomainName = Resolve-DomainName -DomainToken $match.Groups['Domain'].Value
            Corner = $match.Groups['Corner'].Value
            Flow = $match.Groups['Flow'].Value
            FrequencyGHz = $frequencyValue
            FrequencyLabel = Get-DisplayFrequencyLabel -FrequencyGHz $frequencyValue
            CoreIndex = [int]$match.Groups['CoreIndex'].Value
        }) | Out-Null
    }

    if ($prefixSpecs.Count -eq 0) {
        throw 'ILAS DTS columns were found, but none matched the expected ILAS prefix pattern.'
    }

    $pointsWriter = New-Object System.IO.StreamWriter($pointsCsvPath, $false, [System.Text.Encoding]::UTF8, 131072)
    Write-CsvLine -Writer $pointsWriter -Values @('VisualID', 'LotFromFs', 'FullProgramName', 'ClassTestProgram', 'Domain', 'DomainToken', 'Corner', 'Flow', 'FrequencyGHz', 'FrequencyLabel', 'CoreIndex', 'CoreLabel', 'Module', 'Setter', 'LimiterPattern', 'DtsTemperatureC')

    while (-not $parser.EndOfData) {
        $fields = $parser.ReadFields()
        if ($null -eq $fields) { continue }

        $fullProgramName = if ($programIndex -lt $fields.Count) { [string]$fields[$programIndex] } else { '' }
        $classProgramToken = Get-ClassProgramToken -ProgramName $fullProgramName
        $releasedClassProgramToken = Get-ReleasedClassProgramToken -ProgramName $fullProgramName

        if (-not (Test-IsReleasedClassProgram -ProgramName $fullProgramName)) {
            $reason = if ([string]::IsNullOrWhiteSpace($classProgramToken)) { 'CouldNotExtractClassProgramToken' } else { 'NotOfficialReleasedClassTP' }
            $filteredKey = "{0}`t{1}`t{2}" -f $fullProgramName, $classProgramToken, $reason
            if ($filteredProgramCountMap.ContainsKey($filteredKey)) {
                $filteredProgramCountMap[$filteredKey]++
            }
            else {
                $filteredProgramCountMap[$filteredKey] = 1
            }
            continue
        }

        $visualId = if ($visualIdIndex -lt $fields.Count) { [string]$fields[$visualIdIndex] } else { '' }
        $lotFromFs = if ($lotIndex -lt $fields.Count) { [string]$fields[$lotIndex] } else { '' }

        if (-not $programInfoMap.ContainsKey($releasedClassProgramToken)) {
            $programInfoMap[$releasedClassProgramToken] = [pscustomobject]@{
                ClassTestProgram = $releasedClassProgramToken
                FullProgramNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                VisualIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                ObservationCount = 0
            }
        }

        [void]$programInfoMap[$releasedClassProgramToken].FullProgramNames.Add($fullProgramName)
        if (-not [string]::IsNullOrWhiteSpace($visualId)) {
            [void]$programInfoMap[$releasedClassProgramToken].VisualIds.Add($visualId)
        }

        foreach ($spec in $prefixSpecs) {
            $dtsText = if ($spec.MaxDtsIndex -lt $fields.Count) { $fields[$spec.MaxDtsIndex] } else { '' }
            $dtsValue = Convert-ToDoubleOrNull -Value $dtsText
            if ($null -eq $dtsValue) { continue }

            $setter = if ($spec.SetterIndex -ge 0 -and $spec.SetterIndex -lt $fields.Count) { [string]$fields[$spec.SetterIndex] } else { '' }
            $limiterPattern = if ($spec.LpIndex -ge 0 -and $spec.LpIndex -lt $fields.Count) { [string]$fields[$spec.LpIndex] } else { '' }
            $moduleToken = Get-ModuleToken -Setter $setter -LimiterPattern $limiterPattern
            if ($moduleToken -eq 'UNKNOWN') {
                $unknownModuleCount++
            }

            $bucketKey = "{0}`t{1}`t{2}`t{3}" -f $releasedClassProgramToken, $spec.DomainName, $spec.FrequencyLabel, $moduleToken
            if (-not $bucketMap.ContainsKey($bucketKey)) {
                $bucketMap[$bucketKey] = [pscustomobject]@{
                    ClassTestProgram = $releasedClassProgramToken
                    Domain = $spec.DomainName
                    DomainToken = $spec.DomainToken
                    FrequencyGHz = $spec.FrequencyGHz
                    FrequencyLabel = $spec.FrequencyLabel
                    Module = $moduleToken
                    Values = New-Object 'System.Collections.Generic.List[double]'
                    VisualIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                    CoreLabels = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                    Setters = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                    FullProgramNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                    ObservationCount = 0
                }
            }

            $bucket = $bucketMap[$bucketKey]
            $bucket.Values.Add([double]$dtsValue) | Out-Null
            $bucket.ObservationCount++
            if (-not [string]::IsNullOrWhiteSpace($visualId)) {
                [void]$bucket.VisualIds.Add($visualId)
            }
            [void]$bucket.CoreLabels.Add(('core{0}' -f $spec.CoreIndex))
            if (-not [string]::IsNullOrWhiteSpace($setter)) {
                [void]$bucket.Setters.Add($setter)
            }
            if (-not [string]::IsNullOrWhiteSpace($fullProgramName)) {
                [void]$bucket.FullProgramNames.Add($fullProgramName)
            }

            $programInfoMap[$releasedClassProgramToken].ObservationCount++
            $observationCount++

            Write-CsvLine -Writer $pointsWriter -Values @(
                $visualId,
                $lotFromFs,
                $fullProgramName,
                $releasedClassProgramToken,
                $spec.DomainName,
                $spec.DomainToken,
                $spec.Corner,
                $spec.Flow,
                ('{0:0.000}' -f $spec.FrequencyGHz),
                $spec.FrequencyLabel,
                $spec.CoreIndex,
                ('core{0}' -f $spec.CoreIndex),
                $moduleToken,
                $setter,
                $limiterPattern,
                ([math]::Round($dtsValue, 4).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            )
        }
    }
}
finally {
    if ($null -ne $pointsWriter) {
        $pointsWriter.Dispose()
    }
    if ($null -ne $parser) {
        $parser.Close()
    }
}

$filteredProgramSummaryRows = @(
    $filteredProgramCountMap.Keys |
        Sort-Object |
        ForEach-Object {
            $parts = $_ -split "`t", 3
            [pscustomobject]@{
                FullProgramName = $parts[0]
                ClassTestProgram = $parts[1]
                Reason = $parts[2]
                RowCount = $filteredProgramCountMap[$_]
            }
        }
)

if ($filteredProgramSummaryRows.Count -gt 0) {
    $filteredProgramSummaryRows | Export-Csv -LiteralPath $filteredProgramsCsvPath -NoTypeInformation -Encoding UTF8
}
else {
    @([pscustomobject]@{ FullProgramName = ''; ClassTestProgram = ''; Reason = 'None'; RowCount = 0 }) | Export-Csv -LiteralPath $filteredProgramsCsvPath -NoTypeInformation -Encoding UTF8
}

$bucketRenderRows = New-Object System.Collections.Generic.List[object]
$violationRows = New-Object System.Collections.Generic.List[object]

foreach ($bucket in $bucketMap.Values) {
    $values = @($bucket.Values | Sort-Object)
    if ($values.Count -eq 0) { continue }

    $q1 = Get-QuantileLinear -Values $values -Quantile 0.25
    $median = Get-QuantileLinear -Values $values -Quantile 0.5
    $q3 = Get-QuantileLinear -Values $values -Quantile 0.75
    $mean = ($values | Measure-Object -Average).Average
    $deltaFromTarget = [math]::Round(($median - 100.0), 4)
    $direction = if ($deltaFromTarget -gt 0) { 'Above' } elseif ($deltaFromTarget -lt 0) { 'Below' } else { 'OnTarget' }

    $renderRow = [pscustomobject]@{
        ClassTestProgram = $bucket.ClassTestProgram
        Domain = $bucket.Domain
        DomainToken = $bucket.DomainToken
        FrequencyGHz = $bucket.FrequencyGHz
        FrequencyLabel = $bucket.FrequencyLabel
        Module = $bucket.Module
        BucketLabel = ('{0} | {1}' -f $bucket.FrequencyLabel, $bucket.Module)
        ObservationCount = $bucket.ObservationCount
        UnitCount = $bucket.VisualIds.Count
        CoreCoverage = (@($bucket.CoreLabels | Sort-Object) -join '; ')
        CoreCount = $bucket.CoreLabels.Count
        MinDtsC = [math]::Round($values[0], 4)
        P25DtsC = [math]::Round($q1, 4)
        MedianDtsC = [math]::Round($median, 4)
        MeanDtsC = [math]::Round($mean, 4)
        P75DtsC = [math]::Round($q3, 4)
        MaxDtsC = [math]::Round($values[$values.Count - 1], 4)
        DeltaFrom100C = $deltaFromTarget
        Direction = $direction
        SetterSummary = (@($bucket.Setters | Sort-Object) -join '; ')
        FullProgramNames = (@($bucket.FullProgramNames | Sort-Object) -join '; ')
        RawValues = $values
    }
    $bucketRenderRows.Add($renderRow) | Out-Null

    if ($direction -ne 'OnTarget') {
        $violationRows.Add([pscustomobject]@{
            ClassTestProgram = $bucket.ClassTestProgram
            Domain = $bucket.Domain
            FrequencyGHz = $bucket.FrequencyGHz
            FrequencyLabel = $bucket.FrequencyLabel
            Module = $bucket.Module
            BucketLabel = ('{0} | {1}' -f $bucket.FrequencyLabel, $bucket.Module)
            MedianDtsC = [math]::Round($median, 4)
            MeanDtsC = [math]::Round($mean, 4)
            DeltaFrom100C = $deltaFromTarget
            AbsoluteDeltaFrom100C = [math]::Round([math]::Abs($deltaFromTarget), 4)
            Direction = $direction
            ObservationCount = $bucket.ObservationCount
            UnitCount = $bucket.VisualIds.Count
            CoreCoverage = (@($bucket.CoreLabels | Sort-Object) -join '; ')
            SeverityGroup = if ($direction -eq 'Above') { 0 } else { 1 }
            SetterSummary = (@($bucket.Setters | Sort-Object) -join '; ')
        }) | Out-Null
    }
}

$bucketSummaryRows = @($bucketRenderRows | Sort-Object ClassTestProgram, Domain, FrequencyGHz, @{ Expression = { Get-ModuleSortOrder -ModuleName $_.Module } }, Module | ForEach-Object {
    [pscustomobject]@{
        ClassTestProgram = $_.ClassTestProgram
        Domain = $_.Domain
        DomainToken = $_.DomainToken
        FrequencyGHz = $_.FrequencyGHz
        FrequencyLabel = $_.FrequencyLabel
        Module = $_.Module
        BucketLabel = $_.BucketLabel
        ObservationCount = $_.ObservationCount
        UnitCount = $_.UnitCount
        CoreCoverage = $_.CoreCoverage
        CoreCount = $_.CoreCount
        MinDtsC = $_.MinDtsC
        P25DtsC = $_.P25DtsC
        MedianDtsC = $_.MedianDtsC
        MeanDtsC = $_.MeanDtsC
        P75DtsC = $_.P75DtsC
        MaxDtsC = $_.MaxDtsC
        DeltaFrom100C = $_.DeltaFrom100C
        Direction = $_.Direction
        SetterSummary = $_.SetterSummary
        FullProgramNames = $_.FullProgramNames
    }
})

$violationRowsSorted = @($violationRows | Sort-Object SeverityGroup, @{ Expression = { -1 * $_.AbsoluteDeltaFrom100C } }, ClassTestProgram, Domain, FrequencyGHz, @{ Expression = { Get-ModuleSortOrder -ModuleName $_.Module } }, Module)
for ($violationIndex = 0; $violationIndex -lt $violationRowsSorted.Count; $violationIndex++) {
    $violationRowsSorted[$violationIndex] | Add-Member -NotePropertyName SeverityRank -NotePropertyValue ($violationIndex + 1) -Force
}

if ($bucketSummaryRows.Count -gt 0) {
    $bucketSummaryRows | Export-Csv -LiteralPath $bucketCsvPath -NoTypeInformation -Encoding UTF8
}
else {
    @([pscustomobject]@{
        ClassTestProgram = ''
        Domain = ''
        DomainToken = ''
        FrequencyGHz = ''
        FrequencyLabel = ''
        Module = ''
        BucketLabel = ''
        ObservationCount = 0
        UnitCount = 0
        CoreCoverage = ''
        CoreCount = 0
        MinDtsC = ''
        P25DtsC = ''
        MedianDtsC = ''
        MeanDtsC = ''
        P75DtsC = ''
        MaxDtsC = ''
        DeltaFrom100C = ''
        Direction = ''
        SetterSummary = ''
        FullProgramNames = ''
    }) | Export-Csv -LiteralPath $bucketCsvPath -NoTypeInformation -Encoding UTF8
}

if ($violationRowsSorted.Count -gt 0) {
    $violationRowsSorted | Export-Csv -LiteralPath $violationsCsvPath -NoTypeInformation -Encoding UTF8
}
else {
    @([pscustomobject]@{
        ClassTestProgram = ''
        Domain = ''
        FrequencyGHz = ''
        FrequencyLabel = ''
        Module = ''
        BucketLabel = ''
        MedianDtsC = ''
        MeanDtsC = ''
        DeltaFrom100C = ''
        AbsoluteDeltaFrom100C = ''
        Direction = 'OnTarget'
        ObservationCount = 0
        UnitCount = 0
        CoreCoverage = ''
        SeverityGroup = ''
        SeverityRank = ''
        SetterSummary = ''
    }) | Export-Csv -LiteralPath $violationsCsvPath -NoTypeInformation -Encoding UTF8
}

$programCards = New-Object System.Text.StringBuilder
$programOptions = New-Object System.Text.StringBuilder
$programRenderRows = @($bucketRenderRows | Group-Object -Property ClassTestProgram | Sort-Object Name)

if ($programRenderRows.Count -eq 0) {
    [void]$programCards.AppendLine("<section class='program-card active'><div class='placeholder'>No DTS observations matched an officially released Class TP in the input CSV.</div></section>")
}
else {
    for ($programIndex = 0; $programIndex -lt $programRenderRows.Count; $programIndex++) {
        $programGroup = $programRenderRows[$programIndex]
        $programId = Get-SafeId -Value $programGroup.Name
        $programInfo = $programInfoMap[$programGroup.Name]
        [void]$programOptions.AppendLine(("<option value='{0}'>{1}</option>" -f $programId, (ConvertTo-HtmlEscaped -Text $programGroup.Name)))

        $programDomainGroups = @($programGroup.Group | Group-Object -Property Domain | Sort-Object Name)
        $programViolationRows = @($violationRowsSorted | Where-Object { $_.ClassTestProgram -eq $programGroup.Name })
        $programFullNames = @($programInfo.FullProgramNames | Sort-Object)
        $programUnitCount = $programInfo.VisualIds.Count
        $programBucketCount = $programGroup.Group.Count

        [void]$programCards.AppendLine(("<section class='program-card{0}' data-program='{1}'>" -f $(if ($programIndex -eq 0) { ' active' } else { '' }), $programId))
        [void]$programCards.AppendLine(("<div class='program-meta'><h2>Class TP {0}</h2><p>Full program names: {1}</p><p>Units: {2} | DTS observations: {3} | Buckets: {4}</p></div>" -f (ConvertTo-HtmlEscaped -Text $programGroup.Name), (ConvertTo-HtmlEscaped -Text ($programFullNames -join '; ')), $programUnitCount, $programInfo.ObservationCount, $programBucketCount))

        [void]$programCards.AppendLine("<div class='panel'><h3>Violation Summary</h3>")
        $preferredViolationRows = @($programViolationRows | Where-Object { Test-IsPreferredFrequencyLabel -FrequencyLabel $_.FrequencyLabel })
        $programViolationRowsDisplay = if ($preferredViolationRows.Count -gt 0) { $preferredViolationRows } else { $programViolationRows }
        if ($programViolationRowsDisplay.Count -eq 0) {
            [void]$programCards.AppendLine("<div class='placeholder'>No median DTS violations detected for this Class TP.</div>")
        }
        else {
            if ($preferredViolationRows.Count -gt 0) {
                [void]$programCards.AppendLine("<div class='meta' style='margin:6px 0 10px 0;'>Showing preferred frequencies only: 1.2, 2.8, 3.8, 4.3, 4.6 GHz.</div>")
            }
            [void]$programCards.AppendLine("<table><thead><tr><th>Severity</th><th>Domain</th><th>freq</th><th>Module</th><th>Median MaxDTS</th><th>Delta from 100</th><th>Direction</th><th>Units</th><th>Cores</th></tr></thead><tbody>")
            foreach ($violation in $programViolationRowsDisplay) {
                [void]$programCards.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4:N2}</td><td>{5:N2}</td><td>{6}</td><td>{7}</td><td>{8}</td></tr>" -f $violation.SeverityRank, (ConvertTo-HtmlEscaped -Text $violation.Domain), (ConvertTo-HtmlEscaped -Text $violation.FrequencyLabel), (ConvertTo-HtmlEscaped -Text $violation.Module), $violation.MedianDtsC, $violation.DeltaFrom100C, (ConvertTo-HtmlEscaped -Text $violation.Direction), $violation.UnitCount, (ConvertTo-HtmlEscaped -Text $violation.CoreCoverage)))
            }
            [void]$programCards.AppendLine("</tbody></table>")
        }
        [void]$programCards.AppendLine("</div>")

        foreach ($domainGroup in $programDomainGroups) {
            $chartRows = Get-ChartGroupSummaries -DomainRows @($domainGroup.Group)
            $chartMarkup = Get-ScientificGroupedBoxplotSvg -ChartRows $chartRows -ChartTitle ("{0} MaxDTS vs freq" -f $domainGroup.Name)

            [void]$programCards.AppendLine(("<div class='domain-card'><div class='domain-header'><h3>{0}</h3><span class='render-mode'>Grouped Boxplot + Mean Trend</span></div>" -f (ConvertTo-HtmlEscaped -Text $domainGroup.Name)))
            [void]$programCards.AppendLine($chartMarkup)
            [void]$programCards.AppendLine("<div class='domain-table-wrap'><table><thead><tr><th>freq</th><th>Module</th><th>Cores</th><th>Units</th><th>Mean</th><th>Median</th><th>P25</th><th>P75</th><th>Min</th><th>Max</th></tr></thead><tbody>")
            foreach ($summary in $chartRows) {
                [void]$programCards.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4:N2}</td><td>{5:N2}</td><td>{6:N2}</td><td>{7:N2}</td><td>{8:N2}</td><td>{9:N2}</td></tr>" -f (ConvertTo-HtmlEscaped -Text $summary.FrequencyLabel), (ConvertTo-HtmlEscaped -Text $summary.Module), (ConvertTo-HtmlEscaped -Text $summary.CoreCoverage), $summary.UnitCount, $summary.MeanDtsC, $summary.MedianDtsC, $summary.P25DtsC, $summary.P75DtsC, $summary.MinDtsC, $summary.MaxDtsC))
            }
            [void]$programCards.AppendLine("</tbody></table></div></div>")
        }

        [void]$programCards.AppendLine("</section>")
    }
}

$html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>NVLAX DTS Analysis</title>
<style>
:root {
  --bg: #f7f7f7;
  --paper: #ffffff;
  --ink: #1b2733;
  --muted: #566675;
  --line: #d1d6db;
  --major-grid: #d5d5d5;
  --minor-grid: #ececec;
  --accent: #245ea9;
  --red: #c52121;
}
body {
  margin: 0;
  font-family: Segoe UI, Arial, sans-serif;
  color: var(--ink);
  background: var(--bg);
}
header {
  padding: 18px 24px;
  color: #ffffff;
  background: #263645;
  position: sticky;
  top: 0;
  z-index: 10;
}
header h1 {
  margin: 0 0 6px 0;
  font-size: 24px;
}
header p {
  margin: 0;
  font-size: 13px;
  opacity: 0.94;
}
.wrap {
  padding: 20px;
}
.toolbar,
.program-card,
.panel,
.domain-card {
  background: var(--paper);
  border: 1px solid var(--line);
  border-radius: 8px;
}
.toolbar {
  margin-bottom: 16px;
  padding: 14px 16px;
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  align-items: center;
}
.toolbar label {
  font-weight: 600;
}
.toolbar select {
  min-width: 220px;
  padding: 8px 10px;
  border: 1px solid #aab5bf;
  border-radius: 4px;
  font-size: 14px;
  color: var(--ink);
  background: #ffffff;
}
.toolbar .meta {
  color: var(--muted);
  font-size: 12px;
}
.program-card {
  display: none;
  padding: 16px;
  margin-bottom: 20px;
}
.program-card.active {
  display: block;
}
.program-meta h2 {
  margin: 0 0 6px 0;
}
.program-meta p {
  margin: 4px 0;
  color: var(--muted);
  font-size: 13px;
}
.panel {
  padding: 12px;
  margin: 14px 0 18px 0;
}
.panel h3,
.domain-header h3 {
  margin: 0;
}
.domain-card {
  padding: 14px;
  margin-top: 14px;
}
.domain-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 10px;
}
.render-mode {
  font-size: 12px;
  color: var(--muted);
  font-weight: 600;
}
.placeholder {
  border: 1px dashed #aab5bf;
  background: #fafafa;
  color: #43556a;
  border-radius: 6px;
  padding: 20px 14px;
  text-align: center;
  font-weight: 600;
}
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
th, td {
  border: 1px solid var(--line);
  padding: 6px 8px;
  text-align: left;
}
th {
  background: #f0f2f4;
}
.domain-table-wrap {
  margin-top: 10px;
  overflow-x: auto;
}
.chart-svg {
  width: 100%;
  height: auto;
}
.axis-label {
  font-size: 11px;
  fill: #4f5f6f;
  text-anchor: end;
}
.axis-title {
  font-size: 12px;
  fill: #22313f;
  font-weight: 600;
}
.module-label {
  font-size: 10px;
  fill: #3d4b59;
}
.freq-label {
    font-size: 13px;
  fill: #22313f;
  text-anchor: middle;
  font-weight: 600;
}
.major-grid {
  stroke: var(--major-grid);
}
.minor-grid {
  stroke: var(--minor-grid);
}
.axis-line {
  stroke: #555555;
  stroke-width: 1.2;
}
.group-separator {
  stroke: #c2c2c2;
  stroke-width: 0.8;
}
.box-red {
  stroke: var(--red);
  stroke-width: 1.4;
}
.box-median {
  stroke: var(--red);
  stroke-width: 1.8;
}
.outlier-red {
  stroke: var(--red);
  fill: none;
  stroke-width: 1;
}
.mean-line {
  fill: none;
  stroke: var(--accent);
  stroke-width: 1.2;
}
.mean-marker {
  fill: var(--accent);
  stroke: var(--accent);
}
@media (max-width: 900px) {
  .toolbar {
    flex-direction: column;
    align-items: flex-start;
  }
}
</style>
</head>
<body>
<header>
  <h1>NVLAX DTS Analysis</h1>
  <p>Input: $(ConvertTo-HtmlEscaped -Text $InputCsvPath) | Only officially released Class TPs are included.</p>
</header>
<div class='wrap'>
  <div class='toolbar'>
    <label for='programSelect'>Class TP</label>
    <select id='programSelect'>$($programOptions.ToString())</select>
    <div class='meta'>Filtered non-released rows: $(if ($filteredProgramSummaryRows.Count -gt 0) { ($filteredProgramSummaryRows | Measure-Object -Property RowCount -Sum).Sum } else { 0 }) | Unknown-module observations: $unknownModuleCount</div>
  </div>
  $($programCards.ToString())
</div>
<script>
(function() {
  const select = document.getElementById('programSelect');
  const cards = Array.from(document.querySelectorAll('.program-card[data-program]'));
  function showProgram(programId) {
    cards.forEach(card => {
      if (card.getAttribute('data-program') === programId) {
        card.classList.add('active');
      } else {
        card.classList.remove('active');
      }
    });
  }
  if (select && cards.length > 0) {
    if (!select.value) {
      select.value = cards[0].getAttribute('data-program');
    }
    showProgram(select.value);
    select.addEventListener('change', function() {
      showProgram(select.value);
    });
  }
})();
</script>
</body>
</html>
"@

$html | Set-Content -LiteralPath $OutputHtmlPath -Encoding UTF8

$filteredRowCount = if ($filteredProgramSummaryRows.Count -gt 0) { ($filteredProgramSummaryRows | Measure-Object -Property RowCount -Sum).Sum } else { 0 }
$manifest = [ordered]@{
    generatedOn = (Get-Date).ToString('o')
    inputCsvPath = $InputCsvPath
    outputHtmlPath = $OutputHtmlPath
    outputDirectory = $OutputDirectory
    pointsCsvPath = $pointsCsvPath
    bucketSummaryCsvPath = $bucketCsvPath
    violationsCsvPath = $violationsCsvPath
    filteredProgramsCsvPath = $filteredProgramsCsvPath
    releasedProgramMatcher = '(?<tp>\d{2}[A-Z]\d0)S\d+$'
    releasedProgramAllowlists = $script:ReleasedClassProgramAllowlists
    visualIdColumn = $visualIdColumn
    lotColumn = $lotColumn
    programColumn = $programColumn
    releasedClassPrograms = @($programRenderRows | Select-Object -ExpandProperty Name)
    filteredProgramCount = $filteredRowCount
    observationCount = $observationCount
    bucketCount = $bucketSummaryRows.Count
    violationCount = $violationRowsSorted.Count
    unknownModuleObservationCount = $unknownModuleCount
    preferredPlotFrequencies = $script:PreferredPlotFrequencies
    renderThresholds = [ordered]@{
        maxScatterPointsPerDomain = $MaxScatterPointsPerDomain
        maxBucketsPerDomain = $MaxBucketsPerDomain
    }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "HTML report        : $OutputHtmlPath"
Write-Host "Points CSV         : $pointsCsvPath"
Write-Host "Bucket summary CSV : $bucketCsvPath"
Write-Host "Violations CSV     : $violationsCsvPath"
Write-Host "Filtered programs  : $filteredProgramsCsvPath"
Write-Host "Run manifest       : $manifestPath"
