# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

This repo uses a single-context layout:

```text
/
|-- CONTEXT.md
|-- docs/
|   `-- adr/
`-- ...
```

`CONTEXT.md` and `docs/adr/` may not exist yet. If they are absent, proceed silently. The domain-modeling flow can create them later when project terms or architectural decisions need to be recorded.

## Before exploring, read these

- `CONTEXT.md` at the repo root, if it exists.
- Relevant ADRs under `docs/adr/`, if they exist.
- `game_take_home.html` before changing verifier behavior, scoring, calibration, anti-cheat probes, report evidence, or rollout-run documentation.
- `AGENTS.md` and `CLAUDE.md` for repo-specific working rules.

## Vocabulary

When output names a domain concept, prefer the term used in `CONTEXT.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, or `game_take_home.html`.

If the concept is missing or ambiguous, note the gap for domain modeling instead of inventing new project language casually.

## ADR conflicts

If a proposal contradicts an existing ADR, surface the conflict explicitly rather than silently overriding it.
