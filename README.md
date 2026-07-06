# RoboBlast Grenade Verifier

Private external verifier for the RoboBlast grenade weapon benchmark. It grades
candidate Godot projects behaviorally, out of 100, by copying the project to a
temporary directory, injecting `verifier_godot/__verifier__`, running Godot
unattended, and writing structured score artifacts. Full formal scoring uses a
render-capable Godot mode because rendered presentation evidence is part of the
score.

The assignment source of truth is `game_take_home.html`. See `BENCHMARK.md` for
the benchmark construct, agent protocol, candidate interface contract, scoring
interpretation, and reproducibility rules.

## Repository Map

| Path | Purpose |
| --- | --- |
| `run_grader.py` | Main CLI entry point for unattended formal grading. |
| `verifier_godot/__verifier__/` | Godot-side deterministic behavioral checks. |
| `report_renderer.py`, `render_report.py` | PDF score report generation. |
| `export_debug_arena.py` | Exports a manual Godot debug arena matching verifier layout. |
| `BENCHMARK.md` | Benchmark definition and evaluation protocol. |
| `probe_matrix.md` | Anti-cheat probe expectations and observed results. |
| `evaluation/evidence/` | Curated score JSON evidence for calibration and probes. |
| `evaluation/probes/` | Fake near-miss probe cases used to test verifier robustness. |
| `skills/prepare-agent-run-workspace/` | Repo-local skill for preparing isolated agent run workspaces. |
| `skills/collect-agent-run-evidence/` | Repo-local skill for collecting objective run evidence after an agent finishes. |
| `tests/` | Python tests for runner behavior, report rendering, export, and consistency checks. |

## Requirements

- Godot 4.6 console executable.
- Python 3.11+.
- Report/test dependencies when rendering PDFs or running the full test suite:

```powershell
python -m pip install -r requirements.txt
```

## Quick Start

Set paths for your local checkout and tools:

```powershell
$Verifier = "<path-to-this-repo>"
$Godot = "<path-to-godot-4.6-console-executable>"
$Project = "<path-to-candidate-project>"
```

Run the verifier against a candidate Godot project:

```powershell
python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json" `
  --log "$Verifier\artifacts\godot-verifier.log"
```

The default run is a complete formal score and uses `--render-mode windowed` so
Godot can capture rendered projectile and explosion evidence. Headless runs are
for diagnostic checks only when screenshot scoring is intentionally skipped:

```powershell
python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\diagnostic-score.json" `
  --render-mode headless `
  --skip-screenshot-scoring
```

Write a detailed PDF report in the same run:

```powershell
python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json" `
  --pdf-report "$Verifier\artifacts\score-report.pdf" `
  --log "$Verifier\artifacts\godot-verifier.log"
```

Render a PDF later from an existing score JSON:

