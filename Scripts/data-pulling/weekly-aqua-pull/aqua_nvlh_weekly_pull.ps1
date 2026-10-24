<#
.SYNOPSIS
Orchestrate weekly UPSVF AQUA pull, clean data, trigger ILAS analysis, and merge ILAS columns back into UPSVF.

.DESCRIPTION
Pulls UPSVF (unit parametric test/pass/fail) from AQUA, cleans column output, invokes ILAS analysis on VisualID+Lot keys,
and merges ILAS-derived Vmin/Setter/MaxDTS_C/LP columns back into final output.

CHANGES & AUTOMATED FIXES (2026-06-07):
- Temp file collision fix (lines ~480-485): Replaced Move-Item -Force with Copy-Item -Force + explicit stale cleanup
  Problem: Move-Item fails if destination exists (e.g., from prior failed run)
  Solution: Copy-Item -Force atomically replaces content; pre-cleanup of stale .tmp removes collision risk
  Impact: Re-runs and fault recovery now work correctly without manual cleanup
- ILAS opergroup filtering: Delegated to aqua_nvlh_ilas_vmin_analysis.ps1 with default OpergroupFilter="6248_CLASSHOT"
- ILAS test name cleaning: Added suffix filter (aqua_nvlh_ilas_vmin_analysis.ps1) to remove rows ending in "_it" or "_scrb"
- Retention policy: 7-day test-end lookback maintained (LastNDaysTestEnd=7 as default)

CHANGES (2026-06-09):
- Removed -LastNDaysTestEnd from ILAS script invocation (aqua_nvlh_ilas_vmin_analysis.ps1 no longer receives it)
  Reason: ILAS query is VisualID-scoped and must not be date-bounded; passing LastNDays caused empty AQUA results
- Fixed retention CSV pruning bug: changed [datetime]::TryParse to [datetimeoffset]::TryParse
  Reason: status CSV timestamps include timezone offset (e.g., +02:00); DateTime.TryParse overload with [ref] arg
  not available in PowerShell 5.1, causing "Cannot find an overload" warning on every run

CHANGES (2026-06-21):
- AQUA report format change: RCS_PROCESSSTEP column no longer present in BSAT_UPS2_POR_PTL_NVL WW12 report output
  New format uses DevRevStep_CLASSHOT (non-empty value = unit ran at CLASSHOT; empty = did not)
  Fix: step-column detection now falls back to DevRevStep_CLASSHOT when RCS_PROCESSSTEP variants are absent
  Filter mode tracks which column was found: "EqClasshot" (old) vs "NotEmpty" (new DevRevStep_CLASSHOT)

.PARAMETER LastNDaysTestEnd
Default: 7 (filters AQUA pull to last 7 days of test end date)
#>

param(
    [string]$AquaExe = "\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe",
    [string]$AquaServer = "GER",
    [string]$ReportPath = "hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12",
    [string]$ProgramPattern = "NVLHM66*",
    [string]$Operations = "6248",
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs",
    [string]$FunctionalBin = "100",
    [int]$LastNDaysTestEnd = 7,
    [int]$RetentionDays = 366,
    [int]$MaxVisualUnits = 100000,
    [int]$AquaMaxRows = 150000,
    [int]$AquaPullTimeoutSeconds = 900,
    [int]$AquaPullPollSeconds = 10,
    [string]$IlasScriptPath = "",
    [string]$MergeScriptPath = "",
    [switch]$SkipIlasStep,
    [switch]$KeepCleanCsvArtifact,
    [string]$RawInputFile = "",
    [string]$LotsOverride = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-SafeFileNamePart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Value
    foreach ($char in $invalidChars) {
        $safe = $safe.Replace($char, "_")
    }

    # Keep file names readable and reasonably short.
    return ($safe -replace "\s+", "_").Trim("_")
}

function Get-IsoWeekYear {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )

    # Prefer the built-in ISO API when available (.NET Core / newer runtimes).
    $isoWeekType = [type]::GetType("System.Globalization.ISOWeek")
    if ($isoWeekType) {
        return [pscustomobject]@{
            Week = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
            Year = [System.Globalization.ISOWeek]::GetYear($Date)
        }
    }

    # PowerShell 5.1/.NET Framework fallback: ISO-like week/year using FirstFourDayWeek + Monday.
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $dateForWeek = $Date
    if ($Date.DayOfWeek -eq [System.DayOfWeek]::Monday -or
        $Date.DayOfWeek -eq [System.DayOfWeek]::Tuesday -or
        $Date.DayOfWeek -eq [System.DayOfWeek]::Wednesday) {
        $dateForWeek = $Date.AddDays(3)
    }

    return [pscustomobject]@{
        Week = $cal.GetWeekOfYear($dateForWeek, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        Year = $dateForWeek.Year
    }
}

