extends RefCounted

const DamageTarget = preload("res://__verifier__/verifier_damage_target.gd")


static func create_arena() -> Node3D:
	var root := Node3D.new()
	root.name = "VerifierArena"
	root.add_child(_create_ground())
	return root


static func add_player(root: Node3D) -> Node3D:
	var player_scene := load("res://player/player.tscn")
	if player_scene == null:
		return null
	var player: Node = player_scene.instantiate()
	if not player is Node3D:
		player.queue_free()
		return null
	player.name = "VerifierPlayer"
	root.add_child(player)
	(player as Node3D).global_position = Vector3.ZERO
	return player as Node3D


static func add_optional_weapon_ui(root: Node, player: Node) -> Node:
	var weapon_ui_scene := load("res://icons/weapon_ui.tscn")
	if weapon_ui_scene == null:
		return null
	var weapon_ui: Node = weapon_ui_scene.instantiate()
	weapon_ui.name = "VerifierWeaponUI"
	root.add_child(weapon_ui)
	if player != null and player.has_signal("weapon_switched") and weapon_ui.has_method("switch_to"):
		player.connect("weapon_switched", Callable(weapon_ui, "switch_to"))
		weapon_ui.call("switch_to", "DEFAULT")
	return weapon_ui


static func add_damage_target(root: Node3D, name: String, position: Vector3) -> VerifierDamageTarget:
	var target: VerifierDamageTarget = DamageTarget.new()
	target.name = name
	root.add_child(target)
	target.global_position = position
	return target


static func _create_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "VerifierGround"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.55, 0)
	return body