```powershell
python "$Verifier\render_report.py" `
  "$Verifier\artifacts\score.json" `
  "$Verifier\artifacts\score-report.pdf"
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
| `hud_feedback` | 8 |
| `trajectory_preview` | 17 |
| `projectile_physics` | 15 |
| `explosion_gameplay` | 20 |
| `visual_audio_polish` | 20 |
| `stability_repeatability` | 5 |

The score JSON exposes the official benchmark only as `score/max_score`, with a
`Formal Score` entry in `score_sections`. The old `logic_score` and
`logic_max_score` aliases are intentionally removed because the formal score now
includes render-backed presentation evidence.

`visual_audio_polish` includes formal render-backed presentation evidence and
runtime presentation checks. Rendered projectile footprint and rendered
explosion footprint are each worth 5 points, with up to 3 points from the
controlled debug arena and up to 2 points from the real main scene. Footprints
that are too small lose credit; oversized projectile frames lose credit only
when oversize persists across frames or controlled views, and oversized
explosions lose credit only when they stay full-screen or broadly obstructive.
Projectile asset quality and explosion VFX asset quality are each worth 3
points and do not reward mere visibility, avoiding double-counting with rendered
footprint checks. Detonation audio is worth 2 points, temporary visual cleanup
is worth 1 point, and runtime presentation consistency is worth 1 point.
Trajectory preview visibility and aim agreement remain gameplay communication
inside `trajectory_preview`.

Weapon switching is behavioral. The verifier drives `swap_weapons` or
`weapon_switch` when those actions exist, and falls back to a real `Tab` input
event when a candidate implements the key path directly. Controller binding
credit is recorded separately and does not depend on a specific action name.

The `passed` flag is a reporting convenience. It currently requires
`score >= 85` plus half-credit floors in the core gameplay categories:
`trajectory_preview >= 9`, `projectile_physics >= 8`, and
`explosion_gameplay >= 10`, plus a repeatability/integration floor of
`stability_repeatability >= 5`. There is no `visual_audio_polish` pass floor;
rendered presentation quality affects the formal score directly. The primary
benchmark signal is the 0-100 score and category breakdown.

The score JSON can also include a soft `suspect` flag with `suspect_reasons`
for manual review. Suspect conditions include global damage sweeps, damaged
far/side/rear safety targets, and player self-damage.

## Agent Run Workflow

The evaluated agent must receive only the ablated task workspace and the
agent-facing prompt. Do not give the agent this verifier repo, hidden tests,
scoring details, original solution history, calibration artifacts, or other
task branches.

### Skills

The two repo-local skills are intentionally split by trust boundary and timing.
The evaluated agent should not run either script.

#### `prepare-agent-run-workspace`

Use this before the agent starts. It is an operator-side setup step that creates
an isolated `workspace/` from the ablated task project and an adjacent
evaluator-owned `evidence/` directory.

It strips hidden/verifier/solution files, initializes a fresh local git repo in
`workspace/`, creates the baseline commit, copies the task prompt into
`evidence/prompt.md`, and writes `evidence/run-manifest.json`,
`evidence/baseline-sha.txt`, and `evidence/prompt-for-agent.md`.

Give the agent only the prepared `workspace/` path and the text from
`evidence/prompt-for-agent.md`. Do not give the agent `evidence/`, this
verifier repo, original solution history, hidden probes, or scoring details.

#### `collect-agent-run-evidence`

Use this after the agent has stopped. It is an operator-side finalization step
that records what the agent actually changed in the prepared workspace.

It reads the local git repo in `workspace/`, records `git-status.txt`, writes a
binary-capable `diff.patch` from baseline to final state, creates or records
the final commit SHA in `final-sha.txt`, copies `AGENT_RUN_RECORD.md` when the
agent created one, and updates `run-manifest.json` with finalized evidence
paths.

After the external verifier runs, call it again with `--score-json` and
`--grader-command` so `evidence/` contains the score artifact and the exact
command that produced it. Treat `AGENT_RUN_RECORD.md` as useful context, not as
objective evidence; the formal evidence is the diff, manifest, score JSON, log,
grader command, and any transcript/tool artifacts.

### Commands

For evaluated rollout runs, prefer the repo-local preparation skill:

```powershell
$Verifier = "<path-to-this-repo>"
$AblatedProject = "<path-to-ablated-task-project>"
$RunRoot = "<path-to-agent-runs>\run-01-cc-sonnet"
$TaskPrompt = "<path-to-task-prompt>\TASK_PROMPT.md"

python "$Verifier\skills\prepare-agent-run-workspace\scripts\setup_agent_run.py" `
  --source "$AblatedProject" `
  --run-root "$RunRoot" `
  --agent cc-sonnet `
  --model "model/version if known" `
  --tool "Godot MCP available" `
  --godot-mcp available `
  --prompt "$TaskPrompt"
```

This creates `workspace/` for the agent and evaluator-owned `evidence/` beside
it. Give the agent the `workspace/` path and the contents of
`evidence/prompt-for-agent.md`.

After the agent finishes, collect objective evidence:

```powershell
python "$Verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root "$RunRoot"
```

After running the verifier, re-run evidence collection with the score and exact
grader command:

