class_name Main
extends Node2D
## Run orchestrator. Reads RunConfig (seed, depth), generates the depth with
## DungeonGenerator (headless-testable data), builds the DungeonWorld, and
## wires Player / world signals to the HUD, camera and touch controls.
## Retry, replay, new seed and next depth all go through RunConfig + a scene
## reload, so every start is a clean state. A seed only changes when the
## player explicitly asks for a new one.

const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"attack", &"dodge",
]

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
var depth: int
var profile: DepthProfile
var generation: DungeonGenerator.Result
var layout: DungeonLayout
var world: DungeonWorld

var _completed: bool = false
var _start_msec: int = 0
var _rewards_found: int = 0
var _hit_stop_token: int = 0
## Last position with solid, safe ground around it: where a fall respawns.
var _last_safe_position: Vector2 = Vector2.INF
var _last_discovered: int = -2
var _events_fired: int = 0
var _overlay: TacticalOverlay

@onready var _player: Player = $Player
@onready var _camera: GameCamera = $GameCamera
@onready var _hud: Hud = $Hud
@onready var _controls: MobileControls = $MobileControls


func _ready() -> void:
	# Inputs pressed by touch controls survive a scene reload; start clean.
	release_gameplay_actions()
	Engine.time_scale = 1.0
	RunConfig.ensure_initialized()
	run_seed = RunConfig.run_seed
	depth = RunConfig.depth
	print("Dungeon15 run seed: %d  depth: %d" % [run_seed, depth])

	_player.health.health_changed.connect(_hud.set_health)
	_player.health.damaged.connect(_on_player_damaged)
	_player.hurt.connect(_on_player_hurt)
	_player.melee.hit_landed.connect(_on_player_hit_landed)
	_player.died.connect(_on_player_died)
	_hud.set_health(_player.health.current, _player.health.max_health)
	_hud.retry_requested.connect(restart_same_seed)
	_hud.new_seed_requested.connect(start_new_seed)
	_hud.next_depth_requested.connect(start_next_depth)
	_hud.play_seed_requested.connect(start_with_seed)
	_hud.seed_panel_toggled.connect(_on_seed_panel_toggled)
	_camera.follow(_player)
	_start_depth()


func _process(_delta: float) -> void:
	_controls.set_cooldown(&"attack", _player.melee.get_cooldown_ratio())
	_controls.set_cooldown(&"dodge", _player.get_dodge_cooldown_ratio())
	if _hud.is_map_visible():
		_hud.map.set_player_position(_player.global_position)


func _physics_process(_delta: float) -> void:
	if world == null or _player.is_dead() or _player.is_falling():
		return
	var point := _player.global_position
	if world.is_safe_ground(point):
		_last_safe_position = point
	# Exploration map: reveal the room or corridor the player is standing in.
	var t := layout.tile_at(point)
	var room := layout.room_at_tile(t)
	var key := room.id if room != null else -1000 - layout.corridor_at_tile(t)
	if key != _last_discovered:
		_last_discovered = key
		if room != null:
			_hud.map.discover_room(room.id)
		elif layout.corridor_at_tile(t) >= 0:
			_hud.map.discover_corridor(layout.corridor_at_tile(t))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		_hud.toggle_map(DungeonMap.Mode.EXPLORATION)
		get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and event.is_action_pressed(&"toggle_debug_map"):
		_hud.toggle_map(DungeonMap.Mode.DEBUG_FULL)
		get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and event.is_action_pressed(&"toggle_tactical_overlay"):
		toggle_tactical_overlay()
		get_viewport().set_input_as_handled()


## Developer design view over the world (debug builds only).
func toggle_tactical_overlay() -> void:
	if _overlay != null and OS.is_debug_build():
		_overlay.visible = not _overlay.visible
		_overlay.queue_redraw()


func is_tactical_overlay_visible() -> bool:
	return _overlay != null and _overlay.visible


func last_safe_position() -> Vector2:
	return _last_safe_position


func events_fired() -> int:
	return _events_fired


func _start_depth() -> void:
	profile = DepthProfile.load_for_depth(depth)
	if profile == null:
		_fail("No generation profile exists for depth %d." % depth)
		return
	generation = DungeonGenerator.new().generate(profile, run_seed, depth)
	if not generation.ok:
		for line in generation.failure_log:
			printerr(line)
		_fail("Seed %d could not produce a valid depth %d after %d attempts.\nTry another seed." % [
			run_seed, depth, generation.attempts])
		return
	layout = generation.layout
	world = DungeonBuilder.build(layout)
	add_child(world)
	move_child(world, 0)
	world.room_entered.connect(_on_room_entered)
	world.encounter_started.connect(_on_encounter_started)
	world.enemies_remaining_changed.connect(_on_enemies_remaining_changed)
	world.encounter_cleared.connect(_on_encounter_cleared)
	world.marker_collected.connect(_on_marker_collected)
	world.exit_reached.connect(_on_exit_reached)
	world.player_fell.connect(_on_player_fell)
	world.tension_event.connect(_on_tension_event)

	_player.place_at(world.player_spawn)
	_last_safe_position = world.player_spawn
	_camera.set_bounds(world.pixel_bounds())
	_camera.snap()
	_hud.set_run_info(depth, profile.display_name, run_seed)
	_hud.set_status("Explore - find the exit")
	_hud.map.set_layout(layout)
	_hud.map.generation_log = generation.failure_log
	_hud.map.discover_room(layout.graph.entry_id())
	if OS.is_debug_build():
		_overlay = TacticalOverlay.new()
		_overlay.setup(layout)
		world.add_child(_overlay)
		_hud.tactical_overlay_requested.connect(toggle_tactical_overlay)
	_start_msec = Time.get_ticks_msec()
	_hud.show_banner("DEPTH %d" % depth)
	print("Generated depth %d in %.1f ms (%d attempt(s)), %d rooms, fingerprint %s" % [
		depth, generation.msec, generation.attempts, layout.rooms.size(), layout.fingerprint()])


