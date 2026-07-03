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
const FAR_TARGET_MIN_DISTANCE := 20.0
const FAR_TARGET_EXTRA_DISTANCE := 12.0
const CALIBRATION_FULL_MIN_DISTANCE := 6.0
const CALIBRATION_FULL_MAX_DISTANCE := 12.0
const CALIBRATION_BORDERLINE_MIN_DISTANCE := 4.0
const CALIBRATION_BORDERLINE_MAX_DISTANCE := 14.0
const CALIBRATION_SPAWN_RADIUS := 6.0
const CALIBRATION_TRACK_FRAMES := 180
const CALIBRATION_EFFECT_PROXY_RADIUS := 6.0
const CALIBRATION_MIN_TRAVEL_DISTANCE := 0.75
const PROJECTILE_PLAYER_MIN_DISTANCE := 0.4
const NEARBY_DAMAGE_TARGET_DISTANCES := [6.0, 8.0, 10.0, 12.0]
const NEARBY_DAMAGE_TARGET_SIDE_OFFSETS := [-1.5, 0.0, 1.5]
const NEARBY_EFFECT_OBSERVATION_DISTANCE := 9.0
const NEARBY_EFFECT_OBSERVATION_RADIUS := 10.0

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
		var details: Array[Dictionary] = [_detail("Player availability", 0, 15, "missed", "No player available.")]
		board.add("hud_feedback", 0, 15, _detail_notes(details), details)
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
		4,
		before.size() >= 2,
		"player has visible UI controls",
		"player has little or no visible UI control tree"
	))
	if can_switch_weapons and changed > 0:
		details.append(_detail("Weapon-switch UI state", 7, 7, "earned", "UI control state changed after weapon switch"))
	elif not can_switch_weapons:
		details.append(_detail("Weapon-switch UI state", 0, 7, "missed", "weapon-switch UI change not credited because weapon-switch input is missing"))
	else:
		details.append(_detail("Weapon-switch UI state", 0, 7, "missed", "UI did not visibly change after weapon switch"))
	await input.hold("aim", 8)
	var aiming_snapshot := SceneProbe.control_snapshot(arena)
	await input.release("aim")
	details.append(_score_detail(
		"Aiming UI feedback",
		4,
		SceneProbe.count_changed_controls(after, aiming_snapshot) > 0,
		"aiming changes UI feedback",
		"aiming did not change UI feedback"
	))
	board.add("hud_feedback", _detail_score(details), 15, _detail_notes(details), details)


func _score_trajectory_preview() -> void:
	if player == null:
		var details: Array[Dictionary] = [_detail("Player availability", 0, 20, "missed", "No player available.")]
		board.add("trajectory_preview", 0, 20, _detail_notes(details), details)
		return
	var details: Array[Dictionary] = []
	var before_visible := SceneProbe.visible_3d_node_ids(arena)
	await input.tap("swap_weapons")
	await input.hold("aim", 10)
	var newly_visible := SceneProbe.newly_visible_3d_nodes(arena, before_visible, player.global_position, 25.0)
	details.append(_score_detail(
		"Visible trajectory feedback",
		8,
		newly_visible.size() > 0,
		"new visible 3D aim feedback appears in grenade mode",
		"no new visible 3D trajectory or landing feedback detected"
	))
	var first_transforms: Array[Transform3D] = []
	for node in newly_visible:
		first_transforms.append(node.global_transform)
	_set_explosion_trial_heading(0.45)
	await input.wait_physics_frames(10)
	var moved_feedback := false
	for index in range(newly_visible.size()):
		var node := newly_visible[index]
		if not is_instance_valid(node):
			continue
		var first_transform := first_transforms[index]
		var origin_moved := node.global_transform.origin.distance_to(first_transform.origin) > 0.2
		var basis_moved := node.global_transform.basis.get_euler().distance_to(first_transform.basis.get_euler()) > 0.05
		if origin_moved or basis_moved:
			moved_feedback = true
	details.append(_score_detail(
		"Trajectory reacts to aim",
		7,
		moved_feedback,
		"aim feedback moves after aim direction changes",
		"aim feedback did not visibly move after aim direction changes"
	))
	await input.release("aim")
	await input.tap("swap_weapons")
	await input.wait_physics_frames(8)
	var still_visible := 0
	for node in newly_visible:
		if is_instance_valid(node) and node.visible:
			still_visible += 1
	if newly_visible.size() > 0 and still_visible < newly_visible.size():
		details.append(_detail("Trajectory hides outside grenade mode", 5, 5, "earned", "some trajectory feedback hides outside grenade mode"))
	elif newly_visible.size() == 0:
		details.append(_detail("Trajectory hides outside grenade mode", 0, 5, "missed", "no trajectory feedback existed to hide"))
	else:
		details.append(_detail("Trajectory hides outside grenade mode", 0, 5, "missed", "trajectory feedback remains visible outside grenade mode"))
	board.add("trajectory_preview", _detail_score(details), 20, _detail_notes(details), details)


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
		trial_results.append(await _run_explosion_trial(String(trial["label"]), float(trial["heading_y"]), calibration))
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


func _far_forward_distance(target_forward_distance: float) -> float:
	return maxf(FAR_TARGET_MIN_DISTANCE, target_forward_distance + FAR_TARGET_EXTRA_DISTANCE)


