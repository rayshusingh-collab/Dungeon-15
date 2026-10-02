extends "res://tools/test_harness.gd"
## Headless smoke/integration tests for the playable game (combat + dungeon).
## Run: godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
## (--fixed-fps makes every frame exactly 1/60 s, so timings are deterministic.)
## Combat tests run in the generated entry hall (always safe, 24x14 tiles).
## Generation-at-scale tests live in tools/generation_stress.gd.

const MAIN_SCENE := "res://src/main/main.tscn"
const ENEMY_SCENE := "res://src/enemies/enemy.tscn"
## Fixed run seed for deterministic integration tests.
const TEST_SEED := 12345
const ALL_SCENES: Array[String] = [
	"res://src/main/main.tscn", "res://src/player/player.tscn", "res://src/enemies/enemy.tscn",
	"res://src/enemies/brute.tscn", "res://src/enemies/spitter.tscn",
	"res://src/ui/hud.tscn", "res://src/ui/mobile_controls.tscn",
	"res://src/dungeon/rooms/story_chamber_content.tscn",
]


func _suite_name() -> String:
	return "SMOKE TEST"


func _get_tests() -> Array[Callable]:
	return [
		_test_scenes_load, _test_health_component, _test_run_config,
		_test_movement, _test_touch_controls, _test_attack, _test_combat_feel, _test_dodge,
		_test_enemy_states, _test_enemy_attack, _test_enemy_attack_motion,
		_test_dungeon_boot, _test_camera_follow, _test_encounter_flow, _test_spike_trap, _test_markers,
		_test_water, _test_pit_fall, _test_enemy_knocked_into_pit, _test_walls_block_attacks,
		_test_combat_near_walls, _test_enemy_pathfinding, _test_exploration_map, _test_tension_event,
		_test_archetypes, _test_brute_knockback_into_pit, _test_spitter_projectile, _test_spitter_shoots_across_chasm,
		_test_spikes_hurt_enemies, _test_contact_damage, _test_contact_never_stacks, _test_dodge_ignores_contact,
		_test_stagger_guard, _test_brute_windup_armor, _test_crowd_surrounds, _test_group_pressure, _test_density_built,
		_test_ambush_room, _test_heal_shrine, _test_risk_cache, _test_tactical_debug_views,
		_test_depth_completion, _test_next_depth_sealed_exit, _test_seed_entry_and_new_seed,
		_test_seed_panel_pauses, _test_death_restart,
	]


func _after_each() -> void:
	Main.release_gameplay_actions()
	paused = false
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	await process_frame


# --- basics --------------------------------------------------------------------

func _test_scenes_load() -> bool:
	for path in ALL_SCENES:
		var scene := load(path) as PackedScene
		var instance := scene.instantiate() if scene != null else null
		_check(instance != null, "instantiates %s" % path)
		if instance != null:
			instance.free()
	return true


func _test_health_component() -> bool:
	var health := HealthComponent.new()
	health.max_health = 3
	health.invulnerability_after_hit = 0.5
	root.add_child(health)
	var deaths := [0]
	health.died.connect(func() -> void: deaths[0] += 1)
	_check(health.current == 3, "health starts at max")
	_check(health.take_damage(1) and health.current == 2, "damage reduces health")
	_check(not health.take_damage(1) and health.current == 2, "invulnerability blocks immediate second hit")
	await _frames(35)
	_check(health.take_damage(1) and health.current == 1, "damage applies again after invulnerability expires")
	await _frames(35)
	health.take_damage(10)
	_check(health.current == 0 and deaths[0] == 1, "lethal damage clamps at 0 and emits died once")
	await _frames(35)
	_check(not health.take_damage(1) and deaths[0] == 1, "no damage or second death after dying")
	health.grant_invulnerability(0.3)
	health.grant_invulnerability(0.1)
	await _frames(12)
	_check(health.is_invulnerable(), "grant_invulnerability never shortens an existing window")
	health.free()
	return true


func _test_run_config() -> bool:
	var args := RunConfig.parse_args(PackedStringArray(["--seed=777", "--depth=2", "--other"]))
	_check(args.get("seed") == 777 and args.get("depth") == 2, "command-line --seed/--depth are parsed")
	_check(RunConfig.parse_args(PackedStringArray(["--seed="])).is_empty(), "empty --seed is ignored")
	_check(RunConfig.parse_seed_text(" 42 ") == 42, "numeric seed text is used as-is")
	_check(RunConfig.parse_seed_text("crypt") == RunConfig.parse_seed_text("CRYPT")
			and RunConfig.parse_seed_text("CRYPT") >= 0, "word seeds are hashed case-insensitively")
	_check(RunConfig.parse_seed_text("") == -1, "empty seed text is rejected")
	RunConfig.set_run(-5, 0)
	_check(RunConfig.run_seed >= 0 and RunConfig.depth == 1, "set_run keeps seed non-negative and depth >= 1")
	var a := RunConfig.random_seed()
	var b := RunConfig.random_seed()
	_check(a >= 0 and b >= 0 and a != b, "random seeds are non-negative and vary")
	return true


# --- combat (Milestone 1, in the entry hall) ----------------------------------------

func _test_movement() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var start := player.global_position
	Input.action_press(&"move_right")
	await _frames(12)
	Input.action_release(&"move_right")
	var expected := player.move_speed * 12.0 / 60.0
	_check(absf((player.global_position.x - start.x) - expected) < 6.0,
			"move_right covers speed*time (%.1f px, expected ~%.1f)" % [player.global_position.x - start.x, expected])
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	await _frames(3)
	var diagonal_speed := player.velocity.length()
	_check(diagonal_speed <= player.move_speed + 0.01 and diagonal_speed > player.move_speed * 0.95,
			"diagonal speed is not faster (%.1f)" % diagonal_speed)
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	await _frames(2)
	_check(player.velocity == Vector2.ZERO, "player stops when input is released")
	return true


func _test_touch_controls() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var joystick := main.get_node("MobileControls/VirtualJoystick") as Control
	var attack_button := main.get_node("MobileControls/AttackButton") as TouchActionButton
	var dodge_button := main.get_node("MobileControls/DodgeButton") as TouchActionButton
	var center := joystick.get_global_rect().get_center()
	_touch(0, center, true)
	_drag(0, center + Vector2(70, 0))
	await _frames(3)
	_check(Input.get_action_strength(&"move_right") > 0.0, "joystick drag presses move_right")
	_check(player.velocity.x > 0.0, "joystick drag moves the player")
	var attack_center := attack_button.get_global_rect().get_center()
	_touch(1, attack_center, true)
	_check(Input.is_action_pressed(&"attack") and Input.get_action_strength(&"move_right") > 0.0,
			"attack button works while joystick is held (multi-touch)")
	_touch(1, attack_center, false)
	_check(not Input.is_action_pressed(&"attack"), "attack button release clears attack")
	_touch(0, center + Vector2(70, 0), false)
	await _frames(3)
	_check(is_zero_approx(Input.get_action_strength(&"move_right")), "joystick release returns to neutral")
	_check(player.velocity == Vector2.ZERO, "player stops after joystick release")
	var dodge_center := dodge_button.get_global_rect().get_center()
	_touch(2, dodge_center, true)
	_check(Input.is_action_pressed(&"dodge"), "dodge button presses dodge")
	_touch(2, dodge_center, false)
	_check(not Input.is_action_pressed(&"dodge"), "dodge button release clears dodge")
	_check(not attack_button.get_global_rect().intersects(dodge_button.get_global_rect()),
			"attack and dodge touch areas do not overlap")
	var controls := main.get_node("MobileControls") as MobileControls
	controls.set_active(false)
	_touch(3, attack_center, true)
	_check(not Input.is_action_pressed(&"attack"), "hidden controls ignore touches")
	_touch(3, attack_center, false)
	return true


func _test_attack() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var enemy := _spawn_test_enemy(main, player.global_position + Vector2(55, 0), null)
	enemy.set_physics_process(false)
	# Spare HP so an accidental multi-hit shows up as a bigger drop, not a death.
	enemy.health.current = 10
	await _frames(2)
	var strikes := [0]
	player.melee.strike_started.connect(func() -> void: strikes[0] += 1)
	var hits := [0]
	player.melee.hit_landed.connect(func(_h: Hurtbox) -> void: hits[0] += 1)
	player.facing = Vector2.RIGHT
	var hp := enemy.health.current
	await _press(&"attack")
	_check(player.state == Player.State.ATTACK, "attack input starts an attack")
	await _frames(30)
	_check(enemy.health.current == hp - 1 and hits[0] == 1,
			"one swing damages an overlapping enemy exactly once (hp %d -> %d)" % [hp, enemy.health.current])
	_check(player.state == Player.State.NORMAL, "player returns to NORMAL after the swing")
	await _press(&"attack")
	await _frames(2)
	await _press(&"attack")
	await _frames(15)
	_check(strikes[0] == 2, "attack cannot be spammed faster than its cooldown (%d strikes)" % strikes[0])
	await _frames(20)
	enemy.global_position = player.global_position + Vector2(-55, 0)
	await _frames(2)
	hp = enemy.health.current
	player.facing = Vector2.RIGHT
	await _press(&"attack")
	await _frames(30)
	_check(enemy.health.current == hp, "attack only hits in the facing direction")
	return true


