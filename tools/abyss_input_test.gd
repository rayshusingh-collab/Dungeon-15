extends "res://tools/test_harness.gd"

var _source: Node
const DEVICE := 42


func _suite_name() -> String:
	return "ABYSS INPUT"


func _get_tests() -> Array[Callable]:
	return [_test_input, _test_camera_and_route]


func _motion(axis: int, value: float, device: int = DEVICE) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_input() -> bool:
	var shared_before := _shared_bindings()
	_source = preload("res://src/abyss/gamepad_input.gd").new()
	root.add_child(_source)
	_source.bind_device(DEVICE)
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_press(action)
		_check(is_equal_approx(_source.movement_vector().length(), 1.0), "%s retains full keyboard speed" % action)
		Input.action_release(action)
	Input.action_press("move_up")
	Input.action_press("move_right")
	_check(is_equal_approx(_source.movement_vector().length(), 1.0), "keyboard diagonals normalized")
	Input.action_release("move_up")
	Input.action_release("move_right")
	_motion(JOY_AXIS_LEFT_X, 0.1)
	_check(_source.movement_vector().is_zero_approx(), "stick drift inside deadzone produces no movement")
	_motion(JOY_AXIS_LEFT_X, 0.22)
	_check(_source.movement_vector().is_zero_approx(), "deadzone boundary is stationary")
	_motion(JOY_AXIS_LEFT_X, 0.61)
	_check(_source.movement_vector().is_equal_approx(Vector2(0.5, 0)), "half stick response after radial deadzone rescaling")
	_motion(JOY_AXIS_LEFT_X, 1.0)
	_check(_source.movement_vector().is_equal_approx(Vector2.RIGHT), "full analog axis gives full movement")
	_motion(JOY_AXIS_LEFT_Y, -1.0)
	_check(is_equal_approx(_source.movement_vector().length(), 1.0), "analog diagonals normalized")
	_motion(JOY_AXIS_LEFT_X, 0.0)
	_motion(JOY_AXIS_LEFT_Y, 0.0)
	_motion(JOY_AXIS_LEFT_X, 1.0, DEVICE + 1)
	_check(_source.movement_vector().is_zero_approx(), "non-selected device cannot drive movement")
	for pair in [[JOY_BUTTON_DPAD_LEFT, Vector2.LEFT], [JOY_BUTTON_DPAD_RIGHT, Vector2.RIGHT],
			[JOY_BUTTON_DPAD_UP, Vector2.UP], [JOY_BUTTON_DPAD_DOWN, Vector2.DOWN]]:
		_button(pair[0], true)
		_check(_source.movement_vector().is_equal_approx(pair[1]), "logical D-pad button %d moves correctly" % pair[0])
		_button(pair[0], false)
	_button(JOY_BUTTON_DPAD_UP, true)
	_button(JOY_BUTTON_DPAD_RIGHT, true)
	_check(is_equal_approx(_source.movement_vector().length(), 1.0), "D-pad diagonal normalized")
	_button(JOY_BUTTON_DPAD_UP, false)
	_button(JOY_BUTTON_DPAD_RIGHT, false)
	_motion(JOY_AXIS_LEFT_X, 1.0)
	_source.bind_device(-1)
	_check(_source.movement_vector().is_zero_approx(), "disconnect clears held movement")
	Input.action_press("move_left")
	_check(_source.movement_vector() == Vector2.LEFT, "keyboard survives disconnected controller")
	Input.action_release("move_left")
	_source.bind_device(DEVICE)
	_motion(JOY_AXIS_LEFT_X, 0.0)
	_motion(JOY_AXIS_LEFT_X, 1.0)
	_check(_source.movement_vector() == Vector2.RIGHT, "rebind accepts fresh controller events")
	_motion(JOY_AXIS_LEFT_X, 0.0)
	_source.horizontal_axis = JOY_AXIS_RIGHT_X
	_source.invert_horizontal = true
	_source.dpad_right = JOY_BUTTON_A
	_source.bind_device(DEVICE)
	_motion(JOY_AXIS_RIGHT_X, -1.0)
	_check(_source.movement_vector() == Vector2.RIGHT, "alternate axis and inversion mapping works")
	_motion(JOY_AXIS_RIGHT_X, 0.0)
	_button(JOY_BUTTON_A, true)
	_check(_source.movement_vector() == Vector2.RIGHT, "configurable button mapping works")
	_button(JOY_BUTTON_A, false)
	_source.dpad_horizontal_axis = JOY_AXIS_RIGHT_X
	_source.horizontal_axis = JOY_AXIS_LEFT_X
	_source.invert_horizontal = false
	_source.bind_device(DEVICE)
	_motion(JOY_AXIS_RIGHT_X, 1)
	_check(_source.movement_vector() == Vector2.RIGHT, "optional D-pad hat axis works alongside left stick")
	_motion(JOY_AXIS_RIGHT_X, 0)
	_source.invert_dpad_horizontal = true
	_source.bind_device(DEVICE)
	_motion(JOY_AXIS_RIGHT_X, -1)
	_check(_source.movement_vector() == Vector2.RIGHT, "optional hat axis inversion works")
	_motion(JOY_AXIS_RIGHT_X, 0)
	Input.joy_connection_changed.emit(DEVICE, false)
	_check(_source.device_id != DEVICE, "connection signal refreshes selection from real connected list")
	print("ABYSS actual connected devices: ", Input.get_connected_joypads())
	for device in Input.get_connected_joypads():
		print("ID ", device, " name=", Input.get_joy_name(device), " GUID=", Input.get_joy_guid(device))
	var owned_actions: Array = _source.actions.duplicate()
	_source.queue_free()
	await process_frame
	var cleaned := true
	for action in owned_actions:
		cleaned = cleaned and not InputMap.has_action(action)
	_check(cleaned, "scene exit removes owned actions")
	_check(_shared_bindings() == shared_before, "shared action bindings and deadzones unchanged")
	return true


