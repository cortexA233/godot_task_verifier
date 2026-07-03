extends Node3D

const ArenaBuilder = preload("res://__verifier__/arena_builder.gd")
const DamageTarget = preload("res://__verifier__/verifier_damage_target.gd")
const InputDriver = preload("res://__verifier__/input_driver.gd")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")

const FALLBACK_THROW_DISTANCE := 8.0
const FAR_TARGET_MIN_DISTANCE := 20.0
const FAR_TARGET_EXTRA_DISTANCE := 12.0
const CALIBRATION_SPAWN_RADIUS := 6.0
const CALIBRATION_TRACK_FRAMES := 180
const CALIBRATION_EFFECT_PROXY_RADIUS := 6.0
const CALIBRATION_MIN_TRAVEL_DISTANCE := 0.75
const PROJECTILE_PLAYER_MIN_DISTANCE := 0.4
const DISTANCE_BAND_TARGETS := [4.0, 6.0, 8.0, 10.0, 12.0, 14.0]

var input
var arena: Node3D
var player: Node3D


func _ready() -> void:
	name = "VerifierDebugArena"
	call_deferred("_setup_debug_arena")


func _setup_debug_arena() -> void:
	_build_base_arena()
	var calibration := await _calibrate_default_throw_distance()
	await _clear_debug_children()
	_build_base_arena()
	if _calibration_usable(calibration):
		_apply_adaptive_target_layout(float(calibration.get("distance", FALLBACK_THROW_DISTANCE)))
	else:
		_add_distance_band_targets()
	_add_visible_floor()
	_add_controls_label(calibration)
	_add_debug_camera()
	_add_debug_light()
	print("Verifier debug arena ready. Open res://__verifier__/debug_arena.tscn and run this scene.")


func _clear_debug_children() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame


func _build_base_arena() -> void:
	input = InputDriver.new(get_tree())
	arena = ArenaBuilder.create_arena()
	add_child(arena)
	player = ArenaBuilder.add_player(arena)
	ArenaBuilder.add_optional_weapon_ui(arena, player)


func _calibrate_default_throw_distance() -> Dictionary:
	if player == null:
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "no player available")
	await input.wait_physics_frames(8)
	player.rotation.y = 0.0
	await input.wait_physics_frames(4)
	await input.tap(_weapon_switch_action(), 3, 10)
	var before_ids := SceneProbe.collect_instance_ids(arena)
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before_ids), player.global_position, CALIBRATION_SPAWN_RADIUS)
	if spawned.is_empty():
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "no nearby projectile-like node spawned")
	var candidate_records: Array[Dictionary] = []
	for candidate in spawned:
		if is_instance_valid(candidate):
			candidate_records.append({
				"id": candidate.get_instance_id(),
				"name": String(candidate.name),
			})
	var tracks: Dictionary = await SceneProbe.track_nodes_positions(get_tree(), spawned, CALIBRATION_TRACK_FRAMES)
	var best_distance := -1.0
	var best_score := -999999.0
	var best_note := ""
	for candidate_record in candidate_records:
		var id: int = int(candidate_record.get("id", 0))
		var candidate_name := String(candidate_record.get("name", "candidate"))
		var points: Array = tracks.get(id, [])
		if not SceneProbe.calibration_path_is_usable(points, player.global_position, PROJECTILE_PLAYER_MIN_DISTANCE, CALIBRATION_MIN_TRAVEL_DISTANCE):
			continue
		var travel: float = SceneProbe.horizontal_travel_distance(points)
		var end_point: Vector3 = points[points.size() - 1]
		var proxy_point := _detonation_proxy_point(before_visible, end_point)
		var distance: float = SceneProbe.horizontal_distance(player.global_position, proxy_point)
		var candidate_score: float = -absf(distance - FALLBACK_THROW_DISTANCE)
		if candidate_score > best_score:
			best_score = candidate_score
			best_distance = distance
			best_note = "measured default throw at %.2f units from %s after %.2f units of horizontal travel" % [distance, candidate_name, travel]
	if best_distance < 0.0:
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "spawned nodes did not travel far enough for calibration")
	return _calibration_result("measured", best_distance, best_note)


func _detonation_proxy_point(before_visible: Dictionary, fallback_point: Vector3) -> Vector3:
	var proxies := SceneProbe.newly_visible_3d_nodes(arena, before_visible, fallback_point, CALIBRATION_EFFECT_PROXY_RADIUS)
	var best_point := fallback_point
	var best_distance := INF
	for proxy in proxies:
		var distance: float = proxy.global_position.distance_to(fallback_point)
		if distance < best_distance:
			best_distance = distance
			best_point = proxy.global_position
	return best_point


