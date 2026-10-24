#requires -Version 5.1
<#
.SYNOPSIS
Reconstruct weekly analysis database from ITUFF + Aqua with VisualID-only filtering.

.DESCRIPTION
1. Validates ITUFF text files are accessible and scans all files recursively.
2. Extracts Visual IDs and parses ITUFF Vmin/DTS/LP and SICC payloads.
3. Runs Aqua using only VisualID filter (no program/product/date/ops/bin filters).
4. Uses Aqua output as the base and enriches missing data from ITUFF parsing.
5. Writes final CSV and diagnostic artifacts.
#>

param(
    [string]$ItufRootDirectory = "C:\Users\hmarkovi\OneDrive - Intel Corporation\Documents\ituf try\Unzipped",
    [string]$AquaExe = "\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe",
    [string]$AquaServer = "GER",
    [string]$ReportPath = "hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12",
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs",
    [string]$OutputBaseName = "2026_37_NVLAX_25A_ITUF_RESULTS",
    [int]$AquaPullTimeoutSeconds = 1800,
    [int]$AquaPullPollSeconds = 10,
    [int]$MaxVisualIdsPerAquaQuery = 1200,
    [double]$MinValidVmin = 0.2,
    [double]$MaxValidVmin = 2.0,
    [switch]$ListVisualIdsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NonEmptyFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label was not created: $Path" }
    if ((Get-Item -LiteralPath $Path).Length -le 0) { throw "$Label is empty: $Path" }
}

function Wait-ForFileReady {
    param(
        [string]$Path,
        [int]$TimeoutSeconds,
        [int]$PollSeconds,
        [int]$StableChecks = 2
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLength = -1
    $stableCount = 0

    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $currentLength = (Get-Item -LiteralPath $Path).Length
            if ($currentLength -gt 0 -and $currentLength -eq $lastLength) {
                $stableCount++
                if ($stableCount -ge $StableChecks) { return $true }
            }
            else {
                $stableCount = 0
                $lastLength = $currentLength
            }
        }
        Start-Sleep -Seconds $PollSeconds
    }

    return $false
}

function Resolve-AquaExePathForAutomation {
    param([string]$SourceAquaExePath)

    $cacheDir = Join-Path $env:LOCALAPPDATA "NVLH\AquaCmdLine"
    $cachedExe = Join-Path $cacheDir "AquaCmdLine.exe"

    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    }

    $needsCopy = $false
    if (-not (Test-Path -LiteralPath $cachedExe)) {
        $needsCopy = $true
    }
    else {
        $src = Get-Item -LiteralPath $SourceAquaExePath
        $dst = Get-Item -LiteralPath $cachedExe
        if ($src.LastWriteTime -gt $dst.LastWriteTime) { $needsCopy = $true }
    }

    if ($needsCopy) {
        Copy-Item -LiteralPath $SourceAquaExePath -Destination $cachedExe -Force
        Unblock-File -LiteralPath $cachedExe -ErrorAction SilentlyContinue
    }

    return $cachedExe
}

function Get-FirstExistingColumnName {
    param([string[]]$CandidateNames, [string[]]$AvailableNames)
    foreach ($candidate in $CandidateNames) {
        if ($AvailableNames -contains $candidate) { return $candidate }
    }
    return $null
}

function Get-ItufIdentityFromFile {
    param([string]$FilePath)

    $visualId = ""
    $lotFromFs = ""

    $reader = $null
    try {
        $reader = New-Object System.IO.StreamReader($FilePath)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            if ([string]::IsNullOrWhiteSpace($visualId) -and $line -match '^2_visualid_(?<Id>\S+)$') {
                $visualId = $Matches['Id'].Trim().ToUpperInvariant()
                continue
            }

            if ([string]::IsNullOrWhiteSpace($lotFromFs) -and $line -match '^6_lotid_(?<Id>\S+)$') {
                $lotFromFs = $Matches['Id'].Trim().ToUpperInvariant()
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($visualId) -and -not [string]::IsNullOrWhiteSpace($lotFromFs)) {
                break
            }
        }
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
    }

    return [pscustomobject]@{
        VisualID = $visualId
        LotFromFs = $lotFromFs
    }
}

