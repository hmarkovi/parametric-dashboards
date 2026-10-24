#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TemplatePath = "R:\Products\NVL\Presentation template.pptx",
    [string]$OutputDir = "R:\Products\NVL\NVL-H\Weekly Runs\proposals",
    [string]$OutputName = ("NVLH_Grand_Scheme_Proposal_{0}.pptx" -f (Get-Date -Format 'yyyyMMdd'))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-TextBox {
    param(
        $Slide,
        [string]$Text,
        [single]$Left,
        [single]$Top,
        [single]$Width,
        [single]$Height,
        [int]$FontSize = 18,
        [bool]$Bold = $false
    )

    $shape = $Slide.Shapes.AddTextbox(1, $Left, $Top, $Width, $Height)
    $shape.TextFrame.WordWrap = -1
    $shape.TextFrame.AutoSize = 0
    $shape.TextFrame.MarginLeft = 6
    $shape.TextFrame.MarginRight = 6
    $shape.TextFrame.MarginTop = 4
    $shape.TextFrame.MarginBottom = 4
    $range = $shape.TextFrame.TextRange
    $range.Text = $Text
    $range.Font.Size = $FontSize
    $range.Font.Bold = [int]$Bold
    $range.Font.Color.RGB = 20 + 256 * 20 + 65536 * 20
    return $shape
}

function Add-StepBox {
    param(
        $Slide,
        [string]$Title,
        [string]$Body,
        [single]$Left,
        [single]$Top,
        [single]$Width,
        [single]$Height,
        [int]$R,
        [int]$G,
        [int]$B
    )

    $box = $Slide.Shapes.AddShape(1, $Left, $Top, $Width, $Height)
    $box.Fill.Visible = -1
    $box.Fill.ForeColor.RGB = $R + 256 * $G + 65536 * $B
    $box.Line.ForeColor.RGB = 60 + 256 * 60 + 65536 * 60
    $box.Line.Weight = 1.5
    $box.TextFrame.WordWrap = -1
    $box.TextFrame.AutoSize = 0
    $box.TextFrame.MarginLeft = 6
    $box.TextFrame.MarginRight = 6
    $box.TextFrame.MarginTop = 4
    $box.TextFrame.MarginBottom = 4

    $txt = $box.TextFrame.TextRange
    $txt.Text = "$Title`r`n$Body"
    $txt.Font.Size = 10
    $txt.Font.Color.RGB = 20 + 256 * 20 + 65536 * 20
    $txt.ParagraphFormat.SpaceAfter = 4

    # Make first line bolder for title clarity.
    $firstLine = $txt.Paragraphs(1)
    $firstLine.Font.Bold = -1
    $firstLine.Font.Size = 12
    $firstLine.Font.Color.RGB = 20 + 256 * 20 + 65536 * 20

    return $box
}

function Add-Arrow {
    param(
        $Slide,
        [single]$Left,
        [single]$Top,
        [single]$Width,
        [single]$Height
    )

    $arr = $Slide.Shapes.AddShape(33, $Left, $Top, $Width, $Height)
    $arr.Fill.ForeColor.RGB = 90 + 256 * 90 + 65536 * 90
    $arr.Line.Visible = 0
    return $arr
}

if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template not found: $TemplatePath"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$outputPath = Join-Path $OutputDir $OutputName

$pp = $null
$pres = $null

