<#
.SYNOPSIS
Build a Classhot parametric bridge table from TRACE get_test_results CSV output.

.DESCRIPTION
Consumes stacked TRACE rows (for example: JobName, TestName, VisualId, Value),
parses VMIN/DTS/SICC payloads, applies latest-row dedupe, and exports:
1) normalized VMIN staging rows
2) normalized SICC staging rows
3) final wide table (one row per VisualID + Classhot lot)

Optional geometry columns are included when present in TRACE rows:
- SortLot, SortWafer, DieX, DieY
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsvPath,
    [string]$OutputDirectory = "",
    [string]$OutputPrefix = "trace_classhot_bridge",
    [string]$LotFilter = "",
    [double]$MinValidVmin = 0.2,
    [double]$MaxValidVmin = 2.0,
    [bool]$RequireCcfData = $false,
    [string[]]$RequiredCcfLots = @(),
    [string[]]$RequiredCcfCorners = @('F1', 'F2', 'F3', 'F4', 'F7')
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

function Convert-ToDoubleOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $out = 0.0
    if ([double]::TryParse(
            $Value.Trim(),
            [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$out)) {
        return $out
    }

    return $null
}

function Has-NonMissingLp {
    param([string]$LpValue)

    if ([string]::IsNullOrWhiteSpace($LpValue)) { return $false }

    $u = $LpValue.Trim().ToUpperInvariant()
    if ($u -eq "NA" -or $u -eq "N/A" -or $u -eq "NULL") { return $false }
    if ($u -match "MISSING") { return $false }

    return $true
}

function Get-VminDisplayDomainToken {
    param(
        [string]$Domain,
        [int]$CoreIndex,
        [string]$CfgDomain
    )

    $cfgToken = if ([string]::IsNullOrWhiteSpace($CfgDomain)) { "" } else { $CfgDomain.Trim().ToUpperInvariant() }
    if ($cfgToken -match '^CCF\d*$') {
        return "CCF"
    }
    if (-not [string]::IsNullOrWhiteSpace($cfgToken)) {
        return $cfgToken
    }

    $domainToken = if ([string]::IsNullOrWhiteSpace($Domain)) { "" } else { $Domain.Trim().ToUpperInvariant() }
    if ($CoreIndex -ge 0) {
        return ("{0}{1}" -f $domainToken, $CoreIndex)
    }

    return $domainToken
}

function Get-SiccDisplayDomainToken {
    param(
        [string]$Domain,
        [int]$CoreIndex
    )

    $domainToken = if ([string]::IsNullOrWhiteSpace($Domain)) { "" } else { $Domain.Trim().ToUpperInvariant() }
    switch ($domainToken) {
        "AT" { return ("AT{0:D2}" -f $CoreIndex) }
        "IA" { return ("IA{0:D2}" -f $CoreIndex) }
        default { return $domainToken }
    }
}

function Get-SiccDieToken {
    param(
        [string]$Domain,
        [string]$SourceTestName = ""
    )

    $sourceToken = if ([string]::IsNullOrWhiteSpace($SourceTestName)) { "" } else { $SourceTestName.Trim().ToUpperInvariant() }
    if ($sourceToken -match 'PP_SICC_(U1PU[245])') {
        return $Matches[1]
    }
    if ($sourceToken -match 'GTSICC') {
        return 'U1PU4'
    }
    if ($sourceToken -match 'SASICC') {
        if ($sourceToken -match '(_AT|_IA|_CCF)') {
            return 'U1PU5'
        }
        return 'U1PU2'
    }

    $domainToken = if ([string]::IsNullOrWhiteSpace($Domain)) { "" } else { $Domain.Trim().ToUpperInvariant() }
    switch ($domainToken) {
        "GT" { return "U1PU4" }
        "AT" { return "U1PU5" }
        "IA" { return "U1PU5" }
        "CCF" { return "U1PU5" }
        default { return "U1PU2" }
    }
}

function Get-SiccColumnPrefix {
    param(
        [string]$Domain,
        [int]$CoreIndex,
        [string]$VoltagePoint,
        [string]$SourceTestName = ""
    )

    $dieToken = Get-SiccDieToken -Domain $Domain -SourceTestName $SourceTestName
    $displayDomain = Get-SiccDisplayDomainToken -Domain $Domain -CoreIndex $CoreIndex
    return ("VA-IN-NA-GSDS_D_S::PP_SICC_{0}_CLASSHOT_{1}-{2}" -f $dieToken, $displayDomain, $VoltagePoint)
}

function Get-ClasshotLot {
    param(
        [object]$Row,
        [string]$LotColumn,
        [string]$JobColumn
    )

    if (-not [string]::IsNullOrWhiteSpace($LotColumn)) {
        $lot = [string]$Row.$LotColumn
        if (-not [string]::IsNullOrWhiteSpace($lot)) {
            return $lot.Trim().ToUpperInvariant()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($JobColumn)) {
        $jobName = [string]$Row.$JobColumn
        if (-not [string]::IsNullOrWhiteSpace($jobName)) {
            $m = [regex]::Match($jobName.Trim(), '^(?<Lot>[^_]+)_')
            if ($m.Success) {
                return $m.Groups['Lot'].Value.Trim().ToUpperInvariant()
            }
        }
    }

    return ""
}

function Get-RecencyKey {
    param(
        [object]$Row,
        [int]$RowIndex,
        [string]$TimestampColumn,
        [string]$SessionEndColumn,
        [string]$JobEndColumn,
        [string]$SequenceColumn
    )

    $ticks = [int64]::MinValue
    foreach ($col in @($TimestampColumn, $SessionEndColumn, $JobEndColumn)) {
        if ([string]::IsNullOrWhiteSpace($col)) { continue }
        $raw = [string]$Row.$col
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $dt = [datetime]::MinValue
        if ([datetime]::TryParse($raw.Trim(), [ref]$dt)) {
            $ticks = $dt.ToUniversalTime().Ticks
            break
        }
    }

    $seq = [double]::NegativeInfinity
    if (-not [string]::IsNullOrWhiteSpace($SequenceColumn)) {
        $s = Convert-ToDoubleOrNull -Value ([string]$Row.$SequenceColumn)
        if ($null -ne $s) {
            $seq = $s
        }
    }

    return [pscustomobject]@{
        Ticks = $ticks
        Seq = $seq
        RowIndex = $RowIndex
    }
}

function Is-NewerRecency {
    param(
        [object]$Candidate,
        [object]$Current
    )

    if ($null -eq $Current) { return $true }
    if ($Candidate.Ticks -gt $Current.Ticks) { return $true }
    if ($Candidate.Ticks -lt $Current.Ticks) { return $false }

    if ($Candidate.Seq -gt $Current.Seq) { return $true }
    if ($Candidate.Seq -lt $Current.Seq) { return $false }

    return ($Candidate.RowIndex -gt $Current.RowIndex)
}

function Parse-VminFwCfg {
    param([string]$CfgValue)

    $result = @()
    if ([string]::IsNullOrWhiteSpace($CfgValue)) { return $result }

    foreach ($entry in ($CfgValue -split "_")) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        $atParts = $entry -split "@", 2
        $domain = $atParts[0].Trim().ToUpperInvariant()

        $corner = ""
        $flow = ""
        $freqGHz = ""

        if ($atParts.Count -gt 1) {
            $colonParts = $atParts[1] -split ":", 3
            if ($colonParts.Count -ge 1) { $corner = $colonParts[0].Trim().ToUpperInvariant() }
            if ($colonParts.Count -ge 2) { $flow = $colonParts[1].Trim() }
            if ($colonParts.Count -ge 3) { $freqGHz = $colonParts[2].Trim() }
        }

        $result += [pscustomobject]@{
            Domain = $domain
            FreqCorner = $corner
            Flow = $flow
            FreqGHz = $freqGHz
        }
    }

    return $result
}

