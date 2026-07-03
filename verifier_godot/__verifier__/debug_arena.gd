extends Node3D

const ArenaBuilder = preload("res://__verifier__/arena_builder.gd")
const DamageTarget = preload("res://__verifier__/verifier_damage_target.gd")

var arena: Node3D
var player: Node3D


func _ready() -> void:
	name = "VerifierDebugArena"
	arena = ArenaBuilder.create_arena()
	add_child(arena)
	player = ArenaBuilder.add_player(arena)
	ArenaBuilder.add_optional_weapon_ui(arena, player)
	_add_damage_target("NearTargetA", Vector3(0, 0.5, -8))
	_add_damage_target("NearTargetB", Vector3(1.5, 0.5, -8))
	_add_damage_target("FarTarget", Vector3(0, 0.5, -18))
	_add_damage_target("LeftSideTarget", Vector3(-7, 0.5, -8))
	_add_damage_target("RightSideTarget", Vector3(8.5, 0.5, -8))
	_add_damage_target("RearTarget", Vector3(0, 0.5, 6))
	_add_visible_floor()
	_add_target_label("NearTargetA", Vector3(0, 1.55, -8))
	_add_target_label("NearTargetB", Vector3(1.5, 1.55, -8))
	_add_target_label("FarTarget", Vector3(0, 1.55, -18))
	_add_target_label("LeftSideTarget", Vector3(-7, 1.55, -8))
	_add_target_label("RightSideTarget", Vector3(8.5, 1.55, -8))
	_add_target_label("RearTarget", Vector3(0, 1.55, 6))
	_add_controls_label()
	_add_debug_camera()
	_add_debug_light()
	print("Verifier debug arena ready. Open res://__verifier__/debug_arena.tscn and run this scene.")


func _add_damage_target(target_name: String, position: Vector3) -> Node3D:
	var target: Node3D = DamageTarget.new()
	target.name = target_name
	arena.add_child(target)
	target.global_position = position
	return target


func _add_visible_floor() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DebugVisibleFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 32)
	mesh.mesh = plane
	mesh.position = Vector3(0, -0.03, -6)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.22, 0.28, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	add_child(mesh)


func _add_target_label(label_text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.name = label_text + "Label"
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	label.modulate = Color(1.0, 0.95, 0.55)
	label.position = position
	add_child(label)


func _add_controls_label() -> void:
	var label := Label3D.new()
	label.name = "DebugControlsLabel"
	label.text = "Verifier debug arena\nTab: switch weapon\nAttack: throw grenade\nTargets show fallback front explosion trial\ngrader may adapt target distance after calibration"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 22
	label.outline_size = 6
	label.modulate = Color(0.8, 0.92, 1.0)
	label.position = Vector3(-4.5, 2.5, -3.2)
	add_child(label)


func _add_debug_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "DebugCamera"
	camera.current = true
	add_child(camera)
	camera.global_position = Vector3(7, 7, 9)
	camera.look_at(Vector3(0, 0.8, -8), Vector3.UP)


func _add_debug_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DebugDirectionalLight"
	sun.light_energy = 2.4
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)
