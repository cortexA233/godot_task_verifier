extends SceneTree

const ScoreBoard = preload("res://__verifier__/score_board.gd")
const JsonWriter = preload("res://__verifier__/json_writer.gd")
const ArenaBuilder = preload("res://__verifier__/arena_builder.gd")
const InputDriver = preload("res://__verifier__/input_driver.gd")
const SceneProbe = preload("res://__verifier__/scene_probe.gd")

const EXPLOSION_TRIALS := [
	{"label": "Front throw", "heading_y": 0.0},
	{"label": "Left-front throw", "heading_y": -0.65},
	{"label": "Right-front throw", "heading_y": 0.65},
]

const FALLBACK_THROW_DISTANCE := 8.0
const TARGET_FIELD_RADIUS := 30.0
const FAR_TARGET_DISTANCE := 25.0
const NEARBY_TARGET_GROUP_DEGREES := 20
const NEARBY_TARGET_GROUP_COUNT := 18
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

var board
var input
var arena: Node3D
var player: Node3D
var weapon_ui: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(12345)
	board = ScoreBoard.new()
	input = InputDriver.new(self)
	print("Verifier swap input route: ", input.describe_route("swap_weapons"))
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
	JsonWriter.write_result(board.to_dictionary(Engine.get_version_info().get("string", "")))
	quit()


