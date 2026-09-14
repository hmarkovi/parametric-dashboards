# NVLH Parametric Rollup Automation Plan for GitHub Copilot

## 1. Objective

Build a repeatable analysis pipeline that reads one or more raw CSV files and automatically creates the analytical content needed for an NVLH-style parametric rollup presentation.

The automation must reproduce the **analytical intent and slide structure** of the reference presentation while allowing the chart styling to change. The reference PowerPoint will not be available to GitHub Copilot, so this document defines every required slide, chart, calculation, label, fallback, and validation rule.

The first implementation scope is based on these reference slides:

- Slide 4: Material characteristics
- Slide 13: Normalized SICC analysis
- Slide 16: Domain VF curve summary, generalized to one slide per domain

The output should preserve the supplied PowerPoint template, slide masters, page size, headers, footers, logos, and reserved layout areas. Chart graphics may be recreated using native PowerPoint charts, linked or embedded Excel charts, or generated vector/raster graphics. Prefer editable charts with embedded data.

---

## 2. Non-negotiable behavior

### 2.1 Preserve presentation format

1. Use the existing presentation as a template during actual execution.
2. Do not delete or modify slide master elements, footer text, page numbering, confidentiality marks, logos, or theme colors.
3. Replace only designated plot, table, annotation, and comment placeholders.
4. Keep the overall purpose and content allocation of each reference slide, even if individual chart styling changes.
5. Every generated slide must include a small data-status label:
   - `Data source: <file name>`
   - `Generated: <timestamp>`
   - `Population: <N unique units>`
   - `Normalization: UPM | Median | None`

### 2.2 Missing-data rule

If data required for a chart or table is absent from the raw CSV:

- Do not fabricate, interpolate, simulate, or silently substitute values.
- Omit the affected analysis computation.
- Keep the reserved chart area in the slide.
- Add the correct chart title.
- Place a centered placeholder message:

> DATA NOT AVAILABLE IN INPUT CSV  
> Missing fields: `<field list>`

- Use a light-gray background and dark-gray border for the placeholder.
- Record the omission in the run manifest.
- Continue generating all other available content.

Special UPM fallback:

- For Slide 4 material characteristics, keep the histogram even if UPM is absent. Omit only the SICC-vs-UPM scatter plot and keep its titled placeholder.
- For normalized SICC analysis, if domain UPM is unavailable, replace the SICC-vs-UPM chart with a **SICC distribution histogram using per-unit SICC V1 values**. Label the chart and slide clearly as `Median-based; UPM unavailable`.
- For VF curves, if UPM normalization is requested but UPM is missing, use median Vmin only when allowed by the run configuration. Otherwise keep the titled placeholder.

### 2.3 Unit-level integrity

Unless explicitly stated as median, quantile, percentage, or normalized output, each plotted point must represent one measured physical unit.

- Unit identity must remain traceable through a stable `UnitID` field.
- Do not average repeated unit measurements unless the aggregation rule is explicitly configured.
- If duplicate records exist for the same UnitID, product, domain, frequency, corner, test instance, and measurement, apply a configured duplicate policy and report it.
- Recommended default duplicate policy: use the latest valid measurement only if a reliable timestamp exists; otherwise flag duplicates and do not silently collapse them.

---

## 3. Recommended solution architecture

Use a configuration-driven pipeline so product names, domains, column aliases, comparison populations, targets, and slide selections can be changed without editing analysis code.

### 3.1 Suggested repository structure

```text
nvlh-parametric-rollup/
├── README.md
├── requirements.txt
├── config/
│   ├── analysis_config.yaml
│   ├── column_aliases.yaml
│   ├── domain_mapping.yaml
│   ├── upm_mapping.yaml
│   ├── limiter_mapping.yaml
│   └── slide_layout.yaml
├── data/
│   ├── raw/
│   ├── presi/
│   └── reference/
├── templates/
│   └── NVLH_Parametric_rollup_template.pptx
├── src/
│   ├── ingest.py
│   ├── normalize_schema.py
│   ├── validation.py
│   ├── population_filters.py
│   ├── metrics.py
│   ├── material_characteristics.py
│   ├── vf_curve.py
│   ├── sicc_analysis.py
│   ├── limiter_pareto.py
│   ├── temperature_analysis.py
│   ├── flow_matrix.py
│   ├── chart_writer.py
│   ├── ppt_writer.py
│   └── run_pipeline.py
├── tests/
├── output/
│   ├── charts/
│   ├── tables/
│   ├── analysis_data.xlsx
│   ├── run_manifest.json
│   └── NVLH_Parametric_rollup_generated.pptx
└── logs/
```