func _run_explosion_trial(trial_label: String, heading_y: float, calibration: Dictionary) -> Dictionary:
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
	var basis := Basis.from_euler(Vector3(0, heading_y, 0))
	var forward := (basis * Vector3.FORWARD).normalized()
	var right := (basis * Vector3.RIGHT).normalized()
	var target_forward_distance := _target_forward_distance(calibration)
	var far_forward_distance := _far_forward_distance(target_forward_distance)
	var nearby_targets := _add_nearby_damage_targets(arena, forward, right)
	var safety_targets: Array = [
		ArenaBuilder.add_damage_target(arena, "FarTarget", _explosion_target_position(forward, right, far_forward_distance, 0.0)),
		ArenaBuilder.add_damage_target(arena, "LeftSideTarget", _explosion_target_position(forward, right, target_forward_distance, -7.0)),
		ArenaBuilder.add_damage_target(arena, "RightSideTarget", _explosion_target_position(forward, right, target_forward_distance, 8.5)),
		ArenaBuilder.add_damage_target(arena, "RearTarget", _explosion_target_position(forward, right, -6.0, 0.0)),
	]
	await input.wait_physics_frames(4)
	await _tap_weapon_switch(3, 10)
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	var effect_origin := _explosion_target_position(forward, right, NEARBY_EFFECT_OBSERVATION_DISTANCE, 0.0)
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, effect_origin, NEARBY_EFFECT_OBSERVATION_RADIUS, 180)
	var damaged_safety_targets: Array[String] = []
	for safety_target in safety_targets:
		if safety_target.damage_calls > 0:
			damaged_safety_targets.append(String(safety_target.name))
	var nearby_hits := _count_damaged_targets(nearby_targets)
	var near_score := _nearby_hit_score(nearby_hits)
	var damage_detonation_observed: bool = nearby_hits > 0 or damaged_safety_targets.size() > 0
	var player_safe := damage_detonation_observed and (not player is CharacterBody3D or (player as CharacterBody3D).velocity.length() < 20.0)
	return {
		"label": trial_label,
		"near_score": near_score,
		"nearby_hits": nearby_hits,
		"nearby_target_count": nearby_targets.size(),
		"detonation_observed": damage_detonation_observed,
		"player_safe": player_safe,
		"effects_observed": damage_detonation_observed and int(activity.get("visible_count", 0)) > 0,
		"damaged_safety_targets": damaged_safety_targets,
		"calibration_status": String(calibration.get("status", "failed")),
		"calibration_distance": float(calibration.get("distance", FALLBACK_THROW_DISTANCE)),
	}


func _add_nearby_damage_targets(root_node: Node3D, forward: Vector3, right: Vector3) -> Array:
	var targets: Array = []
	for distance in NEARBY_DAMAGE_TARGET_DISTANCES:
		for side_offset in NEARBY_DAMAGE_TARGET_SIDE_OFFSETS:
			var target = ArenaBuilder.add_damage_target(root_node, "NearbyTarget", _explosion_target_position(forward, right, float(distance), float(side_offset)))
			target.name = "NearbyTarget_%02d_%s" % [int(distance), _nearby_side_label(float(side_offset))]
			targets.append(target)
	return targets


func _nearby_side_label(side_offset: float) -> String:
	if side_offset < 0.0:
		return "L"
	if side_offset > 0.0:
		return "R"
	return "C"


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


func _explosion_target_position(forward: Vector3, right: Vector3, forward_distance: float, right_offset: float) -> Vector3:
	return forward * forward_distance + right * right_offset + Vector3.UP * 0.5


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
		near_notes.append("%s %d/10" % [label, near_score])
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
	var nearby_score := _scaled_average_score(total_near_score, trial_results.size(), 10, 10)
	details.append(_detail(
		"Nearby target damage across angles",
		nearby_score,
		10,
		_score_status(nearby_score, 10),
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
		var details: Array[Dictionary] = [_detail("Player availability", 0, 10, "missed", "No player available.")]
		board.add("visual_audio_polish", 0, 10, _detail_notes(details), details)
		return
	await input.tap("swap_weapons")
	var before := SceneProbe.collect_instance_ids(arena)
	await input.tap("attack")
	var activity: Dictionary = await SceneProbe.observe_runtime_activity(self, arena, before, player.global_position, 30.0, 220)
	var details: Array[Dictionary] = []
	var visible_effects := int(activity.get("visible_count", 0))
	details.append(_score_detail(
		"Visible effect nodes",
		4,
		visible_effects > 0,
		"visible grenade or explosion nodes appeared",
		"no visible grenade or explosion nodes appeared"
	))
	details.append(_score_detail(
		"Detonation audio",
		3,
		visible_effects > 0 and bool(activity.get("saw_audio", false)),
		"audio player was active during detonation window",
		"no active audio player detected during detonation window"
	))
	var remaining_new := int(activity.get("remaining_visible_count", 0))
	if visible_effects > 0 and remaining_new < visible_effects:
		details.append(_detail("Temporary node cleanup", 3, 3, "earned", "some temporary nodes cleaned up"))
	elif visible_effects == 0:
		details.append(_detail("Temporary node cleanup", 0, 3, "missed", "no temporary visual nodes were created"))
	else:
		details.append(_detail("Temporary node cleanup", 0, 3, "missed", "temporary nodes did not clean up during observation window"))
	board.add("visual_audio_polish", _detail_score(details), 10, _detail_notes(details), details)


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
