extends CharacterBody3D

const EXPLOSION_SCENE := preload("res://player/explosion_visuals/explosion_scene.tscn")

var gravity: float = 0.0

var _velocity := Vector3.ZERO

@onready var _explosion_sound: AudioStreamPlayer3D = $ExplosionSound
@onready var _explosion_start_timer: Timer = $ExplosionStartTimer


func _ready() -> void:
	_explosion_start_timer.timeout.connect(_explode)


func _physics_process(delta) -> void:
	_velocity += Vector3.DOWN * gravity * delta
	var collision := move_and_collide(_velocity * delta)
	if collision:
		_velocity = _velocity.bounce(collision.get_normal(0)) * 0.7
		if _explosion_start_timer.is_stopped():
			_explosion_start_timer.start()


func throw(throw_velocity: Vector3) -> void:
	_velocity = throw_velocity


func _explode() -> void:
	set_physics_process(false)

	_explosion_sound.pitch_scale = randfn(2.0, 0.1)
	_explosion_sound.play()

	for body in get_tree().get_nodes_in_group("targeteables"):
		if body is Player or not body is Node3D or not body.has_method("damage"):
			continue

		var target := body as Node3D
		var impact_point := global_position - target.global_position
		if impact_point.is_zero_approx():
			impact_point = Vector3.DOWN
		else:
			impact_point = impact_point.normalized()
		impact_point = (impact_point + Vector3.DOWN).normalized() * 0.5
		var force := -impact_point * 10.0
		body.damage(impact_point, force)

	var explosion: Node3D = EXPLOSION_SCENE.instantiate()
	get_parent().add_child(explosion)
	explosion.global_position = global_position

	hide()
	await _explosion_sound.finished
	queue_free()
