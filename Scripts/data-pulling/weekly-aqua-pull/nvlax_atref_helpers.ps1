<#
.SYNOPSIS
Shared helpers for collapsing NVLAX SICC / CDYN "at ref" AQUA columns to one numeric value per unit.

.DESCRIPTION
AQUA returns tokens such as VA-NA-ATA01-CDYN_AT_REF, VA-NA-IAA0-SICC_TESTER_AT_REF and
VA-NA-IAA0-SICC_SYSTEM_AT_REF as '~' concatenated strings (one segment per core/instance), where all
segments are normally identical, e.g. "2.2818~2.2818~2.2818~2.2818".

Rule per cell:
- empty                       -> empty
- single numeric              -> value as-is
- all segments equal (1e-6)   -> the first segment (degenerate, no comment)
- segments differ / partially non-numeric -> the first numeric segment, flagged in AtRef_Parse_Comment
- no numeric segment          -> empty, flagged in AtRef_Parse_Comment

Dot-source this file (. .\nvlax_atref_helpers.ps1).
#>

$script:AtRefColumnRegex = '^VA-NA-(?<Domain>[A-Za-z0-9_]+)-(?<Measure>SICC_TESTER_AT_REF|SICC_SYSTEM_AT_REF|CDYN_AT_REF)(?<Suffix>_CLASSHOT)?$'
$script:LegacyAtRefColumnRegex = '^VA-NA-SUMMARY-RESULTS\[[A-Za-z0-9_]+::SICC_(SYSTEM|TESTER)_AT_REF\](_CLASSHOT)?$'
$script:AtRefCommentColumn = 'AtRef_Parse_Comment'

function Get-AtRefColumnNames {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Names)
    return @($Names | Where-Object { $_ -match $script:AtRefColumnRegex })
}

function Get-LegacyAtRefColumnNames {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Names)
    return @($Names | Where-Object { $_ -match $script:LegacyAtRefColumnRegex })
}

function Get-EmptyLegacyAtRefColumnNames {
    # Legacy VA-NA-SUMMARY-RESULTS[..::SICC_*_AT_REF] columns that carry no data in any row.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Names
    )

    $empty = New-Object System.Collections.Generic.List[string]
    foreach ($col in (Get-LegacyAtRefColumnNames -Names $Names)) {
        $hasData = $false
        foreach ($row in $Rows) {
            if (-not [string]::IsNullOrWhiteSpace([string]$row.$col)) { $hasData = $true; break }
        }
        if (-not $hasData) { $empty.Add($col) }
    }
    return @($empty)
}

function ConvertTo-SingleNumericValue {
    param([AllowNull()][AllowEmptyString()][string]$Text)

    $result = [pscustomobject]@{ Value = ''; Status = 'empty'; SegmentCount = 0 }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }

    $segments = @($Text.Split('~') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $result.SegmentCount = $segments.Count
    if ($segments.Count -eq 0) { return $result }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.NumberStyles]::Float
    $numbers = New-Object System.Collections.Generic.List[double]
    $firstText = $null
    $nonNumeric = 0

    foreach ($segment in $segments) {
        $parsed = 0.0
        if ([double]::TryParse($segment, $styles, $invariant, [ref]$parsed) -and
            -not [double]::IsNaN($parsed) -and -not [double]::IsInfinity($parsed)) {
            if ($null -eq $firstText) { $firstText = $segment }
            $numbers.Add($parsed)
        }
        else {
            $nonNumeric++
        }
    }

    if ($numbers.Count -eq 0) {
        $result.Status = 'non_numeric'
        return $result
    }

    $result.Value = $firstText
    if ($nonNumeric -gt 0) {
        $result.Status = 'partial_non_numeric'
        return $result
    }
    if ($numbers.Count -eq 1) {
        $result.Status = 'scalar'
        return $result
    }

    $reference = $numbers[0]
    $tolerance = [Math]::Max(1e-9, [Math]::Abs($reference) * 1e-6)
    $maxDiff = 0.0
    foreach ($n in $numbers) {
        $diff = [Math]::Abs($n - $reference)
        if ($diff -gt $maxDiff) { $maxDiff = $diff }
    }
    $result.Status = if ($maxDiff -le $tolerance) { 'collapsed' } else { 'mixed_segments' }
    return $result
}

function Convert-AtRefColumnsToSingleValue {
    # Collapses the given columns in place on every row and (re)writes the AtRef_Parse_Comment column.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Columns
    )

    $stats = [ordered]@{
        Columns = $Columns.Count; Rows = 0; Cells = 0; Empty = 0; Scalar = 0; Collapsed = 0
        MixedSegments = 0; PartialNonNumeric = 0; NonNumeric = 0; FlaggedRows = 0
    }

    foreach ($row in $Rows) {
        $stats.Rows++
        $flags = @{}

        foreach ($col in $Columns) {
            $prop = $row.PSObject.Properties[$col]
            if ($null -eq $prop) { continue }

            $conv = ConvertTo-SingleNumericValue -Text ([string]$prop.Value)
            $prop.Value = $conv.Value
            $stats.Cells++

            switch ($conv.Status) {
                'empty'               { $stats.Empty++ }
                'scalar'              { $stats.Scalar++ }
                'collapsed'           { $stats.Collapsed++ }
                'mixed_segments'      { $stats.MixedSegments++;     if (-not $flags.ContainsKey($_)) { $flags[$_] = New-Object System.Collections.Generic.List[string] }; $flags[$_].Add($col) }
                'partial_non_numeric' { $stats.PartialNonNumeric++; if (-not $flags.ContainsKey($_)) { $flags[$_] = New-Object System.Collections.Generic.List[string] }; $flags[$_].Add($col) }
                'non_numeric'         { $stats.NonNumeric++;        if (-not $flags.ContainsKey($_)) { $flags[$_] = New-Object System.Collections.Generic.List[string] }; $flags[$_].Add($col) }
            }
        }

        $comment = ''
        if ($flags.Count -gt 0) {
            $stats.FlaggedRows++
            $parts = foreach ($status in ($flags.Keys | Sort-Object)) {
                $note = if ($status -eq 'non_numeric') { 'left empty' } else { 'first value used' }
                "{0} ({1}): {2}" -f $status, $note, ($flags[$status] -join ', ')
            }
            $comment = $parts -join ' | '
        }

        $row | Add-Member -NotePropertyName $script:AtRefCommentColumn -NotePropertyValue $comment -Force
    }

    return [pscustomobject]$stats
}
