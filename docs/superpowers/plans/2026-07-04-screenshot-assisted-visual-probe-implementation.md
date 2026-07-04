# Screenshot-Assisted Visual Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the experimental screenshot probe so it captures non-scoring visual evidence from both the verifier debug arena and the candidate project's real main scene.

**Architecture:** Keep `run_grader.py` as the formal headless grader. Move screenshot-run behavior behind a small Godot-side visual probe module, let `screenshot_probe_runner.gd` orchestrate requested modes, and let `run_screenshot_probe.py` pass the mode and copy nested artifacts. Record projectile footprint metrics as auxiliary evidence only.

**Tech Stack:** Python `argparse`/`subprocess`/`unittest`; Godot 4.6 GDScript; existing verifier helpers in `SceneProbe`, `InputDriver`, and `debug_arena.tscn`.

---

## File Structure

- Create `verifier_godot/__verifier__/screenshot_visual_probe.gd`: Godot-side module that owns debug arena visual runs, main scene visual runs, screenshot capture, mode result shape, and projectile footprint aggregation.
- Modify `verifier_godot/__verifier__/screenshot_probe_runner.gd`: keep it as the SceneTree entry point, parse `--probe-mode`, call `ScreenshotVisualProbe`, and write the top-level `result.json`.
- Modify `verifier_godot/__verifier__/scene_probe.gd`: add screen-rect and viewport-region helpers used by projectile footprint metrics.
- Modify `run_screenshot_probe.py`: add `--mode`, pass it to Godot after `--`, recursively copy artifacts, and print per-mode summaries.
- Modify `tests/test_run_grader.py`: add structural tests plus two Godot-backed windowed smoke tests.
- Modify `README.md`: document the auxiliary screenshot probe command and artifact layout.

## Task 1: Add Failing Tests For Modes And Artifact Shape

**Files:**
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Add a structural test for the Python CLI mode selector**

Add this test near the existing screenshot probe tests:

```python
def test_screenshot_probe_cli_declares_visual_modes(self):
    cli_source = (ROOT / "run_screenshot_probe.py").read_text(encoding="utf-8")

    self.assertIn('"--mode"', cli_source)
    self.assertIn('choices=["debug-arena", "main-scene", "both"]', cli_source)
    self.assertIn('default="both"', cli_source)
    self.assertIn('"--probe-mode"', cli_source)
    self.assertIn("copytree", cli_source)
```

- [ ] **Step 2: Add a structural test for the Godot visual mode runner**

Add this test below `test_screenshot_probe_captures_every_ten_frames_until_explosion`:

```python
def test_screenshot_probe_runner_declares_debug_and_main_scene_modes(self):
    runner_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_probe_runner.gd").read_text(encoding="utf-8")
    visual_source_path = ROOT / "verifier_godot" / "__verifier__" / "screenshot_visual_probe.gd"

    self.assertTrue(visual_source_path.exists())
    visual_source = visual_source_path.read_text(encoding="utf-8")

    self.assertIn("ScreenshotVisualProbe", runner_source)
    self.assertIn("OS.get_cmdline_user_args", runner_source)
    self.assertIn('"debug-arena"', runner_source)
    self.assertIn('"main-scene"', runner_source)
    self.assertIn('"both"', runner_source)
    self.assertIn('"used_for_score": false', runner_source)
    self.assertIn("run_debug_arena", visual_source)
    self.assertIn("run_main_scene", visual_source)
    self.assertIn("res://main.tscn", visual_source)
    self.assertIn('"debug_arena"', visual_source)
    self.assertIn('"main_scene"', visual_source)
```

- [ ] **Step 3: Add a structural test for projectile footprint metrics**

Add this test near the SceneProbe screenshot helper tests:

```python
def test_scene_probe_declares_projectile_footprint_helpers(self):
    probe_source = (ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd").read_text(encoding="utf-8")
    visual_source = (ROOT / "verifier_godot" / "__verifier__" / "screenshot_visual_probe.gd").read_text(encoding="utf-8")

    self.assertIn("projectile_screen_rect", probe_source)
    self.assertIn("viewport_region_signature", probe_source)
    self.assertIn("projectile_footprint", visual_source)
    self.assertIn("used_for_score", visual_source)
    self.assertIn("delta_in_rect", visual_source)
```

- [ ] **Step 4: Run the new structural tests and verify they fail**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_cli_declares_visual_modes `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_runner_declares_debug_and_main_scene_modes `
  tests.test_run_grader.RunGraderTests.test_scene_probe_declares_projectile_footprint_helpers `
  -v
```

