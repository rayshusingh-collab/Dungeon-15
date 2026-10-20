extends "res://tools/test_harness.gd"

const Scene = preload("res://src/abyss/mechanism_demo.tscn")
var _floor_safe: bool = true
var _stream_bounds: bool = true
var _final_pose: Transform3D
var _stable_id: String


func _suite_name() -> String:
	return "ABYSS MECHANISM"


func _get_tests() -> Array[Callable]:
	return [_test_input_mapping, _test_closed_route, _test_activation_and_persistence, _test_interrupted_deployment]


func _key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(index: int, pressed: bool, device: int = 42) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_input_mapping() -> bool:
	var movement := preload("res://src/abyss/gamepad_input.gd").new()
	root.add_child(movement)
	movement.bind_device(42)
	var input := preload("res://src/abyss/mechanism_input.gd").new()
	input.movement_input = movement
	root.add_child(input)
	var count := [0]
	input.interacted.connect(func() -> void: count[0] += 1)
	_key(KEY_E)
	_key(KEY_E, false)
	_check(count[0] == 1, "keyboard E routes through the scene-owned interaction action")
	input.configure_device(42, true, "synthetic-known")
	_button(JOY_BUTTON_A, true)
	_button(JOY_BUTTON_A, false)
	_check(count[0] == 2, "recognized mapping uses Godot logical south button")
	_button(JOY_BUTTON_A, true, 43)
	_button(JOY_BUTTON_A, false, 43)
	_check(count[0] == 2, "another controller cannot activate the selected device's action")
	input.configure_device(42, false, "synthetic-unknown")
	_button(JOY_BUTTON_A, true)
	_button(JOY_BUTTON_A, false)
	_check(count[0] == 2 and input.button_index == -1, "unknown pad has no assumed Xbox/physical button mapping")
	_key(KEY_F4)
	_key(KEY_F4, false)
	_button(7, true)
	_check(input.button_index == 7 and count[0] == 2, "F4 captures the actually reported button without activating")
	_button(7, false)
	_button(7, true)
	_button(7, false)
	_check(count[0] == 3, "captured south button activates on a fresh press")
	input.configure_device(-1, false, "")
	input.configure_device(42, false, "synthetic-unknown")
	_check(input.button_index == 7, "captured mapping survives device rebind within the session")
	input.configure_device(-1, false, "")
	_key(KEY_E)
	_key(KEY_E, false)
	_check(count[0] == 4, "keyboard interaction remains available without a controller")
	var owned_action: StringName = input.action
	input.queue_free()
	movement.queue_free()
	await process_frame
	_check(not InputMap.has_action(owned_action), "interaction action is cleaned up on scene exit")
	print("Mechanism physical pads detected: ", Input.get_connected_joypads())
	return true


func _ready_demo() -> Node3D:
	var demo := Scene.instantiate()
	root.add_child(demo)
	await _frames(25)
	return demo


