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
const RENDER_SETTLE_FRAMES := 2
const PREVIEW_SETTLE_FRAMES := 8
const DEBUG_ARENA_READY_FRAMES := 540
const SIDE_CAMERA_DISTANCE := 13.0
const SIDE_CAMERA_HEIGHT := 5.0
const SIDE_CAMERA_BACK_OFFSET := 1.5
const SIDE_CAMERA_LOOKAHEAD := 8.5
const SIDE_CAMERA_LOOK_HEIGHT := 1.7
const GAMEPLAY_BASELINE_LABEL := "gameplay_baseline"
const SIDE_BASELINE_LABEL := "side_baseline"
const GAMEPLAY_PREVIEW_LABEL := "gameplay_preview"
const SIDE_PREVIEW_LABEL := "side_preview"
const SIDE_EARLY_FLIGHT_LABEL := "side_early_flight"
const PROJECTILE_SPAWN_RADIUS := 6.0
const EARLY_FLIGHT_CAPTURE_FRAMES := 8
const RUNTIME_TRACK_FRAMES := 42
const MIN_RUNTIME_TRAVEL_DISTANCE := 0.5
const GAMEPLAY_CENTROID_SPREAD_HEALTHY_PX := 80.0

var tree: SceneTree
var input
var root: Window


func _init(p_tree: SceneTree, p_input) -> void:
	tree = p_tree
	input = p_input
	root = tree.root


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
	var gameplay_baseline := await _capture_image("%s_%s" % [heading_label, GAMEPLAY_BASELINE_LABEL], root)
	side_camera.current = true
	var side_baseline := await _capture_image("%s_%s" % [heading_label, SIDE_BASELINE_LABEL], root)

	await input.tap(_weapon_switch_action(), 3, 12)
	await input.wait_physics_frames(PREVIEW_SETTLE_FRAMES)

	gameplay_camera.current = true
	var gameplay_preview := await _capture_image("%s_%s" % [heading_label, GAMEPLAY_PREVIEW_LABEL], root)
	side_camera.current = true
	var side_preview := await _capture_image("%s_%s" % [heading_label, SIDE_PREVIEW_LABEL], root)

	var gameplay_mask := _baseline_diff_metrics(gameplay_baseline.get("image", null), gameplay_preview.get("image", null), GAMEPLAY_ANALYSIS_REGION, GAMEPLAY_PREVIEW_LABEL)
	var side_mask := _baseline_diff_metrics(side_baseline.get("image", null), side_preview.get("image", null), SIDE_ANALYSIS_REGION, SIDE_PREVIEW_LABEL)
	var captures: Array[Dictionary] = [
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
	var side_early_flight := await _capture_image("%s_%s" % [heading_label, SIDE_EARLY_FLIGHT_LABEL], root)
	captures.append(side_early_flight.get("record", {}))
	var side_early_flight_mask := _baseline_diff_metrics(side_baseline.get("image", null), side_early_flight.get("image", null), SIDE_ANALYSIS_REGION, SIDE_EARLY_FLIGHT_LABEL)
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
		"side_early_flight_mask": _unavailable_diff_metrics(SIDE_ANALYSIS_REGION, SIDE_EARLY_FLIGHT_LABEL, reason),
		"provisional_verdict": "missing",
		"reason": reason,
	}


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


func _weapon_switch_action() -> String:
	if InputMap.has_action("swap_weapons"):
		return "swap_weapons"
	if InputMap.has_action("weapon_switch"):
		return "weapon_switch"
	return "swap_weapons"


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


func _overall_verdict(summary: Dictionary) -> String:
	if int(summary.get("healthy_heading_count", 0)) >= 2:
		return "healthy"
	if int(summary.get("suspect_heading_count", 0)) > 0 or int(summary.get("heading_count", 0)) > 0:
		return "suspect"
	return "missing"


func _thresholds() -> Dictionary:
	return {
		"pixel_diff_threshold": PIXEL_DIFF_THRESHOLD,
		"diff_scan_step": DIFF_SCAN_STEP,
		"min_gameplay_changed_pixels": MIN_GAMEPLAY_CHANGED_PIXELS,
		"min_side_changed_pixels": MIN_SIDE_CHANGED_PIXELS,
		"min_arc_width_px": MIN_ARC_WIDTH_PX,
		"min_arc_height_px": MIN_ARC_HEIGHT_PX,
		"runtime_direction_min_dot": RUNTIME_DIRECTION_MIN_DOT,
		"render_settle_frames": RENDER_SETTLE_FRAMES,
		"preview_settle_frames": PREVIEW_SETTLE_FRAMES,
		"debug_arena_ready_frames": DEBUG_ARENA_READY_FRAMES,
		"side_camera_distance": SIDE_CAMERA_DISTANCE,
		"side_camera_height": SIDE_CAMERA_HEIGHT,
		"side_camera_back_offset": SIDE_CAMERA_BACK_OFFSET,
		"side_camera_lookahead": SIDE_CAMERA_LOOKAHEAD,
		"side_camera_look_height": SIDE_CAMERA_LOOK_HEIGHT,
		"projectile_spawn_radius": PROJECTILE_SPAWN_RADIUS,
		"early_flight_capture_frames": EARLY_FLIGHT_CAPTURE_FRAMES,
		"runtime_track_frames": RUNTIME_TRACK_FRAMES,
		"min_runtime_travel_distance": MIN_RUNTIME_TRAVEL_DISTANCE,
		"gameplay_centroid_spread_healthy_px": GAMEPLAY_CENTROID_SPREAD_HEALTHY_PX,
	}


func _prepare_output_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
