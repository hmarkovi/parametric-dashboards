<#
.SYNOPSIS
Step-1 Sort parametric analysis for Vmin raw extraction.

.DESCRIPTION
Reads Sort CSV data, keeps only _VMIN_ instance columns, pairs Vmin and LP prints,
parses relevant metadata from test instance names, and exports a normalized raw CSV.

Input default:
R:\Products\NVL\NVL-AX\Analysis\2026_31_NVLAX_first hub sort data.csv

Output default folder:
R:\Products\NVL\NVL-AX\Analysis\Sort data analysis

Output file naming:
yyyyMMdd_<most-abundant-program>_SORT_vmin_raw.csv
#>

param(
    [string]$InputCsvPath = "R:\Products\NVL\NVL-AX\Analysis\2026_31_NVLAX_first hub sort data.csv",
    [string]$OutputDirectory = "R:\Products\NVL\NVL-AX\Analysis\Sort data analysis",
    [string]$DomainMappingCsvPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Convert-ToSafeFilePart {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "UNKNOWN_PROGRAM"
    }

    $safe = $Value.Trim()
    $safe = $safe -replace '[\\/:*?"<>|]', "_"
    $safe = $safe -replace '\s+', "_"
    $safe = $safe -replace '_{2,}', "_"
    $safe = $safe.Trim('_')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "UNKNOWN_PROGRAM"
    }

    return $safe
}

function Get-MostAbundantValue {
    param(
        [object[]]$Rows,
        [string]$ColumnName
    )

    if (-not $Rows -or $Rows.Count -eq 0 -or [string]::IsNullOrWhiteSpace($ColumnName)) {
        return ""
    }

    $counts = @{}
    foreach ($row in $Rows) {
        $v = [string]$row.$ColumnName
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        $k = $v.Trim()
        if (-not $counts.ContainsKey($k)) {
            $counts[$k] = 0
        }
        $counts[$k]++
    }

    if ($counts.Count -eq 0) {
        return ""
    }

    return ($counts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key
}

function Get-DomainFinalMapping {
    param([string]$MappingCsvPath)

    if ([string]::IsNullOrWhiteSpace($MappingCsvPath)) {
        throw "Domain mapping CSV path is empty."
    }
    if (-not (Test-Path -LiteralPath $MappingCsvPath)) {
        throw "Domain mapping CSV does not exist: $MappingCsvPath"
    }

    $mapRows = @(Import-Csv -LiteralPath $MappingCsvPath)
    if ($mapRows.Count -eq 0) {
        throw "Domain mapping CSV is empty: $MappingCsvPath"
    }

    $map = @{}
    foreach ($r in $mapRows) {
        $domain = [string]$r.Domain
        $finalDomain = [string]$r.FinalDomain
        if ([string]::IsNullOrWhiteSpace($domain)) { continue }

        $domainKey = $domain.Trim().ToUpperInvariant()
        $map[$domainKey] = if (-not [string]::IsNullOrWhiteSpace($finalDomain)) { $finalDomain.Trim() } else { "TBD" }
    }

    return $map
}

function Parse-VminPrintValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]@{
            Raw = ""
            VminResult = ""
            StartVoltage = ""
            EndVoltage = ""
            NumberOfTries = ""
        }
    }

    $parts = @($Value -split "\|")

    return [pscustomobject]@{
        Raw = $Value
        VminResult = if ($parts.Count -ge 1) { $parts[0].Trim() } else { "" }
        StartVoltage = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "" }
        EndVoltage = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }
        NumberOfTries = if ($parts.Count -ge 4) { $parts[3].Trim() } else { "" }
    }
}