function Split-DomainAndCoreIndex {
    param(
        [string]$DomainRaw,
        [int]$DefaultCoreIndex = -1
    )

    $normalized = if ([string]::IsNullOrWhiteSpace($DomainRaw)) { "" } else { $DomainRaw.Trim().ToUpperInvariant() }
    $coreIndex = $DefaultCoreIndex

    if ($normalized -match '^(?<Base>[A-Z]+?)(?<Core>\d+)$') {
        $normalized = $Matches['Base']
        $coreIndex = [int]$Matches['Core']
    }

    return [pscustomobject]@{
        Domain = $normalized
        CoreIndex = $coreIndex
    }
}

function Parse-VminRaw {
    param(
        [string]$VminRaw,
        [double]$MinValue,
        [double]$MaxValue
    )

    if ([string]::IsNullOrWhiteSpace($VminRaw)) {
        return [pscustomobject]@{
            Vmin = ""
            VminLow = ""
            VminHigh = ""
            SearchPoints = ""
            Vector = @()
        }
    }

    $parts = @($VminRaw -split "\|")
    $vmin = if ($parts.Count -ge 1) { $parts[0].Trim() } else { "" }
    $low = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "" }
    $high = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }
    $searchPoints = if ($parts.Count -ge 4) { $parts[3].Trim() } else { "" }

    $vectorRaw = if ($parts.Count -ge 1) { $parts[0].Trim() } else { "" }
    $vector = @()

    if (-not [string]::IsNullOrWhiteSpace($vectorRaw)) {
        if ($vectorRaw -notmatch "_") {
            $single = Convert-ToDoubleOrNull -Value $vectorRaw
            if ($null -ne $single -and $single -ge $MinValue -and $single -le $MaxValue) {
                $vector += $single
            }
            else {
                $vector += $null
            }
        }
        else {
            foreach ($token in ($vectorRaw -split "_")) {
                $d = Convert-ToDoubleOrNull -Value $token
                if ($null -ne $d -and $d -ge $MinValue -and $d -le $MaxValue) {
                    $vector += $d
                }
                else {
                    $vector += $null
                }
            }
        }
    }

    return [pscustomobject]@{
        Vmin = $vmin
        VminLow = $low
        VminHigh = $high
        SearchPoints = $searchPoints
        Vector = $vector
    }
}

function Infer-DomainHintFromTestName {
    param([string]$TestName)

    if ([string]::IsNullOrWhiteSpace($TestName)) { return "" }
    $u = $TestName.ToUpperInvariant()

    if ($u -match "_CR(?:_|$)") { return "CR" }
    if ($u -match "_AT(?:_|$)|_ATOM(?:_|$)") { return "AT" }
    if ($u -match "_GT(?:_|$)|VCCGT|GTSICC") { return "GT" }
    if ($u -match "CCF|VCCF") { return "CCF" }
    if ($u -match "VCCSA|_SA(?:_|$)|SAQ|SAC|SAN|SAPS|SAME|SAIOC|SADPU") { return "SA" }

    return ""
}

function Is-CcfDomain {
    param([string]$Domain)

    if ([string]::IsNullOrWhiteSpace($Domain)) { return $false }
    return $Domain.Trim().ToUpperInvariant() -match '^CCF\d*$'
}

