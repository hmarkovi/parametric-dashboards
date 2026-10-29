---
name: vf-curve-optimization
description: Pick the best subset of test frequencies (testing points) from a high-resolution VF (Vmin-vs-Frequency) sweep CSV to minimize interpolation penalty, and render an interactive self-contained HTML tool. Trigger on "VF curve optimization", "testing point selection", "VF optimization tool".
---

## Purpose

Replicates (in a dependency-free HTML/JS tool instead of JMP) the analysis
described in `VF Optimization Tool.docx` (Amit Menth, Tamar Segal
Rosenthal): given a high-resolution Vmin-vs-Frequency sweep (every data
point measured per unit), choose which frequencies to keep as daily
production "testing points" and estimate the rest by linear interpolation,
while minimizing the interpolation error ("penalty") at the dropped
frequencies.

Implemented in `Scripts/parametric-analysis/vf-curve-optimization/` (path
relative to the `parametric-dashboards` folder, which is its own root with
its own `Scripts/` and `.github/skills/`).

## Scope

Includes:
- Parsing a high-res Vmin sweep CSV (`Visual_ID`, `Test_Name`,
  `Frequency_GHz`, `Vmin_V`, `At_Sweep_Floor`, optional `Core` columns)
  grouped by `Test_Name` (domain).
- Pulling fresh per-unit, per-core VMIN data directly from TRACE
  (`get_vmin` Final mode) across one or more CLASS jobs and merging it
  into the tool's CSV schema via `merge_trace_vmin_to_vf_csv.py` (see
  "TRACE Data Pull Workflow" below).
- Generating one self-contained HTML tool (no external JS/CSS, no
  third-party Python packages) with:
  - A domain selector (if the CSV has more than one `Test_Name`).
  - Checkboxes per frequency to mark "testing" (0 penalty) vs
    "interpolated" points. The lowest and highest frequency are always
    forced on (no extrapolation).
  - Live Actual-vs-Interpolated Vmin and Penalty box-plot charts (full
    whiskers, mean line), rendered in plain SVG.
  - An "Auto" (exhaustive combinatorial search, capped at 50,000
    combinations) and "Semi-Auto" (greedy, fast) search for the best
    testing-point set of a user-chosen size K, ranked by **magnitude** of
    General Mean and General Max penalty (both shown side by side).
  - A "Details" button that snapshots the current selection's stats.
- Persisting the source CSV in-repo under `vf-curve-optimization/data/`
  for reruns without depending on the network share/TRACE staying
  available.

Does not include: non-linear interpolation. **Per-core handling**: when
the CSV has a `Core` column, each `(Visual_ID, Core)` pair is treated as
its own independent sample ("unit" in the JS) sharing the domain's
frequency axis - cores are NOT reduced/merged into one value per unit.
This is deliberate (user-confirmed 2026-10-29): Vmin can differ
meaningfully core-to-core, and treating each core as an extra independent
data point increases statistical assurance of the box-plot/penalty stats
without turning cores into separate domains. CSVs without a `Core` column
(e.g. the original GT dataset) still work unchanged (core defaults to `""`).

## Inputs

- `csv_path`: path to the high-resolution Vmin sweep CSV. Reference copies
  of datasets used so far are saved under `vf-curve-optimization/data/`:
  - `ACM_Vmin_All_Units.csv` - GT domain, single program, true per-unit
    dense sweep (source: `\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-AX\Analysis\2026_45_GT_High resultion MAV\ACM_Vmin_All_Units.csv`).
  - `HX28C_DenseVF_validation_2lots_percore.csv` - CR/CCF/AT domains, same
    physical units re-tested across 13 staggered-frequency DOE lots
    (VPOs), pulled from TRACE and merged with `Core` column preserved
    (see TRACE Data Pull Workflow below). Validation subset (2 of 13
    lots) as of 2026-10-29.
- `-o` / `--output`: output HTML path (default: `<csv-stem>_vf_curve_optimizer.html` next to the CSV).

## TRACE Data Pull Workflow (e.g. HX28C Dense VF DOE)

When the source data comes from a Dense-VF-style DOE where the SAME
physical units are re-tested across multiple CLASS jobs/lots (each lot
reprogramming the VF-corner frequencies to different GHz values):

