# RoboBlast Grenade Verifier

Private external verifier for the RoboBlast grenade weapon benchmark. It grades
candidate Godot projects behaviorally, out of 100, by copying the project to a
temporary directory, injecting `verifier_godot/__verifier__`, running Godot
headlessly, and writing structured score artifacts.

The assignment source of truth is `game_take_home.html`. See `BENCHMARK.md` for
the benchmark construct, agent protocol, candidate interface contract, scoring
interpretation, and reproducibility rules.

## Repository Map

| Path | Purpose |
| --- | --- |
| `run_grader.py` | Main CLI entry point for headless grading. |
| `verifier_godot/__verifier__/` | Godot-side deterministic behavioral checks. |
| `report_renderer.py`, `render_report.py` | PDF score report generation. |
| `export_debug_arena.py` | Exports a manual Godot debug arena matching verifier layout. |
| `BENCHMARK.md` | Benchmark definition and evaluation protocol. |
| `probe_matrix.md` | Anti-cheat probe expectations and observed results. |
| `evaluation/writeup.html` | Browser-viewable assignment writeup with visuals. |
| `evaluation/evidence/` | Curated score JSON evidence for calibration and probes. |
| `evaluation/probes/` | Fake near-miss probe cases used to test verifier robustness. |
| `skills/prepare-agent-run-workspace/` | Repo-local skill for preparing isolated agent run workspaces. |
| `skills/collect-agent-run-evidence/` | Repo-local skill for collecting objective run evidence after an agent finishes. |
| `tests/` | Python tests for runner behavior, report rendering, export, and consistency checks. |

## Requirements

- Godot 4.6 console executable. Current calibration used
  `C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe`.
- Python 3.11+.
- Report/test dependencies when rendering PDFs or running the full test suite:

```powershell
python -m pip install -r requirements.txt
```

## Quick Start

Run the verifier against a candidate Godot project:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  --log C:\recent_project\roboblast-grenade-verifier\artifacts\godot-verifier.log
```

Write a detailed PDF report in the same run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  --pdf-report C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf `
  --log C:\recent_project\roboblast-grenade-verifier\artifacts\godot-verifier.log
```

Render a PDF later from an existing score JSON:

```powershell
python C:\recent_project\roboblast-grenade-verifier\render_report.py `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

## What The Verifier Measures

The verifier grades observable gameplay behavior rather than exact filenames,
class names, node paths, or signal names. It exercises real game systems in a
deterministic arena and checks whether the candidate implements a usable
grenade weapon while preserving existing RoboBlast gameplay.

Score categories:

| Category | Points |
| --- | ---: |
| `weapon_controls` | 15 |
| `hud_feedback` | 10 |
| `trajectory_preview` | 30 |
| `projectile_physics` | 15 |
| `explosion_gameplay` | 20 |
| `visual_audio_polish` | 5 |
| `stability_repeatability` | 5 |

Weapon switching is behavioral. The verifier drives `swap_weapons` or
`weapon_switch` when those actions exist, and falls back to a real `Tab` input
event when a candidate implements the key path directly. Controller binding
credit is recorded separately and does not depend on a specific action name.

The `passed` flag is a reporting convenience. It currently requires
`score >= 85` plus half-credit floors in the core gameplay categories:
`trajectory_preview >= 15`, `projectile_physics >= 8`, and
`explosion_gameplay >= 10`. The primary benchmark signal is the 0-100 score and
category breakdown.

The score JSON can also include a soft `suspect` flag with `suspect_reasons`
for manual review. Suspect conditions include global damage sweeps, damaged
far/side/rear safety targets, and player self-damage.

## Agent Run Workflow

The evaluated agent must receive only the ablated task workspace and the
agent-facing prompt. Do not give the agent this verifier repo, hidden tests,
scoring details, original solution history, calibration artifacts, or other
task branches.

For evaluated rollout runs, prefer the repo-local preparation skill:

```powershell
python C:\recent_project\roboblast-grenade-verifier\skills\prepare-agent-run-workspace\scripts\setup_agent_run.py `
  --source C:\path\to\ablated-task-project `
  --run-root C:\path\to\agent-runs\run-01-cc-sonnet `
  --agent cc-sonnet `
  --model "model/version if known" `
  --tool "Godot MCP available" `
  --godot-mcp available `
  --prompt C:\path\to\TASK_PROMPT.md
```

