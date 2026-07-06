extends SceneTree

const ScoreBoard = preload("res://__verifier__/score_board.gd")
const JsonWriter = preload("res://__verifier__/json_writer.gd")
const ArenaBuilder = preload("res://__verifier__/arena_builder.gd")
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
const CALIBRATION_FULL_MIN_DISTANCE := 6.0
const CALIBRATION_FULL_MAX_DISTANCE := 12.0
const CALIBRATION_BORDERLINE_MIN_DISTANCE := 4.0
const CALIBRATION_BORDERLINE_MAX_DISTANCE := 14.0
const CALIBRATION_SPAWN_RADIUS := 6.0
const CALIBRATION_TRACK_FRAMES := 180
const CALIBRATION_EFFECT_PROXY_RADIUS := 6.0
const CALIBRATION_MIN_TRAVEL_DISTANCE := 0.75
const PROJECTILE_PLAYER_MIN_DISTANCE := 0.4
const TRAJECTORY_AID_RADIUS := 25.0
const TRAJECTORY_AIM_CHANGE_HEADING := 0.45
const TRAJECTORY_DIRECTION_MIN_DOT := 0.5
const TRAJECTORY_PROJECTILE_TRACK_FRAMES := 35
const NEARBY_DAMAGE_TARGET_RADII := [6.0, 8.0, 10.0, 12.0]
const PROJECTILE_VISUAL_MIN_EXTENT := 0.02
const PROJECTILE_VISUAL_MAX_EXTENT := 2.0

var board
var input
var arena: Node3D
var player: Node3D
var weapon_ui: Node
var mouse_safety: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(12345)
	board = ScoreBoard.new()
	input = InputDriver.new(self)
	_install_mouse_safety()
	print("Verifier swap input route: ", input.describe_route(_weapon_switch_action()))
	await _build_arena()
	await _score_weapon_controls()
	await _build_arena()
	await _score_hud_feedback()
	await _build_arena()
	await _score_trajectory_preview()
	await _build_arena()
	await _score_projectile_physics()
	await _build_arena()
	await _score_explosion_gameplay()
	await _build_arena()
	await _score_visual_audio_polish()
	await _build_arena()
	await _score_stability_repeatability()
	await _cleanup_before_quit()
	JsonWriter.write_result(board.to_dictionary(Engine.get_version_info().get("string", "")))
	quit()


func _cleanup_before_quit() -> void:
	paused = false
	_stop_audio_players_under(root)
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
		arena = null
		player = null
		weapon_ui = null
	await process_frame
	await process_frame


func _install_mouse_safety() -> void:
	if mouse_safety != null and is_instance_valid(mouse_safety):
		if mouse_safety.has_method("force_visible_for_startup"):
			mouse_safety.call("force_visible_for_startup")
		return
	mouse_safety = MouseSafety.new()
	mouse_safety.name = "VerifierMouseSafety"
	root.add_child(mouse_safety)


func _build_arena() -> void:
	if arena != null and is_instance_valid(arena):
		_stop_audio_players_under(arena)
		arena.queue_free()
		await process_frame
	arena = ArenaBuilder.create_arena()
	root.add_child(arena)
	player = ArenaBuilder.add_player(arena)
	weapon_ui = ArenaBuilder.add_optional_weapon_ui(arena, player)
	_install_mouse_safety()
	await input.wait_physics_frames(8)
	if player == null:
		push_warning("Player scene did not instantiate.")
	else:
		print("Player scene instantiated in deterministic arena.")


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"


func _tap_weapon_switch(frames_pressed: int = 3, frames_after: int = 8) -> void:
	await input.tap(_weapon_switch_action(), frames_pressed, frames_after)


