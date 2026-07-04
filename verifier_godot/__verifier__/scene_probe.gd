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


static func viewport_screenshot_signature(viewport: Viewport, sample_step: int = 32) -> Dictionary:
	var capture := _capture_viewport_screenshot(viewport)
	if not bool(capture.get("available", false)):
		return capture
	var image: Image = capture["image"]
	var width := image.get_width()
	var height := image.get_height()
	var safe_sample_step := maxi(sample_step, 1)
	var samples: Array = []
	for y in range(0, height, safe_sample_step):
		for x in range(0, width, safe_sample_step):
			var color := image.get_pixel(x, y)
			samples.append([color.r, color.g, color.b, color.a])
	return {
		"available": true,
		"display_driver": DisplayServer.get_name(),
		"width": width,
		"height": height,
		"sample_step": safe_sample_step,
		"sample_count": samples.size(),
		"samples": samples,
	}


static func viewport_image(viewport: Viewport) -> Dictionary:
	var capture := _capture_viewport_screenshot(viewport)
	if not bool(capture.get("available", false)):
		return capture
	return capture


static func viewport_region_signature(viewport: Viewport, rect: Rect2, sample_step: int = 8) -> Dictionary:
	var capture := viewport_image(viewport)
	if not bool(capture.get("available", false)):
		return capture
	var image: Image = capture["image"]
	var signature := image_region_signature(image, rect, sample_step)
	if bool(signature.get("available", false)):
		signature["display_driver"] = DisplayServer.get_name()
	return signature


static func image_region_signature(image: Image, rect: Rect2, sample_step: int = 8) -> Dictionary:
	if image == null:
		return {"available": false, "reason": "image is null"}
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return {
			"available": false,
			"reason": "image has no pixels",
			"width": width,
			"height": height,
		}
	var x0 := clampi(int(floorf(rect.position.x)), 0, maxi(width - 1, 0))
	var y0 := clampi(int(floorf(rect.position.y)), 0, maxi(height - 1, 0))
	var x1 := clampi(int(ceilf(rect.position.x + rect.size.x)), x0 + 1, width)
	var y1 := clampi(int(ceilf(rect.position.y + rect.size.y)), y0 + 1, height)
	var safe_sample_step := maxi(sample_step, 1)
	var samples: Array = []
	for y in range(y0, y1, safe_sample_step):
		for x in range(x0, x1, safe_sample_step):
			var color := image.get_pixel(x, y)
			samples.append([color.r, color.g, color.b, color.a])
	return {
		"available": true,
		"width": width,
		"height": height,
		"region": [x0, y0, x1 - x0, y1 - y0],
		"sample_step": safe_sample_step,
		"sample_count": samples.size(),
		"samples": samples,
	}


static func frame_signature_delta(before: Dictionary, after: Dictionary) -> float:
	if not bool(before.get("available", false)) or not bool(after.get("available", false)):
		return -1.0
	var before_samples: Array = before.get("samples", [])
	var after_samples: Array = after.get("samples", [])
	var count := mini(before_samples.size(), after_samples.size())
	if count <= 0:
		return 0.0
	var total := 0.0
	for index in range(count):
		var before_color: Array = before_samples[index]
		var after_color: Array = after_samples[index]
		for channel in range(4):
			total += absf(float(after_color[channel]) - float(before_color[channel]))
	return total / float(count * 4)


static func save_viewport_screenshot(viewport: Viewport, output_path: String) -> Dictionary:
	var capture := _capture_viewport_screenshot(viewport)
	if not bool(capture.get("available", false)):
		capture.erase("image")
		capture["saved"] = false
		capture["path"] = output_path
		return capture
	var image: Image = capture["image"]
	var error := image.save_png(output_path)
	return {
		"available": true,
		"saved": error == OK,
		"path": output_path,
		"error": error,
		"display_driver": DisplayServer.get_name(),
		"width": image.get_width(),
		"height": image.get_height(),
	}


static func _capture_viewport_screenshot(viewport: Viewport) -> Dictionary:
	if viewport == null:
		return {"available": false, "reason": "viewport is null"}
	if DisplayServer.get_name() == "headless":
		return {
			"available": false,
			"reason": "headless display driver does not expose viewport screenshots",
			"display_driver": DisplayServer.get_name(),
		}
	var texture := viewport.get_texture()
	if texture == null:
		return {
			"available": false,
			"reason": "viewport texture is null",
			"display_driver": DisplayServer.get_name(),
		}
	var image := texture.get_image()
	if image == null:
		return {
			"available": false,
			"reason": "viewport image is null",
			"display_driver": DisplayServer.get_name(),
		}
	if image.get_width() <= 0 or image.get_height() <= 0:
		return {
			"available": false,
			"reason": "viewport image has no pixels",
			"display_driver": DisplayServer.get_name(),
			"width": image.get_width(),
			"height": image.get_height(),
		}
	return {
		"available": true,
		"display_driver": DisplayServer.get_name(),
		"width": image.get_width(),
		"height": image.get_height(),
		"image": image,
	}


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


