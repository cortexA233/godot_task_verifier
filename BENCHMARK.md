# RoboBlast Grenade Benchmark Definition

Date: 2026-07-03

This repository is a single-task benchmark MVP for evaluating whether coding
agents can implement a cross-cutting gameplay feature in an existing Godot
project. It is not yet a multi-task leaderboard benchmark.

## Evaluation Objective

The benchmark evaluates an agent's ability to implement a player-facing grenade
weapon in RoboBlast while preserving existing gameplay. A strong solution must
coordinate input handling, weapon state, HUD feedback, trajectory preview,
projectile physics, localized explosion effects, visual/audio feedback, cleanup,
and regressions in the default weapon.

The benchmark does not primarily evaluate code-style mimicry or recovery of the
historical implementation. Valid alternate implementations should receive high
credit when their observable behavior matches the task.

## Task Resources

Use these resources for the current local benchmark run:

- Agent-facing task branch: `codex/grenade-rollout-task`
- Agent-facing task commit: `886077385809a142f70e04188f43c276982f01d8`
- Ablation base branch: `codex/ablate-grenade-keep-assets`
- Ablation base commit: `ed35453f23ee219747d8706f4cd147acb2de7d37`
- Agent prompt: `TASK_PROMPT.md` in the task branch
- Local reference project path: `C:\recent_project\godot-4-3d-third-person-controller-reference`
- Local reference commit: `2f6d792fc83a1a6453437f4b9412bc31cc13584d`

The rollout agent should receive only the ablated task project and
`TASK_PROMPT.md`. It must not receive this verifier repository, original
solution history, hidden branches, calibration artifacts, probe notes, or
reference project contents.

## Agent Protocol

Record the following for each rollout attempt:

- agent product and model/version
- starting task commit
- prompt/spec text supplied to the agent
- tool access, including whether Godot editor, Godot MCP, shell, or internet
  documentation access was available
- time, token, and hidden-verifier-run budgets
- final diff or patch
- exact verifier command, Godot version, score JSON, and log
- manual observations and known limitations

Recommended protocol for comparable runs:

- Give the agent the ablated task workspace and `TASK_PROMPT.md`.
- Do not expose the verifier source, score rubric internals, calibration
  artifacts, reference implementation, git history, or other task branches.
- Allow normal local inspection and Godot execution inside the candidate
  workspace.
- Allow public documentation lookup, but forbid looking up the RoboBlast grenade
  solution or online copies of the same feature.
- Run the hidden verifier after the agent submits its final candidate. If
  iterative hidden-verifier feedback is allowed, record every run and do not
  compare that score directly against one-shot runs.
- Treat candidate crashes, verifier timeouts, or missing `project.godot` as
  grader-infrastructure failures with score `0/100` unless a result JSON is
  produced.
- For nondeterminism audits, run the same final candidate multiple times and
  report each score rather than only the best score.

## Candidate Interface Contract

The verifier is behavioral, but it still needs a stable project entry contract:

- The candidate project must be a Godot project with `project.godot`.
- The player scene must be loadable from `res://player/player.tscn`.
- The main player attack and aim controls should remain compatible with the
  project's existing `attack` and `aim` actions.
- Weapon switching should use `swap_weapons`, `weapon_switch`, or a real `Tab`
  key path that the player scene receives through Godot input.
- Damageable targets should react through existing gameplay conventions. The
  verifier's test targets expose `damage(impact_point, force)` and are placed in
  `damageables` and `targeteables` groups to match the local game style.

This contract should be treated as part of the benchmark, not as a hint about
the historical grenade implementation.

## Scoring

The verifier grades out of 100:

- `weapon_controls`: 15
- `hud_feedback`: 10
- `trajectory_preview`: 30
- `projectile_physics`: 15
- `explosion_gameplay`: 20
- `visual_audio_polish`: 5
- `stability_repeatability`: 5

The `passed` flag currently uses `score >= 85` as a report convenience. The
primary benchmark signal is the 0-100 score and category breakdown. A reference
score below 100 should be inspected as either reference incompleteness or a
possible verifier false negative; it is not proof that the verifier is perfect.

## Reproducibility

Install report/test dependencies when PDF reports or full tests are needed:

```powershell
python -m pip install -r requirements.txt
```

Run verifier tests:

```powershell
python -m unittest discover -s tests -v
```

Run local calibration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

The calibration script writes score JSON and logs under `artifacts/`. Record the
exact Godot executable and version from the logs with every published result.

## Validity Probes

`probe_matrix.md` lists anti-cheat probes and expected score bands. At minimum,
local validation should demonstrate:

- the ablated task scores low
- the reference behavior scores high
- HUD-only, direct-damage, visual-only, fixed or wrong trajectory, broad-damage,
  borderline throw-distance, and single-use implementations do not receive high
  scores
- repeated runs of the same candidate produce stable scores

Probe candidates should be kept outside rollout-agent workspaces.
