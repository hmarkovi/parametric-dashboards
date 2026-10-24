<#
.SYNOPSIS
Orchestrate parallel UPSVF and ILAS pulls, then merge. Writes stage manifest for resumption.

.DESCRIPTION
Runs UPSVF and ILAS data extractions in parallel PowerShell jobs. Records stage state
in a JSON manifest file for resumption and debugging. Calls merge-ilas-into-upsvf.ps1
to combine results only after both stages succeed.

STAGE MANIFEST tracks:
- Stage name, status (PENDING/IN_PROGRESS/SUCCESS/FAILED/WAITING_FOR_DATA)
- Input/output paths, row counts, timestamps, error messages
- Enables resumption: if ILAS fails, retry just ILAS without re-pulling UPSVF

.PARAMETER OutputDirectory
Base directory for all outputs (manifests, CSVs, logs)

.PARAMETER LotsOverride
Comma-separated lot list for UPSVF pull (default: all lots)

.PARAMETER LastNDaysTestEnd
Days of lookback for UPSVF test-end filter (default: 7)

.PARAMETER IlasScriptPath
Path to aqua_nvlh_ilas_vmin_analysis.ps1

.PARAMETER UpsvfScriptPath
Path to aqua_nvlh_weekly_pull.ps1

.PARAMETER MergeScriptPath
Path to merge-ilas-into-upsvf.ps1

.PARAMETER ManifestPath
Path to write stage manifest JSON (default: OutputDirectory\stage_manifest.json)

.PARAMETER SkipIlasStep
If set, skip ILAS pull and merge; output UPSVF-only CSV

.PARAMETER ForceRestartStage
Force restart of specific stage even if it succeeded (values: discovery, upsvf_pull, ilas_pull, merge)

.PARAMETER VpoList
Comma-separated list of VPO names to use as FilterSet. If empty, runs VPO discovery first.

.PARAMETER DiscoveryScriptPath
Path to discover_nvlh_vpos.ps1

.PARAMETER AutoDiscoverVpos
If true, automatically run VPO discovery (default: true). Set to false to use VpoList parameter only.

.EXAMPLE
# Auto-discover VPOs from past 24 hours, then run parallel pulls
.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory "R:\Products\NVL\NVL-H\Weekly Runs"

