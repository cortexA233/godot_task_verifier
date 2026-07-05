# Trajectory Shadow Screenshot Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit `trajectory-shadow` screenshot probe mode that emits non-scoring hybrid trajectory evidence for preview direction, aim/camera updates, and arcing throw communication.

**Architecture:** Keep the formal headless 0-100 grader unchanged. Extend the existing screenshot probe entry point with a new explicit mode, and put the side-oblique trajectory analysis in a focused Godot module. Each heading run uses a fresh verifier debug arena, captures a per-heading clean baseline before grenade preview appears, extracts visual masks only from baseline-difference pixels, and combines those visual metrics with runtime projectile tracking in `used_for_score: false` JSON.

**Tech Stack:** Python `argparse`/`subprocess`/`unittest`; PowerShell calibration script; Godot 4.6 GDScript; existing verifier helpers in `SceneProbe`, `InputDriver`, and `debug_arena.tscn`.

---

## Design Constraints To Preserve

- The formal `run_grader.py` score, category floors, and pass/fail logic do not change.
- `trajectory-shadow` is opt-in. It is not folded into existing `--mode both`.
- Every top-level and mode-level result keeps `"used_for_score": false`.
- Screenshot recognition uses only baseline/current pixel differences inside verifier-defined analysis regions.
- Runtime node tracking is allowed as separate hybrid evidence, but it must not define or seed the visual mask.
- Each heading gets a clean debug-arena instance and its own baseline, so previous throws, particles, cooldowns, and weapon state cannot pollute the image diff.
- Existing gameplay/debug-camera captures and new side-oblique captures are both required. The side-oblique view makes the arc readable; the gameplay view is the visibility gate.
- Initial thresholds are provisional and must be calibrated on reference, ablated, fixed-trajectory, damage-no-preview, Sonnet-3, and a high-score agent run before any future scoring discussion.

## File Structure

- Create `verifier_godot/__verifier__/trajectory_shadow_probe.gd`: owns `trajectory-shadow` setup, side-oblique camera placement, per-heading clean baselines, baseline-difference mask metrics, runtime projectile tracking, provisional verdicts, and mode result shape.
- Modify `verifier_godot/__verifier__/screenshot_probe_runner.gd`: preload `TrajectoryShadowProbe`, accept `trajectory-shadow`, call it only when that mode is explicitly requested, and keep `both` unchanged.
- Modify `run_screenshot_probe.py`: expose `--mode trajectory-shadow`, pass it through to Godot, and print the provisional verdict when present.
- Create `tests/test_trajectory_shadow_probe.py`: focused structural and Godot-backed tests for mode plumbing, pixel-only mask extraction, JSON contract, and a reference-project smoke run.
- Modify `README.md`: document `trajectory-shadow`, its artifact layout, its shadow/non-scoring status, and the calibration set.
- Create `run_trajectory_shadow_calibration.ps1`: local batch runner for the six agreed calibration cases.

## Result Shape

The top-level `result.json` keeps the current screenshot probe shape and adds a `modes.trajectory_shadow` entry only for `--mode trajectory-shadow`:

```json
{
  "used_for_score": false,
  "requested_mode": "trajectory-shadow",
  "modes": {
    "trajectory_shadow": {
      "ok": true,
      "artifact_dir": "trajectory_shadow",
      "used_for_score": false,
      "provisional_verdict": "healthy",
      "headings_degrees": [-35.0, 0.0, 35.0],
      "summary": {
        "used_for_score": false,
        "healthy_heading_count": 3,
        "suspect_heading_count": 0,
        "missing_heading_count": 0,
        "gameplay_preview_visible_count": 3,
        "side_preview_arc_like_count": 3,
        "runtime_direction_match_count": 3,
        "gameplay_centroid_spread_px": 180.0,
        "visual_claims": {
          "preview_matches_projectile_direction": "healthy",
          "updates_with_aim_camera_direction": "healthy",
          "communicates_arcing_throw": "healthy"
        }
      },
      "heading_results": []
    }
  }
}
```

The numeric values above are example values for the contract. Tests should assert the field names and types, not these example numbers.

## Task 1: Add Failing Structural Tests

**Files:**
- Create: `tests/test_trajectory_shadow_probe.py`

- [ ] **Step 1: Write the focused structural test file**

Create `tests/test_trajectory_shadow_probe.py` with this content:

```python
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHADOW_PROBE = ROOT / "verifier_godot" / "__verifier__" / "trajectory_shadow_probe.gd"


def find_godot() -> Path | None:
    configured = Path(r"C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe")
    if configured.exists():
        return configured
    found = shutil.which("godot")
    return Path(found) if found else None


class TrajectoryShadowProbeTests(unittest.TestCase):
    def test_cli_and_runner_expose_explicit_trajectory_shadow_mode(self):
        cli_source = (ROOT / "run_screenshot_probe.py").read_text(encoding="utf-8")
        runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")

        self.assertIn('choices=["debug-arena", "main-scene", "both", "trajectory-shadow"]', cli_source)
        self.assertIn('"--probe-mode"', cli_source)
        self.assertIn('const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")', runner_source)
        self.assertIn('const VALID_MODES := ["debug-arena", "main-scene", "both", "trajectory-shadow"]', runner_source)
        self.assertIn('if requested_mode == "trajectory-shadow":', runner_source)
        self.assertIn('mode_results["trajectory_shadow"] = await trajectory_probe.run()', runner_source)
        self.assertNotIn('requested_mode == "trajectory-shadow" or requested_mode == "both"', runner_source)
        self.assertNotIn('requested_mode == "both" or requested_mode == "trajectory-shadow"', runner_source)

    def test_shadow_probe_declares_pixel_only_baseline_diff_metrics(self):
        self.assertTrue(SHADOW_PROBE.exists())
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        self.assertIn("func _baseline_diff_metrics", source)
        self.assertIn("PIXEL_DIFF_THRESHOLD", source)
        self.assertIn("GAMEPLAY_ANALYSIS_REGION", source)
        self.assertIn("SIDE_ANALYSIS_REGION", source)
        self.assertIn("changed_pixel_count", source)
        self.assertIn("estimated_area_px", source)
        self.assertIn("suggests_arc", source)
        self.assertNotIn("projectile_screen_rect", source)
        self.assertNotIn("visible_nodes_suggest_arc_or_landing", source)

    def test_shadow_probe_declares_non_scoring_json_contract(self):
        self.assertTrue(SHADOW_PROBE.exists())
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        for token in [
            '"artifact_dir": MODE_NAME',
            '"used_for_score": false',
            '"provisional_verdict"',
            '"heading_results"',
            '"headings_degrees"',
            '"visual_claims"',
            '"preview_matches_projectile_direction"',
            '"updates_with_aim_camera_direction"',
            '"communicates_arcing_throw"',
            '"gameplay_centroid_spread_px"',
            '"runtime_direction_match_count"',
        ]:
            self.assertIn(token, source)
        self.assertNotIn("board.add", source)
        self.assertNotIn('"score"', source)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the structural tests and verify the expected failure**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: FAIL. The failure should mention that `trajectory_shadow_probe.gd` does not exist or that `trajectory-shadow` is missing from the CLI and runner.

- [ ] **Step 3: Commit the failing tests**

```powershell
git add tests\test_trajectory_shadow_probe.py
git commit -m "test: cover trajectory shadow probe contract"
```

## Task 2: Wire The Explicit Mode And Add The Probe Skeleton

**Files:**
- Modify: `run_screenshot_probe.py`
- Modify: `verifier_godot/__verifier__/screenshot_probe_runner.gd`
- Create: `verifier_godot/__verifier__/trajectory_shadow_probe.gd`
- Test: `tests/test_trajectory_shadow_probe.py`

- [ ] **Step 1: Update the Python CLI choices**

In `run_screenshot_probe.py`, replace the `--mode` argument with this block:

```python
    parser.add_argument(
        "--mode",
        choices=["debug-arena", "main-scene", "both", "trajectory-shadow"],
        default="both",
        help="Screenshot probe mode to run. Defaults to debug arena plus main scene evidence; trajectory-shadow must be requested explicitly.",
    )
