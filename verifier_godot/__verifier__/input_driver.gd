extends RefCounted

const KEY_FALLBACKS := {
	"swap_weapons": KEY_TAB,
}

var tree: SceneTree


func _init(new_tree: SceneTree) -> void:
	tree = new_tree


func wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await tree.physics_frame


func can_drive(action: String) -> bool:
	return InputMap.has_action(action) or _fallback_keycode(action) != 0


func describe_route(action: String) -> String:
	if InputMap.has_action(action):
		return "%s action" % action
	var keycode := _fallback_keycode(action)
	if keycode != 0:
		return "%s key fallback" % OS.get_keycode_string(keycode)
	return "missing"


func tap(action: String, frames_pressed: int = 2, frames_after: int = 4) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)
		await wait_physics_frames(frames_pressed)
		Input.action_release(action)
		await wait_physics_frames(frames_after)
		return
	var keycode := _fallback_keycode(action)
	if keycode != 0:
		_send_key_event(keycode, true)
		await wait_physics_frames(frames_pressed)
		_send_key_event(keycode, false)
		await wait_physics_frames(frames_after)
		return
	else:
		await wait_physics_frames(frames_after)
		return


func hold(action: String, frames: int) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)
		await wait_physics_frames(frames)
		return
	var keycode := _fallback_keycode(action)
	if keycode != 0:
		_send_key_event(keycode, true)
		await wait_physics_frames(frames)
		return
	else:
		await wait_physics_frames(frames)
		return


func release(action: String, frames_after: int = 2) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)
		await wait_physics_frames(frames_after)
		return
	var keycode := _fallback_keycode(action)
	if keycode != 0:
		_send_key_event(keycode, false)
		await wait_physics_frames(frames_after)
		return
	else:
		await wait_physics_frames(frames_after)
		return


func _fallback_keycode(action: String) -> int:
	return int(KEY_FALLBACKS.get(action, 0))


func _send_key_event(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