### 3.2 Preferred output design

Generate an intermediate Excel workbook named `analysis_data.xlsx` containing the exact filtered data behind every chart. This provides live hover values when charts are opened in Excel and allows charts to be embedded or linked in PowerPoint.

Recommended workbook sheets:

- `Run_Summary`
- `Data_Quality`
- `Material_CPU`
- `Material_GT`
- `Material_HUB`
- `SICC_Normalized`
- `SICC_PreSi_Comparison`
- one `<Domain>_VF` sheet per domain
- one `<Domain>_Vmin_UPM` sheet per domain
- one `<Domain>_Limiter` sheet per domain
- one `<Domain>_Temperature` sheet per domain
- one `<Product>_FlowMatrix` sheet per product

Charts in the final PowerPoint should preferably be native editable charts with embedded workbook data. If stable PowerPoint chart automation is not practical, create the chart in Excel, copy it to PowerPoint as an editable chart object, and retain the analytical workbook next to the PowerPoint.

---

## 4. Canonical input data model

The raw CSV may use different names. Map all available columns to the following canonical fields using `column_aliases.yaml`.

### 4.1 Required identity and grouping fields

| Canonical field | Purpose | Required for |
|---|---|---|
| `UnitID` | Stable unique unit identifier | all unit-level plots |
| `Product` | Product/population name, for example NVLH, NVLS, NVLHX | cross-product comparison |
| `DieType` | CPU/CDIE, GT, or HUB | material characteristics |
| `Domain` | Core, Ring/CCF, Atom, SA-Atom, GT, SAQ, NPU, etc. | all domain analyses |
| `Frequency_GHz` | Measured frequency operating point | VF, limiter, temperature, flow matrix |
| `Vmin_V` | Measured minimum voltage | VF and Vmin-vs-UPM |
| `TestProgram` | Class test-program identifier | scope and flow matrix |
| `Corner` | Corner name | temperature and flow matrix |
| `TestInstance` | Test-instance/content identifier | temperature and limiter analysis |

### 4.2 UPM fields

At least one of the following representations must be supported:

1. Long form:
   - `UPM_Name`
   - `UPM_Value`
2. Wide form:
   - one CSV column per UPM measurement

The pipeline must discover wildcard names after trimming whitespace and applying case-insensitive matching. It must not use fuzzy matching unless explicitly enabled.

### 4.3 SICC fields

| Canonical field | Purpose |
|---|---|
| `SICC_V1_A` | per-unit SICC V1 current, in amperes |
| `SICC_Domain` | domain associated with SICC measurement, if different from `Domain` |
| `SICC_TestInstance` | optional SICC measurement instance |
| `SICC_Temperature_C` | optional SICC measurement temperature |

### 4.4 Limiter fields

Support either a canonical classified field or raw test results from which the limiter can be calculated:

- `LimiterType`, with canonical values `Scan`, `Array`, `Functional`, `Other`, `Unknown`
- or per-content limiting Vmin fields that can be compared for the same unit/domain/frequency

If limiter classification cannot be derived reliably, create the titled placeholder and list the missing source fields.

### 4.5 Temperature fields

- `DTS_Temperature_C`
- `Corner`
- `Domain`
- `Frequency_GHz`
- `TestInstance`
- `UnitID`
- `Product`

### 4.6 PreSi comparison fields

PreSi data can be supplied in a separate CSV or a dedicated table with:

- `Product`
- `Domain`
- `Frequency_GHz`
- `PreSi_Vmin_V` and/or `PreSi_SICC_A`
- optional process/corner/model identifiers

Do not compare populations with incompatible definitions without displaying a warning. The reference Core slide warns that NVLH/NVLS and NVLHX process speed and Vmin normalization are not on the same scale. Carry an equivalent warning whenever configured populations use different process or normalization definitions.

---

## 5. Configuration files

### 5.1 `upm_mapping.yaml`

```yaml
material_characteristics:
  CPU:
    aliases: [CPU, CDIE]
    pattern: "UPM_0107_DPMH156P48ULVTINVD4_FULLDIE_0950_MED_SORT_U1.U5"
    match: exact_case_insensitive
    entitlement:
      temperature_C: 20
      target_MHz: 9154
  GT:
    aliases: [GT]
    pattern: "UPM_2007_DPMH130P48ULVTINVD4_FULLDIE_0950_MED_*"
    match: wildcard_case_insensitive
    target: 7694
  HUB:
    aliases: [HUB]
    pattern: "UPM_FEM_LVT_FULLDIE_PDK0P9_0950MV_*_U1.U2"
    match: wildcard_case_insensitive
```

