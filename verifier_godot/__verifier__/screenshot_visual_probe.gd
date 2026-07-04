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
	var camera := root.find_child("DebugCamera", true, false) as Camera3D
	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(4)
	var result := await _run_throw_capture_window("debug_arena", root, debug_arena, camera)
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
	var setup_captures: Array[Dictionary] = []
	var camera := await _wait_for_current_camera(main_scene)
	setup_captures.append(await _capture_named("main_scene", "main_ready", root, {}))
	if camera == null:
		main_scene.queue_free()
		var failure := _mode_failure("main_scene", "main scene loaded but no current camera was found")
		failure["captures"] = setup_captures
		return failure
	await input.hold("aim", 4)
	setup_captures.append(await _capture_named("main_scene", "main_aim", root, {}))
	await input.release("aim", 2)
	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(4)
	setup_captures.append(await _capture_named("main_scene", "grenade_ready", root, {}))
	var result := await _run_throw_capture_window("main_scene", root, main_scene, camera, setup_captures)
	main_scene.queue_free()
	await tree.process_frame
	return result


func _run_throw_capture_window(
	mode_name: String,
	capture_viewport: Viewport,
	observed_root: Node,
	camera: Camera3D,
	initial_captures: Array[Dictionary] = []
) -> Dictionary:
	var captures: Array[Dictionary] = []
	captures.append_array(initial_captures)
	var before_attack_ids := SceneProbe.collect_instance_ids(observed_root)
	var baseline_signature := SceneProbe.viewport_screenshot_signature(capture_viewport, SAMPLE_STEP)
	var baseline_image := SceneProbe.viewport_image(capture_viewport)
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
		var capture := await _capture_attack_frame(
			mode_name,
			elapsed_frames,
			capture_viewport,
			baseline_signature,
			baseline_image,
			previous_signature,
			camera,
			projectile_candidates,
			explosion_observed,
			explosion_nodes
		)
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
	baseline_image: Dictionary,
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
	var projectile_visual := _projectile_visual_metric(viewport, baseline_image, camera, projectile_candidates)
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
		"projectile_visual": projectile_visual,
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


func _projectile_candidates(root_node: Node, before_attack_ids: Dictionary) -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for node in SceneProbe.new_nodes_since(root_node, before_attack_ids):
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.visible:
				candidates.append(node_3d)
	return candidates


func _projectile_visual_metric(viewport: Viewport, baseline_image: Dictionary, camera: Camera3D, candidates: Array[Node3D]) -> Dictionary:
	if camera == null:
		return {"available": false, "visible": false, "reason": "camera unavailable"}
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var rect := SceneProbe.projectile_screen_rect(camera, candidate, root.size)
		if not bool(rect.get("visible", false)):
			continue
		var region := Rect2(float(rect.get("x", 0)), float(rect.get("y", 0)), float(rect.get("width", 1)), float(rect.get("height", 1)))
		var baseline_region := baseline_image
		if bool(baseline_image.get("available", false)) and baseline_image.has("image"):
			baseline_region = SceneProbe.image_region_signature(baseline_image["image"], region, REGION_SAMPLE_STEP)
		var current_region := SceneProbe.viewport_region_signature(viewport, region, REGION_SAMPLE_STEP)
		return {
			"available": bool(current_region.get("available", false)),
			"visible": true,
			"screen_rect": [rect.get("x", 0), rect.get("y", 0), rect.get("width", 0), rect.get("height", 0)],
			"area_px": rect.get("area_px", 0),
			"delta_in_rect": SceneProbe.frame_signature_delta(baseline_region, current_region),
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
		"projectile_footprint": {
			"used_for_score": false,
			"best_frame": "",
			"visible_frame_count": 0,
			"max_area_px": 0,
			"max_delta_in_rect": -1.0,
		},
	}


func _prepare_output_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"
