param(
    [string]$WeeklyRunsDir = "R:\Products\NVL\NVL-H\Weekly Runs",
    [string]$CurrentCsv = "",
    [string]$BaselineCsv = "",
    [string]$BaselineTpOverride = "",
    [string[]]$CorrelationLots = @("P630498CR", "P630506CR"),
    [string[]]$WtlLots = @("P631001WTY", "P6301270D", "P6301280D", "P6301290D", "P6301810RD", "Y6311230RD"),
    [string[]]$SiccColumns = @(
        "VA-IN-NA-GSDS_D_S::PP_SICCPU2_CLASSHOT_SA-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU2_CLASSHOT_SAHUB-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU2_CLASSHOT_SAAT-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU4_CLASSHOT_GT-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU5_CLASSHOT_IA00-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU5_CLASSHOT_IA01-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU5_CLASSHOT_AT00-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU5_CLASSHOT_CCF-V1_Value",
        "VA-IN-NA-GSDS_D_S::PP_SICCPU5_CLASSHOT_AT01-V1_Value"
    ),
    [int]$MaxBaselineFiles = 8,
    [int]$MinOverlap = 20,
    [string]$OutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CurrentCsvPath {
    param([string]$Dir, [string]$Configured)
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        if (-not (Test-Path -LiteralPath $Configured)) {
            throw "CurrentCsv not found: $Configured"
        }
        return $Configured
    }

    $latest = Get-ChildItem -LiteralPath $Dir -File -Filter "Vmin_*.csv" |
        Where-Object { $_.Name -notlike "*_clean.csv" -and $_.Name -notlike "*_health.csv" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "No Vmin_*.csv files found in $Dir"
    }

    return $latest.FullName
}

function Convert-ToDouble {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }

    $d = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }

    return $null
}

function Build-PerVisualAverage {
    param(
        [object[]]$Rows,
        [string]$Column,
        [string]$VisualIdColumn
    )

    $sum = @{}
    $count = @{}

    foreach ($r in $Rows) {
        $vid = [string]$r.$VisualIdColumn
        if ([string]::IsNullOrWhiteSpace($vid)) { continue }

        $v = Convert-ToDouble -Value $r.$Column
        if ($null -eq $v) { continue }

        if (-not $sum.ContainsKey($vid)) {
            $sum[$vid] = 0.0
            $count[$vid] = 0
        }

        $sum[$vid] += $v
        $count[$vid] += 1
    }

    $avg = @{}
    foreach ($k in $sum.Keys) {
        if ($count[$k] -gt 0) {
            $avg[$k] = $sum[$k] / $count[$k]
        }
    }

    return $avg
}

function Get-PreviousOfficialTp {
    param([string]$CurrentTp)

    # Expected style: NVLHM66B0H31B00S630 -> previous letter B -> A
    $m = [regex]::Match($CurrentTp, '^(?<prefix>.*?)(?<letter>[A-Z])00(?<suffix>S\d+)?$')
    if (-not $m.Success) { return $null }

    $letter = $m.Groups['letter'].Value
    $code = [int][char]$letter
    if ($code -le [int][char]'A') { return $null }

    $prevLetter = [char]($code - 1)
    $prefix = $m.Groups['prefix'].Value
    $suffix = $m.Groups['suffix'].Value

    return "{0}{1}00{2}" -f $prefix, $prevLetter, $suffix
}