func _switch_route_has_joypad_binding() -> bool:
	for action in InputMap.get_actions():
		if not _action_is_weapon_switch_route(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				return true
	return false


func _action_is_weapon_switch_route(action: StringName) -> bool:
	if action == &"swap_weapons" or action == &"weapon_switch":
		return true
	if String(action).begins_with("ui_"):
		return false
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and (key_event.keycode == KEY_TAB or key_event.physical_keycode == KEY_TAB):
			return true
	return false


func _detail(label: String, score: int, max_score: int, status: String, notes: String) -> Dictionary:
	return {
		"label": label,
		"score": clampi(score, 0, max_score),
		"max": max_score,
		"status": status,
		"notes": notes,
	}


func _score_detail(label: String, max_score: int, earned: bool, earned_notes: String, missed_notes: String) -> Dictionary:
	if earned:
		return _detail(label, max_score, max_score, "earned", earned_notes)
	return _detail(label, 0, max_score, "missed", missed_notes)


func _detail_score(details: Array[Dictionary]) -> int:
	var score := 0
	for detail in details:
		score += int(detail.get("score", 0))
	return score


func _detail_notes(details: Array[Dictionary]) -> String:
	var notes: Array[String] = []
	for detail in details:
		notes.append(String(detail.get("notes", "")))
	return "; ".join(notes)


func _score_weapon_controls() -> void:
	var details: Array[Dictionary] = []
	var switch_route: String = input.describe_route(_weapon_switch_action())
	details.append(_score_detail(
		"Controller weapon-switch binding",
		2,
		_switch_route_has_joypad_binding(),
		"a weapon-switch input route also carries a controller binding",
		"no weapon-switch input route carries a controller binding"
	))
	if player == null:
		board.add("weapon_controls", _detail_score(details), 15, _detail_notes(details), details)
		return
	var before_switch_attack := SceneProbe.collect_instance_ids(arena)
	await _tap_weapon_switch()
	await input.tap("attack")
	var switch_attack_nodes := SceneProbe.new_nodes_since(arena, before_switch_attack)
	var grenade_attack_observed := switch_attack_nodes.size() > 0
	details.append(_score_detail(
		"Weapon switch input responds",
		2,
		grenade_attack_observed,
		"weapon mode observably switches through %s" % switch_route,
		"weapon mode did not observably switch through %s" % switch_route
	))
	details.append(_score_detail(
		"Grenade attack after switching",
		5,
		grenade_attack_observed,
		"attack after weapon switch created runtime nodes",
		"attack after weapon switch did not create observable runtime nodes"
	))
	var before_spam := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack", 1, 1)
	await input.tap("attack", 1, 1)
	var spam_nodes := SceneProbe.new_nodes_since(arena, before_spam)
	if grenade_attack_observed and spam_nodes.size() <= 2:
		details.append(_detail("Rapid attack rate limit", 3, 3, "earned", "rapid grenade attacks appear rate-limited"))
	elif not grenade_attack_observed:
		details.append(_detail("Rapid attack rate limit", 0, 3, "missed", "rate limit not credited because no grenade attack was observed"))
	else:
		details.append(_detail("Rapid attack rate limit", 0, 3, "missed", "rapid grenade attacks were not observably rate-limited"))
	await _tap_weapon_switch()
	var before_default := SceneProbe.collect_instance_ids(arena)
	await input.hold("aim", 4)
	await input.tap("attack")
	await input.release("aim")
	var default_nodes := SceneProbe.new_nodes_since(arena, before_default)
	details.append(_score_detail(
		"Default weapon still works",
		3,
		default_nodes.size() > 0,
		"default aimed attack still creates runtime nodes",
		"default aimed attack created no observable nodes after switching back"
	))
	board.add("weapon_controls", _detail_score(details), 15, _detail_notes(details), details)


func _score_hud_feedback() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 8, "missed", "No player available.")]
		board.add("hud_feedback", 0, 8, _detail_notes(details), details)
		return
	await input.wait_physics_frames(8)
	var before := SceneProbe.control_snapshot(arena)
	await _tap_weapon_switch()
	var after := SceneProbe.control_snapshot(arena)
	var changed := SceneProbe.count_changed_controls(before, after)
	var details: Array[Dictionary] = []
	var can_switch_weapons: bool = input.can_drive(_weapon_switch_action())
	details.append(_score_detail(
		"Visible UI controls",
		2,
		before.size() >= 2,
		"player has visible UI controls",
		"player has little or no visible UI control tree"
	))
	if can_switch_weapons and changed > 0:
		details.append(_detail("Weapon-switch UI state", 4, 4, "earned", "UI control state changed after weapon switch"))
	elif not can_switch_weapons:
		details.append(_detail("Weapon-switch UI state", 0, 4, "missed", "weapon-switch UI change not credited because weapon-switch input is missing"))
	else:
		details.append(_detail("Weapon-switch UI state", 0, 4, "missed", "UI did not visibly change after weapon switch"))
	await input.hold("aim", 8)
	var aiming_snapshot := SceneProbe.control_snapshot(arena)
	await input.release("aim")
	details.append(_score_detail(
		"Aiming UI feedback",
		2,
		SceneProbe.count_changed_controls(after, aiming_snapshot) > 0,
		"aiming changes UI feedback",
		"aiming did not change UI feedback"
	))
	board.add("hud_feedback", _detail_score(details), 8, _detail_notes(details), details)


func _count_visible_nodes(nodes: Array[Node3D]) -> int:
	var count := 0
	for node in nodes:
		if is_instance_valid(node) and node.visible:
			count += 1
	return count


func _nodes_moved_or_rotated(nodes: Array[Node3D], first_transforms: Array[Transform3D], origin_threshold: float, angle_threshold: float) -> bool:
	for index in range(nodes.size()):
		var node := nodes[index]
		if not is_instance_valid(node) or index >= first_transforms.size():
			continue
		var first_transform := first_transforms[index]
		var origin_moved := node.global_transform.origin.distance_to(first_transform.origin) > origin_threshold
		var basis_moved := node.global_transform.basis.get_euler().distance_to(first_transform.basis.get_euler()) > angle_threshold
		if origin_moved or basis_moved:
			return true
	return false


func _projectile_direction_after_attack(before_attack: Dictionary) -> Vector2:
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before_attack), player.global_position, CALIBRATION_SPAWN_RADIUS)
	if spawned.is_empty():
		return Vector2.ZERO
	var tracks: Dictionary = await SceneProbe.track_nodes_positions(self, spawned, TRAJECTORY_PROJECTILE_TRACK_FRAMES)
	for candidate in spawned:
		if not is_instance_valid(candidate):
			continue
		var points: Array = tracks.get(candidate.get_instance_id(), [])
		var direction := SceneProbe.track_horizontal_direction(points, CALIBRATION_MIN_TRAVEL_DISTANCE)
		if not direction.is_zero_approx():
			return direction
	return Vector2.ZERO


