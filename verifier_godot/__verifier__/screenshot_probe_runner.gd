extends SceneTree

const DebugArenaScene = preload("res://__verifier__/debug_arena.tscn")
const InputDriver = preload("res://__verifier__/input_driver.gd")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const SCREENSHOT_INTERVAL_FRAMES := 10
const MAX_POST_THROW_FRAMES := 240
const RENDER_SETTLE_FRAMES := 2
const SAMPLE_STEP := 32
const EXPLOSION_TOKENS := ["explosion", "smoke", "blast", "spark"]

var input
var captures: Array[Dictionary] = []
var baseline_signature: Dictionary = {}
var previous_signature: Dictionary = {}
var before_attack_ids: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	input = InputDriver.new(self)
	var debug_arena := DebugArenaScene.instantiate()
	root.add_child(debug_arena)
	if not await _wait_for_debug_arena_ready():
		_write_result({
			"ok": false,
			"reason": "debug arena did not become ready",
			"display_driver": DisplayServer.get_name(),
			"godot_version": Engine.get_version_info().get("string", ""),
			"captures": captures,
		})
		quit(2)
		return

	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(4)
	before_attack_ids = SceneProbe.collect_instance_ids(root)
	baseline_signature = SceneProbe.viewport_screenshot_signature(root, SAMPLE_STEP)
	previous_signature = baseline_signature
	await input.tap("attack", 2, 2)

	var elapsed_frames := 0
	var stop_reason := "max_frames"
	var explosion_frame := -1
	while elapsed_frames < MAX_POST_THROW_FRAMES:
		await input.wait_physics_frames(SCREENSHOT_INTERVAL_FRAMES)
		elapsed_frames += SCREENSHOT_INTERVAL_FRAMES
		var explosion_nodes := _explosion_nodes_since(before_attack_ids)
		var explosion_observed := not explosion_nodes.is_empty()
		await _capture_after_throw(elapsed_frames, explosion_observed, explosion_nodes)
		if explosion_observed:
			stop_reason = "explosion_observed"
			explosion_frame = elapsed_frames
			break

	_write_result({
		"ok": true,
		"display_driver": DisplayServer.get_name(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"used_for_score": false,
		"screenshot_interval_frames": SCREENSHOT_INTERVAL_FRAMES,
		"stop_reason": stop_reason,
		"explosion_frame": explosion_frame,
		"captures": captures,
	})
	quit(0)


func _wait_for_debug_arena_ready() -> bool:
	for _i in range(540):
		if root.find_child("DebugCamera", true, false) != null and root.find_child("DebugVisibleFloor", true, false) != null:
			return true
		await physics_frame
	return false


func _wait_process_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _capture_after_throw(elapsed_frames: int, explosion_observed: bool, explosion_nodes: Array[String]) -> void:
	await _wait_process_frames(RENDER_SETTLE_FRAMES)
	var label := "attack_%03d" % elapsed_frames
	var path := "%s/%s.png" % [OUTPUT_DIR, label]
	var signature := SceneProbe.viewport_screenshot_signature(root, SAMPLE_STEP)
	var saved := SceneProbe.save_viewport_screenshot(root, path)
	var delta_from_previous := SceneProbe.frame_signature_delta(previous_signature, signature)
	var delta_from_baseline := SceneProbe.frame_signature_delta(baseline_signature, signature)
	previous_signature = signature
	var summarized_signature := signature.duplicate()
	summarized_signature.erase("samples")
	captures.append({
		"label": label,
		"elapsed_frames": elapsed_frames,
		"path": path,
		"signature": summarized_signature,
		"saved": saved,
		"delta_from_previous": delta_from_previous,
		"delta_from_baseline": delta_from_baseline,
		"explosion_observed": explosion_observed,
		"explosion_nodes": explosion_nodes,
	})


func _explosion_nodes_since(before: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for node in SceneProbe.new_nodes_since(root, before):
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


func _write_result(result: Dictionary) -> void:
	var file := FileAccess.open("%s/result.json" % OUTPUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"
