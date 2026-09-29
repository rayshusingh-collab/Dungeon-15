class_name Room
extends Node2D
## A single combat room: static walls, an exit door, and the enemies spawned
## into it. Emits `cleared` once every spawned enemy has died.

signal cleared

const DOOR_LOCKED_COLOR := Color("b33b4b")
const DOOR_OPEN_COLOR := Color("45d483")

@export var enemy_scene: PackedScene
## Local-space rectangle enemies may spawn in.
@export var enemy_spawn_area: Rect2 = Rect2(250, 100, 650, 450)

var is_cleared: bool = false

var _living_enemies: int = 0

@onready var _enemies: Node2D = $Enemies
@onready var _exit_door: ColorRect = $ExitDoor
@onready var _player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	_exit_door.color = DOOR_LOCKED_COLOR


func get_player_spawn_position() -> Vector2:
	return _player_spawn.global_position


## Spawns `count` enemies at positions drawn from `rng`, so a seeded rng
## reproduces the same placement.
func spawn_enemies(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var enemy := enemy_scene.instantiate() as Enemy
		var x := rng.randf_range(enemy_spawn_area.position.x, enemy_spawn_area.end.x)
		var y := rng.randf_range(enemy_spawn_area.position.y, enemy_spawn_area.end.y)
		enemy.position = Vector2(x, y)
		enemy.died.connect(_on_enemy_died)
		_enemies.add_child(enemy)
		_living_enemies += 1
	_check_cleared()


func _on_enemy_died(_enemy: Enemy) -> void:
	_living_enemies -= 1
	_check_cleared()


func _check_cleared() -> void:
	if is_cleared or _living_enemies > 0:
		return
	is_cleared = true
	_exit_door.color = DOOR_OPEN_COLOR
	cleared.emit()