func _score_trajectory_preview() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 22, "missed", "No player available.")]
		board.add("trajectory_preview", 0, 22, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await _tap_weapon_switch(3, 10)
	await input.wait_physics_frames(8)
	var aiming_aid_nodes := SceneProbe.newly_visible_3d_nodes(arena, before_visible, player.global_position, TRAJECTORY_AID_RADIUS)
	var visible_aid := aiming_aid_nodes.size() > 0
	details.append(_score_detail(
		"Visible grenade aiming aid",
		4,
		visible_aid,
		"visible grenade aiming aid appears in grenade mode",
		"no visible grenade trajectory, landing marker, or equivalent aiming aid detected"
	))
	if not visible_aid:
		details.append(_detail("Communicates arcing throw", 0, 4, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Updates with aim/camera direction", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Preview matches projectile direction", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Visibility lifecycle/cooldown behavior", 0, 2, "missed", "trajectory details gated because no visible aiming aid was observed"))
		board.add("trajectory_preview", _detail_score(details), 22, _detail_notes(details), details)
		return

	var first_transforms: Array[Transform3D] = []
	for node in aiming_aid_nodes:
		first_transforms.append(node.global_transform)
	var first_direction := SceneProbe.average_horizontal_direction(aiming_aid_nodes, player.global_position)
	var communicates_arc := SceneProbe.visible_nodes_suggest_arc_or_landing(aiming_aid_nodes, player.global_position)
	details.append(_score_detail(
		"Communicates arcing throw",
		4,
		communicates_arc,
		"aiming aid communicates an arcing throw or landing area",
		"aiming aid does not clearly communicate an arcing grenade throw"
	))

	_set_explosion_trial_heading(0.45)
	await input.wait_physics_frames(12)
	var second_direction := SceneProbe.average_horizontal_direction(aiming_aid_nodes, player.global_position)
	var moved_feedback := _nodes_moved_or_rotated(aiming_aid_nodes, first_transforms, 0.2, 0.05)
	var changed_direction := (not first_direction.is_zero_approx() and not second_direction.is_zero_approx() and first_direction.dot(second_direction) < 0.95)
	var updates_with_aim := moved_feedback or changed_direction
	details.append(_score_detail(
		"Updates with aim/camera direction",
		6,
		updates_with_aim,
		"aiming aid updates after aim or camera direction changes",
		"aiming aid did not update after aim or camera direction changed"
	))

	var before_attack := SceneProbe.collect_instance_ids(arena)
	var projectile_direction := await _projectile_direction_after_attack(before_attack)
	var consistency := updates_with_aim and SceneProbe.directions_match(second_direction, projectile_direction, TRAJECTORY_DIRECTION_MIN_DOT)
	if consistency:
		details.append(_detail("Preview matches projectile direction", 6, 6, "earned", "aiming aid direction matches the thrown grenade direction"))
	elif not updates_with_aim:
		details.append(_detail("Preview matches projectile direction", 0, 6, "missed", "consistency not credited because aiming aid did not update"))
	elif projectile_direction.is_zero_approx():
		details.append(_detail("Preview matches projectile direction", 0, 6, "missed", "consistency not credited because no measurable grenade projectile direction was observed"))
	else:
		details.append(_detail("Preview matches projectile direction", 0, 6, "missed", "aiming aid direction did not match the thrown grenade direction"))

	await input.wait_physics_frames(12)
	var visible_during_cooldown := _count_visible_nodes(aiming_aid_nodes) > 0
	await _tap_weapon_switch(3, 8)
	await input.wait_physics_frames(8)
	var visible_after_switch := _count_visible_nodes(aiming_aid_nodes)
	var lifecycle_ok := visible_during_cooldown and visible_after_switch < aiming_aid_nodes.size()
	details.append(_score_detail(
		"Visibility lifecycle/cooldown behavior",
		2,
		lifecycle_ok,
		"aiming aid remains available in grenade mode and hides after leaving grenade mode",
		"aiming aid did not show the expected grenade-mode lifecycle"
	))
	board.add("trajectory_preview", _detail_score(details), 22, _detail_notes(details), details)


func _score_projectile_physics() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 15, "missed", "No player available.")]
		board.add("projectile_physics", 0, 15, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	await _tap_weapon_switch()
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before), player.global_position, 6.0)
	if spawned.size() == 0:
		details.append(_detail("Projectile spawned", 0, 4, "missed", "No nearby Node3D spawned after grenade attack."))
		details.append(_detail("Arcing motion", 0, 8, "missed", "arc motion not credited because no projectile spawned"))
		details.append(_detail("Player-safe path", 0, 3, "missed", "player-safe path not credited because no projectile spawned"))
		board.add("projectile_physics", 0, 15, _detail_notes(details), details)
		return
	details.append(_detail("Projectile spawned", 4, 4, "earned", "grenade attack spawned a nearby 3D node"))
	var best_arc := false
	var best_safe := true
	for candidate in spawned:
		if not is_instance_valid(candidate):
			continue
		var points: Array[Vector3] = await SceneProbe.track_node_positions(self, candidate, 35)
		if SceneProbe.has_arc_motion(points):
			best_arc = true
		for point in points:
			if point.distance_to(player.global_position) < 0.4:
				best_safe = false
	details.append(_score_detail(
		"Arcing motion",
		8,
		best_arc,
		"spawned node follows arcing motion",
		"no spawned node showed clear arc motion"
	))
	details.append(_score_detail(
		"Player-safe path",
		3,
		best_safe,
		"projectile path stayed clear of player body",
		"projectile overlapped player body"
	))
	board.add("projectile_physics", _detail_score(details), 15, _detail_notes(details), details)


func _score_explosion_gameplay() -> void:
	var calibration := await _calibrate_default_throw_distance()
	var trial_results: Array[Dictionary] = []
	for trial in _explosion_trial_variants(calibration):
		trial_results.append(await _run_explosion_trial(trial, calibration))
	var details := _explosion_details_from_trials(trial_results, calibration)
	var raw_score := _detail_score(details)
	var capped_score := mini(raw_score, _explosion_gameplay_score_cap(trial_results))
	var notes := _detail_notes(details)
	if capped_score < raw_score:
		notes += "; global damage sweep cap applied: explosion_gameplay limited to %d/20" % capped_score
	_flag_explosion_suspects(trial_results, capped_score < raw_score)
	board.add("explosion_gameplay", capped_score, 20, notes, details)


func _explosion_trial_variants(calibration: Dictionary) -> Array[Dictionary]:
	var variants: Array[Dictionary] = []
	var target_forward_distance := _target_forward_distance(calibration)
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
			"target_forward_distance": target_forward_distance,
		})
	return variants


