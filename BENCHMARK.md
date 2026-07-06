# RoboBlast Grenade Benchmark Definition

Date: 2026-07-06

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
- Agent-facing task commit: `fb0fd4f3e74d12c9da82acf7f36a9add06dade02`
- Ablation base branch: `codex/ablate-grenade-keep-assets`
- Ablation base commit: `ed35453f23ee219747d8706f4cd147acb2de7d37`
- Agent prompt: `TASK_PROMPT.md` in the task branch
- Reference implementation: local `main` branch of the task repository
- Local reference commit: `1cf08f7c9ff11cf3d9617b611c2447a04dc79fe4`
- Local git-stripped reference copy used for grading:
  `<path-to-reference-main-complete>`

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
- Prefer preparing evaluated workspaces with the repo-local
  `prepare-agent-run-workspace` skill before the agent starts. It creates an
  isolated `workspace/` plus evaluator-owned `evidence/`, strips local git
  history, verifier files, generated artifacts, and assignment/verifier
  instruction files, then records the baseline SHA and agent-facing prompt.
- After the agent stops, use the repo-local `collect-agent-run-evidence` skill
  to capture the objective diff, final SHA, manifest updates, and later the
  score JSON plus exact grader command. Use `prepare_rollout_workspace.py` only
  for plain clean copies that do not need baseline/evidence metadata.
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
  key path that the player scene receives through Godot input. Scoring is
  behavioral: any of these routes earns switch credit when the mode change is
  observable, and a controller (joypad) binding on a weapon-switch route earns
  the controller-input detail. No points depend on the action name itself.
- Damageable targets should react through existing gameplay conventions. The
  verifier's test targets expose `damage(impact_point, force)`. Most are placed
  in both `damageables` and `targeteables` groups to match enemies, and some
  explosion probes are damageable-only to model destructible objects.

This contract should be treated as part of the benchmark, not as a hint about
the historical grenade implementation.

## Scoring

The verifier grades out of 100:

- `weapon_controls`: 15
- `hud_feedback`: 8
- `trajectory_preview`: 17
- `projectile_physics`: 15
- `explosion_gameplay`: 20
- `visual_audio_polish`: 20
- `stability_repeatability`: 5

The emitted score JSON keeps the formal `score/max_score` as the 100-point
benchmark result, with a `Formal Score` entry in `score_sections`. The old
`logic_score/logic_max_score` aliases are intentionally removed because the
formal score now includes render-backed presentation evidence. Standalone
screenshot-probe output remains auxiliary evidence with `used_for_score: false`,
but the formal grader folds rendered projectile and explosion footprint evidence
into `visual_audio_polish`.

`visual_audio_polish` includes rendered projectile footprint (5), rendered
explosion footprint (5), thrown grenade model asset quality (3), explosion VFX
asset quality (3), detonation audio (2), temporary visual cleanup (1), and
runtime presentation consistency (1). Rendered footprint checks score
screen-space readability: too-small projectiles or explosions lose credit,
oversized projectile frames lose credit only when oversize persists across
frames or controlled views, and oversized explosions lose credit only when they
remain full-screen or broadly obstructive. The controlled debug arena
contributes up to 3 points and the real main scene contributes up to 2 points
for each rendered footprint item. Asset-quality details follow runtime objects
and reject built-in primitive placeholders and obvious reused non-grenade
assets without double-counting mere visibility. Placeholder presentation is a
score penalty, not an automatic pass blocker, so a candidate can still pass if
the core gameplay is strong enough. Trajectory preview visibility and aim
agreement remain gameplay communication inside `trajectory_preview`; model,
VFX, rendered footprint, audio, cleanup, and presentation consistency live in
`visual_audio_polish`.

`stability_repeatability` includes both deterministic verifier-arena repeat use
checks and a real `res://main.tscn` smoke check for default shooting, melee,
targetable/damageable actors, and coin/pickup behavior.

Explosion-gameplay trials use fixed seed constants to generate a small
deterministic suite of headings, nearby target radii, nearby damageable-only
destructible probes, and far/side/rear safety placements. The suite is
parameterized enough to reduce single-layout overfitting, but the seeds are
fixed so the same verifier version gives the same candidate the same score.
The scoring treats blast locality as a core requirement: broad damage sweeps
that hit most nearby targets and multiple safety targets are capped inside
`explosion_gameplay` even if they also hit the expected nearby targets.

The `passed` flag currently uses `score >= 85` as a report convenience, and it
additionally requires at least half credit in each core gameplay category:
`trajectory_preview >= 9/17`, `projectile_physics >= 8/15`, and
`explosion_gameplay >= 10/20`, plus a repeatability/integration floor of
`stability_repeatability >= 5/5`. There is no `visual_audio_polish` pass floor;
rendered presentation quality affects the formal score directly. The score JSON records the threshold in
`pass_threshold` and lists any floor misses in `category_floor_failures`, so a
candidate cannot pass by stacking supporting-category points while a core
category or repeated-use/integration behavior stays badly broken. The primary benchmark signal is the 0-100 score and
category breakdown. The 2026-07-06 active probe refresh is previous-rubric
evidence: it had six probes below the numeric `score >= 85` line, a single-use
probe at `90/100` blocked by the `stability_repeatability` floor, and the
reference implementation passing at `93/100`. Because render-backed
presentation evidence now affects the formal score, refresh the reference,
ablated task, seven active probes, and any retained rollout rows before
publishing current evidence. A reference score below 100 should be inspected as
either reference incompleteness or a possible verifier false negative; it is not
proof that the verifier is perfect.

Complete formal scoring requires render-capable screenshot capture. Headless or
no-screenshot-analysis runs are diagnostic only and must be marked
`formal_score_complete: false`, `diagnostic_only: true`, and list omitted
formal screenshot components. If screenshot capture is required but unavailable,
the run is verifier infrastructure failure rather than a candidate scoring
penalty.

The score JSON also carries a soft `suspect` flag with `suspect_reasons`.
Global damage sweeps, damaged far/side/rear safety targets, and player
self-damage flag the run for manual review without changing the score or the
category breakdown.

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
$Verifier = "<path-to-this-repo>"
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_calibration.ps1"
```

The calibration script reruns the ablated and reference checks and writes score
JSON plus logs under `artifacts/`. Probe and rollout rows in the published
calibration tables are curated evidence produced by separate probe
materialization and agent-run workflows. Record the exact Godot executable and
version from the logs with every published result.

## Validity Probes

`probe_matrix.md` lists anti-cheat probes, expected score bands, observed
results, and explicitly deferred overlapping rows. Every observed probe must
either stay below the `score >= 85` numeric pass line or, for deliberate
high-score floor-fail cases such as single-use behavior, report
`passed: false` through a documented category floor. Record each probe run in
the matrix's Observed column and keep the score JSON as curated evidence under
`evaluation/evidence/`. The current local validation set should demonstrate:

- the ablated task scores low
- the reference behavior scores high
- representative HUD-only, visual-only, no-preview damage, fixed or wrong
  trajectory, global targetable sweep, borderline throw-distance, and
  single-use implementations do not pass; single-use is a deliberate
  high-score floor-fail case because repeated use is required behavior
- deferred direct all-target damage, player-self-damage, one-angle/one-distance
  blast, distant-target damage, and default-weapon regression rows are
  explicitly documented in `probe_matrix.md` rather than treated as silent
  passes
- repeated runs of the same candidate produce stable scores

Probe candidates should be kept outside rollout-agent workspaces.
