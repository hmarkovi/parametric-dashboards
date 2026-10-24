[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot,

    [Parameter()]
    [ValidateSet('DryRun','Execute')]
    [string]$Mode = 'DryRun',

    [Parameter()]
    [int]$OlderThanDays = 2,

    [Parameter()]
    [switch]$SkipTrackedFiles = $true,

    [Parameter()]
    [string[]]$TargetRelativeRoots = @(
        'development/validation',
        'Scripts/parametric-analysis/correlations/output',
        'backups'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $baseUri = [Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\\') + '\\')
    $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
}

function Normalize-RelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace '\\','/').TrimStart('./')
}

function Get-GitTrackedSet {
    param([Parameter(Mandatory = $true)][string]$Root)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $set
    }

    $gitDir = Join-Path $Root '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        return $set
    }

    $tracked = git -C $Root ls-files
    foreach ($line in $tracked) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        [void]$set.Add((Normalize-RelativePath -Path $line))
    }
    return $set
}

function Test-IsProtectedPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $p = Normalize-RelativePath -Path $RelativePath
    $protected = @(
        '.git/*',
        '.github/skills/*',
        'Scripts/data-pulling/*',
        'Scripts/parametric-analysis/ilas/*',
        '*.ps1',
        '*.py',
        '*.ipynb',
        '*.md',
        '*.skill.md'
    )

    foreach ($pattern in $protected) {
        if ($p -like $pattern) {
            return $true
        }
    }
    return $false
}

function Test-IsDisposableFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][datetime]$Cutoff
    )

    if ($File.LastWriteTime -gt $Cutoff) {
        return $false
    }

    $ext = $File.Extension.ToLowerInvariant()
    $baseName = $File.BaseName
    $namePattern = '(?i)(^~\$|_raw$|_clean$|_merged_work$|_tmp$|temp|backup|old|copy|debug|draft|screenshot|snip|capture|\(\d+\)$)'

    if ($ext -in @('.tmp','.bak')) {
        return $true
    }

    if ($ext -in @('.png','.jpg','.jpeg','.gif','.webp')) {
        return ($baseName -match '(?i)(screenshot|screen shot|snip|capture|image \(\d+\))')
    }

    if ($ext -in @('.csv','.log','.txt','.json')) {
        return ($baseName -match $namePattern)
    }

    return $false
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\\..')).Path
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    throw "RepoRoot does not exist: $RepoRoot"
}

$repoResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
$cutoff = (Get-Date).AddDays(-1 * [math]::Abs($OlderThanDays))
$trackedSet = if ($SkipTrackedFiles) { Get-GitTrackedSet -Root $repoResolved } else { New-Object 'System.Collections.Generic.HashSet[string]' }

$candidateFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$candidateDirs = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]

foreach ($relativeRoot in $TargetRelativeRoots) {
    $absRoot = Join-Path $repoResolved $relativeRoot
    if (-not (Test-Path -LiteralPath $absRoot)) {
        continue
    }

    Get-ChildItem -LiteralPath $absRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $rel = Normalize-RelativePath -Path (Convert-ToRelativePath -BasePath $repoResolved -Path $_.FullName)

            if (Test-IsProtectedPath -RelativePath $rel) { return }
            if ($SkipTrackedFiles -and $trackedSet.Contains($rel)) { return }

            if (Test-IsDisposableFile -File $_ -Cutoff $cutoff) {
                [void]$candidateFiles.Add($_)
            }
        }

    # Remove only empty temp-like directories for safety.
    Get-ChildItem -LiteralPath $absRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            if ($_.LastWriteTime -gt $cutoff) { return }
            $rel = Normalize-RelativePath -Path (Convert-ToRelativePath -BasePath $repoResolved -Path $_.FullName)
            if (Test-IsProtectedPath -RelativePath $rel) { return }
            if ($rel -notmatch '(?i)(backup|backups|temp|tmp|old|archive|unzip)') { return }

            $childCount = (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($childCount -eq 0) {
                [void]$candidateDirs.Add($_)
            }
        }
}

$filesToDelete = @($candidateFiles | Sort-Object FullName -Unique)
$dirsToDelete = @($candidateDirs | Sort-Object FullName -Unique)

$totalBytes = 0
if ($filesToDelete.Count -gt 0) {
    $sizeMeasure = $filesToDelete | Measure-Object -Property Length -Sum
    if ($null -ne $sizeMeasure -and $null -ne $sizeMeasure.Sum) {
        $totalBytes = [int64]$sizeMeasure.Sum
    }
}

Write-Host "Mode: $Mode"
Write-Host "RepoRoot: $repoResolved"
Write-Host "OlderThanDays: $OlderThanDays (cutoff: $($cutoff.ToString('s')))"
Write-Host "SkipTrackedFiles: $SkipTrackedFiles"
Write-Host "Target roots: $($TargetRelativeRoots -join ', ')"
Write-Host ""
Write-Host ("Candidate files: {0} (total {1:N2} MB)" -f $filesToDelete.Count, ($totalBytes / 1MB))
Write-Host ("Candidate empty dirs: {0}" -f $dirsToDelete.Count)
Write-Host ""

if ($filesToDelete.Count -gt 0) {
    Write-Host 'Files:'
    $filesToDelete | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host
}

if ($dirsToDelete.Count -gt 0) {
    Write-Host 'Empty directories:'
    $dirsToDelete | Select-Object FullName, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Host
}

if ($Mode -eq 'Execute') {
    foreach ($f in $filesToDelete) {
        Remove-Item -LiteralPath $f.FullName -Force
    }
    foreach ($d in $dirsToDelete) {
        Remove-Item -LiteralPath $d.FullName -Force
    }
    Write-Host 'Cleanup completed in Execute mode.'
} else {
    Write-Host 'Dry run only. No files were deleted.'
}