```

- [ ] **Step 2: Print a trajectory-shadow verdict when present**

Replace the per-mode `print` inside `main()` with this block:

```python
        for mode_name, mode_result in result.get("modes", {}).items():
            stop_label = mode_result.get("provisional_verdict", mode_result.get("stop_reason", "unknown"))
            print(
                f"{mode_name}: ok={mode_result.get('ok', False)} "
                f"stop={stop_label} "
                f"frame={mode_result.get('explosion_frame', -1)} "
                f"screenshots={len(mode_result.get('captures', []))}"
            )
```

- [ ] **Step 3: Preload the new Godot module**

In `verifier_godot/__verifier__/screenshot_probe_runner.gd`, add this line below the existing `ScreenshotVisualProbe` preload:

```gdscript
const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")
```

- [ ] **Step 4: Extend `VALID_MODES` without changing `both` behavior**

Replace the current `VALID_MODES` line with:

```gdscript
const VALID_MODES := ["debug-arena", "main-scene", "both", "trajectory-shadow"]
```

- [ ] **Step 5: Call the trajectory probe only for the explicit mode**

In `_run()`, after the `main-scene` branch, insert:

```gdscript
	if requested_mode == "trajectory-shadow":
		var trajectory_probe := TrajectoryShadowProbe.new(self, input)
		mode_results["trajectory_shadow"] = await trajectory_probe.run()
```

Do not add `or requested_mode == "both"` to this branch.

- [ ] **Step 6: Create the initial Godot module**

Create `verifier_godot/__verifier__/trajectory_shadow_probe.gd` with this content:

```gdscript
extends RefCounted

const DebugArenaScene = preload("res://__verifier__/debug_arena.tscn")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const MODE_NAME := "trajectory_shadow"
const ROOT_SIZE := Vector2i(1280, 720)
const TRAJECTORY_SAMPLE_HEADINGS_DEGREES := [-35.0, 0.0, 35.0]
const GAMEPLAY_ANALYSIS_REGION := Rect2i(96, 80, 1088, 520)
const SIDE_ANALYSIS_REGION := Rect2i(160, 70, 960, 500)
const PIXEL_DIFF_THRESHOLD := 0.18
const DIFF_SCAN_STEP := 1
const MIN_GAMEPLAY_CHANGED_PIXELS := 20
const MIN_SIDE_CHANGED_PIXELS := 32
const MIN_ARC_WIDTH_PX := 80
const MIN_ARC_HEIGHT_PX := 18
const RUNTIME_DIRECTION_MIN_DOT := 0.78

var tree: SceneTree
var input
var root: Window


func _init(p_tree: SceneTree, p_input) -> void:
	tree = p_tree
	input = p_input
	root = tree.root


func run() -> Dictionary:
	_prepare_output_dir("%s/%s" % [OUTPUT_DIR, MODE_NAME])
	return {
		"ok": false,
		"artifact_dir": MODE_NAME,
		"used_for_score": false,
		"stop_reason": "not_executed",
		"provisional_verdict": "suspect",
		"headings_degrees": TRAJECTORY_SAMPLE_HEADINGS_DEGREES,
		"heading_results": [],
		"captures": [],
		"thresholds": _thresholds(),
		"summary": _trajectory_shadow_summary([]),
	}


func _baseline_diff_metrics(before_image: Image, after_image: Image, region: Rect2i, label: String) -> Dictionary:
	return {
		"available": before_image != null and after_image != null,
		"label": label,
		"analysis_region": [region.position.x, region.position.y, region.size.x, region.size.y],
		"changed_pixel_count": 0,
		"estimated_area_px": 0,
		"bbox": [0, 0, 0, 0],
		"centroid": [0.0, 0.0],
		"horizontal_span_px": 0,
		"vertical_span_px": 0,
		"upper_pixel_fraction": 0.0,
		"middle_pixel_fraction": 0.0,
		"lower_pixel_fraction": 0.0,
		"suggests_arc": false,
	}


func _trajectory_shadow_summary(heading_results: Array[Dictionary]) -> Dictionary:
	return {
		"used_for_score": false,
		"healthy_heading_count": 0,
		"suspect_heading_count": 0,
		"missing_heading_count": 0,
		"gameplay_preview_visible_count": 0,
		"side_preview_arc_like_count": 0,
		"runtime_direction_match_count": 0,
		"gameplay_centroid_spread_px": 0.0,
		"visual_claims": {
			"preview_matches_projectile_direction": "missing",
			"updates_with_aim_camera_direction": "missing",
			"communicates_arcing_throw": "missing",
		},
		"heading_count": heading_results.size(),
	}


func _thresholds() -> Dictionary:
	return {
		"pixel_diff_threshold": PIXEL_DIFF_THRESHOLD,
		"diff_scan_step": DIFF_SCAN_STEP,
		"min_gameplay_changed_pixels": MIN_GAMEPLAY_CHANGED_PIXELS,
		"min_side_changed_pixels": MIN_SIDE_CHANGED_PIXELS,
		"min_arc_width_px": MIN_ARC_WIDTH_PX,
		"min_arc_height_px": MIN_ARC_HEIGHT_PX,
		"runtime_direction_min_dot": RUNTIME_DIRECTION_MIN_DOT,
	}


