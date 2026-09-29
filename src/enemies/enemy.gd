class_name Enemy
extends CharacterBody2D
## Basic melee chaser: walks toward the player while inside aggro range.

signal died(enemy: Enemy)

@export var max_health: int = 2
@export var move_speed: float = 75.0
@export var aggro_range: float = 300.0
## Stops approaching at this distance so it does not shove the player.
@export var stop_distance: float = 45.0

var health: int

var _target: Node2D


func _ready() -> void:
	health = max_health


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node2D
		if _target == null:
			return

	var to_target := _target.global_position - global_position
	var distance := to_target.length()
	if distance < aggro_range and distance > stop_distance:
		velocity = to_target / distance * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO


func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health -= amount
	if health <= 0:
		died.emit(self)
		queue_free()
