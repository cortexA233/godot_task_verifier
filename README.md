# RoboBlast Grenade Verifier

External verifier for the RoboBlast grenade weapon benchmark.

See `BENCHMARK.md` for the evaluation objective, agent protocol, candidate
interface contract, and reproducibility notes.

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json
```

The verifier copies the candidate project to a temporary directory, imports resources in that copy, injects `verifier_godot\__verifier__`, runs Godot headlessly, and writes a 0-100 JSON result.

For weapon switching, the verifier first drives the `swap_weapons` input action when it exists. If a candidate implements the player-facing `Tab` key directly instead of registering that action, the verifier falls back to injecting a real `Tab` key event through Godot's input event path.

To write a detailed PDF score report during grading, add `--pdf-report`:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" `
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

This scene uses the same deterministic arena shell as the grader. When it starts, it performs one target-free default throw, measures the safe projectile travel distance, rebuilds the arena, and places nearby damage targets across the 6-12 unit forward band with left/center/right offsets, plus `FarTarget`, `LeftSideTarget`, `RightSideTarget`, and `RearTarget` safety targets. If debug-scene calibration cannot measure a usable throw, it shows a 4-14 unit distance band of labeled damage targets instead of pretending the fixed 8-unit fallback is authoritative. The debug scene adds a camera, light, visible floor, and labels so manual inspection matches the grader's adaptive setup.

## Score Categories

- `weapon_controls`: 15 points
- `hud_feedback`: 15 points
- `trajectory_preview`: 20 points
- `projectile_physics`: 15 points
- `explosion_gameplay`: 20 points
- `visual_audio_polish`: 10 points
- `stability_repeatability`: 5 points

The score is behavioral. It does not require historical filenames, class names, node paths, or signal names.

## Calibration

Explosion scoring calibrates default throw distance behaviorally. The runner measures a target-free throw, accepts only a nearby player-safe travel path, gives the strongest calibration confidence to a 6-12 unit default landing distance, and treats 4-14 units as borderline usable. Formal explosion trials place several nearby damage targets across the 6-12 unit forward band with left/center/right offsets; each trial receives nearby-damage credit when any nearby target is damaged. Safety targets stay strict and do not move inward with explosion radius.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Latest local calibration:

- Godot executable: `C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`
- Godot version: `4.7.stable.mono.official.5b4e0cb0f`
- Ablated task branch: `13/100`; no grenade projectile is available, so explosion calibration falls back and explosion gameplay scores 0.
- Reference branch: not available at `C:\recent_project\godot-4-3d-third-person-controller-reference` during the latest local run.

The ablated score is low because the grenade weapon behavior is absent. The
nearby target band, adaptive calibration, and frame-window effect observation
reduce false negatives from exact throw-distance mismatch and short-lived
presentation effects.

## Probe Matrix

Anti-cheat probe expectations are documented in `probe_matrix.md`. Each probe should receive only the relevant partial credit rather than a high score.