func _seeded_nearby_damage_radii(rng: RandomNumberGenerator, target_forward_distance: float) -> Array[float]:
	var radii: Array[float] = []
	for index in range(NEARBY_DAMAGE_TARGET_RADII.size()):
		var base_radius := float(NEARBY_DAMAGE_TARGET_RADII[index])
		if index == 2:
			base_radius = target_forward_distance
		var jittered_radius := clampf(base_radius + rng.randf_range(-0.35, 0.35), CALIBRATION_BORDERLINE_MIN_DISTANCE, TARGET_FIELD_RADIUS - 1.0)
		radii.append(round(jittered_radius * 4.0) / 4.0)
	return radii


func _calibrate_default_throw_distance() -> Dictionary:
	await _build_arena()
	if player == null:
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "default throw calibration failed: no player available")
	_set_explosion_trial_heading(0.0)
	await input.wait_physics_frames(4)
	await _tap_weapon_switch(3, 10)
	var before_ids := SceneProbe.collect_instance_ids(arena)
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before_ids), player.global_position, CALIBRATION_SPAWN_RADIUS)
	if spawned.is_empty():
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "default throw calibration failed: no nearby projectile-like node spawned")
	var candidate_records: Array[Dictionary] = []
	for candidate in spawned:
		if is_instance_valid(candidate):
			candidate_records.append({
				"id": candidate.get_instance_id(),
				"name": String(candidate.name),
			})
	var tracks: Dictionary = await SceneProbe.track_nodes_positions(self, spawned, CALIBRATION_TRACK_FRAMES)
	var best_distance := -1.0
	var best_score := -999999.0
	var best_note := ""
	for candidate_record in candidate_records:
		var id: int = int(candidate_record.get("id", 0))
		var candidate_name := String(candidate_record.get("name", "candidate"))
		var points: Array = tracks.get(id, [])
		if not SceneProbe.calibration_path_is_usable(points, player.global_position, PROJECTILE_PLAYER_MIN_DISTANCE, CALIBRATION_MIN_TRAVEL_DISTANCE):
			continue
		var travel := SceneProbe.horizontal_travel_distance(points)
		var end_point: Vector3 = points[points.size() - 1]
		var proxy_point := _detonation_proxy_point(before_visible, end_point)
		var distance := SceneProbe.horizontal_distance(player.global_position, proxy_point)
		var candidate_score := _calibration_candidate_score(distance)
		if candidate_score > best_score:
			best_score = candidate_score
			best_distance = distance
			best_note = "default throw calibration measured %.2f units from %s after %.2f units of horizontal travel" % [distance, candidate_name, travel]
	if best_distance < 0.0:
		return _calibration_result("failed", FALLBACK_THROW_DISTANCE, "default throw calibration failed: spawned nodes did not produce a safe measurable travel path")
	return _calibration_result(_calibration_band(best_distance), best_distance, best_note)


func _detonation_proxy_point(before_visible: Dictionary, fallback_point: Vector3) -> Vector3:
	var proxies := SceneProbe.newly_visible_3d_nodes(arena, before_visible, fallback_point, CALIBRATION_EFFECT_PROXY_RADIUS)
	var best_point := fallback_point
	var best_distance := INF
	for proxy in proxies:
		var distance := proxy.global_position.distance_to(fallback_point)
		if distance < best_distance:
			best_distance = distance
			best_point = proxy.global_position
	return best_point


func _calibration_candidate_score(distance: float) -> float:
	var center: float = (CALIBRATION_FULL_MIN_DISTANCE + CALIBRATION_FULL_MAX_DISTANCE) * 0.5
	var distance_from_center: float = absf(distance - center)
	if distance >= CALIBRATION_FULL_MIN_DISTANCE and distance <= CALIBRATION_FULL_MAX_DISTANCE:
		return 1000.0 - distance_from_center
	if distance >= CALIBRATION_BORDERLINE_MIN_DISTANCE and distance <= CALIBRATION_BORDERLINE_MAX_DISTANCE:
		return 500.0 - distance_from_center
	return -distance_from_center


func _calibration_band(distance: float) -> String:
	if distance >= CALIBRATION_FULL_MIN_DISTANCE and distance <= CALIBRATION_FULL_MAX_DISTANCE:
		return "full"
	if distance >= CALIBRATION_BORDERLINE_MIN_DISTANCE and distance <= CALIBRATION_BORDERLINE_MAX_DISTANCE:
		return "borderline"
	return "failed"


func _calibration_result(status: String, distance: float, notes: String) -> Dictionary:
	var effective_distance := distance
	if status == "failed":
		effective_distance = FALLBACK_THROW_DISTANCE
		notes += "; using fixed fallback target geometry"
	elif status == "borderline":
		notes += "; default throw distance is outside the preferred 6-12 unit envelope but still usable"
	var calibration := {}
	calibration["status"] = status
	calibration["distance"] = effective_distance
	calibration["notes"] = notes
	return calibration


func _target_forward_distance(calibration: Dictionary) -> float:
	var status := String(calibration.get("status", "failed"))
	if status == "full" or status == "borderline":
		return float(calibration.get("distance", FALLBACK_THROW_DISTANCE))
	return FALLBACK_THROW_DISTANCE


