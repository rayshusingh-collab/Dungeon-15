extends CharacterBody3D
## Isolated P1A controller. Reuses existing movement actions without changing them.

@export var move_speed: float = 5.0
@export var gravity: float = 20.0
@export var movement_camera: Camera3D

@onready var visual: Node3D = $Visual


func _physics_process(delta: float) -> void:
	var input := _movement_input()
	var direction := Vector3(input.x, 0.0, input.y)
	if is_instance_valid(movement_camera):
		var right := movement_camera.global_basis.x
		var forward := -movement_camera.global_basis.z
		right.y = 0.0
		forward.y = 0.0
		direction = right.normalized() * input.x - forward.normalized() * input.y
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	if direction.length_squared() > 0.0001:
		visual.look_at(visual.global_position + direction, Vector3.UP)
	move_and_slide()


func _movement_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")