func _test_activation_and_persistence() -> bool:
	var demo: Node3D = await _ready_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	_check(stream.bridge != null and not stream.state().activated and stream.bridge.deck.collision_layer == 0,
		"bridge begins visibly lowered, disconnected and non-traversable")
	_check(not stream.logical_edge_open(Vector2i.ZERO, Vector2i.RIGHT)
		and not stream.logical_edge_open(Vector2i(1, 1), Vector2i.RIGHT), "destination has no bypass before the mechanism opens its sole entrance")
	_key(KEY_E)
	_key(KEY_E, false)
	_check(not stream.state().activated, "out-of-range E cannot activate the mechanism")
	var approach: Vector3 = stream.bridge.mechanism_position - Vector3.RIGHT
	_check(await _walk(stream, player, camera, approach), "player can walk safely into configurable interaction range")
	_check("activate ancient mechanism" in stream.prompt(), "interaction prompt appears only near the mechanism")
	var initial_pose: Transform3D = stream.bridge.deck.transform
	# Occupancy rejection includes another layer-2 body, without shifting any actor.
	var blocker := CharacterBody3D.new()
	blocker.collision_layer = 2
	blocker.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.6
	shape.radius = 0.35
	collider.shape = shape
	blocker.add_child(collider)
	blocker.position = (stream.bridge.link.start + stream.bridge.link.end) * 0.5
	root.add_child(blocker)
	await _frames(3)
	_check(not stream.activate() and not stream.state().activated, "occupied sweep rejects activation before any movement")
	blocker.queue_free()
	await _frames(3)
	_key(KEY_E)
	_key(KEY_E, false)
	_check(stream.state().activated and not stream.state().completed and stream.activation_count == 1,
		"in-range keyboard activation records one persistent event")
	_key(KEY_E)
	_key(KEY_E, false)
	_check(stream.activation_count == 1, "repeat input during deployment cannot activate twice")
	await _frames(30)
	_check(not stream.bridge.deck.transform.is_equal_approx(initial_pose) and stream.bridge.deck.collision_layer == 0,
		"bridge visibly animates while traversable collision stays disabled")
	# Deliberately inject player occupancy to verify pause, not transport/crush.
	var safe_position := player.position
	player.set_physics_process(false)
	player.position = (stream.bridge.link.start + stream.bridge.link.end) * 0.5 + Vector3.UP
	await _frames(3)
	var paused_progress: float = stream.state().progress
	var occupied_position := player.position
	await _frames(10)
	_check(is_equal_approx(stream.state().progress, paused_progress) and player.position == occupied_position
		and stream.bridge.deck.collision_layer == 0, "player occupancy pauses deployment without collision, crushing or teleporting")
	player.position = safe_position
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await _frames(4)
	_check(await _wait_until(func() -> bool: return stream.state().completed, 260), "cleared sweep resumes deployment and commits after collider readiness")
	await _frames(4)
	_check(stream.bridge.deck.collision_layer == 1 and stream.logical_edge_open(Vector2i.ZERO, Vector2i.RIGHT)
		and "open" in stream.status, "completed bridge enables collision and confirms route opening")
	var final_pose: Transform3D = stream.bridge.deck.transform
	var id: String = stream.mechanism_id
	_final_pose = final_pose
	_stable_id = id
	_check(_reachable(stream).size() == 289, "completed predefined state connects every world chunk including the destination")
	var old_bridge: WeakRef = weakref(stream.bridge)
	_check(await _walk(stream, player, camera, stream.catalog.room(Vector2i.ZERO).center)
		and await _walk(stream, player, camera, stream.catalog.room(Vector2i.RIGHT).center), "actual capsule crosses the deployed bridge to the destination")
	await _frames(4)
	_check(stream.state().destination_reached, "newly accessible chamber provides an explicit route-discovery objective")
	_check(not stream.logical_edge_open(Vector2i.RIGHT, Vector2i(1, 1)), "destination side entrances remain closed after completion")
	_check(await _walk(stream, player, camera, stream.catalog.room(Vector2i.ZERO).center), "deployed bridge remains bidirectionally navigable")
	var travel := true
	for cell in [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-3, 0)]:
		travel = await _walk(stream, player, camera, stream.catalog.room(cell).center) and travel
	_check(travel and stream.bridge == null and old_bridge.get_ref() == null and stream.state().completed,
		"completed state survives real chunk eviction independently of the freed visual")
	for cell in [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i.ZERO]:
		travel = await _walk(stream, player, camera, stream.catalog.room(cell).center) and travel
	_check(travel and stream.mechanism_id == id and stream.bridge.deck.transform.is_equal_approx(final_pose)
		and stream.bridge.deck.collision_layer == 1 and stream.state().completed,
		"reconstructed chunk restores stable ID, exact final pose and collision without reactivation")
	_check(not stream.activate() and stream.activation_count == 1, "completed mechanism never repeats its activation")
	_check(_floor_safe and _stream_bounds and stream.max_resident <= 9 and stream.max_active_boxes <= 175,
		"normal traversal preserves floor support and Stage 4 residency/work limits")
	print("MECHANISM measurements: max_transition_ms=", stream.transition_max_ms,
		" mechanism_build_ms=", stream.mechanism_build_max_ms,
		" ", stream.diagnostic_text(), " state=", stream.state(), " FPS=not_measured")
	demo.queue_free()
	await process_frame
	return true