function Parse-SortTestColumnName {
    param([string]$TestName)

    if ([string]::IsNullOrWhiteSpace($TestName)) {
        return $null
    }

    if ($TestName -notlike "*_VMIN_*") {
        return $null
    }

    $doubleColonParts = $TestName -split "::", 2
    if ($doubleColonParts.Count -lt 2) {
        return $null
    }

    $testModule = $doubleColonParts[0].Trim()
    $rhs = $doubleColonParts[1].Trim()
    if ([string]::IsNullOrWhiteSpace($rhs)) {
        return $null
    }

    $tokens = @($rhs -split "_")
    if ($tokens.Count -lt 6) {
        return $null
    }

    $socket = $tokens[$tokens.Count - 1]
    $beforeSocket = @($tokens[0..($tokens.Count - 2)])

    $markerToken = ""
    if ($beforeSocket.Count -gt 0) {
        $possibleMarker = $beforeSocket[$beforeSocket.Count - 1].ToUpperInvariant()
        if ($possibleMarker -in @("LP", "EC", "IT", "SCRB")) {
            $markerToken = $possibleMarker
            $beforeSocket = @($beforeSocket[0..($beforeSocket.Count - 2)])
        }
    }

    $baseRhs = (($beforeSocket + @($socket)) -join "_")
    $baseName = "{0}::{1}" -f $testModule, $baseRhs

    $printType = "VMIN"
    if ($markerToken -eq "LP") {
        $printType = "LP"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($markerToken)) {
        $printType = "OTHER"
    }

    $contentType = if ($beforeSocket.Count -ge 1) { $beforeSocket[0] } else { "" }
    $domain = if ($beforeSocket.Count -ge 2) { $beforeSocket[1] } else { "" }
    $vminTest = if ($beforeSocket.Count -ge 3) { $beforeSocket[2] } else { "" }
    $killToken = if ($beforeSocket.Count -ge 4) { $beforeSocket[3] } else { "" }
    $prePostStress = if ($beforeSocket.Count -ge 5) { $beforeSocket[4] } else { "" }
    $corner = if ($beforeSocket.Count -ge 2) { $beforeSocket[$beforeSocket.Count - 2] } else { "" }
    $algo = if ($beforeSocket.Count -ge 1) { $beforeSocket[$beforeSocket.Count - 1] } else { "" }

    return [pscustomobject]@{
        OriginalTestName = $TestName
        BaseTestName = $baseName
        PrintType = $printType
        MarkerToken = $markerToken
        TestModule = $testModule
        ContentType = $contentType
        Domain = $domain
        VminTest = $vminTest
        KillToken = $killToken
        PrePostStress = $prePostStress
        Corner = $corner
        Algo = $algo
        Socket = $socket
    }
}

if (-not (Test-Path -LiteralPath $InputCsvPath)) {
    throw "Input CSV does not exist: $InputCsvPath"
}