func _test_combat_feel() -> bool:
	var main := await _start_main()
	var player := _player(main)
	player.facing = Vector2.RIGHT
	var start := player.global_position
	var strike_frame := [-1]
	player.melee.strike_started.connect(func() -> void: strike_frame[0] = Engine.get_physics_frames())
	var press_frame := Engine.get_physics_frames()
	await _press(&"attack")
	_check(player.melee.phase == MeleeAttack.Phase.WINDUP and not player.melee.hitbox.active,
			"attack begins with a short anticipation (windup, hitbox off)")
	await _frames(20)
	var windup_frames: int = strike_frame[0] - press_frame
	_check(windup_frames >= 2 and windup_frames <= 6,
			"strike follows the press within a few frames (%d) - responsive" % windup_frames)
	var step := player.global_position.x - start.x
	_check(step > 5.0 and step < 30.0 and absf(player.global_position.y - start.y) < 1.0,
			"swing steps forward in the facing direction (%.1f px) with no input" % step)
	await _frames(30)
	var enemy := _spawn_test_enemy(main, player.global_position + Vector2(52, 0), null)
	await _frames(2)
	enemy.health.current = 10
	var hit_frame := [-1]
	player.melee.hit_landed.connect(func(_h: Hurtbox) -> void: hit_frame[0] = Engine.get_physics_frames())
	var enemy_x := enemy.global_position.x
	player.facing = Vector2.RIGHT
	await _press(&"attack")
	var hit := await _wait_until(func() -> bool: return hit_frame[0] >= 0, 20)
	_check(hit and hit_frame[0] == strike_frame[0],
			"damage lands on the strike frame (%d frame(s) after strike start)" % (hit_frame[0] - strike_frame[0]))
	_check(main.is_hit_stopped(), "a connecting hit triggers hit-stop")
	_check(await _wait_until(func() -> bool: return not main.is_hit_stopped(), 12), "hit-stop ends quickly")
	await _frames(20)
	_check(enemy.global_position.x - enemy_x > 15.0,
			"enemy is knocked back along the swing (%.0f px)" % (enemy.global_position.x - enemy_x))
	await _frames(30)
	enemy.health.current = 1
	player.place_at(enemy.global_position - Vector2(52, 0))
	player.facing = Vector2.RIGHT
	await _frames(1)
	var death_x := enemy.global_position.x
	await _press(&"attack")
	await _wait_until(func() -> bool: return enemy.state == Enemy.State.DEAD, 20)
	await _frames(12)
	_check(enemy.state == Enemy.State.DEAD and enemy.global_position.x - death_x > 15.0,
			"killing blow sends the body sliding (%.0f px)" % (enemy.global_position.x - death_x))
	return true


func _test_dodge() -> bool:
	var main := await _start_main()
	var player := _player(main)
	player.place_at(_arena(main) + Vector2(-300, 0))
	player.facing = Vector2.RIGHT
	var x0 := player.global_position.x
	var hp := player.health.current
	await _press(&"dodge")
	_check(player.state == Player.State.DODGE, "dodge input starts a dodge")
	_check(player.health.is_invulnerable(), "dodge grants invulnerability")
	_check(not player.health.take_damage(1) and player.health.current == hp, "damage is ignored during dodge i-frames")
	await _frames(14)
	_check(player.global_position.x - x0 > 90.0, "dodge is a fast burst (%.0f px)" % (player.global_position.x - x0))
	_check(player.state == Player.State.NORMAL, "dodge ends after its duration")
	await _press(&"dodge")
	_check(player.state != Player.State.DODGE, "dodge cannot be spammed during cooldown")
	await _frames(10)
	_check(not player.health.is_invulnerable(), "dodge invulnerability expires")
	await _frames(20)
	await _press(&"dodge")
	_check(player.state == Player.State.DODGE, "dodge is available again after cooldown")
	await _frames(60)
	await _press(&"attack")
	_check(player.state == Player.State.ATTACK, "attack started before dodge-cancel")
	await _press(&"dodge")
	_check(player.state == Player.State.DODGE and not player.melee.is_busy(), "dodge cancels an attack cleanly")
	return true


func _test_enemy_states() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	var enemy := _spawn_test_enemy(main, arena + Vector2(200, 0), player)
	player.place_at(arena + Vector2(-150, 0))
	await _frames(5)
	_check(enemy.state == Enemy.State.IDLE, "enemy IDLE while player is out of aggro range")
	player.place_at(arena + Vector2(-40, 0))
	await _frames(3)
	_check(enemy.state == Enemy.State.CHASE, "enemy CHASE when player enters aggro range")
	player.place_at(arena + Vector2(-180, 0))
	await _frames(20)
	_check(enemy.state == Enemy.State.CHASE, "engaged enemy keeps chasing beyond aggro range")
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.ATTACK, 400),
			"enemy reaches the player and starts ATTACK")
	player.facing = (enemy.global_position - player.global_position).normalized()
	await _press(&"attack")
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.HURT, 20),
			"player hit puts enemy into HURT (interrupting its attack)")
	_check(not enemy.melee.is_busy(), "hurt cancels the enemy attack")
	_check(enemy.melee.get_cooldown_ratio() * enemy.melee.cooldown <= enemy.post_hurt_attack_delay + 0.001,
			"after a stagger the next attack is at most post_hurt_attack_delay away")
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.CHASE, 30),
			"enemy resumes CHASE after the stagger")
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 120)
	player.health.take_damage(99)
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.RETURN, 10),
			"enemy RETURNs when the player dies")
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.IDLE, 600),
			"enemy goes IDLE once home")
	_check(enemy.global_position.distance_to(enemy.home_position) < 6.0, "enemy is back at its home position")
	var died := [false]
	enemy.died.connect(func(_e: Enemy) -> void: died[0] = true)
	enemy.health.take_damage(99)
	_check(died[0] and enemy.state == Enemy.State.DEAD, "enemy DEAD emits died")
	_check(is_instance_valid(enemy) and not enemy.is_in_group(&"enemies"),
			"dead enemy stays briefly for its death effect, out of the enemies group")
	var enemy_id := enemy.get_instance_id()
	_check(await _wait_until(func() -> bool: return not is_instance_id_valid(enemy_id), 60),
			"dead enemy is freed after the effect")
	return true


func _test_enemy_attack() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena + Vector2(-176, 0))
	var enemy := _spawn_test_enemy(main, arena + Vector2(-124, 0), player)
	var hp := player.health.current
	_check(await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.WINDUP, 20),
			"enemy in range begins a telegraphed windup")
	await _frames(20)
	_check(player.health.current == hp, "no damage during the windup (reaction window)")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 30),
			"enemy strike damages the player")
	_check(player.health.current == hp - 1, "one strike deals damage once")
	_check(player.health.is_invulnerable(), "player is invulnerable right after being hit")
	player.place_at(enemy.global_position + Vector2(-50, 0))
	await _frames(40)
	_check(player.health.current == hp - 1, "no continuous contact damage")
	_check(await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.WINDUP, 120),
			"enemy telegraphs its next attack")
	hp = player.health.current
	Input.action_press(&"move_left")
	await _press(&"dodge")
	await _frames(20)
	Input.action_release(&"move_left")
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.RECOVERY, 40)
	_check(player.health.current == hp, "dodging away from the telegraph avoids damage")
	return true


func _test_enemy_attack_motion() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena + Vector2(-176, 0))
	var enemy := _spawn_test_enemy(main, arena + Vector2(-124, 0), player)
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.WINDUP, 20)
	var windup_x := enemy.global_position.x
	var hp := player.health.current
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.ACTIVE, 40)
	var strike_x := enemy.global_position.x
	_check(strike_x - windup_x > 5.0, "enemy coils back during the windup (%.1f px)" % (strike_x - windup_x))
	Input.action_press(&"move_right")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 20), "enemy strike connects")
	var hit_x := player.global_position.x
	_check(player.is_staggered(), "player is staggered after being hit")
	await _frames(2)
	_check(player.velocity.x < -250.0,
			"held movement input does not fight the knockback (vx %.0f)" % player.velocity.x)
	await _frames(8)
	_check(player.global_position.x < hit_x,
			"movement input is ignored during the stagger (knocked back %.1f px)" % (hit_x - player.global_position.x))
	await _press(&"dodge")
	Input.action_release(&"move_right")
	_check(player.state == Player.State.DODGE, "dodge still works during the stagger")
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.RECOVERY, 20)
	_check(strike_x - enemy.global_position.x > 5.0,
			"enemy lunges forward on the strike (%.1f px)" % (strike_x - enemy.global_position.x))
	return true


# --- dungeon integration --------------------------------------------------------

