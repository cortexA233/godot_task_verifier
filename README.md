# RoboBlast Grenade Verifier

External verifier for the RoboBlast grenade weapon benchmark.

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json
```

The verifier copies the candidate project to a temporary directory, imports resources in that copy, injects `verifier_godot\__verifier__`, runs Godot headlessly, and writes a 0-100 JSON result.

For weapon switching, the verifier first drives the `swap_weapons` input action when it exists. If a candidate implements the player-facing `Tab` key directly instead of registering that action, the verifier falls back to injecting a real `Tab` key event through Godot's input event path.

To write a one-page PDF summary during grading, add `--pdf-report`:

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

PDF rendering uses ReportLab. If your default `python` does not have it, use the bundled Codex Python runtime or install `reportlab` in the Python environment you use to run the report command.

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

This scene uses the same deterministic arena layout as the grader's front explosion trial: the real `player/player.tscn`, optional weapon UI, `NearTargetA`, `NearTargetB`, `FarTarget`, `LeftSideTarget`, `RightSideTarget`, and `RearTarget`. The grader also runs rotated left-front and right-front explosion trials headlessly. The debug scene adds a camera, light, visible floor, and labels so the target placement is easy to inspect.

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

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_calibration.ps1
```

Latest local calibration:

- Ablated task branch: `13/100`
- Reference branch: `87/100`

The ablated score is low because the grenade weapon behavior is absent. The reference score is high enough to prove discrimination, while leaving room for the verifier to distinguish partial agent attempts.

## Probe Matrix

Anti-cheat probe expectations are documented in `probe_matrix.md`. Each probe should receive only the relevant partial credit rather than a high score.
