extends Node2D
## Scene root for the current prototype: seeds the run and populates the room.
## Run-level state moves into a dedicated system in Milestone 2.

@export var enemy_count: int = 4

var run_seed: int

@onready var _room: Room = $Room
@onready var _player: Player = $Player


func _ready() -> void:
	run_seed = int(Time.get_unix_time_from_system())
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	print("Dungeon15 run seed: %d" % run_seed)

	_player.global_position = _room.get_player_spawn_position()
	_room.spawn_enemies(rng, enemy_count)