func _test_dungeon_boot() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var layout := main.layout
	_check(main.world != null and layout != null and main.run_seed == TEST_SEED and main.depth == 1,
			"main generated and built depth 1 for the configured seed")
	_check(player.global_position.distance_to(main.world.player_spawn) < 2.0
			and main.world.room_at(player.global_position) == main.world.get_room(layout.graph.entry_id()),
			"player starts on the entry spawn inside the entry room")
	_check(main.get_node("Hud").get_run_text().contains(str(TEST_SEED)), "HUD shows the seed")
	_check(main.world.get_enemies().is_empty(), "no enemies exist before any encounter starts (idle rooms cost nothing)")
	var count := _count_nodes(main.world)
	_check(count < 500, "world node count is modest (%d)" % count)
	_check(main.world.wall_shape_count < layout.size.x * layout.size.y / 10,
			"wall collision is merged (%d shapes for %d tiles)" % [main.world.wall_shape_count, layout.size.x * layout.size.y])
	var hud := main.get_node("Hud") as Hud
	var event := InputEventAction.new()
	event.action = &"toggle_map"
	event.pressed = true
	root.push_input(event)
	await _frames(1)
	_check(hud.is_map_visible(), "toggle_map action opens the debug map")
	root.push_input(event)
	await _frames(1)
	_check(not hud.is_map_visible(), "toggle_map action closes the debug map")
	hud.press_button("TopButtons/MapButton")
	_check(hud.is_map_visible(), "MAP button opens the debug map")
	return true


func _test_camera_follow() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var camera := main.get_node("GameCamera") as GameCamera
	_check(camera.global_position.distance_to(player.global_position) < 2.0, "camera starts on the player")
	var bounds := main.world.pixel_bounds()
	_check(camera.limit_left == int(bounds.position.x) and camera.limit_right == int(bounds.end.x)
			and camera.limit_bottom == int(bounds.end.y), "camera limits match the dungeon bounds")
	player.place_at(main.layout.tile_center(main.layout.exit_tile))
	await _frames(90)
	_check(camera.get_screen_center_position().distance_to(player.global_position) < 200.0,
			"camera follows the player across the dungeon")
	_check(bounds.has_point(camera.get_screen_center_position()), "camera stays inside the dungeon bounds")
	return true


func _test_encounter_flow() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var room := _first_main_combat_room(main)
	_check(room != null, "the test seed has a combat room on the main path")
	if room == null:
		return true
	_check(room.state == DungeonRoom.EncounterState.DORMANT and not room.gates.is_empty()
			and not room.gates[0].is_blocking(), "combat room starts dormant with open gates")
	var door: Dictionary = room.data.doors[0]
	var probe := _make_probe()
	var inside_door := main.layout.tile_center(door.inside)
	var outward := Vector2(RoomShape.SIDE_VECTORS[door.side]) * DungeonLayout.TILE_SIZE
	probe.global_position = inside_door
	await _frames(2)
	_check(not probe.test_move(probe.global_transform, outward * 3.0), "doorway is passable before the encounter")
	var entry_point := _room_entry_point(main.layout, room.data, door)
	player.place_at(entry_point)
	_check(await _wait_until(func() -> bool: return room.state == DungeonRoom.EncounterState.ACTIVE, 10),
			"entering the room starts the encounter")
	await _frames(2)
	var all_locked := true
	for gate in room.gates:
		all_locked = all_locked and gate.is_blocking()
	_check(all_locked, "all doorways of the room lock")
	_check(probe.test_move(probe.global_transform, outward * 3.0), "a locked gate physically blocks the doorway")
	_check(await _wait_until(func() -> bool: return room.enemies.size() == room.data.enemy_ids.size(), 60),
			"%d enemies spawn after the telegraph" % room.data.enemy_ids.size())
	var rect := room.pixel_rect()
	var ok_spawns := true
	for enemy in room.enemies:
		ok_spawns = ok_spawns and rect.has_point(enemy.global_position) \
			and enemy.global_position.distance_to(entry_point) >= DungeonValidator.MIN_SPAWN_DISTANCE - 1.0
	_check(ok_spawns, "enemies spawn inside the room, away from the player")
	var engaged := true
	for enemy in room.enemies:
		engaged = engaged and enemy.state != Enemy.State.IDLE
	_check(engaged, "ambush enemies engage immediately")
	_check((main.get_node("Hud") as Hud).get_status().begins_with("ENCOUNTER"), "HUD shows the encounter status")
	player.health.grant_invulnerability(100.0)
	for enemy in room.enemies.duplicate():
		enemy.health.take_damage(99)
	_check(room.state == DungeonRoom.EncounterState.CLEARED, "killing every enemy clears the room")
	await _frames(2)
	var all_open := true
	for gate in room.gates:
		all_open = all_open and not gate.is_blocking()
	_check(all_open and not probe.test_move(probe.global_transform, outward * 3.0), "gates reopen after the clear")
	player.place_at(main.world.player_spawn)
	await _frames(3)
	player.place_at(entry_point)
	await _frames(40)
	_check(room.state == DungeonRoom.EncounterState.CLEARED and room.enemies.is_empty(),
			"re-entering a cleared room does not relock or respawn")
	probe.queue_free()
	return true


func _test_spike_trap() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var tile := Vector2i(floori(player.global_position.x / DungeonLayout.TILE_SIZE),
			floori(player.global_position.y / DungeonLayout.TILE_SIZE))
	var trap := SpikeTrap.new()
	var tiles: Array[Vector2i] = [tile, tile + Vector2i.RIGHT]
	trap.setup(tiles, 0.0)
	main.world.add_child(trap)
	var hp := player.health.current
	await _frames(40)
	_check(trap.phase == SpikeTrap.Phase.RETRACTED and player.health.current == hp, "retracted spikes are harmless")
	_check(await _wait_until(func() -> bool: return trap.phase == SpikeTrap.Phase.WARNING, 60), "spikes telegraph before rising")
	_check(player.health.current == hp, "no damage during the warning")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 60), "raised spikes damage the player")
	_check(player.health.current == hp - 1, "one raise hits once")
	await _wait_until(func() -> bool: return trap.phase == SpikeTrap.Phase.RETRACTED, 120)
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 120)
	player.place_at(Vector2(tile * DungeonLayout.TILE_SIZE) + Vector2(16, 16))
	hp = player.health.current
	await _wait_until(func() -> bool: return trap.phase == SpikeTrap.Phase.WARNING, 200)
	player.health.grant_invulnerability(1.2)  # e.g. dodge i-frames timed over the raise
	await _wait_until(func() -> bool: return trap.phase == SpikeTrap.Phase.RETRACTED, 120)
	_check(player.health.current == hp, "invulnerability (e.g. a dodge) avoids spike damage")
	trap.queue_free()
	return true


func _test_markers() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var marker: RoomMarker = null
	for candidate in main.world.markers:
		if candidate.kind == &"reward" or candidate.kind == &"lore":
			marker = candidate
			break
	if marker == null:
		marker = RoomMarker.new()
		marker.setup(player.global_position + Vector2(120, 0), &"reward")
		main.world.add_child(marker)
	var got := [false]
	marker.collected.connect(func(_m: RoomMarker) -> void: got[0] = true)
	player.place_at(marker.global_position)
	_check(await _wait_until(func() -> bool: return got[0], 10), "touching a marker collects it")
	_check(marker.is_collected, "marker stays collected")
	return true


func _test_water() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena + Vector2(-250, 0))
	var water := WaterZone.new()
	var rects: Array[Rect2] = [Rect2(arena + Vector2(-80, -120), Vector2(240, 240))]
	water.setup(rects)
	main.world.add_child(water)
	await _frames(2)
	var x0 := player.global_position.x
	Input.action_press(&"move_right")
	await _frames(12)
	var dry_speed := (player.global_position.x - x0) / 12.0
	player.place_at(arena)
	await _frames(3)
	_check(player.terrain.is_in(&"water"), "standing in water registers on the TerrainState")
	x0 = player.global_position.x
	await _frames(12)
	Input.action_release(&"move_right")
	var wet_speed := (player.global_position.x - x0) / 12.0
	_check(wet_speed < dry_speed * 0.75 and wet_speed > dry_speed * 0.5,
			"water slows walking noticeably but not severely (%.1f vs %.1f px/frame)" % [wet_speed, dry_speed])
	player.place_at(arena)
	await _frames(2)
	player.facing = Vector2.DOWN
	var y0 := player.global_position.y
	await _press(&"dodge")
	await _frames(12)
	_check(player.global_position.y - y0 > 80.0, "dodging through water still covers ground (%.0f px)" % (player.global_position.y - y0))
	player.place_at(arena + Vector2(-250, 0))
	await _frames(3)
	_check(not player.terrain.is_in(&"water") and is_equal_approx(player.terrain.speed_scale(), 1.0),
			"leaving water restores full speed")
	var enemy := _spawn_test_enemy(main, arena + Vector2(40, 0), null)
	await _frames(3)
	_check(enemy.terrain.is_in(&"water") and enemy.terrain.speed_scale() < 1.0, "enemies are slowed by water too")
	return true


