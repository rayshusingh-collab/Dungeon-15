extends Camera3D
## Position follows; orientation and projection remain fixed after startup.

@export var target: Node3D
@export var follow_offset: Vector3 = Vector3(12.0, 12.0, 12.0)
@export var follow_speed: float = 7.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	if is_instance_valid(target):
		global_position = target.global_position + follow_offset
		look_at(target.global_position, Vector3.UP)


func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = global_position.lerp(
			target.global_position + follow_offset, 1.0 - exp(-follow_speed * delta))