func _run_explosion_trial(trial: Dictionary, calibration: Dictionary) -> Dictionary:
	var trial_label := String(trial.get("label", "Seeded explosion trial"))
	var seed_value := int(trial.get("seed", 0))
	var heading_y := float(trial.get("heading_y", 0.0))
	var target_group := String(trial.get("target_group", _target_group_for_heading(heading_y)))
	var nearby_radii: Array = trial.get("nearby_radii", NEARBY_DAMAGE_TARGET_RADII)
	var safety_radius := float(trial.get("safety_radius", FAR_TARGET_DISTANCE))
	await _build_arena()
	if player == null:
		return {
			"label": trial_label,
			"seed": seed_value,
			"near_score": 0,
			"detonation_observed": false,
			"player_safe": false,
			"effects_observed": false,
			"damaged_safety_targets": [],
			"notes": "No player available.",
		}
	_set_explosion_trial_heading(heading_y)
	await input.wait_physics_frames(4)
	var target_forward_distance := _target_forward_distance(calibration)
	var nearby_layout := _add_nearby_damage_targets(arena, target_group, nearby_radii)
	var all_nearby_targets: Array = nearby_layout["all"]
	var nearby_targets: Array = nearby_layout["scored"]
	var nearby_destructible_target := _add_nearby_destructible_target(arena, heading_y, target_forward_distance)
	var safety_targets: Array = [
		_add_safety_target(arena, "FarTarget", heading_y, safety_radius),
		_add_safety_target(arena, "LeftSideTarget", heading_y - PI * 0.5, safety_radius),
		_add_safety_target(arena, "RightSideTarget", heading_y + PI * 0.5, safety_radius),
		_add_safety_target(arena, "RearTarget", heading_y + PI, safety_radius),
	]
	await input.wait_physics_frames(4)
	await _tap_weapon_switch(3, 10)
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	var effect_origin := player.global_position
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, effect_origin, TARGET_FIELD_RADIUS, 180)
	var damaged_safety_targets: Array[String] = []
	for safety_target in safety_targets:
		if safety_target.damage_calls > 0:
			damaged_safety_targets.append(String(safety_target.name))
	var expected_nearby_hits := _count_damaged_targets(nearby_targets)
	var nearby_hits := _count_damaged_targets(all_nearby_targets)
	var nearby_destructible_hit: bool = int(nearby_destructible_target.get("damage_calls")) > 0
	var global_sweep := _global_sweep_detected(nearby_hits, all_nearby_targets.size(), damaged_safety_targets)
	var near_score := _nearby_hit_score(expected_nearby_hits, nearby_hits, damaged_safety_targets.size(), global_sweep)
	var damage_detonation_observed: bool = nearby_hits > 0 or nearby_destructible_hit or damaged_safety_targets.size() > 0
	var player_safe := damage_detonation_observed and (not player is CharacterBody3D or (player as CharacterBody3D).velocity.length() < 20.0)
	return {
		"label": trial_label,
		"seed": seed_value,
		"near_score": near_score,
		"nearby_hits": nearby_hits,
		"expected_nearby_hits": expected_nearby_hits,
		"nearby_destructible_hit": nearby_destructible_hit,
		"nearby_target_count": nearby_targets.size(),
		"nearby_total_target_count": all_nearby_targets.size(),
		"detonation_observed": damage_detonation_observed,
		"player_safe": player_safe,
		"effects_observed": damage_detonation_observed and int(activity.get("visible_count", 0)) > 0,
		"damaged_safety_targets": damaged_safety_targets,
		"global_sweep_detected": global_sweep,
		"calibration_status": String(calibration.get("status", "failed")),
		"calibration_distance": float(calibration.get("distance", FALLBACK_THROW_DISTANCE)),
		"target_forward_distance": target_forward_distance,
		"heading_y": heading_y,
		"target_group": target_group,
		"nearby_radii": nearby_radii,
		"safety_radius": safety_radius,
	}


func _add_nearby_destructible_target(root_node: Node3D, heading_y: float, radius: float) -> Node3D:
	var target := ArenaBuilder.add_damageable_only_target(root_node, "NearbyDestructibleTarget", _offset_polar_target_position(heading_y, radius, 1.1))
	return target


func _add_nearby_damage_targets(root_node: Node3D, target_group: String, nearby_radii: Array) -> Dictionary:
	var all_targets: Array = []
	var scored_targets: Array = []
	for group_data in _nearby_damage_target_groups():
		var group := String(group_data["target_group"])
		for radius_value in nearby_radii:
			var radius := float(radius_value)
			var target = ArenaBuilder.add_damage_target(root_node, "NearbyTarget", _polar_target_position(float(group_data["heading_y"]), radius))
			target.name = "NearbyTarget_%s_%02d" % [group, int(radius)]
			all_targets.append(target)
			if group == target_group:
				scored_targets.append(target)
	return {
		"all": all_targets,
		"scored": scored_targets,
	}


func _nearby_damage_target_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for index in range(NEARBY_TARGET_GROUP_COUNT):
		var degrees := index * NEARBY_TARGET_GROUP_DEGREES
		groups.append({
			"target_group": _nearby_target_group_name(degrees),
			"heading_y": deg_to_rad(float(degrees)),
			"degrees": degrees,
		})
	return groups


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


func _add_safety_target(root_node: Node3D, target_name: String, heading_y: float, radius: float) -> Node3D:
	return ArenaBuilder.add_damage_target(root_node, target_name, _polar_target_position(heading_y, radius))


func _count_damaged_targets(targets: Array) -> int:
	var hits := 0
	for target in targets:
		if target.damage_calls > 0:
			hits += 1
	return hits


func _nearby_hit_score(expected_nearby_hits: int, nearby_hits: int, damaged_safety_count: int, global_sweep: bool) -> int:
	if global_sweep:
		return 3 if expected_nearby_hits > 0 else 1
	if damaged_safety_count > 0 and expected_nearby_hits > 0:
		return 6
	if expected_nearby_hits > 0:
		return 10
	if nearby_hits > 0:
		return 5
	return 0


func _global_sweep_detected(nearby_hits: int, nearby_total_target_count: int, damaged_safety_targets: Array) -> bool:
	if nearby_total_target_count <= 0:
		return false
	var nearby_threshold := int(ceil(float(nearby_total_target_count) * 0.7))
	return nearby_hits >= nearby_threshold and damaged_safety_targets.size() >= 3


func _set_explosion_trial_heading(heading_y: float) -> void:
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