function Limit-RowsByVisualUnits {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InputRows,
        [Parameter(Mandatory = $true)]
        [string]$VisualIdColumn,
        [Parameter(Mandatory = $true)]
        [int]$Limit
    )

    $seenVisualIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $selectedRows = New-Object System.Collections.Generic.List[object]

    foreach ($row in $InputRows) {
        $visualId = [string]$row.$VisualIdColumn
        if ([string]::IsNullOrWhiteSpace($visualId)) {
            continue
        }

        if ($seenVisualIds.Contains($visualId)) {
            $selectedRows.Add($row)
            continue
        }

        if ($seenVisualIds.Count -ge $Limit) {
            continue
        }

        [void]$seenVisualIds.Add($visualId)
        $selectedRows.Add($row)
    }

    return [pscustomobject]@{
        Rows = $selectedRows
        VisualUnitCount = $seenVisualIds.Count
    }
}

function Remove-ExpiredRunFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [datetime]$Cutoff
    )

    $patterns = @("_raw_*.csv", "_clean_*.csv", "_clean_*.jmp", "Vmin_*.csv", "Vmin_*.jmp")
    foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $Cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Update-LogRetention {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [Parameter(Mandatory = $true)]
        [datetime]$Cutoff
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return
    }

    $lines = @(Get-Content -LiteralPath $LogPath)
    if ($lines.Count -eq 0) {
        return
    }

    $keptLines = New-Object System.Collections.Generic.List[string]
    $keptLines.Add($lines[0])

    $currentSection = New-Object System.Collections.Generic.List[string]
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -like '## WW*') {
            if ($currentSection.Count -gt 0) {
                $timestampLine = $currentSection | Where-Object { $_ -like '- Run timestamp:*' } | Select-Object -First 1
                $keepSection = $true
                if ($timestampLine) {
                    $timestampValue = ($timestampLine -replace '^- Run timestamp:\s*', '').Trim()
                    $parsedTimestamp = $null
                    if ([datetime]::TryParse($timestampValue, [ref]$parsedTimestamp)) {
                        $keepSection = $parsedTimestamp -ge $Cutoff
                    }
                }

                if ($keepSection) {
                    foreach ($sectionLine in $currentSection) {
                        $keptLines.Add($sectionLine)
                    }
                }
            }

            $currentSection = New-Object System.Collections.Generic.List[string]
        }

        $currentSection.Add($line)
    }

    if ($currentSection.Count -gt 0) {
        $timestampLine = $currentSection | Where-Object { $_ -like '- Run timestamp:*' } | Select-Object -First 1
        $keepSection = $true
        if ($timestampLine) {
            $timestampValue = ($timestampLine -replace '^- Run timestamp:\s*', '').Trim()
            $parsedTimestamp = $null
            if ([datetime]::TryParse($timestampValue, [ref]$parsedTimestamp)) {
                $keepSection = $parsedTimestamp -ge $Cutoff
            }
        }

        if ($keepSection) {
            foreach ($sectionLine in $currentSection) {
                $keptLines.Add($sectionLine)
            }
        }
    }

    $keptLines | Set-Content -LiteralPath $LogPath -Encoding UTF8
}

function Assert-NonEmptyFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label was not created: $Path"
    }

    $fileInfo = Get-Item -LiteralPath $Path
    if ($fileInfo.Length -le 0) {
        throw "$Label is empty: $Path"
    }
}

function Wait-ForFileReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)]
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
                if ($stableCount -ge $StableChecks) {
                    return $true
                }
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
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceAquaExePath
    )
    
    # Cache AquaCmdLine.exe locally and unblock it to eliminate UNC security zone warnings
    # This allows fully unattended execution (e.g., at 5AM via Task Scheduler)
    
    $cacheDir = Join-Path $env:LOCALAPPDATA "NVLH\AquaCmdLine"
    $cachedExe = Join-Path $cacheDir "AquaCmdLine.exe"
    
    # Ensure cache directory exists
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy from UNC if not cached, or if source is newer
    $needsCopy = $false
    if (-not (Test-Path -LiteralPath $cachedExe)) {
        $needsCopy = $true
    } else {
        $sourceInfo = Get-Item -LiteralPath $SourceAquaExePath
        $cachedInfo = Get-Item -LiteralPath $cachedExe
        if ($sourceInfo.LastWriteTime -gt $cachedInfo.LastWriteTime) {
            $needsCopy = $true
        }
    }
    
    if ($needsCopy) {
        Copy-Item -LiteralPath $SourceAquaExePath -Destination $cachedExe -Force | Out-Null
        # Unblock the local copy to suppress security warnings
        Unblock-File -LiteralPath $cachedExe -ErrorAction SilentlyContinue
    }
    
    return $cachedExe
}