function Find-BaselineRows {
    param(
        [string]$Dir,
        [string]$ExcludeCsv,
        [string]$VisualIdColumn,
        [string]$ProgramColumn,
        [System.Collections.Generic.HashSet[string]]$CorrVisualSet,
        [string]$BaselineTp,
        [int]$MaxFiles
    )

    $files = Get-ChildItem -LiteralPath $Dir -File -Filter "Vmin_*.csv" |
        Where-Object {
            $_.FullName -ne $ExcludeCsv -and
            $_.Name -notlike "*_clean.csv" -and
            $_.Name -notlike "*_health.csv"
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $MaxFiles

    $baselineRows = New-Object System.Collections.Generic.List[object]

    foreach ($f in $files) {
        Write-Host "Scanning baseline candidate file: $($f.Name)"
        $rows = Import-Csv -LiteralPath $f.FullName
        foreach ($r in $rows) {
            $vid = [string]$r.$VisualIdColumn
            if ([string]::IsNullOrWhiteSpace($vid)) { continue }
            if (-not $CorrVisualSet.Contains($vid)) { continue }

            $tp = [string]$r.$ProgramColumn
            if ([string]::IsNullOrWhiteSpace($tp)) { continue }

            if ($tp -eq $BaselineTp) {
                $baselineRows.Add($r)
            }
        }

        if ($baselineRows.Count -gt 0) {
            # Keep scanning more files to improve overlap, but stop when large enough.
            $foundVisuals = @($baselineRows | Select-Object -ExpandProperty $VisualIdColumn -Unique).Count
            if ($foundVisuals -ge [Math]::Max(50, [int]($CorrVisualSet.Count * 0.7))) {
                break
            }
        }
    }

    return @($baselineRows)
}

function New-TableRowsHtml {
    param([object[]]$Rows, [string[]]$Columns)

    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $Rows) {
        [void]$sb.Append('<tr>')
        foreach ($c in $Columns) {
            $v = $r.$c
            [void]$sb.Append("<td>$v</td>")
        }
        [void]$sb.Append('</tr>')
    }

    return $sb.ToString()
}

$currentCsvPath = Get-CurrentCsvPath -Dir $WeeklyRunsDir -Configured $CurrentCsv
Write-Host "Current CSV: $currentCsvPath"

$currentRows = @(Import-Csv -LiteralPath $currentCsvPath)
if ($currentRows.Count -eq 0) { throw "Current CSV has no rows: $currentCsvPath" }

$cols = $currentRows[0].PSObject.Properties.Name
$visualCol = "VISUAL_ID"
$lotCol = "LOTFROMFS"
$programCol = "Program Name_CLASSHOT"
$vpoCol = "DevRevStep_CLASSHOT"

foreach ($required in @($visualCol, $lotCol, $programCol)) {
    if (-not ($cols -contains $required)) {
        throw "Required column '$required' is missing in current CSV"
    }
}

$corrSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$CorrelationLots | ForEach-Object { [void]$corrSet.Add($_) }
$wtlSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$WtlLots | ForEach-Object { [void]$wtlSet.Add($_) }
$allLotSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$CorrelationLots + $WtlLots | ForEach-Object { [void]$allLotSet.Add($_) }

$focusRows = @($currentRows | Where-Object { $allLotSet.Contains([string]$_.$lotCol) })
$corrRows = @($focusRows | Where-Object { $corrSet.Contains([string]$_.$lotCol) })
$wtlRows = @($focusRows | Where-Object { $wtlSet.Contains([string]$_.$lotCol) })

if ($corrRows.Count -eq 0) {
    throw "No rows found for correlation lots in current CSV"
}

$currentTp = ($corrRows | Group-Object $programCol | Sort-Object Count -Descending | Select-Object -First 1).Name
$baselineTp = if (-not [string]::IsNullOrWhiteSpace($BaselineTpOverride)) { $BaselineTpOverride } else { Get-PreviousOfficialTp -CurrentTp $currentTp }

if ([string]::IsNullOrWhiteSpace($baselineTp)) {
    throw "Could not infer previous official TP from current TP '$currentTp'. Please provide manual baseline TP logic."
}

$corrVisualSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
($corrRows | Select-Object -ExpandProperty $visualCol -Unique) | ForEach-Object { [void]$corrVisualSet.Add($_) }

$baselineRows = @()
if (-not [string]::IsNullOrWhiteSpace($BaselineCsv)) {
    if (-not (Test-Path -LiteralPath $BaselineCsv)) {
        throw "BaselineCsv not found: $BaselineCsv"
    }

    Write-Host "Using explicit baseline CSV: $BaselineCsv"
    $candidate = @(Import-Csv -LiteralPath $BaselineCsv)
    $baselineRows = @($candidate | Where-Object {
        $corrVisualSet.Contains([string]$_.$visualCol) -and
        ([string]$_.$programCol -eq $baselineTp)
    })
}
else {
    $baselineRows = Find-BaselineRows -Dir $WeeklyRunsDir -ExcludeCsv $currentCsvPath -VisualIdColumn $visualCol -ProgramColumn $programCol -CorrVisualSet $corrVisualSet -BaselineTp $baselineTp -MaxFiles $MaxBaselineFiles
}
$baselineCorrRows = @($baselineRows | Where-Object { $corrVisualSet.Contains([string]$_.$visualCol) })

