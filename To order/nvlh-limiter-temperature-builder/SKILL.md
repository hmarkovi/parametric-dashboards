---
name: nvlh-limiter-temperature-builder
description: Build limiter pareto and temperature distribution data for each domain foil with strict source requirements, explicit eligibility denominators, and 100C target annotation support.
---

## Purpose

Use this skill to generate the two domain foil panels that are most sensitive to source-quality gaps: limiter pareto and DTS distributions.

## Scope

This skill includes:
- limiter classification mapping/derivation
- 100% stacked pareto data tables
- DTS grouping tables by Corner -> Frequency -> TestInstance
- mode-switch metadata for Box+Jitter or Histogram fallback

This skill does not include:
- VF normalization
- SICC normalization
- PPT/HTML parity checks

## Limiter rules

1. Classify per unit per Domain x Frequency x series.
2. Use `LimiterType` when present, else derive from module-level required Vmin.
3. Ties within tolerance => `Tie`.
4. Incomplete inputs => `Unknown`.
5. Denominator is eligible classified units only.

## Temperature rules

1. Use `DTS_Temperature_C` as y-value.
2. Group by `Corner`, `Frequency_GHz`, `TestInstance`.
3. Primary mode: Box+Jitter.
4. Fallback mode: Histogram when density/readability threshold is exceeded.
5. Always include 100C target metadata.

## Outputs

- `limiter_pareto_points_*.csv`
- `temperature_distribution_points_*.csv`
- panel metadata JSON indicating chosen render mode

## Fast prompt

`Use nvlh-limiter-temperature-builder: generate limiter and DTS panel tables for all configured domains.`
