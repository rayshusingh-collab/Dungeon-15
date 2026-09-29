extends SceneTree
## Headless smoke/integration tests. Exits with code 1 on any failure.
## Run: godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
## (--fixed-fps makes every frame exactly 1/60 s, so timings are deterministic.)
## These prove wiring and rules, not game feel.

const MAIN_SCENE := "res://src/main/main.tscn"
const ENEMY_SCENE := "res://src/enemies/enemy.tscn"
const ROOM_SCENES: Array[String] = ["res://src/rooms/room.tscn", "res://src/rooms/room_pillars.tscn"]
const ALL_SCENES: Array[String] = [
	"res://src/main/main.tscn", "res://src/player/player.tscn", "res://src/enemies/enemy.tscn",
	"res://src/rooms/room.tscn", "res://src/rooms/room_pillars.tscn", "res://src/rooms/exit_door.tscn",
	"res://src/ui/hud.tscn", "res://src/ui/mobile_controls.tscn",
]

var _failures: int = 0
var _checks: int = 0
var _errors := ErrorCounter.new()


## Counts every engine/script error or warning logged while tests run, so a
## script error that silently aborts a test coroutine still fails the suite.
class ErrorCounter extends Logger:
	var count: int = 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		count += 1
		_mutex.unlock()

	func get_count() -> int:
		_mutex.lock()
		var value := count
		_mutex.unlock()
		return value


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var tests: Array[Callable] = [
		_test_scenes_load, _test_health_component, _test_movement, _test_touch_controls,
		_test_attack, _test_combat_feel, _test_dodge, _test_enemy_states, _test_enemy_attack,
		_test_enemy_attack_motion, _test_spawning,
		_test_room_flow, _test_death_restart,
	]
	for test in tests:
		print("== ", test.get_method())
		var errors_before := _errors.get_count()
		# Tests return true on completion; null means a script error aborted it.
		var completed: Variant = await test.call()
		_check(completed == true, "%s ran to completion" % test.get_method())
		Main.release_gameplay_actions()
		await _free_current_scene()
		var new_errors := _errors.get_count() - errors_before
		_check(new_errors == 0, "%s logged no engine/script errors or warnings (%d)" % [test.get_method(), new_errors])
		_check(is_equal_approx(Engine.time_scale, 1.0), "%s left Engine.time_scale at 1.0" % test.get_method())
	print("SMOKE TEST: %s (%d checks, %d failure(s))" % ["OK" if _failures == 0 else "FAILED", _checks, _failures])
	OS.remove_logger(_errors)
	quit(1 if _failures > 0 else 0)


# --- tests -------------------------------------------------------------------

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


func _test_movement() -> bool:
	var main := await _start_main()
	var player := _player(main)
	_freeze_enemies(main)
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
	_freeze_enemies(main)
	var joystick := main.get_node("MobileControls/VirtualJoystick") as Control
	var attack_button := main.get_node("MobileControls/AttackButton") as TouchActionButton
	var dodge_button := main.get_node("MobileControls/DodgeButton") as TouchActionButton
	var center := joystick.get_global_rect().get_center()
	_touch(0, center, true)
	_drag(0, center + Vector2(70, 0))
	await _frames(3)
	_check(Input.get_action_strength(&"move_right") > 0.0, "joystick drag presses move_right")
	_check(player.velocity.x > 0.0, "joystick drag moves the player")
	# Simultaneous action while the stick is held (touch index 1).
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
	_clear_enemies(main)
	await _frames(1)
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
	# Cooldown: a second press during the cooldown (beyond the buffer) is ignored.
	await _press(&"attack")
	await _frames(2)
	await _press(&"attack")
	await _frames(15)
	_check(strikes[0] == 2, "attack cannot be spammed faster than its cooldown (%d strikes)" % strikes[0])
	await _frames(20)
	# Direction: an enemy behind the player is not hit.
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
	_clear_enemies(main)
	await _frames(1)
	# Anticipation and forward step, with nothing to hit.
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
	# Damage frame, knockback direction, hit-stop, kill feedback.
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
	# Killing blow: the body slides with the hit.
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