if ($baselineCorrRows.Count -eq 0) {
    throw "No baseline rows found for previous TP '$baselineTp' using correlation visual IDs."
}

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent $PSCommandPath) "..\artifacts"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$outDir = Join-Path $OutputRoot ("tp_release_{0}" -f $runStamp)
New-Item -Path $outDir -ItemType Directory -Force | Out-Null

# ---------- Vmin analysis ----------
$vminCols = @($cols | Where-Object { $_ -like "ILAS_*_Vmin" })
$vminResults = New-Object System.Collections.Generic.List[object]

foreach ($c in $vminCols) {
    $newAvg = Build-PerVisualAverage -Rows $corrRows -Column $c -VisualIdColumn $visualCol
    $oldAvg = Build-PerVisualAverage -Rows $baselineCorrRows -Column $c -VisualIdColumn $visualCol

    $common = @($newAvg.Keys | Where-Object { $oldAvg.ContainsKey($_) })
    if ($common.Count -lt $MinOverlap) { continue }

    $deltas = New-Object System.Collections.Generic.List[double]
    foreach ($vid in $common) {
        $deltas.Add($newAvg[$vid] - $oldAvg[$vid])
    }

    $meanDelta = ($deltas | Measure-Object -Average).Average
    $maxAbsMv = ($deltas | ForEach-Object { [Math]::Abs($_ * 1000.0) } | Measure-Object -Maximum).Maximum
    $outlierCount = @($deltas | Where-Object { [Math]::Abs($_ * 1000.0) -gt 30.0 }).Count

    $vminResults.Add([pscustomobject]@{
        MetricColumn = $c
        OverlapVisuals = $common.Count
        MeanDelta_mV = [Math]::Round(($meanDelta * 1000.0), 3)
        MaxAbsDelta_mV = [Math]::Round($maxAbsMv, 3)
        OutlierCount_gt30mV = $outlierCount
        ShiftGate = if ([Math]::Abs($meanDelta * 1000.0) -le 2.0) { "PASS" } else { "FAIL" }
    })
}

# ---------- SICC analysis ----------
$siccResults = New-Object System.Collections.Generic.List[object]
foreach ($c in $SiccColumns) {
    if (-not ($cols -contains $c)) { continue }

    $newAvg = Build-PerVisualAverage -Rows $corrRows -Column $c -VisualIdColumn $visualCol
    $oldAvg = Build-PerVisualAverage -Rows $baselineCorrRows -Column $c -VisualIdColumn $visualCol
    $common = @($newAvg.Keys | Where-Object { $oldAvg.ContainsKey($_) -and [Math]::Abs($oldAvg[$_]) -gt 1e-9 })
    if ($common.Count -lt $MinOverlap) { continue }

    $pctDeltas = New-Object System.Collections.Generic.List[double]
    foreach ($vid in $common) {
        $pctDeltas.Add((($newAvg[$vid] - $oldAvg[$vid]) / $oldAvg[$vid]) * 100.0)
    }

    $meanAbsPct = ($pctDeltas | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Average).Average
    $outlierCount = @($pctDeltas | Where-Object { [Math]::Abs($_) -gt 10.0 }).Count

    $siccResults.Add([pscustomobject]@{
        MetricColumn = $c
        OverlapVisuals = $common.Count
        MeanAbsShift_pct = [Math]::Round($meanAbsPct, 4)
        OutlierCount_gt10pct = $outlierCount
        ShiftGate = if ($meanAbsPct -le 0.2) { "PASS" } else { "FAIL" }
    })
}

# ---------- DTS and limiter evidence ----------
$dtsCols = @($cols | Where-Object { $_ -like "ILAS_*_MaxDTS_C" })
$lpCols = @($cols | Where-Object { $_ -like "ILAS_*_LP" })

$dtsResults = New-Object System.Collections.Generic.List[object]
foreach ($c in $dtsCols) {
    $newAvg = Build-PerVisualAverage -Rows $corrRows -Column $c -VisualIdColumn $visualCol
    $oldAvg = Build-PerVisualAverage -Rows $baselineCorrRows -Column $c -VisualIdColumn $visualCol
    $common = @($newAvg.Keys | Where-Object { $oldAvg.ContainsKey($_) })
    if ($common.Count -lt $MinOverlap) { continue }
    $deltas = @($common | ForEach-Object { $newAvg[$_] - $oldAvg[$_] })
    $meanDelta = ($deltas | Measure-Object -Average).Average
    $dtsResults.Add([pscustomobject]@{
        MetricColumn = $c
        OverlapVisuals = $common.Count
        MeanDelta_C = [Math]::Round($meanDelta, 4)
    })
}

