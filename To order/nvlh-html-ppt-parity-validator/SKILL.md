---
name: nvlh-html-ppt-parity-validator
description: Validate that HTML and PPT outputs use identical panel IDs, titles, basis labels, and missing-data placeholder wording for every required foil component.
---

## Purpose

Use this skill to enforce cross-output consistency after analysis generation.

## Scope

This skill includes:
- panel ID parity checks
- title and subtitle parity checks
- basis-label parity checks (`Normalized-at-target`, `Median fallback`, etc.)
- missing-data placeholder text parity checks
- source-table coverage checks per panel

This skill does not include:
- data recomputation
- chart rendering internals

## Required checks

1. Every required panel exists in both HTML and PPT contracts.
2. Every panel maps to a source table.
3. Basis labels are identical for the same panel/series.
4. Placeholder messages are identical for the same missing dependency.
5. Report drift as blocking findings.

## Outputs

- parity report Markdown
- parity manifest JSON

## Fast prompt

`Use nvlh-html-ppt-parity-validator: compare latest HTML and PPT contract outputs and report blocking parity drift.`
