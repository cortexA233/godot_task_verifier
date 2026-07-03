class_name VerifierDamageTarget
extends RigidBody3D

var damage_calls := 0
var last_impact_point := Vector3.ZERO
var last_force := Vector3.ZERO


func _ready() -> void:
	add_to_group("damageables")
	add_to_group("targeteables")
	freeze = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.6
	mesh.mesh = sphere_mesh
	add_child(mesh)


func damage(impact_point: Vector3, force: Vector3) -> void:
	damage_calls += 1
	last_impact_point = impact_point
	last_force = force