static func visible_mesh_instances_under(root_node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in flatten(root_node):
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null and _mesh_instance_is_visible(mesh_instance):
				result.append(mesh_instance)
	return result


static func projectile_screen_rect(camera: Camera3D, projectile: Node3D, viewport_size: Vector2i) -> Dictionary:
	if camera == null:
		return {"available": false, "visible": false, "reason": "camera unavailable"}
	if projectile == null or not is_instance_valid(projectile):
		return {"available": false, "visible": false, "reason": "projectile unavailable"}
	var points: Array[Vector2] = []
	for mesh_instance in visible_mesh_instances_under(projectile):
		var aabb := mesh_instance.get_aabb()
		for x in [aabb.position.x, aabb.position.x + aabb.size.x]:
			for y in [aabb.position.y, aabb.position.y + aabb.size.y]:
				for z in [aabb.position.z, aabb.position.z + aabb.size.z]:
					var world_point := mesh_instance.global_transform * Vector3(x, y, z)
					if not camera.is_position_behind(world_point):
						points.append(camera.unproject_position(world_point))
	if points.is_empty():
		if camera.is_position_behind(projectile.global_position):
			return {"available": true, "visible": false, "reason": "projectile is behind camera"}
		var center := camera.unproject_position(projectile.global_position)
		points = [center - Vector2(6, 6), center + Vector2(6, 6)]
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	min_x = clampf(floorf(min_x) - 2.0, 0.0, float(viewport_size.x))
	min_y = clampf(floorf(min_y) - 2.0, 0.0, float(viewport_size.y))
	max_x = clampf(ceilf(max_x) + 2.0, 0.0, float(viewport_size.x))
	max_y = clampf(ceilf(max_y) + 2.0, 0.0, float(viewport_size.y))
	var rect_width := maxf(0.0, max_x - min_x)
	var rect_height := maxf(0.0, max_y - min_y)
	return {
		"available": true,
		"visible": rect_width > 0.0 and rect_height > 0.0,
		"x": int(min_x),
		"y": int(min_y),
		"width": int(rect_width),
		"height": int(rect_height),
		"area_px": int(rect_width * rect_height),
	}


static func grenade_projectile_visual_report(
	candidates: Array[Node3D],
	tracks: Dictionary,
	minimum_travel_distance: float = 0.5,
	min_visual_extent: float = 0.1,
	max_visual_extent: float = 2.0
) -> Dictionary:
	var moving_projectile_count := 0
	var mesh_count := 0
	var accepted_count := 0
	var placeholder_count := 0
	var reused_asset_count := 0
	var bad_size_count := 0
	var inspected_notes: Array[String] = []
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var points: Array = tracks.get(candidate.get_instance_id(), [])
		if horizontal_travel_distance(points) < minimum_travel_distance:
			continue
		moving_projectile_count += 1
		for mesh_instance in visible_mesh_instances_under(candidate):
			mesh_count += 1
			var mesh := mesh_instance.mesh
			var mesh_class := mesh.get_class()
			var max_extent := _mesh_max_world_extent(mesh_instance)
			if _mesh_is_placeholder_primitive(mesh):
				placeholder_count += 1
				inspected_notes.append("%s uses placeholder primitive %s" % [str(mesh_instance.get_path()), mesh_class])
				continue
			if _mesh_uses_reused_projectile_asset(mesh_instance):
				reused_asset_count += 1
				inspected_notes.append("%s appears to reuse non-grenade asset %s" % [str(mesh_instance.get_path()), _mesh_resource_path(mesh_instance)])
				continue
			if max_extent < min_visual_extent or max_extent > max_visual_extent:
				bad_size_count += 1
				inspected_notes.append("%s has model extent %.2f outside %.2f-%.2f" % [str(mesh_instance.get_path()), max_extent, min_visual_extent, max_visual_extent])
				continue
			accepted_count += 1
			inspected_notes.append("%s has non-placeholder projectile mesh %s, extent %.2f" % [str(mesh_instance.get_path()), mesh_class, max_extent])
	var notes := ""
	if accepted_count > 0:
		notes = "moving grenade projectile carries a visible non-placeholder model"
	elif moving_projectile_count <= 0:
		notes = "no moving projectile candidates were available for model inspection"
	elif mesh_count <= 0:
		notes = "moving projectile had no visible MeshInstance3D child"
	elif placeholder_count > 0:
		notes = "moving projectile visual used placeholder primitive mesh"
	elif reused_asset_count > 0:
		notes = "moving projectile visual appeared to reuse a non-grenade asset"
	else:
		notes = "moving projectile visual was not grenade-sized or model-like"
	if not inspected_notes.is_empty():
		notes += ": " + "; ".join(inspected_notes.slice(0, 3))
	return {
		"has_model_visual": accepted_count > 0,
		"moving_projectile_count": moving_projectile_count,
		"visible_mesh_count": mesh_count,
		"accepted_mesh_count": accepted_count,
		"placeholder_mesh_count": placeholder_count,
		"reused_asset_count": reused_asset_count,
		"bad_size_count": bad_size_count,
		"notes": notes,
	}


static func _mesh_instance_is_visible(mesh_instance: MeshInstance3D) -> bool:
	if not mesh_instance.visible:
		return false
	if mesh_instance.is_inside_tree():
		return mesh_instance.is_visible_in_tree()
	return true


static func _mesh_max_world_extent(mesh_instance: MeshInstance3D) -> float:
	var aabb := mesh_instance.get_aabb()
	var scale := mesh_instance.global_transform.basis.get_scale()
	var size := Vector3(
		absf(aabb.size.x * scale.x),
		absf(aabb.size.y * scale.y),
		absf(aabb.size.z * scale.z)
	)
	return maxf(size.x, maxf(size.y, size.z))


static func _mesh_resource_path(mesh_instance: MeshInstance3D) -> String:
	if mesh_instance.mesh == null:
		return ""
	return String(mesh_instance.mesh.resource_path)


static func _mesh_context_text(mesh_instance: MeshInstance3D) -> String:
	var parts: Array[String] = [String(mesh_instance.name), _mesh_resource_path(mesh_instance)]
	var current: Node = mesh_instance.get_parent()
	while current != null:
		parts.append(String(current.name))
		current = current.get_parent()
	return " ".join(parts).to_lower()


static func _mesh_is_placeholder_primitive(mesh: Mesh) -> bool:
	return (
		mesh is BoxMesh
		or mesh is SphereMesh
		or mesh is CapsuleMesh
		or mesh is CylinderMesh
		or mesh is PlaneMesh
		or mesh is PrismMesh
		or mesh is QuadMesh
		or mesh is TorusMesh
	)


static func _mesh_uses_reused_projectile_asset(mesh_instance: MeshInstance3D) -> bool:
	var text := _mesh_context_text(mesh_instance)
	var rejected_tokens := [
		"bullet",
		"coin",
		"box",
		"crate",
		"gdbot",
		"player/model",
		"trajectory",
		"target",
		"reticle",
		"explosion",
		"smoke",
	]
	for token in rejected_tokens:
		if text.find(token) >= 0:
			return true
	return false


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


static func horizontal_direction(a: Vector3, b: Vector3) -> Vector2:
	var delta := Vector2(b.x - a.x, b.z - a.z)
	if delta.length() <= 0.001:
		return Vector2.ZERO
	return delta.normalized()


static func track_horizontal_direction(points: Array, minimum_distance: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var start: Vector3 = points[0]
	for index in range(points.size() - 1, 0, -1):
		var point: Vector3 = points[index]
		if horizontal_distance(start, point) >= minimum_distance:
			return horizontal_direction(start, point)
	return Vector2.ZERO


static func average_horizontal_direction(nodes: Array[Node3D], origin: Vector3) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var position_direction := horizontal_direction(origin, node.global_position)
		if not position_direction.is_zero_approx():
			total += position_direction
			count += 1
			continue
		var forward_3d := (node.global_transform.basis * Vector3.FORWARD).normalized()
		var forward_2d := Vector2(forward_3d.x, forward_3d.z)
		if forward_2d.length() > 0.001:
			total += forward_2d.normalized()
			count += 1
	if count <= 0 or total.length() <= 0.001:
		return Vector2.ZERO
	return total.normalized()


static func directions_match(a: Vector2, b: Vector2, minimum_dot: float) -> bool:
	if a.length() <= 0.001 or b.length() <= 0.001:
		return false
	return a.normalized().dot(b.normalized()) >= minimum_dot


static func visible_nodes_suggest_arc_or_landing(nodes: Array[Node3D], origin: Vector3) -> bool:
	if nodes.is_empty():
		return false
	var min_distance := INF
	var max_distance := 0.0
	var min_y := INF
	var max_y := -INF
	var far_ground_marker := false
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var distance := horizontal_distance(origin, node.global_position)
		min_distance = minf(min_distance, distance)
		max_distance = maxf(max_distance, distance)
		min_y = minf(min_y, node.global_position.y)
		max_y = maxf(max_y, node.global_position.y)
		if distance >= 4.0 and absf(node.global_position.y - origin.y) <= 1.0:
			far_ground_marker = true
	var horizontal_span := max_distance - min_distance
	var vertical_span := max_y - min_y
	return far_ground_marker or (horizontal_span >= 2.0 and vertical_span >= 0.2)


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