function Get-MaxDtsForRecord {
    param(
        [string]$DtsRaw,
        [string[]]$CfgDomains,
        [string]$DomainHint
    )

    if ([string]::IsNullOrWhiteSpace($DtsRaw)) { return "" }

    $pairs = @()
    foreach ($sensor in ($DtsRaw -split "\|")) {
        if ([string]::IsNullOrWhiteSpace($sensor)) { continue }
        $parts = $sensor.Trim() -split ":", 2
        if ($parts.Count -lt 2) { continue }

        $name = $parts[0].Trim().ToUpperInvariant()
        $temp = Convert-ToDoubleOrNull -Value $parts[1]
        if ($null -eq $temp) { continue }

        $pairs += [pscustomobject]@{ Name = $name; Temp = $temp }
    }

    if ($pairs.Count -eq 0) { return "" }

    $domainSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in $CfgDomains) {
        if (-not [string]::IsNullOrWhiteSpace($d)) {
            [void]$domainSet.Add($d)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($DomainHint)) {
        [void]$domainSet.Add($DomainHint)
    }

    $hasHub = $false
    $hasGt = $false
    $hasCore = $false
    $hasAtom = $false

    foreach ($d in $domainSet) {
        $u = $d.ToUpperInvariant()
        if ($u.StartsWith("SA") -or $u.StartsWith("HUB")) { $hasHub = $true }
        if ($u.StartsWith("GT")) { $hasGt = $true }
        if ($u.StartsWith("CR") -or $u -eq "CORE") { $hasCore = $true }
        if ($u.StartsWith("CCF")) { $hasCore = $true }
        if ($u.StartsWith("AT") -or $u -eq "ATOM") { $hasAtom = $true }
    }

    # Plan rule: HUB and GT currently use global max over all sensors.
    if ($hasHub -or $hasGt) {
        $global = ($pairs | Sort-Object Temp -Descending | Select-Object -First 1).Temp
        return $global.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    # Core and Atom domain-aware filtering.
    $filtered = @()
    if ($hasCore) {
        $filtered += @($pairs | Where-Object { $_.Name -match '^C\d+S\d+' -or $_.Name -match '^CCF\d+S\d+' })
    }
    if ($hasAtom) {
        $filtered += @($pairs | Where-Object { $_.Name -match '^A\d+S\d+' })
    }

    if ($filtered.Count -gt 0) {
        $maxFiltered = ($filtered | Sort-Object Temp -Descending | Select-Object -First 1).Temp
        return $maxFiltered.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    # Fallback when no known domain mapping matched.
    $fallback = ($pairs | Sort-Object Temp -Descending | Select-Object -First 1).Temp
    return $fallback.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Parse-SiccEntriesFromRaw {
    param([string]$RawValue)

    $entries = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($RawValue)) { return $entries }

    $tokens = @($RawValue -split '\^') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($token in $tokens) {
        $t = $token.Trim()
        if ($t -match '^(?<Domain>[A-Za-z0-9]+)-(?<Vp>V\d+):(?<Value>[+-]?\d*\.?\d+)(?:%(?<Volt>[+-]?\d*\.?\d+))?(?:%(?<Temp>[+-]?\d*\.?\d+))?$') {
            $domainParts = Split-DomainAndCoreIndex -DomainRaw $Matches['Domain'] -DefaultCoreIndex 0
            $entries.Add([pscustomobject]@{
                CoreIndex = $domainParts.CoreIndex
                Domain = $domainParts.Domain
                VoltagePoint = $Matches['Vp'].ToUpperInvariant()
                SiccValue = $Matches['Value']
                VoltageValue = if ($Matches['Volt']) { $Matches['Volt'] } else { "" }
                TemperatureValue = if ($Matches['Temp']) { $Matches['Temp'] } else { "" }
            })
        }
    }

    return $entries
}

function Parse-SiccEntryFromTestName {
    param(
        [string]$TestName,
        [string]$RawValue
    )

    if ([string]::IsNullOrWhiteSpace($TestName) -or [string]::IsNullOrWhiteSpace($RawValue)) {
        return $null
    }

    $val = Convert-ToDoubleOrNull -Value $RawValue
    if ($null -eq $val) { return $null }

    $segments = @($TestName -split '\|')
    foreach ($seg in $segments) {
        $u = $seg.Trim().ToUpperInvariant()
        if ($u -match 'PP_SICC_(?<Domain>[A-Z0-9]+)_(?<Vp>V\d+)') {
            $domainParts = Split-DomainAndCoreIndex -DomainRaw $Matches['Domain'] -DefaultCoreIndex 0
            return [pscustomobject]@{
                CoreIndex = $domainParts.CoreIndex
                Domain = $domainParts.Domain
                VoltagePoint = $Matches['Vp'].ToUpperInvariant()
                SiccValue = $val.ToString([System.Globalization.CultureInfo]::InvariantCulture)
                VoltageValue = ""
                TemperatureValue = ""
            }
        }
    }

    return $null
}

function Parse-SortGeometryFromValue {
    param([string]$RawValue)

    if ([string]::IsNullOrWhiteSpace($RawValue)) { return $null }

    $parts = @($RawValue.Trim() -split '_')
    if ($parts.Count -lt 4) { return $null }

    $offset = $parts.Count - 4
    $lotToken = $parts[$offset]
    $waferToken = $parts[$offset + 1]
    $xToken = $parts[$offset + 2]
    $yToken = $parts[$offset + 3]

    if ($lotToken -match '^[A-Za-z0-9]+[A-Za-z]$') {
        $lotToken = $lotToken.Substring(0, $lotToken.Length - 1)
    }

    $waferOut = $waferToken
    $xOut = $xToken
    $yOut = $yToken

    $num = 0
    if ([int]::TryParse($waferToken, [ref]$num)) { $waferOut = $num.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    if ([int]::TryParse($xToken, [ref]$num)) { $xOut = $num.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    if ([int]::TryParse($yToken, [ref]$num)) { $yOut = $num.ToString([System.Globalization.CultureInfo]::InvariantCulture) }

    return [pscustomobject]@{
        SortLot = $lotToken.ToUpperInvariant()
        SortWafer = $waferOut
        SortX = $xOut
        SortY = $yOut
    }
}

function Get-GeometrySuffixFromTestName {
    param([string]$TestName)

    if ([string]::IsNullOrWhiteSpace($TestName)) { return "" }
    $u = $TestName.Trim().ToUpperInvariant()
    if ($u.StartsWith('TESTTIME_')) { return "" }

    if ($u -like '*FUS_UNITINFO_HXX*MAIN_FUSE_READ*') { return 'U1.U2' }
    if ($u -like '*FUS_UNITINFO_GXX*MAIN_FUSE_READ*') { return 'U1.U4' }
    if ($u -like '*FUS_UNITINFO_CXX*MAIN_FUSE_READ*') { return 'U1.U5' }

    return ""
}

function Get-UniqueUpper {
    param([string[]]$Values)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$set.Add($value.Trim().ToUpperInvariant())
        }
    }
    return @($set | Sort-Object)
}

if (-not (Test-Path -LiteralPath $InputCsvPath)) {
    throw "Input CSV does not exist: $InputCsvPath"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Split-Path -Parent $InputCsvPath
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$firstRow = Import-Csv -LiteralPath $InputCsvPath | Select-Object -First 1
if ($null -eq $firstRow) {
    throw "Input CSV is empty: $InputCsvPath"
}

$cols = $firstRow.PSObject.Properties.Name

$visualCol = Get-FirstExistingColumnName -CandidateNames @("VisualId", "VISUAL_ID", "Visual ID", "VisualID", "VID") -AvailableNames $cols
$testNameCol = Get-FirstExistingColumnName -CandidateNames @("TestName", "TEST_NAME", "Test Name") -AvailableNames $cols
$valueCol = Get-FirstExistingColumnName -CandidateNames @("Value", "TEST_RESULT", "Test Result", "RESULT") -AvailableNames $cols
$jobCol = Get-FirstExistingColumnName -CandidateNames @("JobName", "JOB_NAME", "Job") -AvailableNames $cols
$lotCol = Get-FirstExistingColumnName -CandidateNames @("ClasshotLot", "LOTFROMFS", "LotFromFs", "LOT", "Lot") -AvailableNames $cols

if (-not $visualCol) { throw "Could not locate VisualId column." }
if (-not $testNameCol) { throw "Could not locate TestName column." }
if (-not $valueCol) { throw "Could not locate Value column." }

$tsCol = Get-FirstExistingColumnName -CandidateNames @("TEST_END", "TestEnd", "EndDate", "END_DATE") -AvailableNames $cols
$sessionEndCol = Get-FirstExistingColumnName -CandidateNames @("SESSION_END", "SessionEnd") -AvailableNames $cols
$jobEndCol = Get-FirstExistingColumnName -CandidateNames @("JOB_END", "JobEnd") -AvailableNames $cols
$seqCol = Get-FirstExistingColumnName -CandidateNames @("TEST_RESULT_ORDER_NUM", "ResultOrder", "RowOrder") -AvailableNames $cols

$sortLotCol = Get-FirstExistingColumnName -CandidateNames @("SORT_LOT", "SortLot", "LOTFROMFS_SORT") -AvailableNames $cols
$sortWaferCol = Get-FirstExistingColumnName -CandidateNames @("SORT_WAFER", "SortWafer", "WAFER") -AvailableNames $cols
$dieXCol = Get-FirstExistingColumnName -CandidateNames @("DIE_X", "DieX", "X", "X_COORD") -AvailableNames $cols
$dieYCol = Get-FirstExistingColumnName -CandidateNames @("DIE_Y", "DieY", "Y", "Y_COORD") -AvailableNames $cols
$functionalBinCol = Get-FirstExistingColumnName -CandidateNames @("FUNCTIONAL_BIN", "FunctionalBin", "Functional Bin", "HBIN", "SOFT_BIN", "SoftBin") -AvailableNames $cols

$vminLookup = @{}
$siccLookup = @{}
$geometryLookup = @{}
$violations = @{}

$inputRowsUsed = 0
$rowIndex = 0

function Add-Violation {
    param(
        [string]$VisualID,
        [string]$ClasshotLot,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    $k = "{0}||{1}" -f $VisualID, $ClasshotLot
    if (-not $violations.ContainsKey($k)) {
        $violations[$k] = New-Object System.Collections.Generic.List[string]
    }
    $violations[$k].Add($Message)
}

Import-Csv -LiteralPath $InputCsvPath | ForEach-Object {
    $row = $_
    $currentRowIndex = $rowIndex
    $rowIndex++

    $vid = [string]$row.$visualCol
    if (-not [string]::IsNullOrWhiteSpace($vid)) {
        $vid = $vid.Trim().ToUpperInvariant()

        $lot = Get-ClasshotLot -Row $row -LotColumn $lotCol -JobColumn $jobCol
        if (-not [string]::IsNullOrWhiteSpace($lot)) {
            if ([string]::IsNullOrWhiteSpace($LotFilter) -or $lot -eq $LotFilter.Trim().ToUpperInvariant()) {
                $inputRowsUsed++
                $testName = [string]$row.$testNameCol
                $rawValue = [string]$row.$valueCol
                $recency = Get-RecencyKey -Row $row -RowIndex $currentRowIndex -TimestampColumn $tsCol -SessionEndColumn $sessionEndCol -JobEndColumn $jobEndCol -SequenceColumn $seqCol

                $geoKey = "{0}||{1}" -f $vid, $lot
                if (-not $geometryLookup.ContainsKey($geoKey)) {
                    $geometryLookup[$geoKey] = [pscustomobject]@{
                        FunctionalBin = if ($functionalBinCol) { [string]$row.$functionalBinCol } else { "" }
                        SortLot = if ($sortLotCol) { [string]$row.$sortLotCol } else { "" }
                        SortWafer = if ($sortWaferCol) { [string]$row.$sortWaferCol } else { "" }
                        DieX = if ($dieXCol) { [string]$row.$dieXCol } else { "" }
                        DieY = if ($dieYCol) { [string]$row.$dieYCol } else { "" }
                        SortLot_U1U2 = ""
                        SortWafer_U1U2 = ""
                        SortX_U1U2 = ""
                        SortY_U1U2 = ""
                        SortLot_U1U4 = ""
                        SortWafer_U1U4 = ""
                        SortX_U1U4 = ""
                        SortY_U1U4 = ""
                        SortLot_U1U5 = ""
                        SortWafer_U1U5 = ""
                        SortX_U1U5 = ""
                        SortY_U1U5 = ""
                        U1U2Recency = $null
                        U1U4Recency = $null
                        U1U5Recency = $null
                        Recency = $recency
                    }
                }
                elseif (Is-NewerRecency -Candidate $recency -Current $geometryLookup[$geoKey].Recency) {
                    $newFunctionalBin = if ($functionalBinCol) { [string]$row.$functionalBinCol } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($newFunctionalBin)) {
                        $geometryLookup[$geoKey].FunctionalBin = $newFunctionalBin
                    }
                    $geometryLookup[$geoKey].SortLot = if ($sortLotCol) { [string]$row.$sortLotCol } else { "" }
                    $geometryLookup[$geoKey].SortWafer = if ($sortWaferCol) { [string]$row.$sortWaferCol } else { "" }
                    $geometryLookup[$geoKey].DieX = if ($dieXCol) { [string]$row.$dieXCol } else { "" }
                    $geometryLookup[$geoKey].DieY = if ($dieYCol) { [string]$row.$dieYCol } else { "" }
                    $geometryLookup[$geoKey].Recency = $recency
                }

                $suffix = Get-GeometrySuffixFromTestName -TestName $testName
                if (-not [string]::IsNullOrWhiteSpace($suffix)) {
                    $parsedGeo = Parse-SortGeometryFromValue -RawValue $rawValue
                    if ($null -ne $parsedGeo) {
                        switch ($suffix) {
                            'U1.U2' {
                                if (Is-NewerRecency -Candidate $recency -Current $geometryLookup[$geoKey].U1U2Recency) {
                                    $geometryLookup[$geoKey].SortLot_U1U2 = $parsedGeo.SortLot
                                    $geometryLookup[$geoKey].SortWafer_U1U2 = $parsedGeo.SortWafer
                                    $geometryLookup[$geoKey].SortX_U1U2 = $parsedGeo.SortX
                                    $geometryLookup[$geoKey].SortY_U1U2 = $parsedGeo.SortY
                                    $geometryLookup[$geoKey].U1U2Recency = $recency
                                }
                            }
                            'U1.U4' {
                                if (Is-NewerRecency -Candidate $recency -Current $geometryLookup[$geoKey].U1U4Recency) {
                                    $geometryLookup[$geoKey].SortLot_U1U4 = $parsedGeo.SortLot
                                    $geometryLookup[$geoKey].SortWafer_U1U4 = $parsedGeo.SortWafer
                                    $geometryLookup[$geoKey].SortX_U1U4 = $parsedGeo.SortX
                                    $geometryLookup[$geoKey].SortY_U1U4 = $parsedGeo.SortY
                                    $geometryLookup[$geoKey].U1U4Recency = $recency
                                }
                            }
                            'U1.U5' {
                                if (Is-NewerRecency -Candidate $recency -Current $geometryLookup[$geoKey].U1U5Recency) {
                                    $geometryLookup[$geoKey].SortLot_U1U5 = $parsedGeo.SortLot
                                    $geometryLookup[$geoKey].SortWafer_U1U5 = $parsedGeo.SortWafer
                                    $geometryLookup[$geoKey].SortX_U1U5 = $parsedGeo.SortX
                                    $geometryLookup[$geoKey].SortY_U1U5 = $parsedGeo.SortY
                                    $geometryLookup[$geoKey].U1U5Recency = $recency
                                }
                            }
                        }
                    }
                }

                $uName = if ($null -ne $testName) { $testName.ToUpperInvariant() } else { "" }

                if ($uName -like "*_VMIN_*") {
        $kind = "Base"
        $base = $testName

        if ($uName.EndsWith("_DTS")) {
            $kind = "DTS"
            $base = $testName.Substring(0, $testName.Length - 4)
        }
        elseif ($uName.EndsWith("_VMINFWCFG")) {
            $kind = "CFG"
            $base = $testName.Substring(0, $testName.Length - 10)
        }
        elseif ($uName.EndsWith("_LP")) {
            $kind = "LP"
            $base = $testName.Substring(0, $testName.Length - 3)
        }
        elseif ($uName.EndsWith("_IT") -or $uName.EndsWith("_SCRB")) {
            $kind = "Ignore"
        }

        if ($kind -ne "Ignore") {
            $k = "{0}||{1}||{2}" -f $vid, $lot, $base
            if (-not $vminLookup.ContainsKey($k)) {
                $vminLookup[$k] = [ordered]@{
                    VisualID = $vid
                    ClasshotLot = $lot
                    BaseTest = $base
                    VminRaw = ""
                    CfgRaw = ""
                    DtsRaw = ""
                    LpRaw = ""
                    BaseRecency = $null
                    CfgRecency = $null
                    DtsRecency = $null
                    LpRecency = $null
                }
            }

            switch ($kind) {
                "Base" {
                    if (Is-NewerRecency -Candidate $recency -Current $vminLookup[$k].BaseRecency) {
                        $vminLookup[$k].VminRaw = $rawValue
                        $vminLookup[$k].BaseRecency = $recency
                    }
                }
                "CFG" {
                    if (Is-NewerRecency -Candidate $recency -Current $vminLookup[$k].CfgRecency) {
                        $vminLookup[$k].CfgRaw = $rawValue
                        $vminLookup[$k].CfgRecency = $recency
                    }
                }
                "DTS" {
                    if (Is-NewerRecency -Candidate $recency -Current $vminLookup[$k].DtsRecency) {
                        $vminLookup[$k].DtsRaw = $rawValue
                        $vminLookup[$k].DtsRecency = $recency
                    }
                }
                "LP" {
                    if (Is-NewerRecency -Candidate $recency -Current $vminLookup[$k].LpRecency) {
                        $vminLookup[$k].LpRaw = $rawValue
                        $vminLookup[$k].LpRecency = $recency
                    }
                }
            }
        }
                }

                if ($uName -match "SICC") {
        $parsed = @(Parse-SiccEntriesFromRaw -RawValue $rawValue)
        if ($parsed.Count -eq 0) {
            $single = Parse-SiccEntryFromTestName -TestName $testName -RawValue $rawValue
            if ($null -ne $single) {
                $parsed = ,$single
            }
        }

        foreach ($s in $parsed) {
            $siccCoreKey = if ($s.CoreIndex -ge 0) { $s.CoreIndex.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "NA" }
            $sk = "{0}||{1}||{2}||{3}||{4}" -f $vid, $lot, $siccCoreKey, $s.Domain, $s.VoltagePoint
            if (-not $siccLookup.ContainsKey($sk) -or (Is-NewerRecency -Candidate $recency -Current $siccLookup[$sk].Recency)) {
                $siccLookup[$sk] = [pscustomobject]@{
                    VisualID = $vid
                    ClasshotLot = $lot
                    SourceTestName = $testName
                    CoreIndex = $s.CoreIndex
                    Domain = $s.Domain
                    VoltagePoint = $s.VoltagePoint
                    SiccValue = $s.SiccValue
                    TemperatureValue = $s.TemperatureValue
                    Recency = $recency
                }
            }
        }

        if ($parsed.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($rawValue)) {
            Add-Violation -VisualID $vid -ClasshotLot $lot -Message "SICC_PARSE_FAILED:$testName"
        }
                }
            }
        }
    }
}

if ($inputRowsUsed -eq 0) {
    throw "No rows remained after VisualID/Classhot lot filtering."
}

$vminStage = New-Object System.Collections.Generic.List[object]

foreach ($item in $vminLookup.Values) {
    if ([string]::IsNullOrWhiteSpace($item.VminRaw)) { continue }

    if ([string]::IsNullOrWhiteSpace($item.CfgRaw)) {
        Add-Violation -VisualID $item.VisualID -ClasshotLot $item.ClasshotLot -Message "MISSING_VMINFWCFG:$($item.BaseTest)"
        continue
    }

    $cfg = @(Parse-VminFwCfg -CfgValue $item.CfgRaw)
    if ($cfg.Count -eq 0) {
        Add-Violation -VisualID $item.VisualID -ClasshotLot $item.ClasshotLot -Message "EMPTY_VMINFWCFG:$($item.BaseTest)"
        continue
    }

    $parsedVmin = Parse-VminRaw -VminRaw $item.VminRaw -MinValue $MinValidVmin -MaxValue $MaxValidVmin
    $vector = @($parsedVmin.Vector)

    if ($vector.Count -ne $cfg.Count) {
        Add-Violation -VisualID $item.VisualID -ClasshotLot $item.ClasshotLot -Message ("CFG_VMIN_VECTOR_MISMATCH:{0}:cfg={1}:vmin={2}" -f $item.BaseTest, $cfg.Count, $vector.Count)
    }

    $domainHint = Infer-DomainHintFromTestName -TestName $item.BaseTest
    if (-not [string]::IsNullOrWhiteSpace($domainHint)) {
        $matchesHint = $false
        foreach ($c in $cfg) {
            if ($c.Domain.StartsWith($domainHint)) {
                $matchesHint = $true
                break
            }
        }
        if (-not $matchesHint) {
            Add-Violation -VisualID $item.VisualID -ClasshotLot $item.ClasshotLot -Message ("TEST_CFG_DOMAIN_MISMATCH:{0}:hint={1}:cfg={2}" -f $item.BaseTest, $domainHint, (($cfg | ForEach-Object { $_.Domain }) -join ','))
        }
    }

    $maxDts = Get-MaxDtsForRecord -DtsRaw $item.DtsRaw -CfgDomains @($cfg | ForEach-Object { $_.Domain }) -DomainHint $domainHint

    $pairCount = [Math]::Min($cfg.Count, $vector.Count)
    for ($idx = 0; $idx -lt $pairCount; $idx++) {
        $v = $vector[$idx]
        if ($null -eq $v) { continue }

        $domainParts = Split-DomainAndCoreIndex -DomainRaw $cfg[$idx].Domain -DefaultCoreIndex $idx
        $domain = $domainParts.Domain
        $corner = $cfg[$idx].FreqCorner
        $flow = $cfg[$idx].Flow
        $freq = $cfg[$idx].FreqGHz
        $coreIndex = $domainParts.CoreIndex

        $vminStage.Add([pscustomobject]@{
            VisualID = $item.VisualID
            ClasshotLot = $item.ClasshotLot
            BaseTest = $item.BaseTest
            CfgDomain = $cfg[$idx].Domain
            Domain = $domain
            FreqCorner = $corner
            Flow = $flow
            FreqGHz = $freq
            CoreIndex = $coreIndex
            Vmin = $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            VminLow = $parsedVmin.VminLow
            VminHigh = $parsedVmin.VminHigh
            SearchPoints = $parsedVmin.SearchPoints
            Setter = $item.BaseTest
            MaxDTS_C = $maxDts
            LP = $item.LpRaw
        })
    }
}

$bestVminByCombo = @{}
foreach ($rec in $vminStage) {
    $k = "{0}||{1}||{2}||{3}||{4}||{5}||{6}" -f $rec.VisualID, $rec.ClasshotLot, $rec.Domain, $rec.FreqCorner, $rec.Flow, $rec.FreqGHz, $rec.CoreIndex

    if (-not $bestVminByCombo.ContainsKey($k)) {
        $bestVminByCombo[$k] = $rec
        continue
    }

    $cur = $bestVminByCombo[$k]
    $vCur = Convert-ToDoubleOrNull -Value ([string]$cur.Vmin)
    $vNew = Convert-ToDoubleOrNull -Value ([string]$rec.Vmin)

    if ($null -eq $vCur -or ($null -ne $vNew -and $vNew -gt $vCur)) {
        $bestVminByCombo[$k] = $rec
        continue
    }

    if ($null -ne $vNew -and $null -ne $vCur -and $vNew -eq $vCur) {
        # For equal Vmin values, prefer the first record that has a non-missing LP companion.
        $newHasLp = Has-NonMissingLp -LpValue ([string]$rec.LP)
        $curHasLp = Has-NonMissingLp -LpValue ([string]$cur.LP)
        if ($newHasLp -and -not $curHasLp) {
            $bestVminByCombo[$k] = $rec
            continue
        }

        if ($curHasLp -and -not $newHasLp) {
            continue
        }

        # Keep the first encountered record when both equal-Vmin candidates have the same LP presence.
        if ($newHasLp -eq $curHasLp) {
            continue
        }

        $newHasDts = -not [string]::IsNullOrWhiteSpace([string]$rec.MaxDTS_C)
        $curHasDts = -not [string]::IsNullOrWhiteSpace([string]$cur.MaxDTS_C)
        if ($newHasDts -and -not $curHasDts) {
            $bestVminByCombo[$k] = $rec
        }
    }
}

$vminComboSet = New-Object 'System.Collections.Generic.SortedSet[string]'
$visualLotSet = New-Object 'System.Collections.Generic.SortedSet[string]'

foreach ($rec in $bestVminByCombo.Values) {
    [void]$visualLotSet.Add(("{0}||{1}" -f $rec.VisualID, $rec.ClasshotLot))
    [void]$vminComboSet.Add(("{0}||{1}||{2}||{3}||{4}" -f $rec.Domain, $rec.FreqCorner, $rec.Flow, $rec.FreqGHz, $rec.CoreIndex))
}

foreach ($s in $siccLookup.Values) {
    [void]$visualLotSet.Add(("{0}||{1}" -f $s.VisualID, $s.ClasshotLot))
}

foreach ($gk in $geometryLookup.Keys) {
    [void]$visualLotSet.Add($gk)
}

$siccColumns = New-Object 'System.Collections.Generic.SortedSet[string]'
foreach ($s in $siccLookup.Values) {
    $siccPrefix = Get-SiccColumnPrefix -Domain $s.Domain -CoreIndex $s.CoreIndex -VoltagePoint $s.VoltagePoint -SourceTestName $s.SourceTestName
    [void]$siccColumns.Add(("{0}_Value" -f $siccPrefix))
    [void]$siccColumns.Add(("{0}_Temperature" -f $siccPrefix))
}

$siccByVisualLot = @{}
foreach ($s in $siccLookup.Values) {
    $k = "{0}||{1}" -f $s.VisualID, $s.ClasshotLot
    if (-not $siccByVisualLot.ContainsKey($k)) {
        $siccByVisualLot[$k] = New-Object System.Collections.Generic.List[object]
    }
    $siccByVisualLot[$k].Add($s)
}

$requiredCcfLotsNormalized = Get-UniqueUpper -Values $RequiredCcfLots
$requiredCcfCornersNormalized = Get-UniqueUpper -Values $RequiredCcfCorners

$finalRows = New-Object System.Collections.Generic.List[object]

foreach ($vk in $visualLotSet) {
    $parts = $vk -split '\|\|', 2
    $vid = $parts[0]
    $lot = $parts[1]

    $rowMap = [ordered]@{
        VisualID = $vid
        ClasshotLot = $lot
    }

    $geoKey = "{0}||{1}" -f $vid, $lot
    if ($geometryLookup.ContainsKey($geoKey)) {
        $geo = $geometryLookup[$geoKey]
        $rowMap["FunctionalBin"] = [string]$geo.FunctionalBin
        $rowMap["SortLot"] = [string]$geo.SortLot
        $rowMap["SortWafer"] = [string]$geo.SortWafer
        $rowMap["DieX"] = [string]$geo.DieX
        $rowMap["DieY"] = [string]$geo.DieY
        $rowMap["SORT_LOT_U1.U2"] = [string]$geo.SortLot_U1U2
        $rowMap["SORT_WAFER_U1.U2"] = [string]$geo.SortWafer_U1U2
        $rowMap["SORT_X_U1.U2"] = [string]$geo.SortX_U1U2
        $rowMap["SORT_Y_U1.U2"] = [string]$geo.SortY_U1U2
        $rowMap["SORT_LOT_U1.U4"] = [string]$geo.SortLot_U1U4
        $rowMap["SORT_WAFER_U1.U4"] = [string]$geo.SortWafer_U1U4
        $rowMap["SORT_X_U1.U4"] = [string]$geo.SortX_U1U4
        $rowMap["SORT_Y_U1.U4"] = [string]$geo.SortY_U1U4
        $rowMap["SORT_LOT_U1.U5"] = [string]$geo.SortLot_U1U5
        $rowMap["SORT_WAFER_U1.U5"] = [string]$geo.SortWafer_U1U5
        $rowMap["SORT_X_U1.U5"] = [string]$geo.SortX_U1U5
        $rowMap["SORT_Y_U1.U5"] = [string]$geo.SortY_U1U5
    }
    else {
        $rowMap["FunctionalBin"] = ""
        $rowMap["SortLot"] = ""
        $rowMap["SortWafer"] = ""
        $rowMap["DieX"] = ""
        $rowMap["DieY"] = ""
        $rowMap["SORT_LOT_U1.U2"] = ""
        $rowMap["SORT_WAFER_U1.U2"] = ""
        $rowMap["SORT_X_U1.U2"] = ""
        $rowMap["SORT_Y_U1.U2"] = ""
        $rowMap["SORT_LOT_U1.U4"] = ""
        $rowMap["SORT_WAFER_U1.U4"] = ""
        $rowMap["SORT_X_U1.U4"] = ""
        $rowMap["SORT_Y_U1.U4"] = ""
        $rowMap["SORT_LOT_U1.U5"] = ""
        $rowMap["SORT_WAFER_U1.U5"] = ""
        $rowMap["SORT_X_U1.U5"] = ""
        $rowMap["SORT_Y_U1.U5"] = ""
    }

    foreach ($combo in $vminComboSet) {
        $cp = $combo -split '\|\|', 5
        $domain = $cp[0]
        $corner = $cp[1]
        $flow = $cp[2]
        $freq = $cp[3]
        $core = $cp[4]

        $cornerToken = if ([string]::IsNullOrWhiteSpace($corner)) { "NA" } else { ($corner -replace '[^A-Za-z0-9]', '_') }
        $flowToken = if ([string]::IsNullOrWhiteSpace($flow)) { "NA" } else { ($flow -replace '[^A-Za-z0-9]', '_') }
        $freqToken = if ([string]::IsNullOrWhiteSpace($freq)) { "NA" } else { ($freq -replace '[^A-Za-z0-9\.]', '_') }

        $lookup = "{0}||{1}||{2}||{3}||{4}||{5}||{6}" -f $vid, $lot, $domain, $corner, $flow, $freq, $core

        if ($bestVminByCombo.ContainsKey($lookup)) {
            $rec = $bestVminByCombo[$lookup]
            $displayDomain = Get-VminDisplayDomainToken -Domain $rec.Domain -CoreIndex ([int]$rec.CoreIndex) -CfgDomain ([string]$rec.CfgDomain)
            $prefix = "ILAS_{0}_{1}_Flow{2}_Freq{3}_C{4}" -f $displayDomain, $cornerToken, $flowToken, $freqToken, $core
            $rowMap["${prefix}_Vmin"] = $rec.Vmin
            $rowMap["${prefix}_VminLow"] = $rec.VminLow
            $rowMap["${prefix}_VminHigh"] = $rec.VminHigh
            $rowMap["${prefix}_SearchPoints"] = $rec.SearchPoints
            $rowMap["${prefix}_Setter"] = $rec.Setter
            $rowMap["${prefix}_MaxDTS_C"] = $rec.MaxDTS_C
            $rowMap["${prefix}_LP"] = $rec.LP
        }
        else {
            $displayDomain = Get-VminDisplayDomainToken -Domain $domain -CoreIndex ([int]$core) -CfgDomain ""
            $prefix = "ILAS_{0}_{1}_Flow{2}_Freq{3}_C{4}" -f $displayDomain, $cornerToken, $flowToken, $freqToken, $core
            $rowMap["${prefix}_Vmin"] = ""
            $rowMap["${prefix}_VminLow"] = ""
            $rowMap["${prefix}_VminHigh"] = ""
            $rowMap["${prefix}_SearchPoints"] = ""
            $rowMap["${prefix}_Setter"] = ""
            $rowMap["${prefix}_MaxDTS_C"] = ""
            $rowMap["${prefix}_LP"] = ""
        }
    }

    foreach ($sCol in $siccColumns) {
        $rowMap[$sCol] = ""
    }

    if ($siccByVisualLot.ContainsKey($geoKey)) {
        foreach ($s in $siccByVisualLot[$geoKey]) {
            $siccPrefix = Get-SiccColumnPrefix -Domain $s.Domain -CoreIndex $s.CoreIndex -VoltagePoint $s.VoltagePoint -SourceTestName $s.SourceTestName
            $vCol = "{0}_Value" -f $siccPrefix
            $tCol = "{0}_Temperature" -f $siccPrefix
            $rowMap[$vCol] = $s.SiccValue
            $rowMap[$tCol] = $s.TemperatureValue
        }
    }

    $finalRows.Add([pscustomobject]$rowMap)
}

$ccfDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($lot in $requiredCcfLotsNormalized) {
    $lotRecords = @($bestVminByCombo.Values | Where-Object { $_.ClasshotLot -eq $lot -and (Is-CcfDomain -Domain ([string]$_.CfgDomain)) })
    if ($lotRecords.Count -eq 0) {
        $ccfDiagnostics.Add([pscustomobject]@{
            ClasshotLot = $lot
            Corner = ''
            Status = 'missing-ccf-records'
            Message = 'No CCF VMIN records found for required lot.'
        })
        Add-Violation -VisualID '' -ClasshotLot $lot -Message 'REQUIRED_CCF_MISSING:No CCF VMIN records found.'
        continue
    }

    foreach ($corner in $requiredCcfCornersNormalized) {
        $cornerRecords = @($lotRecords | Where-Object { ([string]$_.FreqCorner).Trim().ToUpperInvariant() -eq $corner })
        if ($cornerRecords.Count -eq 0) {
            $ccfDiagnostics.Add([pscustomobject]@{
                ClasshotLot = $lot
                Corner = $corner
                Status = 'missing-corner'
                Message = 'Required CCF corner is missing.'
            })
            Add-Violation -VisualID '' -ClasshotLot $lot -Message ("REQUIRED_CCF_CORNER_MISSING:{0}" -f $corner)
            continue
        }

        $fieldComplete = $false
        foreach ($rec in $cornerRecords) {
            if (-not [string]::IsNullOrWhiteSpace([string]$rec.Vmin) -and
                -not [string]::IsNullOrWhiteSpace([string]$rec.Setter) -and
                -not [string]::IsNullOrWhiteSpace([string]$rec.MaxDTS_C) -and
                -not [string]::IsNullOrWhiteSpace([string]$rec.LP)) {
                $fieldComplete = $true
                break
            }
        }

        if ($fieldComplete) {
            $ccfDiagnostics.Add([pscustomobject]@{
                ClasshotLot = $lot
                Corner = $corner
                Status = 'ok'
                Message = 'CCF corner has Vmin/Setter/MaxDTS_C/LP.'
            })
        }
        else {
            $ccfDiagnostics.Add([pscustomobject]@{
                ClasshotLot = $lot
                Corner = $corner
                Status = 'missing-fields'
                Message = 'CCF corner exists but one or more fields are empty: Vmin/Setter/MaxDTS_C/LP.'
            })
            Add-Violation -VisualID '' -ClasshotLot $lot -Message ("REQUIRED_CCF_FIELDS_MISSING:{0}" -f $corner)
        }
    }
}

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$vminStagePath = Join-Path $OutputDirectory ("{0}_vmin_stage_{1}.csv" -f $OutputPrefix, $runStamp)
$siccStagePath = Join-Path $OutputDirectory ("{0}_sicc_stage_{1}.csv" -f $OutputPrefix, $runStamp)
$finalPath = Join-Path $OutputDirectory ("{0}_final_{1}.csv" -f $OutputPrefix, $runStamp)
$violationsPath = Join-Path $OutputDirectory ("{0}_violations_{1}.csv" -f $OutputPrefix, $runStamp)
$ccfDiagnosticsPath = Join-Path $OutputDirectory ("{0}_ccf_diagnostics_{1}.csv" -f $OutputPrefix, $runStamp)

$bestVminRows = foreach ($row in $bestVminByCombo.Values) { $row }
$bestVminRows |
    Sort-Object VisualID, ClasshotLot, Domain, CoreIndex, FreqCorner, Flow, FreqGHz |
    Select-Object VisualID, ClasshotLot, Domain, FreqCorner, Flow, FreqGHz, CoreIndex, Vmin, VminLow, VminHigh, SearchPoints, Setter, MaxDTS_C, LP |
    Export-Csv -LiteralPath $vminStagePath -NoTypeInformation -Encoding UTF8
$siccStageRows = foreach ($row in $siccLookup.Values) { $row }
$siccStageRows |
    Sort-Object VisualID, ClasshotLot, Domain, CoreIndex, VoltagePoint |
    Select-Object VisualID, ClasshotLot, SourceTestName, Domain, CoreIndex, VoltagePoint, SiccValue, TemperatureValue |
    Export-Csv -LiteralPath $siccStagePath -NoTypeInformation -Encoding UTF8
$finalRows | Export-Csv -LiteralPath $finalPath -NoTypeInformation -Encoding UTF8

$violationRows = New-Object System.Collections.Generic.List[object]
foreach ($violationKey in $violations.Keys) {
    $vp = $violationKey -split '\|\|', 2
    $vVisual = if ($vp.Count -ge 1) { $vp[0] } else { '' }
    $vLot = if ($vp.Count -ge 2) { $vp[1] } else { '' }
    foreach ($msg in $violations[$violationKey]) {
        $violationRows.Add([pscustomobject]@{
            VisualID = $vVisual
            ClasshotLot = $vLot
            Message = [string]$msg
        })
    }
}

$violationRows |
    Sort-Object ClasshotLot, VisualID, Message |
    Export-Csv -LiteralPath $violationsPath -NoTypeInformation -Encoding UTF8

$ccfDiagnostics |
    Sort-Object ClasshotLot, Corner, Status |
    Export-Csv -LiteralPath $ccfDiagnosticsPath -NoTypeInformation -Encoding UTF8

if ($RequireCcfData -and $requiredCcfLotsNormalized.Count -gt 0) {
    $blocking = @($ccfDiagnostics | Where-Object { $_.Status -ne 'ok' })
    if ($blocking.Count -gt 0) {
        throw ("CCF required-data gate failed. See diagnostics CSV: {0}" -f $ccfDiagnosticsPath)
    }
}

Write-Host "Trace Classhot bridge completed."
Write-Host ("Input rows used : {0}" -f $inputRowsUsed)
Write-Host ("Final rows      : {0}" -f $finalRows.Count)
Write-Host ("VMIN stage CSV  : {0}" -f $vminStagePath)
Write-Host ("SICC stage CSV  : {0}" -f $siccStagePath)
Write-Host ("Final CSV       : {0}" -f $finalPath)
Write-Host ("Violations CSV  : {0}" -f $violationsPath)
Write-Host ("CCF diag CSV    : {0}" -f $ccfDiagnosticsPath)