func _prepare_output_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
```

- [ ] **Step 7: Run the structural tests and verify they pass**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS for all three structural tests.

- [ ] **Step 8: Commit the mode skeleton**

```powershell
git add run_screenshot_probe.py verifier_godot\__verifier__\screenshot_probe_runner.gd verifier_godot\__verifier__\trajectory_shadow_probe.gd
git commit -m "feat: add explicit trajectory shadow probe mode"
```

## Task 3: Implement Pixel-Only Baseline Difference Metrics

**Files:**
- Modify: `tests/test_trajectory_shadow_probe.py`
- Modify: `verifier_godot/__verifier__/trajectory_shadow_probe.gd`

- [ ] **Step 1: Add a Godot-backed pixel helper test**

Add this method inside `TrajectoryShadowProbeTests`:

```python
    def test_baseline_diff_metrics_detect_arc_like_changed_pixels_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verifier_dir = tmp_path / "__verifier__"
            verifier_dir.mkdir()
            shutil.copy(SHADOW_PROBE, verifier_dir / "trajectory_shadow_probe.gd")
            shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
            (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
                """
                extends SceneTree

                const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")

                func _init() -> void:
                    call_deferred("_run")

                func _run() -> void:
                    var before_image := Image.create(64, 48, false, Image.FORMAT_RGBA8)
                    before_image.fill(Color(0, 0, 0, 1))
                    var after_image := Image.create(64, 48, false, Image.FORMAT_RGBA8)
                    after_image.fill(Color(0, 0, 0, 1))
                    for x in range(8, 57):
                        var normalized := float(x - 8) / 48.0
                        var y := 32 - int(round(sin(normalized * PI) * 14.0))
                        for dy in range(0, 3):
                            after_image.set_pixel(x, clampi(y + dy, 0, 47), Color(1, 1, 1, 1))
                    var probe := TrajectoryShadowProbe.new(self, null)
                    var metrics: Dictionary = probe._baseline_diff_metrics(before_image, after_image, Rect2i(0, 0, 64, 48), "unit_arc")
                    var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                    file.store_string(JSON.stringify(metrics))
                    quit(0)
                """
            ).strip() + "\n", encoding="utf-8")

            completed = subprocess.run(
                [
                    str(godot),
                    "--path",
                    str(tmp_path),
                    "--script",
                    "res://test_runner.gd",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            output = completed.stdout + completed.stderr
            self.assertEqual(completed.returncode, 0, output)
            result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
            self.assertTrue(result.get("available"), result)
            self.assertGreater(result.get("changed_pixel_count", 0), 100, result)
            self.assertGreater(result.get("horizontal_span_px", 0), 40, result)
            self.assertGreater(result.get("vertical_span_px", 0), 10, result)
            self.assertTrue(result.get("suggests_arc"), result)
```

- [ ] **Step 2: Run the new test and verify the expected failure**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe.TrajectoryShadowProbeTests.test_baseline_diff_metrics_detect_arc_like_changed_pixels_when_available -v
```

Expected: FAIL because `_baseline_diff_metrics` returns zero changed pixels.

- [ ] **Step 3: Replace `_baseline_diff_metrics` with the pixel scanner**

In `trajectory_shadow_probe.gd`, replace `_baseline_diff_metrics` with:

```gdscript
func _baseline_diff_metrics(before_image: Image, after_image: Image, region: Rect2i, label: String) -> Dictionary:
	if before_image == null or after_image == null:
		return _unavailable_diff_metrics(region, label, "baseline or current image unavailable")
	if before_image.get_width() != after_image.get_width() or before_image.get_height() != after_image.get_height():
		return _unavailable_diff_metrics(region, label, "baseline/current image sizes differ")
	var bounds := _clamped_region(region, before_image.get_width(), before_image.get_height())
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return _unavailable_diff_metrics(region, label, "analysis region is empty")

	var changed_count := 0
	var min_x := bounds.position.x + bounds.size.x
	var min_y := bounds.position.y + bounds.size.y
	var max_x := bounds.position.x
	var max_y := bounds.position.y
	var sum_x := 0.0
	var sum_y := 0.0
	var upper_count := 0
	var middle_count := 0
	var lower_count := 0
	var upper_cut := bounds.position.y + int(floor(float(bounds.size.y) / 3.0))
	var lower_cut := bounds.position.y + int(floor(float(bounds.size.y) * 2.0 / 3.0))

	for y in range(bounds.position.y, bounds.position.y + bounds.size.y, DIFF_SCAN_STEP):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x, DIFF_SCAN_STEP):
			var before_color := before_image.get_pixel(x, y)
			var after_color := after_image.get_pixel(x, y)
			var delta := (
				absf(after_color.r - before_color.r)
				+ absf(after_color.g - before_color.g)
				+ absf(after_color.b - before_color.b)
				+ absf(after_color.a - before_color.a)
			) / 4.0
			if delta < PIXEL_DIFF_THRESHOLD:
				continue
			changed_count += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			sum_x += float(x)
			sum_y += float(y)
			if y < upper_cut:
				upper_count += 1
			elif y < lower_cut:
				middle_count += 1
			else:
				lower_count += 1

	if changed_count <= 0:
		return {
			"available": true,
			"label": label,
			"analysis_region": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"changed_pixel_count": 0,
			"estimated_area_px": 0,
			"bbox": [0, 0, 0, 0],
			"centroid": [0.0, 0.0],
			"horizontal_span_px": 0,
			"vertical_span_px": 0,
			"upper_pixel_fraction": 0.0,
			"middle_pixel_fraction": 0.0,
			"lower_pixel_fraction": 0.0,
			"suggests_arc": false,
		}

	var horizontal_span := max_x - min_x + 1
	var vertical_span := max_y - min_y + 1
	var upper_fraction := float(upper_count) / float(changed_count)
	var middle_fraction := float(middle_count) / float(changed_count)
	var lower_fraction := float(lower_count) / float(changed_count)
	var suggests_arc := (
		changed_count >= MIN_SIDE_CHANGED_PIXELS
		and horizontal_span >= MIN_ARC_WIDTH_PX
		and vertical_span >= MIN_ARC_HEIGHT_PX
		and (upper_fraction > 0.02 or middle_fraction > 0.2)
	)
	return {
		"available": true,
		"label": label,
		"analysis_region": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"changed_pixel_count": changed_count,
		"estimated_area_px": changed_count * DIFF_SCAN_STEP * DIFF_SCAN_STEP,
		"bbox": [min_x, min_y, horizontal_span, vertical_span],
		"centroid": [sum_x / float(changed_count), sum_y / float(changed_count)],
		"horizontal_span_px": horizontal_span,
		"vertical_span_px": vertical_span,
		"upper_pixel_fraction": upper_fraction,
		"middle_pixel_fraction": middle_fraction,
		"lower_pixel_fraction": lower_fraction,
		"suggests_arc": suggests_arc,
	}
```

- [ ] **Step 4: Add the helper methods used by the scanner**

Add these methods below `_baseline_diff_metrics`:

```gdscript
func _unavailable_diff_metrics(region: Rect2i, label: String, reason: String) -> Dictionary:
	return {
		"available": false,
		"reason": reason,
		"label": label,
		"analysis_region": [region.position.x, region.position.y, region.size.x, region.size.y],
		"changed_pixel_count": 0,
		"estimated_area_px": 0,
		"bbox": [0, 0, 0, 0],
		"centroid": [0.0, 0.0],
		"horizontal_span_px": 0,
		"vertical_span_px": 0,
		"upper_pixel_fraction": 0.0,
		"middle_pixel_fraction": 0.0,
		"lower_pixel_fraction": 0.0,
		"suggests_arc": false,
	}


func _clamped_region(region: Rect2i, width: int, height: int) -> Rect2i:
	var x0 := clampi(region.position.x, 0, width)
	var y0 := clampi(region.position.y, 0, height)
	var x1 := clampi(region.position.x + region.size.x, x0, width)
	var y1 := clampi(region.position.y + region.size.y, y0, height)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)
```

- [ ] **Step 5: Run the pixel helper tests**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS for the structural tests and the pixel helper test. Tests that require a full reference project are not added until Task 5.

- [ ] **Step 6: Commit the pixel scanner**

```powershell
git add tests\test_trajectory_shadow_probe.py verifier_godot\__verifier__\trajectory_shadow_probe.gd
git commit -m "feat: compute trajectory shadow baseline diff metrics"
```

## Task 4: Capture Per-Heading Gameplay And Side-Oblique Evidence

**Files:**
- Modify: `verifier_godot/__verifier__/trajectory_shadow_probe.gd`
- Test: `tests/test_trajectory_shadow_probe.py`

- [ ] **Step 1: Add a source-level test for clean per-heading runs**

Add this method inside `TrajectoryShadowProbeTests`:

```python
    def test_shadow_probe_uses_fresh_debug_arena_and_two_view_baselines_per_heading(self):
        source = SHADOW_PROBE.read_text(encoding="utf-8")

        self.assertIn("for heading_degrees in TRAJECTORY_SAMPLE_HEADINGS_DEGREES", source)
        self.assertIn("DebugArenaScene.instantiate()", source)
        self.assertIn('"%s/%s" % [OUTPUT_DIR, MODE_NAME]', source)
        self.assertIn('"gameplay_baseline"', source)
        self.assertIn('"side_baseline"', source)
        self.assertIn('"gameplay_preview"', source)
        self.assertIn('"side_preview"', source)
        self.assertIn("_set_side_oblique_camera", source)
        self.assertIn("SIDE_CAMERA_DISTANCE", source)
        self.assertIn("SIDE_CAMERA_HEIGHT", source)
        self.assertIn("SIDE_CAMERA_BACK_OFFSET", source)
```

- [ ] **Step 2: Run the new source-level test and verify the expected failure**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe.TrajectoryShadowProbeTests.test_shadow_probe_uses_fresh_debug_arena_and_two_view_baselines_per_heading -v
```

Expected: FAIL because `run()` still returns the skeleton result.

- [ ] **Step 3: Add side-oblique camera constants**

Add these constants below `RUNTIME_DIRECTION_MIN_DOT`:

```gdscript
const RENDER_SETTLE_FRAMES := 2
const PREVIEW_SETTLE_FRAMES := 8
const DEBUG_ARENA_READY_FRAMES := 540
const SIDE_CAMERA_DISTANCE := 13.0
const SIDE_CAMERA_HEIGHT := 5.0
const SIDE_CAMERA_BACK_OFFSET := 1.5
const SIDE_CAMERA_LOOKAHEAD := 8.5
const SIDE_CAMERA_LOOK_HEIGHT := 1.7
```

- [ ] **Step 4: Replace `run()` with the real heading loop**

Replace `run()` with:

```gdscript
func run() -> Dictionary:
	_prepare_output_dir("%s/%s" % [OUTPUT_DIR, MODE_NAME])
	root.size = ROOT_SIZE
	var heading_results: Array[Dictionary] = []
	var captures: Array[Dictionary] = []
	for heading_degrees in TRAJECTORY_SAMPLE_HEADINGS_DEGREES:
		var heading_result := await _run_heading_sample(float(heading_degrees))
		heading_results.append(heading_result)
		captures.append_array(heading_result.get("captures", []))
	var summary := _trajectory_shadow_summary(heading_results)
	return {
		"ok": not heading_results.is_empty(),
		"artifact_dir": MODE_NAME,
		"used_for_score": false,
		"stop_reason": "completed",
		"provisional_verdict": _overall_verdict(summary),
		"headings_degrees": TRAJECTORY_SAMPLE_HEADINGS_DEGREES,
		"heading_results": heading_results,
		"captures": captures,
		"thresholds": _thresholds(),
		"summary": summary,
	}
```

- [ ] **Step 5: Add the per-heading capture routine**

Add this method below `run()`:

```gdscript
func _run_heading_sample(heading_degrees: float) -> Dictionary:
	var debug_arena := DebugArenaScene.instantiate()
	root.add_child(debug_arena)
	var heading_label := _heading_label(heading_degrees)
	if not await _wait_for_debug_arena_ready(debug_arena):
		debug_arena.queue_free()
		await tree.process_frame
		return _heading_failure(heading_degrees, "debug arena did not become ready")

	var player := debug_arena.find_child("VerifierPlayer", true, false) as Node3D
	var gameplay_camera := debug_arena.find_child("DebugCamera", true, false) as Camera3D
	if player == null or gameplay_camera == null:
		debug_arena.queue_free()
		await tree.process_frame
		return _heading_failure(heading_degrees, "player or debug camera unavailable")

	var heading_y := deg_to_rad(heading_degrees)
	_set_player_heading(player, heading_y)
	var side_camera := _set_side_oblique_camera(debug_arena, player, heading_y)
	await input.wait_physics_frames(PREVIEW_SETTLE_FRAMES)

	gameplay_camera.current = true
	var gameplay_baseline := await _capture_image("%s_gameplay_baseline" % heading_label, root)
	side_camera.current = true
	var side_baseline := await _capture_image("%s_side_baseline" % heading_label, root)

	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(PREVIEW_SETTLE_FRAMES)

	gameplay_camera.current = true
	var gameplay_preview := await _capture_image("%s_gameplay_preview" % heading_label, root)
	side_camera.current = true
	var side_preview := await _capture_image("%s_side_preview" % heading_label, root)

	var gameplay_mask := _baseline_diff_metrics(gameplay_baseline.get("image", null), gameplay_preview.get("image", null), GAMEPLAY_ANALYSIS_REGION, "gameplay_preview")
	var side_mask := _baseline_diff_metrics(side_baseline.get("image", null), side_preview.get("image", null), SIDE_ANALYSIS_REGION, "side_preview")
	var captures := [
		gameplay_baseline.get("record", {}),
		side_baseline.get("record", {}),
		gameplay_preview.get("record", {}),
		side_preview.get("record", {}),
	]
	var result := {
		"heading_degrees": heading_degrees,
		"heading_radians": heading_y,
		"used_for_score": false,
		"captures": captures,
		"gameplay_preview_mask": gameplay_mask,
		"side_preview_mask": side_mask,
		"runtime_projectile": {},
		"side_early_flight_mask": {},
		"provisional_verdict": "suspect",
	}
	debug_arena.queue_free()
	await tree.process_frame
	return result
```

- [ ] **Step 6: Add camera, capture, and setup helpers**

Add these methods below `_run_heading_sample`:

```gdscript
func _set_side_oblique_camera(debug_arena: Node, player: Node3D, heading_y: float) -> Camera3D:
	var camera := debug_arena.find_child("TrajectoryShadowCamera", true, false) as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "TrajectoryShadowCamera"
		debug_arena.add_child(camera)
	var heading_basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (heading_basis * Vector3.FORWARD).normalized()
	var right := (heading_basis * Vector3.RIGHT).normalized()
	camera.current = true
	camera.global_position = player.global_position + right * SIDE_CAMERA_DISTANCE - forward * SIDE_CAMERA_BACK_OFFSET + Vector3.UP * SIDE_CAMERA_HEIGHT
	camera.look_at(player.global_position + forward * SIDE_CAMERA_LOOKAHEAD + Vector3.UP * SIDE_CAMERA_LOOK_HEIGHT, Vector3.UP)
	return camera


func _capture_image(label: String, viewport: Viewport) -> Dictionary:
	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	var capture := SceneProbe.viewport_image(viewport)
	var path := "%s/%s/%s.png" % [OUTPUT_DIR, MODE_NAME, label]
	if not bool(capture.get("available", false)):
		return {
			"image": null,
			"record": {
				"label": label,
				"path": path,
				"available": false,
				"saved": false,
				"used_for_score": false,
				"reason": String(capture.get("reason", "viewport image unavailable")),
			},
		}
	var image: Image = capture["image"]
	var error := image.save_png(path)
	return {
		"image": image,
		"record": {
			"label": label,
			"path": path,
			"available": true,
			"saved": error == OK,
			"error": error,
			"used_for_score": false,
			"width": image.get_width(),
			"height": image.get_height(),
		},
	}


func _wait_for_debug_arena_ready(debug_arena: Node) -> bool:
	for _i in range(DEBUG_ARENA_READY_FRAMES):
		if debug_arena.find_child("DebugCamera", true, false) != null and debug_arena.find_child("DebugVisibleFloor", true, false) != null:
			return true
		await tree.physics_frame
	return false


func _wait_process_frames(count: int) -> void:
	for _i in range(count):
		await tree.process_frame


func _set_player_heading(player: Node3D, heading_y: float) -> void:
	var heading_basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (heading_basis * Vector3.FORWARD).normalized()
	player.rotation.y = heading_y
	if _object_has_property(player, "_last_strong_direction"):
		player.set("_last_strong_direction", forward)
	var camera_controller := player.get_node_or_null("CameraController")
	if camera_controller != null:
		camera_controller.set("_euler_rotation", Vector3.ZERO)
		(camera_controller as Node3D).transform.basis = Basis.IDENTITY


func _object_has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


func _heading_label(heading_degrees: float) -> String:
	var rounded := int(round(heading_degrees))
	if rounded < 0:
		return "heading_neg_%03d" % abs(rounded)
	return "heading_pos_%03d" % rounded


func _heading_failure(heading_degrees: float, reason: String) -> Dictionary:
	return {
		"heading_degrees": heading_degrees,
		"heading_radians": deg_to_rad(heading_degrees),
		"used_for_score": false,
		"captures": [],
		"gameplay_preview_mask": _unavailable_diff_metrics(GAMEPLAY_ANALYSIS_REGION, "gameplay_preview", reason),
		"side_preview_mask": _unavailable_diff_metrics(SIDE_ANALYSIS_REGION, "side_preview", reason),
		"runtime_projectile": {"available": false, "reason": reason},
		"side_early_flight_mask": _unavailable_diff_metrics(SIDE_ANALYSIS_REGION, "side_early_flight", reason),
		"provisional_verdict": "missing",
		"reason": reason,
	}


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"
```

- [ ] **Step 7: Run the trajectory shadow tests**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS for source-level and pixel helper tests.

- [ ] **Step 8: Commit the capture loop**

```powershell
git add tests\test_trajectory_shadow_probe.py verifier_godot\__verifier__\trajectory_shadow_probe.gd
git commit -m "feat: capture trajectory shadow baselines per heading"
```

## Task 5: Add Early-Flight Runtime Tracking And Provisional Verdicts

**Files:**
- Modify: `tests/test_trajectory_shadow_probe.py`
- Modify: `verifier_godot/__verifier__/trajectory_shadow_probe.gd`

- [ ] **Step 1: Add a full reference-project smoke test**

Add this method inside `TrajectoryShadowProbeTests`:

```python
    def test_trajectory_shadow_mode_writes_hybrid_metrics_for_reference_when_available(self):
        godot = find_godot()
        if godot is None:
            self.skipTest("Godot console executable is not available")
        reference_project = Path(r"C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\reference-main-complete")
        if not (reference_project / "project.godot").exists():
            self.skipTest(f"reference project unavailable: {reference_project}")

        out_dir = Path(tempfile.mkdtemp(prefix="trajectory-shadow-reference-"))
        try:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "run_screenshot_probe.py"),
                    "--project",
                    str(reference_project),
                    "--godot",
                    str(godot),
                    "--out-dir",
                    str(out_dir),
                    "--mode",
                    "trajectory-shadow",
                    "--timeout",
                    "180",
                ],
                text=True,
                capture_output=True,
                check=False,
                timeout=240,
            )
            output = completed.stdout + completed.stderr
            if not (out_dir / "result.json").exists():
                self.skipTest(f"trajectory shadow probe unavailable in this renderer: {output}")
            self.assertEqual(completed.returncode, 0, output)
            result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
            self.assertFalse(result.get("used_for_score", True), result)
            shadow = result.get("modes", {}).get("trajectory_shadow", {})
            self.assertTrue(shadow.get("ok"), result)
            self.assertFalse(shadow.get("used_for_score", True), shadow)
            self.assertEqual(len(shadow.get("heading_results", [])), 3, shadow)
            self.assertIn(shadow.get("provisional_verdict"), ["healthy", "suspect", "missing"], shadow)
            summary = shadow.get("summary", {})
            self.assertFalse(summary.get("used_for_score", True), summary)
            self.assertIn("preview_matches_projectile_direction", summary.get("visual_claims", {}), summary)
            self.assertIn("updates_with_aim_camera_direction", summary.get("visual_claims", {}), summary)
            self.assertIn("communicates_arcing_throw", summary.get("visual_claims", {}), summary)
            first_heading = shadow.get("heading_results", [{}])[0]
            self.assertIn("runtime_projectile", first_heading, first_heading)
            self.assertIn("side_early_flight_mask", first_heading, first_heading)
            self.assertTrue((out_dir / "trajectory_shadow").exists(), result)
        finally:
            shutil.rmtree(out_dir, ignore_errors=True)