func _polar_target_position(heading_y: float, radius: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (basis * Vector3.FORWARD).normalized()
	return forward * minf(radius, TARGET_FIELD_RADIUS) + Vector3.UP * 0.5


func _offset_polar_target_position(heading_y: float, radius: float, side_offset: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (basis * Vector3.FORWARD).normalized()
	var right := (basis * Vector3.RIGHT).normalized()
	return forward * minf(radius, TARGET_FIELD_RADIUS) + right * side_offset + Vector3.UP * 0.5


func _calibration_quality_score(calibration_status: String) -> int:
	if calibration_status == "full":
		return 2
	return 0


func _explosion_details_from_trials(trial_results: Array[Dictionary], calibration: Dictionary) -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	if trial_results.is_empty():
		details.append(_detail("Explosion trials", 0, 20, "missed", "No explosion trials were configured."))
		return details
	var calibration_status := String(calibration.get("status", "failed"))
	var calibration_distance := float(calibration.get("distance", FALLBACK_THROW_DISTANCE))
	var calibration_notes := String(calibration.get("notes", "default throw calibration did not run"))
	var calibration_prefix := "default throw calibration %s at %.2f units: %s" % [calibration_status, calibration_distance, calibration_notes]
	var total_near_score := 0
	var destructible_hit_count := 0
	var localized_count := 0
	var player_safe_count := 0
	var all_trials_detonated := true
	var safety_misses: Array[String] = []
	var near_notes: Array[String] = []
	var destructible_notes: Array[String] = []
	var locality_notes: Array[String] = []
	var player_notes: Array[String] = []
	for trial_result in trial_results:
		var label := String(trial_result["label"])
		var near_score := int(trial_result["near_score"])
		total_near_score += near_score
		near_notes.append("%s raw nearby hit score %d/10" % [label, near_score])
		var detonation_observed := bool(trial_result["detonation_observed"])
		if not detonation_observed:
			all_trials_detonated = false
		var damaged_safety_targets: Array = trial_result["damaged_safety_targets"]
		if damaged_safety_targets.size() > 0:
			safety_misses.append("%s damaged %s" % [label, ", ".join(damaged_safety_targets)])
		if bool(trial_result.get("nearby_destructible_hit", false)):
			destructible_hit_count += 1
			destructible_notes.append("%s nearby damageable-only destructible was damaged" % label)
		else:
			destructible_notes.append("%s nearby damageable-only destructible was not damaged" % label)
		var global_sweep := bool(trial_result.get("global_sweep_detected", false))
		if detonation_observed and damaged_safety_targets.is_empty() and not global_sweep:
			localized_count += 1
			locality_notes.append("%s explosion damage stayed localized" % label)
		elif global_sweep:
			locality_notes.append("%s global damage sweep detected" % label)
		elif damaged_safety_targets.size() > 0:
			locality_notes.append("%s out-of-range safety targets were damaged" % label)
		else:
			locality_notes.append("%s locality not credited because no detonation was observed" % label)
		if bool(trial_result["player_safe"]):
			player_safe_count += 1
			player_notes.append("%s player safe" % label)
		elif detonation_observed:
			player_notes.append("%s player appears affected by explosion force" % label)
		else:
			player_notes.append("%s player safety not credited because no detonation was observed" % label)
	var nearby_score := _scaled_average_score(total_near_score, trial_results.size(), 10, 5)
	details.append(_detail(
		"Nearby target damage across angles",
		nearby_score,
		5,
		_score_status(nearby_score, 5),
		calibration_prefix + "; nearby target damage averaged across explosion trials: " + "; ".join(near_notes)
	))
	var destructible_score := _scaled_average_score(destructible_hit_count, trial_results.size(), 1, 3)
	details.append(_detail(
		"Nearby destructible damage across angles",
		destructible_score,
		3,
		_score_status(destructible_score, 3),
		"nearby damageable-only destructible damage averaged across explosion trials: " + "; ".join(destructible_notes)
	))
	var locality_score := _scaled_average_score(localized_count, trial_results.size(), 1, 8)
	var locality_note := "blast locality averaged across explosion trials: " + "; ".join(locality_notes)
	if not all_trials_detonated:
		locality_note += "; not all explosion trials detonated"
	if not safety_misses.is_empty():
		locality_note += "; out-of-range safety targets were damaged: " + "; ".join(safety_misses)
	elif all_trials_detonated:
		locality_note += "; all explosion safety trials protected out-of-range targets"
	details.append(_detail(
		"Blast locality across angles",
		locality_score,
		8,
		_score_status(locality_score, 8),
		locality_note
	))
	var player_score := _scaled_average_score(player_safe_count, trial_results.size(), 1, 2)
	details.append(_detail(
		"Player safety across angles",
		player_score,
		2,
		_score_status(player_score, 2),
		"player safety averaged across explosion trials: " + "; ".join(player_notes)
	))
	var calibration_quality_score := _calibration_quality_score(calibration_status)
	var calibration_quality_status := _score_status(calibration_quality_score, 2)
	var calibration_quality_notes := "default throw calibration is full quality inside the 6-12 unit envelope"
	if calibration_status == "borderline":
		calibration_quality_notes = "borderline default throw distance receives 0/2 calibration-quality credit"
	elif calibration_status != "full":
		calibration_quality_notes = "default throw calibration failed or landed outside the accepted envelope"
	details.append(_detail(
		"Throw distance calibration quality",
		calibration_quality_score,
		2,
		calibration_quality_status,
		calibration_quality_notes
	))
	return details


func _explosion_gameplay_score_cap(trial_results: Array[Dictionary]) -> int:
	if trial_results.is_empty():
		return 20
	var global_sweep_count := 0
	for trial_result in trial_results:
		if bool(trial_result.get("global_sweep_detected", false)):
			global_sweep_count += 1
	var global_sweep_threshold := maxi(1, int(ceil(float(trial_results.size()) * 0.5)))
	if global_sweep_count >= global_sweep_threshold:
		return 4
	return 20


func _flag_explosion_suspects(trial_results: Array[Dictionary], sweep_cap_applied: bool) -> void:
	if sweep_cap_applied:
		board.flag_suspect("global damage sweep detected across explosion trials")
	for trial_result in trial_results:
		var damaged_safety_targets: Array = trial_result.get("damaged_safety_targets", [])
		if damaged_safety_targets.size() > 0:
			board.flag_suspect("explosion damaged out-of-range far/side/rear safety targets")
		if bool(trial_result.get("detonation_observed", false)) and not bool(trial_result.get("player_safe", true)):
			board.flag_suspect("player was affected by their own grenade explosion")


func _scaled_average_score(total_score: int, sample_count: int, per_sample_max: int, max_score: int) -> int:
	if sample_count <= 0 or per_sample_max <= 0:
		return 0
	return int(round(float(total_score * max_score) / float(sample_count * per_sample_max)))


func _score_status(score: int, max_score: int) -> String:
	if score >= max_score:
		return "earned"
	if score <= 0:
		return "missed"
	return "partial"


func _score_visual_audio_polish() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 15, "missed", "No player available.")]
		board.add("visual_audio_polish", 0, 15, _detail_notes(details), details)
		return
	await _tap_weapon_switch()
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	await input.wait_physics_frames(2)
	var spawned := SceneProbe.node3d_candidates(SceneProbe.new_nodes_since(arena, before), player.global_position, CALIBRATION_SPAWN_RADIUS)
	var projectile_tracks: Dictionary = await SceneProbe.track_nodes_positions(self, spawned, TRAJECTORY_PROJECTILE_TRACK_FRAMES)
	var projectile_visual: Dictionary = SceneProbe.grenade_projectile_visual_report(
		spawned,
		projectile_tracks,
		CALIBRATION_MIN_TRAVEL_DISTANCE,
		PROJECTILE_VISUAL_MIN_EXTENT,
		PROJECTILE_VISUAL_MAX_EXTENT
	)
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, player.global_position, 30.0, 220)
	var details: Array[Dictionary] = []
	details.append(_score_detail(
		"Thrown grenade model",
		2,
		bool(projectile_visual.get("has_model_visual", false)),
		"moving grenade projectile used a visible non-placeholder model",
		String(projectile_visual.get("notes", "moving grenade projectile model was not validated"))
	))
	var visible_effects := int(activity.get("visible_count", 0))
	details.append(_score_detail(
		"Visible effect nodes",
		1,
		visible_effects > 0,
		"visible grenade or explosion nodes appeared",
		"no visible grenade or explosion nodes appeared"
	))
	details.append(_score_detail(
		"Detonation audio",
		1,
		visible_effects > 0 and bool(activity.get("saw_audio", false)),
		"audio player was active during detonation window",
		"detonation audio not observed during visible detonation window"
	))
	var remaining_new := int(activity.get("remaining_visible_count", 0))
	if visible_effects > 0 and remaining_new < visible_effects:
		details.append(_detail("Temporary node cleanup", 1, 1, "earned", "some temporary nodes cleaned up"))
	elif visible_effects == 0:
		details.append(_detail("Temporary node cleanup", 0, 1, "missed", "no temporary visual nodes were created"))
	else:
		details.append(_detail("Temporary node cleanup", 0, 1, "missed", "temporary visual nodes did not visibly clean up"))
	board.add("visual_audio_polish", _detail_score(details), 15, _detail_notes(details), details)