func _test_enemy_attack_motion() -> bool:
	var main := await _start_main()
	var player := _player(main)
	_clear_enemies(main)
	await _frames(1)
	player.place_at(Vector2(400, 324))
	var enemy := _spawn_test_enemy(main, Vector2(452, 324), player)
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.WINDUP, 20)
	var windup_x := enemy.global_position.x
	var hp := player.health.current
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.ACTIVE, 40)
	var strike_x := enemy.global_position.x
	_check(strike_x - windup_x > 5.0, "enemy coils back during the windup (%.1f px)" % (strike_x - windup_x))
	# Hold "toward the enemy" through the hit: during the stagger it must be ignored.
	Input.action_press(&"move_right")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 20), "enemy strike connects")
	var hit_x := player.global_position.x
	_check(player.is_staggered(), "player is staggered after being hit")
	await _frames(2)
	# Knockback (~360 px/s) must not be reduced by the held input (230 px/s).
	_check(player.velocity.x < -250.0,
			"held movement input does not fight the knockback (vx %.0f)" % player.velocity.x)
	await _frames(8)  # includes the hurt hit-stop
	_check(player.global_position.x < hit_x,
			"movement input is ignored during the stagger (knocked back %.1f px)" % (hit_x - player.global_position.x))
	await _press(&"dodge")
	Input.action_release(&"move_right")
	_check(player.state == Player.State.DODGE, "dodge still works during the stagger")
	await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.RECOVERY, 20)
	_check(strike_x - enemy.global_position.x > 5.0,
			"enemy lunges forward on the strike (%.1f px)" % (strike_x - enemy.global_position.x))
	return true


func _test_dodge() -> bool:
	var main := await _start_main()
	var player := _player(main)
	_freeze_enemies(main)
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
	await _frames(20)
	# Dodge cancels an attack in progress.
	await _frames(40)
	await _press(&"attack")
	_check(player.state == Player.State.ATTACK, "attack started before dodge-cancel")
	await _press(&"dodge")
	_check(player.state == Player.State.DODGE and not player.melee.is_busy(), "dodge cancels an attack cleanly")
	return true


func _test_enemy_states() -> bool:
	var main := await _start_main()
	var player := _player(main)
	_clear_enemies(main)
	await _frames(1)
	var enemy := _spawn_test_enemy(main, Vector2(760, 324), player)
	player.place_at(Vector2(200, 324))
	await _frames(5)
	_check(enemy.state == Enemy.State.IDLE, "enemy IDLE while player is out of aggro range")
	player.place_at(Vector2(560, 324))
	await _frames(3)
	_check(enemy.state == Enemy.State.CHASE, "enemy CHASE when player enters aggro range")
	player.place_at(Vector2(360, 324))
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
	# Death: effect plays, then the node is freed.
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
	_clear_enemies(main)
	await _frames(1)
	player.place_at(Vector2(400, 324))
	var enemy := _spawn_test_enemy(main, Vector2(452, 324), player)
	var hp := player.health.current
	_check(await _wait_until(func() -> bool: return enemy.melee.phase == MeleeAttack.Phase.WINDUP, 20),
			"enemy in range begins a telegraphed windup")
	await _frames(20)
	_check(player.health.current == hp, "no damage during the windup (reaction window)")
	_check(await _wait_until(func() -> bool: return player.health.current < hp, 30),
			"enemy strike damages the player")
	_check(player.health.current == hp - 1, "one strike deals damage once")
	_check(player.health.is_invulnerable(), "player is invulnerable right after being hit")
	# Player stays in range: no damage every frame, and no hit during the i-frames.
	player.place_at(enemy.global_position + Vector2(-50, 0))
	await _frames(40)
	_check(player.health.current == hp - 1, "no continuous contact damage")
	# Dodging away from the telegraph avoids the hit.
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


func _test_spawning() -> bool:
	var violations := {"player": 0, "bounds": 0, "obstacle": 0, "overlap": 0, "count": 0}
	for path in ROOM_SCENES:
		for seed_value in 60:
			var room := (load(path) as PackedScene).instantiate() as Room
			root.add_child(room)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			room.spawn_enemies(rng, 6, null)
			var positions := _enemy_positions(room)
			if positions.size() != 6:
				violations["count"] += 1
			var player_spawn := room.get_player_spawn_position()
			var blockers := room.get_spawn_blockers()
			for i in positions.size():
				var p := positions[i]
				if p.distance_to(player_spawn) < room.min_player_distance:
					violations["player"] += 1
				if not room.spawn_area.has_point(p):
					violations["bounds"] += 1
				for rect in blockers:
					if rect.has_point(p):
						violations["obstacle"] += 1
				for j in i:
					if p.distance_to(positions[j]) < 40.0:
						violations["overlap"] += 1
			room.free()
	for key: String in violations:
		_check(violations[key] == 0, "spawn rule '%s' holds over 120 rooms (%d violations)" % [key, violations[key]])
	_check(_spawn_signature(ROOM_SCENES[0], 12345) == _spawn_signature(ROOM_SCENES[0], 12345),
			"same seed -> same enemy placement")
	_check(_spawn_signature(ROOM_SCENES[0], 12345) != _spawn_signature(ROOM_SCENES[0], 54321),
			"different seed -> different enemy placement")
	# Main derives per-room seeds deterministically from the run seed.
	var main := await _start_main()
	var room_seed_a: int = main.room_seed(1)
	_check(room_seed_a == main.room_seed(1) and room_seed_a != main.room_seed(2),
			"room seeds are derived deterministically per room")
	for enemy in main.current_room.get_enemies():
		_check(enemy.global_position.distance_to(_player(main).global_position) >= main.current_room.min_player_distance,
				"live room: enemy spawned away from the player")
	return true