```

- [ ] **Step 2: Run the smoke test and verify the expected failure**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe.TrajectoryShadowProbeTests.test_trajectory_shadow_mode_writes_hybrid_metrics_for_reference_when_available -v
```

Expected: FAIL or SKIP. A SKIP is acceptable only when Godot or the local reference project is unavailable. If it runs, it should fail because runtime and early-flight fields are still empty.

- [ ] **Step 3: Add runtime tracking constants**

Add these constants below the side-camera constants:

```gdscript
const PROJECTILE_SPAWN_RADIUS := 6.0
const EARLY_FLIGHT_CAPTURE_FRAMES := 8
const RUNTIME_TRACK_FRAMES := 42
const MIN_RUNTIME_TRAVEL_DISTANCE := 0.5
const GAMEPLAY_CENTROID_SPREAD_HEALTHY_PX := 80.0
```

- [ ] **Step 4: Replace the tail of `_run_heading_sample` with early-flight capture and runtime metrics**

In `_run_heading_sample`, replace the block from `var captures := [` through `return result` with:

```gdscript
	var captures := [
		gameplay_baseline.get("record", {}),
		side_baseline.get("record", {}),
		gameplay_preview.get("record", {}),
		side_preview.get("record", {}),
	]

	var before_attack_ids := SceneProbe.collect_instance_ids(debug_arena)
	await input.tap("attack", 2, 2)
	await input.wait_physics_frames(2)
	var projectile_candidates := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(debug_arena, before_attack_ids), player.global_position, PROJECTILE_SPAWN_RADIUS)
	await input.wait_physics_frames(EARLY_FLIGHT_CAPTURE_FRAMES)
	side_camera.current = true
	var side_early_flight := await _capture_image("%s_side_early_flight" % heading_label, root)
	captures.append(side_early_flight.get("record", {}))
	var side_early_flight_mask := _baseline_diff_metrics(side_baseline.get("image", null), side_early_flight.get("image", null), SIDE_ANALYSIS_REGION, "side_early_flight")
	var tracks: Dictionary = await SceneProbe.track_nodes_positions(tree, projectile_candidates, RUNTIME_TRACK_FRAMES)
	var runtime_projectile := _runtime_projectile_metrics(projectile_candidates, tracks, player, heading_y)
	var result := {
		"heading_degrees": heading_degrees,
		"heading_radians": heading_y,
		"used_for_score": false,
		"captures": captures,
		"gameplay_preview_mask": gameplay_mask,
		"side_preview_mask": side_mask,
		"runtime_projectile": runtime_projectile,
		"side_early_flight_mask": side_early_flight_mask,
		"provisional_verdict": _heading_verdict(gameplay_mask, side_mask, side_early_flight_mask, runtime_projectile),
	}
	debug_arena.queue_free()
	await tree.process_frame
	return result
```