function Write-HealthLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HealthLogPath,
        [Parameter(Mandatory = $true)]
        [datetime]$RunStart,
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [int]$RowsBefore = 0,
        [int]$RowsAfter = 0,
        [int]$VisualUnits = 0,
        [string]$CleanCsvPath = "",
        [string]$JmpPath = ""
    )

    try {
        $logDirectory = Split-Path -Path $HealthLogPath -Parent
        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        $entry = [pscustomobject]@{
            RunTimestamp = $RunStart.ToString("yyyy-MM-dd HH:mm:ss zzz")
            Status = $Status
            Message = $Message
            RowsBefore = $RowsBefore
            RowsAfter = $RowsAfter
            VisualUnits = $VisualUnits
            CleanCsvPath = $CleanCsvPath
            JmpPath = $JmpPath
        }

        if (Test-Path -LiteralPath $HealthLogPath) {
            $entry | Export-Csv -LiteralPath $HealthLogPath -Append -NoTypeInformation
        }
        else {
            $entry | Export-Csv -LiteralPath $HealthLogPath -NoTypeInformation
        }
    }
    catch {
        Write-Warning "Could not write health log: $($_.Exception.Message)"
    }
}

function Update-CsvLogRetention {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        [Parameter(Mandatory = $true)]
        [datetime]$Cutoff
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        return
    }

    try {
        $rows = @(Import-Csv -LiteralPath $CsvPath)
        if ($rows.Count -eq 0) {
            return
        }

        $kept = @($rows | Where-Object {
            $ts = [datetimeoffset]::MinValue
            [datetimeoffset]::TryParse([string]$_.RunTimestamp, [ref]$ts) -and $ts.UtcDateTime -ge $Cutoff.ToUniversalTime()
        })

        if ($kept.Count -gt 0) {
            $kept | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
        }
        else {
            Remove-Item -LiteralPath $CsvPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Could not prune status CSV by retention: $($_.Exception.Message)"
    }
}

function Test-UpsvfCsvReady {
    param([string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        return $false
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ($rows.Count -eq 0) {
        return $false
    }

    $cols = $rows[0].PSObject.Properties.Name
    $vidCol = Get-FirstExistingColumnName -CandidateNames @("Visual ID", "VISUAL_ID", "VisualId", "VISUALID", "VID", "VisualID") -AvailableNames $cols
    $lotCol = Get-FirstExistingColumnName -CandidateNames @("LOTFROMFS", "LotFromFs", "LOT", "Lot", "SortLot", "SORT_LOT", "LATO_LOT") -AvailableNames $cols

    return (-not [string]::IsNullOrWhiteSpace($vidCol) -and -not [string]::IsNullOrWhiteSpace($lotCol))
}

function Get-IlasScriptPath {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return $ConfiguredPath
    }

    $weeklyDir = Split-Path -Path $PSCommandPath -Parent
    $scriptsDir = Split-Path (Split-Path $weeklyDir -Parent) -Parent
    $candidatePaths = @(
        (Join-Path $weeklyDir "aqua_nvlh_ilas_vmin_analysis.ps1"),
        (Join-Path $scriptsDir "parametric-analysis\ilas\aqua_nvlh_ilas_vmin_analysis.ps1")
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    return $candidatePaths[-1]
}

function Get-MergeScriptPath {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return $ConfiguredPath
    }

    $weeklyDir = Split-Path -Path $PSCommandPath -Parent
    $scriptsDir = Split-Path (Split-Path $weeklyDir -Parent) -Parent
    $candidatePaths = @(
        (Join-Path $weeklyDir "merge-ilas-into-upsvf.ps1"),
        (Join-Path $scriptsDir "utility\merge-ilas-into-upsvf.ps1")
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    return $candidatePaths[-1]
}

function Get-VisualLotKey {
    param([string]$VisualId, [string]$Lot)
    return ("{0}||{1}" -f $VisualId.Trim(), $Lot.Trim())
}

function Get-DomainCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainToken
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($DomainToken)) {
        return @($candidates)
    }

    # Domain mappings from ILAS naming to UPSVF naming.
    # Known issue domains: CR, CCF/CLR, AT, GT, GTVG, SAAT, SAQ, SAC.
    $domainAliases = @{
        "CR" = @("CR")
        "CCF" = @("CCF", "CLR")
        "CLR" = @("CCF", "CLR")
        "AT" = @("AT")
        "GT" = @("GT")
        "GTVG" = @("GTVG")
        "SAAT" = @("SAAT")
        "SAQ" = @("SAQ")
        "SAC" = @("SAC")
    }

    $token = $DomainToken.Trim().ToUpperInvariant()
    $candidates.Add($token)

    # Common ILAS domain naming includes trailing core index (for example SAQ0, CR0).
    $withoutDigits = ($token -replace '\d+$', '')
    if (-not [string]::IsNullOrWhiteSpace($withoutDigits)) {
        $candidates.Add($withoutDigits)
        if ($domainAliases.ContainsKey($withoutDigits)) {
            foreach ($alias in $domainAliases[$withoutDigits]) {
                $candidates.Add($alias)
            }
        }
    }

    return @($candidates | Select-Object -Unique)
}

