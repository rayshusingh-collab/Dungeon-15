extends "res://tools/test_harness.gd"

const Plan = preload("res://src/abyss/vertical_plan.gd")


func _suite_name() -> String:
	return "ABYSS VERTICAL"


func _get_tests() -> Array[Callable]:
	return [_test_contract, _test_traversal]


func _test_contract() -> bool:
	_check(Plan.validate(Plan.route()).is_empty(), "fixed route sockets validate")
	_check(not Plan.validate(PackedVector3Array()).is_empty(), "reject missing entry/exit")
	_check(not Plan.validate(PackedVector3Array([Vector3.ZERO, Vector3(1, 4, 0)])).is_empty(), "reject unsafe slope")
	_check(not Plan.validate(PackedVector3Array([Vector3.ZERO, Vector3(-1, 0, 0)])).is_empty(), "reject reversed sockets")
	_check(not Plan.validate(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 2)])).is_empty(), "reject misaligned sockets")
	_check(not Plan.validate(PackedVector3Array([Vector3.ZERO, Vector3(INF, 0, 0)])).is_empty(), "reject infinite coordinates")
	return true


func _test_traversal() -> bool:
	var demo := preload("res://src/abyss/vertical_demo.tscn").instantiate()
	root.add_child(demo)
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	await _frames(20)
	_check(player.is_on_floor(), "entry has physical floor support")
	_check(player.get("movement_camera") == camera, "demo uses P1A camera-relative controller")
	var orientation := camera.global_basis
	var surface_valid := true
	for x in 55:
		for z in [-1.0, 0.0, 1.0]:
			var expected := Vector3(x, _height(x), z)
			var query := PhysicsRayQueryParameters3D.create(
				expected + Vector3.UP * 2, expected - Vector3.UP * 2, 1)
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or absf(hit.position.y - expected.y) > 0.05:
				surface_valid = false
	_check(surface_valid, "165 physical probes confirm route surface and usable width")
	# Exercise actual capsule and move_and_slide on the generated collision.
	# Disable only the camera mapping so test input follows the fixture world X.
	player.set("movement_camera", null)
	var unsupported := 0
	var worst_height_error := 0.0
	Input.action_press("move_right")
	for target_x in [24.0, 54.0]:
		var frames := 0
		while player.position.x < target_x and frames < 650:
			await physics_frame
			frames += 1
			if not player.is_on_floor():
				unsupported += 1
			worst_height_error = maxf(worst_height_error, absf(player.position.y - _height(player.position.x)))
		_check(player.position.x >= target_x, "walk reaches chamber at X %.0f" % target_x)
		_check(absf(player.position.y - _height(target_x)) < 0.1, "chamber has correct elevation")
	Input.action_release("move_right")
	await _frames(4)
	_check(unsupported == 0, "ascending route has continuous floor support")
	_check(worst_height_error < 0.12, "ascending feet follow expected surface")
	Input.action_press("move_left")
	var descent_frames := 0
	var descent_unsupported := 0
	while player.position.x > 0.0 and descent_frames < 1000:
		await physics_frame
		descent_frames += 1
		if not player.is_on_floor():
			descent_unsupported += 1
	var returned := player.position.x <= 0.0
	Input.action_release("move_left")
	await _frames(5)
	_check(returned and player.is_on_floor() and absf(player.position.y) < 0.1, "return down both stairs to entry")
	_check(descent_unsupported == 0, "descending route has continuous floor support")
	# Probe bridge and stair railings from both sides, plus chamber end walls.
	for position in [Vector3(33, 4.05, 0), Vector3(12, 2.05, 0), Vector3(42, 6.05, 0)]:
		for action in ["move_up", "move_down"]:
			player.position = position
			player.velocity = Vector3.ZERO
			await _frames(10)
			Input.action_press(action)
			await _frames(70)
			Input.action_release(action)
			_check(absf(player.position.z) < 1.6 and player.is_on_wall(), "guardrail blocks %s at X %.0f" % [action, position.x])
	player.position = Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_left")
	await _frames(100)
	Input.action_release("move_left")
	_check(player.position.x > -5.5 and player.is_on_wall(), "entry end wall prevents falling")
	player.position = Vector3(54, 8.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_right")
	await _frames(100)
	Input.action_release("move_right")
	_check(player.position.x < 59.5 and player.is_on_wall(), "exit end wall prevents falling")
	_check(camera.global_basis.is_equal_approx(orientation), "camera keeps isometric orientation across elevations")
	_check(demo.get_node("Geometry").get("piece_count") < 100, "fixed fixture stays within 100-box budget")
	print("ABYSS measurements: build_ms=", demo.get_node("Geometry").get("build_msec"),
		" static_memory_bytes=", OS.get_static_memory_usage(), " headless_only=true")
	demo.queue_free()
	await process_frame
	return true


func _height(x: float) -> float:
	if x < 6:
		return 0.0
	if x < 18:
		return (x - 6) / 3.0
	if x < 36:
		return 4.0
	if x < 48:
		return 4.0 + (x - 36) / 3.0
	return 8.0