- [ ] **Step 5: Add runtime and verdict helpers**

Add these methods below `_heading_failure`:

```gdscript
func _runtime_projectile_metrics(candidates: Array[Node3D], tracks: Dictionary, player: Node3D, heading_y: float) -> Dictionary:
	var best_points: Array = []
	var best_distance := -1.0
	var best_name := ""
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var points: Array = tracks.get(candidate.get_instance_id(), [])
		var distance := SceneProbe.horizontal_travel_distance(points)
		if distance > best_distance:
			best_distance = distance
			best_points = points
			best_name = String(candidate.name)
	var direction := SceneProbe.track_horizontal_direction(best_points, MIN_RUNTIME_TRAVEL_DISTANCE)
	var heading_basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward_3d := (heading_basis * Vector3.FORWARD).normalized()
	var expected_direction := Vector2(forward_3d.x, forward_3d.z).normalized()
	var direction_dot := -1.0
	if direction.length() > 0.001 and expected_direction.length() > 0.001:
		direction_dot = direction.normalized().dot(expected_direction)
	return {
		"available": not best_points.is_empty(),
		"candidate_count": candidates.size(),
		"best_candidate": best_name,
		"tracked_point_count": best_points.size(),
		"horizontal_travel_distance": best_distance,
		"direction": [direction.x, direction.y],
		"expected_direction": [expected_direction.x, expected_direction.y],
		"direction_dot": direction_dot,
		"direction_matches_heading": direction_dot >= RUNTIME_DIRECTION_MIN_DOT,
		"has_arc_motion": SceneProbe.has_arc_motion(best_points),
		"used_for_score": false,
	}


func _heading_verdict(gameplay_mask: Dictionary, side_mask: Dictionary, side_early_flight_mask: Dictionary, runtime_projectile: Dictionary) -> String:
	var gameplay_visible := int(gameplay_mask.get("changed_pixel_count", 0)) >= MIN_GAMEPLAY_CHANGED_PIXELS
	var side_visible := int(side_mask.get("changed_pixel_count", 0)) >= MIN_SIDE_CHANGED_PIXELS
	var side_arc_like := bool(side_mask.get("suggests_arc", false))
	var early_arc_like := bool(side_early_flight_mask.get("suggests_arc", false)) or bool(runtime_projectile.get("has_arc_motion", false))
	var runtime_direction_ok := bool(runtime_projectile.get("direction_matches_heading", false))
	if gameplay_visible and side_visible and side_arc_like and runtime_direction_ok:
		return "healthy"
	if gameplay_visible or side_visible or early_arc_like or bool(runtime_projectile.get("available", false)):
		return "suspect"
	return "missing"


func _overall_verdict(summary: Dictionary) -> String:
	var healthy_count := int(summary.get("healthy_heading_count", 0))
	var suspect_count := int(summary.get("suspect_heading_count", 0))
	if healthy_count >= 2:
		return "healthy"
	if healthy_count + suspect_count > 0:
		return "suspect"
	return "missing"
```