if ([string]::IsNullOrWhiteSpace($DomainMappingCsvPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $DomainMappingCsvPath = Join-Path $scriptDir "sort_domain_mapping.csv"
}

$domainMap = Get-DomainFinalMapping -MappingCsvPath $DomainMappingCsvPath

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

Write-Host "Loading input CSV..."
$rows = @(Import-Csv -LiteralPath $InputCsvPath)
if ($rows.Count -eq 0) {
    throw "Input CSV is empty: $InputCsvPath"
}

$allColumns = $rows[0].PSObject.Properties.Name

$visualIdColumn = Get-FirstExistingColumnName -CandidateNames @("VISUAL_ID", "Visual ID", "VisualId", "VISUALID", "VID") -AvailableNames $allColumns
if (-not $visualIdColumn) {
    throw "Could not find a Visual ID column in input CSV."
}

$programColumn = Get-FirstExistingColumnName -CandidateNames @("Program Name_SORT", "Program Name", "PROGRAM", "PROGRAM_NAME", "Program") -AvailableNames $allColumns

$trackedContextColumns = @("LOTFROMFS", "LOTFROMFS_SORT", "LOT", "Lot", "Program Name_SORT", "Program Name", "PROGRAM") |
    Where-Object { $allColumns -contains $_ } |
    Select-Object -Unique

# Keep only test-instance columns with _VMIN_ token.
$vminInstanceColumns = @($allColumns | Where-Object { $_ -like "*_VMIN_*" })
if ($vminInstanceColumns.Count -eq 0) {
    throw "No test-instance columns containing _VMIN_ were found."
}

Write-Host ("Detected {0} _VMIN_ columns for parsing." -f $vminInstanceColumns.Count)

$parsedColumns = @{}
foreach ($col in $vminInstanceColumns) {
    $parsed = Parse-SortTestColumnName -TestName $col
    if ($null -eq $parsed) { continue }
    $parsedColumns[$col] = $parsed
}

if ($parsedColumns.Count -eq 0) {
    throw "No parsable _VMIN_ test-instance columns were found."
}

$records = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $visualId = [string]$row.$visualIdColumn
    if ([string]::IsNullOrWhiteSpace($visualId)) {
        continue
    }
    $visualId = $visualId.Trim()

    # Build per-unit lookup by base test name to pair VMIN and LP values.
    $baseLookup = @{}

    foreach ($columnName in $parsedColumns.Keys) {
        $meta = $parsedColumns[$columnName]
        if ($meta.PrintType -eq "OTHER") {
            continue
        }

        $cellValue = [string]$row.$columnName
        if ([string]::IsNullOrWhiteSpace($cellValue)) {
            continue
        }

        if (-not $baseLookup.ContainsKey($meta.BaseTestName)) {
            $baseLookup[$meta.BaseTestName] = [ordered]@{
                Meta = $meta
                VminValue = ""
                LpValue = ""
            }
        }

        if ($meta.PrintType -eq "VMIN") {
            $baseLookup[$meta.BaseTestName].VminValue = $cellValue.Trim()
        }
        elseif ($meta.PrintType -eq "LP") {
            $baseLookup[$meta.BaseTestName].LpValue = $cellValue.Trim()
        }
    }

    foreach ($entry in $baseLookup.GetEnumerator()) {
        $item = $entry.Value
        if ([string]::IsNullOrWhiteSpace($item.VminValue)) {
            continue
        }

        $parsedVmin = Parse-VminPrintValue -Value $item.VminValue
        $domainSource = [string]$item.Meta.Domain
        $domainKey = if (-not [string]::IsNullOrWhiteSpace($domainSource)) { $domainSource.Trim().ToUpperInvariant() } else { "" }
        $finalDomain = "TBD"
        if (-not [string]::IsNullOrWhiteSpace($domainKey) -and $domainMap.ContainsKey($domainKey)) {
            $finalDomain = [string]$domainMap[$domainKey]
        }

        $record = [ordered]@{
            VISUAL_ID = $visualId
            BaseTestName = $item.Meta.BaseTestName
            TestModule = $item.Meta.TestModule
            ContentType = $item.Meta.ContentType
            Domain = $item.Meta.Domain
            FinalDomain = $finalDomain
            VminTest = $item.Meta.VminTest
            KillToken = $item.Meta.KillToken
            PrePostStress = $item.Meta.PrePostStress
            Corner = $item.Meta.Corner
            Algo = $item.Meta.Algo
            Socket = $item.Meta.Socket
            VminPrintRaw = $parsedVmin.Raw
            VminResult = $parsedVmin.VminResult
            StartVoltage = $parsedVmin.StartVoltage
            EndVoltage = $parsedVmin.EndVoltage
            NumberOfTries = $parsedVmin.NumberOfTries
            LimiterPattern = $item.LpValue
        }

        foreach ($ctxCol in $trackedContextColumns) {
            $record[$ctxCol] = [string]$row.$ctxCol
        }

        $records.Add([pscustomobject]$record)
    }
}

if ($records.Count -eq 0) {
    throw "No Vmin raw records were produced. Check that input has VMIN and LP values per VISUAL_ID."
}

$mostAbundantProgram = ""
if ($programColumn) {
    $mostAbundantProgram = Get-MostAbundantValue -Rows $rows -ColumnName $programColumn
}
$safeProgram = Convert-ToSafeFilePart -Value $mostAbundantProgram
$dateTag = Get-Date -Format "yyyyMMdd"

$outputFileName = "{0}_{1}_SORT_vmin_raw.csv" -f $dateTag, $safeProgram
$outputPath = Join-Path $OutputDirectory $outputFileName

$records |
    Sort-Object -Property VISUAL_ID, Domain, Corner, BaseTestName |
    Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "Sort Vmin raw extraction completed."
Write-Host ("Input rows: {0}" -f $rows.Count)
Write-Host ("Output records: {0}" -f $records.Count)
Write-Host ("Output file: {0}" -f $outputPath)