function Test-HasUpsvfDataForDomainFreq {
    param(
        [object]$Row,
        [string]$DomainToken,
        [string]$FreqToken,
        [string[]]$ExcludeColumns
    )

    $domainCandidates = @(Get-DomainCandidates -DomainToken $DomainToken)
    $alt1 = $FreqToken
    $alt2 = $FreqToken -replace '\.', '_'
    $alt3 = $FreqToken -replace '\.', ''

    foreach ($prop in $Row.PSObject.Properties) {
        $name = [string]$prop.Name
        if ($ExcludeColumns -contains $name) { continue }
        if ($name -like "ILAS_*") { continue }

        $domainMatch = $false
        foreach ($domainCandidate in $domainCandidates) {
            if ([string]::IsNullOrWhiteSpace($domainCandidate)) { continue }
            if ($name -match ("(?<![A-Za-z0-9]){0}(?![A-Za-z0-9])" -f [regex]::Escape($domainCandidate))) {
                $domainMatch = $true
                break
            }
        }
        if (-not $domainMatch) { continue }

        if ($name -match [regex]::Escape($alt1) -or $name -match [regex]::Escape($alt2) -or $name -match [regex]::Escape($alt3)) {
            $val = [string]$prop.Value
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                return $true
            }
        }
    }

    return $false
}

function Merge-IlasColumnsIntoUpsvfCsv {
    param(
        [string]$UpsvfCsvPath,
        [string]$IlasSummaryCsvPath
    )

    $upsRows = @(Import-Csv -LiteralPath $UpsvfCsvPath)
    $ilasRows = @(Import-Csv -LiteralPath $IlasSummaryCsvPath)
    if ($upsRows.Count -eq 0) { throw "UPSVF CSV is empty: $UpsvfCsvPath" }
    if ($ilasRows.Count -eq 0) { throw "ILAS summary CSV is empty: $IlasSummaryCsvPath" }

    $upsCols = $upsRows[0].PSObject.Properties.Name
    $ilasCols = $ilasRows[0].PSObject.Properties.Name

    $upsVidCol = Get-FirstExistingColumnName -CandidateNames @("Visual ID", "VISUAL_ID", "VisualId", "VISUALID", "VID", "VisualID") -AvailableNames $upsCols
    $upsLotCol = Get-FirstExistingColumnName -CandidateNames @("LOTFROMFS", "LotFromFs", "LOT", "Lot", "SortLot", "SORT_LOT", "LATO_LOT") -AvailableNames $upsCols
    $ilasVidCol = Get-FirstExistingColumnName -CandidateNames @("Visual ID", "VISUAL_ID", "VisualId", "VISUALID", "VID", "VisualID") -AvailableNames $ilasCols
    $ilasLotCol = Get-FirstExistingColumnName -CandidateNames @("LotFromFs", "LOTFROMFS", "LOT", "Lot", "SortLot", "SORT_LOT", "LATO_LOT") -AvailableNames $ilasCols

    if (-not $upsVidCol -or -not $upsLotCol) {
        throw "UPSVF CSV must contain Visual ID and lot/class-lot columns."
    }
    if (-not $ilasVidCol -or -not $ilasLotCol) {
        throw "ILAS summary must contain Visual ID and LotFromFs columns."
    }

    $ilasDataColumns = @($ilasCols | Where-Object { $_ -ne $ilasVidCol -and $_ -ne $ilasLotCol })
    $ilasLookup = @{}
    foreach ($r in $ilasRows) {
        $vid = [string]$r.$ilasVidCol
        $lot = [string]$r.$ilasLotCol
        if ([string]::IsNullOrWhiteSpace($vid) -or [string]::IsNullOrWhiteSpace($lot)) { continue }
        $key = Get-VisualLotKey -VisualId $vid -Lot $lot
        $ilasLookup[$key] = $r
    }

    $ilasPrefixedColumns = @($ilasDataColumns | ForEach-Object { "ILAS_{0}" -f $_ })

    foreach ($row in $upsRows) {
        foreach ($col in $ilasPrefixedColumns) {
            $row | Add-Member -NotePropertyName $col -NotePropertyValue "" -Force
        }

        $vid = [string]$row.$upsVidCol
        $lot = [string]$row.$upsLotCol
        if ([string]::IsNullOrWhiteSpace($vid) -or [string]::IsNullOrWhiteSpace($lot)) { continue }

        $key = Get-VisualLotKey -VisualId $vid -Lot $lot
        if (-not $ilasLookup.ContainsKey($key)) { continue }

        $ilasRow = $ilasLookup[$key]
        foreach ($srcCol in $ilasDataColumns) {
            $dstCol = "ILAS_{0}" -f $srcCol
            $row.$dstCol = $ilasRow.$srcCol
        }
    }

    # Final cleanup: if UPSVF has no value for a given ILAS domain+frequency, clear matching ILAS columns.
    foreach ($row in $upsRows) {
        $domainFreqToIlasCols = @{}
        foreach ($prop in $row.PSObject.Properties) {
            $col = [string]$prop.Name
            if ($col -notlike "ILAS_*") { continue }
            if ($col -match '^ILAS_(?<Domain>.+?)_F\d+_Flow\d+_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$') {
                $d = [string]$Matches['Domain']
                $f = [string]$Matches['Freq']
                $k = "{0}||{1}" -f $d, $f
                if (-not $domainFreqToIlasCols.ContainsKey($k)) {
                    $domainFreqToIlasCols[$k] = New-Object System.Collections.Generic.List[string]
                }
                $domainFreqToIlasCols[$k].Add($col)
            }
        }

        foreach ($domainFreq in $domainFreqToIlasCols.Keys) {
            $parts = $domainFreq -split '\|\|', 2
            if ($parts.Count -ne 2) { continue }

            $domain = $parts[0]
            $freq = $parts[1]
            if (-not (Test-HasUpsvfDataForDomainFreq -Row $row -DomainToken $domain -FreqToken $freq -ExcludeColumns $ilasPrefixedColumns)) {
                foreach ($ilasCol in $domainFreqToIlasCols[$domainFreq]) {
                    $row.$ilasCol = ""
                }
            }
        }
    }

    $tmpPath = "{0}.tmp" -f $UpsvfCsvPath
    if (Test-Path -LiteralPath $tmpPath) {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }

    $upsRows | Export-Csv -LiteralPath $tmpPath -NoTypeInformation
    Assert-NonEmptyFile -Path $tmpPath -Label "Merged UPSVF+ILAS CSV"

    # Replace destination content in a way that tolerates pre-existing files.
    Copy-Item -LiteralPath $tmpPath -Destination $UpsvfCsvPath -Force
    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
}