- [ ] **Step 6: Replace `_trajectory_shadow_summary` with the real rollup**

Replace `_trajectory_shadow_summary` with:

```gdscript
func _trajectory_shadow_summary(heading_results: Array[Dictionary]) -> Dictionary:
	var healthy_count := 0
	var suspect_count := 0
	var missing_count := 0
	var gameplay_visible_count := 0
	var side_arc_count := 0
	var runtime_direction_count := 0
	var gameplay_centroids: Array[float] = []
	for heading_result in heading_results:
		var verdict := String(heading_result.get("provisional_verdict", "missing"))
		if verdict == "healthy":
			healthy_count += 1
		elif verdict == "suspect":
			suspect_count += 1
		else:
			missing_count += 1
		var gameplay_mask: Dictionary = heading_result.get("gameplay_preview_mask", {})
		if int(gameplay_mask.get("changed_pixel_count", 0)) >= MIN_GAMEPLAY_CHANGED_PIXELS:
			gameplay_visible_count += 1
			var centroid: Array = gameplay_mask.get("centroid", [])
			if centroid.size() >= 2:
				gameplay_centroids.append(float(centroid[0]))
		var side_mask: Dictionary = heading_result.get("side_preview_mask", {})
		if bool(side_mask.get("suggests_arc", false)):
			side_arc_count += 1
		var runtime_projectile: Dictionary = heading_result.get("runtime_projectile", {})
		if bool(runtime_projectile.get("direction_matches_heading", false)):
			runtime_direction_count += 1
	var centroid_spread := _centroid_spread(gameplay_centroids)
	return {
		"used_for_score": false,
		"healthy_heading_count": healthy_count,
		"suspect_heading_count": suspect_count,
		"missing_heading_count": missing_count,
		"gameplay_preview_visible_count": gameplay_visible_count,
		"side_preview_arc_like_count": side_arc_count,
		"runtime_direction_match_count": runtime_direction_count,
		"gameplay_centroid_spread_px": centroid_spread,
		"visual_claims": {
			"preview_matches_projectile_direction": _claim_verdict(runtime_direction_count, heading_results.size()),
			"updates_with_aim_camera_direction": "healthy" if centroid_spread >= GAMEPLAY_CENTROID_SPREAD_HEALTHY_PX else _claim_verdict(gameplay_visible_count, heading_results.size()),
			"communicates_arcing_throw": _claim_verdict(side_arc_count, heading_results.size()),
		},
		"heading_count": heading_results.size(),
	}
```

