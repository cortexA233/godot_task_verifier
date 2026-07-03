extends SceneTree

const DEBUG_SCENE := preload("res://__verifier__/debug_arena.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := DEBUG_SCENE.instantiate()
	root.add_child(scene)
	for _i in range(10):
		await physics_frame
	var required := [
		"VerifierPlayer",
		"NearTargetA",
		"NearTargetB",
		"FarTarget",
		"LeftSideTarget",
		"RightSideTarget",
		"RearTarget",
	]
	var missing: Array[String] = []
	for node_name in required:
		if _find_by_name(scene, node_name) == null:
			missing.append(node_name)
	if missing.size() > 0:
		push_error("Verifier debug arena smoke check missing nodes: " + ", ".join(missing))
		quit(1)
		return
	print("Verifier debug arena smoke check passed.")
	quit()


func _find_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, node_name)
		if found != null:
			return found
	return null