func _test_interrupted_deployment() -> bool:
	var demo: Node3D = await _ready_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	stream.deployment_seconds = 1000
	var approach: Vector3 = stream.bridge.mechanism_position - Vector3.RIGHT
	_check(await _walk(stream, player, camera, approach) and stream.activate(), "long deployment starts from a valid approach")
	for cell in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(-2, 0)]:
		await _walk(stream, player, camera, stream.catalog.room(cell).center)
	var progress: float = stream.state().progress
	await _frames(20)
	_check(stream.bridge == null and stream.state().activated and not stream.state().completed
		and is_equal_approx(stream.state().progress, progress), "unloaded in-progress mechanism retains its event/progress and pauses work")
	for cell in [Vector2i(-1, 0), Vector2i.ZERO]:
		await _walk(stream, player, camera, stream.catalog.room(cell).center)
	_check(stream.bridge != null and stream.state().activated and stream.state().progress >= progress
		and stream.bridge.deck.collision_layer == 0, "reloaded in-progress bridge resumes without resetting or premature collision")
	stream.deployment_seconds = 0.2
	_check(await _wait_until(func() -> bool: return stream.state().completed, 100), "resumed deployment reaches the same predefined connected state")
	_check(stream.mechanism_id == _stable_id and stream.bridge.deck.transform.is_equal_approx(_final_pose),
		"independent runs and different deployment timings produce the identical final ID/pose")
	demo.queue_free()
	await process_frame
	return true


func _test_closed_route() -> bool:
	var demo: Node3D = await _ready_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var visited := _reachable(stream)
	_check(visited.size() == 288 and not visited.has(Vector2i.RIGHT),
		"closed state preserves all 288 other chunks while isolating only the optional destination")
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _frames(150)
	_release()
	_check(player.position.x < stream.bridge.link.start.x and player.is_on_floor() and player.is_on_wall()
		and stream.bridge.deck.collision_layer == 0, "physical gate prevents falling or premature crossing of the disconnected bridge")
	demo.queue_free()
	await process_frame
	return true


func _reachable(stream: Node3D) -> Dictionary:
	var visited := {Vector2i.ZERO: true}
	var pending: Array[Vector2i] = [Vector2i.ZERO]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if stream.settings.contains(next) and not visited.has(next) and stream.logical_edge_open(cell, next):
				visited[next] = true
				pending.append(next)
	return visited


func _walk(stream: Node3D, player: CharacterBody3D, camera: Camera3D, target: Vector3) -> bool:
	for frame in 900:
		var delta := target - player.position
		delta.y = 0
		if delta.length() < 0.18:
			_release()
			await _frames(4)
			return player.is_on_floor() and absf(player.position.y - target.y) < 0.1
		var right := camera.global_basis.x
		var forward := -camera.global_basis.z
		right.y = 0
		forward.y = 0
		var direction := delta.normalized()
		var vector := Vector2(direction.dot(right.normalized()), -direction.dot(forward.normalized()))
		_release()
		Input.action_press("move_left" if vector.x < 0 else "move_right", absf(vector.x))
		Input.action_press("move_up" if vector.y < 0 else "move_down", absf(vector.y))
		await physics_frame
		_floor_safe = _floor_safe and player.is_on_floor()
		_stream_bounds = _stream_bounds and stream.active.size() <= stream.settings.capacity() \
			and stream.last_jobs <= stream.settings.jobs_per_frame
	_release()
	return false


func _release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