func restart_same_seed() -> void:
	RunConfig.set_run(run_seed, depth)
	_reload()


func start_new_seed() -> void:
	RunConfig.new_random_run()
	_reload()


func start_next_depth() -> void:
	RunConfig.set_run(run_seed, depth + 1)
	_reload()


func start_with_seed(seed_value: int) -> void:
	RunConfig.set_run(seed_value, 1)
	_reload()


func is_completed() -> bool:
	return _completed


static func release_gameplay_actions() -> void:
	for action in GAMEPLAY_ACTIONS:
		Input.action_release(action)


func _reload() -> void:
	release_gameplay_actions()
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _fail(message: String) -> void:
	_player.controls_enabled = false
	_controls.set_active(false)
	_hud.show_generation_failure(message)


func _on_room_entered(room: DungeonRoom) -> void:
	_hud.map.discover_room(room.data.id)


func _on_player_fell(player: Player) -> void:
	var respawn := _last_safe_position
	if respawn == Vector2.INF or not world.is_safe_ground(respawn):
		respawn = world.player_spawn
	player.fall(respawn)
	_hud.show_banner("YOU FELL", Color(0.8, 0.8, 0.95), 0.6)


## Debug proof that tension/event sockets work end to end. Later milestones
## replace this with real thriller beats (sound, silhouette, flicker, story).
func _on_tension_event(trigger: EventTrigger) -> void:
	_events_fired += 1
	print("Tension event socket fired: %s at %s" % [trigger.kind, trigger.socket_tile])
	if OS.is_debug_build():
		_hud.show_debug_event("[debug] tension event socket fired (%s)" % trigger.kind)


func _on_encounter_started(room: DungeonRoom) -> void:
	if room.is_ambush():
		_hud.show_banner("AMBUSH! - the doors are open", Color(1, 0.7, 0.35), 1.0)
	else:
		_hud.show_banner("DOORS SEALED", Color(1, 0.45, 0.4), 0.9)
	_camera.shake(4.0, 0.2)


func _on_enemies_remaining_changed(_room: DungeonRoom, count: int) -> void:
	if count > 0:
		_hud.set_status("ENCOUNTER - %d ENEM%s LEFT" % [count, "Y" if count == 1 else "IES"], Color(1, 0.55, 0.5))


func _on_encounter_cleared(room: DungeonRoom) -> void:
	_hud.map.mark_cleared(room.data.id)
	_hud.show_banner("ENCOUNTER CLEARED", Color(0.45, 0.95, 0.6), 1.2)
	_hud.set_status("Explore - find the exit")


func _on_marker_collected(marker: RoomMarker) -> void:
	match marker.kind:
		&"reward":
			_rewards_found += 1
			_hud.show_banner("REWARD FOUND (placeholder)", Color(1, 0.85, 0.35), 1.0)
		&"lore":
			_hud.show_banner("AN OLD INSCRIPTION (placeholder)", Color(0.8, 0.82, 0.95), 1.0)
		&"secret":
			_hud.show_banner("SOMETHING IS HIDDEN HERE... (future secret)", Color(0.7, 0.6, 0.9), 1.2)
		&"cache":
			_rewards_found += 1
			_hud.show_banner("CACHE CLAIMED (placeholder high-value reward)", Color(1, 0.6, 0.25), 1.2)
		&"power":
			_rewards_found += 1
			_hud.show_banner("POWER SOCKET (future power-up)", Color(0.8, 0.6, 1.0), 1.2)
		&"heal":
			# Resource hook: recovery is only spent when it helps.
			if _player.health.is_full():
				marker.restore()
				_hud.show_banner("FULL HEALTH - the shrine will wait", Color(0.6, 0.9, 0.7), 1.0)
			else:
				_player.health.heal(1)
				_hud.show_banner("RECOVERED 1 HEART", Color(0.45, 0.95, 0.6), 1.0)


func _on_exit_reached() -> void:
	if _completed or _player.is_dead():
		return
	_completed = true
	_player.controls_enabled = false
	_controls.set_active(false)
	release_gameplay_actions()
	var has_next := DepthProfile.exists_for_depth(depth + 1)
	_hud.show_depth_complete("DEPTH %d COMPLETE" % depth, _stats_text(), has_next)


func _stats_text() -> String:
	var visited := 0
	var fights := 0
	var cleared := 0
	for room in world.rooms:
		if room.visited:
			visited += 1
		if room.has_encounter():
			fights += 1
			if room.state == DungeonRoom.EncounterState.CLEARED:
				cleared += 1
	var seconds := (Time.get_ticks_msec() - _start_msec) / 1000
	return "Seed %d, depth %d\nRooms explored %d / %d   Encounters cleared %d / %d   Rewards %d\nTime %d:%02d" % [
		run_seed, depth, visited, world.rooms.size(), cleared, fights, _rewards_found, seconds / 60, seconds % 60]


func _on_seed_panel_toggled(open: bool) -> void:
	get_tree().paused = open
	_controls.set_active(not open and not _player.is_dead() and not _completed)
	if open:
		release_gameplay_actions()


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
	_hud.show_death("Seed %d, depth %d" % [run_seed, depth])


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
	# Never leave the engine slowed or paused if the scene is freed.
	Engine.time_scale = 1.0
	if get_tree() != null:
		get_tree().paused = false
