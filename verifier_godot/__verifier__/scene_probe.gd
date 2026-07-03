extends RefCounted


static func collect_instance_ids(root: Node) -> Dictionary:
	var ids := {}
	for node in flatten(root):
		ids[node.get_instance_id()] = true
	return ids


static func new_nodes_since(root: Node, before: Dictionary) -> Array[Node]:
	var nodes: Array[Node] = []
	for node in flatten(root):
		if not before.has(node.get_instance_id()):
			nodes.append(node)
	return nodes


static func flatten(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child in root.get_children():
		result.append_array(flatten(child))
	return result


static func visible_3d_nodes_near(root: Node, point: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in flatten(root):
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.visible and node_3d.global_position.distance_to(point) <= radius:
				found.append(node_3d)
	return found


static func audio_players_playing(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node in flatten(root):
		if node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
			found.append(node)
		elif node is AudioStreamPlayer2D and (node as AudioStreamPlayer2D).playing:
			found.append(node)
		elif node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
			found.append(node)
	return found


static func observe_runtime_activity(tree: SceneTree, root: Node, before: Dictionary, point: Vector3, radius: float, frame_count: int) -> Dictionary:
	var visible_ids := {}
	var saw_audio := false
	for _i in range(frame_count):
		for node in new_nodes_since(root, before):
			if node is Node3D:
				var node_3d := node as Node3D
				if node_3d.visible and node_3d.global_position.distance_to(point) <= radius:
					visible_ids[node_3d.get_instance_id()] = true
		if audio_players_playing(root).size() > 0:
			saw_audio = true
		await tree.physics_frame
	var remaining_visible_count := 0
	for node in flatten(root):
		if visible_ids.has(node.get_instance_id()):
			remaining_visible_count += 1
	return {
		"visible_count": visible_ids.size(),
		"remaining_visible_count": remaining_visible_count,
		"saw_audio": saw_audio,
	}


static func control_snapshot(root: Node) -> Dictionary:
	var snapshot := {}
	for node in flatten(root):
		if node is Control:
			var control := node as Control
			snapshot[str(control.get_path())] = {
				"visible": control.visible,
				"modulate": control.modulate,
				"position": control.position,
				"size": control.size,
			}
	return snapshot


static func count_changed_controls(before: Dictionary, after: Dictionary) -> int:
	var changed := 0
	for path in after.keys():
		if before.has(path) and before[path] != after[path]:
			changed += 1
	return changed


static func visible_3d_node_ids(root: Node) -> Dictionary:
	var ids := {}
	for node in flatten(root):
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.visible:
				ids[node_3d.get_instance_id()] = true
	return ids


static func newly_visible_3d_nodes(root: Node, before: Dictionary, point: Vector3, radius: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in flatten(root):
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.visible and not before.has(node_3d.get_instance_id()) and node_3d.global_position.distance_to(point) <= radius:
				result.append(node_3d)
	return result


static func node3d_candidates(nodes: Array[Node], origin: Vector3, max_distance: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in nodes:
		if node is Node3D:
			var node_3d := node as Node3D
			if node_3d.global_position.distance_to(origin) <= max_distance:
				result.append(node_3d)
	return result


static func track_node_positions(tree: SceneTree, node: Node3D, frame_count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for _i in range(frame_count):
		if not is_instance_valid(node):
			break
		points.append(node.global_position)
		await tree.physics_frame
	return points


static func track_nodes_positions(tree: SceneTree, nodes: Array[Node3D], frame_count: int) -> Dictionary:
	var tracks := {}
	for node in nodes:
		if is_instance_valid(node):
			tracks[node.get_instance_id()] = []
	for _i in range(frame_count):
		for node in nodes:
			if not is_instance_valid(node):
				continue
			var id := node.get_instance_id()
			if not tracks.has(id):
				tracks[id] = []
			var points: Array = tracks[id]
			points.append(node.global_position)
		await tree.physics_frame
	return tracks


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


static func horizontal_travel_distance(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	return horizontal_distance(points[0], points[points.size() - 1])


static func path_is_player_safe(points: Array, player_position: Vector3, minimum_distance: float) -> bool:
	for point in points:
		if point.distance_to(player_position) < minimum_distance:
			return false
	return true


static func calibration_path_is_usable(points: Array, player_position: Vector3, minimum_distance: float, minimum_travel_distance: float) -> bool:
	if points.size() < 2:
		return false
	if not path_is_player_safe(points, player_position, minimum_distance):
		return false
	return horizontal_travel_distance(points) >= minimum_travel_distance


static func has_arc_motion(points: Array) -> bool:
	if points.size() < 6:
		return false
	var max_y: float = points[0].y
	for point in points:
		max_y = maxf(max_y, point.y)
	var start_y: float = points[0].y
	var end_y: float = points[points.size() - 1].y
	var start_xz := Vector2(points[0].x, points[0].z)
	var end_xz := Vector2(points[points.size() - 1].x, points[points.size() - 1].z)
	var horizontal_distance: float = start_xz.distance_to(end_xz)
	return max_y > start_y + 0.15 and end_y < max_y - 0.1 and horizontal_distance > 0.5
