# Quick Test: Parallel Architecture Validation

**Goal:** Verify the new orchestrator runs UPSVF and ILAS stages correctly in parallel

## Test Setup

**Estimated time:** 30–45 minutes (depends on AQUA response times)

```powershell
# Set test output directory (use a temporary folder to isolate from production)
$testDir = "C:\Temp\NVLH_Parallel_Test_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-Item -Path $testDir -ItemType Directory -Force | Out-Null

# Navigate to scripts folder
cd C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\data-pulling\weekly-aqua-pull
```

## Test 1: Basic Parallel Run (UPSVF + ILAS)

```powershell
.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory $testDir `
  -LastNDaysTestEnd 1
```

**Expected output:**
```
[START] UPSVF pull stage...
[DONE] UPSVF pull completed: C:\Temp\...\Vmin_NVLHM66A0H30N00S623_WW25_2026_clean.csv (XXXX rows)

[START] ILAS pull stage (parallel job)...
[DONE] ILAS pull completed: C:\Temp\...\ILAS_Vmin_Summary_WW25_2026.csv (XXX rows)

[START] Merge stage...
[DONE] Merge completed: C:\Temp\...\Vmin_NVLHM66A0H30N00S623_WW25_2026_merged.csv (XXXX rows)

FINAL OUTPUT: C:\Temp\...\Vmin_NVLHM66A0H30N00S623_WW25_2026_merged.csv
```

**Verify:**
- ✅ Manifest JSON created at `$testDir\stage_manifest.json`
- ✅ All three stages show `"status": "SUCCESS"`
- ✅ UPSVF CSV exists with row count > 0
- ✅ ILAS CSV exists with row count > 0
- ✅ Merged CSV row count equals UPSVF row count (all UPSVF rows preserved)

```powershell
# Check manifest
Get-Content -LiteralPath "$testDir\stage_manifest.json" | ConvertFrom-Json | ConvertTo-Json

# Check UPSVF row count
(Import-Csv -LiteralPath "$testDir\Vmin_*_clean.csv" -First 1 | Measure-Object).Count

# Check merged row count
(Import-Csv -LiteralPath "$testDir\Vmin_*_merged.csv" -First 1 | Measure-Object).Count
```

---

## Test 2: UPSVF-Only Run (Skip ILAS)

```powershell
$testDir2 = "C:\Temp\NVLH_Parallel_Test_UPSVF_Only_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-Item -Path $testDir2 -ItemType Directory -Force | Out-Null

.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory $testDir2 `
  -SkipIlasStep
```

**Expected output:**
```
[SKIP] ILAS step skipped by parameter
[SKIP] Merge skipped (ILAS step skipped)

Overall Status: SUCCESS
```

**Verify:**
- ✅ `ilas_pull` stage shows `"status": "SKIPPED"`
- ✅ `merge` stage shows `"status": "SKIPPED"`
- ✅ Only UPSVF CSV created (no merged CSV)

---

## Test 3: Resumption (Retry ILAS After Failure)

**Scenario:** Simulate ILAS failure, then retry just ILAS stage

```powershell
# First run (may or may not fail, that's okay)
$testDir3 = "C:\Temp\NVLH_Parallel_Test_Resume_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-Item -Path $testDir3 -ItemType Directory -Force | Out-Null

.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory $testDir3

# Check manifest
$manifest = Get-Content -LiteralPath "$testDir3\stage_manifest.json" | ConvertFrom-Json
$manifest.stages

# Now manually mark ILAS as PENDING (simulate recovery scenario)
$manifest.stages.ilas_pull.status = "PENDING"
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath "$testDir3\stage_manifest.json"

# Re-run with ForceRestartStage (should skip UPSVF, only retry ILAS)
Write-Host "=== RETRYING ILAS STAGE ===" -ForegroundColor Yellow
.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory $testDir3 `
  -ForceRestartStage "ilas_pull"
```

**Expected behavior:**
- ✅ First run: All stages run
- ✅ Second run: `[SKIP] UPSVF stage already completed` (uses cached UPSVF)
- ✅ Second run: `[START] ILAS pull stage` (retries ILAS)
- ✅ Manifest timestamps show two run attempts

**Verify resumption time savings:**
```powershell
$m = Get-Content "$testDir3\stage_manifest.json" | ConvertFrom-Json
Write-Host "UPSVF duration: $(New-TimeSpan ($m.stages.upsvf_pull.start_time) ($m.stages.upsvf_pull.end_time) | Select-Object -ExpandProperty TotalSeconds) seconds"
Write-Host "ILAS duration: $(New-TimeSpan ($m.stages.ilas_pull.start_time) ($m.stages.ilas_pull.end_time) | Select-Object -ExpandProperty TotalSeconds) seconds"
Write-Host "Total: $(New-TimeSpan ($m.start_time) (Get-Date) | Select-Object -ExpandProperty TotalSeconds) seconds"
```

---

## Test 4: Timeout Behavior (Long-Running ILAS)

**Scenario:** Monitor 30-minute timeout if ILAS query hangs

```powershell
# Start a run and observe console
$testDir4 = "C:\Temp\NVLH_Parallel_Test_Timeout_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-Item -Path $testDir4 -ItemType Directory -Force | Out-Null

