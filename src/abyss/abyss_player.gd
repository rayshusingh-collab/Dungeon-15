extends "res://src/prototype_3d/player_3d.gd"
## Keep P1A physics/camera mapping; substitute only the input source.

@export var movement_input: Node


func _movement_input() -> Vector2:
	if is_instance_valid(movement_input):
		return movement_input.movement_vector()
	return super._movement_input()
