extends "res://tools/test_harness.gd"
## Run with --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd.


func _suite_name() -> String:
	return "P1A 3D"


func _get_tests() -> Array[Callable]:
	return [_test_foundation]


func _test_foundation() -> bool:
	var scene := preload("res://src/prototype_3d/foundation_3d.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player3D")
	var camera: Camera3D = scene.get_node("IsometricCamera3D")
	await _frames(20)
	_check(player.is_on_floor() and absf(player.position.y) < 0.02, "capsule settles on floor")
	_check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic projection")
	var orientation := camera.global_basis
	var expected_keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	}
	var screen_directions := {
		"move_up": Vector2.UP, "move_down": Vector2.DOWN,
		"move_left": Vector2.LEFT, "move_right": Vector2.RIGHT,
	}
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		var keys: Array[int] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append(event.physical_keycode)
		_check(keys.has(expected_keys[action][0]) and keys.has(expected_keys[action][1]),
			"%s retains WASD and arrow binding" % action)
		player.position = Vector3(0, 0.05, 0)
		await _frames(3)
		var start := player.position
		var screen_start := camera.unproject_position(start)
		camera.set_process(false)
		Input.action_press(action)
		await _frames(30)
		Input.action_release(action)
		var travel := player.position - start
		var screen_travel := camera.unproject_position(player.position) - screen_start
		_check(screen_travel.normalized().dot(screen_directions[action]) > 0.99,
			"%s travels in expected screen direction" % action)
		camera.set_process(true)
		_check(travel.length() > 2.2 and travel.length() < 2.7, "%s moves at expected speed" % action)
		_check((-player.get_node("Visual").global_basis.z).dot(travel.normalized()) > 0.99,
			"%s turns visible facing toward travel" % action)
		await _frames(3)
		_check(Vector2(player.velocity.x, player.velocity.z).is_zero_approx(), "release stops movement")
	player.position = Vector3(0, 0.05, 0)
	await _frames(3)
	Input.action_press("move_up")
	Input.action_press("move_right")
	await _frames(30)
	_check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), 5.0), "diagonal speed is normalized")
	Input.action_release("move_up")
	Input.action_release("move_right")
	# Disable camera-relative mapping to push directly against each world boundary.
	player.set("movement_camera", null)
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		player.position = Vector3(0, 0.05, 0)
		await _frames(3)
		Input.action_press(action)
		await _frames(150)
		Input.action_release(action)
		_check(player.is_on_wall(), "%s collides with surrounding wall" % action)
		_check(absf(player.position.x) <= 9.17 and absf(player.position.z) <= 9.17,
			"capsule remains inside room")
		_check(player.is_on_floor(), "wall contact preserves floor support")
	# Push diagonally into east wall; the tangential component must keep moving.
	player.position = Vector3(9.1, 0.05, 0)
	await _frames(3)
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _frames(30)
	Input.action_release("move_right")
	Input.action_release("move_up")
	_check(player.position.x <= 9.17 and player.position.z < -1.5, "slides along wall")
	player.set_physics_process(false)
	await process_frame
	player.position += Vector3(-3, 0, 0)
	var error := camera.position.distance_to(player.position + camera.get("follow_offset"))
	await process_frame
	var after := camera.position.distance_to(player.position + camera.get("follow_offset"))
	_check(after > 0.0 and after < error, "camera follows smoothly without snapping")
	await _frames(90)
	_check(camera.position.distance_to(player.position + camera.get("follow_offset")) < 0.02,
		"camera converges to follow offset")
	_check(camera.global_basis.is_equal_approx(orientation), "camera orientation remains fixed")
	_check(camera.position.is_finite(), "camera position remains finite")
	scene.queue_free()
	await process_frame
	return true
