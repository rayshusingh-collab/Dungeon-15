class_name Player
extends CharacterBody2D
## Player controller. Reads only InputMap actions, so keyboard and the
## on-screen touch controls drive it through the same path.

@export var move_speed: float = 230.0
## Prototype radial melee: every enemy within this distance is hit.
## To be replaced by a directional hitbox in Milestone 1.
@export var attack_range: float = 85.0
@export var attack_damage: int = 1


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * move_speed
	move_and_slide()

	if Input.is_action_just_pressed(&"attack"):
		_attack()


func _attack() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and global_position.distance_to(enemy.global_position) <= attack_range:
			enemy.take_damage(attack_damage)
