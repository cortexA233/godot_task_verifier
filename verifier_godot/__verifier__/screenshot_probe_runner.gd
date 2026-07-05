extends SceneTree

const InputDriver = preload("res://__verifier__/input_driver.gd")
const ScreenshotVisualProbe = preload("res://__verifier__/screenshot_visual_probe.gd")
const TrajectoryShadowProbe = preload("res://__verifier__/trajectory_shadow_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const VALID_MODES := ["debug-arena", "main-scene", "both", "trajectory-shadow"]
const DEBUG_FOOTPRINT_PARTIAL_AREA := 64
const DEBUG_FOOTPRINT_FULL_AREA := 96
const MAIN_FOOTPRINT_PARTIAL_AREA := 50
const MAIN_FOOTPRINT_STRONG_AREA := 100
const MAIN_FOOTPRINT_FULL_AREA := 200

var input


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	input = InputDriver.new(self)
	var requested_mode := _requested_mode()
	var probe := ScreenshotVisualProbe.new(self, input)
	var mode_results := {}
	if requested_mode == "debug-arena" or requested_mode == "both":
		mode_results["debug_arena"] = await probe.run_debug_arena()
	if requested_mode == "main-scene" or requested_mode == "both":
		mode_results["main_scene"] = await probe.run_main_scene()
	if requested_mode == "trajectory-shadow":
		var trajectory_probe := TrajectoryShadowProbe.new(self, input)
		mode_results["trajectory_shadow"] = await trajectory_probe.run()
	var result := {
		"ok": true,
		"display_driver": DisplayServer.get_name(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"used_for_score": false,
		"requested_mode": requested_mode,
		"auxiliary_score_sections": [_screenshot_visual_score(mode_results)],
		"modes": mode_results,
	}
	_write_result(result)
	quit(0)


func _screenshot_visual_score(mode_results: Dictionary) -> Dictionary:
	var runnable_modes := 0
	var modes_with_projectile := 0
	var modes_with_explosion := 0
	var footprint_score := 0
	var notes: Array[String] = []
	for mode_name in mode_results:
		var mode_result: Dictionary = mode_results[mode_name]
		if not bool(mode_result.get("ok", false)):
			notes.append("%s unavailable: %s" % [String(mode_name), String(mode_result.get("reason", "unknown"))])
			continue
		runnable_modes += 1
		var footprint: Dictionary = mode_result.get("projectile_footprint", {})
		var visible_frames := int(footprint.get("visible_frame_count", 0))
		if visible_frames > 0:
			modes_with_projectile += 1
			notes.append("%s projectile visible in %d captured frame(s)" % [String(mode_name), visible_frames])
			footprint_score += _footprint_quality_score(String(mode_name), footprint, notes)
		if String(mode_result.get("stop_reason", "")) == "explosion_observed":
			modes_with_explosion += 1
			notes.append("%s explosion observed at frame %d" % [String(mode_name), int(mode_result.get("explosion_frame", -1))])
	var score := 0
	if runnable_modes > 0:
		score += 1
	if modes_with_projectile > 0:
		score += 2
	if modes_with_explosion > 0:
		score += 2
	score += footprint_score
	if notes.is_empty():
		notes.append("no rendered screenshot visual evidence was observed")
	notes.append("auxiliary screenshot score is not counted in 100-point score")
	return {
		"name": "screenshot_visual",
		"label": "Screenshot Visual Analysis",
		"score": score,
		"max": 10,
		"used_for_score": false,
		"notes": "; ".join(notes),
		"categories": mode_results.keys(),
	}


func _footprint_quality_score(mode_name: String, footprint: Dictionary, notes: Array[String]) -> int:
	var area := int(footprint.get("max_area_px", 0))
	if mode_name == "debug_arena":
		if area >= DEBUG_FOOTPRINT_FULL_AREA:
			notes.append("debug_arena projectile footprint %dpx earns full debug footprint credit" % area)
			return 2
		if area >= DEBUG_FOOTPRINT_PARTIAL_AREA:
			notes.append("debug_arena projectile footprint %dpx earns partial debug footprint credit" % area)
			return 1
		notes.append("debug_arena projectile footprint too small: %dpx below %dpx minimum" % [area, DEBUG_FOOTPRINT_PARTIAL_AREA])
		return 0
	if mode_name == "main_scene":
		if area >= MAIN_FOOTPRINT_FULL_AREA:
			notes.append("main_scene projectile footprint %dpx earns full main-scene footprint credit" % area)
			return 3
		if area >= MAIN_FOOTPRINT_STRONG_AREA:
			notes.append("main_scene projectile footprint %dpx earns strong main-scene footprint credit" % area)
			return 2
		if area >= MAIN_FOOTPRINT_PARTIAL_AREA:
			notes.append("main_scene projectile footprint %dpx earns partial main-scene footprint credit" % area)
			return 1
		notes.append("main_scene projectile footprint too small: %dpx below %dpx minimum" % [area, MAIN_FOOTPRINT_PARTIAL_AREA])
		return 0
	notes.append("%s projectile footprint quality not scored for unknown visual mode" % mode_name)
	return 0


func _requested_mode() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--probe-mode" and index + 1 < args.size():
			var value := String(args[index + 1])
			if VALID_MODES.has(value):
				return value
	return "both"


func _write_result(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var file := FileAccess.open("%s/result.json" % OUTPUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