## Carves a pit into the layout (so safe-ground tracking knows it) and adds
## its PitZone, `offset` tiles right of the entry anchor, `size` tiles large.
func _make_pit(main: Main, offset: int, size: Vector2i) -> PitZone:
	var layout := main.layout
	var entry := layout.entry_room()
	var top_left := entry.anchor + Vector2i(offset, -size.y / 2)
	for y in size.y:
		for x in size.x:
			layout.set_tile(top_left + Vector2i(x, y), DungeonLayout.Tile.PIT, entry.id)
	var pit := PitZone.new()
	var rects: Array[Rect2] = [Rect2(Vector2(top_left * DungeonLayout.TILE_SIZE), Vector2(size * DungeonLayout.TILE_SIZE))]
	pit.setup(rects)
	pit.player_fell.connect(main.world.player_fell.emit)
	main.world.add_child(pit)
	return pit


func _test_pit_fall() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	var pit := _make_pit(main, 2, Vector2i(4, 5))
	var pit_edge_x := float((main.layout.entry_room().anchor.x + 2) * DungeonLayout.TILE_SIZE)
	player.place_at(arena)
	await _frames(3)
	var safe := main.last_safe_position()
	_check(main.world.is_safe_ground(safe), "last safe position is tracked on solid ground")
	var hp := player.health.current
	Input.action_press(&"move_right")
	_check(await _wait_until(func() -> bool: return player.is_falling(), 60), "walking over a pit makes the player fall")
	Input.action_release(&"move_right")
	_check(player.health.current == hp - 1, "a fall costs one heart (through the normal hit path)")
	_check(await _wait_until(func() -> bool: return not player.is_falling(), 60), "the fall ends")
	_check(not pit.contains_point(player.global_position) and main.world.is_safe_ground(player.global_position),
			"the player reappears on safe ground, not in the pit")
	_check(player.health.is_invulnerable(), "brief invulnerability after reappearing")
	_check(player.global_position.distance_to(arena) < 120.0, "respawn is the last safe spot near the edge")
	# Brushing the edge is forgiven: centre just outside the pit does not fall.
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 120)
	player.place_at(Vector2(pit_edge_x - 2.0, arena.y))
	await _frames(10)
	_check(not player.is_falling(), "standing right at the pit edge does not fall")
	return true


func _test_enemy_knocked_into_pit() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	_make_pit(main, 4, Vector2i(5, 6))
	var pit_edge_x := float((main.layout.entry_room().anchor.x + 4) * DungeonLayout.TILE_SIZE)
	var enemy := _spawn_test_enemy(main, Vector2(pit_edge_x - 12.0, arena.y), null)
	player.place_at(Vector2(pit_edge_x - 62.0, arena.y))
	player.facing = Vector2.RIGHT
	await _frames(2)
	await _press(&"attack")
	_check(await _wait_until(func() -> bool: return enemy.state == Enemy.State.DEAD, 60),
			"knocking an enemy into a pit kills it (pits are a tactic)")
	return true


func _test_walls_block_attacks() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	player.facing = Vector2.RIGHT
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 200)
	var node := CollisionShape2D.new()
	node.shape = shape
	wall.add_child(node)
	wall.position = arena + Vector2(30, 0)
	main.world.add_child(wall)
	var enemy := _spawn_test_enemy(main, arena + Vector2(62, 0), null)
	enemy.set_physics_process(false)
	enemy.health.current = 10
	await _frames(3)
	await _press(&"attack")
	await _frames(30)
	_check(enemy.health.current == 10, "the player cannot hit an enemy through a wall")
	# In reach (~54 px of the 72 px reach) but on the other side of the wall.
	var attacker := _spawn_test_enemy(main, arena + Vector2(50, 22), player)
	await _frames(1)
	attacker.set_physics_process(false)
	_check(attacker.global_position.distance_to(player.global_position) < attacker.melee.reach,
			"the blocked enemy is within its attack reach")
	attacker.melee.start((player.global_position - attacker.global_position).normalized())
	var hp := player.health.current
	await _frames(60)
	_check(player.health.current == hp, "an enemy cannot hit the player through a wall")
	wall.queue_free()
	await _frames(3)
	player.facing = Vector2.RIGHT
	await _frames(20)
	await _press(&"attack")
	await _frames(30)
	_check(enemy.health.current < 10, "with the wall gone, the same swing connects")
	return true


func _test_combat_near_walls() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var layout := main.layout
	var entry := layout.entry_room()
	# Stand one tile from the entry hall's west wall, facing it.
	var t := Vector2i(entry.origin.x + 2, entry.anchor.y)
	player.place_at(layout.tile_center(t))
	player.facing = Vector2.LEFT
	await _frames(2)
	await _press(&"attack")
	await _frames(20)
	Input.action_press(&"move_left")
	await _press(&"dodge")
	await _frames(15)
	Input.action_release(&"move_left")
	var now := layout.tile_at(player.global_position)
	_check(layout.is_walkable(now) and not DungeonLayout.is_solid_kind(layout.get_tile(now)),
			"attacking and dodging into a wall never tunnels through it")
	var enemy := _spawn_test_enemy(main, layout.tile_center(t + Vector2i(2, 0)), null)
	enemy.set_physics_process(true)
	player.facing = Vector2.RIGHT
	player.place_at(layout.tile_center(t + Vector2i(4, 0)))
	player.facing = Vector2.LEFT
	await _frames(2)
	await _press(&"attack")
	await _frames(25)
	var et := layout.tile_at(enemy.global_position)
	_check(layout.is_walkable(et), "knockback into a wall leaves the enemy on walkable floor")
	return true


## Finds the inner-sanctum variant (walled ring with two gaps) and checks an
## enemy outside the ring paths around the walls to reach the player inside.
func _test_enemy_pathfinding() -> bool:
	var profile := DepthProfile.load_for_depth(1)
	var chosen := -1
	for s in range(1, 300):
		for r in DungeonGenerator.new().generate(profile, s, 1).layout.rooms:
			if r.template.id == &"chamber_large" and r.variant == 1 and r.encounter == DungeonGraph.Encounter.NONE:
				chosen = s
		if chosen >= 0:
			break
	_check(chosen >= 0, "a seed with a peaceful inner sanctum exists (%d)" % chosen)
	if chosen < 0:
		return true
	var main := await _start_main(chosen)
	var player := _player(main)
	var layout := main.layout
	var sanctum: DungeonLayout.PlacedRoom = null
	for r in layout.rooms:
		if r.template.id == &"chamber_large" and r.variant == 1:
			sanctum = r
	player.health.grant_invulnerability(1000.0)
	player.place_at(layout.tile_center(sanctum.anchor))
	var start := layout.tile_center(sanctum.to_world(Vector2i(2, 2)))
	var nav := main.world.navigation
	_check(not nav.line_of_sight(start, player.global_position), "the ring wall blocks the straight line")
	_check(not nav.path(start, player.global_position).is_empty(), "navigation finds a path around the ring")
	var enemy := _spawn_test_enemy(main, start, player)
	enemy.navigator = nav
	enemy.engage(INF)
	var stuck_in_wall := [false]
	var reached := await _wait_until(func() -> bool:
		if not layout.is_walkable(layout.tile_at(enemy.global_position), true):
			stuck_in_wall[0] = true
		return enemy.global_position.distance_to(player.global_position) <= enemy.attack_range + 8.0, 900)
	_check(reached, "the enemy walks around the walls and reaches the player")
	_check(not stuck_in_wall[0], "the enemy never overlaps a wall tile on the way")
	return true


func _test_exploration_map() -> bool:
	var main := await _start_main()
	var hud := main.get_node("Hud") as Hud
	var layout := main.layout
	var entry_id := layout.graph.entry_id()
	hud.toggle_map(DungeonMap.Mode.EXPLORATION)
	var map := hud.map
	await _frames(1)
	var hidden := 0
	for room in layout.rooms:
		if room.id != entry_id and not map.is_room_shown(room.id):
			hidden += 1
	_check(map.is_room_shown(entry_id) and hidden == layout.rooms.size() - 1,
			"exploration map starts with only the entry room revealed (%d hidden)" % hidden)
	_check(map.shown_tile_count() < layout.size.x * layout.size.y / 5, "most of the floor is still hidden")
	var corridor := layout.corridors[0]
	var mid := corridor.rects[1].position + corridor.rects[1].size / 2
	_player(main).place_at(layout.tile_center(mid))
	await _frames(3)
	_check(map.is_corridor_shown(corridor.link), "walking a corridor reveals it")
	var other := layout.rooms[corridor.b] if corridor.a == entry_id else layout.rooms[corridor.a]
	_check(not map.is_room_shown(other.id) or other.id == entry_id, "the room beyond stays hidden until entered")
	_player(main).place_at(layout.tile_center(other.anchor))
	await _frames(3)
	_check(map.is_room_shown(other.id), "entering a room reveals it")
	hud.toggle_map(DungeonMap.Mode.DEBUG_FULL)
	var all_shown := true
	for room in layout.rooms:
		all_shown = all_shown and map.is_room_shown(room.id)
	_check(all_shown and map.mode == DungeonMap.Mode.DEBUG_FULL, "debug full map shows every room")
	hud.toggle_map(DungeonMap.Mode.DEBUG_FULL)
	_check(not hud.is_map_visible(), "the debug key closes the debug map")
	return true