This creates `workspace/` for the agent and evaluator-owned `evidence/` beside
it. Give the agent the `workspace/` path and the contents of
`evidence/prompt-for-agent.md`.

After the agent finishes, collect objective evidence:

```powershell
python C:\recent_project\roboblast-grenade-verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py `
  --run-root C:\path\to\agent-runs\run-01-cc-sonnet
```

After running the verifier, re-run evidence collection with the score and exact
grader command:

```powershell
python C:\recent_project\roboblast-grenade-verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py `
  --run-root C:\path\to\agent-runs\run-01-cc-sonnet `
  --score-json C:\path\to\score.json `
  --grader-command 'python C:\recent_project\roboblast-grenade-verifier\run_grader.py --project C:\path\to\agent-runs\run-01-cc-sonnet\workspace --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" --out C:\path\to\score.json'
```

For a plain clean rollout copy without baseline/evidence metadata, use:

```powershell
python C:\recent_project\roboblast-grenade-verifier\prepare_rollout_workspace.py `
  --project C:\path\to\ablated-task-project `
  --out C:\path\to\clean-rollout-workspace `
  --force
```

## Debug Arena Export

Export the verifier arena for manual inspection in Godot:

```powershell
python C:\recent_project\roboblast-grenade-verifier\export_debug_arena.py `
  --project C:\path\to\candidate-project `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena
```

Open the exported project in Godot and run:

```text
res://__verifier__/debug_arena.tscn
```

The debug scene uses the same deterministic arena shell and fixed seed target
generation as the grader. It measures default throw distance, places nearby
damage targets and far/side/rear safety targets, and adds camera, light, floor,
and labels for inspection.

## Calibration And Evidence

Run local calibration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Latest local calibration was recorded on 2026-07-03 with Godot
`4.6.stable.official.89cea1439` and the `score >= 85` pass line.

| Candidate or probe | Score | Result |
| --- | ---: | --- |
| Ablated task branch `codex/grenade-rollout-task` at `fb0fd4f` | 13/100 | Fails as expected. |
| Reference `main` at `1cf08f7` | 91/100 | Passes. |
| Global targetable sweep probe at `14310ca` | 78/100 | Fails; `explosion_gameplay` capped to 4/20. |
| HUD-only probe | 19/100 | Caught. |
| Visual-only/no-damage probe | 34/100 | Caught. |
| Damage-without-preview probe | 54/100 | Caught. |
| Fixed-trajectory probe | 65/100 | Caught. |
| Bad-distance probe | 50/100 | Caught. |
| Single-use probe | 75/100 | Caught. |

Curated calibration and probe score JSONs live under `evaluation/evidence/`.
Anti-cheat expectations are documented in `probe_matrix.md`.

Published rollout branches in the game repository record three attempts per
agent family, each with branch-captured `score.json`, `score-report.pdf`,
`diff.patch`, verifier log, grader command, and run manifest under
`evaluation/agent-runs/<run>/`:

| Agent run family | Scores |
| --- | --- |
| `codex/agent-run-01-codex` through `codex/agent-run-03-codex` | 6/100, 28/100, 28/100 |
| `codex/agent-run-01-cc-opus` through `codex/agent-run-03-cc-opus` | 74/100, 88/100, 80/100 |
| `codex/agent-run-01-cc-sonnet` through `codex/agent-run-03-cc-sonnet` | 77/100, 82/100, 59/100 |

The repository writeup for the assignment is `evaluation/writeup.html`.

## Development

Run unit tests:

```powershell
python -m unittest discover -s tests -v
```

Useful narrow checks:

```powershell
python run_grader.py --help
python -m py_compile run_grader.py report_renderer.py render_report.py export_debug_arena.py
```

Generated runtime artifacts should stay out of git unless they are deliberately
curated evidence. The normal scratch locations are `artifacts/` and `tmp/`.