func _shared_bindings() -> String:
	var result := ""
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		result += str(InputMap.action_get_deadzone(action))
		for event in InputMap.action_get_events(action):
			result += event.as_text()
	return result


func _test_camera_and_route() -> bool:
	var demo := preload("res://src/abyss/vertical_demo.tscn").instantiate()
	root.add_child(demo)
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	_source = demo.get_node("MovementInput")
	_source.bind_device(DEVICE)
	await _frames(10)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		player.position = Vector3(0, 0.05, 0)
		player.velocity = Vector3.ZERO
		_motion(JOY_AXIS_LEFT_X, 0)
		_motion(JOY_AXIS_LEFT_Y, 0)
		await _frames(5)
		camera.set_process(false)
		var start := camera.unproject_position(player.position)
		_motion(JOY_AXIS_LEFT_X, direction.x)
		_motion(JOY_AXIS_LEFT_Y, direction.y)
		await _frames(15)
		var screen_delta := camera.unproject_position(player.position) - start
		# Isometric projection compresses screen vertical displacement; compare sign
		# on diagonals and exact cardinal direction, rather than demanding 45 degrees.
		var expected: Vector2 = direction.normalized()
		if direction.x == 0 or direction.y == 0:
			_check(screen_delta.normalized().dot(expected) > 0.99, "camera-relative analog direction %s" % direction)
		else:
			_check(signf(screen_delta.x) == signf(direction.x) and signf(screen_delta.y) == signf(direction.y), "camera-relative diagonal %s" % direction)
		_check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), 5), "world movement keeps normalized speed")
		_motion(JOY_AXIS_LEFT_X, 0)
		_motion(JOY_AXIS_LEFT_Y, 0)
		camera.set_process(true)
	player.position = Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(10)
	# Actual camera mapping: +X route is right+down; reverse is left+up.
	_motion(JOY_AXIS_LEFT_X, 1)
	_motion(JOY_AXIS_LEFT_Y, 1)
	var reached := await _wait_until(func() -> bool: return player.position.x >= 54, 1000)
	_motion(JOY_AXIS_LEFT_X, 0)
	_motion(JOY_AXIS_LEFT_Y, 0)
	_check(reached and absf(player.position.y - 8) < 0.1, "camera-relative stick traverses stairs and bridge to upper chamber")
	Input.action_press("move_left")
	Input.action_press("move_up")
	var returned := await _wait_until(func() -> bool: return player.position.x <= 0, 1000)
	Input.action_release("move_left")
	Input.action_release("move_up")
	await _frames(5)
	_check(returned and player.is_on_floor(), "camera-relative A+W returns down both stairs")
	demo.queue_free()
	await process_frame
	return true
