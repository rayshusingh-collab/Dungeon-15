class_name Main
extends Node2D
## Run orchestrator for the Milestone 1 prototype: owns the run seed, swaps
## rooms when the player takes the exit, and wires Player / Room signals to
## the HUD, camera and touch controls. Rooms cycle through room_scenes; there
## is no procedural generation until Milestone 2.

const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"attack", &"dodge",
]

@export var room_scenes: Array[PackedScene] = []
@export var base_enemy_count: int = 3
@export var max_enemy_count: int = 6
## Non-zero forces this run seed (debugging / reproducing a run).
@export var fixed_seed: int = 0
@export var transition_fade_time: float = 0.25

@export_group("Impact feedback")
## Hit-stop briefly slows the whole game (Engine.time_scale) on impacts.
## Durations are real seconds; 0 disables.
@export var hit_stop_time_scale: float = 0.05
@export var hit_stop_on_hit: float = 0.045
@export var hit_stop_on_kill: float = 0.08
@export var hit_stop_on_player_hurt: float = 0.07
@export var camera_kick_on_hit: float = 4.0
@export var camera_kick_on_kill: float = 7.0
@export var camera_kick_on_player_hurt: float = 8.0
@export var camera_shake_on_player_hurt: float = 5.0

var run_seed: int
var room_index: int = 0
var current_room: Room

var _transitioning: bool = false
var _hit_stop_token: int = 0

@onready var _player: Player = $Player
@onready var _camera: GameCamera = $GameCamera
@onready var _hud: Hud = $Hud
@onready var _controls: MobileControls = $MobileControls


func _ready() -> void:
	# Inputs pressed by touch controls survive a scene reload; start clean.
	release_gameplay_actions()
	run_seed = fixed_seed if fixed_seed != 0 else int(Time.get_unix_time_from_system())
	print("Dungeon15 run seed: %d" % run_seed)

	_player.health.health_changed.connect(_hud.set_health)
	_player.health.damaged.connect(_on_player_damaged)
	_player.hurt.connect(_on_player_hurt)
	_player.melee.hit_landed.connect(_on_player_hit_landed)
	_player.died.connect(_on_player_died)
	_hud.restart_requested.connect(restart)
	_hud.set_health(_player.health.current, _player.health.max_health)

	_load_room(0)
	_hud.show_banner("ROOM 1")


func _process(_delta: float) -> void:
	_controls.set_cooldown(&"attack", _player.melee.get_cooldown_ratio())
	_controls.set_cooldown(&"dodge", _player.get_dodge_cooldown_ratio())


func is_transitioning() -> bool:
	return _transitioning


func enemy_count_for_room(index: int) -> int:
	return mini(base_enemy_count + index, max_enemy_count)


## Each room gets its own RNG derived from the run seed, so a room's content
## does not depend on what happened in earlier rooms.
func room_seed(index: int) -> int:
	return hash([run_seed, index])


func restart() -> void:
	release_gameplay_actions()
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


static func release_gameplay_actions() -> void:
	for action in GAMEPLAY_ACTIONS:
		Input.action_release(action)


func _load_room(index: int) -> void:
	if current_room != null:
		remove_child(current_room)
		current_room.queue_free()
	room_index = index
	var scene := room_scenes[index % room_scenes.size()]
	current_room = scene.instantiate() as Room
	add_child(current_room)
	move_child(current_room, 0)
	current_room.enemies_remaining_changed.connect(_on_enemies_remaining_changed)
	current_room.cleared.connect(_on_room_cleared)
	current_room.exit_entered.connect(_on_room_exit_entered)

	_player.place_at(current_room.get_player_spawn_position())
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed(index)
	current_room.spawn_enemies(rng, enemy_count_for_room(index), _player)
	_camera.frame_rect(current_room.get_bounds())


func _on_room_exit_entered() -> void:
	if _transitioning or _player.is_dead():
		return
	_transitioning = true
	_player.controls_enabled = false
	await _hud.fade_out(transition_fade_time)
	_load_room(room_index + 1)
	_player.controls_enabled = true
	_hud.show_banner("ROOM %d" % (room_index + 1))
	await _hud.fade_in(transition_fade_time)
	_transitioning = false


func _on_enemies_remaining_changed(count: int) -> void:
	_hud.set_room_info(room_index + 1, count)


func _on_room_cleared() -> void:
	_hud.show_banner("ROOM CLEARED - EXIT UNLOCKED", Color(0.45, 0.95, 0.6), 1.8)


func _on_player_damaged(_amount: int) -> void:
	_hud.flash_damage()


func _on_player_hurt(knockback_direction: Vector2) -> void:
	hit_stop(hit_stop_on_player_hurt)
	_camera.kick(knockback_direction, camera_kick_on_player_hurt, 0.2)
	_camera.shake(camera_shake_on_player_hurt, 0.2)


func _on_player_hit_landed(hurtbox: Hurtbox) -> void:
	var direction := (hurtbox.global_position - _player.global_position).normalized()
	var killed := hurtbox.health != null and hurtbox.health.is_dead()
	hit_stop(hit_stop_on_kill if killed else hit_stop_on_hit)
	_camera.kick(direction, camera_kick_on_kill if killed else camera_kick_on_hit)


func _on_player_died() -> void:
	_controls.set_active(false)
	release_gameplay_actions()
	_hud.show_death(room_index + 1)


## Briefly slows the whole game to sell an impact. Overlapping calls: the most
## recent one decides when time resumes.
func hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hit_stop_token += 1
	Engine.time_scale = hit_stop_time_scale
	# process_always + ignore_time_scale: the timer runs in real time even
	# though the game is slowed.
	get_tree().create_timer(duration, true, false, true).timeout.connect(_end_hit_stop.bind(_hit_stop_token))


func is_hit_stopped() -> bool:
	return Engine.time_scale < 1.0


func _end_hit_stop(token: int) -> void:
	if token == _hit_stop_token:
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	# Never leave the engine slowed if the scene is freed mid hit-stop (restart).
	Engine.time_scale = 1.0