try {
    $pp = New-Object -ComObject PowerPoint.Application
    $pp.Visible = -1

    $pres = $pp.Presentations.Open($TemplatePath, $false, $false, $false)

    # Slide 1 - general aim
    $s1 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s1 -Text 'NVL-H Unified Data and Analysis Infrastructure Proposal' -Left 40 -Top 22 -Width 1220 -Height 56 -FontSize 34 -Bold $true)

    $aim = @(
        'General Aim',
        '',
        'Create a robust, minimal-retention, analysis-focused flow where AQUA remains the system of record, while NVL-H teams get daily insights organized by test program instead of noisy single-day views.',
        '',
        'Core principles:',
        '- Pull UPSVF + ILAS daily and merge consistently.',
        '- Publish test-program analysis windows to avoid day bias.',
        '- Preserve full data only for phases needed for BinSplit model decisions and LIRA review.',
        '- For later phases, keep raw data for 10 days, then keep only metadata plus published analysis history.'
    ) -join "`r`n"
    [void](Add-TextBox -Slide $s1 -Text $aim -Left 60 -Top 110 -Width 1180 -Height 560 -FontSize 20)

    # Slide 2 - architecture with linear arrows and boxes
    $s2 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s2 -Text 'Finalized Architecture (Linear Flow)' -Left 40 -Top 18 -Width 1200 -Height 44 -FontSize 30 -Bold $true)

    $topY = 64
    $boxW = 230
    $boxH = 332
    $gap = 20

    $b1 = Add-StepBox -Slide $s2 -Title '1) Daily Pull' -Body @(
        'Data needed:',
        'UPSVF raw + ILAS raw',
        'program/date filters',
        '',
        'Scripts/helpers:',
        'UPS Parametric data pull script',
        'AQUA command helper',
        'task scheduling helper',
        'run health check + retry logic',
        '',
        'Retention:',
        'keep raw data in recent-run storage',
        '',
        'Final outcome (success):',
        'daily pull completes on time,',
        'raw files are present and readable,',
        'run status is recorded'
    ) -join "`r`n" -Left 40 -Top $topY -Width $boxW -Height $boxH -R 240 -G 248 -B 255

    Add-Arrow -Slide $s2 -Left (40 + $boxW + 3) -Top ($topY + 150) -Width $gap -Height 28 | Out-Null

    $b2Left = 40 + $boxW + $gap + 6
    $b2 = Add-StepBox -Slide $s2 -Title '2) Curate + Merge' -Body @(
        'Data needed:',
        'VISUAL_ID, LOTFROMFS, and test-program details',
        'ILAS_* signals',
        '',
        'Scripts/helpers:',
        'ILAS data pull script',
        'data merge script',
        'schema check + naming map',
        'visual ID and lot matching logic',
        '',
        'Retention:',
        'keep merged daily artifact',
        '',
        'Final outcome (success):',
        'merged output is created,',
        'schema checks pass,',
        'no silent row loss'
    ) -join "`r`n" -Left $b2Left -Top $topY -Width $boxW -Height $boxH -R 236 -G 255 -B 239

    Add-Arrow -Slide $s2 -Left ($b2Left + $boxW + 3) -Top ($topY + 150) -Width $gap -Height 28 | Out-Null

    $b3Left = $b2Left + $boxW + $gap + 6
    $b3 = Add-StepBox -Slide $s2 -Title '3) Program Analytics' -Body @(
        'Data needed:',
        'daily merged data + program window',
        '',
        'Scripts/helpers:',
        'Vmin analysis script',
        'parametric summary script',
        'correlation analysis job',
        'shift analysis job',
        'email report generator',
        '',
        'Retention:',
        'keep published program reports',
        '',
        'Final outcome (success):',
        'all 6 analysis streams are published,',
        'program-window metrics are generated,',
        'daily summary email is sent'
    ) -join "`r`n" -Left $b3Left -Top $topY -Width $boxW -Height $boxH -R 255 -G 248 -B 232

    Add-Arrow -Slide $s2 -Left ($b3Left + $boxW + 3) -Top ($topY + 150) -Width $gap -Height 28 | Out-Null

    $b4Left = $b3Left + $boxW + $gap + 6
    $b4 = Add-StepBox -Slide $s2 -Title '4) Retain + Prune' -Body @(
        'Data needed:',
        'test-program lifecycle policy',
        'LIRA checkpoint marker',
        '',
        'Scripts/helpers:',
        'retention policy checker',
        'manifest and history writer',
        'index generator',
        'cleanup job for old files',
        '',
        'Retention:',
        'Before LIRA: keep full data',
        'After LIRA: 10 days raw then metadata only',
        '',
        'Final outcome (success):',
        'retention policy is enforced daily,',
        'audit history remains complete,',
        'storage stays within target'
    ) -join "`r`n" -Left $b4Left -Top $topY -Width $boxW -Height $boxH -R 255 -G 236 -B 236

    [void](Add-TextBox -Slide $s2 -Text 'End-to-end success criteria for the full architecture: daily pull reliability >= 99%, validated merged output every day, all six analysis streams published, full traceability by request ID, and automatic retention enforcement with zero policy violations.' -Left 48 -Top 414 -Width 1180 -Height 102 -FontSize 14)

    # Slide 3 - execution flow details
    $s3 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s3 -Text 'Execution Flow (Daily + Program-Based Publishing)' -Left 40 -Top 18 -Width 1220 -Height 44 -FontSize 30 -Bold $true)

    $flowText = @(
        'Execution sequence:',
        '1. Pull UPSVF + ILAS daily from AQUA using stable report paths and filters.',
        '2. Validate schema, merge on visual ID and lot, and calculate ILAS coverage metrics.',
        '3. Partition by test program and compute daily key metrics.',
        '4. Build 7-day and 10-day program windows to remove single-day bias and lot spikes.',
        '5. Publish the test-program analysis package (CSV + summary + PPT-ready snippets).',
        '6. Run correlation, lot-shift, and test-program-shift jobs; send the notification email.',
        '7. Apply retention policy: before LIRA keep full data; after LIRA keep raw data for 10 days only.',
        '8. Persist manifests and history logs for full traceability and rerun reproducibility.',
        '',
        'Control points:',
        '- If ILAS data is not available yet, the run still continues with UPSVF-only output when needed.',
        '- Every run writes row counts, unique VID counts, ILAS coverage, and policy decision.',
        '- Re-runs are idempotent by request ID and test-program plus date partition keys.'
    ) -join "`r`n"
    [void](Add-TextBox -Slide $s3 -Text $flowText -Left 55 -Top 90 -Width 1200 -Height 620 -FontSize 17)

    # Slide 4 - advantages
    $s4 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s4 -Text 'Advantages of the Proposed Scheme' -Left 40 -Top 18 -Width 1220 -Height 44 -FontSize 30 -Bold $true)

    $adv = @(
        '1) Minimum data retention with maximum traceability',
        '   - Avoids maintaining a second full historical database while preserving lineage manifests.',
        '',
        '2) Protects BinSplit model and LIRA review evidence',
        '   - Full raw, clean, and merged retention for the lifecycle stages that matter.',
        '',
        '3) Better signal quality through program-window publishing',
        '   - Reduces day-level and lot-level bias in decisions.',
        '',
        '4) Faster decisions from automated daily analytics',
        '   - Test-program release approval, PreSi/PostSi, and thermal compliance stay visible every day.',
        '',
        '5) Controlled storage growth after the LIRA checkpoint',
        '   - 10-day recent-run storage, then metadata-only mode for non-critical tails.',
        '',
        '6) Scalable operations',
        '   - New test programs can be onboarded by policy updates, not code rewrites.'
    ) -join "`r`n"
    [void](Add-TextBox -Slide $s4 -Text $adv -Left 60 -Top 94 -Width 1180 -Height 620 -FontSize 18)

    # Slide 5 - next steps detailed table
    $s5 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s5 -Text 'Detailed Next Steps and Ownership' -Left 40 -Top 18 -Width 1220 -Height 44 -FontSize 30 -Bold $true)

    $shape = $s5.Shapes.AddTable(9, 6, 24, 88, 1230, 595)
    $tbl = $shape.Table

    $headers = @('Step', 'Action', 'Needed Data/Config', 'Output', 'Owner', 'Target')
    for ($c = 1; $c -le $headers.Count; $c++) {
        $tbl.Cell(1, $c).Shape.TextFrame.TextRange.Text = $headers[$c - 1]
        $tbl.Cell(1, $c).Shape.TextFrame.TextRange.Font.Bold = -1
        $tbl.Cell(1, $c).Shape.TextFrame.TextRange.Font.Color.RGB = 15 + 256 * 15 + 65536 * 15
        $tbl.Cell(1, $c).Shape.Fill.ForeColor.RGB = 225 + 256 * 235 + 65536 * 248
    }

    $rows = @(
        @('1', 'Define test-program lifecycle policy', 'LIRA list, post-LIRA tags, 10-day TTL', 'policy.json', 'Data + Product', 'Week 1'),
        @('2', 'Harden daily pull orchestration', 'AQUA paths, timeout, retry, health checks', 'stable daily merged output', 'Automation', 'Week 1'),
        @('3', 'Manifest and history logging', 'request ID schema, status fields, run metrics', 'run_manifest.csv/jsonl', 'Data Eng', 'Week 1'),
        @('4', 'Program-window analytics', 'test-program partitions, 7-day and 10-day windows', 'test-program KPI tables', 'Analytics', 'Week 2'),
        @('5', 'Correlation + lot/shift jobs', 'historical program windows, thresholds', 'daily shift report', 'Analytics', 'Week 2'),
        @('6', 'Email publisher', 'distribution list, severity rules', 'auto daily digest', 'Automation', 'Week 2'),
        @('7', 'Retention enforcer', 'policy.json + manifest', 'raw cleanup + audit logs', 'Data Eng', 'Week 3'),
        @('8', 'Governance review', 'all six analysis outputs KPIs', 'approval to production', 'Leadership', 'Week 4')
    )

    for ($r = 0; $r -lt $rows.Count; $r++) {
        for ($c = 0; $c -lt $rows[$r].Count; $c++) {
            $tbl.Cell($r + 2, $c + 1).Shape.TextFrame.TextRange.Text = [string]$rows[$r][$c]
            $tbl.Cell($r + 2, $c + 1).Shape.TextFrame.TextRange.Font.Size = 11
            $tbl.Cell($r + 2, $c + 1).Shape.TextFrame.TextRange.Font.Color.RGB = 20 + 256 * 20 + 65536 * 20
        }
    }

    # Slide 6 - analysis catalog
    $s6 = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    [void](Add-TextBox -Slide $s6 -Text 'Analysis Catalog Derived from the Data Flow' -Left 40 -Top 18 -Width 1220 -Height 44 -FontSize 30 -Bold $true)

    $catalog = @(
        'The following analysis streams are produced from the unified UPSVF + ILAS pipeline:',
        '',
        '1. TP release approval',
        '2. Parametric results week-to-week follow up',
        '3. PreSi to PostSi matching',
        '4. Parametric areas where improvement is required, prioritized by BinSplit model impact',
        '5. Test time reduction relevant analysis',
        '6. Thermal compliance',
        '',
        'Recommendation: treat these six streams as mandatory release gates in the test-program dashboard.'
    ) -join "`r`n"

    [void](Add-TextBox -Slide $s6 -Text $catalog -Left 70 -Top 105 -Width 1140 -Height 530 -FontSize 22)

    try {
        $pres.SaveAs($outputPath)
    }
    catch {
        $fallback = Join-Path $OutputDir ("NVLH_Grand_Scheme_Proposal_{0}.pptx" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Write-Warning "Primary output path was busy. Saving to $fallback"
        $outputPath = $fallback
        $pres.SaveAs($outputPath)
    }

    Write-Host "Generated PPT: $outputPath"
}
finally {
    if ($pres) {
        try { $pres.Close() } catch {}
    }
    if ($pp) {
        try { $pp.Quit() } catch {}
    }
}
