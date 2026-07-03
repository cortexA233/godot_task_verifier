# AGENTS.md

## Project Goal

This repository is the private external verifier for the RoboBlast grenade
weapon benchmark. It implements the verifier side of the assignment described
in `game_take_home.html`: grade candidate Godot projects behaviorally, out of
100, by copying a candidate project to a temporary directory, injecting
`verifier_godot/__verifier__`, running Godot headlessly, and writing structured
score artifacts.

The verifier is part of the evaluation infrastructure, not part of the ablated
task handed to rollout agents. Keep it private from candidate workspaces and do
not copy verifier files, hidden tests, scoring details, anti-cheat probes, or
solution hints into the ablated game repository.

## Source Of Truth

- `game_take_home.html` is the assignment source of truth for this verifier
  repository. Read it before changing verifier behavior, scoring, calibration,
  anti-cheat probes, report evidence, or rollout-run documentation. If local
  docs disagree with the assignment, follow `game_take_home.html` and update the
  docs as part of the same scoped change.
- `BENCHMARK.md` defines the benchmark construct, agent evaluation protocol,
  candidate interface contract, score interpretation, reproducibility
  expectations, and validity-probe requirements. Keep it aligned with verifier
  behavior and calibration evidence.
- `README.md` documents the public command interface, score categories, report
  rendering, debug arena export, and latest calibration notes.
- `probe_matrix.md` documents anti-cheat probe expectations.
- `run_grader.py` is the Python entry point that prepares and runs the verifier.
- `verifier_godot/__verifier__/runner.gd` and related Godot files contain the
  behavioral checks.
- `tests/` contains Python tests for runner behavior, report rendering, debug
  export, and selected Godot-facing assumptions.

## Working Rules

- Preserve existing user changes. Do not reset, checkout, or revert unrelated
  files unless explicitly asked.
- Keep verifier changes scoped and reproducible. The grader should exercise
  real game behavior rather than checking for exact filenames, class names,
  node paths, or code shape.
- Maintain deterministic headless execution. Control timing, scene setup,
  target placement, input events, random seeds, viewport assumptions, and
  artifact paths where relevant.
- Pin verifier runs, calibration, and assignment evidence to Godot 4.6 unless a
  human explicitly approves an engine-version change and the verifier is
  recalibrated against the new version.
- Keep scoring meaningful and out of 100. When scoring changes, update the
  README, tests, calibration notes, and probe matrix as needed.
- Reject reward hacking and near-miss implementations with behavioral probes,
  but avoid false negatives for reasonable alternate implementations.
- Do not commit generated runtime artifacts such as logs, temporary candidate
  copies, score JSON files, screenshots, PDFs, or debug arena exports unless
  they are deliberately curated fixtures or report evidence.
- When modifying `verifier_godot/__verifier__`, keep the debug arena and any
  exported-inspection workflow aligned with the same deterministic layout used
  by the grader.
- Any changes made in this verifier repository must also be committed in this
  verifier repository. Stage only the files that belong to the current task.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for this repo; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default mattpocock/skills triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout: root `CONTEXT.md` plus root `docs/adr/` when they exist. See `docs/agents/domain.md`.

## Common Commands

Run the verifier against a candidate project:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json
```

Run with a PDF report:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  --pdf-report C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

Run unit tests:

```powershell
python -m unittest discover -s tests
```

Run calibration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Export a manual debug arena:

```powershell
python C:\recent_project\roboblast-grenade-verifier\export_debug_arena.py `
  --project C:\path\to\candidate-project `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena
```

## Verification Expectations

Before claiming a verifier change is complete, run the narrowest relevant test
command and record the result. For scoring or Godot-runner changes, prefer a
real headless verifier run or calibration pass in addition to Python unit tests
when the required Godot executable is available.

Record the exact Godot executable and version used for any calibration or
assignment evidence.