func _test_tension_event() -> bool:
	var main := await _start_main()
	var world := main.world
	_check(world.event_triggers.size() == 1, "one tension/event socket is armed per floor")
	if world.event_triggers.is_empty():
		return true
	var trigger := world.event_triggers[0]
	_check(main.layout.is_clear(trigger.socket_tile), "the armed socket is on clear, safe floor")
	_player(main).health.grant_invulnerability(1000.0)
	_player(main).place_at(trigger.global_position)
	_check(await _wait_until(func() -> bool: return main.events_fired() == 1, 10), "the event fires when the player arrives")
	_check((main.get_node("Hud") as Hud).get_debug_event_text().contains("tension"), "the debug proof text is shown")
	_player(main).place_at(main.world.player_spawn)
	await _frames(3)
	_player(main).place_at(trigger.global_position)
	await _frames(5)
	_check(main.events_fired() == 1, "the event fires only once")
	return true


# --- tactical systems (Milestone 2.2) --------------------------------------------

func _test_archetypes() -> bool:
	var main := await _start_main()
	var ok := true
	for id: StringName in EnemyCatalog.ARCHETYPES:
		var enemy := EnemyCatalog.instantiate(id)
		ok = ok and enemy != null and EnemyCatalog.threat(id) > 0.0
		main.world.actors.add_child(enemy)
		await _frames(1)
		ok = ok and enemy.health.current > 0 and enemy.terrain != null
		enemy.queue_free()
	_check(ok, "every placeholder archetype (%s) instantiates with health, terrain and a threat value" % [EnemyCatalog.ARCHETYPES.keys()])
	return true


## Knockback threat + pit: the brute's blow throws the player into a chasm a
## chaser's blow would not. The composition logic ("chasm_brawl") relies on it.
func _test_brute_knockback_into_pit() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	_make_pit(main, 3, Vector2i(5, 7))
	var pit_edge_x := float((main.layout.entry_room().anchor.x + 3) * DungeonLayout.TILE_SIZE)
	var stand := Vector2(pit_edge_x - 56.0, arena.y)
	# Control: a chaser's hit only nudges the player.
	player.place_at(stand)
	var chaser := _spawn_test_enemy(main, stand + Vector2(-58, 0), player)
	var hp := player.health.current
	await _wait_until(func() -> bool: return player.health.current < hp, 180)
	await _frames(30)
	_check(player.health.current < hp and not player.is_falling() and player.global_position.x < pit_edge_x,
			"a chaser's hit near the edge does not throw the player into the chasm")
	chaser.queue_free()
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 120)
	player.place_at(stand)
	var brute := EnemyCatalog.instantiate(&"brute")
	brute.position = stand + Vector2(-66, 0)
	brute.target = player
	main.world.actors.add_child(brute)
	var fell := await _wait_until(func() -> bool: return player.is_falling(), 240)
	_check(fell, "the brute's knockback throws the player into the chasm (knockback threat + pit)")
	await _wait_until(func() -> bool: return not player.is_falling(), 60)
	_check(main.world.is_safe_ground(player.global_position), "after the fall the player is back on safe ground")
	return true


## Ranged pressure + cover: the spitter telegraphs, fires a slow shot that
## hurts the player in the open and is stopped by a wall; it backs away when
## the player closes in.
func _test_spitter_projectile() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	var spitter := EnemyCatalog.instantiate(&"spitter") as Spitter
	spitter.position = arena + Vector2(-240, 0)
	spitter.target = player
	main.world.actors.add_child(spitter)
	var hp := player.health.current
	_check(await _wait_until(func() -> bool: return spitter.state == Enemy.State.ATTACK, 120), "the spitter starts a telegraphed shot")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 150), "its projectile hurts a player standing in the open")
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 120)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 240)
	var node := CollisionShape2D.new()
	node.shape = shape
	wall.add_child(node)
	wall.position = (spitter.global_position + player.global_position) / 2.0
	main.world.add_child(wall)
	hp = player.health.current
	var shots_seen := [0]
	var watcher := func(n: Node) -> void:
		if n is EnemyProjectile:
			shots_seen[0] += 1
	main.world.actors.child_entered_tree.connect(watcher)
	await _wait_until(func() -> bool: return shots_seen[0] >= 2, 300)
	await _frames(60)
	_check(shots_seen[0] >= 2 and player.health.current == hp, "shots are stopped by a wall (cover works) (%d shots, hp %d -> %d, spitter at %s, player at %s, wall at %s)" % [
		shots_seen[0], hp, player.health.current, spitter.global_position, player.global_position, wall.position])
	wall.queue_free()
	player.place_at(spitter.global_position + Vector2(70, 0))
	var before := spitter.global_position.distance_to(player.global_position)
	await _frames(40)
	_check(spitter.global_position.distance_to(player.global_position) > before + 10.0, "the spitter backs away when the player closes in")
	return true


## Ranged enemy + chasm ("sniper_nest"): the spitter sees and shoots across a
## pit (sight is blocked only by solids) although it cannot walk across, so it
## holds its side instead of walking around.
func _test_spitter_shoots_across_chasm() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	_make_pit(main, 2, Vector2i(3, 9))
	var navigation := DungeonNavigation.new(main.layout)  # built after the pit exists
	player.place_at(arena)
	var spitter := EnemyCatalog.instantiate(&"spitter") as Spitter
	spitter.position = arena + Vector2(8 * DungeonLayout.TILE_SIZE, 0)
	spitter.target = player
	spitter.navigator = navigation
	main.world.actors.add_child(spitter)
	_check(not navigation.line_of_sight(spitter.position, arena) and navigation.clear_sight(spitter.position, arena),
			"the chasm blocks walking but not sight")
	var start := spitter.position
	var hp := player.health.current
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 240),
			"the spitter shoots the player across the chasm")
	_check(spitter.global_position.distance_to(start) < 48.0,
			"it holds its side of the chasm instead of walking around (moved %d px)" % spitter.global_position.distance_to(start))
	return true


## Body pressure: touching an active enemy hurts (1 damage through the normal
## Hitbox -> Hurtbox path), shoves the player away, and the invulnerability
## that follows stops rapid repeat damage. A staggered enemy is safe to touch.
func _test_contact_damage() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	var chaser := _spawn_test_enemy(main, arena + Vector2(120, 0), player)
	await _frames(1)
	chaser.melee.set_cooldown_remaining(999.0)  # its body only: it never swings
	chaser.engage()
	var hp := player.health.current
	var hit := await _wait_until(func() -> bool: return player.health.current < hp, 300)
	var hit_at := player.global_position
	_check(hit and player.health.current == hp - 1, "an active enemy's body hurts on contact (1 damage)")
	await _frames(8)
	var shove := player.global_position.distance_to(hit_at)
	_check(shove > 10.0, "contact shoves the player away from the body (%d px)" % shove)
	await _frames(30)
	_check(player.health.current == hp - 1, "invulnerability prevents rapid repeated contact damage")
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 60)
	var contact := chaser.get_node("ContactDamage") as ContactDamage
	player.place_at(chaser.global_position + Vector2(-50, 0))
	player.facing = Vector2.RIGHT
	await _press(&"attack")
	var staggered := await _wait_until(func() -> bool: return chaser.state == Enemy.State.HURT, 20)
	await _frames(1)
	_check(staggered and not chaser.is_body_dangerous() and not contact.armed,
			"a staggered enemy's body is safe to touch (readable opening)")
	return true


## Four bodies touching the player on the same frame cost one hit, not four.
func _test_contact_never_stacks() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	var hp := player.health.current
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var chaser := _spawn_test_enemy(main, arena + dir * 35.0, player)
		chaser.ready.connect(func() -> void: chaser.melee.set_cooldown_remaining(999.0))
	await _frames(1)
	for enemy in main.get_tree().get_nodes_in_group(&"enemies"):
		(enemy as Enemy).engage()
	var hit := await _wait_until(func() -> bool: return player.health.current < hp, 30)
	await _frames(20)
	_check(hit and player.health.current == hp - 1,
			"4 enemies touching at once deal exactly 1 contact hit (hp %d -> %d)" % [hp, player.health.current])
	return true


## A dodge's invulnerability covers contact: dodging into a body costs nothing
## while the i-frames last.
func _test_dodge_ignores_contact() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	player.facing = Vector2.RIGHT
	var chaser := _spawn_test_enemy(main, arena + Vector2(70, 0), player)
	await _frames(1)
	chaser.melee.set_cooldown_remaining(999.0)
	var hp := player.health.current
	await _press(&"dodge")
	var touched := false
	var hurt_during_dodge := false
	for i in 14:
		await physics_frame
		if player.health.is_invulnerable():
			touched = touched or player.global_position.distance_to(chaser.global_position) < 40.0
			hurt_during_dodge = hurt_during_dodge or player.health.current < hp
	_check(touched and not hurt_during_dodge, "dodging into an active enemy's body costs nothing during the i-frames")
	return true


