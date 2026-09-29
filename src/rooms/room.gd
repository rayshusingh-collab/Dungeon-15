class_name Room
extends Node2D
## One combat room: walls, optional obstacles, an ExitDoor, and the enemies
## spawned into it. ACTIVE while any spawned enemy lives (exit locked);
## CLEARED once all of them are dead (exit unlocked). Emits exit_entered once
## when the player walks into the open exit.

signal cleared
signal enemy_died(enemy: Enemy)
signal enemies_remaining_changed(count: int)
signal exit_entered

enum State { ACTIVE, CLEARED }

@export var enemy_scene: PackedScene
@export var room_size: Vector2 = Vector2(1152, 648)
## Local-space rectangle that enemy positions are drawn from (inside the walls).
@export var spawn_area: Rect2 = Rect2(96, 80, 960, 488)
## Enemies never spawn closer than this to the player spawn point.
@export var min_player_distance: float = 320.0
## Preferred minimum distance between spawned enemies.
@export var min_enemy_separation: float = 96.0
## Clearance kept around obstacle rectangles when spawning.
@export var obstacle_clearance: float = 28.0

var state: State = State.ACTIVE
var living_enemy_count: int = 0

var _exit_used: bool = false

@onready var _enemies: Node2D = $Enemies
@onready var _obstacles: Node2D = $Obstacles
@onready var _exit_door: ExitDoor = $ExitDoor
@onready var _player_spawn: Marker2D = $PlayerSpawn


func _ready() -> void:
	_exit_door.set_locked(true)
	_exit_door.player_entered.connect(_on_exit_door_entered)


func get_player_spawn_position() -> Vector2:
	return _player_spawn.global_position


func get_bounds() -> Rect2:
	return Rect2(global_position, room_size)


func is_cleared() -> bool:
	return state == State.CLEARED


func is_exit_locked() -> bool:
	return _exit_door.locked


func get_exit_position() -> Vector2:
	return _exit_door.global_position


func get_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for child in _enemies.get_children():
		if child is Enemy:
			result.append(child)
	return result


## Spawns up to `count` enemies at positions drawn from `rng` (a seeded rng
## reproduces the same placement) and gives each of them `target`.
func spawn_enemies(rng: RandomNumberGenerator, count: int, target: Player) -> void:
	var positions := SpawnPlacer.pick_positions(rng, spawn_area, count,
			_player_spawn.position, min_player_distance, min_enemy_separation, get_spawn_blockers())
	for spawn_position in positions:
		var enemy := enemy_scene.instantiate() as Enemy
		enemy.position = spawn_position
		enemy.target = target
		enemy.died.connect(_on_enemy_died)
		_enemies.add_child(enemy)
		living_enemy_count += 1
	enemies_remaining_changed.emit(living_enemy_count)
	_check_cleared()


## Obstacle rectangles (local space, grown by obstacle_clearance) that
## spawning must avoid. Derived from the RectangleShape2Ds under $Obstacles,
## so new obstacles are picked up automatically.
func get_spawn_blockers() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for body in _obstacles.get_children():
		var body_2d := body as Node2D
		if body_2d == null:
			continue
		for child in body_2d.get_children():
			var shape_node := child as CollisionShape2D
			if shape_node == null or not shape_node.shape is RectangleShape2D:
				continue
			var shape_size := (shape_node.shape as RectangleShape2D).size
			var center := body_2d.position + shape_node.position
			rects.append(Rect2(center - shape_size / 2.0, shape_size).grow(obstacle_clearance))
	return rects


func _on_enemy_died(enemy: Enemy) -> void:
	living_enemy_count -= 1
	enemy_died.emit(enemy)
	enemies_remaining_changed.emit(living_enemy_count)
	_check_cleared()


func _check_cleared() -> void:
	if state == State.CLEARED or living_enemy_count > 0:
		return
	state = State.CLEARED
	_exit_door.set_locked(false)
	cleared.emit()


func _on_exit_door_entered() -> void:
	if state != State.CLEARED or _exit_used:
		return
	_exit_used = true
	exit_entered.emit()