Interpret `*` as a wildcard that can match zero or more characters. Escape dots and other regular-expression characters before converting the wildcard to a regular expression. If multiple columns or UPM names match a wildcard, list all matches in the run manifest and apply a configured selection rule. Default: do not choose silently; mark as ambiguous.

### 5.2 `analysis_config.yaml`

```yaml
run:
  product_scope: [NVLH]
  unit_filter: null
  allowed_test_programs: [30N, 30P]
  output_pptx: "NVLH_Parametric_rollup_generated.pptx"
  output_excel: "analysis_data.xlsx"

normalization:
  vf_default: median
  allow_median_fallback_when_upm_missing: true
  normalized_value_definition: "Vmin_V minus reference_V"

comparisons:
  products: [NVLH]
  include_presi: false
  presi_source: null

frequency:
  highest_measured_definition: "maximum frequency with valid Vmin data after filtering"

temperature:
  target_C: 100

slides:
  material_characteristics: true
  normalized_sicc: true
  domain_vf_summary: true
```

The exact definition of UPM normalization must be explicit in configuration. Do not assume whether normalization means subtraction, division, ratio, or another transform. Recommended default for voltage normalization is `Vmin_V - reference_V`, but only use this when confirmed in configuration.

---

## 6. Data validation before analysis

The pipeline must create a data-quality report before generating charts.

### 6.1 Validation checks

1. File exists and is readable.
2. CSV delimiter and encoding are detected or configured.
3. Canonical column mappings are unique.
4. UnitID is not empty for unit-level records.
5. Numeric columns parse successfully.
6. Vmin, frequency, SICC, UPM, and DTS units are identified.
7. Frequency unit is converted consistently to GHz.
8. UPM frequency-like values are converted consistently to MHz or GHz as required per chart.
9. DTS values are in degrees Celsius.
10. Domain aliases are mapped to one canonical domain.
11. Product and test-program filters are applied and logged.
12. Duplicate measurement keys are detected.
13. Invalid or nonphysical values are not deleted silently; they are flagged and excluded according to configured limits.
14. All wildcard UPM patterns are checked for zero, one, or multiple matches.
15. PreSi and PostSi definitions are checked for compatible domain, frequency, units, and normalization.

### 6.2 Run manifest

Create `run_manifest.json` with:

- input file names and hashes
- run timestamp
- input row count
- retained row count
- unique unit count
- products, lots, test programs, corners, and domains found
- canonical column mapping
- UPM pattern matches
- duplicate handling
- exclusions and reasons
- created analyses
- omitted analyses and missing fields
- normalization mode per chart
- selected comparison populations
- highest measured frequency per domain

---

## 7. Slide 4 specification: Material characteristics

### 7.1 Slide purpose

Provide a one-slide material summary for the three die groups: CPU/CDIE, GT, and HUB. The slide must show the distribution of the designated UPM for each die and the relationship between the die's SICC V1 and that UPM.

### 7.2 Layout

Preserve the reference three-column arrangement:

- Slide title at top: `Material characteristics`
- Optional population subtitle below the title, generated from actual data, for example:
  - `<N> units, <material/step if available>. Tested in Class TP <test programs>`
- Three equal columns with dark-blue section headers:
  - `CPU` or `CDIE`, use the configured display name
  - `GT`
  - `HUB`
- Each column contains:
  1. Upper panel: UPM distribution histogram plus quantile/statistics table
  2. Lower panel: SICC V1 versus UPM scatter plot

Do not hard-code the reference statement `32.9k units, ES2 material. Tested in Class TP 30N and 30P`; generate the population text only from available input fields.

### 7.3 Upper panel: UPM histogram

Create one histogram per die using one point per UnitID.

Required title format:

- `CPU material UPM distribution`
- `GT material UPM distribution`
- `HUB material UPM distribution`

Required x-axis:

- label: `UPM value (MHz)` or the actual validated unit
- apply the die-specific UPM field

Required y-axis:

- label: `Unit count`

Required annotation:

- CPU: vertical target/reference line at `9154 MHz`, labeled `PDK1.0 entitlement at 20°C: 9154 MHz`
- GT: vertical target line at `7694`, converted to the displayed UPM unit if needed, labeled `Target: 7694`
- HUB: no target line unless a target is provided in configuration

Required statistical summary beside or inside the upper panel:

- N valid units
- missing UPM count
- minimum
- Q01
- Q05
- Q10
- Q25
- median/Q50
- mean
- Q75
- Q90
- Q95
- Q99
- maximum
- standard deviation

Use a consistent quantile interpolation method and record it in the workbook. Recommended default: linear interpolation.

Histogram-bin rule:

- Prefer Freedman-Diaconis bin width.
- If the interquartile range is zero or the result is invalid, use Sturges' rule.
- Use identical binning only when comparing the same UPM field across populations; otherwise optimize per die.

### 7.4 Lower panel: SICC V1 versus UPM

Create one scatter point per valid UnitID with both SICC V1 and die-specific UPM data.

Required title:

- `CPU SICC V1 vs material UPM`
- `GT SICC V1 vs material UPM`
- `HUB SICC V1 vs material UPM`

Axes:

- x-axis: designated UPM, with unit
- y-axis: `SICC V1 (A)`

Required analysis:

- scatter markers with high transparency to handle dense populations
- optional hexbin/density shading only if individual points remain available in the workbook
- ordinary least-squares fit line if N is sufficient and configuration enables the fit
- display N and correlation coefficient only when computed from valid paired points
- never substitute aggregate points for unit-level points

If more than one SICC V1 value exists per unit, use the configured SICC instance. If none is configured, mark the analysis ambiguous rather than selecting silently.

### 7.5 Missing-data behavior

- UPM missing: retain histogram and scatter titles with placeholders. If no UPM column exists, both panels become placeholders.
- SICC missing but UPM present: render histogram; retain the SICC-vs-UPM titled placeholder.
- Die population absent: retain the full die column and display `No units found for configured population`.

---

## 8. Slide 13 specification: Normalized SICC analysis

### 8.1 Slide purpose

Compare per-unit SICC V1 behavior against the relevant UPM for each domain, and summarize PostSi values versus PreSi targets where compatible PreSi input exists.

### 8.2 Reference content to preserve conceptually

The reference slide contains:

- title: `Normalized SICC analysis`
- six compact unit-level scatter panels for SA-Atom, GT, CCF/Ring, HUB/SA total, Core, and Atom
- a comparison table with domain, PreSi SICC target, and normalized SICC
- an insight statement above the charts

The automated slide may reflow the plots, but must preserve the same components: domain plot matrix, PreSi comparison table, and a clearly separated insight/comment area.

### 8.3 Domain plot matrix

For every configured domain with valid data:

- x-axis: relevant domain/die UPM
- y-axis: `SICC V1 (A)`
- one point per UnitID
- panel title: `<Domain> SICC V1 vs UPM`
- show the exact UPM field in a subtitle or footnote
- show N valid paired units

Recommended default domains from the reference:

- Core
- Ring/CCF
- Atom
- SA-Atom
- SA total/HUB
- GT

Do not assume SA total and HUB are synonymous. Define that relationship in `domain_mapping.yaml`. If SA-total is calculated as a sum of components, document the formula and require the component data.

### 8.4 Normalized SICC metric

The normalized metric must be defined in configuration. Acceptable examples include:

- median of per-unit SICC V1 after filtering
- value predicted at a configured UPM reference using regression
- SICC divided by a UPM-derived scale
- SICC residual after UPM adjustment

Do not infer the formula from the slide title. The chart subtitle and table header must display the configured definition, for example:

- `Median SICC V1 (A)`
- `SICC at target UPM (A)`
- `UPM-normalized SICC (configured formula)`

### 8.5 PreSi comparison table

Required columns:

| Domain | PostSi metric | PreSi target | Delta | Delta % | Basis | Status |
|---|---:|---:|---:|---:|---|---|

Definitions:

- `Delta = PostSi - PreSi`
- `Delta % = 100 × (PostSi - PreSi) / PreSi`
- `Basis` identifies `UPM-normalized`, `Median`, or the configured method
- `Status` is `Comparable`, `Missing PreSi`, `Missing PostSi`, or `Definition mismatch`

Only calculate Delta and Delta % when the values have compatible units and definitions.

Reference values visible in the source slide must not be hard-coded as current results. They may be stored only in an optional reference-validation file:

| Domain | Reference PreSi target | Reference normalized SICC |
|---|---:|---:|
| Core | 2.96 | 2.27 |
| Ring | 0.94 | 0.95 |
| Atom | 1.78 | 1.43 |
| SA-Atom | 1.93 | 2.06 |
| SA total | 4.92 | 6.60 |
| GT | 3.46 | 3.48 |

Use these values only to verify reproduction on the original reference dataset, never as a fallback for new raw data.

### 8.6 UPM-unavailable fallback

For a domain without UPM data:

1. Replace scatter panel with a histogram of per-unit `SICC_V1_A`.
2. Title: `<Domain> SICC V1 distribution`
3. Subtitle: `Median-based; UPM unavailable`
4. x-axis: `SICC V1 (A)`
5. y-axis: `Unit count`
6. Annotate median, Q10, Q90, N, and missing count.
7. In the comparison table, set `Basis = Median`.
8. If no valid SICC exists either, retain the titled placeholder.