Expected: FAIL because `screenshot_visual_probe.gd`, CLI `--mode`, and projectile footprint helpers do not exist yet.

## Task 2: Add SceneProbe Screen-Space And Region Helpers

**Files:**
- Modify: `verifier_godot/__verifier__/scene_probe.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add a Godot-backed helper test for screen rect and region delta**

Add this test after `test_scene_probe_detects_windowed_screenshot_pixel_delta_when_available`:

```python
def test_scene_probe_reports_projectile_screen_rect_and_region_delta_when_available(self):
    godot = find_godot()
    if godot is None:
        self.skipTest("Godot console executable is not available")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        verifier_dir = tmp_path / "__verifier__"
        verifier_dir.mkdir()
        shutil.copy(ROOT / "verifier_godot" / "__verifier__" / "scene_probe.gd", verifier_dir / "scene_probe.gd")
        (tmp_path / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (tmp_path / "test_runner.gd").write_text(textwrap.dedent(
            """
            extends SceneTree

            const SceneProbe = preload("res://__verifier__/scene_probe.gd")

            func _init() -> void:
                call_deferred("_run")

            func _run() -> void:
                root.size = Vector2i(640, 360)
                var world := Node3D.new()
                root.add_child(world)
                var camera := Camera3D.new()
                camera.current = true
                camera.position = Vector3(0, 1.5, 6)
                camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
                world.add_child(camera)
                var projectile := Node3D.new()
                projectile.name = "Projectile"
                world.add_child(projectile)
                var mesh := MeshInstance3D.new()
                mesh.mesh = SphereMesh.new()
                mesh.position = Vector3(0, 1.0, 0)
                projectile.add_child(mesh)
                for _i in range(8):
                    await process_frame
                var before := SceneProbe.viewport_region_signature(root, Rect2(250, 130, 140, 100), 8)
                var material := StandardMaterial3D.new()
                material.albedo_color = Color(1, 0, 0, 1)
                mesh.set_surface_override_material(0, material)
                for _i in range(8):
                    await process_frame
                var rect := SceneProbe.projectile_screen_rect(camera, projectile, root.size)
                var after := SceneProbe.viewport_region_signature(root, Rect2(rect.get("x", 0), rect.get("y", 0), rect.get("width", 1), rect.get("height", 1)), 4)
                var delta := SceneProbe.frame_signature_delta(before, after)
                var result := {"rect": rect, "after": after, "delta": delta}
                result["after"].erase("samples")
                var file := FileAccess.open("res://result.json", FileAccess.WRITE)
                file.store_string(JSON.stringify(result))
                quit(0)
            """
        ), encoding="utf-8")

        completed = subprocess.run(
            [str(godot), "--path", str(tmp_path), "--script", "res://test_runner.gd"],
            text=True,
            capture_output=True,
            check=False,
            timeout=20,
        )
        output = completed.stdout + completed.stderr
        if not (tmp_path / "result.json").exists():
            self.skipTest("Windowed projectile footprint probe could not produce a result in this environment")
        result = json.loads((tmp_path / "result.json").read_text(encoding="utf-8"))
        if not result["after"].get("available"):
            self.skipTest(f"Windowed viewport capture unavailable: {result}")
        self.assertEqual(completed.returncode, 0, output)
        self.assertTrue(result["rect"].get("visible"), result)
        self.assertGreater(result["rect"].get("area_px", 0), 0, result)
        self.assertGreater(result["delta"], -1.0, result)
```

- [ ] **Step 2: Run the helper test and verify it fails**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_scene_probe_reports_projectile_screen_rect_and_region_delta_when_available -v
```

Expected: FAIL with a Godot error that `projectile_screen_rect` or `viewport_region_signature` does not exist.

- [ ] **Step 3: Implement `projectile_screen_rect` in `scene_probe.gd`**

Add this function after `visible_mesh_instances_under`:

```gdscript
static func projectile_screen_rect(camera: Camera3D, projectile: Node3D, viewport_size: Vector2i) -> Dictionary:
	if camera == null:
		return {"available": false, "visible": false, "reason": "camera unavailable"}
	if projectile == null or not is_instance_valid(projectile):
		return {"available": false, "visible": false, "reason": "projectile unavailable"}
	var points: Array[Vector2] = []
	for mesh_instance in visible_mesh_instances_under(projectile):
		var aabb := mesh_instance.get_aabb()
		for x in [aabb.position.x, aabb.position.x + aabb.size.x]:
			for y in [aabb.position.y, aabb.position.y + aabb.size.y]:
				for z in [aabb.position.z, aabb.position.z + aabb.size.z]:
					var world_point := mesh_instance.global_transform * Vector3(x, y, z)
					if not camera.is_position_behind(world_point):
						points.append(camera.unproject_position(world_point))
	if points.is_empty():
		if camera.is_position_behind(projectile.global_position):
			return {"available": true, "visible": false, "reason": "projectile is behind camera"}
		var center := camera.unproject_position(projectile.global_position)
		points = [center - Vector2(6, 6), center + Vector2(6, 6)]
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	min_x = clampf(floorf(min_x) - 2.0, 0.0, float(viewport_size.x))
	min_y = clampf(floorf(min_y) - 2.0, 0.0, float(viewport_size.y))
	max_x = clampf(ceilf(max_x) + 2.0, 0.0, float(viewport_size.x))
	max_y = clampf(ceilf(max_y) + 2.0, 0.0, float(viewport_size.y))
	var width := maxf(0.0, max_x - min_x)
	var height := maxf(0.0, max_y - min_y)
	return {
		"available": true,
		"visible": width > 0.0 and height > 0.0,
		"x": int(min_x),
		"y": int(min_y),
		"width": int(width),
		"height": int(height),
		"area_px": int(width * height),
	}
```

- [ ] **Step 4: Implement `viewport_region_signature` in `scene_probe.gd`**

Add this function after `viewport_screenshot_signature`:

```gdscript
static func viewport_region_signature(viewport: Viewport, rect: Rect2, sample_step: int = 8) -> Dictionary:
	var capture := _capture_viewport_screenshot(viewport)
	if not bool(capture.get("available", false)):
		return capture
	var image: Image = capture["image"]
	var width := image.get_width()
	var height := image.get_height()
	var x0 := clampi(int(floorf(rect.position.x)), 0, maxi(width - 1, 0))
	var y0 := clampi(int(floorf(rect.position.y)), 0, maxi(height - 1, 0))
	var x1 := clampi(int(ceilf(rect.position.x + rect.size.x)), x0 + 1, width)
	var y1 := clampi(int(ceilf(rect.position.y + rect.size.y)), y0 + 1, height)
	var safe_sample_step := maxi(sample_step, 1)
	var samples: Array = []
	for y in range(y0, y1, safe_sample_step):
		for x in range(x0, x1, safe_sample_step):
			var color := image.get_pixel(x, y)
			samples.append([color.r, color.g, color.b, color.a])
	return {
		"available": true,
		"display_driver": DisplayServer.get_name(),
		"width": width,
		"height": height,
		"region": [x0, y0, x1 - x0, y1 - y0],
		"sample_step": safe_sample_step,
		"sample_count": samples.size(),
		"samples": samples,
	}
```

- [ ] **Step 5: Run the helper tests and verify they pass**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_scene_probe_declares_projectile_footprint_helpers `
  tests.test_run_grader.RunGraderTests.test_scene_probe_reports_projectile_screen_rect_and_region_delta_when_available `
  -v
```

Expected: PASS, or the Godot-backed test SKIP when the local display cannot provide windowed viewport pixels.

## Task 3: Create The Godot Visual Probe Module

**Files:**
- Create: `verifier_godot/__verifier__/screenshot_visual_probe.gd`
- Modify: `verifier_godot/__verifier__/screenshot_probe_runner.gd`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add `screenshot_visual_probe.gd` with explicit mode entry points**

Create the file with this structure:

```gdscript
extends RefCounted

const DebugArenaScene = preload("res://__verifier__/debug_arena.tscn")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const SCREENSHOT_INTERVAL_FRAMES := 10
const MAX_POST_THROW_FRAMES := 240
const RENDER_SETTLE_FRAMES := 2
const SAMPLE_STEP := 32
const REGION_SAMPLE_STEP := 4
const EXPLOSION_TOKENS := ["explosion", "smoke", "blast", "spark"]

var tree: SceneTree
var input
var root: Window

func _init(p_tree: SceneTree, p_input) -> void:
	tree = p_tree
	input = p_input
	root = tree.root

func run_debug_arena() -> Dictionary:
	_prepare_output_dir("%s/debug_arena" % OUTPUT_DIR)
	root.size = Vector2i(1280, 720)
	var debug_arena := DebugArenaScene.instantiate()
	root.add_child(debug_arena)
	if not await _wait_for_debug_arena_ready():
		debug_arena.queue_free()
		return _mode_failure("debug_arena", "debug arena did not become ready")
	var result := await _run_throw_capture_window("debug_arena", root, debug_arena, root.find_child("DebugCamera", true, false))
	debug_arena.queue_free()
	await tree.process_frame
	return result

func run_main_scene() -> Dictionary:
	_prepare_output_dir("%s/main_scene" % OUTPUT_DIR)
	root.size = Vector2i(1280, 720)
	var main_scene_resource := load("res://main.tscn")
	if main_scene_resource == null or not main_scene_resource is PackedScene:
		return _mode_failure("main_scene", "res://main.tscn could not be loaded")
	var main_scene: Node = (main_scene_resource as PackedScene).instantiate()
	main_scene.name = "ScreenshotProbeMainScene"
	root.add_child(main_scene)
	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	var player := await _wait_for_main_scene_player(main_scene)
	if player == null:
		main_scene.queue_free()
		return _mode_failure("main_scene", "main scene loaded but no playable player was found")
	var camera := await _wait_for_current_camera(main_scene)
	if camera == null:
		await _capture_named("main_scene", "main_ready", root, {})
		main_scene.queue_free()
		return _mode_failure("main_scene", "main scene loaded but no current camera was found")
	await _capture_named("main_scene", "main_ready", root, {})
	await input.hold("aim", 4)
	await _capture_named("main_scene", "main_aim", root, {})
	await input.release("aim", 2)
	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(4)
	await _capture_named("main_scene", "grenade_ready", root, {})
	var result := await _run_throw_capture_window("main_scene", root, main_scene, camera)
	main_scene.queue_free()
	await tree.process_frame
	return result
```

- [ ] **Step 2: Add shared capture helpers to `screenshot_visual_probe.gd`**

Append these helper functions to the same file:

```gdscript
func _run_throw_capture_window(mode_name: String, capture_viewport: Viewport, observed_root: Node, camera: Camera3D) -> Dictionary:
	var captures: Array[Dictionary] = []
	var before_attack_ids := SceneProbe.collect_instance_ids(observed_root)
	var baseline_signature := SceneProbe.viewport_screenshot_signature(capture_viewport, SAMPLE_STEP)
	var previous_signature := baseline_signature
	await input.tap("attack", 2, 2)
	await input.wait_physics_frames(2)
	var projectile_candidates := _projectile_candidates(observed_root, before_attack_ids)
	var elapsed_frames := 0
	var stop_reason := "max_frames"
	var explosion_frame := -1
	while elapsed_frames < MAX_POST_THROW_FRAMES:
		await input.wait_physics_frames(SCREENSHOT_INTERVAL_FRAMES)
		elapsed_frames += SCREENSHOT_INTERVAL_FRAMES
		var explosion_nodes := _explosion_nodes_since(observed_root, before_attack_ids)
		var explosion_observed := not explosion_nodes.is_empty()
		var capture := await _capture_attack_frame(mode_name, elapsed_frames, capture_viewport, baseline_signature, previous_signature, camera, projectile_candidates, explosion_observed, explosion_nodes)
		previous_signature = capture.get("_signature", previous_signature)
		capture.erase("_signature")
		captures.append(capture)
		if explosion_observed:
			stop_reason = "explosion_observed"
			explosion_frame = elapsed_frames
			break
	return {
		"ok": true,
		"artifact_dir": mode_name,
		"used_for_score": false,
		"screenshot_interval_frames": SCREENSHOT_INTERVAL_FRAMES,
		"stop_reason": stop_reason,
		"explosion_frame": explosion_frame,
		"captures": captures,
		"projectile_footprint": _projectile_footprint_summary(captures),
	}

func _capture_attack_frame(
	mode_name: String,
	elapsed_frames: int,
	viewport: Viewport,
	baseline_signature: Dictionary,
	previous_signature: Dictionary,
	camera: Camera3D,
	projectile_candidates: Array[Node3D],
	explosion_observed: bool,
	explosion_nodes: Array[String]
) -> Dictionary:
	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	var label := "attack_%03d" % elapsed_frames
	var path := "%s/%s/%s.png" % [OUTPUT_DIR, mode_name, label]
	var signature := SceneProbe.viewport_screenshot_signature(viewport, SAMPLE_STEP)
	var saved := SceneProbe.save_viewport_screenshot(viewport, path)
	var summarized_signature := signature.duplicate()
	summarized_signature.erase("samples")
	return {
		"label": label,
		"elapsed_frames": elapsed_frames,
		"path": path,
		"signature": summarized_signature,
		"_signature": signature,
		"saved": saved,
		"delta_from_previous": SceneProbe.frame_signature_delta(previous_signature, signature),
		"delta_from_baseline": SceneProbe.frame_signature_delta(baseline_signature, signature),
		"explosion_observed": explosion_observed,
		"explosion_nodes": explosion_nodes,
		"projectile_visual": _projectile_visual_metric(viewport, baseline_signature, camera, projectile_candidates),
	}

func _capture_named(mode_name: String, label: String, viewport: Viewport, extra: Dictionary) -> Dictionary:
	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	var path := "%s/%s/%s.png" % [OUTPUT_DIR, mode_name, label]
	var signature := SceneProbe.viewport_screenshot_signature(viewport, SAMPLE_STEP)
	var saved := SceneProbe.save_viewport_screenshot(viewport, path)
	var summarized_signature := signature.duplicate()
	summarized_signature.erase("samples")
	var capture := {
		"label": label,
		"path": path,
		"signature": summarized_signature,
		"saved": saved,
	}
	for key in extra.keys():
		capture[key] = extra[key]
	return capture
```

- [ ] **Step 3: Add projectile metric helpers to `screenshot_visual_probe.gd`**

Append these helper functions:

```gdscript
func _projectile_candidates(root_node: Node, before_attack_ids: Dictionary) -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for node in SceneProbe.new_nodes_since(root_node, before_attack_ids):
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.visible:
				candidates.append(node_3d)
	return candidates

func _projectile_visual_metric(viewport: Viewport, baseline_signature: Dictionary, camera: Camera3D, candidates: Array[Node3D]) -> Dictionary:
	if camera == null:
		return {"available": false, "visible": false, "reason": "camera unavailable"}
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var rect := SceneProbe.projectile_screen_rect(camera, candidate, root.size)
		if not bool(rect.get("visible", false)):
			continue
		var region := Rect2(float(rect.get("x", 0)), float(rect.get("y", 0)), float(rect.get("width", 1)), float(rect.get("height", 1)))
		var signature := SceneProbe.viewport_region_signature(viewport, region, REGION_SAMPLE_STEP)
		var delta := SceneProbe.frame_signature_delta(baseline_signature, signature)
		return {
			"available": bool(signature.get("available", false)),
			"visible": true,
			"screen_rect": [rect.get("x", 0), rect.get("y", 0), rect.get("width", 0), rect.get("height", 0)],
			"area_px": rect.get("area_px", 0),
			"delta_in_rect": delta,
		}
	return {"available": true, "visible": false, "reason": "no projectile candidate projected into screen space"}

func _projectile_footprint_summary(captures: Array[Dictionary]) -> Dictionary:
	var visible_count := 0
	var best_frame := ""
	var max_area := 0
	var max_delta := -1.0
	for capture in captures:
		var visual: Dictionary = capture.get("projectile_visual", {})
		if bool(visual.get("visible", false)):
			visible_count += 1
		var area := int(visual.get("area_px", 0))
		var delta := float(visual.get("delta_in_rect", -1.0))
		if area > max_area or delta > max_delta:
			best_frame = String(capture.get("label", ""))
			max_area = maxi(max_area, area)
			max_delta = maxf(max_delta, delta)
	return {
		"used_for_score": false,
		"best_frame": best_frame,
		"visible_frame_count": visible_count,
		"max_area_px": max_area,
		"max_delta_in_rect": max_delta,
	}
```

- [ ] **Step 4: Add waiting, explosion, and output helpers to `screenshot_visual_probe.gd`**

Append these helper functions:

```gdscript
func _wait_process_frames(count: int) -> void:
	for _i in range(count):
		await tree.process_frame

func _wait_for_debug_arena_ready() -> bool:
	for _i in range(540):
		if root.find_child("DebugCamera", true, false) != null and root.find_child("DebugVisibleFloor", true, false) != null:
			return true
		await tree.physics_frame
	return false

func _wait_for_main_scene_player(main_scene: Node) -> Node:
	for _i in range(360):
		var player := _find_main_scene_player(main_scene)
		if player != null:
			return player
		await tree.physics_frame
	return null

func _wait_for_current_camera(main_scene: Node) -> Camera3D:
	for _i in range(180):
		for node in SceneProbe.flatten(main_scene):
			if node is Camera3D and (node as Camera3D).current:
				return node as Camera3D
		var viewport_camera := root.get_camera_3d()
		if viewport_camera != null:
			return viewport_camera
		await tree.process_frame
	return null

func _find_main_scene_player(main_scene: Node) -> Node:
	for node in SceneProbe.flatten(main_scene):
		if node.name == "Player" or (node is CharacterBody3D and node.has_method("collect_coin")):
			return node
	return null

func _explosion_nodes_since(root_node: Node, before: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for node in SceneProbe.new_nodes_since(root_node, before):
		var text := _node_context_text(node)
		for token in EXPLOSION_TOKENS:
			if text.find(token) >= 0:
				result.append(str(node.get_path()))
				break
	return result

func _node_context_text(node: Node) -> String:
	var parts: Array[String] = [String(node.name)]
	var current := node.get_parent()
	while current != null:
		parts.append(String(current.name))
		current = current.get_parent()
	return " ".join(parts).to_lower()

func _mode_failure(mode_name: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"artifact_dir": mode_name,
		"used_for_score": false,
		"reason": reason,
		"screenshot_interval_frames": SCREENSHOT_INTERVAL_FRAMES,
		"stop_reason": "failed",
		"explosion_frame": -1,
		"captures": [],
	}

func _prepare_output_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"
```

- [ ] **Step 5: Replace `screenshot_probe_runner.gd` orchestration**

Replace the file body with this entry-point shape:

```gdscript
extends SceneTree

const InputDriver = preload("res://__verifier__/input_driver.gd")
const ScreenshotVisualProbe = preload("res://__verifier__/screenshot_visual_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const VALID_MODES := ["debug-arena", "main-scene", "both"]

var input

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	input = InputDriver.new(self)
	var requested_mode := _requested_mode()
	var probe := ScreenshotVisualProbe.new(self, input)
	var mode_results := {}
	if requested_mode == "debug-arena" or requested_mode == "both":
		mode_results["debug_arena"] = await probe.run_debug_arena()
	if requested_mode == "main-scene" or requested_mode == "both":
		mode_results["main_scene"] = await probe.run_main_scene()
	var result := {
		"ok": true,
		"display_driver": DisplayServer.get_name(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"used_for_score": false,
		"requested_mode": requested_mode,
		"modes": mode_results,
	}
	_write_result(result)
	quit(0)

func _requested_mode() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--probe-mode" and index + 1 < args.size():
			var value := String(args[index + 1])
			if VALID_MODES.has(value):
				return value
	return "both"

func _write_result(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var file := FileAccess.open("%s/result.json" % OUTPUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
```

- [ ] **Step 6: Run structural tests and verify they pass**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_runner_declares_debug_and_main_scene_modes `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_captures_every_ten_frames_until_explosion `
  -v
```

Expected: PASS.

## Task 4: Add Python CLI Mode Selection And Recursive Artifact Copying

**Files:**
- Modify: `run_screenshot_probe.py`
- Test: `tests/test_run_grader.py`

- [ ] **Step 1: Add `--mode` to `build_parser`**

Add this parser argument after `--out-dir`:

```python
parser.add_argument(
    "--mode",
    choices=["debug-arena", "main-scene", "both"],
    default="both",
    help="Screenshot probe mode to run. Defaults to both debug arena and main scene evidence.",
)
```

- [ ] **Step 2: Replace flat artifact copying with recursive copying**

Replace `_copy_probe_artifacts` with:

```python
def _copy_probe_artifacts(project_copy: Path, output_dir: Path) -> dict:
    source = project_copy / PROBE_OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        return {}
    for artifact in source.iterdir():
        target = output_dir / artifact.name
        if artifact.is_dir():
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(artifact, target)
        elif artifact.is_file():
            shutil.copy2(artifact, target)
    result_path = output_dir / "result.json"
    if result_path.exists():
        return json.loads(result_path.read_text(encoding="utf-8"))
    return {}
```

- [ ] **Step 3: Pass the requested mode to Godot**

Replace the script command construction with:

```python
script_command = [
    str(args.godot),
    "--path",
    str(temp_project),
    "--script",
    PROBE_SCRIPT,
    "--",
    "--probe-mode",
    args.mode,
]
```

- [ ] **Step 4: Print per-mode summaries**

Replace the current stop reason and screenshot count prints with:

```python
print(f"Wrote screenshot probe artifacts: {args.out_dir}")
print(f"Requested mode: {result.get('requested_mode', args.mode)}")
for mode_name, mode_result in result.get("modes", {}).items():
    print(
        f"{mode_name}: ok={mode_result.get('ok', False)} "
        f"stop={mode_result.get('stop_reason', 'unknown')} "
        f"frame={mode_result.get('explosion_frame', -1)} "
        f"screenshots={len(mode_result.get('captures', []))}"
    )
```

- [ ] **Step 5: Run the CLI structural test and verify it passes**

Run:

```powershell
python -m unittest tests.test_run_grader.RunGraderTests.test_screenshot_probe_cli_declares_visual_modes -v
```

Expected: PASS.

## Task 5: Add Godot-Backed Windowed Smoke Tests

**Files:**
- Modify: `tests/test_run_grader.py`

- [ ] **Step 1: Add a debug arena mode smoke test**

Add this test near the existing windowed screenshot test:

```python
def test_screenshot_probe_debug_arena_mode_writes_nested_artifacts_when_available(self):
    godot = find_godot()
    if godot is None:
        self.skipTest("Godot console executable is not available")

    candidate = ROOT / "tmp" / "screenshot-probe-debug-arena-candidate"
    if candidate.exists():
        shutil.rmtree(candidate)
    candidate.mkdir(parents=True)
    (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    out_dir = Path(tempfile.mkdtemp(prefix="screenshot-probe-debug-arena-out-"))
    try:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "run_screenshot_probe.py"),
                "--project",
                str(candidate),
                "--godot",
                str(godot),
                "--out-dir",
                str(out_dir),
                "--mode",
                "debug-arena",
                "--timeout",
                "60",
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=90,
        )
        output = completed.stdout + completed.stderr
        if not (out_dir / "result.json").exists():
            self.skipTest(f"Windowed debug arena screenshot probe unavailable: {output}")
        result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
        self.assertFalse(result.get("used_for_score", True), result)
        self.assertIn("debug_arena", result.get("modes", {}), result)
        self.assertTrue((out_dir / "debug_arena").exists(), result)
    finally:
        shutil.rmtree(candidate, ignore_errors=True)
        shutil.rmtree(out_dir, ignore_errors=True)
```

- [ ] **Step 2: Add a minimal main scene mode smoke test**

Add this test after the debug arena smoke test:

```python
def test_screenshot_probe_main_scene_mode_writes_ready_capture_when_available(self):
    godot = find_godot()
    if godot is None:
        self.skipTest("Godot console executable is not available")

    with tempfile.TemporaryDirectory() as candidate_tmp, tempfile.TemporaryDirectory() as out_tmp:
        candidate = Path(candidate_tmp)
        out_dir = Path(out_tmp)
        (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (candidate / "player.gd").write_text(
            "extends CharacterBody3D\n\nfunc collect_coin():\n\tpass\n",
            encoding="utf-8",
        )
        (candidate / "main.tscn").write_text(textwrap.dedent(
            """
            [gd_scene load_steps=2 format=3]

            [ext_resource type="Script" path="res://player.gd" id="1"]

            [node name="Main" type="Node3D"]

            [node name="Player" type="CharacterBody3D" parent="."]
            script = ExtResource("1")

            [node name="Camera3D" type="Camera3D" parent="Player"]
            transform = Transform3D(1, 0, 0, 0, 0.965926, 0.258819, 0, -0.258819, 0.965926, 0, 2, 6)
            current = true
            """
        ).strip() + "\n", encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "run_screenshot_probe.py"),
                "--project",
                str(candidate),
                "--godot",
                str(godot),
                "--out-dir",
                str(out_dir),
                "--mode",
                "main-scene",
                "--timeout",
                "60",
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=90,
        )
        output = completed.stdout + completed.stderr
        if not (out_dir / "result.json").exists():
            self.skipTest(f"Windowed main scene screenshot probe unavailable: {output}")
        result = json.loads((out_dir / "result.json").read_text(encoding="utf-8"))
        self.assertFalse(result.get("used_for_score", True), result)
        self.assertIn("main_scene", result.get("modes", {}), result)
        self.assertTrue((out_dir / "main_scene").exists(), result)
        self.assertTrue((out_dir / "main_scene" / "main_ready.png").exists(), result)
```

- [ ] **Step 3: Run the new Godot-backed smoke tests**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_debug_arena_mode_writes_nested_artifacts_when_available `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_main_scene_mode_writes_ready_capture_when_available `
  -v
```

Expected: PASS, or SKIP when Godot or windowed viewport capture is unavailable.

## Task 6: Document The Auxiliary Screenshot Probe

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a README section after Debug Arena Export**

Add this section:

````markdown
## Experimental Screenshot Probe

The screenshot probe is an auxiliary visual-evidence runner. It is not part of
the formal 0-100 score and every result marks `used_for_score: false`.

```powershell
python "$Verifier\run_screenshot_probe.py" `
  --project "$Project" `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out-dir "$Verifier\artifacts\screenshot-probe" `
  --mode both
```

Modes:

| Mode | Evidence |
| --- | --- |
| `debug-arena` | Controlled verifier arena screenshots every 10 physics frames after grenade throw until explosion or timeout. |
| `main-scene` | Real `res://main.tscn` ready, aim, grenade-ready, and post-throw screenshots when the playable scene exposes a player and camera. |
| `both` | Runs both visual modes and writes separate `debug_arena/` and `main_scene/` artifact folders. |

The top-level `result.json` contains one `modes` entry per attempted visual run.
Windowed rendering can be unavailable on headless machines; that is reported as
probe infrastructure state rather than as a candidate scoring failure.
````

- [ ] **Step 2: Run repository consistency tests**

Run:

```powershell
python -m unittest tests.test_repository_consistency -v
```

Expected: PASS.

## Task 7: Verify Against The Previously Inspected Candidate

**Files:**
- No source edits in this task unless a verification failure identifies a concrete defect.

- [ ] **Step 1: Run the focused Python and Godot-backed tests**

Run:

```powershell
python -m unittest `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_cli_declares_visual_modes `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_runner_declares_debug_and_main_scene_modes `
  tests.test_run_grader.RunGraderTests.test_scene_probe_declares_projectile_footprint_helpers `
  tests.test_run_grader.RunGraderTests.test_scene_probe_reports_projectile_screen_rect_and_region_delta_when_available `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_debug_arena_mode_writes_nested_artifacts_when_available `
  tests.test_run_grader.RunGraderTests.test_screenshot_probe_main_scene_mode_writes_ready_capture_when_available `
  -v
```

Expected: PASS, with Godot-backed tests allowed to SKIP only when the local Godot executable or render-capable display is unavailable.

- [ ] **Step 2: Run the full verifier test module**

Run:

```powershell
python -m unittest tests.test_run_grader -v
```

Expected: PASS. Existing Godot-backed tests may SKIP when the Godot executable is unavailable.

- [ ] **Step 3: Run the screenshot probe against the candidate project**

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_screenshot_probe.py `
  --project C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\run-03-codex\workspace `
  --godot C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe `
  --out-dir C:\recent_project\roboblast-grenade-verifier\artifacts\screenshot-probe-run03-codex-both `
  --mode both `
  --timeout 180
```

Expected: `result.json` exists, top-level `used_for_score` is `false`, `modes.debug_arena` exists, and `modes.main_scene` exists. If the main scene mode reports `ok: false`, its `reason` is concrete and the debug arena artifacts remain present.

- [ ] **Step 4: Inspect generated artifact paths without staging them**

Run:

```powershell
Get-ChildItem C:\recent_project\roboblast-grenade-verifier\artifacts\screenshot-probe-run03-codex-both -Recurse | Select-Object FullName
git status --short
```

Expected: PNGs, logs, and `result.json` remain under ignored `artifacts/`; `git status --short` does not show generated runtime artifacts.

## Task 8: Commit Scoped Implementation Files

**Files:**
- Stage only implementation, tests, and README files from this plan.

- [ ] **Step 1: Review the final diff**

Run:

```powershell
git diff -- `
  run_screenshot_probe.py `
  verifier_godot\__verifier__\screenshot_probe_runner.gd `
  verifier_godot\__verifier__\screenshot_visual_probe.gd `
  verifier_godot\__verifier__\scene_probe.gd `
  tests\test_run_grader.py `
  README.md
```

Expected: Diff is limited to auxiliary screenshot probe behavior, projectile footprint evidence, tests, and documentation.

- [ ] **Step 2: Stage only scoped files**

Run:

```powershell
git add `
  run_screenshot_probe.py `
  verifier_godot\__verifier__\screenshot_probe_runner.gd `
  verifier_godot\__verifier__\screenshot_visual_probe.gd `
  verifier_godot\__verifier__\scene_probe.gd `
  tests\test_run_grader.py `
  README.md
```

Expected: `README.zh.md` and generated `artifacts/` files are not staged.

- [ ] **Step 3: Commit the implementation**

Run:

```powershell
git commit -m "feat: add screenshot-assisted visual probe modes"
```

Expected: Commit succeeds with only the scoped implementation files.