func _score_main_scene_integration() -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	var main_scene_resource := load("res://main.tscn")
	if main_scene_resource == null or not main_scene_resource is PackedScene:
		details.append(_detail("Main scene loads", 0, 1, "missed", "res://main.tscn could not be loaded"))
		details.append(_detail("Main scene default attacks", 0, 1, "missed", "default attacks not checked because main scene did not load"))
		details.append(_detail("Main scene actors and pickups", 0, 1, "missed", "actors and pickups not checked because main scene did not load"))
		return details

	var main_scene: Node = (main_scene_resource as PackedScene).instantiate()
	main_scene.name = "VerifierMainSceneSmoke"
	root.add_child(main_scene)
	await process_frame
	paused = false
	await input.wait_physics_frames(60)

	var main_player := _find_main_scene_player(main_scene)
	details.append(_score_detail(
		"Main scene loads",
		1,
		main_player != null,
		"main scene loaded with a playable player",
		"main scene loaded but no playable player was found"
	))
	details.append(await _score_main_scene_default_attacks(main_scene, main_player))
	details.append(await _score_main_scene_actors_and_pickups(main_scene, main_player))

	_stop_audio_players_under(main_scene)
	await process_frame
	main_scene.queue_free()
	paused = false
	await process_frame
	await process_frame
	return details