### 8.7 Insight box

Create a reserved user-editable insight box below the title or above the table. Automatic text may include only directly computed results, for example:

- `<Domain> PostSi metric is <x.x>% above/below the compatible PreSi target.`

If no compatible comparison exists, leave the insight box with:

> User comments / interpretation

---

## 9. Slide 16 family: one VF summary slide per domain

### 9.1 Slide generation rule

Generate one slide for every domain found in the configured domain list, even if part of the required data is missing. If the domain has no rows at all, generate the slide with all titled placeholders so the missing domain is visible.

Suggested domain order:

1. Core
2. Ring/CCF
3. Atom
4. SA-Atom
5. GT
6. SAQ
7. NPU
8. additional configured domains

### 9.2 Slide title and layout

Title:

`<Domain> VF curve`

Required regions:

1. User comments text box
2. Main VF curve
3. Highest-frequency Vmin versus UPM
4. Limiter test Pareto
5. Test-temperature distribution per corner and test
6. Flow-matrix summary
7. Normalization/comparison warning area

Recommended 16:9 layout:

- top-left to center, approximately 60% width: main VF curve
- top-right: limiter Pareto
- bottom-left: Vmin versus UPM or a compact inset under the VF curve
- bottom-center/right: temperature distribution
- bottom-right: flow-matrix summary
- narrow comment box under the title or along the left margin

The exact styling may change, but no required region may be omitted without leaving its titled placeholder.

---

## 10. Domain slide component A: user comments

Create an editable text box with title:

`User comments / interpretation`

Default content:

`Click to add comments.`

The pipeline must never overwrite non-placeholder user text on a rerun unless an explicit `overwrite_user_comments: true` configuration is set.

If automated observations are enabled, place them in a separate box labeled `Automatically generated observations`; do not mix them with user-authored comments.

---

## 11. Domain slide component B: VF curve

### 11.1 Analytical definition

A VF curve is the relationship between frequency and Vmin for a domain.

- x-axis: `Frequency (GHz)`
- y-axis: `Vmin (V)`, `Median Vmin (V)`, or `Normalized Vmin (V)` depending on configuration
- one curve per configured population or comparison series
- each curve point is normally the median across valid units at a domain/frequency after filtering
- individual unit records remain available in the Excel source sheet

The slide must explicitly state whether curve points represent:

- raw per-unit Vmin traces
- median Vmin by frequency
- UPM-normalized median Vmin
- median-normalized Vmin

Do not label a curve merely `normalized` without naming the reference and formula.

### 11.2 Supported normalization modes

#### Mode 1: No normalization

```text
CurveValue = median(Vmin_V) by Product × Domain × Frequency_GHz
```

#### Mode 2: UPM-normalized

```text
UnitNormalizedVmin = Vmin_V - UPM_reference_V
CurveValue = median(UnitNormalizedVmin) by Product × Domain × Frequency_GHz
```

Use only if the UPM field and normalization formula are configured.

#### Mode 3: Median-normalized

The anchor must be explicit. Example:

```text
ReferenceMedian = median(Vmin_V) at configured anchor frequency for each population
UnitNormalizedVmin = Vmin_V - ReferenceMedian
CurveValue = median(UnitNormalizedVmin) by Product × Domain × Frequency_GHz
```

If no anchor is specified, do not invent one. Use unnormalized medians or a placeholder according to configuration.

### 11.3 Comparisons

The user controls comparison scope in configuration:

- single-product PostSi
- multiple PostSi products
- PostSi versus PreSi
- any combination backed by valid raw/reference data

Each line must have:

- distinct color
- distinct marker or line style, so meaning does not depend only on color
- legend entry
- direct label adjacent to the final valid point, with collision avoidance
- product and basis, for example `NVLH | median Vmin`

A warning must be shown when compared products use different process-speed or normalization scales.

### 11.4 Interactivity

Preferred implementation:

- write chart source data to `<Domain>_VF` in the Excel workbook
- create an editable Excel or native PowerPoint XY/line chart
- embed the chart data in the PowerPoint so PowerPoint tooltips expose series, frequency, and value when editing/selecting the chart
- retain a detailed source table with N, median, Q10, Q90, and missing count by series and frequency

### 11.5 VF uncertainty

Optionally show Q10-Q90 or Q25-Q75 error bars/ribbon when supported. Never display uncertainty bars without labeling the quantiles.

### 11.6 Missing-data behavior

