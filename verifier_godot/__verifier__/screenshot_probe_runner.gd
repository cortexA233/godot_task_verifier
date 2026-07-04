extends SceneTree

const InputDriver = preload("res://__verifier__/input_driver.gd")
const ScreenshotVisualProbe = preload("res://__verifier__/screenshot_visual_probe.gd")

const OUTPUT_DIR := "res://__screenshot_probe__"
const VALID_MODES := ["debug-arena", "main-scene", "both"]

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
	var result := {
		"ok": true,
		"display_driver": DisplayServer.get_name(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"used_for_score": false,
		"requested_mode": requested_mode,
		"modes": mode_results,
	}
	_write_result(result)
	quit(0)


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
