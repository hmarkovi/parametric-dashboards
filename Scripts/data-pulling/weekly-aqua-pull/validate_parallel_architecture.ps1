<#
.SYNOPSIS
Validation script for parallel UPSVF + ILAS architecture with detailed step-by-step logging.

.DESCRIPTION
Runs the complete orchestrator and saves detailed validation reports.

.PARAMETER ValidationOutputRoot
Base directory for validation results (default: R:\Products\NVL\NVL-H\Weekly Runs\validation)

.PARAMETER LastNDaysTestEnd
Days of lookback for data pull (default: 1)

.PARAMETER SkipIlasStep
If set, only run UPSVF (useful for testing just one stage)

#>

param(
    [string]$ValidationOutputRoot = "R:\Products\NVL\NVL-H\Weekly Runs\validation",
    [int]$LastNDaysTestEnd = 1,
    [switch]$SkipIlasStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-ValidationLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFilePath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Write-Host $logEntry -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "DONE" { "Green" }
            default { "White" }
        }
    )
    
    if ($LogFilePath) {
        Add-Content -LiteralPath $LogFilePath -Value $logEntry -Encoding UTF8
    }
}

function Get-FileInfo {
    param([string]$FilePath)
    
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return @{Exists = $false; Size = 0; Rows = 0; Path = $FilePath}
    }
    
    $file = Get-Item -LiteralPath $FilePath
    $rows = 0
    try {
        $csv = Import-Csv -LiteralPath $FilePath
        $rows = @($csv).Count
    } catch {
        $rows = -1
    }
    
    return @{
        Exists = $true
        Size = $file.Length
        SizeMB = [Math]::Round($file.Length / 1MB, 2)
        Rows = $rows
        Path = $FilePath
        LastWriteTime = $file.LastWriteTime
    }
}

# ============================================================================
# MAIN VALIDATION
# ============================================================================

