extends Node3D

const ArenaBuilder = preload("res://__verifier__/arena_builder.gd")
const DamageTarget = preload("res://__verifier__/verifier_damage_target.gd")
const InputDriver = preload("res://__verifier__/input_driver.gd")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")
const MouseSafety = preload("res://__verifier__/mouse_safety.gd")

const FALLBACK_THROW_DISTANCE := 8.0
const TARGET_FIELD_RADIUS := 30.0
const FAR_TARGET_DISTANCE := 25.0
const NEARBY_TARGET_GROUP_DEGREES := 20
const NEARBY_TARGET_GROUP_COUNT := 18
const EXPLOSION_TRIAL_SEEDS := [17031, 27059, 37087]
const EXPLOSION_TRIAL_BASE_HEADING_DEGREES := [-40.0, 0.0, 40.0]
const CALIBRATION_SPAWN_RADIUS := 6.0
const CALIBRATION_TRACK_FRAMES := 180
const CALIBRATION_EFFECT_PROXY_RADIUS := 6.0
const CALIBRATION_MIN_TRAVEL_DISTANCE := 0.75
const PROJECTILE_PLAYER_MIN_DISTANCE := 0.4
const DISTANCE_BAND_TARGETS := [4.0, 6.0, 8.0, 10.0, 12.0, 14.0]
const NEARBY_DAMAGE_TARGET_RADII := [6.0, 8.0, 10.0, 12.0]

var input
var arena: Node3D
var player: Node3D
var mouse_safety: Node


func _ready() -> void:
	name = "VerifierDebugArena"
	_install_mouse_safety()
	call_deferred("_setup_debug_arena")


func _install_mouse_safety() -> void:
	if mouse_safety != null and is_instance_valid(mouse_safety):
		if mouse_safety.has_method("force_visible_for_startup"):
			mouse_safety.call("force_visible_for_startup")
		return
	mouse_safety = MouseSafety.new()
	mouse_safety.name = "VerifierMouseSafety"
	add_child(mouse_safety)


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
		if child == mouse_safety or child.name == "VerifierMouseSafety":
			continue
		child.queue_free()
	await get_tree().process_frame


func _build_base_arena() -> void:
	input = InputDriver.new(get_tree())
	arena = ArenaBuilder.create_arena()
	add_child(arena)
	player = ArenaBuilder.add_player(arena)
	ArenaBuilder.add_optional_weapon_ui(arena, player)
	_install_mouse_safety()


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
	for trial in _explosion_trial_variants(target_forward_distance):
		_add_seeded_trial_layout(trial)


func _explosion_trial_variants(target_forward_distance: float) -> Array[Dictionary]:
	var variants: Array[Dictionary] = []
	for index in range(EXPLOSION_TRIAL_SEEDS.size()):
		var seed_value := int(EXPLOSION_TRIAL_SEEDS[index])
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var base_heading_degrees := float(EXPLOSION_TRIAL_BASE_HEADING_DEGREES[index % EXPLOSION_TRIAL_BASE_HEADING_DEGREES.size()])
		var heading_y := deg_to_rad(base_heading_degrees + rng.randf_range(-6.0, 6.0))
		var safety_radius := clampf(FAR_TARGET_DISTANCE + rng.randf_range(-1.0, 2.0), FAR_TARGET_DISTANCE - 1.0, TARGET_FIELD_RADIUS)
		var nearby_radii := _seeded_nearby_damage_radii(rng, target_forward_distance)
		variants.append({
			"label": "Seed %d throw" % seed_value,
			"seed": seed_value,
			"heading_y": heading_y,
			"target_group": _target_group_for_heading(heading_y),
			"nearby_radii": nearby_radii,
			"safety_radius": safety_radius,
		})
	return variants


func _seeded_nearby_damage_radii(rng: RandomNumberGenerator, target_forward_distance: float) -> Array[float]:
	var radii: Array[float] = []
	for index in range(NEARBY_DAMAGE_TARGET_RADII.size()):
		var base_radius := float(NEARBY_DAMAGE_TARGET_RADII[index])
		if index == 2:
			base_radius = target_forward_distance
		var jittered_radius := clampf(base_radius + rng.randf_range(-0.35, 0.35), 4.0, TARGET_FIELD_RADIUS - 1.0)
		radii.append(round(jittered_radius * 4.0) / 4.0)
	return radii


