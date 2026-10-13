---
name: lemans-prepare
description: Prepare raw lemans/miniswen benchmark runs for analysis — capture per-step and cumulative diffs from the agents' git branches and merge multi-step results into a single Lemans::Result-format result.json per run. Use when the user asks to merge run data, capture run diffs, or before analyzing runs whose artifacts don't exist yet.
---

# lemans-prepare

Turn raw run data (per-model `results.N.json` / `trajectory.N.json`, plus git branches with the agents' work) into the mechanical artifacts the analysis builds on: `agent.{N,}.patch` diffs and a merged `result.json` per run. No grading, no judgment — that's the `lemans-analyze` skill.

## 0. Locate inputs

If the user gave no paths, ask where the runs live. Discover (and ask only for what can't be found):

- **Runs**: per-model directories. Multi-step: `results.N.json` + `trajectory.N.json` per step. Single-step: one results/trajectory pair. Don't invent step structure that isn't there.
- **Work product**: git branches (typically `run/<model>`, N commits on top of a baseline branch) in the target app repo. No branches → diffs can't be captured; say so and merge what exists.
- **Limits**: the bench profile (`bench.yml`: `step_limit`, `cost_limit`) if present; otherwise ask or default to 100 steps / $5.0 per trial.

**Idempotency**: reuse artifacts that already exist unless the user asks to regenerate, and say what was reused.

**Do-not-touch**: never modify the analyzed repos except the runs directories (verify they're gitignored). Restore the original checkout when done.

## 1. Capture diffs

For each model with a branch: `agent.N.patch` per step (`git diff <prev>..<commit>`, commits in order on top of the baseline) and cumulative `agent.patch` (`git diff <baseline>..<head>`). Single-step: just `agent.patch`. Store next to that model's results.

## 2. Merged `result.json` (Lemans::Result format)

One `result.json` per model per task so `lemans report` renders it. Current format keys: `trial` (`<task>__<7 alnum>`), `task`, `agent`, `model`, `index`, `revision` `{commit, dirty}`, `lemans_version`, `tags`, `metadata`, `phases`, `reward`, `outcome` `{name, scored}`, `usage` `{input_tokens, output_tokens, cached_tokens, steps, cost_usd, cost_source}`, `duration`, `started_at`, `finished_at`.

- Multi-step: sum usage across steps; put per-step detail in `metadata.per_step_usage` (steps, cost, tokens, duration, over-limit flags per step). Timestamps come from the step commits — each commit marks its step's **end**, so step 1's duration is unknown and totals are lower bounds; note that in `metadata`.
- Over-limit highlighting: tag `over-step-limit` / `over-cost-limit` when any single step exceeds the limits; flag merged totals separately in `metadata.over_default_limits`; record the limits used in `metadata.default_limits`.
- **Reward contract**: if a `checks.json` with a grade already exists for the run, copy its reward; otherwise omit `reward` — `lemans-analyze` fills it in after verification, don't fabricate one.
- Validate: parse each file with `Lemans::Result.from_json` and render the runs dir with `lemans report` before calling it done.