func _score_main_scene_default_attacks(main_scene: Node, main_player: Node) -> Dictionary:
	if main_player == null:
		return _detail("Main scene default attacks", 0, 1, "missed", "default attacks not checked because main scene player was missing")
	if main_player is CharacterBody3D:
		await _wait_for_character_floor(main_player as CharacterBody3D, 90)
	var before_shoot := SceneProbe.collect_instance_ids(main_scene)
	await input.hold("aim", 4)
	await input.tap("attack", 2, 8)
	await input.release("aim", 8)
	var shoot_nodes := SceneProbe.new_nodes_since(main_scene, before_shoot).size()

	await input.wait_physics_frames(20)
	var melee_velocity_before := 0.0
	var melee_position_before := Vector3.ZERO
	if main_player is CharacterBody3D:
		melee_velocity_before = (main_player as CharacterBody3D).velocity.length()
		melee_position_before = (main_player as CharacterBody3D).global_position
	await input.tap("attack", 2, 8)
	await input.wait_physics_frames(12)
	var melee_velocity_after := melee_velocity_before
	var melee_position_delta := 0.0
	if main_player is CharacterBody3D:
		melee_velocity_after = (main_player as CharacterBody3D).velocity.length()
		melee_position_delta = (main_player as CharacterBody3D).global_position.distance_to(melee_position_before)
	var melee_animation_observed := _scene_has_playing_animation(main_scene, "Attack")
	var melee_observed := melee_animation_observed or melee_velocity_after > melee_velocity_before + 0.1 or melee_position_delta > 0.02
	if shoot_nodes > 0 and melee_observed:
		return _detail("Main scene default attacks", 1, 1, "earned", "main scene default shooting and melee both produced runtime behavior")
	return _detail(
		"Main scene default attacks",
		0,
		1,
		"missed",
		"main scene default attack observation was incomplete: shoot_nodes=%d, melee_animation=%s, melee_velocity_delta=%.2f, melee_position_delta=%.2f" % [
			shoot_nodes,
			str(melee_animation_observed),
			melee_velocity_after - melee_velocity_before,
			melee_position_delta,
		]
	)


func _wait_for_character_floor(character: CharacterBody3D, max_frames: int) -> void:
	for _i in range(max_frames):
		if character.is_on_floor():
			return
		await input.wait_physics_frames(1)


func _score_main_scene_actors_and_pickups(main_scene: Node, main_player: Node) -> Dictionary:
	var targetables := _group_nodes_under(main_scene, "targeteables")
	var damageables := _group_nodes_under(main_scene, "damageables")
	var coin_system := main_player != null and main_player.has_method("collect_coin")
	var damage_spawned_pickups := await _damage_main_scene_actor_spawns_runtime_nodes(main_scene, targetables)
	return _score_detail(
		"Main scene actors and pickups",
		1,
		targetables.size() > 0 and damageables.size() > 1 and coin_system and damage_spawned_pickups,
		"main scene kept targeteables, damageables, collect_coin, and damage-spawned pickup behavior",
		"main scene actors, crates, enemies, or coin pickup behavior appeared incomplete"
	)


func _damage_main_scene_actor_spawns_runtime_nodes(main_scene: Node, targetables: Array[Node]) -> bool:
	var target := _preferred_main_scene_damage_target(targetables)
	if target == null or not target.has_method("damage"):
		return false
	var before := SceneProbe.collect_instance_ids(main_scene)
	target.call("damage", Vector3.ZERO, Vector3.UP)
	await input.wait_physics_frames(150)
	return SceneProbe.new_nodes_since(main_scene, before).size() > 0


func _preferred_main_scene_damage_target(targetables: Array[Node]) -> Node:
	for target in targetables:
		if target.has_method("damage") and _node_name_contains(target, "box"):
			return target
	for target in targetables:
		if target.has_method("damage"):
			return target
	return null


func _find_main_scene_player(main_scene: Node) -> Node:
	for node in SceneProbe.flatten(main_scene):
		if node.name == "Player" or (node is CharacterBody3D and node.has_method("collect_coin")):
			return node
	return null


func _group_nodes_under(root_node: Node, group_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_nodes_in_group(group_name):
		if _is_descendant_of(node, root_node):
			result.append(node)
	return result


func _is_descendant_of(node: Node, possible_ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == possible_ancestor:
			return true
		current = current.get_parent()
	return false


func _scene_has_playing_animation(root_node: Node, animation_name: String) -> bool:
	for node in SceneProbe.flatten(root_node):
		if node is AnimationPlayer:
			var animation_player := node as AnimationPlayer
			if animation_player.is_playing() and animation_player.current_animation == animation_name:
				return true
	return false


func _stop_audio_players_under(root_node: Node) -> void:
	for node in SceneProbe.flatten(root_node):
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stop()
		elif node is AudioStreamPlayer2D:
			(node as AudioStreamPlayer2D).stop()
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stop()


func _node_name_contains(node: Node, text: String) -> bool:
	return String(node.name).to_lower().find(text.to_lower()) >= 0


func _score_stability_repeatability() -> void:
	var details: Array[Dictionary] = []
	if player == null:
		details.append(_detail("Repeated grenade attacks", 0, 1, "missed", "No player available."))
		details.append(_detail("Default attack after grenade use", 0, 1, "missed", "No player available."))
	else:
		await _tap_weapon_switch()
		var first_before := SceneProbe.collect_instance_ids(arena)
		await input.tap("attack")
		await input.wait_physics_frames(90)
		var first_nodes := SceneProbe.new_nodes_since(arena, first_before).size()
		await input.wait_physics_frames(60)
		var second_before := SceneProbe.collect_instance_ids(arena)
		await input.tap("attack")
		await input.wait_physics_frames(90)
		var second_nodes := SceneProbe.new_nodes_since(arena, second_before).size()
		details.append(_score_detail(
			"Repeated grenade attacks",
			1,
			first_nodes > 0 and second_nodes > 0,
			"two separated grenade attacks produced runtime behavior",
			"repeated grenade attacks did not both produce runtime behavior"
		))
		await _tap_weapon_switch()
		var default_before := SceneProbe.collect_instance_ids(arena)
		await input.hold("aim", 4)
		await input.tap("attack")
		await input.release("aim")
		var default_nodes := SceneProbe.new_nodes_since(arena, default_before).size()
		details.append(_score_detail(
			"Default attack after grenade use",
			1,
			default_nodes > 0,
			"default aimed attack still works after grenade use",
			"default aimed attack did not produce runtime behavior after grenade use"
		))
	details.append_array(await _score_main_scene_integration())
	board.add("stability_repeatability", _detail_score(details), 5, _detail_notes(details), details)