## Stagger guard: swinging non-stop is no longer a stun-lock. The enemy is
## interrupted once, then fights through the hits (gold spark) and strikes.
func _test_stagger_guard() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	player.facing = Vector2.RIGHT
	player.health.grant_invulnerability(100.0)
	var chaser := _spawn_test_enemy(main, arena + Vector2(62, 0), player)
	await _frames(1)
	chaser.health.max_health = 99
	chaser.health.current = 99
	chaser.engage()
	var strikes := [0]
	chaser.melee.strike_started.connect(func() -> void: strikes[0] += 1)
	var guarded_seen := false
	var staggered_seen := false
	for i in 150:
		if i % 21 == 0:
			player.place_at(chaser.global_position + Vector2(-56, 0))
			player.facing = Vector2.RIGHT
			Input.action_press(&"attack")
		elif i % 21 == 1:
			Input.action_release(&"attack")
		await physics_frame
		staggered_seen = staggered_seen or chaser.state == Enemy.State.HURT
		guarded_seen = guarded_seen or chaser.is_stagger_guarded()
	_check(staggered_seen and guarded_seen, "the first hit staggers, then the stagger guard holds")
	_check(strikes[0] >= 1, "an enemy hit every 0.35 s still gets its attack off (%d strikes in 2.5 s)" % strikes[0])
	return true


## The brute's windup is armored: a hit lands but does not cancel the blow.
func _test_brute_windup_armor() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	player.health.grant_invulnerability(100.0)
	var brute := EnemyCatalog.instantiate(&"brute")
	brute.position = arena + Vector2(70, 0)
	brute.target = player
	main.world.actors.add_child(brute)
	brute.engage()
	var winding := await _wait_until(func() -> bool: return brute.melee.phase == MeleeAttack.Phase.WINDUP, 120)
	var hp := brute.health.current
	player.facing = (brute.global_position - player.global_position).normalized()
	await _press(&"attack")
	await _wait_until(func() -> bool: return brute.health.current < hp, 20)
	_check(winding and brute.health.current < hp and brute.melee.phase != MeleeAttack.Phase.IDLE
			and brute.state == Enemy.State.ATTACK, "a hit during the brute's windup damages it but does not cancel the blow")
	return true


## Crowd steering: a group arriving from one side fans out around the player
## instead of queueing in front of one swing, and bodies never stack.
func _test_crowd_surrounds() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	player.health.grant_invulnerability(100.0)
	var group: Array[Enemy] = []
	for i in 4:
		var chaser := _spawn_test_enemy(main, arena + Vector2(170 + 36 * (i % 2), -40 + 26 * i), player)
		chaser.flank_sign = 1.0 if i % 2 == 0 else -1.0
		group.append(chaser)
	await _frames(1)
	for chaser in group:
		chaser.engage()
	await _frames(180)
	var spread := _angular_spread(arena, group)
	var closest := INF
	for i in group.size():
		for j in range(i + 1, group.size()):
			closest = minf(closest, group[i].global_position.distance_to(group[j].global_position))
	_check(spread >= 150.0, "4 chasers arriving from one side spread around the player (%d deg covered)" % spread)
	_check(closest >= 28.0, "enemy bodies never stack (closest pair %d px)" % closest)
	return true


## Degrees around `center` covered by `actors` (360 minus the largest gap).
func _angular_spread(center: Vector2, actors: Array[Enemy]) -> float:
	var angles: Array[float] = []
	for actor in actors:
		angles.append(rad_to_deg((actor.global_position - center).angle()))
	angles.sort()
	var largest_gap := 360.0 - (angles[angles.size() - 1] - angles[0])
	for i in range(1, angles.size()):
		largest_gap = maxf(largest_gap, angles[i] - angles[i - 1])
	return 360.0 - largest_gap


## Representative group fight on real navigation: 2 chasers + 1 spitter
## against a player who stands still and keeps swinging at the nearest enemy.
## Every archetype attacks, the player is hurt (standing in a group is
## dangerous), bodies never stack. Control: the same player beats a single
## chaser cleanly (still powerful one-on-one).
func _test_group_pressure() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var arena := _arena(main)
	player.place_at(arena)
	var group: Array[Enemy] = []
	# Spread like a room's spawn points (SpawnPlanner places them apart).
	var spots: Array[Vector2] = [Vector2(190, -90), Vector2(-90, 150), Vector2(-250, -40)]
	var ids: Array[StringName] = [&"chaser", &"chaser", &"spitter"]
	for i in 3:
		var enemy := EnemyCatalog.instantiate(ids[i])
		enemy.position = arena + spots[i]
		enemy.target = player
		enemy.navigator = main.world.navigation
		enemy.flank_sign = 1.0 if i % 2 == 0 else -1.0
		main.world.actors.add_child(enemy)
		group.append(enemy)
	for enemy in group:
		enemy.engage()
	var strikes := {}
	for enemy in group:
		var id := ids[group.find(enemy)]
		enemy.melee.strike_started.connect(func() -> void: strikes[id] = strikes.get(id, 0) + 1)
	var hp := player.health.current
	var closest := INF
	var reached := 0
	for i in 600:
		if i % 20 == 0:
			var nearest := _nearest_alive(player, group)
			if nearest != null:
				player.facing = (nearest.global_position - player.global_position).normalized()
				Input.action_press(&"attack")
		elif i % 20 == 1:
			Input.action_release(&"attack")
		await physics_frame
		if player.is_dead() or _nearest_alive(player, group) == null:
			break
		for a in group.size():
			if not is_instance_valid(group[a]) or group[a].state == Enemy.State.DEAD:
				continue
			for b in range(a + 1, group.size()):
				if is_instance_valid(group[b]) and group[b].state != Enemy.State.DEAD:
					closest = minf(closest, group[a].global_position.distance_to(group[b].global_position))
	_check(strikes.get(&"chaser", 0) >= 1 and strikes.get(&"spitter", 0) >= 1,
			"chasers and the spitter all attack in a group fight (%s)" % strikes)
	_check(player.health.current <= hp - 2,
			"standing still in a group is dangerous (hp %d -> %d by the end of the fight)" % [hp, player.health.current])
	_check(closest >= 28.0, "group bodies never stack (closest pair %d px)" % closest)
	Main.release_gameplay_actions()
	# Clear the group and any spitter shot still in flight before the one-on-one.
	for node in main.world.actors.get_children():
		if node is Enemy or node is EnemyProjectile:
			node.queue_free()
	await _frames(2)
	player.health.heal(99)
	await _wait_until(func() -> bool: return not player.health.is_invulnerable(), 60)
	hp = player.health.current
	var solo := _spawn_test_enemy(main, player.global_position + Vector2(150, 0), player)
	await _frames(1)
	solo.engage()
	for i in 240:
		if is_instance_valid(solo) and solo.state != Enemy.State.DEAD \
				and solo.global_position.distance_to(player.global_position) < 105.0 and i % 20 == 0:
			player.facing = (solo.global_position - player.global_position).normalized()
			Input.action_press(&"attack")
		elif i % 20 == 1:
			Input.action_release(&"attack")
		await physics_frame
		if not is_instance_valid(solo) or solo.state == Enemy.State.DEAD:
			break
	_check(not is_instance_valid(solo) or solo.state == Enemy.State.DEAD,
			"one-on-one, the same swinging player still beats a chaser")
	_check(player.health.current >= hp - 1, "and takes at most one hit doing it (hp %d -> %d)" % [hp, player.health.current])
	return true


