# Screenshot-Assisted Visual Probe Design

## Context

The current branch already has an experimental screenshot probe that can run a
render-capable Godot window, switch to the grenade, throw it in the verifier
debug arena, and capture frames every 10 physics frames until an explosion-like
node appears. A recent candidate run showed that these screenshots expose a real
visual defect: the grenade logic and explosion can look acceptable in the formal
score, while the thrown grenade model is visibly wrong in rendered frames.

The formal grader still needs to stay deterministic and headless. Godot 4.6
headless mode uses a display path that does not reliably expose viewport pixels,
so screenshots must remain an auxiliary render-capable run for this iteration.
The new design adds richer visual evidence without changing the official
0-100 score, category floors, or `passed` semantics.

## Goals

- Capture screenshot evidence for both the deterministic verifier debug arena
  and the real `res://main.tscn` playable scene.
- Keep the formal grader's default headless score path unchanged.
- Record projectile-focused visual metrics before detonation so model defects
  are visible in machine-readable output as well as PNG artifacts.
- Make render-capable runs opportunistic: unavailable windowed rendering should
  be reported clearly, not treated as a candidate failure.
- Keep the implementation scoped enough that screenshot evidence can later be
  calibrated into scoring, but does not become scoring in this change.

## Non-Goals

- Do not change the 100-point score allocation.
- Do not change the `visual_audio_polish >= 4` pass floor.
- Do not use whole-frame screenshot similarity as a formal oracle.
- Do not require a specific grenade resource path, node path, class name, or
  material name.
- Do not commit generated screenshots or probe logs, except deliberately curated
  evidence in a separate calibration task.

## Approaches Considered

Recommended: extend the auxiliary screenshot probe into two visual run modes.
The debug arena mode remains the controlled probe for grenade-specific evidence.
The main scene mode loads `res://main.tscn`, waits for the playable scene to
settle, captures ready and attack evidence, then drives the same grenade window
when possible. The CLI runs both by default and writes separate artifact folders
plus one summary JSON. This preserves deterministic formal scoring while adding
the real-scene screenshot coverage the benchmark writeup wants.

Alternative: wire screenshots directly into `run_grader.py` after the headless
score completes. This would give one command a richer artifact bundle, but it
mixes official scoring infrastructure with an environment-dependent windowed
step. A windowing failure could look like grader instability even when the
formal score is valid.

Alternative: promote rendered projectile footprint to formal scoring now. This
would catch the observed defect more strongly, but it needs calibration against
the reference, rollout attempts, and wrong-model probes before it is safe. It is
better as a follow-up after the screenshot artifacts and metrics are stable.

## Architecture

Keep `run_grader.py` as the formal grader entry point. It continues to copy the
candidate project, inject `verifier_godot/__verifier__`, run Godot with
`--headless`, and write the official score JSON.

Extend `run_screenshot_probe.py` as the render-capable auxiliary entry point.
It still copies and injects the candidate project, performs a headless import,
then runs a normal windowed Godot process with a verifier script. Its interface
should grow a small mode selector:

```text
--mode debug-arena | main-scene | both
```

The default should be `both`, because the user-facing probe should answer two
different questions in one command:

- Does the grenade render correctly in the controlled debug arena?
- Does the candidate's real main scene still load, run, and show the grenade
  workflow in a playable context?

Create a deeper Godot-side visual probe module rather than expanding one large
script forever. The external seam should stay small: a script can request a
visual run mode and receive a structured result with captures, stop reason,
render availability, and optional projectile metrics. Internally, debug arena
setup, main scene setup, screenshot capture, projectile tracking, and explosion
node detection can be separated without leaking those details into Python.

## Debug Arena Visual Run

The debug arena visual run should keep the current deterministic behavior:

1. Set the root viewport size to a fixed value, initially `1280x720`.
2. Instantiate `res://__verifier__/debug_arena.tscn`.
3. Wait until `DebugCamera` and `DebugVisibleFloor` exist.
4. Wait a short render-settle window.
5. Switch to grenade through `swap_weapons`, `weapon_switch`, or the existing
   verifier fallback action.
6. Capture the baseline screenshot signature before attack.
7. Tap `attack`.
8. Capture one screenshot every 10 physics frames.
9. Stop when explosion-like nodes are observed or when the max post-throw frame
   budget is reached.

The output folder should be `debug_arena/` under the user-supplied artifact
directory. Capture filenames should stay frame-labeled, for example
`attack_010.png`, `attack_020.png`, and `attack_080.png`.

## Main Scene Visual Run

The main scene visual run should load the candidate's real `res://main.tscn`
rather than the verifier arena. It is auxiliary evidence, so it can be more
conservative about what it claims.

The run should:

1. Set the root viewport size to the same fixed value as the debug arena run.
2. Load and instantiate `res://main.tscn`.
3. Wait for a playable player using the same broad heuristic as
   `_find_main_scene_player`: a node named `Player`, or a `CharacterBody3D`
   with `collect_coin`.
4. Wait for the scene to settle and for a current camera to become available.
5. Capture `main_ready.png`.
6. Hold or tap `aim` briefly when available and capture `main_aim.png`.
7. Try to switch to grenade, capture `grenade_ready.png`, then tap `attack`.
8. Capture one screenshot every 10 physics frames until an explosion-like node
   appears or the max frame budget is reached.