- [ ] **Step 7: Add summary helpers and include new thresholds**

Add these methods below `_trajectory_shadow_summary`:

```gdscript
func _centroid_spread(values: Array[float]) -> float:
	if values.size() < 2:
		return 0.0
	var min_value := INF
	var max_value := -INF
	for value in values:
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	return max_value - min_value


func _claim_verdict(healthy_count: int, total_count: int) -> String:
	if total_count <= 0:
		return "missing"
	if healthy_count >= 2:
		return "healthy"
	if healthy_count >= 1:
		return "suspect"
	return "missing"
```

Add these entries to `_thresholds()`:

```gdscript
		"projectile_spawn_radius": PROJECTILE_SPAWN_RADIUS,
		"early_flight_capture_frames": EARLY_FLIGHT_CAPTURE_FRAMES,
		"runtime_track_frames": RUNTIME_TRACK_FRAMES,
		"min_runtime_travel_distance": MIN_RUNTIME_TRAVEL_DISTANCE,
		"gameplay_centroid_spread_healthy_px": GAMEPLAY_CENTROID_SPREAD_HEALTHY_PX,
```

- [ ] **Step 8: Run the full trajectory shadow test file**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS. The reference smoke test may SKIP only when Godot or the local reference project is unavailable.

- [ ] **Step 9: Commit the hybrid metrics**

```powershell
git add tests\test_trajectory_shadow_probe.py verifier_godot\__verifier__\trajectory_shadow_probe.gd
git commit -m "feat: add trajectory shadow hybrid metrics"
```

## Task 6: Document The Mode And Add Calibration Runner

**Files:**
- Modify: `README.md`
- Create: `run_trajectory_shadow_calibration.ps1`

- [ ] **Step 1: Update README mode table**

In `README.md`, under `## Experimental Screenshot Probe`, replace the modes table with:

```markdown
| Mode | Evidence |
| --- | --- |
| `debug-arena` | Controlled verifier arena screenshots every 10 physics frames after grenade throw until explosion or timeout. |
| `main-scene` | Real `res://main.tscn` ready, aim, grenade-ready, and post-throw screenshots when the playable scene exposes a player and camera. |
| `both` | Runs `debug-arena` and `main-scene`, writing separate `debug_arena/` and `main_scene/` artifact folders. It intentionally does not run `trajectory-shadow`. |
| `trajectory-shadow` | Opt-in shadow evidence for grenade trajectory preview. It captures per-heading gameplay-view and side-oblique baselines/previews, extracts baseline-difference pixel masks, combines them with runtime projectile tracking, and writes `modes.trajectory_shadow` with `used_for_score: false`. |
```

- [ ] **Step 2: Add a trajectory shadow note after the screenshot score paragraph**

Add this paragraph after the paragraph ending with `probe infrastructure state rather than as a candidate scoring failure.`:

```markdown
`trajectory-shadow` is a shadow-analysis mode for calibrating screenshot-based
trajectory evidence. It is deliberately excluded from `both` and from the
formal score. The visual mask is derived only from per-heading clean-baseline
pixel differences in verifier-defined analysis regions; runtime projectile
tracking is reported separately as hybrid context. Use this mode to compare
reference, ablated, near-miss, and agent-run behavior before deciding whether
any screenshot-derived signal is stable enough for formal grading.
```

- [ ] **Step 3: Create the calibration runner**

Create `run_trajectory_shadow_calibration.ps1` with this content:

```powershell
param(
    [string]$Godot = "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe",
    [string]$OutRoot = "$PSScriptRoot\artifacts\trajectory-shadow-calibration"
)

