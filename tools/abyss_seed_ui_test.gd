extends "res://tools/test_harness.gd"

const Validator = preload("res://src/abyss/spatial_validator.gd")


func _suite_name() -> String:
	return "ABYSS SEED UI"


func _get_tests() -> Array[Callable]:
	return [_test_seed_selection]


func _test_seed_selection() -> bool:
	var demo := preload("res://src/abyss/generated_demo.tscn").instantiate()
	demo.world_seed = 777
	root.add_child(demo)
	await _frames(10)
	var exposed := false
	for property in demo.get_property_list():
		if property.name == "world_seed":
			exposed = (int(property.usage) & PROPERTY_USAGE_EDITOR) != 0
	_check(exposed and demo.world_seed == 777 and demo.layout.run_seed == 777,
		"World Seed is exposed in the Inspector and controls startup generation")
	var source: Node = demo.get_node("MovementInput")
	var source_id := source.get_instance_id()
	var actions: Array = source.actions.duplicate()
	var camera: Camera3D = demo.get_node("Camera")
	var orientation := camera.global_basis
	var signatures: Dictionary = {}
	var first_fingerprint := ""
	for value in [12345, 42, 7, 12345]:
		var previous: WeakRef = weakref(demo.geometry)
		demo._complete = true
		demo.get_node("Player3D").velocity = Vector3(3, 0, 2)
		var button: Button = demo.get_node("Instructions/SeedSelector/Seed%d" % value)
		_check(not button.disabled, "seed %d is selectable" % value)
		var center := button.get_global_rect().get_center()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = center
		press.pressed = true
		root.push_input(press, true)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = center
		release.pressed = false
		root.push_input(release, true)
		await _frames(8)
		_check(demo.world_seed == value and demo.layout.run_seed == value
			and Validator.validate(demo.layout).is_empty(), "mouse selection builds valid seed %d" % value)
		_check(previous.get_ref() == null, "old seed geometry is released")
		var player: CharacterBody3D = demo.get_node("Player3D")
		_check(not demo._complete and player.is_on_floor() and player.position.distance_to(demo.layout.spawn) < 0.1
			and Vector2(player.velocity.x, player.velocity.z).is_zero_approx(), "seed change resets player and exit progress")
		_check(demo.get_node("MovementInput").get_instance_id() == source_id
			and source.actions == actions and camera.global_basis.is_equal_approx(orientation),
			"seed change retains controller actions and fixed camera orientation")
		_check(button.disabled and str(value) in demo.get_node("Instructions/Label").text,
			"active seed is displayed and its button marked current")
		var fingerprint: String = demo.layout.fingerprint()
		if first_fingerprint.is_empty():
			first_fingerprint = fingerprint
		elif value == 12345:
			_check(fingerprint == first_fingerprint, "returning to seed 12345 reproduces the same layout")
		signatures[fingerprint] = true
		print("SEED UI seed=", value, " fingerprint=", fingerprint,
			" rooms=", demo.layout.rooms.size(), " links=", demo.layout.connections.size())
	_check(signatures.size() == 3, "12345, 42 and 7 produce three distinct valid layouts")
	demo.queue_free()
	await process_frame
	for action in actions:
		_check(not InputMap.has_action(action), "controller action cleaned up after demo exit")
	return true