The main scene run should not fail the whole probe because the real scene has a
different camera path, intro state, or missing player heuristic. Instead, it
should write `ok: false` for `main_scene` with a concrete `reason`, while the
debug arena result can still be useful.

The main scene output folder should be `main_scene/`. Its filenames should be
semantic for setup frames and frame-labeled for attack frames:
`main_ready.png`, `main_aim.png`, `grenade_ready.png`, `attack_010.png`, and so
on.

## Projectile Visual Metrics

The probe should record projectile-focused metrics, but not score them yet. A
good first pass is:

- Track candidate projectile nodes created after `attack`.
- Prefer moving `Node3D` candidates near the player whose horizontal travel
  exceeds the existing minimum projectile distance.
- For each screenshot frame before explosion, project the candidate into the
  active camera's screen space.
- Estimate a screen-space rectangle from visible mesh AABBs when possible.
- Record local pixel activity in that rectangle compared with the pre-attack
  baseline.

The per-capture result should allow future scoring experiments to read data like
this:

```json
{
  "label": "attack_040",
  "projectile_visual": {
    "available": true,
    "visible": true,
    "screen_rect": [620, 330, 18, 14],
    "area_px": 252,
    "delta_in_rect": 0.04
  }
}
```

An experimental aggregate can also be written:

```json
{
  "projectile_footprint": {
    "used_for_score": false,
    "best_frame": "attack_040",
    "visible_frame_count": 3,
    "max_area_px": 252,
    "max_delta_in_rect": 0.04
  }
}
```

When no camera, no projectile candidate, no viewport pixels, or no projected
screen rectangle is available, the metric should explain that as structured
data. It should not silently report zero in a way that looks like a candidate
visual failure.

## Result JSON

`run_screenshot_probe.py` should copy PNGs, logs, and one top-level
`result.json` into the requested output directory. The result should make the
non-scoring status impossible to miss:

```json
{
  "ok": true,
  "used_for_score": false,
  "display_driver": "Windows",
  "godot_version": "4.6-stable",
  "modes": {
    "debug_arena": {
      "ok": true,
      "artifact_dir": "debug_arena",
      "screenshot_interval_frames": 10,
      "stop_reason": "explosion_observed",
      "explosion_frame": 80,
      "captures": []
    },
    "main_scene": {
      "ok": true,
      "artifact_dir": "main_scene",
      "screenshot_interval_frames": 10,
      "stop_reason": "max_frames",
      "explosion_frame": -1,
      "captures": []
    }
  }
}
```

Top-level `ok` should mean the probe infrastructure ran and wrote a result, not
that every mode succeeded. Each mode owns its own `ok` and `reason`.

## Error Handling

Windowed rendering can be unavailable on some machines. If Godot cannot create a
render-capable window, the CLI should return a clear infrastructure code and
write `run.log`. If the window opens but viewport capture is unavailable, the
mode result should mark screenshots unavailable and include the display driver
and reason from `SceneProbe`.

The probe should keep copying partial artifacts even when one mode fails. This
matters because `main_scene` is expected to be less deterministic than the debug
arena.

## Testing

Add tests before implementation:

- A structural test that the screenshot probe exposes `--mode` with
  `debug-arena`, `main-scene`, and `both`.
- A structural test that the Godot visual runner references `res://main.tscn`,
  writes `debug_arena` and `main_scene` mode results, and keeps
  `used_for_score: false`.
- A structural test that captures remain every 10 frames until explosion or max
  frames.
- A Godot-backed windowed test, skipped when Godot or a render-capable display
  is unavailable, that verifies the debug arena mode writes PNGs and mode JSON.
- A Godot-backed windowed smoke test for a minimal temporary `main.tscn` with a
  player-like `CharacterBody3D` and camera, verifying that `main_ready.png` and
  a `main_scene` mode result are written.

For this iteration, a formal `run_grader.py` score comparison is not required
because the official scoring path is intentionally unchanged. A focused
regression run against the previously inspected candidate is still useful as
manual acceptance evidence.

## Documentation Updates

Update `README.md` after implementation to document the new auxiliary command
and artifact layout. The wording should say that screenshot evidence is
experimental and not part of the official score.

Update `BENCHMARK.md` only if the benchmark evidence section starts referencing
these artifacts. If screenshots later affect scoring, then `README.md`,
`BENCHMARK.md`, calibration notes, and `probe_matrix.md` must be updated in the
same scoring change.

## Acceptance Criteria

- `run_grader.py` remains headless and produces the same formal score semantics.
- `run_screenshot_probe.py --mode both` attempts both debug arena and main scene
  visual runs.
- Debug arena screenshots are captured every 10 physics frames after grenade
  throw until explosion or timeout.
- Main scene screenshots include at least a settled ready frame when
  `res://main.tscn` can load and expose a playable player and camera.
- The result JSON clearly marks every screenshot and projectile metric as
  `used_for_score: false`.
- Partial mode failures are reported with reasons and do not erase artifacts
  from successful modes.
- Generated screenshots and logs stay under ignored artifact paths unless a
  later calibration task deliberately curates them.