func _build_arena() -> void:
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	arena = ArenaBuilder.create_arena()
	root.add_child(arena)
	player = ArenaBuilder.add_player(arena)
	weapon_ui = ArenaBuilder.add_optional_weapon_ui(arena, player)
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
	var can_switch_weapons: bool = input.can_drive("swap_weapons")
	if InputMap.has_action("swap_weapons"):
		details.append(_detail("Weapon switch input action", 4, 4, "earned", "swap_weapons input exists"))
	elif can_switch_weapons:
		details.append(_detail("Weapon switch input action", 0, 4, "missed", "using Tab key fallback for weapon switching"))
	else:
		details.append(_detail("Weapon switch input action", 0, 4, "missed", "weapon-switch input is missing"))
	if player == null:
		board.add("weapon_controls", _detail_score(details), 15, _detail_notes(details), details)
		return
	var before_switch_attack := SceneProbe.collect_instance_ids(arena)
	await input.tap("swap_weapons")
	await input.tap("attack")
	var switch_attack_nodes := SceneProbe.new_nodes_since(arena, before_switch_attack)
	var grenade_attack_observed := switch_attack_nodes.size() > 0
	details.append(_score_detail(
		"Grenade attack after switching",
		5,
		switch_attack_nodes.size() > 0 and can_switch_weapons,
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
	await input.tap("swap_weapons")
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
		var details: Array[Dictionary] = [_detail("Player availability", 0, 10, "missed", "No player available.")]
		board.add("hud_feedback", 0, 10, _detail_notes(details), details)
		return
	await input.wait_physics_frames(8)
	var before := SceneProbe.control_snapshot(arena)
	await input.tap("swap_weapons")
	var after := SceneProbe.control_snapshot(arena)
	var changed := SceneProbe.count_changed_controls(before, after)
	var details: Array[Dictionary] = []
	var can_switch_weapons: bool = input.can_drive("swap_weapons")
	details.append(_score_detail(
		"Visible UI controls",
		3,
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
		3,
		SceneProbe.count_changed_controls(after, aiming_snapshot) > 0,
		"aiming changes UI feedback",
		"aiming did not change UI feedback"
	))
	board.add("hud_feedback", _detail_score(details), 10, _detail_notes(details), details)


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
		var details: Array[Dictionary] = [_detail("Player availability", 0, 30, "missed", "No player available.")]
		board.add("trajectory_preview", 0, 30, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await _tap_weapon_switch(3, 10)
	await input.wait_physics_frames(8)
	var aiming_aid_nodes := SceneProbe.newly_visible_3d_nodes(arena, before_visible, player.global_position, TRAJECTORY_AID_RADIUS)
	var visible_aid := aiming_aid_nodes.size() > 0
	details.append(_score_detail(
		"Visible grenade aiming aid",
		5,
		visible_aid,
		"visible grenade aiming aid appears in grenade mode",
		"no visible grenade trajectory, landing marker, or equivalent aiming aid detected"
	))
	if not visible_aid:
		details.append(_detail("Communicates arcing throw", 0, 6, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Updates with aim/camera direction", 0, 8, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "trajectory details gated because no visible aiming aid was observed"))
		details.append(_detail("Visibility lifecycle/cooldown behavior", 0, 4, "missed", "trajectory details gated because no visible aiming aid was observed"))
		board.add("trajectory_preview", _detail_score(details), 30, _detail_notes(details), details)
		return

	var first_transforms: Array[Transform3D] = []
	for node in aiming_aid_nodes:
		first_transforms.append(node.global_transform)
	var first_direction := SceneProbe.average_horizontal_direction(aiming_aid_nodes, player.global_position)
	var communicates_arc := SceneProbe.visible_nodes_suggest_arc_or_landing(aiming_aid_nodes, player.global_position)
	details.append(_score_detail(
		"Communicates arcing throw",
		6,
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
		8,
		updates_with_aim,
		"aiming aid updates after aim or camera direction changes",
		"aiming aid did not update after aim or camera direction changed"
	))

	var before_attack := SceneProbe.collect_instance_ids(arena)
	var projectile_direction := await _projectile_direction_after_attack(before_attack)
	var consistency := updates_with_aim and SceneProbe.directions_match(second_direction, projectile_direction, TRAJECTORY_DIRECTION_MIN_DOT)
	if consistency:
		details.append(_detail("Preview matches projectile direction", 7, 7, "earned", "aiming aid direction matches the thrown grenade direction"))
	elif not updates_with_aim:
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "consistency not credited because aiming aid did not update"))
	elif projectile_direction.is_zero_approx():
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "consistency not credited because no measurable grenade projectile direction was observed"))
	else:
		details.append(_detail("Preview matches projectile direction", 0, 7, "missed", "aiming aid direction did not match the thrown grenade direction"))

	await input.wait_physics_frames(12)
	var visible_during_cooldown := _count_visible_nodes(aiming_aid_nodes) > 0
	await _tap_weapon_switch(3, 8)
	await input.wait_physics_frames(8)
	var visible_after_switch := _count_visible_nodes(aiming_aid_nodes)
	var lifecycle_ok := visible_during_cooldown and visible_after_switch < aiming_aid_nodes.size()
	details.append(_score_detail(
		"Visibility lifecycle/cooldown behavior",
		4,
		lifecycle_ok,
		"aiming aid remains available in grenade mode and hides after leaving grenade mode",
		"aiming aid did not show the expected grenade-mode lifecycle"
	))
	board.add("trajectory_preview", _detail_score(details), 30, _detail_notes(details), details)


func _score_projectile_physics() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 15, "missed", "No player available.")]
		board.add("projectile_physics", 0, 15, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	await input.tap("swap_weapons")
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
	for trial in EXPLOSION_TRIALS:
		trial_results.append(await _run_explosion_trial(String(trial["label"]), float(trial["heading_y"]), _target_group_for_heading(float(trial["heading_y"])), calibration))
	var details := _explosion_details_from_trials(trial_results, calibration)
	board.add("explosion_gameplay", _detail_score(details), 20, _detail_notes(details), details)


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


func _run_explosion_trial(trial_label: String, heading_y: float, target_group: String, calibration: Dictionary) -> Dictionary:
	await _build_arena()
	if player == null:
		return {
			"label": trial_label,
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
	var nearby_layout := _add_nearby_damage_targets(arena, target_group)
	var all_nearby_targets: Array = nearby_layout["all"]
	var nearby_targets: Array = nearby_layout["scored"]
	var safety_targets: Array = [
		_add_safety_target(arena, "FarTarget", heading_y, FAR_TARGET_DISTANCE),
		_add_safety_target(arena, "LeftSideTarget", heading_y - PI * 0.5, FAR_TARGET_DISTANCE),
		_add_safety_target(arena, "RightSideTarget", heading_y + PI * 0.5, FAR_TARGET_DISTANCE),
		_add_safety_target(arena, "RearTarget", heading_y + PI, FAR_TARGET_DISTANCE),
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
	var near_score := _nearby_hit_score(nearby_hits)
	var damage_detonation_observed: bool = nearby_hits > 0 or damaged_safety_targets.size() > 0
	var player_safe := damage_detonation_observed and (not player is CharacterBody3D or (player as CharacterBody3D).velocity.length() < 20.0)
	return {
		"label": trial_label,
		"near_score": near_score,
		"nearby_hits": nearby_hits,
		"expected_nearby_hits": expected_nearby_hits,
		"nearby_target_count": nearby_targets.size(),
		"nearby_total_target_count": all_nearby_targets.size(),
		"detonation_observed": damage_detonation_observed,
		"player_safe": player_safe,
		"effects_observed": damage_detonation_observed and int(activity.get("visible_count", 0)) > 0,
		"damaged_safety_targets": damaged_safety_targets,
		"calibration_status": String(calibration.get("status", "failed")),
		"calibration_distance": float(calibration.get("distance", FALLBACK_THROW_DISTANCE)),
		"target_forward_distance": target_forward_distance,
	}


func _add_nearby_damage_targets(root_node: Node3D, target_group: String) -> Dictionary:
	var all_targets: Array = []
	var scored_targets: Array = []
	for group_data in _nearby_damage_target_groups():
		var group := String(group_data["target_group"])
		for radius in NEARBY_DAMAGE_TARGET_RADII:
			var target = ArenaBuilder.add_damage_target(root_node, "NearbyTarget", _polar_target_position(float(group_data["heading_y"]), float(radius)))
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


func _nearby_hit_score(nearby_hits: int) -> int:
	if nearby_hits > 0:
		return 10
	return 0


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
	var player_safe_count := 0
	var effects_count := 0
	var all_trials_detonated := true
	var safety_misses: Array[String] = []
	var near_notes: Array[String] = []
	var player_notes: Array[String] = []
	var effect_notes: Array[String] = []
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
		if bool(trial_result["player_safe"]):
			player_safe_count += 1
			player_notes.append("%s player safe" % label)
		elif detonation_observed:
			player_notes.append("%s player appears affected by explosion force" % label)
		else:
			player_notes.append("%s player safety not credited because no detonation was observed" % label)
		if bool(trial_result["effects_observed"]):
			effects_count += 1
			effect_notes.append("%s detonation produced runtime nodes or effects" % label)
		else:
			effect_notes.append("%s no runtime detonation effects observed" % label)
	var nearby_score := _scaled_average_score(total_near_score, trial_results.size(), 10, 8)
	details.append(_detail(
		"Nearby target damage across angles",
		nearby_score,
		8,
		_score_status(nearby_score, 8),
		calibration_prefix + "; nearby target damage averaged across explosion trials: " + "; ".join(near_notes)
	))
	if all_trials_detonated and safety_misses.is_empty():
		details.append(_detail("Out-of-range safety across angles", 4, 4, "earned", "all explosion safety trials protected out-of-range targets"))
	else:
		var safety_notes: Array[String] = []
		if not all_trials_detonated:
			safety_notes.append("not all explosion trials detonated")
		if not safety_misses.is_empty():
			safety_notes.append("out-of-range safety targets were damaged: " + "; ".join(safety_misses))
		details.append(_detail("Out-of-range safety across angles", 0, 4, "missed", "; ".join(safety_notes)))
	var player_score := _scaled_average_score(player_safe_count, trial_results.size(), 1, 3)
	details.append(_detail(
		"Player safety across angles",
		player_score,
		3,
		_score_status(player_score, 3),
		"player safety averaged across explosion trials: " + "; ".join(player_notes)
	))
	var effects_score := _scaled_average_score(effects_count, trial_results.size(), 1, 3)
	details.append(_detail(
		"Detonation effects across angles",
		effects_score,
		3,
		_score_status(effects_score, 3),
		"detonation effects averaged across explosion trials: " + "; ".join(effect_notes)
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
		var details: Array[Dictionary] = [_detail("Player availability", 0, 5, "missed", "No player available.")]
		board.add("visual_audio_polish", 0, 5, _detail_notes(details), details)
		return
	await input.tap("swap_weapons")
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, player.global_position, 30.0, 220)
	var details: Array[Dictionary] = []
	var visible_effects := int(activity.get("visible_count", 0))
	details.append(_score_detail(
		"Visible effect nodes",
		2,
		visible_effects > 0,
		"visible grenade or explosion nodes appeared",
		"no visible grenade or explosion nodes appeared"
	))
	details.append(_score_detail(
		"Detonation audio",
		2,
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
	board.add("visual_audio_polish", _detail_score(details), 5, _detail_notes(details), details)


func _score_stability_repeatability() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 5, "missed", "No player available.")]
		board.add("stability_repeatability", 0, 5, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	await input.tap("swap_weapons")
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
		3,
		first_nodes > 0 and second_nodes > 0,
		"two separated grenade attacks produced runtime behavior",
		"repeated grenade attacks did not both produce runtime behavior"
	))
	await input.tap("swap_weapons")
	var default_before := SceneProbe.collect_instance_ids(arena)
	await input.hold("aim", 4)
	await input.tap("attack")
	await input.release("aim")
	var default_nodes := SceneProbe.new_nodes_since(arena, default_before).size()
	details.append(_score_detail(
		"Default attack after grenade use",
		2,
		default_nodes > 0,
		"default aimed attack still works after grenade use",
		"default aimed attack did not produce runtime behavior after grenade use"
	))
	board.add("stability_repeatability", _detail_score(details), 5, _detail_notes(details), details)