1. `find_jobs` on the VPO/lot list to resolve CLASS job names.
2. `get_vmin` `ListDomains` on one job to discover domain names (e.g.
   `CR`, `CCF`, `AT` for Core/CCF/Atom).
3. For **each (job, domain) pair separately**, call `get_vmin` mode
   `Final` (no `visualIds` filter -> all units). **Important**: passing
   multiple jobs in one `get_vmin` call does NOT union a unit's data
   across jobs - it only returns one job's result per unit. You must
   pull one job at a time and merge the raw CSVs yourself.
4. Run `merge_trace_vmin_to_vf_csv.py <raw_csv_1> <raw_csv_2> ... -o <output.csv>`
   on all the raw `get_vmin` CSVs (one per job x domain). It:
   - Keeps each `(Domain, VisualId, CoreNumber)` as an independent row
     (no cross-core reduction - see Per-core handling above).
   - Averages duplicate `(Domain, VisualId, Core, Frequency)` points that
     recur across overlapping DOE lots (deliberate QA cross-check
     frequencies) - confirmed with user 2026-10-29.
   - Skips blank `Value` rows (untested/bypassed corner-core).
   - Writes the tool's standard schema with a `Core` column.
5. Run `build_vf_curve_optimizer.py` on the merged CSV as usual.

Raw `get_vmin` Final-mode CSV columns (for reference): `DomainName,
VisualId,FlowIndex,FinalFlowIndex,ValueType,CornerName,CoreNumber,
CoreName,Value,Frequency,SetterInstancePath,Pattern,IsFinalValueForCorner,
BaseValue,Ticks`. `Frequency` is in Hz - divide by 1e9 for GHz. This mode
has no sweep-floor/censoring field (unlike the GT CSV's `At_Sweep_Floor`)
- acceptable to leave blank/False for TRACE-sourced datasets unless a
future need requires pulling per-instance floor/status data separately.

## How to Run

```powershell
python "Scripts/parametric-analysis/vf-curve-optimization/build_vf_curve_optimizer.py" `
  "Scripts/parametric-analysis/vf-curve-optimization/data/ACM_Vmin_All_Units.csv"
```

Open the resulting `*_vf_curve_optimizer.html` directly in a browser - all
computation (interpolation, brute-force search) runs client-side in JS.

## Algorithm Notes (ported from the JMP tool doc)

- `Penalty = Interpolated - Actual` at every frequency (0 by construction
  at checked/testing frequencies). Linear interpolation only, between the
  two nearest checked frequencies.
- `Mean_Penalty_by_Freq[f]` = mean of `Penalty` across units at frequency
  `f` (includes the trivial zeros at testing frequencies, by design -
  matches the JMP "Col Mean" formula column).
- `General Mean` / `General Max` = mean / max of `Mean_Penalty_by_Freq`
  across all frequencies for the current selection.
- **Ranking deviation from a literal transcription**: the JMP doc text
  didn't specify the Auto/Semi-Auto ranking direction. A large *negative*
  General Mean/Max (interpolation underestimates true Vmin - the unsafe
  direction) is not "better" than a small negative one, so results are
  ranked by **absolute value**, not raw ascending value. The signed value
  is still shown for transparency.
- "Exclude sweep-floor-capped points" toggle (default on): `Vmin_V` rows
  flagged `At_Sweep_Floor = True` are censored (true Vmin may be lower
  than recorded) and are excluded from penalty stats by default - this is
  a reasonable approximation of the JMP "Clean" button since its exact
  logic wasn't present in the extracted doc text (image-only section).

## Core Rules

1. Zero third-party dependencies - CSV parsing/JSON embedding in Python
   stdlib only; all interactivity/search/rendering in plain JS/SVG in the
   generated HTML (see `/memories/python-environment.md` for why: no
   internet access to pypi for numpy/pandas on this machine).
2. Endpoints (min/max frequency) are always forced as testing points -
   never let the search drop them (avoids extrapolation).
3. Whiskers on box plots are full observed min/max, consistent with the
   `dts-analysis` skill's convention elsewhere in this repo - never 1.5*IQR.
4. Auto search is exhaustive only up to 50,000 combinations; above that it
   falls back to the greedy Semi-Auto search and says so in the UI.
5. Keep the input CSV copy in `vf-curve-optimization/data/` in sync if the
   user supplies a newer/different high-res sweep for the same study.
