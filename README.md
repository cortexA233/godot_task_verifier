# RoboBlast Grenade Verifier

External verifier for the RoboBlast grenade weapon benchmark.

See `BENCHMARK.md` for the evaluation objective, agent protocol, candidate
interface contract, and reproducibility notes.

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json
```

The verifier copies the candidate project to a temporary directory, imports resources in that copy, injects `verifier_godot\__verifier__`, runs Godot headlessly, and writes a 0-100 JSON result.

For weapon switching, the verifier drives the project's `swap_weapons` or `weapon_switch` input action when one exists. If a candidate implements the player-facing `Tab` key directly instead of registering an action, the verifier falls back to injecting a real `Tab` key event through Godot's input event path. Weapon-switch scoring is behavioral: observable switching earns credit through any of these routes, and a controller (joypad) binding on a weapon-switch route earns a separate controller-input detail instead of any points depending on the action name.

## Rollout Workspace Export

Before giving an ablated task project to a rollout agent, create a clean agent-facing copy:

```powershell
python C:\recent_project\roboblast-grenade-verifier\prepare_rollout_workspace.py `
  --project C:\path\to\ablated-task-project `
  --out C:\path\to\clean-rollout-workspace `
  --force
```

The exporter keeps runnable Godot resources and the agent-facing `TASK_PROMPT.md` while excluding git history, Godot caches, local agent config, verifier folders, generated artifacts, debug exports, temporary files, localized prompt drafts, and assignment/verifier files such as `AGENTS.md`, `CLAUDE.md`, `game_take_home.html`, `BENCHMARK.md`, and `probe_matrix.md`.

To write a detailed PDF score report during grading, add `--pdf-report`:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  --pdf-report C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

You can also render a PDF from an existing score JSON:

```powershell
python C:\recent_project\roboblast-grenade-verifier\render_report.py `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

PDF rendering uses ReportLab. Install the Python dependencies with `python -m pip install -r requirements.txt` (or use the bundled Codex Python runtime) in the environment you use to run the report command. The PDF preserves full category notes and includes per-check earned or missed point details when the score JSON contains `details`.

## Debug Arena Export

To inspect the verifier arena manually in Godot, export a debug project copy:

```powershell
python C:\recent_project\roboblast-grenade-verifier\export_debug_arena.py `
  --project C:\path\to\candidate-project `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\debug-arena
```

Open the exported project in Godot, then run:

```text
res://__verifier__/debug_arena.tscn
```

This scene uses the same deterministic arena shell and fixed seed target generation as the grader. When it starts, it performs one target-free default throw, measures the safe projectile travel distance, rebuilds the arena, and places the seeded nearby damage targets plus far/side/rear safety targets used by the formal explosion trials. If debug-scene calibration cannot measure a usable throw, it shows a 4-14 unit distance band of labeled damage targets instead of pretending the fixed 8-unit fallback is authoritative. The debug scene adds a camera, light, visible floor, and labels so manual inspection matches the grader's seeded layout.

## Score Categories

- `weapon_controls`: 15 points
- `hud_feedback`: 10 points
- `trajectory_preview`: 30 points
- `projectile_physics`: 15 points
- `explosion_gameplay`: 20 points
- `visual_audio_polish`: 5 points
- `stability_repeatability`: 5 points

The score is behavioral. It does not require historical filenames, class names, node paths, or signal names.
The `passed` flag in the score JSON is a report convenience meaning `score >= 85`
plus half-credit pass floors in the core gameplay categories
(`trajectory_preview >= 15`, `projectile_physics >= 8`, `explosion_gameplay >= 10`);
the primary benchmark signal is the 0-100 score and category breakdown. The JSON
also carries a soft `suspect` flag with `suspect_reasons` when global damage
sweeps, damaged safety targets, or player self-damage need manual review.
The `stability_repeatability` category now includes a real `res://main.tscn`
smoke check for default shooting, melee, targetable actors, damageable actors,
and coin/pickup behavior in addition to the deterministic verifier arena.

## Calibration

Explosion scoring calibrates default throw distance behaviorally. The runner measures a target-free throw, accepts only a nearby player-safe travel path, gives full throw-distance quality credit to a 6-12 unit default landing distance, and treats 4-14 units as borderline usable but worth `0/2` calibration-quality points. Formal explosion trials are generated from fixed seed constants: each seed deterministically picks a heading, nearby target radii around the canonical 6, 8, 10, and 12 unit rings plus the measured landing distance, and a far/side/rear safety radius inside the 30-unit target field. Every run of the same verifier version uses the same seeded variants. Explosion gameplay now separates nearby target damage, nearby damageable-only/destructible damage, blast locality, player safety, detonation effects, and throw-distance quality. Global damage sweeps that hit most nearby targets and multiple safety targets are capped within `explosion_gameplay`, so "damage every enemy in the scene" does not score like a localized blast. Trajectory preview scoring emphasizes visible aiming aid behavior, arcing or landing-area communication, aim/camera reactivity, and broad direction consistency with the actual thrown grenade.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Latest local calibration (2026-07-03, `score >= 85` pass line):

- Godot executable: `C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe`
- Godot version: `4.6.stable.official.89cea1439`
- Ablated task branch `codex/grenade-rollout-task` commit `fb0fd4f`: `13/100`, `passed: false`; no grenade projectile is available, so explosion calibration falls back, trajectory preview scores 0, and explosion gameplay scores 0.
- Reference `main` commit `1cf08f7`: `91/100`, `passed: true`, with localized explosion gameplay at `17/20`.
- Global targetable sweep probe branch `codex/grenade-global-enemy-damage` commit `14310ca`: `78/100`, `passed: false`, with `explosion_gameplay` capped to `4/20` after global damage sweep detection.
- Three Claude Code Sonnet rollout candidates score `80/100`, `78/100`, and `13/100` under the same verifier; see `evaluation/writeup.html`.
- Committed score JSONs for these runs live under `evaluation/evidence/`.

The ablated score is low because the grenade weapon behavior is absent. The
trajectory-preview gates, fixed-seed radial target variants, adaptive calibration,
damageable-only destructible probe, global-sweep cap, and frame-window effect
observation reduce false negatives from exact throw-distance mismatch and
short-lived presentation effects while keeping missing or reward-hacked grenade
behavior low-scoring.

## Probe Matrix

Anti-cheat probe expectations are documented in `probe_matrix.md`. Each probe should receive only the relevant partial credit rather than a high score.
