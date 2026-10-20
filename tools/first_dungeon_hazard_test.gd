extends "res://tools/test_harness.gd"
const Fixture = preload("res://src/game_3d/hazard_validation.tscn")
const Data = preload("res://src/game_3d/hazard_fixture_data.gd")
const Grid = preload("res://src/game_3d/grid_space.gd")
const T = DungeonLayout.Tile

func _suite_name() -> String:
	return "M1.1 HAZARDS AND CONTROLLER"

func _get_tests() -> Array[Callable]:
	return [_test_fixture, _test_controller]

func _test_fixture() -> bool:
	var scene := Fixture.instantiate()
	root.add_child(scene)
	await _frames(5)
	_check(scene.fixture_mode and scene.layout.tiles == Data.create().tiles, "explicit F6 fixture uses deterministic separate data")
	_check(scene.layout.tiles.count(T.PIT)==24 and scene.layout.tiles.count(T.BRIDGE)==18 and scene.layout.tiles.count(T.WATER)==18 and scene.layout.tiles.count(T.HAZARD)==9, "fixture exact terrain counts")
	_check(scene.detail_counts.pit_recess_sides > 0, "pit opening has visible recess sides")
	_check(scene.detail_counts.bridge_edge_beams > 0 and scene.detail_counts.bridge_planks==54, "bridge has edge beams and plank seams")
	_check(scene.detail_counts.water_shore_edges > 0 and scene.materials[T.WATER] is ShaderMaterial, "water has shore edges and ripple material")
	_check(scene.detail_counts.spike_sockets==36, "safe spikes have visible sockets")
	var player: CharacterBody3D = scene.player
	player.movement_camera = null
	player.position = Grid.center(Vector2i(6,5),0.05)
	player.velocity = Vector3.ZERO
	scene.elapsed = 0
	await _frames(3)
	Input.action_press("move_right")
	await _frames(192)
	Input.action_release("move_right")
	_check(Grid.tile_at(player.position)==Vector2i(14,5) and player.is_on_floor() and scene.resets==0, "crosses full bridge over pits using real keyboard physics")
	player.position = Grid.center(Vector2i(9,2),0.05)
	player.velocity = Vector3.ZERO
	await _frames(65)
	_check(scene.resets==1 and Grid.tile_at(player.position)==scene.layout.player_spawn, "open pit physically drops and resets capsule")
	var distances: Array[float] = []
	for tile in [Vector2i(3,10),Vector2i(7,11)]:
		player.position = Grid.center(tile,0.05)
		player.velocity = Vector3.ZERO
		await _frames(3)
		var start := player.position
		Input.action_press("move_right")
		await _frames(60)
		Input.action_release("move_right")
		distances.append(player.position.distance_to(start))
	_check(absf(distances[0]-5.0)<0.15 and absf(distances[1]-2.5)<0.15, "water travel distance is physically half safe-floor distance")
	player.position = Grid.center(Vector2i(14,5),0.05)
	player.velocity = Vector3.ZERO
	scene.elapsed = 0
	await _frames(3)
	_check(not scene.spike_tips.visible, "safe spike tips retracted")
	Input.action_press("move_right")
	await _frames(96)
	Input.action_release("move_right")
	_check(Grid.tile_at(player.position)==Vector2i(18,5) and scene.resets==1, "full spike patch traversed during safe phase")
	scene.elapsed = scene.safe_seconds+0.1
	await _frames(2)
	_check(scene.spike_tips.visible and is_equal_approx(scene.spike_tips.scale.y,0.25) and scene.spike_material.albedo_color.g>0.5, "warning tips are short and amber")
	scene.elapsed = scene.safe_seconds+0.7
	player.position = Grid.center(Vector2i(16,5),0.05)
	await _frames(2)
	_check(scene.spike_tips.visible and scene.spike_tips.scale.y==1 and scene.spike_material.albedo_color.g<0.2, "raised tips full-height red")
	_check(scene.resets==2 and Grid.tile_at(player.position)==scene.layout.player_spawn, "raised spikes physically reset player")
	var count := get_node_count()
	await _frames(400)
	_check(count==get_node_count(), "fixture visuals and hazard cycles do not grow nodes")
	scene.queue_free()
	await process_frame
	return true

func _motion(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device=42
	event.axis=axis
	event.axis_value=value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device=42
	event.button_index=index
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _test_controller() -> bool:
	var scene := Fixture.instantiate()
	root.add_child(scene)
	await _frames(4)
	var source: Node=scene.input_source
	_check(scene.player.movement_input==source and source==scene.get_node("ControllerInput"), "M1 scene adapter is connected to the active P1A player")
	source.bind_device(42)
	_motion(JOY_AXIS_LEFT_X,0.1)
	_check(source.movement_vector().is_zero_approx(), "deadzone suppresses synthetic resting drift")
	_motion(JOY_AXIS_LEFT_X,0.61)
	_check(source.stick_vector().is_equal_approx(Vector2(0.5,0)), "analog half deflection after deadzone")
	_motion(JOY_AXIS_LEFT_X,1)
	var start: Vector3=scene.player.position
	await _frames(10)
	_check(scene.player.position.distance_to(start)>0.6, "synthetic stick moves real M1 capsule")
	Input.action_press("move_up")
	_check(is_equal_approx(source.movement_vector().length(),1) and source.movement_vector().x>0 and source.movement_vector().y<0, "keyboard and controller combine with normalized diagonal")
	Input.action_release("move_up")
	_motion(JOY_AXIS_LEFT_X,0)
	for pair in [[JOY_BUTTON_DPAD_LEFT,Vector2.LEFT],[JOY_BUTTON_DPAD_RIGHT,Vector2.RIGHT],[JOY_BUTTON_DPAD_UP,Vector2.UP],[JOY_BUTTON_DPAD_DOWN,Vector2.DOWN]]:
		_button(pair[0],true)
		_check(source.movement_vector().is_equal_approx(pair[1]), "D-pad logical direction %d" % pair[0])
		_button(pair[0],false)
	_motion(JOY_AXIS_LEFT_X,1)
	scene.reset_to_entry()
	await _frames(4)
	_check(source.movement_vector()==Vector2.RIGHT and scene.player.velocity.length()>0, "held controller remains live after entry reset")
	source.bind_device(-1)
	_check(source.movement_vector().is_zero_approx(), "synthetic disconnect releases scene actions")
	Input.action_press("move_left")
	_check(source.movement_vector()==Vector2.LEFT, "keyboard remains usable with controller disconnected")
	Input.action_release("move_left")
	source.bind_device(42)
	_motion(JOY_AXIS_LEFT_X,0)
	_motion(JOY_AXIS_LEFT_Y,0)
	await _frames(3)
	_check(source.movement_vector().is_zero_approx(), "re-entry with neutral controller has no unintended input")
	var event := InputEventKey.new()
	event.pressed=true
	event.physical_keycode=KEY_R
	scene._unhandled_key_input(event)
	_check(Grid.tile_at(scene.player.position)==scene.layout.player_spawn, "R returns to entry with controller adapter active")
	event.physical_keycode=KEY_H
	scene._unhandled_key_input(event)
	scene._physics_process(0.0)
	_check(scene.survey_visible and scene.status.text.contains("Pad ") and scene.status.text.contains("deadzone 0.22"), "H diagnostics display processed controller vector and deadzone")
	scene._unhandled_key_input(event)
	_check(not scene.survey_visible, "H diagnostics can be hidden without changing input")
	scene.queue_free()
	await process_frame
	return true
