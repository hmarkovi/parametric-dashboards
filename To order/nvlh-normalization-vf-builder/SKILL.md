---
name: nvlh-normalization-vf-builder
description: Build two-stage domain analytics: Stage A per-frequency Vmin-vs-UPM normalization and Stage B VF curve assembly with explicit normalized or median-fallback basis labels.
---

## Purpose

Use this skill for domain VF computation that matches the plan contract and avoids mixed definitions.

## Scope

This skill includes:
- Stage A regression panel data per Domain x Frequency x grouping series
- Stage B VF curve points from Stage A outputs
- explicit median fallback when UPM target/data is missing
- output tables for HTML/PPT parity

This skill does not include:
- limiter pareto
- temperature distribution
- SICC panel rendering

## Stage A contract

For each Domain + Frequency + series:
1. use unit-level paired points (`Vmin_V`, `UPM_Value`)
2. fit `Vmin = a * UPM + b`
3. evaluate `Vmin_norm = a * UPM_target + b`
4. output N, slope, intercept, R2, target, status

## Stage B contract

For each Domain + series across frequencies:
1. prefer Stage A normalized points
2. fallback to median Vmin points where Stage A unavailable and fallback allowed
3. mark each point basis as `Normalized-at-target` or `Median fallback`

## Required rules

1. Do not publish unlabeled normalized curves.
2. Keep one primary comparison axis per chart.
3. If no valid point exists for a frequency, leave gap or placeholder per panel policy.

## Outputs

- `normalized_vmin_points_*.csv`
- `vf_curve_points_*.csv`
- stage report Markdown with status counts

## Fast prompt

`Use nvlh-normalization-vf-builder: compute Stage A normalized points and Stage B VF curves for the latest canonical dataset.`