func _add_seeded_trial_layout(trial: Dictionary) -> void:
	var seed_value := int(trial["seed"])
	var heading_y := float(trial["heading_y"])
	var target_group := String(trial["target_group"])
	var safety_radius := float(trial["safety_radius"])
	var nearby_radii: Array = trial["nearby_radii"]
	for radius_value in nearby_radii:
		var radius := float(radius_value)
		var position := _polar_target_position(heading_y, radius)
		var target_name := "NearbyTarget_Seed%d_%s_%04d" % [seed_value, target_group, int(round(radius * 100.0))]
		_add_damage_target(target_name, position)
		_add_target_label("Seed %d %s %.2fm" % [seed_value, target_group, radius], position + Vector3.UP * 1.05, Color(0.9, 1.0, 0.5))
	var destructible_position := _offset_polar_target_position(heading_y, _target_forward_radius(nearby_radii), 1.1)
	_add_damageable_only_target("NearbyDestructible_Seed%d" % seed_value, destructible_position)
	_add_target_label("Seed %d damageable-only" % seed_value, destructible_position + Vector3.UP * 1.05, Color(0.4, 1.0, 0.85))
	_add_debug_safety_target("FarTarget_Seed%d" % seed_value, "Seed %d far %.1fm" % [seed_value, safety_radius], heading_y, safety_radius)
	_add_debug_safety_target("LeftSideTarget_Seed%d" % seed_value, "Seed %d left %.1fm" % [seed_value, safety_radius], heading_y - PI * 0.5, safety_radius)
	_add_debug_safety_target("RightSideTarget_Seed%d" % seed_value, "Seed %d right %.1fm" % [seed_value, safety_radius], heading_y + PI * 0.5, safety_radius)
	_add_debug_safety_target("RearTarget_Seed%d" % seed_value, "Seed %d rear %.1fm" % [seed_value, safety_radius], heading_y + PI, safety_radius)


func _add_debug_safety_target(target_name: String, label_text: String, heading_y: float, radius: float) -> void:
	var position := _polar_target_position(heading_y, radius)
	_add_damage_target(target_name, position)
	_add_target_label(label_text, position + Vector3.UP * 1.05)


func _target_group_for_heading(heading_y: float) -> String:
	var snapped_degrees := int(round(rad_to_deg(heading_y) / float(NEARBY_TARGET_GROUP_DEGREES))) * NEARBY_TARGET_GROUP_DEGREES
	return _nearby_target_group_name(snapped_degrees)


func _nearby_target_group_name(degrees: int) -> String:
	return "Angle%03d" % _wrapped_degrees(degrees)


func _wrapped_degrees(degrees: int) -> int:
	var wrapped := degrees
	while wrapped < 0:
		wrapped += 360
	while wrapped >= 360:
		wrapped -= 360
	return wrapped


func _add_distance_band_targets() -> void:
	for distance in DISTANCE_BAND_TARGETS:
		var forward_distance: float = float(distance)
		var target_name := "DistanceBandTarget%d" % int(forward_distance)
		_add_damage_target(target_name, Vector3(0, 0.5, -forward_distance))
		_add_target_label("%dm" % int(forward_distance), Vector3(0, 1.55, -forward_distance), Color(0.9, 1.0, 0.5))


func _polar_target_position(heading_y: float, radius: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (basis * Vector3.FORWARD).normalized()
	return forward * minf(radius, TARGET_FIELD_RADIUS) + Vector3.UP * 0.5


func _offset_polar_target_position(heading_y: float, radius: float, side_offset: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (basis * Vector3.FORWARD).normalized()
	var right := (basis * Vector3.RIGHT).normalized()
	return forward * minf(radius, TARGET_FIELD_RADIUS) + right * side_offset + Vector3.UP * 0.5


func _target_forward_radius(nearby_radii: Array) -> float:
	if nearby_radii.size() > 2:
		return float(nearby_radii[2])
	return FALLBACK_THROW_DISTANCE


func _add_damage_target(target_name: String, position: Vector3) -> Node3D:
	var target: Node3D = DamageTarget.new()
	target.name = target_name
	arena.add_child(target)
	target.global_position = position
	return target


func _add_damageable_only_target(target_name: String, position: Vector3) -> Node3D:
	var target: Node3D = DamageTarget.new()
	target.name = target_name
	target.set("targetable", false)
	arena.add_child(target)
	target.global_position = position
	return target


func _add_visible_floor() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DebugVisibleFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(TARGET_FIELD_RADIUS * 2.2, TARGET_FIELD_RADIUS * 2.2)
	mesh.mesh = plane
	mesh.position = Vector3(0, -0.03, 0)
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
		label.text = "Verifier debug arena\nTab: switch weapon\nAttack: throw grenade\nfixed seed target variants; calibrated throw %.2fm\n%s" % [distance, notes]
	else:
		label.text = "Verifier debug arena\nTab: switch weapon\nAttack: throw grenade\ncalibration %s; showing distance band fallback\n%s" % [status, notes]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.outline_size = 6
	label.modulate = Color(0.8, 0.92, 1.0)
	label.position = Vector3(-16, 3.2, 12)
	add_child(label)


func _add_debug_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "DebugCamera"
	camera.current = true
	add_child(camera)
	camera.global_position = Vector3(18, 24, 26)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)


func _add_debug_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DebugDirectionalLight"
	sun.light_energy = 2.4
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)
