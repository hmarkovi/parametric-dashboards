---
name: nvlh-schema-token-resolution
description: Resolve wide CSV tokens into strict canonical mappings for UnitID, Product, Domain, Frequency, Vmin, UPM, SICC, DTS, limiter, and flow dimensions without silent assumptions.
---

## Purpose

Use this skill to convert a very-wide raw CSV schema into a deterministic mapping contract that downstream chart logic can trust.

## Scope

This skill includes:
- header and delimiter profiling
- canonical candidate discovery
- wildcard UPM matching with strict ambiguity handling
- domain token mapping and unresolved-token reporting
- mapping manifest output for Phase 2

This skill does not include:
- chart rendering
- normalization computation
- limiter/temperature derivation logic

## Required rules

1. Keep configured UPM and SICC token names exactly as provided.
2. If a wildcard resolves to multiple columns, stop and request explicit user choice.
3. If required canonical fields are missing, emit blockers and stop dependent stages.
4. Never infer SICC authority when multiple candidate instances exist.

## Inputs

- Raw CSV path
- Mapping config path
- Optional sample-row limit

## Outputs

- mapping proposal JSON
- column profile CSV
- mapping review Markdown

## Fast prompt

Use this single prompt:

`Use nvlh-schema-token-resolution: profile <csv-path> and produce strict canonical mapping blockers.`