$startTime = Get-Date
.\run_upsvf_ilas_parallel.ps1 `
  -OutputDirectory $testDir4

$endTime = Get-Date
Write-Host "Total time: $((New-TimeSpan $startTime $endTime).TotalSeconds) seconds"
```

**If ILAS hangs:**
- ✅ Orchestrator waits ~30 minutes
- ✅ After 30 minutes, ILAS job is stopped
- ✅ Console shows: `[FAILED] ILAS pull timed out after 30 minutes`
- ✅ Manifest shows: `"status": "FAILED"`, `"error": "ILAS pull timed out..."`

---

## Test 5: Validation - Compare With Legacy Script

**Goal:** Verify new architecture produces equivalent outputs to old sequential script

```powershell
# Run new parallel architecture
$parallelDir = "C:\Temp\NVLH_Parallel_Compare_$(Get-Date -Format yyyyMMdd_HHmmss)"
New-Item -Path $parallelDir -ItemType Directory -Force | Out-Null

.\run_upsvf_ilas_parallel.ps1 -OutputDirectory $parallelDir

# Optional: Also run old script for comparison (if you want to keep it)
# $legacyDir = "C:\Temp\NVLH_Legacy_Compare_$(Get-Date -Format yyyyMMdd_HHmmss)"
# New-Item -Path $legacyDir -ItemType Directory -Force | Out-Null
# .\aqua_nvlh_weekly_pull.ps1 -OutputDirectory $legacyDir

# Compare row counts
$parallelMerged = Import-Csv -LiteralPath (Get-ChildItem $parallelDir -Filter "*_merged.csv" | Select-Object -First 1 -ExpandProperty FullName)
Write-Host "Parallel merged row count: $($parallelMerged.Count)"

# Compare column counts
$parallelCols = $parallelMerged[0].PSObject.Properties.Count
Write-Host "Parallel merged column count: $parallelCols"

# Spot check: verify no UPSVF rows were lost
$upsvfOnly = Import-Csv -LiteralPath (Get-ChildItem $parallelDir -Filter "*_clean.csv" | Select-Object -First 1 -ExpandProperty FullName)
Write-Host "UPSVF clean row count: $($upsvfOnly.Count)"
Write-Host "Rows match: $(if ($parallelMerged.Count -eq $upsvfOnly.Count) { 'YES ✓' } else { 'NO ✗' })"
```

---

## Cleanup

```powershell
# Remove test directories when done
Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $testDir2 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $testDir3 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $testDir4 -Recurse -Force -ErrorAction SilentlyContinue
```

---

## Expected Stage Manifest for Successful Run

```json
{
  "run_id": "20260623_150000",
  "start_time": "2026-06-23T15:00:00Z",
  "stages": {
    "upsvf_pull": {
      "status": "SUCCESS",
      "start_time": "2026-06-23T15:00:00Z",
      "end_time": "2026-06-23T15:05:30Z",
      "output_csv": "C:\\Temp\\...\\Vmin_NVLHM66A0H30N00S623_WW25_2026_clean.csv",
      "rows": 10525,
      "error": null
    },
    "ilas_pull": {
      "status": "SUCCESS",
      "start_time": "2026-06-23T15:00:15Z",
      "end_time": "2026-06-23T15:18:45Z",
      "output_csv": "C:\\Temp\\...\\ILAS_Vmin_Summary_WW25_2026.csv",
      "rows": 358,
      "error": null
    },
    "merge": {
      "status": "SUCCESS",
      "start_time": "2026-06-23T15:18:50Z",
      "end_time": "2026-06-23T15:19:05Z",
      "output_csv": "C:\\Temp\\...\\Vmin_NVLHM66A0H30N00S623_WW25_2026_merged.csv",
      "rows": 10525,
      "error": null
    }
  }
}
```

**Note:** UPSVF and ILAS run in parallel, so `ilas_pull.start_time` is shortly after `upsvf_pull.start_time` (not after `end_time`). This demonstrates parallel execution.

---

## Troubleshooting

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| `"UPSVF script not found"` | Path resolution failed | Explicitly set `-UpsvfScriptPath` |
| `"ILAS summary output was not generated"` | ILAS query returned empty | Check UPSVF CSV has VisualID+Lot columns; check AQUA ILAS report availability |
| `Merge skipped` | ILAS status is not SUCCESS | Check ilas_pull error in manifest |
| Stage marked PENDING but script doesn't run | Manifest corrupted | Delete manifest JSON, re-run |
| `"ILAS pull timed out"` | Query hangs or AQUA slow | Increase timeout in orchestrator (search for `1800` seconds) or optimize AQUA query |

