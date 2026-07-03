# CLAUDE.md

## Claude Instructions

Start by reading `AGENTS.md` and `game_take_home.html` in this repository.
Treat `game_take_home.html` as the assignment source of truth for verifier
implementation, scoring, calibration, anti-cheat probes, and report evidence.
This repository is the private RoboBlast grenade verifier, so keep verifier
internals, scoring probes, and implementation details out of any ablated task
workspace or rollout-agent prompt.

## How To Work Here

- Use PowerShell commands from `C:\recent_project\roboblast-grenade-verifier`.
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
