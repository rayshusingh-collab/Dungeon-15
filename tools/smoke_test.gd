extends SceneTree
## Headless smoke test for the main scene. Exits with code 1 on any failure.
## Run: godot --headless --path . --script res://tools/smoke_test.gd
## Automated checks only prove wiring, not game feel.

const ROOM_SCENE_PATH := "res://src/rooms/room.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	_check(main_scene != null, "main scene loads")
	if main_scene == null:
		_finish()
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var player := main.get_node_or_null("Player") as Player
	var room := main.get_node_or_null("Room") as Room
	_check(player != null, "Player node present and typed")
	_check(room != null, "Room node present and typed")
	if player == null or room == null:
		_finish()
		return
	var expected_enemies: int = main.get(&"enemy_count")
	_check(get_nodes_in_group(&"enemies").size() == expected_enemies, "room spawned %d enemies" % expected_enemies)
	_check(not room.is_cleared, "room starts uncleared")

	# InputMap action path (keyboard) moves the player.
	var start := player.global_position
	Input.action_press(&"move_right")
	for i in 10:
		await physics_frame
	Input.action_release(&"move_right")
	_check(player.global_position.x > start.x, "move_right action moves player")

	# Native VirtualJoystick feeds the move_* actions from touch.
	var joystick := main.get_node_or_null("MobileControls/VirtualJoystick") as Control
	_check(joystick != null, "VirtualJoystick present")
	if joystick != null:
		var center := joystick.get_global_rect().get_center()
		_touch(0, center, true)
		_drag(0, center + Vector2(-60, 0))
		await process_frame
		_check(Input.get_action_strength(&"move_left") > 0.0, "joystick drag presses move_left")
		_touch(0, center + Vector2(-60, 0), false)
		await process_frame
		_check(is_zero_approx(Input.get_action_strength(&"move_left")), "joystick release clears move_left")

	# Touch attack button presses the attack action while held.
	var button := main.get_node_or_null("MobileControls/AttackButton") as Control
	_check(button != null, "AttackButton present")
	if button != null:
		var button_center := button.get_global_rect().get_center()
		_touch(1, button_center, true)
		_check(Input.is_action_pressed(&"attack"), "attack button presses attack")
		_touch(1, button_center, false)
		_check(not Input.is_action_pressed(&"attack"), "attack button release clears attack")

	# Killing every enemy clears the room.
	for node: Node in get_nodes_in_group(&"enemies"):
		(node as Enemy).take_damage(1000)
	await process_frame
	_check(room.is_cleared, "room clears after all enemies die")

	# Seeded enemy placement is deterministic.
	var positions_a := await _spawn_positions(12345)
	var positions_b := await _spawn_positions(12345)
	var positions_c := await _spawn_positions(54321)
	_check(positions_a == positions_b, "same seed -> same enemy placement")
	_check(positions_a != positions_c, "different seed -> different enemy placement")

	main.queue_free()
	_finish()


func _spawn_positions(seed_value: int) -> PackedVector2Array:
	var room := (load(ROOM_SCENE_PATH) as PackedScene).instantiate() as Room
	root.add_child(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	room.spawn_enemies(rng, 4)
	var positions := PackedVector2Array()
	for enemy: Node2D in room.get_node("Enemies").get_children():
		positions.append(enemy.position)
	room.queue_free()
	await process_frame
	return positions


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
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _finish() -> void:
	print("SMOKE TEST: %s (%d failure(s))" % ["OK" if _failures == 0 else "FAILED", _failures])
	quit(1 if _failures > 0 else 0)
