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
- Do not write machine-specific local absolute paths in new or refreshed
  documentation, including reviewer-facing docs, generated reports, README
  files, and AGENTS instructions. Use repo-relative paths or placeholders such
  as `<verifier-repo>`,
  `<candidate-project>`, `<godot-4.6-console-executable>`, and
  `<agent-runs-root>`.
- In reports, any formal 100/100 rollout contradicted by screenshot evidence,
  suspect flags, or manual review must be labeled as an anomalous failure case
  and grouped with failure analysis, not presented as a success.
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

## Writeup Generation Rules

These rules apply to `evaluation/writeup.html`, any copied final-deliverable
writeup, and temporary Chinese previews:

- Treat the English HTML writeup as the source deliverable. Chinese previews
  are for user review only and must not be committed unless the user explicitly
  asks.
- Do not include machine-specific local absolute paths anywhere in the visible
  report, reproduction commands, captions, or generated documentation. Use
  repo-relative evidence paths or placeholders such as `<verifier-repo>`,
  `<candidate-project>`, `<godot-4.6-console-executable>`, and
  `<agent-runs-root>`.
- Keep exactly one consolidated score table. `Calibration And Scores` is the
  only place that should tabulate formal logic score, pass/fail,
  screenshot auxiliary score, captured PNG count, and score/PDF evidence.
  `Screenshot Evidence` must not add another score table; keep that section to
  narrative visual-review notes and embedded example frames.
- Every screenshot-probe rerun or screenshot-analysis result must be reflected
  in the HTML in the same update. Update the consolidated score table, the
  screenshot narrative notes, and the embedded representative frames when the
  frame set changes.
- Embed report screenshots directly in the HTML as data URIs. Do not reference
  separate screenshot image files from the report. The report may explain where
  full raw frames can be inspected using repo-relative evidence paths and the
  `score.json` fields such as `screenshot_probe_dir` and `probe_result`, but it
  must not print local absolute paths.
- The screenshot examples should show real frames from retained runs and should
  explain what actual test screenshots are used for: reference behavior, ablated
  absence of grenade evidence, and at least one failure/anomaly case.
- Any formal 100/100 rollout contradicted by screenshot evidence, suspect flags,
  or manual review must be labeled as an anomalous failure case and grouped with
  failure analysis, not presented as a success. For this submission, the Codex
  full-score record should explicitly be called out as the anomaly that
  motivated the screenshot-analysis iteration.
- The `Rollout Runs` table must include every retained agent-run branch as a
  separate row. For this submission, that means all nine runs: three Claude Code
  Sonnet 5 medium, three Claude Code Opus 4.8 max, and three Codex GPT-5 xhigh
  runs. Do not collapse Opus, Sonnet, or Codex into only a family summary.
- The `Rollout Runs` table must not duplicate the consolidated score table.
  Do not include formal score, pass/fail, screenshot auxiliary score, captured
  PNG count, or score/PDF evidence columns there. Those facts belong only in
  `Calibration And Scores`; `Rollout Runs` may reference score facts only as
  narrative deduction analysis inside `Observed result`.
- Model/tooling labels must be consistent across the report, score summary,
  branch notes, and reproduction notes. For this submission, record that Codex
  runs had Godot MCP available and use the same model labels everywhere.
- The `Observed result` column must provide detailed deduction analysis, not a
  short generic outcome. It should call out category scores, pass-floor
  failures, missed rubric subitems, screenshot footprint measurements, captured
  frame timing when relevant, and whether the defect is agent behavior or
  verifier/report artifact.
- The anti-cheat probe set for this submission is seven representative fake
  candidates. Keep probe branches, implementation notes, report prose, and docs
  aligned to seven unless the user explicitly changes the probe set.
- The writeup must mention that the evaluator used the verifier repository's
  two repo-local skills: `prepare-agent-run-workspace` to create isolated
  agent workspaces and `collect-agent-run-evidence` to collect objective run
  evidence. Future evaluated runs should use the same two-skill workflow.
- Include a verifier repository reference and complete reproduction/use
  instructions: how to prepare an isolated run, run the grader, collect
  evidence, inspect score JSON/PDF/log/screenshot outputs, export a debug arena
  if needed, and record the exact Godot 4.6 version and command used.
- Do not add a `Final Submission Checklist` section, duplicate footer status
  block, or informal "updated on" footer unless the user explicitly asks for
  that content.

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
$Verifier = "<verifier-repo>"
$Project = "<candidate-project>"
$Godot = "<godot-4.6-console-executable>"

python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json"
```

Run with a PDF report:

```powershell
$Verifier = "<verifier-repo>"
$Project = "<candidate-project>"
$Godot = "<godot-4.6-console-executable>"

python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json" `
  --pdf-report "$Verifier\artifacts\score-report.pdf"
```

Run unit tests:

```powershell
python -m unittest discover -s tests
```

Run calibration:

```powershell
$Verifier = "<verifier-repo>"
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_calibration.ps1"
```

Export a manual debug arena:

```powershell
$Verifier = "<verifier-repo>"
$Project = "<candidate-project>"

python "$Verifier\export_debug_arena.py" `
  --project "$Project" `
  --out "$Verifier\artifacts\debug-arena"
```

## Verification Expectations

Before claiming a verifier change is complete, run the narrowest relevant test
command and record the result. For scoring or Godot-runner changes, prefer a
real headless verifier run or calibration pass in addition to Python unit tests
when the required Godot executable is available.

Record the exact Godot executable and version used for any calibration or
assignment evidence.