function Parse-VminFwCfg {
    param([string]$CfgValue)

    $result = @()
    if ([string]::IsNullOrWhiteSpace($CfgValue)) { return $result }

    foreach ($entry in ($CfgValue -split "_")) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $atParts = $entry -split "@", 2
        $domain = $atParts[0].Trim()
        $corner = ""
        $flow = ""
        $freqGHz = ""

        if ($atParts.Count -gt 1) {
            $colonParts = $atParts[1] -split ":", 3
            if ($colonParts.Count -ge 1) { $corner = $colonParts[0].Trim() }
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

function Parse-TestNameFreqInfo {
    param([string]$TestName)

    if ([string]::IsNullOrWhiteSpace($TestName)) {
        return [pscustomobject]@{ Corner = ""; FreqGHz = "" }
    }

    if ($TestName -match '_FMIN_(\d{3,4})(?:_|$)') {
        $mhzRaw = $Matches[1]
        $mhz = 0
        if ([int]::TryParse($mhzRaw, [ref]$mhz)) {
            $ghz = [double]$mhz / 1000.0
            return [pscustomobject]@{
                Corner = "FMIN"
                FreqGHz = $ghz.ToString("0.000", [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
    }

    return [pscustomobject]@{ Corner = ""; FreqGHz = "" }
}

function Parse-PerCoreVminValues {
    param([string]$VminRaw, [double]$MinValue = 0.2, [double]$MaxValue = 2.0)

    if ([string]::IsNullOrWhiteSpace($VminRaw)) { return @() }

    if ($VminRaw -notmatch "\|" -and $VminRaw -notmatch "_") {
        $single = 0.0
        if ([double]::TryParse($VminRaw.Trim(),
                [System.Globalization.NumberStyles]::Any,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$single) -and $single -ge $MinValue -and $single -le $MaxValue) {
            return @($single)
        }
        return @()
    }

    $pipeSegments = @($VminRaw -split "\|")
    if ($pipeSegments.Count -eq 0) { return @() }
    $primarySegment = [string]$pipeSegments[0]
    if ($null -eq $primarySegment) { return @() }

    $result = @()
    foreach ($part in ($primarySegment -split "_")) {
        $val = 0.0
        if ([double]::TryParse($part.Trim(),
                [System.Globalization.NumberStyles]::Any,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$val) -and $val -ge $MinValue -and $val -le $MaxValue) {
            $result += $val
        }
        else {
            $result += $null
        }
    }

    return $result
}

function Get-MaxDts {
    param([string]$DtsValue)

    if ([string]::IsNullOrWhiteSpace($DtsValue)) { return $null }

    $maxTemp = $null
    foreach ($sensor in ($DtsValue -split "\|")) {
        $parts = $sensor.Trim() -split ":", 2
        if ($parts.Count -lt 2) { continue }

        $tempVal = 0.0
        if ([double]::TryParse($parts[1].Trim(),
                [System.Globalization.NumberStyles]::Any,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$tempVal)) {
            if ($null -eq $maxTemp -or $tempVal -gt $maxTemp) {
                $maxTemp = $tempVal
            }
        }
    }

    return $maxTemp
}

function Parse-SiccEntries {
    param([string]$RawValue)

    $entries = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($RawValue)) { return $entries }

    $tokens = @($RawValue -split '\^') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($token in $tokens) {
        $t = $token.Trim()
        if ($t -match '^(?<Domain>[A-Za-z0-9]+)-(?<Vp>V\d+):(?<Value>[+-]?\d*\.?\d+)(?:%(?<Volt>[+-]?\d*\.?\d+))?(?:%(?<Temp>[+-]?\d*\.?\d+))?$') {
            $entries.Add([pscustomobject]@{
                DomainCore = $Matches['Domain'].ToUpperInvariant()
                VoltagePoint = $Matches['Vp'].ToUpperInvariant()
                SiccValue = $Matches['Value']
                VoltageValue = if ($Matches['Volt']) { $Matches['Volt'] } else { "" }
                TemperatureValue = if ($Matches['Temp']) { $Matches['Temp'] } else { "" }
            })
        }
    }

    return $entries
}

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -LiteralPath $ItufRootDirectory)) {
    throw "ITUFF root folder does not exist: $ItufRootDirectory"
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$manifestPath = Join-Path $OutputDirectory ("{0}_manifest_{1}.csv" -f $OutputBaseName, $runStamp)
$identityPath = Join-Path $OutputDirectory ("{0}_ituf_identities_{1}.csv" -f $OutputBaseName, $runStamp)
$visualIdsPath = Join-Path $OutputDirectory ("{0}_visualids_{1}.csv" -f $OutputBaseName, $runStamp)
$aquaRawPath = Join-Path $OutputDirectory ("{0}_aqua_raw_{1}.csv" -f $OutputBaseName, $runStamp)
$unmatchedPath = Join-Path $OutputDirectory ("{0}_unmatched_{1}.csv" -f $OutputBaseName, $runStamp)
$coveragePath = Join-Path $OutputDirectory ("{0}_coverage_{1}.csv" -f $OutputBaseName, $runStamp)
$finalPath = Join-Path $OutputDirectory ("{0}.csv" -f $OutputBaseName)

$itufFiles = @(
    Get-ChildItem -LiteralPath $ItufRootDirectory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.txt' -or $_.Name -like '*.itf' -or $_.Name -like '*.itf.txt' }
)

if ($itufFiles.Count -eq 0) {
    throw "No ITUFF text files found under $ItufRootDirectory"
}

$manifestRows = New-Object System.Collections.Generic.List[object]
$identityRows = New-Object System.Collections.Generic.List[object]
$visualIdSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$vminBaseLookup = @{}
$siccLatestLookup = @{}
$sequence = 0

foreach ($file in $itufFiles) {
    $fileVisualId = ""
    $fileLotFromFs = ""
    $parseStatus = "OK"
    $errorText = ""
    $pairLookup = @{}

    try {
        $identity = Get-ItufIdentityFromFile -FilePath $file.FullName
        $fileVisualId = [string]$identity.VisualID
        $fileLotFromFs = [string]$identity.LotFromFs

        $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            if ($line -match '^(?<Idx>\d+)_tname_(?<Val>.+)$') {
                $idx = [int]$Matches['Idx']
                if (-not $pairLookup.ContainsKey($idx)) {
                    $pairLookup[$idx] = [ordered]@{ tname = ""; strgval = "" }
                }
                $pairLookup[$idx].tname = $Matches['Val']
                continue
            }

            if ($line -match '^(?<Idx>\d+)_strgval_(?<Val>.*)$') {
                $idx = [int]$Matches['Idx']
                if (-not $pairLookup.ContainsKey($idx)) {
                    $pairLookup[$idx] = [ordered]@{ tname = ""; strgval = "" }
                }
                $pairLookup[$idx].strgval = $Matches['Val']
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($fileVisualId)) {
            [void]$visualIdSet.Add($fileVisualId)
        }

        foreach ($idx in $pairLookup.Keys) {
            $pair = $pairLookup[$idx]
            $tname = [string]$pair.tname
            $value = [string]$pair.strgval
            if ([string]::IsNullOrWhiteSpace($tname) -or [string]::IsNullOrWhiteSpace($value)) { continue }
            if ([string]::IsNullOrWhiteSpace($fileVisualId)) { continue }

            $sequence++
            $upperTname = $tname.ToUpperInvariant()

            if ($upperTname -like '*SICC*') {
                $siccEntries = Parse-SiccEntries -RawValue $value
                foreach ($entry in $siccEntries) {
                    $k = "{0}||{1}||{2}" -f $fileVisualId, $entry.VoltagePoint, $entry.DomainCore
                    $siccLatestLookup[$k] = [pscustomobject]@{
                        VisualID = $fileVisualId
                        VoltagePoint = $entry.VoltagePoint
                        DomainCore = $entry.DomainCore
                        SiccValue = $entry.SiccValue
                        VoltageValue = $entry.VoltageValue
                        TemperatureValue = $entry.TemperatureValue
                        Sequence = $sequence
                        TestName = $tname
                    }
                }
            }

            if ($upperTname -notlike '*_VMIN_*') { continue }

            $kind = 'Base'
            $base = $tname
            if ($upperTname.EndsWith('_DTS')) {
                $kind = 'DTS'
                $base = $tname.Substring(0, $tname.Length - 4)
            }
            elseif ($upperTname.EndsWith('_VMINFWCFG')) {
                $kind = 'CFG'
                $base = $tname.Substring(0, $tname.Length - 10)
            }
            elseif ($upperTname.EndsWith('_LP')) {
                $kind = 'LP'
                $base = $tname.Substring(0, $tname.Length - 3)
            }
            elseif ($upperTname.EndsWith('_IT') -or $upperTname.EndsWith('_SCRB')) {
                continue
            }

            $vkey = "{0}||{1}" -f $fileVisualId, $base
            if (-not $vminBaseLookup.ContainsKey($vkey)) {
                $vminBaseLookup[$vkey] = [ordered]@{
                    VisualID = $fileVisualId
                    BaseTest = $base
                    VminRaw = ""
                    CfgRaw = ""
                    DtsRaw = ""
                    LpRaw = ""
                }
            }

            switch ($kind) {
                'Base' { $vminBaseLookup[$vkey].VminRaw = $value }
                'CFG' { $vminBaseLookup[$vkey].CfgRaw = $value }
                'DTS' { $vminBaseLookup[$vkey].DtsRaw = $value }
                'LP' { $vminBaseLookup[$vkey].LpRaw = $value }
            }
        }
    }
    catch {
        $parseStatus = "ERROR"
        $errorText = $_.Exception.Message
    }

    $manifestRows.Add([pscustomobject]@{
        FilePath = $file.FullName
        FileName = $file.Name
        FileSize = $file.Length
        LastWriteTime = $file.LastWriteTime
        ParsedVisualID = $fileVisualId
        ParsedLotFromFs = $fileLotFromFs
        ParseStatus = $parseStatus
        ErrorMessage = $errorText
    })

    $identityRows.Add([pscustomobject]@{
        FileName = $file.Name
        FilePath = $file.FullName
        VisualID = $fileVisualId
        LotFromFs = $fileLotFromFs
        ParseStatus = $parseStatus
    })
}

$manifestRows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8
$identityRows | Export-Csv -LiteralPath $identityPath -NoTypeInformation -Encoding UTF8

$visualRows = @($visualIdSet | Sort-Object | ForEach-Object { [pscustomobject]@{ VisualID = $_ } })
if ($visualRows.Count -eq 0 -and -not $ListVisualIdsOnly) {
    throw "No Visual IDs extracted from ITUFF files. Expected records like 2_visualid_<value>."
}
if ($visualRows.Count -gt 0) {
    $visualRows | Export-Csv -LiteralPath $visualIdsPath -NoTypeInformation -Encoding UTF8
}

Write-Host ("ITUFF files found: {0}" -f $itufFiles.Count)
Write-Host ("Visual IDs extracted: {0}" -f $visualRows.Count)

if ($ListVisualIdsOnly) {
    Write-Host ""
    Write-Host "ITUFF file identities:"
    $identityRows |
        Sort-Object FileName |
        Select-Object FileName, VisualID, LotFromFs, ParseStatus |
        Format-Table -AutoSize | Out-Host

    Write-Host ""
    Write-Host "All Visual IDs:"
    if ($visualRows.Count -gt 0) {
        $visualRows | Sort-Object VisualID | Select-Object -ExpandProperty VisualID | Out-Host
    }
    else {
        Write-Host "<none found>"
    }

    Write-Host ""
    Write-Host ("Identity CSV        : {0}" -f $identityPath)
    if ($visualRows.Count -gt 0) {
        Write-Host ("VisualID list CSV   : {0}" -f $visualIdsPath)
    }
    return
}

if (-not (Test-Path -LiteralPath $AquaExe)) {
    throw "Aqua executable not found: $AquaExe"
}

$AquaExe = Resolve-AquaExePathForAutomation -SourceAquaExePath $AquaExe

$allAquaRows = New-Object System.Collections.Generic.List[object]
$chunks = @()
for ($i = 0; $i -lt $visualRows.Count; $i += $MaxVisualIdsPerAquaQuery) {
    $end = [Math]::Min($i + $MaxVisualIdsPerAquaQuery - 1, $visualRows.Count - 1)
    $chunks += ,(@($visualRows[$i..$end]))
}

$chunkIndex = 0
foreach ($chunk in $chunks) {
    $chunkIndex++
    $visualIdsCsv = (($chunk | ForEach-Object { $_.VisualID }) -join ',')
    $chunkOut = Join-Path $OutputDirectory ("{0}_aqua_chunk{1}_{2}.csv" -f $OutputBaseName, $chunkIndex, $runStamp)

    $aquaArgs = @(
        '-aquaserver', $AquaServer,
        '-reportpath', $ReportPath,
        '-outputfilename', $chunkOut,
        '-visualIds', $visualIdsCsv
    )

    & $AquaExe @aquaArgs

    $isReady = Wait-ForFileReady -Path $chunkOut -TimeoutSeconds $AquaPullTimeoutSeconds -PollSeconds $AquaPullPollSeconds
    if (-not $isReady) {
        throw "Aqua chunk output was not ready in time: $chunkOut"
    }

    Assert-NonEmptyFile -Path $chunkOut -Label "Aqua chunk output"

    $chunkRows = @(Import-Csv -LiteralPath $chunkOut)
    foreach ($r in $chunkRows) { $allAquaRows.Add($r) }

    Remove-Item -LiteralPath $chunkOut -Force -ErrorAction SilentlyContinue
}

if ($allAquaRows.Count -eq 0) {
    throw "Aqua returned no rows for extracted Visual IDs."
}

$allAquaRows | Export-Csv -LiteralPath $aquaRawPath -NoTypeInformation -Encoding UTF8

$aquaColumns = $allAquaRows[0].PSObject.Properties.Name
$aquaVisualCol = Get-FirstExistingColumnName -CandidateNames @('VISUAL_ID', 'Visual ID', 'VisualID', 'VisualId', 'VISUALID', 'VID') -AvailableNames $aquaColumns
if (-not $aquaVisualCol) {
    throw "Could not find Visual ID column in Aqua output."
}

$allDetailRecords = New-Object System.Collections.Generic.List[object]
foreach ($item in $vminBaseLookup.Values) {
    if ([string]::IsNullOrWhiteSpace($item.VminRaw)) { continue }
    if ([string]::IsNullOrWhiteSpace($item.CfgRaw)) { continue }

    $cfgList = @(Parse-VminFwCfg -CfgValue $item.CfgRaw)
    if ($cfgList.Count -eq 0) { continue }

    $vminValues = @(Parse-PerCoreVminValues -VminRaw $item.VminRaw -MinValue $MinValidVmin -MaxValue $MaxValidVmin)
    $maxDts = Get-MaxDts -DtsValue $item.DtsRaw
    $testFreqInfo = Parse-TestNameFreqInfo -TestName $item.BaseTest

    $pairCount = [Math]::Min($cfgList.Count, $vminValues.Count)
    for ($idx = 0; $idx -lt $pairCount; $idx++) {
        $v = $vminValues[$idx]
        if ($null -eq $v) { continue }

        $domain = $cfgList[$idx].Domain
        $corner = $cfgList[$idx].FreqCorner
        $flow = $cfgList[$idx].Flow
        $freq = $cfgList[$idx].FreqGHz
        $coreIndex = $idx
        if ($domain -match '(\d+)$') {
            $coreIndex = [int]$Matches[1]
        }

        $allDetailRecords.Add([pscustomobject]@{
            VisualID = $item.VisualID
            Domain = $domain
            FreqCorner = $corner
            Flow = $flow
            FreqGHz = $freq
            CoreIndex = $coreIndex
            Vmin = $v
            Setter = $item.BaseTest
            MaxDTS_C = if ($null -ne $maxDts) { $maxDts } else { '' }
            LP = $item.LpRaw
            TestFreqCorner = $testFreqInfo.Corner
            TestFreqGHz = $testFreqInfo.FreqGHz
        })
    }
}

$maxByCombo = @{}
foreach ($rec in $allDetailRecords) {
    if ([string]::Equals([string]$rec.TestFreqCorner, 'FMIN', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $key = "{0}||{1}||{2}||{3}||{4}||{5}" -f $rec.VisualID, $rec.Domain, $rec.FreqCorner, $rec.Flow, $rec.FreqGHz, $rec.CoreIndex
    if (-not $maxByCombo.ContainsKey($key)) {
        $maxByCombo[$key] = $rec
        continue
    }

    $cur = $maxByCombo[$key]
    if ([double]$rec.Vmin -gt [double]$cur.Vmin) {
        $maxByCombo[$key] = $rec
        continue
    }

    if ([double]$rec.Vmin -eq [double]$cur.Vmin) {
        $recHasLp = -not [string]::IsNullOrWhiteSpace([string]$rec.LP)
        $curHasLp = -not [string]::IsNullOrWhiteSpace([string]$cur.LP)
        if ($recHasLp -and -not $curHasLp) {
            $maxByCombo[$key] = $rec
            continue
        }

        $recHasDts = -not [string]::IsNullOrWhiteSpace([string]$rec.MaxDTS_C)
        $curHasDts = -not [string]::IsNullOrWhiteSpace([string]$cur.MaxDTS_C)
        if ($recHasDts -and -not $curHasDts) {
            $maxByCombo[$key] = $rec
        }
    }
}

$vminColumnMap = @{}
$vminUniqueColumns = New-Object 'System.Collections.Generic.SortedSet[string]'
foreach ($rec in $maxByCombo.Values) {
    $cornerToken = if ([string]::IsNullOrWhiteSpace($rec.FreqCorner)) { 'NA' } else { ([string]$rec.FreqCorner -replace '[^A-Za-z0-9]', '_') }
    $flowToken = if ([string]::IsNullOrWhiteSpace($rec.Flow)) { 'NA' } else { ([string]$rec.Flow -replace '[^A-Za-z0-9]', '_') }
    $freqToken = if ([string]::IsNullOrWhiteSpace($rec.FreqGHz)) { 'NA' } else { ([string]$rec.FreqGHz -replace '[^A-Za-z0-9\.]', '_') }
    $prefix = "ITUF_{0}_{1}_Flow{2}_Freq{3}_C{4}" -f $rec.Domain, $cornerToken, $flowToken, $freqToken, $rec.CoreIndex

    foreach ($suffix in @('Vmin', 'Setter', 'MaxDTS_C', 'LP')) {
        [void]$vminUniqueColumns.Add("{0}_{1}" -f $prefix, $suffix)
    }

    $vminColumnMap["{0}||{1}" -f $rec.VisualID, $prefix] = $rec
}

$siccColumnSet = New-Object 'System.Collections.Generic.SortedSet[string]'
foreach ($entry in $siccLatestLookup.Values) {
    [void]$siccColumnSet.Add(("SICC {0} {1}" -f $entry.VoltagePoint, $entry.DomainCore))
    [void]$siccColumnSet.Add(("SICC {0} {1} Temperature" -f $entry.VoltagePoint, $entry.DomainCore))
}

$finalRows = New-Object System.Collections.Generic.List[object]
foreach ($row in $allAquaRows) {
    $newMap = [ordered]@{}
    foreach ($p in $row.PSObject.Properties) {
        $newMap[$p.Name] = $p.Value
    }

    $visual = ([string]$row.$aquaVisualCol).Trim().ToUpperInvariant()

    foreach ($col in $vminUniqueColumns) {
        $newMap[$col] = ''
    }
    foreach ($col in $siccColumnSet) {
        $newMap[$col] = ''
    }

    foreach ($k in $vminColumnMap.Keys) {
        if ($k -like "$visual||*") {
            $parts = $k -split '\|\|', 2
            $prefix = $parts[1]
            $rec = $vminColumnMap[$k]
            $newMap["{0}_Vmin" -f $prefix] = $rec.Vmin
            $newMap["{0}_Setter" -f $prefix] = $rec.Setter
            $newMap["{0}_MaxDTS_C" -f $prefix] = $rec.MaxDTS_C
            $newMap["{0}_LP" -f $prefix] = $rec.LP
        }
    }

    foreach ($entry in $siccLatestLookup.Values) {
        if ($entry.VisualID -ne $visual) { continue }
        $valueCol = "SICC {0} {1}" -f $entry.VoltagePoint, $entry.DomainCore
        $tempCol = "SICC {0} {1} Temperature" -f $entry.VoltagePoint, $entry.DomainCore
        $newMap[$valueCol] = $entry.SiccValue
        $newMap[$tempCol] = $entry.TemperatureValue
    }

    $finalRows.Add([pscustomobject]$newMap)
}

$finalRows | Export-Csv -LiteralPath $finalPath -NoTypeInformation -Encoding UTF8
Assert-NonEmptyFile -Path $finalPath -Label "Final reconstructed CSV"

$aquaVisualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $allAquaRows) {
    $v = ([string]$r.$aquaVisualCol).Trim().ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$aquaVisualSet.Add($v) }
}

$unmatchedRows = New-Object System.Collections.Generic.List[object]
foreach ($vid in $visualIdSet) {
    if (-not $aquaVisualSet.Contains($vid)) {
        $unmatchedRows.Add([pscustomobject]@{ Source = 'ITUFF_ONLY'; VisualID = $vid })
    }
}
foreach ($vid in $aquaVisualSet) {
    if (-not $visualIdSet.Contains($vid)) {
        $unmatchedRows.Add([pscustomobject]@{ Source = 'AQUA_ONLY'; VisualID = $vid })
    }
}
$unmatchedRows | Export-Csv -LiteralPath $unmatchedPath -NoTypeInformation -Encoding UTF8

$rowsWithVmin = @($finalRows | Where-Object {
        $hasValue = $false
        foreach ($prop in $_.PSObject.Properties) {
            if ($prop.Name -like 'ITUF_*_Vmin' -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                $hasValue = $true
                break
            }
        }
        $hasValue
    }).Count
$rowsWithSicc = @($finalRows | Where-Object {
        $hasValue = $false
        foreach ($prop in $_.PSObject.Properties) {
            if ($prop.Name -like 'SICC V* *' -and $prop.Name -notlike '*Temperature' -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                $hasValue = $true
                break
            }
        }
        $hasValue
    }).Count

@(
    [pscustomobject]@{ Metric = 'ItufFiles'; Value = $itufFiles.Count }
    [pscustomobject]@{ Metric = 'VisualIdsFromItuf'; Value = $visualRows.Count }
    [pscustomobject]@{ Metric = 'AquaRows'; Value = $allAquaRows.Count }
    [pscustomobject]@{ Metric = 'FinalRows'; Value = $finalRows.Count }
    [pscustomobject]@{ Metric = 'RowsWithVmin'; Value = $rowsWithVmin }
    [pscustomobject]@{ Metric = 'RowsWithSicc'; Value = $rowsWithSicc }
    [pscustomobject]@{ Metric = 'VminDetailRecords'; Value = $allDetailRecords.Count }
    [pscustomobject]@{ Metric = 'SiccDecodedRecords'; Value = $siccLatestLookup.Count }
) | Export-Csv -LiteralPath $coveragePath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host ("Final output        : {0}" -f $finalPath)
Write-Host ("Manifest            : {0}" -f $manifestPath)
Write-Host ("VisualID list       : {0}" -f $visualIdsPath)
Write-Host ("Aqua raw            : {0}" -f $aquaRawPath)
Write-Host ("Unmatched diagnostics: {0}" -f $unmatchedPath)
Write-Host ("Coverage summary    : {0}" -f $coveragePath)
Write-Host ("Rows in final       : {0}" -f $finalRows.Count)