$lpResults = New-Object System.Collections.Generic.List[object]
foreach ($c in $lpCols) {
    $newMap = @{}
    foreach ($r in $corrRows) {
        $vid = [string]$r.$visualCol
        if ([string]::IsNullOrWhiteSpace($vid)) { continue }
        $newMap[$vid] = [string]$r.$c
    }

    $oldMap = @{}
    foreach ($r in $baselineCorrRows) {
        $vid = [string]$r.$visualCol
        if ([string]::IsNullOrWhiteSpace($vid)) { continue }
        $oldMap[$vid] = [string]$r.$c
    }

    $common = @($newMap.Keys | Where-Object { $oldMap.ContainsKey($_) })
    if ($common.Count -lt $MinOverlap) { continue }

    $changes = 0
    foreach ($vid in $common) {
        if (($newMap[$vid] -ne $oldMap[$vid]) -and -not ([string]::IsNullOrWhiteSpace($newMap[$vid]) -and [string]::IsNullOrWhiteSpace($oldMap[$vid]))) {
            $changes++
        }
    }

    $rate = if ($common.Count -gt 0) { ($changes * 100.0) / $common.Count } else { 0.0 }
    $lpResults.Add([pscustomobject]@{
        MetricColumn = $c
        OverlapVisuals = $common.Count
        ChangedPatternCount = $changes
        ChangedPatternRate_pct = [Math]::Round($rate, 3)
    })
}

$vminFails = @($vminResults | Where-Object { $_.ShiftGate -eq "FAIL" }).Count
$siccFails = @($siccResults | Where-Object { $_.ShiftGate -eq "FAIL" }).Count
$overall = if (($vminFails + $siccFails) -eq 0) { "APPROVED" } else { "ADDITIONAL_DATA_REQUIRED" }

$summary = [ordered]@{
    run_timestamp = (Get-Date).ToString("s")
    weekly_runs_dir = $WeeklyRunsDir
    current_csv = $currentCsvPath
    current_tp = $currentTp
    baseline_tp = $baselineTp
    correlation_lots = $CorrelationLots
    wtl_lots = $WtlLots
    matched_focus_rows = $focusRows.Count
    correlation_rows = $corrRows.Count
    wtl_rows = $wtlRows.Count
    correlation_visual_count = $corrVisualSet.Count
    baseline_corr_rows = $baselineCorrRows.Count
    vpo_distribution = @($focusRows | Group-Object $vpoCol | Sort-Object Count -Descending | Select-Object Count,Name)
    decision = $overall
    vmin_fail_count = $vminFails
    sicc_fail_count = $siccFails
}

$summaryJson = Join-Path $outDir "approval_summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

$vminCsv = Join-Path $outDir "vmin_shift_table.csv"
$siccCsv = Join-Path $outDir "sicc_shift_table.csv"
$dtsCsv = Join-Path $outDir "dts_shift_table.csv"
$lpCsv = Join-Path $outDir "limiter_change_table.csv"

$vminResults | Sort-Object {[Math]::Abs($_.MeanDelta_mV)} -Descending | Export-Csv -LiteralPath $vminCsv -NoTypeInformation
$siccResults | Sort-Object MeanAbsShift_pct -Descending | Export-Csv -LiteralPath $siccCsv -NoTypeInformation
$dtsResults | Sort-Object {[Math]::Abs($_.MeanDelta_C)} -Descending | Export-Csv -LiteralPath $dtsCsv -NoTypeInformation
$lpResults | Sort-Object ChangedPatternRate_pct -Descending | Export-Csv -LiteralPath $lpCsv -NoTypeInformation

$vminTop = @($vminResults | Sort-Object {[Math]::Abs($_.MeanDelta_mV)} -Descending | Select-Object -First 20)
$siccTop = @($siccResults | Sort-Object MeanAbsShift_pct -Descending | Select-Object -First 20)
$dtsTop = @($dtsResults | Sort-Object {[Math]::Abs($_.MeanDelta_C)} -Descending | Select-Object -First 20)
$lpTop = @($lpResults | Sort-Object ChangedPatternRate_pct -Descending | Select-Object -First 20)
$vpoTop = @($summary.vpo_distribution | Select-Object -First 10)