```powershell
$ScoreJson = "<path-to-score-json>"
$GraderCommand = 'python "<path-to-this-repo>\run_grader.py" --project "<path-to-agent-run>\workspace" --godot "<path-to-godot-4.6-console-executable>" --out "<path-to-score-json>"'

python "$Verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root "$RunRoot" `
  --score-json "$ScoreJson" `
  --grader-command "$GraderCommand"
```

For a plain clean rollout copy without baseline/evidence metadata, use:

```powershell
python "$Verifier\prepare_rollout_workspace.py" `
  --project "$AblatedProject" `
  --out "<path-to-clean-rollout-workspace>" `
  --force
```

## Debug Arena Export

Export the verifier arena for manual inspection in Godot:

```powershell
python "$Verifier\export_debug_arena.py" `
  --project "$Project" `
  --out "$Verifier\artifacts\debug-arena"
```

Open the exported project in Godot and run:

```text
res://__verifier__/debug_arena.tscn
```

The debug scene uses the same deterministic arena shell and fixed seed target
generation as the grader. It measures default throw distance, places nearby
damage targets and far/side/rear safety targets, and adds camera, light, floor,
and labels for inspection.

Mouse safety is enabled in verifier-owned scenes. The debug arena starts with
the cursor visible, `F8` toggles temporary mouse capture for manual aiming, and
`Esc` releases the cursor. Automated grenade throws continue to use Godot input
actions and do not require cursor capture.

## Experimental Screenshot Probe

The screenshot probe remains an auxiliary visual-evidence runner for debugging
and report inspection. Its standalone result is not itself the formal 0-100
score and every standalone probe result marks `used_for_score: false`.

```powershell
python "$Verifier\run_screenshot_probe.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out-dir "$Verifier\artifacts\screenshot-probe" `
  --mode both
```

Modes:

| Mode | Evidence |
| --- | --- |
| `debug-arena` | Controlled verifier arena screenshots every 10 physics frames after grenade throw until explosion or timeout. |
| `main-scene` | Real `res://main.tscn` ready, aim, grenade-ready, and post-throw screenshots when the playable scene exposes a player and camera. |
| `both` | Runs `debug-arena` and `main-scene`, writing separate `debug_arena/` and `main_scene/` artifact folders. It intentionally does not run `trajectory-shadow`. |
| `trajectory-shadow` | Opt-in shadow evidence for grenade trajectory preview. It captures per-heading gameplay-view and side-oblique baselines/previews, extracts baseline-difference pixel masks, combines them with runtime projectile tracking, and writes `modes.trajectory_shadow` with `used_for_score: false`. |

The standalone top-level `result.json` contains one `modes` entry per attempted visual run.
It also includes an `auxiliary_score_sections` entry for the screenshot visual
analysis. That auxiliary section is scored out of 10: 1 point for runnable
rendered capture, 2 points for visible projectile evidence, 2 points for
observed explosion evidence, and 5 points for projectile footprint quality
across the debug arena and main scene screenshots. It is marked
`used_for_score: false`. The formal grader has its own render-backed
presentation scoring inside `visual_audio_polish`.
Windowed rendering can be unavailable on headless machines; that is reported as
probe infrastructure state rather than as a candidate scoring failure.

`trajectory-shadow` is a shadow-analysis mode for calibrating screenshot-based
trajectory evidence. It is deliberately excluded from `both` and remains
calibration evidence rather than a separate formal score. The visual mask is derived only from per-heading clean-baseline
pixel differences in verifier-defined analysis regions; runtime projectile
tracking is reported separately as hybrid context. Use this mode to compare
reference, ablated, near-miss, and agent-run behavior before changing the
formal trajectory or presentation rubric.

## Calibration And Evidence

Run local calibration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_calibration.ps1"
```

Run trajectory shadow calibration after changing the shadow probe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_trajectory_shadow_calibration.ps1"
```

The trajectory-shadow calibration runner compares reference, ablated,
fixed-trajectory, damage-no-preview, Sonnet-3, and high-score Codex workspaces.
Treat that output as threshold calibration evidence, not as a formal score.