- Frequency or Vmin absent: titled placeholder.
- Requested comparison population absent: keep the available curve and add a small placeholder/note for the missing series.
- Requested UPM normalization unavailable: apply the configured median fallback and label it, or create the titled placeholder.

---

## 12. Domain slide component C: highest-frequency Vmin versus UPM

### 12.1 Frequency selection

For each domain and product:

1. Filter to valid Vmin and domain-relevant UPM records.
2. Identify the highest `Frequency_GHz` with valid paired data.
3. Require a configurable minimum paired-unit count. Recommended default: 20.
4. If the absolute highest frequency has insufficient paired data, either:
   - select the next-highest frequency meeting the threshold and label the selection rule, or
   - leave a placeholder, according to configuration.

### 12.2 Plot definition

Title:

`<Domain> <Frequency> GHz Vmin vs UPM`

- x-axis: `UPM value (<unit>)`
- y-axis: `<Domain> Vmin at <Frequency> GHz (V)`
- one point per UnitID
- color by Product when several products are compared
- optional fitted line per product
- display N paired points
- direct series labels where readable

If the domain has no configured UPM, keep the titled placeholder. Do not substitute an unrelated UPM.

---

## 13. Domain slide component D: limiter test Pareto

### 13.1 Purpose

Show, for every domain-frequency combination, the percentage of valid units whose limiting content is Scan, Array, Functional, or another configured category.

### 13.2 Limiter classification

If `LimiterType` is already present, map raw values through `limiter_mapping.yaml`.

If limiter must be derived:

1. Group records by UnitID, Product, Domain, and Frequency.
2. Compare the limiting Vmin requirement among content categories.
3. The category with the maximum valid required Vmin is the limiter.
4. If the top categories are tied within a configured voltage tolerance, set `LimiterType = Tie` rather than choosing arbitrarily.
5. If required content data is incomplete, set `LimiterType = Unknown` and include it in the chart or quality report according to configuration.

### 13.3 Plot design

Preferred chart: 100% stacked bar chart.

- x-axis: ordered `<Domain> @ <Frequency> GHz` categories, or frequency alone when the slide is already domain-specific
- y-axis: `Units (%)`, fixed at 0 to 100%
- stack colors:
  - Scan: configured blue
  - Array: configured orange
  - Functional: configured green
  - Tie: gray
  - Other/Unknown: light gray or hatched pattern
- labels: percent inside sufficiently large segments
- legend title: `Limiting content`

Use percentage denominator equal to the number of units eligible for limiter classification at that frequency. Report the denominator in the workbook.

---

## 14. Domain slide component E: test-temperature distribution

### 14.1 Purpose

Show DTS temperature distribution per domain, frequency, corner, and test instance, with a 100°C target.

### 14.2 Required chart

Title:

`Test temperature dist. per corner and test`

Required dimensions:

- filter: current slide domain
- x-axis grouping: `Corner → Frequency → TestInstance`, ordered by configuration
- y-axis: `DTS temperature (°C)`
- one point per UnitID/test observation
- color by test instance or corner

Recommended plot form:

- box-and-whisker per group with individual points overlaid using horizontal jitter
- use transparency for dense points
- show median in each box
- preserve unit-level values in Excel

Target annotation:

- green horizontal line at `100°C`
- line label near the right edge: `Target = 100°C`

Optional annotations:

- N per group
- median temperature per group
- percentage above 100°C

Only show the optional percentage if it is calculated from actual data.

### 14.3 Missing-data behavior

If DTS temperature, corner, frequency, or test-instance data is unavailable, keep the full titled placeholder and list the missing fields.

---

## 15. Domain slide component F: flow-matrix summary

### 15.1 Purpose

Summarize corner names and their frequency values by Class test program. If multiple products are selected, give each product a separate matrix or separate section.

### 15.2 Table structure

Preferred structure:

| Product | Test program | Corner | Domain | Frequency (GHz) | Active/Observed | Unit count |
|---|---|---|---|---:|---|---:|

For the compact slide table, pivot to:

- rows: corner names
- columns: Class test programs or products/test programs
- cell: frequency value in GHz

If several frequencies exist in the same cell, display a sorted comma-separated list. Do not average frequencies.

### 15.3 Visual rules

- title: `Flow matrix summary` or `<Product> flow matrix summary`
- use green fill for observed/active combinations only if verified from data
- use blank or gray cells for missing combinations
- include a legend explaining fill meaning
- keep full matrix data in Excel even if the slide uses a compact subset

---

## 16. Domain mapping and naming consistency

Use a controlled alias table. Do not merge domains merely because names look similar.

Example:

```yaml
canonical_domains:
  Core:
    aliases: [CORE, CR]
  Ring:
    aliases: [RING, CCF]
  Atom:
    aliases: [ATOM, AT]
  SA-Atom:
    aliases: [SAAT, SA_ATOM, LPATOM]
  GT:
    aliases: [GT]
  SAQ:
    aliases: [SAQ, QCLK]
  NPU:
    aliases: [NPU, SADPU]
```

Any broader aggregation such as `SA total`, `HUB`, or `All SA domains` requires an explicit formula or membership list. Never infer it from naming.

The output title may use a user-friendly display name while the workbook records the canonical domain and raw source values.

---

## 17. Chart styling rules

1. Maintain professional technical-report styling and generous white space.
2. Use consistent colors for the same product across all slides.
3. Use consistent colors for limiter categories across all slides.
4. Use marker shape or line style in addition to color.
5. Keep all axis titles and units visible.
6. Do not use truncated scientific notation without a scale label.
7. Use sensible precision:
   - voltage: typically 2 or 3 decimals
   - frequency: preserve source precision, normally 1 to 3 decimals
   - SICC: normally 2 decimals
   - percentages: 0 or 1 decimal depending on population size
8. Do not place a regression line without distinguishing it from raw points.
9. Do not place legends over data.
10. Prefer direct line labels on VF curves, while retaining a legend when multiple series exist.
11. Add N to every analytical panel.
12. Use the same axis range across comparison panels only when a common scale is analytically meaningful. Otherwise label each panel clearly.
13. Ensure chart titles describe domain, measurement, frequency when relevant, and normalization basis.

---

## 18. Statistical definitions

Use one validated implementation for all slides.

- Count: number of valid unique unit-level observations after filtering
- Median: 50th percentile
- Standard deviation: sample standard deviation unless configured otherwise
- Quantiles: linear interpolation by default
- Correlation: Pearson correlation for paired numeric observations, only when N meets configured minimum
- Regression: ordinary least-squares by default, with slope/intercept stored in Excel and manifest
- Percent limiter: `100 × classified units in category / eligible classified units`
- Percent above temperature target: `100 × valid observations above 100°C / valid observations`

Keep full precision in calculations and round only for display.

---

## 19. PowerPoint generation strategy

### 19.1 Template handling

1. Start from a copy of the original template presentation.
2. Locate slides by a stable slide tag, shape name, or exact title, not solely by slide number.
3. Preserve all unmodified shapes.
4. Name target placeholders, for example:
   - `ph_material_cpu_hist`
   - `ph_material_cpu_sicc_upm`
   - `ph_sicc_plot_core`
   - `ph_vf_main`
   - `ph_vmin_upm`
   - `ph_limiter_pareto`
   - `ph_temperature`
   - `ph_flow_matrix`
   - `ph_user_comments`
5. For one-slide-per-domain generation, duplicate a clean template slide and replace only the domain-specific placeholders.
6. Do not overwrite the original presentation. Save to a new output file.

### 19.2 Editable data requirement

For each chart, store:

- raw filtered records
- calculated summary table
- chart-ready pivot table
- chart definition and filters

If the chart is pasted as an image, also embed a hyperlink or note pointing to the exact Excel sheet and table name. Prefer editable chart objects over images.

### 19.3 Rerun behavior

- Use deterministic shape names and slide tags.
- Replace charts created by the pipeline on rerun.
- Preserve user comments unless overwrite is explicitly enabled.
- Recreate missing-data placeholders based on the current run.
- Produce a new versioned output rather than overwriting the prior report unless configured otherwise.

---

## 20. Recommended implementation phases for GHCP

### Phase 1: inspect and profile input

Deliverables:

- detected column list
- proposed alias mapping
- products, domains, frequencies, corners, instances, and test programs found
- UPM wildcard match report
- data-quality report

No charts should be generated until column mapping and measurement units are validated.

### Phase 2: build canonical analytical dataset

Deliverables:

- normalized long-form table
- explicit domain aliases
- duplicate report
- unit conversion report
- stable filters

### Phase 3: implement reusable calculations

Implement and unit-test:

- quantile summary
- histogram bins
- paired SICC-UPM extraction
- normalization methods
- VF aggregation
- highest-valid-frequency selection
- limiter classification
- temperature grouping
- flow-matrix pivot
- compatible PreSi/PostSi comparison

### Phase 4: generate Excel analytical workbook

Deliverables:

- all chart source data
- summaries
- data-quality sheet
- run-summary sheet
- editable charts where practical

### Phase 5: generate Slide 4

Confirm:

- correct UPM column per die
- CPU entitlement line at 9154 MHz and 20°C
- GT target line at 7694
- distributions and statistics per die
- unit-level SICC vs UPM
- placeholders for missing analyses