$decisionColor = if ($overall -eq "APPROVED") { "#137333" } else { "#b3261e" }

$html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<title>TP Release Approval Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; }
h1 { margin-bottom: 4px; }
.small { color: #6b7280; font-size: 12px; }
.card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 14px; margin: 12px 0; }
.badge { display: inline-block; padding: 4px 10px; border-radius: 999px; font-weight: 600; color: white; background: $decisionColor; }
table { border-collapse: collapse; width: 100%; font-size: 12px; }
th, td { border: 1px solid #e5e7eb; padding: 6px; text-align: left; }
th { background: #f9fafb; }
</style>
</head>
<body>
  <h1>NVLH TP Release Approval Report</h1>
  <div class="small">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</div>

  <div class="card">
    <div><strong>Decision:</strong> <span class="badge">$overall</span></div>
    <div><strong>Current TP:</strong> $currentTp</div>
    <div><strong>Baseline TP (previous official):</strong> $baselineTp</div>
    <div><strong>Correlation lots:</strong> $($CorrelationLots -join ', ')</div>
    <div><strong>WTL lots:</strong> $($WtlLots -join ', ')</div>
    <div><strong>Rows in focus cohort:</strong> $($focusRows.Count)</div>
    <div><strong>Correlation visuals:</strong> $($corrVisualSet.Count)</div>
    <div><strong>Baseline matched rows:</strong> $($baselineCorrRows.Count)</div>
  </div>

  <div class="card">
    <h3>Relevant VPO / Step Signatures</h3>
    <table>
      <thead><tr><th>Count</th><th>DevRevStep_CLASSHOT</th></tr></thead>
      <tbody>
      $(New-TableRowsHtml -Rows $vpoTop -Columns @('Count','Name'))
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3>Vmin Shift (Correlation vs Previous TP)</h3>
    <table>
      <thead><tr><th>MetricColumn</th><th>OverlapVisuals</th><th>MeanDelta_mV</th><th>MaxAbsDelta_mV</th><th>OutlierCount_gt30mV</th><th>ShiftGate</th></tr></thead>
      <tbody>
      $(New-TableRowsHtml -Rows $vminTop -Columns @('MetricColumn','OverlapVisuals','MeanDelta_mV','MaxAbsDelta_mV','OutlierCount_gt30mV','ShiftGate'))
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3>SICC Shift (Correlation vs Previous TP)</h3>
    <table>
      <thead><tr><th>MetricColumn</th><th>OverlapVisuals</th><th>MeanAbsShift_pct</th><th>OutlierCount_gt10pct</th><th>ShiftGate</th></tr></thead>
      <tbody>
      $(New-TableRowsHtml -Rows $siccTop -Columns @('MetricColumn','OverlapVisuals','MeanAbsShift_pct','OutlierCount_gt10pct','ShiftGate'))
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3>DTS Shift Evidence</h3>
    <table>
      <thead><tr><th>MetricColumn</th><th>OverlapVisuals</th><th>MeanDelta_C</th></tr></thead>
      <tbody>
      $(New-TableRowsHtml -Rows $dtsTop -Columns @('MetricColumn','OverlapVisuals','MeanDelta_C'))
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3>Limiter Pattern Change Evidence</h3>
    <table>
      <thead><tr><th>MetricColumn</th><th>OverlapVisuals</th><th>ChangedPatternCount</th><th>ChangedPatternRate_pct</th></tr></thead>
      <tbody>
      $(New-TableRowsHtml -Rows $lpTop -Columns @('MetricColumn','OverlapVisuals','ChangedPatternCount','ChangedPatternRate_pct'))
      </tbody>
    </table>
  </div>

  <div class="small">
    Output files: approval_summary.json, vmin_shift_table.csv, sicc_shift_table.csv, dts_shift_table.csv, limiter_change_table.csv
  </div>
</body>
</html>
"@

$htmlPath = Join-Path $outDir "tp_release_approval_report.html"
$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8

Write-Host "Generated report directory: $outDir"
Write-Host "HTML report: $htmlPath"
Write-Host "Summary JSON: $summaryJson"
