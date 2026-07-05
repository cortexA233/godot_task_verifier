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