### Phase 6: generate Slide 13

Confirm:

- SICC V1 vs UPM per configured domain
- median histogram fallback when UPM is absent
- compatible PreSi comparison table
- basis clearly labeled
- user-editable insight box

### Phase 7: generate one VF slide per domain

Confirm every domain slide includes all seven layout regions and correct placeholders.

### Phase 8: presentation QA

Programmatically check:

- all expected slides exist
- all expected placeholders were replaced or marked missing
- all charts have title and axis titles
- all slide charts have a corresponding workbook source table
- all unit counts match source tables
- no hard-coded reference result was used as new output data
- no required slide object extends beyond the slide canvas
- output opens without package errors

---

## 21. Acceptance criteria

The implementation is acceptable when all conditions below are met.

### Data correctness

- Every unit-level point can be traced to a source UnitID.
- Every aggregate value can be regenerated from an output workbook table.
- Normalization formula and basis are visible.
- UPM wildcard matching is deterministic and reported.
- No missing metric is silently replaced with fabricated data.

### Slide 4

- Three die columns exist: CPU/CDIE, GT, HUB.
- Each die has a UPM histogram with quantile/statistics summary or titled placeholder.
- Each die has SICC V1 versus its designated UPM or titled placeholder.
- CPU target/entitlement 9154 MHz at 20°C is annotated when unit-compatible.
- GT target 7694 is annotated when unit-compatible.

### Slide 13

- Each configured domain has SICC V1 versus UPM, a median-based SICC histogram, or a titled placeholder.
- PreSi comparison table is present.
- The table identifies comparison basis and compatibility status.
- Median fallback is clearly labeled.

### Domain VF slides

- One slide exists per configured domain.
- Title is `<Domain> VF curve`.
- User comment box is editable.
- Main VF curve indicates raw, median, UPM-normalized, or median-normalized basis.
- Highest-frequency Vmin versus UPM uses the correct selected frequency and axes.
- Limiter Pareto sums to 100% per eligible category group, subject to displayed rounding.
- Temperature plot includes the 100°C green horizontal target line.
- Flow matrix shows corner and frequency per Class test program and product when available.
- Missing components remain visible as titled placeholders.

### Presentation integrity

- Original file is not overwritten.
- Template formatting, slide size, masters, and fixed branding are preserved.
- Charts are editable or have traceable Excel source data.
- User-entered comments survive a normal rerun.

---

## 22. GHCP implementation prompt

Use the following as the primary GitHub Copilot Chat instruction after placing this plan in the repository:

```text
Implement the NVLH parametric rollup pipeline exactly as specified in NVLH_Parametric_Automation_GHCP_Plan.md.

Start with Phase 1 only. Inspect the CSV files under data/raw, create the canonical-column mapping proposal, validate units, list available products/domains/frequencies/corners/test instances/test programs, and report exact matches for every configured UPM pattern. Do not invent missing columns or values. Create a machine-readable data-quality report and a concise Markdown review report.

After Phase 1, continue through the remaining phases without changing analytical definitions. Use configuration files for all domain aliases, UPM patterns, products, normalization formulas, target values, thresholds, and comparison scopes. Keep one row per physical measurement in canonical long form and preserve UnitID traceability.

Generate analysis_data.xlsx before generating the PowerPoint. Every PowerPoint chart must have a clearly identified source sheet/table in that workbook. Use the supplied PowerPoint template, preserve its layout/master/footer/branding, do not overwrite the original file, and retain titled placeholders for every missing analysis according to the plan.

Add automated tests for quantiles, normalization, highest-frequency selection, limiter classification, population percentages, wildcard UPM matching, missing-data placeholders, and slide completeness. Produce run_manifest.json recording every created, omitted, or fallback analysis.
```

---

## 23. Items intentionally left configuration-driven

The following cannot be determined reliably from the reference slides alone and must not be guessed by the implementation:

1. Exact mathematical definition of `normalized Vmin`.
2. Exact mathematical definition of `normalized SICC`.
3. Which UPM applies to every domain beyond the three material-characteristic die mappings supplied above.
4. Which SICC test instance is authoritative when several are present.
5. Exact domain membership/formula for `SA total` or its relation to HUB.
6. Minimum unit count for a valid frequency or statistical fit.
7. Outlier-handling rules.
8. Comparison products and whether PreSi is included in a specific run.
9. PreSi/PostSi process equivalence rules.
10. The authoritative rule for duplicate measurements without a reliable timestamp.

Expose these items in YAML configuration and stop or create a placeholder when a required choice is unresolved.
