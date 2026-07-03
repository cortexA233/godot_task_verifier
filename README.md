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

For weapon switching, the verifier first drives the `swap_weapons` input action when it exists. If a candidate implements the player-facing `Tab` key directly instead of registering that action, the verifier falls back to injecting a real `Tab` key event through Godot's input event path.

## Rollout Workspace Export

Before giving an ablated task project to a rollout agent, create a clean agent-facing copy:

```powershell
python C:\recent_project\roboblast-grenade-verifier\prepare_rollout_workspace.py `
  --project C:\path\to\ablated-task-project `
  --out C:\path\to\clean-rollout-workspace `
  --force
```

The exporter keeps runnable Godot resources and task prompts while excluding git history, Godot caches, local agent config, verifier folders, generated artifacts, debug exports, temporary files, and assignment/verifier files such as `AGENTS.md`, `CLAUDE.md`, `game_take_home.html`, `BENCHMARK.md`, and `probe_matrix.md`.

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

This scene uses the same deterministic arena shell as the grader. When it starts, it performs one target-free default throw, measures the safe projectile travel distance, rebuilds the arena, and places radial nearby damage targets at 6, 8, 10, and 12 units for every 20-degree direction group around the player inside a 30-unit target field. It also shows a 25-unit safety ring used by the formal `FarTarget`, `LeftSideTarget`, `RightSideTarget`, and `RearTarget` checks. If debug-scene calibration cannot measure a usable throw, it shows a 4-14 unit distance band of labeled damage targets instead of pretending the fixed 8-unit fallback is authoritative. The debug scene adds a camera, light, visible floor, and labels so manual inspection matches the grader's radial setup.

## Score Categories

- `weapon_controls`: 15 points
- `hud_feedback`: 10 points
- `trajectory_preview`: 30 points
- `projectile_physics`: 15 points
- `explosion_gameplay`: 20 points
- `visual_audio_polish`: 5 points
- `stability_repeatability`: 5 points

The score is behavioral. It does not require historical filenames, class names, node paths, or signal names.
The `stability_repeatability` category now includes a real `res://main.tscn`
smoke check for default shooting, melee, targetable actors, damageable actors,
and coin/pickup behavior in addition to the deterministic verifier arena.

## Calibration

Explosion scoring calibrates default throw distance behaviorally. The runner measures a target-free throw, accepts only a nearby player-safe travel path, gives full throw-distance quality credit to a 6-12 unit default landing distance, and treats 4-14 units as borderline usable but worth `0/2` calibration-quality points. Formal explosion trials are generated from fixed seed constants: each seed deterministically picks a heading, nearby target radii around the canonical 6, 8, 10, and 12 unit rings plus the measured landing distance, and a far/side/rear safety radius inside the 30-unit target field. Every run of the same verifier version uses the same seeded variants. A trial gives full nearby-damage credit for the seeded expected direction group and partial credit for real localized damage in another radial group, so the verifier can distinguish hard-coded directions without false-negativing every coordinate-convention mismatch. Detonation effects are observed inside the same 30-unit target field, but explosion gameplay still requires real damage evidence before effect or safety credit is awarded. Safety targets remain far enough to catch over-large explosions without moving inward with explosion radius. Trajectory preview scoring now emphasizes visible aiming aid behavior, arcing or landing-area communication, aim/camera reactivity, and broad direction consistency with the actual thrown grenade.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Latest local calibration:

- Godot executable: `C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe`
- Godot version: `4.6.stable.official.89cea1439`
- Ablated task branch: `11/100`; no grenade projectile is available, so explosion calibration falls back, trajectory preview scores 0, and explosion gameplay scores 0.
- Reference branch: not available at `C:\recent_project\godot-4-3d-third-person-controller-reference` during the latest local run.

The ablated score is low because the grenade weapon behavior is absent. The
trajectory-preview gates, fixed-seed radial target variants, adaptive calibration, and
frame-window effect observation reduce false negatives from exact
throw-distance mismatch and short-lived presentation effects while keeping
missing grenade behavior low-scoring.

## Probe Matrix

Anti-cheat probe expectations are documented in `probe_matrix.md`. Each probe should receive only the relevant partial credit rather than a high score.