func _calibration_result(status: String, distance: float, notes: String) -> Dictionary:
	var calibration := {}
	calibration["status"] = status
	calibration["distance"] = distance
	calibration["notes"] = notes
	return calibration


func _calibration_usable(calibration: Dictionary) -> bool:
	return String(calibration.get("status", "failed")) == "measured"


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"


func _apply_adaptive_target_layout(target_forward_distance: float) -> void:
	var far_forward_distance: float = maxf(FAR_TARGET_MIN_DISTANCE, target_forward_distance + FAR_TARGET_EXTRA_DISTANCE)
	_add_standard_target_layout(target_forward_distance, far_forward_distance)


func _add_standard_target_layout(target_forward_distance: float, far_forward_distance: float) -> void:
	_add_damage_target("NearTargetA", Vector3(0, 0.5, -target_forward_distance))
	_add_damage_target("NearTargetB", Vector3(1.5, 0.5, -target_forward_distance))
	_add_damage_target("FarTarget", Vector3(0, 0.5, -far_forward_distance))
	_add_damage_target("LeftSideTarget", Vector3(-7, 0.5, -target_forward_distance))
	_add_damage_target("RightSideTarget", Vector3(8.5, 0.5, -target_forward_distance))
	_add_damage_target("RearTarget", Vector3(0, 0.5, 6))
	_add_target_label("NearTargetA", Vector3(0, 1.55, -target_forward_distance))
	_add_target_label("NearTargetB", Vector3(1.5, 1.55, -target_forward_distance))
	_add_target_label("FarTarget", Vector3(0, 1.55, -far_forward_distance))
	_add_target_label("LeftSideTarget", Vector3(-7, 1.55, -target_forward_distance))
	_add_target_label("RightSideTarget", Vector3(8.5, 1.55, -target_forward_distance))
	_add_target_label("RearTarget", Vector3(0, 1.55, 6))


func _add_distance_band_targets() -> void:
	for distance in DISTANCE_BAND_TARGETS:
		var forward_distance: float = float(distance)
		var target_name := "DistanceBandTarget%d" % int(forward_distance)
		_add_damage_target(target_name, Vector3(0, 0.5, -forward_distance))
		_add_target_label("%dm" % int(forward_distance), Vector3(0, 1.55, -forward_distance), Color(0.9, 1.0, 0.5))


func _add_damage_target(target_name: String, position: Vector3) -> Node3D:
	var target: Node3D = DamageTarget.new()
	target.name = target_name
	arena.add_child(target)
	target.global_position = position
	return target


func _add_visible_floor() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DebugVisibleFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 36)
	mesh.mesh = plane
	mesh.position = Vector3(0, -0.03, -8)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.22, 0.28, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	add_child(mesh)


func _add_target_label(label_text: String, position: Vector3, color: Color = Color(1.0, 0.95, 0.55)) -> void:
	var label := Label3D.new()
	label.name = label_text + "Label"
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	label.modulate = color
	label.position = position
	add_child(label)


func _add_controls_label(calibration: Dictionary) -> void:
	var label := Label3D.new()
	label.name = "DebugControlsLabel"
	var status := String(calibration.get("status", "failed"))
	var distance := float(calibration.get("distance", FALLBACK_THROW_DISTANCE))
	var notes := String(calibration.get("notes", "calibration did not run"))
	if _calibration_usable(calibration):
		label.text = "Verifier debug arena\nTab: switch weapon\nAttack: throw grenade\nadaptive target distance %.2fm\n%s" % [distance, notes]
	else:
		label.text = "Verifier debug arena\nTab: switch weapon\nAttack: throw grenade\ncalibration %s; showing distance band fallback\n%s" % [status, notes]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.outline_size = 6
	label.modulate = Color(0.8, 0.92, 1.0)
	label.position = Vector3(-4.5, 2.5, -3.2)
	add_child(label)


func _add_debug_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "DebugCamera"
	camera.current = true
	add_child(camera)
	camera.global_position = Vector3(7, 7, 10)
	camera.look_at(Vector3(0, 0.8, -8), Vector3.UP)


func _add_debug_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DebugDirectionalLight"
	sun.light_energy = 2.4
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)