# Use pre-defined VPO list (skip discovery)
.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory "R:\Products\NVL\NVL-H\Weekly Runs" `
  -VpoList "VPO_A,VPO_B,VPO_C"

#>

param(
    [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs",
    [string]$VpoList = "",
    [int]$LastNDaysTestEnd = 1,
    [string]$LotsOverride = "",
    [string]$IlasScriptPath = "",
    [string]$UpsvfScriptPath = "",
    [string]$MergeScriptPath = "",
    [string]$DiscoveryScriptPath = "",
    [string]$ManifestPath = "",
    [bool]$AutoDiscoverVpos = $true,
    [switch]$SkipIlasStep,
    [string]$ForceRestartStage = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ===== FUNCTIONS =====

function Initialize-StageManifest {
    param([string]$ManifestFilePath)
    
    $manifest = [ordered]@{
        run_id = (Get-Date -Format "yyyyMMdd_HHmmss")
        start_time = ([datetime]::UtcNow).ToString("o")
        stages = [ordered]@{
            discovery = @{status = "PENDING"; start_time = $null; end_time = $null; output_vpos = $null; vpo_count = 0; error = $null}
            upsvf_pull = @{status = "PENDING"; start_time = $null; end_time = $null; output_csv = $null; rows = 0; error = $null}
            ilas_pull = @{status = "PENDING"; start_time = $null; end_time = $null; output_csv = $null; rows = 0; error = $null}
            merge = @{status = "PENDING"; start_time = $null; end_time = $null; output_csv = $null; rows = 0; error = $null}
        }
    }
    
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ManifestFilePath -Encoding UTF8
    return $manifest
}

function Load-StageManifest {
    param([string]$ManifestFilePath)
    
    if (-not (Test-Path -LiteralPath $ManifestFilePath)) {
        return $null
    }
    return Get-Content -LiteralPath $ManifestFilePath -Encoding UTF8 | ConvertFrom-Json
}

function Update-StageStatus {
    param(
        [string]$ManifestFilePath,
        [string]$StageName,
        [string]$Status,
        [string]$OutputCsv = "",
        [int]$RowCount = 0,
        [string]$ErrorMessage = ""
    )
    
    # Load manifest - ConvertFrom-Json creates PSCustomObjects
    $manifestJson = Get-Content -LiteralPath $ManifestFilePath -Encoding UTF8 -Raw
    $manifest = $manifestJson | ConvertFrom-Json
    
    if ($null -eq $manifest) {
        throw "Stage manifest not found: $ManifestFilePath"
    }
    
    # Convert PSCustomObject to hashtable for safe manipulation
    $stagesObj = $manifest.stages
    $stagesHash = @{}
    foreach ($prop in $stagesObj.PSObject.Properties) {
        $stageObj = $prop.Value
        $stageHash = @{}
        foreach ($stageProp in $stageObj.PSObject.Properties) {
            $stageHash[$stageProp.Name] = $stageProp.Value
        }
        $stagesHash[$prop.Name] = $stageHash
    }
    
    # Update the stage
    $now = ([datetime]::UtcNow).ToString("o")
    $stage = $stagesHash[$StageName]
    
    if ($Status -eq "IN_PROGRESS") {
        $stage.status = "IN_PROGRESS"
        $stage.start_time = $now
    }
    elseif ($Status -in @("SUCCESS", "FAILED", "WAITING_FOR_DATA", "SKIPPED")) {
        $stage.status = $Status
        $stage.end_time = $now
        if ($OutputCsv) { $stage.output_csv = $OutputCsv }
        if ($RowCount -gt 0) { $stage.rows = $RowCount }
        if ($ErrorMessage) { $stage.error = $ErrorMessage }
    }
    
    # Reconstruct the manifest as a hashtable
    $updatedManifest = @{
        run_id = $manifest.run_id
        start_time = $manifest.start_time
        stages = $stagesHash
    }
    
    $updatedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestFilePath -Encoding UTF8
}

function Resolve-ScriptPath {
    param(
        [string]$ConfiguredPath,
        [string]$RelativeName,
        [string]$BasePath = (Split-Path -Path $PSCommandPath -Parent)
    )
    
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return $ConfiguredPath
    }
    
    $candidates = @(
        (Join-Path $BasePath $RelativeName),
        (Join-Path (Split-Path $BasePath -Parent) "parametric-analysis\ilas\$RelativeName"),
        (Join-Path (Split-Path (Split-Path $BasePath -Parent) -Parent) "parametric-analysis\ilas\$RelativeName")
    )
    
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }
    
    return $candidates[0]
}

function Get-CsvRowCount {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath)) { return 0 }
    try {
        $rows = @(Import-Csv -LiteralPath $CsvPath)
        return $rows.Count
    }
    catch {
        return 0
    }
}

# ===== MAIN =====

$runStart = Get-Date
$overallStatus = "FAILED"
$overallMessage = "Unknown failure"

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Resolve script paths
    $upsvfScript = Resolve-ScriptPath -ConfiguredPath $UpsvfScriptPath -RelativeName "aqua_nvlh_weekly_pull.ps1" -BasePath (Split-Path $PSCommandPath -Parent)
    $ilasScript = Resolve-ScriptPath -ConfiguredPath $IlasScriptPath -RelativeName "aqua_nvlh_ilas_vmin_analysis.ps1" -BasePath (Split-Path $PSCommandPath -Parent)
    $mergeScript = Resolve-ScriptPath -ConfiguredPath $MergeScriptPath -RelativeName "merge-ilas-into-upsvf.ps1" -BasePath (Join-Path (Split-Path (Split-Path (Split-Path $PSCommandPath -Parent) -Parent) -Parent) "utility")
    $discoveryScript = Resolve-ScriptPath -ConfiguredPath $DiscoveryScriptPath -RelativeName "discover_nvlh_vpos.ps1" -BasePath (Split-Path $PSCommandPath -Parent)
    
    Write-Host "Discovery script: $discoveryScript"
    Write-Host "UPSVF script:     $upsvfScript"
    Write-Host "ILAS script:      $ilasScript"
    Write-Host "Merge script:     $mergeScript"
    Write-Host ""
    
    if ($AutoDiscoverVpos -and -not (Test-Path -LiteralPath $discoveryScript)) {
        Write-Warning "Discovery script not found: $discoveryScript (VPO discovery disabled)"
        $AutoDiscoverVpos = $false
    }
    if (-not (Test-Path -LiteralPath $upsvfScript)) { throw "UPSVF script not found: $upsvfScript" }
    if (-not $SkipIlasStep -and -not (Test-Path -LiteralPath $ilasScript)) { throw "ILAS script not found: $ilasScript" }
    
    # Initialize or load manifest
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = Join-Path $OutputDirectory "stage_manifest.json"
    }
    
    $existingManifest = Load-StageManifest -ManifestFilePath $ManifestPath
    if ($null -eq $existingManifest) {
        $manifest = Initialize-StageManifest -ManifestFilePath $ManifestPath
        Write-Host "Created new stage manifest: $ManifestPath"
    }
    else {
        $manifest = $existingManifest
        Write-Host "Loaded existing stage manifest: $ManifestPath"
    }
    
    $runId = $manifest.run_id
    Write-Host "Run ID: $runId"
    Write-Host ""
    
    # ===== STAGE 0: VPO DISCOVERY =====
    $discoveryStage = $manifest.stages.discovery
    $skipDiscovery = ($discoveryStage.status -eq "SUCCESS") -and ([string]::IsNullOrWhiteSpace($ForceRestartStage) -or $ForceRestartStage -ne "discovery")
    
    if (-not [string]::IsNullOrWhiteSpace($VpoList)) {
        # VPO list provided, skip discovery
        Write-Host "[SKIP] VPO discovery (list provided)" -ForegroundColor Green
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "discovery" -Status "SUCCESS" -OutputCsv $VpoList -RowCount ($VpoList.Split(',').Count)
    }
    elseif ($skipDiscovery) {
        Write-Host "[SKIP] VPO discovery already completed. VPO count: $($discoveryStage.rows)" -ForegroundColor Green
        $VpoList = $discoveryStage.output_vpos
    }
    elseif ($AutoDiscoverVpos) {
        Write-Host "[START] VPO discovery stage..." -ForegroundColor Cyan
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "discovery" -Status "IN_PROGRESS"
        
        try {
            # Run discovery with explicit parameter passing (not splatting)
            Write-Host "[DEBUG] Running discovery: & $discoveryScript -LastNDaysTestEnd $LastNDaysTestEnd" -ForegroundColor Gray
            $discoveryOutput = & $discoveryScript -LastNDaysTestEnd ([int]$LastNDaysTestEnd) 2>&1
            
            # Discovery script outputs "VPO List (comma-separated):" followed by the list
            # Extract the comma-separated list from output
            $vpoListLine = $discoveryOutput | Where-Object { $_ -match "^[A-Z0-9_,]+$" -and $_ -notmatch "^(VPO|RowCount|Discovered|Overall)" }
            
            if ($vpoListLine) {
                $VpoList = $vpoListLine | Select-Object -First 1
            }
            else {
                # Fallback: look for line with commas and alphanumeric/underscore only
                $VpoList = $discoveryOutput | Where-Object { $_ -match "^[A-Z0-9_]+(\,[A-Z0-9_]+)*$" } | Select-Object -First 1
            }
            
            if ([string]::IsNullOrWhiteSpace($VpoList)) {
                # Additional fallback: take the last non-empty, non-debug line
                $VpoList = ($discoveryOutput | Where-Object { $_ -and $_ -notmatch "^\s*\[" -and $_ -notmatch "^Environment" -and $_ -notmatch "^=====" } | Select-Object -Last 1).Trim()
            }
            
            if ([string]::IsNullOrWhiteSpace($VpoList)) {
                $discoveryError = "VPO discovery returned empty list. Full output:`n$($discoveryOutput | Out-String)"
                Write-Host $discoveryError -ForegroundColor Yellow
                throw $discoveryError
            }
            
            $vpoCount = @($VpoList -split ',').Count
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "discovery" -Status "SUCCESS" -OutputCsv $VpoList -RowCount $vpoCount
            Write-Host "[DONE] VPO discovery completed: $vpoCount VPOs found" -ForegroundColor Green
            Write-Host "VPO List: $VpoList" -ForegroundColor Yellow
        }
        catch {
            $errMsg = $_.Exception.Message
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "discovery" -Status "FAILED" -ErrorMessage $errMsg
            throw "VPO discovery failed: $errMsg"
        }
    }
    else {
        Write-Host "[WARN] No VPO list provided and auto-discovery disabled" -ForegroundColor Yellow
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "discovery" -Status "SKIPPED" -ErrorMessage "VPO list not provided; auto-discovery disabled"
        throw "VPO FilterSet required (provide -VpoList or enable -AutoDiscoverVpos)"
    }
    
    Write-Host ""
    # ===== STAGE 1: UPSVF PULL =====
    $upsvfStage = $manifest.stages.upsvf_pull
    $skipUpsvf = ($upsvfStage.status -eq "SUCCESS") -and ([string]::IsNullOrWhiteSpace($ForceRestartStage) -or $ForceRestartStage -ne "upsvf_pull")
    
    if ($skipUpsvf) {
        Write-Host "[SKIP] UPSVF stage already completed. Output: $($upsvfStage.output_csv)" -ForegroundColor Green
        $upsvfCsv = $upsvfStage.output_csv
    }
    else {
        Write-Host "[START] UPSVF pull stage..." -ForegroundColor Cyan
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "upsvf_pull" -Status "IN_PROGRESS"
        
        try {
            # Run UPSVF script with explicit parameters
            Write-Host "[DEBUG] Running UPSVF: & $upsvfScript -SkipIlasStep -OutputDirectory $OutputDirectory -LastNDaysTestEnd $LastNDaysTestEnd" -ForegroundColor Gray
            
            & $upsvfScript `
                -SkipIlasStep `
                -OutputDirectory $OutputDirectory `
                -LastNDaysTestEnd ([int]$LastNDaysTestEnd)
            
            if (-not [string]::IsNullOrWhiteSpace($LotsOverride)) {
                Write-Warning "[INFO] LotsOverride parameter available but not used in this refactored version; use discovered VPOs instead"
            }
            
            # Find the generated CSV (most recent Vmin_*.csv)
            $upsvfCsv = Get-ChildItem -LiteralPath $OutputDirectory -Filter "Vmin_*_WW*_*.csv" -File |
                Where-Object { $_.Name -notlike "*_clean" -and $_.Name -notlike "*_merged" } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
            
            if (-not $upsvfCsv) {
                throw "UPSVF pull did not create expected output CSV"
            }
            
            $upsvfRows = Get-CsvRowCount -CsvPath $upsvfCsv
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "upsvf_pull" -Status "SUCCESS" -OutputCsv $upsvfCsv -RowCount $upsvfRows
            Write-Host "[DONE] UPSVF pull completed: $upsvfCsv ($upsvfRows rows)" -ForegroundColor Green
        }
        catch {
            $errMsg = $_.Exception.Message
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "upsvf_pull" -Status "FAILED" -ErrorMessage $errMsg
            throw "UPSVF pull failed: $errMsg"
        }
    }
    
    Write-Host ""
    
    # ===== STAGE 2: ILAS PULL (parallel) =====
    if (-not $SkipIlasStep) {
        $ilasStage = $manifest.stages.ilas_pull
        $skipIlas = ($ilasStage.status -in @("SUCCESS", "WAITING_FOR_DATA")) -and ([string]::IsNullOrWhiteSpace($ForceRestartStage) -or $ForceRestartStage -ne "ilas_pull")
        
        if ($skipIlas) {
            Write-Host "[SKIP] ILAS stage already completed with status: $($ilasStage.status)" -ForegroundColor Green
            $ilasCsv = $ilasStage.output_csv
        }
        else {
            Write-Host "[START] ILAS pull stage (parallel job)..." -ForegroundColor Cyan
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "IN_PROGRESS"
            
            $ilasOutputDir = Join-Path $OutputDirectory ("_ilas_parallel_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
            if (-not (Test-Path -LiteralPath $ilasOutputDir)) {
                New-Item -Path $ilasOutputDir -ItemType Directory -Force | Out-Null
            }
            
            $ilasJob = Start-Job -ScriptBlock {
                param($Script, $UpsvfRef, $OutDir)
                $ErrorActionPreference = "Stop"
                try {
                    & $Script `
                        -UpsvfReferenceCsv $UpsvfRef `
                        -OutputDirectory $OutDir
                    return $OutDir
                }
                catch {
                    throw $_
                }
            } -ArgumentList $ilasScript, $upsvfCsv, $ilasOutputDir
            
            # Wait for ILAS job (with timeout of 30 minutes)
            $ilasJobResult = Wait-Job -Job $ilasJob -Timeout 1800 -ErrorAction SilentlyContinue
            if ($null -eq $ilasJobResult) {
                Stop-Job -Job $ilasJob -ErrorAction SilentlyContinue
                $ilasError = "ILAS pull timed out after 30 minutes"
                Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "FAILED" -ErrorMessage $ilasError
                Write-Warning $ilasError
            }
            else {
                try {
                    $ilasResult = Receive-Job -Job $ilasJob -ErrorAction Stop
                    
                    # Find ILAS summary CSV
                    $ilasCsv = Get-ChildItem -LiteralPath $ilasOutputDir -Filter "ILAS_Vmin_Summary_*.csv" -File |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1 -ExpandProperty FullName
                    
                    if ($ilasCsv) {
                        $ilasRows = Get-CsvRowCount -CsvPath $ilasCsv
                        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "SUCCESS" -OutputCsv $ilasCsv -RowCount $ilasRows
                        Write-Host "[DONE] ILAS pull completed: $ilasCsv ($ilasRows rows)" -ForegroundColor Green
                    }
                    else {
                        $ilasError = "ILAS pull did not create expected summary CSV in $ilasOutputDir"
                        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "WAITING_FOR_DATA" -ErrorMessage $ilasError
                        Write-Warning "[WAITING] $ilasError"
                    }
                }
                catch {
                    $ilasError = $_.Exception.Message
                    Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "FAILED" -ErrorMessage $ilasError
                    Write-Warning "[FAILED] ILAS pull error: $ilasError"
                }
            }
            
            Remove-Job -Job $ilasJob -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "[SKIP] ILAS step skipped by parameter" -ForegroundColor Green
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "ilas_pull" -Status "SKIPPED"
    }
    
    Write-Host ""
    
    # ===== STAGE 3: MERGE (if ILAS succeeded) =====
    $manifest = Load-StageManifest -ManifestFilePath $ManifestPath
    $ilasStage = $manifest.stages.ilas_pull
    if (-not $SkipIlasStep -and $ilasStage.status -eq "SUCCESS" -and $ilasCsv) {
        Write-Host "[START] Merge stage..." -ForegroundColor Cyan
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "merge" -Status "IN_PROGRESS"
        
        try {
            # Always write merged CSV beside UPSVF input with _merged suffix.
            $upsvfBaseName = [System.IO.Path]::GetFileNameWithoutExtension($upsvfCsv)
            $upsvfDir = [System.IO.Path]::GetDirectoryName($upsvfCsv)
            if ($upsvfBaseName -notlike "*_merged") {
                $upsvfBaseName = "$upsvfBaseName`_merged"
            }
            $mergedCsv = Join-Path $upsvfDir "$upsvfBaseName.csv"
            
            & $mergeScript `
                -UpsvfCleanCsv $upsvfCsv `
                -IlasSummaryCsv $ilasCsv `
                -OutputCsv $mergedCsv
            
            if (Test-Path -LiteralPath $mergedCsv) {
                $mergedRows = Get-CsvRowCount -CsvPath $mergedCsv
                Update-StageStatus -ManifestFilePath $ManifestPath -StageName "merge" -Status "SUCCESS" -OutputCsv $mergedCsv -RowCount $mergedRows
                Write-Host "[DONE] Merge completed: $mergedCsv ($mergedRows rows)" -ForegroundColor Green
                Write-Host ""
                Write-Host "FINAL OUTPUT: $mergedCsv" -ForegroundColor Yellow
            }
            else {
                throw "Merge script did not create output: $mergedCsv"
            }
        }
        catch {
            $errMsg = $_.Exception.Message
            Update-StageStatus -ManifestFilePath $ManifestPath -StageName "merge" -Status "FAILED" -ErrorMessage $errMsg
            Write-Warning "[FAILED] Merge failed: $errMsg"
        }
    }
    elseif (-not $SkipIlasStep -and $ilasStage.status -eq "WAITING_FOR_DATA") {
        Write-Host "[HOLD] Merge held pending ILAS data availability" -ForegroundColor Yellow
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "merge" -Status "WAITING_FOR_DATA" -ErrorMessage "ILAS data not yet available"
    }
    elseif ($SkipIlasStep) {
        Write-Host "[SKIP] Merge skipped (ILAS step skipped)" -ForegroundColor Green
        Update-StageStatus -ManifestFilePath $ManifestPath -StageName "merge" -Status "SKIPPED"
    }
    
    Write-Host ""
    Write-Host "STAGE MANIFEST: $ManifestPath" -ForegroundColor Cyan
    Get-Content -LiteralPath $ManifestPath | Write-Host
    
    $overallStatus = "SUCCESS"
    $overallMessage = "Parallel pipeline completed"
}
catch {
    $overallStatus = "FAILED"
    $overallMessage = $_.Exception.Message
    Write-Error $overallMessage
}
finally {
    $runEnd = Get-Date
    $duration = ($runEnd - $runStart).TotalSeconds
    Write-Host ""
    Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if ($overallStatus -eq "SUCCESS") { "Green" } else { "Red" })
    Write-Host "Duration: $duration seconds"
    Write-Host "Manifest: $ManifestPath"
}
