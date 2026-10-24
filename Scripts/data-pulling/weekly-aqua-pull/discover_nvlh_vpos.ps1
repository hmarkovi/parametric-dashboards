<#
.SYNOPSIS
Discover NVLH VPO names that ran in the past 24 hours (or custom date range).

.DESCRIPTION
Queries AQUA for unique Visual Process Operation (VPO) names where:
- Program Name matches NVLHM* (NVLH case study)
- Data collected within past N days

Output is a comma-separated VPO list suitable for FilterSet input to UPSVF and ILAS scripts.

.PARAMETER LastNDaysTestEnd
Number of days back from today to search (default: 1 = past 24 hours)

.PARAMETER OutputFile
Optional: Save VPO list to CSV file. If provided, writes VPO names with row counts.

.PARAMETER MinRowThreshold
Only include VPO if it has at least this many rows (default: 1)

.EXAMPLE
# Get VPOs from past 24 hours
.\discover_nvlh_vpos.ps1

# Get VPOs from past 7 days and save to CSV
.\discover_nvlh_vpos.ps1 -LastNDaysTestEnd 7 -OutputFile "C:\Temp\nvlh_vpos_ww25.csv"

.NOTES
Author: NVLH Parametric Analysis
Requires: AQUA CLI installed and accessible
#>