func _test_room_flow() -> bool:
	var main := await _start_main()
	var player := _player(main)
	var room: Room = main.current_room
	_freeze_enemies(main)
	_check(main.room_index == 0 and room.state == Room.State.ACTIVE, "room 1 starts ACTIVE")
	_check(room.is_exit_locked(), "exit is locked while enemies live")
	_check(room.get_enemies().size() == main.enemy_count_for_room(0), "room 1 has the expected enemy count")
	# Try to walk out through the locked exit.
	player.place_at(room.get_exit_position() + Vector2(-80, 0))
	Input.action_press(&"move_right")
	await _frames(45)
	Input.action_release(&"move_right")
	_check(player.global_position.x < room.get_exit_position().x - 16.0 - 17.0 and main.room_index == 0,
			"locked exit blocks the player (x=%.0f)" % player.global_position.x)
	for enemy in room.get_enemies():
		enemy.health.take_damage(99)
	await _frames(3)
	_check(room.state == Room.State.CLEARED and not room.is_exit_locked(), "room CLEARED unlocks the exit")
	var hp := player.health.current
	Input.action_press(&"move_right")
	_check(await _wait_until(func() -> bool: return main.room_index == 1, 90), "walking into the open exit transitions")
	Input.action_release(&"move_right")
	_check(await _wait_until(func() -> bool: return not main.is_transitioning(), 90), "transition finishes")
	var next_room: Room = main.current_room
	_check(next_room != room and next_room.scene_file_path.ends_with("room_pillars.tscn"),
			"next room is a distinct room (pillars variant)")
	_check(next_room.state == Room.State.ACTIVE and next_room.is_exit_locked(), "next room starts ACTIVE and locked")
	_check(next_room.get_enemies().size() == main.enemy_count_for_room(1), "next room spawns its own enemies")
	_check(player.global_position.distance_to(next_room.get_player_spawn_position()) < 2.0,
			"player placed at the next room's spawn")
	_check(player.health.current == hp and player.controls_enabled, "player keeps health and control after transition")
	_check(not is_instance_valid(room), "previous room is freed")
	return true


func _test_death_restart() -> bool:
	var main := await _start_main()
	var player := _player(main)
	_freeze_enemies(main)
	var old_main_id := main.get_instance_id()
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
	var button := main.get_node("Hud/DeathScreen/Panel/RestartButton") as Button
	await _wait_until(func() -> bool: return not button.disabled, 60)
	Input.action_press(&"move_right")  # simulate a held input across the restart
	button.pressed.emit()
	_check(await _wait_until(func() -> bool:
			return current_scene != null and current_scene.get_instance_id() != old_main_id, 30),
			"restart reloads the scene")
	await _frames(2)
	var new_main := current_scene as Main
	var new_player := _player(new_main)
	_check(new_player.state == Player.State.NORMAL and new_player.health.current == new_player.health.max_health,
			"restarted player is alive with full health")
	_check(new_main.room_index == 0 and new_main.current_room.state == Room.State.ACTIVE
			and new_main.current_room.get_enemies().size() == new_main.enemy_count_for_room(0),
			"restart returns to a fresh room 1")
	_check(not Input.is_action_pressed(&"move_right"), "restart clears held inputs")
	_check((new_main.get_node("MobileControls") as MobileControls).is_active(), "touch controls visible after restart")
	return true


# --- helpers -----------------------------------------------------------------

func _start_main() -> Main:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	root.add_child(main)
	current_scene = main
	await _frames(2)
	return main


func _free_current_scene() -> void:
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	await process_frame


func _player(main: Main) -> Player:
	return main.get_node("Player") as Player


func _freeze_enemies(main: Main) -> void:
	for enemy in main.current_room.get_enemies():
		enemy.set_physics_process(false)


func _clear_enemies(main: Main) -> void:
	for enemy in main.current_room.get_enemies():
		enemy.queue_free()


func _spawn_test_enemy(main: Main, at: Vector2, target: Player) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.position = at
	enemy.target = target
	main.current_room.get_node("Enemies").add_child(enemy)
	return enemy


func _enemy_positions(room: Room) -> PackedVector2Array:
	var positions := PackedVector2Array()
	for enemy in room.get_enemies():
		positions.append(enemy.position)
	return positions


func _spawn_signature(path: String, seed_value: int) -> PackedVector2Array:
	var room := (load(path) as PackedScene).instantiate() as Room
	root.add_child(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	room.spawn_enemies(rng, 4, null)
	var positions := _enemy_positions(room)
	room.free()
	return positions


## Taps an action for one physics frame, then leaves one frame to react.
func _press(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	root.push_input(event, true)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