This script reruns the ablated and reference checks. The probe and rollout rows
below are curated evidence produced by the probe materializer and agent-run
evidence workflows, not by `run_calibration.ps1` alone.

Latest local calibration was recorded on 2026-07-06 with Godot
`4.6.stable.official.89cea1439` and the `score >= 85` pass line, before
render-backed presentation evidence was folded into the formal score. After the
render-backed scoring change, refresh at least the reference, ablated task,
seven active probes, and any retained rollout rows that still appear in a
published report. The three deleted Codex run rows do not need to be rerun.

| Candidate or probe | Score | Result |
| --- | ---: | --- |
| Ablated task branch `codex/grenade-rollout-task` at `fb0fd4f` | Previous rubric: 11/100 | Fails as expected. |
| Reference `main` at `1cf08f7` | Previous rubric: 93/100 | Passes. |
| Global targetable sweep probe at `14310ca` | Previous rubric: 80/100 | Fails; `explosion_gameplay` capped to 4/20 and `suspect: true`. |
| HUD-only probe | Previous rubric: 17/100 | Caught. |
| Visual-only/no-damage probe | Previous rubric: 33/100 | Caught. |
| Damage-without-preview probe | Previous rubric: 78/100 | Caught by the trajectory floor. |
| Fixed-trajectory probe | Previous rubric: 57/100 | Caught. |
| Bad-distance probe | Previous rubric: 58/100 | Caught. |
| Single-use probe | Previous rubric: 90/100 | `passed: false`; `stability_repeatability` floor catches one-shot grenade behavior. |
| Historical wrong-projectile-model overlay evidence | 98/100 | Retained as pre-reweighting evidence only; the active probe set no longer includes this high-scoring model-only probe. |

Curated calibration, probe, and replacement Codex rollout score evidence lives
under `evaluation/evidence/`. Anti-cheat expectations are documented in
`probe_matrix.md`.

Published rollout branches in the game repository record three attempts per
agent family, each with branch-captured `score.json`, `score-report.pdf`,
`diff.patch`, verifier log, grader command, and run manifest under
`evaluation/agent-runs/<run>/`:

| Agent run family | Scores |
| --- | --- |
| `agent-run/01-codex` through `agent-run/03-codex` | Previous rubric: 73/100, 75/100, 100/100; the 100/100 record was report-classified as an anomalous failure because screenshot evidence did not support a clean visual pass |
| `agent-run/01-cc-opus` through `agent-run/03-cc-opus` | Previous rubric: 74/100, 88/100, 80/100 |
| `agent-run/01-cc-sonnet` through `agent-run/03-cc-sonnet` | Previous rubric: 77/100, 82/100, 59/100 |

The Codex 100/100 anomaly is also documented as the concrete trigger for the
later screenshot-analysis iteration: retained frames exposed a visual mismatch
that the previous formal score alone did not communicate.

The replacement Codex score JSONs, PDF reports, logs, commands, and manifests
are retained under
`evaluation/evidence/agent-runs-20260703-151656/run-0{1,2,3}-codex/`.

The assignment writeup is not currently retained in this repository. If a new
HTML report is regenerated later, keep its reproduction section complete. It
must include the verifier repository entry, the `prepare-agent-run-workspace`
and `collect-agent-run-evidence` workflow, the full `run_grader.py` command
with `--verifier-root`, `--pdf-report`, and `--log`, the operator/agent trust
boundary, and the evidence files reviewers should inspect after a run. Do not
write machine-specific local absolute paths in new or refreshed documentation,
including reviewer-facing docs, generated reports, README files, and AGENTS
instructions; use repo-relative paths or placeholders such as
`<verifier-repo>`, `<candidate-project>`, `<godot-4.6-console-executable>`,
and `<agent-runs-root>`. Any formal 100/100 rollout contradicted by screenshot
evidence, suspect flags, or manual review must be labeled as an anomalous
failure case and grouped with failure analysis, not presented as a success. If
the mismatch motivates new screenshot-analysis checks, explain that iteration
in the report.

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
