# CLAUDE.md

## Claude Instructions

Start by reading `AGENTS.md` and `game_take_home.html` in this repository.
Treat `game_take_home.html` as the assignment source of truth for verifier
implementation, scoring, calibration, anti-cheat probes, and report evidence.
This repository is the private RoboBlast grenade verifier, so keep verifier
internals, scoring probes, and implementation details out of any ablated task
workspace or rollout-agent prompt.

## How To Work Here

- Use PowerShell commands from the verifier repository root.
- Prefer `rg` / `rg --files` for searching.
- Keep edits small, deterministic, and tied to the verifier behavior being
  changed.
- Before changing behavior, scoring, calibration data, anti-cheat probes, or
  report generation, check the relevant requirement in `game_take_home.html`
  and keep the implementation aligned with it.
- Preserve existing user work. If the tree is dirty, inspect status and stage
  only the files that belong to the current task.
- Use `apply_patch` for manual text edits.
- Do not use destructive git commands unless the user explicitly asks for them.
- Commit any verifier-repository changes in this repository after verification.
- Do not add machine-specific local absolute paths to new or refreshed
  documentation, including reviewer-facing docs, generated reports, README
  files, and AGENTS instructions. Use repo-relative paths or placeholders
  instead.
- In reports, label any formal 100/100 rollout contradicted by screenshot
  evidence, suspect flags, or manual review as an anomalous failure case and
  group it with failure analysis, not successful rollouts.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for this repo; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default mattpocock/skills triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout: root `CONTEXT.md` plus root `docs/adr/` when they exist. See `docs/agents/domain.md`.

## Verification

For documentation-only changes, verify the relevant files and diff. For Python
or Godot verifier changes, run the focused unit tests first:

```powershell
python -m unittest discover -s tests
```

For scoring, runner, input, physics, visual, or anti-cheat changes, also run a
real headless verifier command when Godot is available and record the exact
command, executable path, and observed score.

## Output Discipline

When reporting back, include the files changed, the verification command that
was run, and the commit hash if a commit was created. If unrelated pre-existing
changes remain in the working tree, call that out explicitly.