$ErrorActionPreference = "Stop"
$Verifier = $PSScriptRoot

if (-not (Test-Path $Godot)) {
    throw "Godot 4.6 console executable not found at $Godot"
}

$Cases = @(
    @{ Name = "reference"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\reference-main-complete" },
    @{ Name = "ablated"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\rollout-task\workspace" },
    @{ Name = "fixed-trajectory"; Project = "$Verifier\artifacts\probe-candidates\fixed-trajectory" },
    @{ Name = "damage-no-preview"; Project = "$Verifier\artifacts\probe-candidates\damage-no-preview" },
    @{ Name = "sonnet-3"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\run-03-cc-sonnet\workspace" },
    @{ Name = "high-score-codex"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\run-03-codex\workspace" }
)

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

foreach ($Case in $Cases) {
    $project = [string]$Case.Project
    if (-not (Test-Path (Join-Path $project "project.godot"))) {
        throw "Project for $($Case.Name) does not contain project.godot: $project"
    }
    $outDir = Join-Path $OutRoot $Case.Name
    Write-Host "Running trajectory-shadow probe for $($Case.Name)"
    python (Join-Path $Verifier "run_screenshot_probe.py") `
        --project $project `
        --godot $Godot `
        --out-dir $outDir `
        --mode trajectory-shadow `
        --timeout 180
}

Write-Host ""
Write-Host "Trajectory shadow calibration summary"
Get-ChildItem $OutRoot -Directory | Sort-Object Name | ForEach-Object {
    $resultPath = Join-Path $_.FullName "result.json"
    if (-not (Test-Path $resultPath)) {
        Write-Host "$($_.Name): missing result.json"
        return
    }
    $result = Get-Content $resultPath -Raw | ConvertFrom-Json
    $shadow = $result.modes.trajectory_shadow
    $summary = $shadow.summary
    Write-Host ("{0}: verdict={1} healthy={2} suspect={3} missing={4} gameplay_visible={5} side_arc={6} runtime_match={7} centroid_spread={8}" -f `
        $_.Name, `
        $shadow.provisional_verdict, `
        $summary.healthy_heading_count, `
        $summary.suspect_heading_count, `
        $summary.missing_heading_count, `
        $summary.gameplay_preview_visible_count, `
        $summary.side_preview_arc_like_count, `
        $summary.runtime_direction_match_count, `
        $summary.gameplay_centroid_spread_px)
}
```

- [ ] **Step 4: Add a README pointer to the calibration script**

Under `## Calibration And Evidence`, add:

````markdown
Run trajectory shadow calibration after changing the shadow probe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_trajectory_shadow_calibration.ps1"
```

The calibration runner compares reference, ablated, fixed-trajectory,
damage-no-preview, Sonnet-3, and high-score Codex workspaces. Treat the output
as threshold calibration evidence, not as a formal score.
````

- [ ] **Step 5: Run docs/source tests**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS or SKIP only for environment-dependent Godot smoke portions.

- [ ] **Step 6: Commit docs and calibration runner**

```powershell
git add README.md run_trajectory_shadow_calibration.ps1
git commit -m "docs: document trajectory shadow calibration"
```

## Task 7: Final Verification And Calibration Pass

**Files:**
- No code edits unless a verification failure identifies a concrete bug.

- [ ] **Step 1: Run focused trajectory shadow tests**

Run:

```powershell
python -m unittest tests.test_trajectory_shadow_probe -v
```

Expected: PASS. Godot-backed tests may SKIP only if Godot 4.6 or the local reference project is unavailable.

- [ ] **Step 2: Run existing screenshot probe tests**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_cli_declares_visual_modes `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_runner_declares_debug_and_main_scene_modes `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_debug_arena_mode_writes_nested_artifacts_when_available `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_main_scene_mode_writes_ready_capture_when_available `
  -v
```

Expected: PASS or environment SKIP for windowed rendering. Existing assertions for `both` must still pass, proving the old mode contract is intact.

- [ ] **Step 3: Run a direct reference smoke probe**

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_screenshot_probe.py `
  --project C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\reference-main-complete `
  --godot C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe `
  --out-dir C:\recent_project\roboblast-grenade-verifier\artifacts\trajectory-shadow-reference-smoke `
  --mode trajectory-shadow `
  --timeout 180
```

Expected: exit code 0, `artifacts\trajectory-shadow-reference-smoke\result.json` exists, `requested_mode` is `trajectory-shadow`, and `modes.trajectory_shadow.used_for_score` is `false`.

- [ ] **Step 4: Run the six-case calibration script**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\recent_project\roboblast-grenade-verifier\run_trajectory_shadow_calibration.ps1
```

Expected: six summary lines for `reference`, `ablated`, `fixed-trajectory`, `damage-no-preview`, `sonnet-3`, and `high-score-codex`. `reference` should be healthier than `ablated` and `damage-no-preview`; if it is not, adjust only the provisional thresholds in `trajectory_shadow_probe.gd`, rerun this step, and commit the threshold change with the observed before/after summary in the commit message body.

- [ ] **Step 5: Confirm no formal grader path changed**

Run:

```powershell
git diff --name-only HEAD~6..HEAD
```

Expected: changed files are limited to `run_screenshot_probe.py`, `screenshot_probe_runner.gd`, `trajectory_shadow_probe.gd`, `tests/test_trajectory_shadow_probe.py`, `README.md`, and `run_trajectory_shadow_calibration.ps1`. `run_grader.py`, `runner.gd`, and `score_board.gd` must not appear.

- [ ] **Step 6: Record final status**

Run:

```powershell
git status --short
```

Expected: no uncommitted source changes. Calibration artifacts under `artifacts\trajectory-shadow-calibration\` may be untracked; leave them uncommitted unless the report task explicitly needs them.

## Self-Review Checklist

- Spec coverage: explicit mode, shadow-only status, two camera views, per-heading clean baselines, baseline-difference pixels only, hybrid runtime context, provisional verdicts, calibration set, and no formal score changes are each covered by a task.
- Completeness scan: every implementation step names exact files, commands, and code blocks needed for execution.
- Type consistency: `trajectory_shadow`, `trajectory-shadow`, `provisional_verdict`, `heading_results`, `gameplay_preview_mask`, `side_preview_mask`, `side_early_flight_mask`, and `runtime_projectile` are used consistently across tests, GDScript, README, and calibration output.
