---
name: ilas
description: Build ILAS Vmin detail and summary CSVs from AQUA stacked TEST_NAME/TEST_RESULT data with strict VMIN parsing, VMINFWCFG positional mapping, FMIN separation, and FMIN exclusion from main F-corner aggregation.
---

## Purpose

Use this skill to run or troubleshoot ILAS Vmin analysis logic implemented in Scripts/aqua_nvlh_ilas_vmin_analysis.ps1.

## Scope

This skill covers ILAS extraction and transformation only.

It includes:
- Parsing stacked AQUA rows by VisualID, lot/class-lot, base test, and companion rows (_VMINFWCFG, _DTS, _LP)
- Strict first-pipe Vmin parsing aligned by index to VMINFWCFG order
- Preservation of VMINFWCFG semantics in output columns: domain, frequency corner, flow, frequency, core
- Separate handling of FMIN test instances (test-name-derived frequency, separate FMIN columns)
- Exclusion of FMIN test instances from main F-corner aggregation

This skill does not include UPSVF merge orchestration.

## Inputs

Typical inputs:
- AQUA connectivity: AquaExe, AquaServer, IlasReportPath, ProgramPattern, Operations
- Time window: LastNDaysTestEnd
- Optional local raw file: RawInputFile
- OutputDirectory

## Output Artifacts

- ILAS_Vmin_Detail_<suffix>.csv
- ILAS_Vmin_Summary_<suffix>.csv

Summary rows are keyed by VisualID and LotFromFs.

## Core Rules

1. Parse only VMIN-family tests.
2. Require VMINFWCFG row presence for mapping.
3. Parse Vmin values from first pipe segment only.
4. Map Vmin values to VMINFWCFG entries by index.
5. Use domain numeric suffix as physical core when present.
6. Preserve decimal frequency formatting in column names.
7. Parse FMIN frequency from test instance (_FMIN_0400 -> 0.400 GHz).
8. Keep FMIN outputs in separate columns.
9. Exclude FMIN test rows from main F-corner aggregation.

## Example Invocation

PowerShell:

& ".\Scripts\parametric-analysis\ilas\aqua_nvlh_ilas_vmin_analysis.ps1" `
  -IlasReportPath "hmarkovi\ILAS_VMIN_DTS" `
  -ProgramPattern "NVLHM66*" `
  -OutputDirectory "R:\Products\NVL\NVL-H\Weekly Runs"