func _nearest_alive(player: Player, group: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	for enemy in group:
		if is_instance_valid(enemy) and enemy.state != Enemy.State.DEAD and (best == null
				or enemy.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = enemy
	return best


## Dungeon density in the built world: all decor is one cosmetic node, room
## structure and collapsed corridor alcoves are solid, nooks are walkable.
func _test_density_built() -> bool:
	var main := await _start_main()
	var decor := main.world.get_node_or_null("Decor") as DecorLayer
	_check(decor != null and not main.layout.decor.is_empty(), "the floor's decor is drawn by one node (%d items)" % main.layout.decor.size())
	_check(decor != null and decor.get_child_count() == 0, "decor adds no child nodes or collision")
	var space := main.world.get_world_2d().direct_space_state
	var solid := 0
	var pieces := 0
	for room in main.layout.rooms:
		for piece in room.dressing:
			pieces += 1
			var query := PhysicsPointQueryParameters2D.new()
			query.position = main.layout.tile_center(piece.tiles[0])
			query.collision_mask = 1
			solid += int(not space.intersect_point(query).is_empty())
	_check(pieces > 0 and solid == pieces, "room structure is solid where it was placed (%d/%d)" % [solid, pieces])
	var rubble := 0
	var rubble_solid := 0
	var nook := 0
	var nook_open := 0
	for corridor in main.layout.corridors:
		for alcove in corridor.alcoves:
			for t: Vector2i in alcove.rubble:
				var query := PhysicsPointQueryParameters2D.new()
				query.position = main.layout.tile_center(t)
				query.collision_mask = 1
				rubble += 1
				rubble_solid += int(not space.intersect_point(query).is_empty())
			for t: Vector2i in alcove.tiles:
				var query := PhysicsPointQueryParameters2D.new()
				query.position = main.layout.tile_center(t)
				query.collision_mask = 1
				nook += 1
				nook_open += int(space.intersect_point(query).is_empty())
	_check(rubble == rubble_solid and nook == nook_open and nook > 0,
			"collapsed alcoves are solid (%d/%d), recesses are walkable (%d/%d)" % [rubble_solid, rubble, nook_open, nook])
	return true


## Enemy + spikes: raised spikes hurt enemies too, so baiting works.
func _test_spikes_hurt_enemies() -> bool:
	var main := await _start_main()
	var arena := _arena(main)
	var enemy := _spawn_test_enemy(main, arena + Vector2(160, 0), null)
	await _frames(1)
	enemy.set_physics_process(false)
	var tile := main.layout.tile_at(enemy.global_position)
	var trap := SpikeTrap.new()
	var tiles: Array[Vector2i] = [tile]
	trap.setup(tiles, 0.0)
	main.world.add_child(trap)
	var hp := enemy.health.current
	_check(await _wait_until(func() -> bool: return enemy.health.current < hp, 240), "raised spikes damage an enemy standing on them (bait)")
	return true


## Ambush + alternate route: the encounter starts mid-room but no gate closes,
## so the player can retreat through a doorway.
func _test_ambush_room() -> bool:
	var chosen := _seed_with(2, func(r: DungeonLayout.PlacedRoom) -> bool: return r.tactic == RoomRole.AMBUSH)
	_check(chosen >= 0, "a depth 2 seed with an ambush room exists (%d)" % chosen)
	if chosen < 0:
		return true
	var main := await _start_main(chosen, 2)
	var player := _player(main)
	player.health.grant_invulnerability(1000.0)
	var room: DungeonRoom = null
	for candidate in main.world.rooms:
		if candidate.data.tactic == RoomRole.AMBUSH:
			room = candidate
	_check(room.gates.is_empty() and room.data.doors.size() >= 2 and not room.locks_doors(),
			"an ambush room has no gates and at least two doorways")
	var door: Dictionary = room.data.doors[0]
	# Where a player walking in through this doorway first touches the trigger.
	var inward: Vector2i = -RoomShape.SIDE_VECTORS[door.side]
	var trigger_point := main.layout.tile_center(door.inside + inward)
	player.place_at(trigger_point)
	_check(await _wait_until(func() -> bool: return room.state == DungeonRoom.EncounterState.ACTIVE, 20), "the ambush triggers inside the room")
	_check(await _wait_until(func() -> bool: return room.enemies.size() == room.data.enemy_ids.size(), 90), "ambushers appear after the telegraph")
	var nearest := INF
	var leashed := true
	for enemy in room.enemies:
		nearest = minf(nearest, enemy.home_position.distance_to(trigger_point))
		leashed = leashed and enemy.leash_range < INF
	_check(nearest >= DungeonValidator.MIN_SPAWN_DISTANCE - 1.0 and leashed,
			"ambushers spawn away from the player (nearest %.0f px) and keep a leash (running away is possible)" % nearest)
	_check((main.get_node("Hud") as Hud).get_status().begins_with("ENCOUNTER"), "HUD shows the ambush")
	var probe := _make_probe()
	probe.global_position = main.layout.tile_center(door.inside)
	await _frames(2)
	_check(not probe.test_move(probe.global_transform, Vector2(RoomShape.SIDE_VECTORS[door.side]) * DungeonLayout.TILE_SIZE * 3.0),
			"the doorway stays open during the ambush")
	probe.queue_free()
	return true


## Resource hook: a recovery shrine heals once, and is not wasted at full health.
func _test_heal_shrine() -> bool:
	var chosen := _seed_with(1, func(r: DungeonLayout.PlacedRoom) -> bool: return r.tactic == RoomRole.REST)
	_check(chosen >= 0, "a depth 1 seed with a rest room exists (%d)" % chosen)
	if chosen < 0:
		return true
	var main := await _start_main(chosen)
	var player := _player(main)
	var shrine: RoomMarker = null
	for marker in main.world.markers:
		if marker.kind == &"heal":
			shrine = marker
	_check(shrine != null, "the rest room has a recovery shrine")
	player.place_at(shrine.global_position)
	await _frames(3)
	_check(not shrine.is_collected and player.health.is_full(), "at full health the shrine is not used up")
	player.place_at(main.world.player_spawn)
	await _frames(3)
	player.health.take_damage(2)
	var hp := player.health.current
	player.place_at(shrine.global_position)
	await _frames(3)
	_check(shrine.is_collected and player.health.current == hp + 1, "touching the shrine when hurt restores one heart")
	return true


## Risk / reward: the cache sits behind a visible risk (spikes) and is optional.
func _test_risk_cache() -> bool:
	var chosen := _seed_with(2, func(r: DungeonLayout.PlacedRoom) -> bool: return r.tactic == RoomRole.RISK_REWARD)
	_check(chosen >= 0, "a depth 2 seed with a risk room exists (%d)" % chosen)
	if chosen < 0:
		return true
	var main := await _start_main(chosen, 2)
	var layout := main.layout
	var risk: DungeonLayout.PlacedRoom = null
	for room in layout.rooms:
		if room.tactic == RoomRole.RISK_REWARD:
			risk = room
	var crosses := false
	for t in risk.risk_route:
		crosses = crosses or risk.risk_tiles().has(t)
	_check(crosses, "the risky route to the cache crosses the visible spikes")
	_check(DungeonValidator.flood(layout, DungeonValidator.required_mask(layout), layout.player_spawn)[layout.index_of(layout.exit_tile)] == 1,
			"the exit is reachable without ever touching the risk")
	var cache: RoomMarker = null
	for marker in main.world.markers:
		if marker.kind == &"cache":
			cache = marker
	_player(main).health.grant_invulnerability(1000.0)
	_player(main).place_at(cache.global_position)
	await _frames(3)
	_check(cache.is_collected, "the cache can be claimed")
	return true


## Developer views: the tactical overlay (F4 / TAC) and the debug map show the
## design data; the player map does not.
func _test_tactical_debug_views() -> bool:
	var main := await _start_main(TEST_SEED, 3)
	var hud := main.get_node("Hud") as Hud
	_check(OS.is_debug_build() and (hud.get_node("TopButtons/TacticsButton") as Button).visible,
			"the TAC button is offered in debug builds")
	_check(not main.is_tactical_overlay_visible(), "the tactical overlay starts hidden")
	var event := InputEventAction.new()
	event.action = &"toggle_tactical_overlay"
	event.pressed = true
	root.push_input(event)
	await _frames(2)
	_check(main.is_tactical_overlay_visible(), "F4 shows the tactical overlay")
	hud.press_button("TopButtons/TacticsButton")
	_check(not main.is_tactical_overlay_visible(), "TAC hides it again")
	var notes := 0
	for room in main.layout.rooms:
		if not room.design_note.is_empty():
			notes += 1
	_check(notes == main.layout.rooms.size(), "every room carries a design note (the decision it asks for)")
	hud.toggle_map(DungeonMap.Mode.EXPLORATION)
	_check(hud.map._room_tag(main.layout.rooms[main.layout.graph.main_path[1]]) == "",
			"the player map does not reveal room roles")
	hud.toggle_map(DungeonMap.Mode.DEBUG_FULL)
	_check(hud.map._room_tag(main.layout.entry_room()).begins_with("ENTRY"), "the debug map labels room roles")
	return true


func _test_depth_completion() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var hud := main.get_node("Hud") as Hud
	var fingerprint := main.layout.fingerprint()
	_check(not main.world.depth_exit.sealed, "depth 1 exit is open (profile has no objective encounter)")
	player.place_at(main.layout.tile_center(main.layout.exit_tile))
	_check(await _wait_until(func() -> bool: return main.is_completed(), 10), "stepping on the exit completes the depth")
	_check(not (main.get_node("MobileControls") as MobileControls).is_active() and not player.controls_enabled,
			"controls stop after completion")
	_check(await _wait_until(func() -> bool: return hud.is_complete_screen_visible(), 60), "completion screen appears")
	await _wait_until(func() -> bool: return not (hud.get_node("CompleteScreen/Panel/Buttons/ReplayButton") as Button).disabled, 60)
	var new_main := await _press_and_reload(hud, "CompleteScreen/Panel/Buttons/ReplayButton", main)
	_check(new_main != null and new_main.run_seed == TEST_SEED and new_main.depth == 1
			and new_main.layout.fingerprint() == fingerprint, "REPLAY SEED rebuilds the identical dungeon")
	return true


func _test_next_depth_sealed_exit() -> bool:
	var main := await _start_main()
	var hud := main.get_node("Hud") as Hud
	_player(main).place_at(main.layout.tile_center(main.layout.exit_tile))
	await _wait_until(func() -> bool: return hud.is_complete_screen_visible(), 60)
	await _wait_until(func() -> bool: return not (hud.get_node("CompleteScreen/Panel/Buttons/NextButton") as Button).disabled, 60)
	_check((hud.get_node("CompleteScreen/Panel/Buttons/NextButton") as Button).visible, "NEXT DEPTH offered when a profile exists")
	var next := await _press_and_reload(hud, "CompleteScreen/Panel/Buttons/NextButton", main)
	_check(next != null and next.depth == 2 and next.run_seed == TEST_SEED, "NEXT DEPTH keeps the run seed and loads depth 2")
	if next == null:
		return true
	var player := _player(next)
	var objective := next.world.get_room(next.layout.graph.objective_id())
	_check(next.world.depth_exit.sealed and objective.has_encounter(), "depth 2 exit is sealed by an objective encounter")
	player.health.grant_invulnerability(1000.0)
	var door: Dictionary = objective.data.doors[0]
	player.place_at(_room_entry_point(next.layout, objective.data, door))
	await _wait_until(func() -> bool: return objective.enemies.size() == objective.data.enemy_ids.size(), 90)
	player.place_at(next.layout.tile_center(next.layout.exit_tile))
	await _frames(10)
	_check(not next.is_completed(), "a sealed exit does not complete the depth")
	for enemy in objective.enemies.duplicate():
		enemy.health.take_damage(99)
	await _frames(3)
	_check(not next.world.depth_exit.sealed, "clearing the objective encounter unseals the exit")
	_check(await _wait_until(func() -> bool: return next.is_completed(), 10), "standing on the unsealed exit completes the depth")
	var next_hud := next.get_node("Hud") as Hud
	await _wait_until(func() -> bool: return next_hud.is_complete_screen_visible(), 60)
	_check((next_hud.get_node("CompleteScreen/Panel/Buttons/NextButton") as Button).visible,
			"depth 2 offers NEXT DEPTH (depth 3 test profile exists)")
	# The last test depth: completing it offers no further depth.
	next.queue_free()
	await process_frame
	var last := await _start_main(TEST_SEED, 3)
	var last_player := _player(last)
	last_player.health.grant_invulnerability(1000.0)
	var final_room := last.world.get_room(last.layout.graph.objective_id())
	last_player.place_at(_room_entry_point(last.layout, final_room.data, final_room.data.doors[0]))
	await _wait_until(func() -> bool: return final_room.enemies.size() == final_room.data.enemy_ids.size(), 90)
	for enemy in final_room.enemies.duplicate():
		enemy.health.take_damage(99)
	await _frames(3)
	last_player.place_at(last.layout.tile_center(last.layout.exit_tile))
	var last_hud := last.get_node("Hud") as Hud
	await _wait_until(func() -> bool: return last_hud.is_complete_screen_visible(), 90)
	_check(last.is_completed() and not (last_hud.get_node("CompleteScreen/Panel/Buttons/NextButton") as Button).visible,
			"no NEXT DEPTH after the last test depth (finite test campaign)")
	return true


func _test_seed_entry_and_new_seed() -> bool:
	var main := await _start_main()
	var hud := main.get_node("Hud") as Hud
	var base_fingerprint := main.layout.fingerprint()
	hud.open_seed_panel()
	hud.seed_panel.set_entry_text("crypt")
	var expected := RunConfig.parse_seed_text("crypt")
	var crypt := await _press_and_reload(hud, "SeedPanel/Panel/Box/Row1/PlayButton", main)
	_check(crypt != null and crypt.run_seed == expected and crypt.depth == 1, "PLAY THIS SEED starts the entered seed")
	if crypt == null:
		return true
	_check(crypt.layout.fingerprint() != base_fingerprint, "a different seed gives a different dungeon")
	var crypt_fingerprint := crypt.layout.fingerprint()
	var crypt_hud := crypt.get_node("Hud") as Hud
	crypt_hud.open_seed_panel()
	var again := await _press_and_reload(crypt_hud, "SeedPanel/Panel/Box/Row1/ReplayButton", crypt)
	_check(again != null and again.run_seed == expected and again.layout.fingerprint() == crypt_fingerprint,
			"RESTART CURRENT keeps the entered seed and dungeon")
	if again == null:
		return true
	var again_hud := again.get_node("Hud") as Hud
	again_hud.open_seed_panel()
	var fresh := await _press_and_reload(again_hud, "SeedPanel/Panel/Box/Row2/NewButton", again)
	_check(fresh != null and fresh.run_seed != expected, "NEW SEED picks a different seed")
	return true


func _test_seed_panel_pauses() -> bool:
	var main := await _start_main()
	var hud := main.get_node("Hud") as Hud
	var controls := main.get_node("MobileControls") as MobileControls
	hud.open_seed_panel()
	_check(paused and hud.is_seed_panel_open() and not controls.is_active(), "seed panel pauses the game and hides touch controls")
	hud.seed_panel.close()
	_check(not paused and controls.is_active(), "closing the seed panel resumes the game")
	return true


func _test_death_restart() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var fingerprint := main.layout.fingerprint()
	player.health.take_damage(99)
	_check(player.state == Player.State.DEAD, "zero health -> player DEAD")
	var pos := player.global_position
	Input.action_press(&"move_right")
	await _press(&"attack")
	await _frames(10)
	_check(player.global_position == pos and not player.melee.is_busy(), "dead player cannot move or attack")
	_check(not (main.get_node("MobileControls") as MobileControls).is_active(), "touch controls hidden on death")
	var hud := main.get_node("Hud") as Hud
	_check(await _wait_until(func() -> bool: return hud.is_death_screen_visible(), 90), "death screen appears")
	var retry := hud.get_node("DeathScreen/Panel/Buttons/RetryButton") as Button
	await _wait_until(func() -> bool: return not retry.disabled, 60)
	Input.action_press(&"move_right")  # a held input must not leak across the restart
	var new_main := await _press_and_reload(hud, "DeathScreen/Panel/Buttons/RetryButton", main)
	_check(new_main != null, "RETRY reloads the scene")
	if new_main == null:
		return true
	var new_player := _player(new_main)
	_check(new_player.state == Player.State.NORMAL and new_player.health.current == new_player.health.max_health,
			"restarted player is alive with full health")
	_check(new_main.run_seed == TEST_SEED and new_main.layout.fingerprint() == fingerprint,
			"RETRY keeps the same seed and dungeon")
	_check(not Input.is_action_pressed(&"move_right"), "restart clears held inputs")
	_check((new_main.get_node("MobileControls") as MobileControls).is_active(), "touch controls visible after restart")
	return true


# --- helpers -------------------------------------------------------------------

func _start_main(seed_value: int = TEST_SEED, depth: int = 1) -> Main:
	RunConfig.set_run(seed_value, depth)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	root.add_child(main)
	current_scene = main
	await _frames(2)
	return main


## Presses a HUD button that reloads the scene; returns the new Main (or null).
func _press_and_reload(hud: Hud, button_path: String, old_main: Main) -> Main:
	var old_id := old_main.get_instance_id()
	hud.press_button(button_path)
	var reloaded := await _wait_until(func() -> bool:
			return current_scene != null and current_scene.get_instance_id() != old_id, 30)
	if not reloaded:
		return null
	await _frames(2)
	return current_scene as Main


func _player(main: Main) -> Player:
	return main.get_node("Player") as Player


## Centre of the entry hall (a safe 24x14-tile arena).
func _arena(main: Main) -> Vector2:
	return main.world.player_spawn


func _spawn_test_enemy(main: Main, at: Vector2, target: Player) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.position = at
	enemy.target = target
	main.world.actors.add_child(enemy)
	return enemy


## Where walking in through `door` triggers the room (SpawnPlanner.entry_point,
## the point generation validates spawns from) if it is clear; otherwise the
## first clear tile at least 3 tiles in (interior geometry may put a pillar,
## water or a wall straight ahead), as a pixel position.
func _room_entry_point(layout: DungeonLayout, data: DungeonLayout.PlacedRoom, door: Dictionary) -> Vector2:
	var trigger := SpawnPlanner.entry_point(layout, door)
	if layout.room_at_tile(layout.tile_at(trigger)) == data and layout.is_clear(layout.tile_at(trigger)):
		return trigger
	var inward: Vector2i = -RoomShape.SIDE_VECTORS[door.side]
	var inside: Vector2i = door.inside
	var side_step := Vector2i(inward.y, inward.x)
	for depth in range(3, 9):
		for offset in [0, 1, -1, 2, -2, 3, -3]:
			var t: Vector2i = inside + inward * depth + side_step * offset
			if layout.room_at_tile(t) == data and layout.is_clear(t):
				return layout.tile_center(t)
	return layout.tile_center(data.anchor)


## First seed (scan from 1) whose floor at `depth` has a room matching `test`.
func _seed_with(depth: int, test: Callable) -> int:
	var profile := DepthProfile.load_for_depth(depth)
	for s in range(1, 300):
		for room in DungeonGenerator.new().generate(profile, s, depth).layout.rooms:
			if test.call(room):
				return s
	return -1


func _first_main_combat_room(main: Main) -> DungeonRoom:
	for id in main.layout.graph.main_path:
		var room := main.world.get_room(id)
		if room.data.encounter == DungeonGraph.Encounter.COMBAT:
			return room
	return null


## Player-sized physics probe for test_move checks against world collision.
func _make_probe() -> CharacterBody2D:
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = 1
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var node := CollisionShape2D.new()
	node.shape = shape
	probe.add_child(node)
	current_scene.add_child(probe)
	return probe


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