param(
    [int] $LastNDaysTestEnd = 1,
    [string] $OutputFile = "",
    [int] $MinRowThreshold = 1,
    [int] $MaxVisualUnits = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Resolve-AquaExePathForAutomation {
    <#
    .SYNOPSIS
    Resolve AQUA CmdLine executable with local caching for automation.
    #>
    [string] $localAquaExePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "NVLH\AquaCmdLine\AquaCmdLine.exe"
    
    if (Test-Path -LiteralPath $localAquaExePath) {
        return $localAquaExePath
    }
    
    [string] $uncPath = "\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe"
    
    if (-not (Test-Path -LiteralPath $uncPath)) {
        throw "AquaCmdLine.exe not found at: $localAquaExePath or $uncPath"
    }
    
    Write-Host "AquaCmdLine.exe not cached; copying from UNC..."
    [string] $cacheDir = Split-Path -Parent $localAquaExePath
    New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $uncPath -Destination $localAquaExePath -Force
    Unblock-File -LiteralPath $localAquaExePath -ErrorAction SilentlyContinue
    
    return $localAquaExePath
}

function Invoke-AquaVpoDiscoveryQuery {
    <#
    .SYNOPSIS
    Query AQUA for unique RCS_PROCESSSTEP (VPO) values matching filter criteria.
    Uses "Program Name"=NVLHM* filter to get NVLH products only.
    #>
    param(
        [string] $AquaExePath,
        [int] $LastNDays,
        [int] $MaxVisualUnits
    )
    
    Write-Host "[INFO] Querying AQUA for NVLH data with RCS_PROCESSSTEP from past $LastNDays day(s)..." -ForegroundColor Cyan
    
    # Calculate date range
    $endDate = (Get-Date).ToString("yyyy-MM-dd")
    $startDate = (Get-Date).AddDays(-$LastNDays).ToString("yyyy-MM-dd")
    
    # Run AQUA query to pull all records with RCS_PROCESSSTEP 
    # We'll extract unique values from the CSV
    # Filter: Program Name = NVLHM*
    $aquaArgs = @(
        "/report:Device_Tracking",
        "/filter:Program Name`=NVLHM*",
        "/filter:RCS_PROCESSSTEP!`=",
        "/datefrom:$startDate",
        "/dateto:$endDate",
        "/server:GER",
        "/csv",
        "/limit:$MaxVisualUnits"
    )
    
    Write-Host "[DEBUG] AQUA args: $($aquaArgs -join ' ')" -ForegroundColor Gray
    
    # Run query and capture output
    $output = & $AquaExePath $aquaArgs 2>&1
    
    if ($LASTEXITCODE -ne 0 -or $output -match "ERROR|error|Index was outside") {
        Write-Host "[WARN] AQUA query returned error or unexpected output" -ForegroundColor Yellow
        Write-Host "Output sample: $($output | Select-Object -First 5)" -ForegroundColor Gray
    }
    
    return $output
}

function Extract-UniqueVpos {
    <#
    .SYNOPSIS
    Parse AQUA Device_Tracking CSV output and extract unique RCS_PROCESSSTEP values.
    #>
    param(
        [string[]] $AquaOutput,
        [int] $MinRowThreshold
    )
    
    # Filter non-empty, non-header, non-error lines
    $validLines = $AquaOutput | 
        Where-Object { 
            $_ -and 
            -not $_.StartsWith("#") -and 
            -not $_.StartsWith("====") -and 
            -not $_.StartsWith("---") -and
            -not $_.StartsWith("[") -and
            -not $_ -match "ERROR|error|Index was"
        }
    
    # Collect potential VPO names (first non-empty lines after headers)
    $vpos = @{}
    $csvHeaderLine = $null
    $rcsProcessStepColumnIndex = -1
    
    foreach ($line in $validLines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        
        # Try to detect header row (contains "RCS_PROCESSSTEP")
        if ($line -match "RCS_PROCESSSTEP" -and $null -eq $csvHeaderLine) {
            $csvHeaderLine = $line
            # Parse header to find RCS_PROCESSSTEP column index
            $headers = $csvHeaderLine -split ',' | ForEach-Object { $_.Trim('"').Trim() }
            $rcsProcessStepColumnIndex = [Array]::IndexOf($headers, "RCS_PROCESSSTEP")
            Write-Host "[DEBUG] Found header: $csvHeaderLine" -ForegroundColor Gray
            Write-Host "[DEBUG] RCS_PROCESSSTEP column index: $rcsProcessStepColumnIndex" -ForegroundColor Gray
            continue
        }
        
        # If we found the header, extract values from data rows
        if ($rcsProcessStepColumnIndex -ge 0) {
            $fields = $line -split ',' | ForEach-Object { $_.Trim('"').Trim() }
            if ($fields.Count -gt $rcsProcessStepColumnIndex) {
                $vpoValue = $fields[$rcsProcessStepColumnIndex]
                if ($vpoValue -and $vpoValue -notmatch "^(RCS_PROCESSSTEP|====)") {
                    # Only add if it looks like a real VPO name (alphanumeric + underscore)
                    if ($vpoValue -match "^[A-Z0-9_]+$") {
                        if (-not $vpos.ContainsKey($vpoValue)) {
                            $vpos[$vpoValue] = 0
                        }
                        $vpos[$vpoValue]++
                    }
                }
            }
        }
        # If no header found yet, try to extract as simple line
        elseif ($csvHeaderLine -eq $null -and $trimmed -match "^[A-Z0-9_]+$") {
            # Simple fallback: assume each line is a VPO name if no CSV header found
            if (-not $vpos.ContainsKey($trimmed)) {
                $vpos[$trimmed] = 0
            }
            $vpos[$trimmed]++
        }
    }
    
    if ($vpos.Count -eq 0) {
        Write-Host "[WARN] No VPO values extracted from AQUA output" -ForegroundColor Yellow
        return @()
    }
    
    # Convert to objects with Name property
    $result = $vpos.GetEnumerator() |
        Sort-Object -Property Name |
        ForEach-Object {
            [PSCustomObject]@{Name = $_.Key; Value = $_.Value}
        }
    
    return $result
}

function Format-VpoList {
    <#
    .SYNOPSIS
    Format VPO list as comma-separated string for FilterSet input.
    #>
    param(
        [Object[]] $VpoGroups
    )
    
    $vpoNames = $VpoGroups | Select-Object -ExpandProperty Name
    return $vpoNames -join ","
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "NVLH VPO Discovery Script" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    # Resolve AQUA executable
    $aquaExePath = Resolve-AquaExePathForAutomation
    Write-Host "[DONE] AquaCmdLine.exe resolved: $aquaExePath" -ForegroundColor Green
    
    # Query AQUA for VPOs
    $aquaOutput = Invoke-AquaVpoDiscoveryQuery -AquaExePath $aquaExePath -LastNDays $LastNDaysTestEnd -MaxVisualUnits $MaxVisualUnits
    
    if ($aquaOutput.Count -eq 0) {
        Write-Host "[WARN] No data returned from AQUA query" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Discovered VPOs: (empty)"
        if ($OutputFile) {
            Set-Content -LiteralPath $OutputFile -Value "VPO,RowCount"
        }
        exit 0
    }
    
    # Extract unique VPOs
    $vpoGroups = Extract-UniqueVpos -AquaOutput $aquaOutput -MinRowThreshold $MinRowThreshold
    
    if ($vpoGroups.Count -eq 0) {
        Write-Host "[WARN] No VPOs found matching filter criteria" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Discovered VPOs: (none)"
        if ($OutputFile) {
            Set-Content -LiteralPath $OutputFile -Value "VPO,RowCount"
        }
        exit 0
    }
    
    # Format output
    $vpoList = Format-VpoList -VpoGroups $vpoGroups
    $vpoCount = @($vpoGroups).Count
    $totalRows = ($vpoGroups | Measure-Object -Property Value -Sum).Sum
    
    Write-Host "[DONE] VPO discovery complete" -ForegroundColor Green
    Write-Host "  Unique VPOs found: $vpoCount" -ForegroundColor Green
    Write-Host "  Total rows: $totalRows" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Discovered VPOs:" -ForegroundColor Cyan
    $vpoGroups | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.Value) rows)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "VPO List (comma-separated):" -ForegroundColor Cyan
    Write-Host $vpoList -ForegroundColor White
    Write-Host ""
    
    # Save to file if requested
    if ($OutputFile) {
        Write-Host "[INFO] Saving VPO list to: $OutputFile" -ForegroundColor Cyan
        
        $csvContent = @("VPO,RowCount")
        $csvContent += $vpoGroups | ForEach-Object {
            "$($_.Name),$($_.Value)"
        }
        
        $csvContent | Set-Content -LiteralPath $OutputFile
        Write-Host "[DONE] VPO list saved" -ForegroundColor Green
    }
    
    # Export variables for downstream scripts
    $env:NVLH_VPO_LIST = $vpoList
    $env:NVLH_VPO_COUNT = $vpoCount
    
    Write-Host ""
    Write-Host "Environment variables set:" -ForegroundColor Cyan
    Write-Host "  `$env:NVLH_VPO_LIST = $vpoList" -ForegroundColor Gray
    Write-Host "  `$env:NVLH_VPO_COUNT = $vpoCount" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Ready for parallel UPSVF + ILAS pulls" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green

}
catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
