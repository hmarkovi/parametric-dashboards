---
name: trace-parametric-data-tool
description: Build a Classhot TRACE parametric bridge table for VMIN, SICC, DTS, and Sort lot geometry (plus FunctionalBin when available), with ILAS/GSDS-aligned output naming.
---

## Quick Prompt

Use this single prompt:

`Use trace-parametric-data-tool: <request>`

Examples:
- `Use trace-parametric-data-tool: pull Classhot test results for lot P6380240 and build bridge table`
- `Use trace-parametric-data-tool: run bridge parser on trace-test-results CSV and export final wide table`
- `Use trace-parametric-data-tool: run real-case all Classhot lots for NVLAX62A0H25* and save outputs to R:\Products\NVL\NVL-AX\Weekly data pull\Trace based data`

## Purpose

Use this skill to build a Classhot-only parametric bridge from TRACE test-result rows into a POR-compatible wide table for weekly ILAS gap coverage.

## Scope

This skill covers:
- Classhot job discovery and test-result pull from TRACE
- VMIN companion-row parsing (`_VMIN_`, `_VMINFWCFG`, `_DTS`, `_LP`) with winner selection
- DTS reduction rules (domain-aware for core/atom, global max for hub/GT)
- SICC parsing from caret-delimited payloads and test-name fallback patterns
- SICC source-name-aware die-token mapping (`PP_SICC_U1PUx`, `GTSICC`, `SASICC`) with domain fallback
- Sort fuse parsing from `FUS_UNITINFO_*...MAIN_FUSE_READ` into per-die suffix columns
- FunctionalBin pass-through when source rows include a supported bin field
- Final one-row-per-VisualID+ClasshotLot wide table output with ILAS/GSDS naming

This skill does not include:
- CDYN extraction/analysis in this Classhot bridge phase
- Silent broadening of user filters

## Required Parameter Conventions

Use exact parameter names:
- `jobs`: pass exactly as returned from `find_jobs`
- `visualIds`: array for unit filtering
- `testInstanceNames`: array for instance filtering

Do not substitute synonyms like `unitId`, `visualId`, or `units`.

## Core Workflow

1. Resolve Classhot jobs with `find_jobs` using user filters.
2. For large weekly NVLAX62A0H25 scopes, exclude lots ending with `MV` and split by lot prefix:
	- `Y*` -> IDC
	- `P*` -> PG
3. Pull stacked test-result rows with `get_test_results` for:
	- Core parametric set: `SICC`, `_VMIN_`, `_VMINFWCFG`, `_DTS`, `_LP`, `FUS_UNITINFO_HXX`, `FUS_UNITINFO_GXX`, `FUS_UNITINFO_CXX`
	- Bin probe set: `FUNCTIONAL_BIN`, `SOFT_BIN`, `HBIN`, `BIN`
4. Merge pulled rows, dedupe by `JobName+TestName+VisualId+Value`.
5. Run parser script: `Scripts/parametric-analysis/ilas/trace_classhot_parametric_bridge.ps1`.
6. Safe mode gates (enabled by default in real-case runner):
	- Write stage lot-coverage manifests: `find_jobs_coverage.json`, `chunk_coverage.json`, `raw_coverage.json`, `merged_coverage.json`
	- If expected lots are missing at pull stage, retry missing-lot jobs only (up to configured attempts)
	- Fail fast if raw/merged coverage still misses required lots
7. Optional CCF gate (bridge):
	- `-RequireCcfData` with `-RequiredCcfLots` and `-RequiredCcfCorners` (default corners: `F1,F2,F3,F4,F7`)
	- Emit diagnostics: `<prefix>_violations_<timestamp>.csv`, `<prefix>_ccf_diagnostics_<timestamp>.csv`
6. Export site-specific artifacts:
	- IDC: `trace_classhot_bridge_real_nvlax62a0h25_idc_only_<stage/final>_<timestamp>.csv`
	- PG: `trace_classhot_bridge_real_nvlax62a0h25_pg_only_<stage/final>_<timestamp>.csv`
8. Join authoritative IDC and PG final CSVs into one combined final CSV after both site phases complete.

## Source Constraints

- Bridge scope defaults to CLASSHOT operations only.
- Sort geometry requires `FUS_UNITINFO_*...MAIN_FUSE_READ` rows.
- `FunctionalBin` remains blank when source rows contain no supported bin column.

If the requested source/tool combination is unsupported, report that directly.

## Reporting Rules

- Preserve returned names exactly (test names, instance paths, field values).
- Report counts accurately when `totalCount` differs from displayed rows.
- If a tool fails, report the error as returned; do not fabricate fallback values.

## Fast Mapping

- "Build Classhot bridge for lot X" -> `find_jobs` + `get_test_results` + bridge parser script
- "Need Sort lot/wafer/X/Y too" -> include `FUS_UNITINFO_*...MAIN_FUSE_READ` in `testInstanceNames`
- "Need FunctionalBin in final" -> also pull `FUNCTIONAL_BIN`/`SOFT_BIN`/`HBIN`/`BIN` test instances
- "Run all NVLAX62A0H25* Classhot lots" -> use `find_jobs` full CSV list, exclude `*MV`, split IDC/PG, finalize site outputs independently, then join final CSVs

## Recovery And Publication

- Site phases are allowed to complete independently.
- If IDC final already exists, reuse it and continue with PG instead of rerunning IDC.
- Publish one combined final CSV only from authoritative IDC and PG finals.
- Inventory the output root before cleanup; archive stale runs rather than deleting first.
- In safe mode, suppress joined publish if site coverage gates fail.

## Open in TRACE

When validating on a pulled TRACE CSV, run:

```powershell
.
\Scripts\parametric-analysis\ilas\trace_classhot_parametric_bridge.ps1 `
	-InputCsvPath "<trace_test_results.csv>" `
	-LotFilter "P6380240"
```

Expected outputs:
- `<prefix>_vmin_stage_<timestamp>.csv`
- `<prefix>_sicc_stage_<timestamp>.csv`
- `<prefix>_final_<timestamp>.csv`

## Current Script References

- Bridge parser: `Scripts/parametric-analysis/ilas/trace_classhot_parametric_bridge.ps1`
- Real-case runner: `development/validation/run_trace_realcase_nvlax62a0h25.ps1`
- Split wrapper: `development/validation/run_trace_realcase_nvlax62a0h25_split_by_prefix.ps1`
- Output inventory: `development/validation/inventory_trace_output_root.ps1`
- Cleanup planner: `development/validation/plan_trace_output_cleanup.ps1`
- Final join helper: `development/validation/join_trace_bridge_finals.ps1`