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
	return {
		"available": before_image != null and after_image != null,
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