$runStart = Get-Date
$runStatus = "FAILED"
$runMessage = "Unknown failure"
$rowsBeforeCount = 0
$rowsAfterCount = 0
$visualUnitCount = 0
$cleanCsvPath = ""
$jmpPath = ""
$csvPath = ""
$tempMergedWorkFile = ""
$ilasStatus = "NOT_RUN"
$ilasMessage = "ILAS step not started"
$ilasSummaryPath = ""

function Test-IsIlasDataUnavailableMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $patterns = @(
        "completed without creating an output file",
        "ILAS summary output was not generated",
        "AQUA ILAS output was not ready",
        "ILAS raw file is empty",
        "No ILAS rows remain",
        "No detail records produced"
    )

    foreach ($pattern in $patterns) {
        if ($Message.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}


try {
    if (-not (Test-Path -LiteralPath $AquaExe)) {
        throw "Aqua executable not found: $AquaExe"
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $retentionCutoff = (Get-Date).AddDays(-$RetentionDays)
    $tempRawFile = Join-Path $OutputDirectory ("_raw_{0}.csv" -f $runStamp)
    $tempCleanFile = Join-Path $OutputDirectory ("_clean_{0}.csv" -f $runStamp)
    $tempMergedWorkFile = Join-Path $OutputDirectory ("_merged_work_{0}.csv" -f $runStamp)
    $sourceRawFile = ""
    $pulledRawInThisRun = $false
    $lotArgs = if ([string]::IsNullOrWhiteSpace($LotsOverride)) {
        @("-lotsfromfs")
    }
    else {
        @("-lots", $LotsOverride)
    }

    if (-not [string]::IsNullOrWhiteSpace($RawInputFile)) {
        if (-not (Test-Path -LiteralPath $RawInputFile)) {
            throw "Provided RawInputFile does not exist: $RawInputFile"
        }

        Write-Host "Using existing raw AQUA file: $RawInputFile"
        $sourceRawFile = $RawInputFile
    }
    else {
        Write-Host "Running AQUA pull..."
        # Resolve AquaCmdLine.exe to local cache (eliminates UNC security warnings for unattended execution)
        $AquaExe = Resolve-AquaExePathForAutomation -SourceAquaExePath $AquaExe
        Write-Host "Using Aqua executable: $AquaExe"

        # Build AQUA args array conditionally so callers can clear individual filters
        # by passing empty string (ProgramPattern/Operations) or 0 (LastNDaysTestEnd).
        $aquaCallArgs = [System.Collections.Generic.List[string]]::new()
        $aquaCallArgs.AddRange([string[]]@("-aquaserver", $AquaServer, "-reportpath", $ReportPath, "-outputfilename", $tempRawFile))
        if (-not [string]::IsNullOrWhiteSpace($ProgramPattern)) {
            $aquaCallArgs.AddRange([string[]]@("-programNames", $ProgramPattern))
        }
        if ($LastNDaysTestEnd -gt 0) {
            $aquaCallArgs.AddRange([string[]]@("-lastNDaysTestEnd", [string]$LastNDaysTestEnd))
        }
        if (-not [string]::IsNullOrWhiteSpace($Operations)) {
            $aquaCallArgs.AddRange([string[]]@("-operations", $Operations))
        }
        $aquaCallArgs.AddRange([string[]]@("-dataSampling", [string]$AquaMaxRows))
        $aquaCallArgs.AddRange([string[]]$lotArgs)
        $aquaCallArgs.AddRange([string[]]@("-UnitFunctionalBin", $FunctionalBin))

        $activeFilters = @()
        if (-not [string]::IsNullOrWhiteSpace($ProgramPattern)) { $activeFilters += "ProgramNames=$ProgramPattern" }
        if ($LastNDaysTestEnd -gt 0)                             { $activeFilters += "LastNDaysTestEnd=$LastNDaysTestEnd" }
        if (-not [string]::IsNullOrWhiteSpace($Operations))      { $activeFilters += "Operations=$Operations" }
        $activeFilters += "LotArgs=$($lotArgs -join ' ')"
        $activeFilters += "FunctionalBin=$FunctionalBin"
        Write-Host "AQUA filters active: $($activeFilters -join ' | ')"

        & $AquaExe @aquaCallArgs

        Write-Host "Waiting for AQUA output file to be created and stabilized..."
        $isReady = Wait-ForFileReady -Path $tempRawFile -TimeoutSeconds $AquaPullTimeoutSeconds -PollSeconds $AquaPullPollSeconds
        if (-not $isReady) {
            throw "AQUA output was not ready within $AquaPullTimeoutSeconds seconds: $tempRawFile"
        }

        $sourceRawFile = $tempRawFile
        $pulledRawInThisRun = $true
    }

    $rows = Import-Csv -LiteralPath $sourceRawFile
    if (-not $rows -or $rows.Count -eq 0) {
        throw "Raw AQUA output is empty: $sourceRawFile"
    }
    $rowsBeforeCount = $rows.Count

    # Drop DS columns right after raw pull.
    $rawColumns = $rows[0].PSObject.Properties.Name
    $keepRawColumns = $rawColumns | Where-Object { $_ -notlike "DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW*" }
    $droppedRawDsColumns = $rawColumns.Count - $keepRawColumns.Count
    if ($droppedRawDsColumns -gt 0) {
        Write-Host "Dropping $droppedRawDsColumns DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull..."
        $rows = $rows | Select-Object -Property $keepRawColumns
    }

    $columns = $rows[0].PSObject.Properties.Name
    $lotColumn = Get-FirstExistingColumnName -CandidateNames @("Lot", "LOT", "SortLot", "SORT_LOT", "LATO_LOT", "LOTFROMFS") -AvailableNames $columns
    # Try legacy RCS_PROCESSSTEP first (value = "Classhot"); fall back to new DevRevStep_CLASSHOT (non-empty = unit was at CLASSHOT).
    $stepColumn = Get-FirstExistingColumnName -CandidateNames @("RCS_PROCESSSTEP", "Rcs_ProcessStep", "PROCESSSTEP", "ProcessStep") -AvailableNames $columns
    $stepFilterMode = "EqClasshot"
    if (-not $stepColumn) {
        $stepColumn = Get-FirstExistingColumnName -CandidateNames @("DevRevStep_CLASSHOT", "DEVREVSTEP_CLASSHOT") -AvailableNames $columns
        $stepFilterMode = "NotEmpty"
    }
    $programColumn = Get-FirstExistingColumnName -CandidateNames @("Program Name", "Program Name_RCS", "PROGRAM_NAME", "PROGRAM", "Program", "ProgramName") -AvailableNames $columns
    $visualIdColumn = Get-FirstExistingColumnName -CandidateNames @("Visual ID", "VISUAL_ID", "VisualId", "VISUALID", "VID") -AvailableNames $columns

    if (-not $lotColumn) {
        throw "Could not find a lot column in the AQUA output."
    }
    if (-not $stepColumn) {
        $stepLikeColumns = @($columns | Where-Object {
            $_ -match '(?i)(step|devrev|process|classhot|opergroup|operation)'
        })
        $stepLikePreview = if ($stepLikeColumns.Count -gt 0) {
            ($stepLikeColumns | Select-Object -First 25) -join '; '
        }
        else {
            '<none>'
        }

        throw "Could not find a process-step column in the AQUA output. Tried RCS_PROCESSSTEP variants and DevRevStep_CLASSHOT. Candidate step-like columns: $stepLikePreview"
    }
    if (-not $programColumn) {
        Write-Warning "Could not find a program-name column in the AQUA output. Falling back to UNKNOWN_PROGRAM for output naming."
    }
    if (-not $visualIdColumn) {
        throw "Could not find a visual-unit column in the AQUA output."
    }

    Write-Host "Process-step column: $stepColumn (filter mode: $stepFilterMode)"

    $filteredRows = $rows | Where-Object {
        if ($_.$lotColumn -like "*MV") { return $false }
        if ($stepFilterMode -eq "EqClasshot") {
            return $_.$stepColumn -eq "Classhot"
        }
        else {
            return -not [string]::IsNullOrWhiteSpace([string]$_.$stepColumn)
        }
    }

    if (-not $filteredRows -or $filteredRows.Count -eq 0) {
        throw "No rows left after filters (exclude *MV and keep Classhot)."
    }

    $limitedResult = Limit-RowsByVisualUnits -InputRows $filteredRows -VisualIdColumn $visualIdColumn -Limit $MaxVisualUnits
    $filteredRows = $limitedResult.Rows
    $visualUnitCount = $limitedResult.VisualUnitCount

    if (-not $filteredRows -or $filteredRows.Count -eq 0) {
        throw "No rows left after applying the visual-unit cap."
    }
    $rowsAfterCount = $filteredRows.Count

    $topProgram = $null
    if ($programColumn) {
        $topProgram = $filteredRows |
            Group-Object -Property $programColumn |
            Sort-Object -Property Count -Descending |
            Select-Object -First 1
    }

    $mostAbundantProgram = if ($topProgram -and $topProgram.Name) { $topProgram.Name } else { "UNKNOWN_PROGRAM" }
    $safeProgram = Get-SafeFileNamePart -Value $mostAbundantProgram

    $now = Get-Date
    $dateStamp = $now.ToString("yyyyMMdd")
    $csvName = "Vmin_{0}.csv" -f $dateStamp
    $csvPath = Join-Path $OutputDirectory $csvName

    $filteredRows | Export-Csv -LiteralPath $tempCleanFile -NoTypeInformation
    $filteredRows | Export-Csv -LiteralPath $tempMergedWorkFile -NoTypeInformation

    if ($KeepCleanCsvArtifact) {
        $cleanCsvName = "Vmin_{0}_clean.csv" -f $dateStamp
        $cleanCsvPath = Join-Path $OutputDirectory $cleanCsvName
        Copy-Item -LiteralPath $tempCleanFile -Destination $cleanCsvPath -Force
    }

    if ($KeepCleanCsvArtifact) {
        Assert-NonEmptyFile -Path $cleanCsvPath -Label "Clean CSV"
    }

    if (-not $SkipIlasStep) {
        if (Test-UpsvfCsvReady -CsvPath $tempMergedWorkFile) {
            try {
                $resolvedIlasScriptPath = Get-IlasScriptPath -ConfiguredPath $IlasScriptPath
                if (-not (Test-Path -LiteralPath $resolvedIlasScriptPath)) {
                    throw "ILAS script not found: $resolvedIlasScriptPath"
                }

                try {
                    Unblock-File -LiteralPath $resolvedIlasScriptPath -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Warning "Could not unblock ILAS script (continuing): $($_.Exception.Message)"
                }

                $ilasOutDir = Join-Path $OutputDirectory ("_ilas_weekly_{0}" -f $runStamp)
                if (-not (Test-Path -LiteralPath $ilasOutDir)) {
                    New-Item -Path $ilasOutDir -ItemType Directory -Force | Out-Null
                }

                Write-Host "Running ILAS analysis for final UPSVF VisualID set..."
                & $resolvedIlasScriptPath `
                    -AquaExe $AquaExe `
                    -AquaServer $AquaServer `
                    -ProgramPattern $ProgramPattern `
                    -Operations $Operations `
                    -FunctionalBin $FunctionalBin `
                    -OutputDirectory $ilasOutDir `
                    -UpsvfReferenceCsv $tempMergedWorkFile

                $ilasSummaryPath = Get-ChildItem -LiteralPath $ilasOutDir -Filter "ILAS_Vmin_Summary_*.csv" -File |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
                if (-not $ilasSummaryPath) {
                    throw "ILAS summary output was not generated in $ilasOutDir"
                }

                $resolvedMergeScriptPath = Get-MergeScriptPath -ConfiguredPath $MergeScriptPath
                if (-not (Test-Path -LiteralPath $resolvedMergeScriptPath)) {
                    throw "Merge script not found: $resolvedMergeScriptPath"
                }

                & $resolvedMergeScriptPath `
                    -UpsvfCleanCsv $tempMergedWorkFile `
                    -IlasSummaryCsv $ilasSummaryPath `
                    -OutputCsv $csvPath
                Assert-NonEmptyFile -Path $csvPath -Label "Final merged UPSVF+ILAS CSV"

                $ilasStatus = "SUCCESS"
                $ilasMessage = "ILAS completed and merged successfully"
                Write-Host "ILAS merge completed successfully."
            }
            catch {
                $ilasMessage = $_.Exception.Message
                if (Test-IsIlasDataUnavailableMessage -Message $ilasMessage) {
                    $ilasStatus = "WAITING_FOR_DATA"
                    $ilasMessage = "ILAS data is not yet available for this run. Saved UPSVF-only CSV and will merge ILAS when data appears. Details: $ilasMessage"
                    Copy-Item -LiteralPath $tempMergedWorkFile -Destination $csvPath -Force
                    Assert-NonEmptyFile -Path $csvPath -Label "UPSVF-only CSV while waiting for ILAS data"
                    Write-Warning $ilasMessage
                }
                else {
                    $ilasStatus = "FAILED"
                    Write-Warning "ILAS step failed. Final UPSVF+ILAS CSV was not created. Details: $($ilasMessage)"
                }
            }
        }
        else {
            $ilasStatus = "SKIPPED"
            $ilasMessage = "UPSVF output missing required VisualID/lot structure; ILAS step was not started"
            Write-Warning $ilasMessage
        }
    }
    else {
        Write-Host "Finalizing CSV output..."
        Copy-Item -LiteralPath $tempMergedWorkFile -Destination $csvPath -Force
        Assert-NonEmptyFile -Path $csvPath -Label "Final CSV output"
        $ilasStatus = "SKIPPED"
        $ilasMessage = "ILAS step skipped by parameter"
    }

    # Remove transient working files after final outputs are confirmed.
    if ($pulledRawInThisRun) {
        Remove-Item -LiteralPath $tempRawFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $tempCleanFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempMergedWorkFile -Force -ErrorAction SilentlyContinue

    $statusCsvPath = Join-Path $OutputDirectory "Weekly_Run_Status.csv"

    Remove-ExpiredRunFiles -Directory $OutputDirectory -Cutoff $retentionCutoff
    Update-CsvLogRetention -CsvPath $statusCsvPath -Cutoff $retentionCutoff

    $statusEntry = [pscustomobject]@{
        RunTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        IsoWeek = ("WW{0:D2}-{1}" -f $isoWeek, $year)
        ProgramFilter = $ProgramPattern
        MostAbundantProgram = $mostAbundantProgram
        RowsBeforeClean = $rows.Count
        RowsAfterClean = $filteredRows.Count
        AquaSamplingCapRows = $AquaMaxRows
        VisualUnitsKept = $visualUnitCount
        VisualUnitsCap = $MaxVisualUnits
        CleanCsvPath = $cleanCsvPath
        FinalOutputCsvPath = $(if ($ilasStatus -eq "SUCCESS" -or $ilasStatus -eq "WAITING_FOR_DATA" -or $SkipIlasStep) { $csvPath } else { "" })
        Filters = ("exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits)
        RetentionDays = $RetentionDays
        IlasStatus = $ilasStatus
        IlasMessage = $ilasMessage
        IlasSummaryPath = $ilasSummaryPath
    }

    if (Test-Path -LiteralPath $statusCsvPath) {
        $statusEntry | Export-Csv -LiteralPath $statusCsvPath -Append -NoTypeInformation
    }
    else {
        $statusEntry | Export-Csv -LiteralPath $statusCsvPath -NoTypeInformation
    }

    if ($KeepCleanCsvArtifact -and -not [string]::IsNullOrWhiteSpace($cleanCsvPath)) {
        Write-Host "Clean CSV: $cleanCsvPath"
    }
    if ($ilasStatus -eq "SUCCESS" -or $ilasStatus -eq "WAITING_FOR_DATA" -or $SkipIlasStep) {
        Write-Host "Final CSV: $csvPath"
    }
    Write-Host "Status CSV: $statusCsvPath"
    Write-Host "Rows before: $($rows.Count)"
    Write-Host "Rows after:  $($filteredRows.Count)"
    Write-Host "AQUA sampling cap: $AquaMaxRows"
    Write-Host "Visual units kept: $visualUnitCount"
    Write-Host "Top program: $mostAbundantProgram"

    if (-not $SkipIlasStep -and $ilasStatus -eq "FAILED") {
        $runStatus = "FAILED"
        $runMessage = "Final UPSVF+ILAS CSV was not created. $ilasMessage"
        throw $runMessage
    }

    $runStatus = "SUCCESS"
    if ($ilasStatus -eq "WAITING_FOR_DATA") {
        $runMessage = "Run completed with UPSVF-only CSV; waiting for ILAS data availability"
    }
    else {
        $runMessage = "Run completed successfully"
    }
}
catch {
    $runStatus = "FAILED"
    $runMessage = $_.Exception.Message
    throw
}
finally {
    # Scoped cleanup: only remove this run's specific temp files by exact path.
    foreach ($path in @($tempRawFile, $tempCleanFile, $tempMergedWorkFile)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    $healthLogPath = Join-Path $OutputDirectory "Vmin_health.csv"
    Write-HealthLog `
        -HealthLogPath $healthLogPath `
        -RunStart $runStart `
        -Status $runStatus `
        -Message $runMessage `
        -RowsBefore $rowsBeforeCount `
        -RowsAfter $rowsAfterCount `
        -VisualUnits $visualUnitCount `
        -CleanCsvPath $cleanCsvPath `
        -JmpPath $csvPath
}
