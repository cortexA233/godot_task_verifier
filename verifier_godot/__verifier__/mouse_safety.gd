extends Node

const STARTUP_VISIBLE_FRAMES := 12

var _startup_guard_frames := 0


func _ready() -> void:
	name = "VerifierMouseSafety"
	process_mode = Node.PROCESS_MODE_ALWAYS
	force_visible_for_startup()


func force_visible_for_startup() -> void:
	_startup_guard_frames = STARTUP_VISIBLE_FRAMES
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _process(_delta: float) -> void:
	if _startup_guard_frames <= 0:
		set_process(false)
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_startup_guard_frames -= 1


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var keycode := key_event.physical_keycode
	if keycode == 0:
		keycode = key_event.keycode
	if keycode == KEY_ESCAPE:
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif keycode == KEY_F8:
		_toggle_capture()
		get_viewport().set_input_as_handled()


func _release_mouse() -> void:
	_startup_guard_frames = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(false)


func _toggle_capture() -> void:
	_startup_guard_frames = 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(false)