try {
    # Create validation directory structure
    $validationId = "VALIDATION_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $validationDir = Join-Path $ValidationOutputRoot $validationId
    
    if (-not (Test-Path -LiteralPath $ValidationOutputRoot)) {
        Write-Host "Creating validation root: $ValidationOutputRoot" -ForegroundColor Cyan
        New-Item -Path $ValidationOutputRoot -ItemType Directory -Force | Out-Null
    }
    
    New-Item -Path $validationDir -ItemType Directory -Force | Out-Null
    
    $logFile = Join-Path $validationDir "validation_log.txt"
    $reportFile = Join-Path $validationDir "validation_report.json"
    $csvOutputDir = Join-Path $validationDir "csv_outputs"
    New-Item -Path $csvOutputDir -ItemType Directory -Force | Out-Null
    
    # Initialize validation report
    $report = [ordered]@{
        validation_id = $validationId
        start_time = ([datetime]::UtcNow).ToString("o")
        parameters = [ordered]@{
            LastNDaysTestEnd = $LastNDaysTestEnd
            SkipIlasStep = $SkipIlasStep.IsPresent
            ValidationRoot = $ValidationOutputRoot
        }
        stages = [ordered]@{}
        final_status = "UNKNOWN"
        summary = ""
    }
    
    Write-ValidationLog "========================================" -LogFilePath $logFile
    Write-ValidationLog "NVLH Parallel Architecture Validation" -LogFilePath $logFile
    Write-ValidationLog "========================================" -LogFilePath $logFile
    Write-ValidationLog "Validation ID: $validationId" -LogFilePath $logFile
    Write-ValidationLog "Start Time: $($report.start_time)" -LogFilePath $logFile
    Write-ValidationLog "" -LogFilePath $logFile
    
    # ===== STAGE 1: RUN ORCHESTRATOR =====
    Write-ValidationLog "STAGE 1: Running Orchestrator" -LogFilePath $logFile
    $orchestratorStartTime = Get-Date
    
    # Run the orchestrator with parameters
    $orchestratorScript = Join-Path (Split-Path $PSCommandPath -Parent) "run_upsvf_ilas_parallel.ps1"
    
    Write-ValidationLog "Orchestrator: $orchestratorScript" -LogFilePath $logFile
    Write-ValidationLog "Output Dir: $csvOutputDir" -LogFilePath $logFile
    
    $orchestratorOutput = & $orchestratorScript `
        -OutputDirectory $csvOutputDir `
        -LastNDaysTestEnd $LastNDaysTestEnd `
        -AutoDiscoverVpos $false `
        -VpoList "6248_CLASSHOT" `
        -SkipIlasStep:$SkipIlasStep `
        2>&1
    
    $orchestratorDuration = (Get-Date) - $orchestratorStartTime
    Write-ValidationLog "[DONE] Orchestrator completed in $($orchestratorDuration.TotalSeconds) seconds" -Level "DONE" -LogFilePath $logFile
    
    # Save orchestrator output
    $orchestratorOutput | Set-Content -LiteralPath (Join-Path $validationDir "orchestrator_output.log") -Encoding UTF8
    
    Write-ValidationLog "" -LogFilePath $logFile
    
    # ===== STAGE 2: COLLECT RESULTS =====
    Write-ValidationLog "STAGE 2: Analyzing Results" -LogFilePath $logFile
    
    # Find generated files
    $csvFiles = Get-ChildItem -LiteralPath $csvOutputDir -Filter "*.csv" -File -ErrorAction SilentlyContinue
    $allCsvFiles = Get-ChildItem -LiteralPath $csvOutputDir -Filter "*.csv" -File -Recurse -ErrorAction SilentlyContinue
    Write-ValidationLog "CSV files found: $($csvFiles.Count)" -LogFilePath $logFile
    
    foreach ($csv in $csvFiles) {
        $fileInfo = Get-FileInfo -FilePath $csv.FullName
        Write-ValidationLog "  - $($csv.Name): $($fileInfo.Rows) rows, $($fileInfo.SizeMB) MB" -LogFilePath $logFile
    }
    
    # Check for manifest
    $manifestPath = Join-Path $csvOutputDir "stage_manifest.json"
    if (Test-Path -LiteralPath $manifestPath) {
        Write-ValidationLog "[DONE] Stage manifest found" -Level "DONE" -LogFilePath $logFile
        $manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
        
        foreach ($stageName in @("discovery", "upsvf_pull", "ilas_pull", "merge")) {
            if ($manifest.stages.PSObject.Properties.Name -contains $stageName) {
                $stage = $manifest.stages.$stageName
                Write-ValidationLog "  Stage: $stageName = $($stage.status)" -LogFilePath $logFile
            }
        }
    } else {
        Write-ValidationLog "[WARN] Stage manifest not found" -Level "WARN" -LogFilePath $logFile
    }
    
    Write-ValidationLog "" -LogFilePath $logFile
    
    # ===== STAGE 3: VALIDATION CHECKS =====
    Write-ValidationLog "STAGE 3: Running Validation Checks" -LogFilePath $logFile
    $validationChecks = @()
    
    # Check 1: CSV files created
    if ($csvFiles.Count -gt 0) {
        $validationChecks += @{name = "CSV files created"; result = "PASS"; details = "$($csvFiles.Count) files"}
        Write-ValidationLog "  PASS CSV files created: $($csvFiles.Count) files" -Level "DONE" -LogFilePath $logFile
    } else {
        $validationChecks += @{name = "CSV files created"; result = "FAIL"; details = "No CSV files found"}
        Write-ValidationLog "  FAIL CSV files created: FAILED" -Level "ERROR" -LogFilePath $logFile
    }
    
    # Check 2: UPSVF CSV has rows
    $upsvfCsv = $csvFiles | Where-Object { $_.Name -like "Vmin_*_clean.csv" -or $_.Name -like "Vmin_*WW*.csv" } | Select-Object -First 1
    if ($upsvfCsv) {
        $upsvfInfo = Get-FileInfo -FilePath $upsvfCsv.FullName
        if ($upsvfInfo.Rows -gt 0) {
            $validationChecks += @{name = "UPSVF data exists"; result = "PASS"; details = "$($upsvfInfo.Rows) rows"}
            Write-ValidationLog "  PASS UPSVF data: $($upsvfInfo.Rows) rows" -Level "DONE" -LogFilePath $logFile
        } else {
            $validationChecks += @{name = "UPSVF data exists"; result = "FAIL"; details = "0 rows"}
            Write-ValidationLog "  FAIL UPSVF data: 0 rows" -Level "ERROR" -LogFilePath $logFile
        }
    } else {
        $validationChecks += @{name = "UPSVF data exists"; result = "FAIL"; details = "File not found"}
        Write-ValidationLog "  FAIL UPSVF data: File not found" -Level "ERROR" -LogFilePath $logFile
    }
    
    # Check 3: Merged CSV exists and has all UPSVF rows
    $mergedCsv = $allCsvFiles | Where-Object { $_.Name -like "*_merged.csv" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($mergedCsv) {
        $mergedInfo = Get-FileInfo -FilePath $mergedCsv.FullName
        if ($upsvfInfo -and $mergedInfo.Rows -eq $upsvfInfo.Rows) {
            $validationChecks += @{name = "Merged preserves all UPSVF rows"; result = "PASS"; details = "$($mergedInfo.Rows) rows match"}
            Write-ValidationLog "  PASS Merged CSV: $($mergedInfo.Rows) rows (matches UPSVF)" -Level "DONE" -LogFilePath $logFile
        } else {
            $validationChecks += @{name = "Merged preserves all UPSVF rows"; result = "FAIL"; details = "Row counts do not match"}
            Write-ValidationLog "  FAIL Merged CSV: Row count mismatch" -Level "WARN" -LogFilePath $logFile
        }
    } else {
        $validationChecks += @{name = "Merged preserves all UPSVF rows"; result = "WARN"; details = "Merged CSV not found"}
        Write-ValidationLog "  WARN Merged CSV: Not found" -Level "WARN" -LogFilePath $logFile
    }
    
    # Check 4: ILAS CSV exists (if not skipped)
    if (-not $SkipIlasStep) {
        $ilasCsv = $allCsvFiles | Where-Object { $_.Name -like "*ILAS*Summary*.csv" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($ilasCsv) {
            $ilasInfo = Get-FileInfo -FilePath $ilasCsv.FullName
            $validationChecks += @{name = "ILAS data exists"; result = "PASS"; details = "$($ilasInfo.Rows) rows"}
            Write-ValidationLog "  PASS ILAS data: $($ilasInfo.Rows) rows" -Level "DONE" -LogFilePath $logFile
        } else {
            $validationChecks += @{name = "ILAS data exists"; result = "WARN"; details = "No ILAS CSV found"}
            Write-ValidationLog "  WARN ILAS data: Not found" -Level "WARN" -LogFilePath $logFile
        }
    }
    
    # Check 5: Manifest exists and is valid JSON
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifestJson = Get-Content -LiteralPath $manifestPath | ConvertFrom-Json
            $validationChecks += @{name = "Stage manifest valid"; result = "PASS"; details = "JSON valid"}
            Write-ValidationLog "  PASS Stage manifest: Valid JSON" -Level "DONE" -LogFilePath $logFile
        } catch {
            $validationChecks += @{name = "Stage manifest valid"; result = "FAIL"; details = "Invalid JSON"}
            Write-ValidationLog "  FAIL Stage manifest: Invalid JSON" -Level "ERROR" -LogFilePath $logFile
        }
    } else {
        $validationChecks += @{name = "Stage manifest valid"; result = "FAIL"; details = "Manifest not found"}
        Write-ValidationLog "  FAIL Stage manifest: Not found" -Level "ERROR" -LogFilePath $logFile
    }
    
    Write-ValidationLog "" -LogFilePath $logFile
    
    # ===== FINAL REPORT =====
    Write-ValidationLog "STAGE 4: Generating Final Report" -LogFilePath $logFile
    
    $passCount = @($validationChecks | Where-Object { $_.result -eq "PASS" }).Count
    $failCount = @($validationChecks | Where-Object { $_.result -eq "FAIL" }).Count
    $warnCount = @($validationChecks | Where-Object { $_.result -eq "WARN" }).Count
    
    $report.validation_checks = $validationChecks
    $report.check_summary = [ordered]@{
        total = $validationChecks.Count
        passed = $passCount
        failed = $failCount
        warnings = $warnCount
    }
    
    if ($failCount -eq 0) {
        $report.final_status = "SUCCESS"
        Write-ValidationLog "[DONE] Validation PASSED: $passCount/$($validationChecks.Count) checks" -Level "DONE" -LogFilePath $logFile
    } else {
        $report.final_status = "PARTIAL"
        Write-ValidationLog "[WARN] Validation PARTIAL: $passCount passed, $failCount failed, $warnCount warnings" -Level "WARN" -LogFilePath $logFile
    }
    
    $endUtc = [datetimeoffset]::UtcNow
    $startUtc = [datetimeoffset]::Parse($report.start_time, [System.Globalization.CultureInfo]::InvariantCulture)
    $report.end_time = $endUtc.ToString("o")
    $totalDuration = $endUtc - $startUtc
    $report.duration_seconds = $totalDuration.TotalSeconds
    
    Write-ValidationLog "" -LogFilePath $logFile
    Write-ValidationLog "========================================" -LogFilePath $logFile
    Write-ValidationLog "Validation Summary" -LogFilePath $logFile
    Write-ValidationLog "========================================" -LogFilePath $logFile
    Write-ValidationLog "Status: $($report.final_status)" -LogFilePath $logFile
    Write-ValidationLog "Duration: $($totalDuration.TotalSeconds) seconds" -LogFilePath $logFile
    Write-ValidationLog "Passed: $passCount / $($validationChecks.Count)" -LogFilePath $logFile
    Write-ValidationLog "Failed: $failCount" -LogFilePath $logFile
    Write-ValidationLog "Warnings: $warnCount" -LogFilePath $logFile
    Write-ValidationLog "Validation ID: $validationId" -LogFilePath $logFile
    Write-ValidationLog "Location: $validationDir" -LogFilePath $logFile
    Write-ValidationLog "========================================" -LogFilePath $logFile
    
    # Save report as JSON
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFile -Encoding UTF8
    
    Write-ValidationLog "" -LogFilePath $logFile
    Write-ValidationLog "Full report saved to: $reportFile" -LogFilePath $logFile
    Write-ValidationLog "Validation log: $logFile" -LogFilePath $logFile
    
    # Print summary to console
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Validation Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Status: $($report.final_status)" -ForegroundColor $(if($report.final_status -eq "SUCCESS") {"Green"} else {"Yellow"})
    Write-Host "Validation ID: $validationId" -ForegroundColor White
    Write-Host "Location: $validationDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Results Summary:" -ForegroundColor Cyan
    Write-Host "  Passed: $passCount / $($validationChecks.Count)"
    Write-Host "  Failed: $failCount"
    Write-Host "  Warnings: $warnCount"
    Write-Host "  Duration: $($totalDuration.TotalSeconds) seconds"
    Write-Host ""
    Write-Host "Key Files:" -ForegroundColor Cyan
    Write-Host "  Report: $reportFile"
    Write-Host "  Log: $logFile"
    Write-Host "  CSVs: $csvOutputDir"
    Write-Host ""
} catch {
    Write-Host "[ERROR] Validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
