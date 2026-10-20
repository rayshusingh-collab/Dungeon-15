extends "res://tools/test_harness.gd"
const Scene = preload("res://src/game_3d/first_dungeon.tscn")
const Grid = preload("res://src/game_3d/grid_space.gd")
const T = DungeonLayout.Tile

func _suite_name() -> String:
	return "M1 FIRST DUNGEON"

func _get_tests() -> Array[Callable]:
	return [_test_floors, _test_terrain_fixture, _test_input]

func _test_floors() -> bool:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for seed_value in [12345, 42, 7]:
		var scene := Scene.instantiate()
		scene.run_seed = seed_value
		root.add_child(scene)
		await _frames(4)
		var data: DungeonLayout = scene.layout
		_check(data.errors.is_empty(), "seed %d generator validated" % seed_value)
		_check(data.fingerprint() == DungeonGenerator.new().generate(DepthProfile.load_for_depth(1), seed_value, 1).layout.fingerprint(), "deterministic repeat")
		if seed_value != 7:
			_check(data.fingerprint() == {12345: "2994f8107a89ee44", 42: "31476b85897e6431"}[seed_value], "existing golden baseline")
		var coverage := PackedByteArray()
		coverage.resize(data.tiles.size())
		var exact := true
		for piece: Dictionary in scene.rects:
			var rect: Rect2i = piece.rect
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var i := data.index_of(Vector2i(x, y))
					coverage[i] += 1
					exact = exact and data.tiles[i] == piece.kind
		for i in data.tiles.size():
			exact = exact and coverage[i] == (0 if data.tiles[i] == T.VOID else 1)
		_check(exact, "all geometry rectangles exactly cover source terrain once")
		await physics_frame
		var hits_match := true
		var counts := {}
		for y in data.size.y:
			for x in data.size.x:
				var tile := Vector2i(x, y)
				var kind := data.get_tile(tile)
				counts[kind] = counts.get(kind, 0) + 1
				var origin := Grid.center(tile, 3)
				var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4, 1)
				var hit := root.world_3d.direct_space_state.intersect_ray(query)
				var supported := kind != T.VOID and kind != T.PIT
				hits_match = hits_match and (not hit.is_empty()) == supported
				if not hit.is_empty():
					hits_match = hits_match and absf(hit.position.y - (1.0 if DungeonLayout.is_solid_kind(kind) else 0.0)) < 0.001
		_check(hits_match, "physics ray every tile: solids height 1, supported ground 0, pits/void open")
		print("TERRAIN seed=", seed_value, " counts=", counts)
		var player: CharacterBody3D = scene.player
		_check(Grid.tile_at(player.position) == data.player_spawn and player.is_on_floor(), "clear supported entrance spawn")
		_check(Grid.pixels(Grid.center(data.exit_tile)).is_equal_approx(data.tile_center(data.exit_tile)), "metres to pixel navigation conversion")
		# Physically walk the full cardinal route with the real capsule and move_and_slide.
		# Wait on safe ground for the next retracted phase before a hazard run.
		player.set_physics_process(false)
		var walked := true
		var started := Time.get_ticks_usec()
		var route_resets: int = scene.resets
		for tile: Vector2i in scene.route:
			if data.get_tile(tile) == T.HAZARD and data.get_tile(Grid.tile_at(player.position)) != T.HAZARD:
				while fmod(scene.elapsed, scene.safe_seconds + scene.WARNING_SECONDS + scene.RAISED_SECONDS) > 0.03:
					await physics_frame
			var target := Grid.center(tile)
			var steps := 0
			while Vector2(player.position.x - target.x, player.position.z - target.z).length() > 0.06 and steps < 100:
				var dir := (target - player.position)
				dir.y = 0
				player.velocity = dir.normalized() * minf(2.5 if data.get_tile(Grid.tile_at(player.position)) == T.WATER else 5.0, dir.length() * 60.0)
				player.velocity.y = -1
				player.move_and_slide()
				steps += 1
				await physics_frame
			if steps == 100 or not player.is_on_floor():
				walked = false
				break
		_check(walked and scene.resets == route_resets and Grid.tile_at(player.position) == data.exit_tile, "full entrance-exit route physically traversed with capsule, water slowdown and timed spikes")
		print("ROUTE tiles=", scene.route.size(), " wall_ms=", (Time.get_ticks_usec() - started) / 1000.0)
		# Exercise actual terrain rules without disabling P1A physics.
		player.set_physics_process(true)
		scene.set_physics_process(true)
		await _frames(2)
		_check(scene.reached_exit, "exit arrival reports completion without loading another depth")
		for kind: int in [T.WATER, T.BRIDGE, T.PIT, T.HAZARD]:
			var index := data.tiles.find(kind)
			if index < 0:
				continue
			var tile := Vector2i(index % data.size.x, floori(float(index) / data.size.x))
			player.position = Grid.center(tile, 0.05)
			player.velocity = Vector3.ZERO
			if kind == T.HAZARD:
				scene.elapsed = 0
			await _frames(5)
			if kind == T.WATER:
				_check(player.move_speed == 2.5 and player.is_on_floor(), "water slows but supports")
			elif kind == T.BRIDGE:
				_check(player.is_on_floor(), "bridge supports capsule")
			elif kind == T.PIT:
				var resets: int = scene.resets
				await _frames(70)
				_check(scene.resets > resets and Grid.tile_at(player.position) == data.player_spawn, "pit fall resets to entrance")
			else:
				_check(Grid.tile_at(player.position) == tile, "retracted spikes permit standing")
				scene.elapsed = scene.safe_seconds + 0.1
				await _frames(2)
				_check(scene.spike_phase == 1 and Grid.tile_at(player.position) == tile, "spike warning permits crossing")
				scene.elapsed = scene.safe_seconds + 0.7
				await _frames(2)
				_check(Grid.tile_at(player.position) == data.player_spawn, "raised spikes reset")
		var nodes := get_node_count()
		await _frames(300)
		_check(get_node_count() == nodes, "steady runtime has no node growth")
		print("PERF physics_ms=", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, " process_ms=", Performance.get_monitor(Performance.TIME_PROCESS) * 1000, " peak_bytes=", OS.get_static_memory_peak_usage())
		scene.queue_free()
		await process_frame
		await process_frame
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_before, "repeated scene teardown leaves no orphan nodes")
	return true

func _test_input() -> bool:
	var scene := Scene.instantiate()
	var actions_before := InputMap.get_actions()
	var shared_before := str(InputMap.action_get_events("move_left"), InputMap.action_get_events("move_right"), InputMap.action_get_events("move_up"), InputMap.action_get_events("move_down"))
	root.add_child(scene)
	await _frames(4)
	var source: Node = scene.input_source
	source.bind_device(42)
	for pair in [[JOY_AXIS_LEFT_X, 1.0, Vector2.RIGHT], [JOY_AXIS_LEFT_Y, -1.0, Vector2.UP]]:
		var event := InputEventJoypadMotion.new()
		event.device = 42
		event.axis = pair[0]
		event.axis_value = pair[1]
		Input.parse_input_event(event.duplicate())
		Input.flush_buffered_events()
		_check(source.movement_vector().is_equal_approx(pair[2]), "synthetic controller axis")
		event.axis_value = 0
		Input.parse_input_event(event.duplicate())
		Input.flush_buffered_events()
	for button: int in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		var event := InputEventJoypadButton.new()
		event.device = 42
		event.button_index = button
		event.pressed = true
		Input.parse_input_event(event.duplicate())
		Input.flush_buffered_events()
		_check(source.movement_vector().length() == 1, "synthetic D-pad")
		event.pressed = false
		Input.parse_input_event(event.duplicate())
		Input.flush_buffered_events()
	var start: Vector3 = scene.player.position
	Input.action_press("move_right")
	await _frames(12)
	Input.action_release("move_right")
	_check(scene.player.position.distance_to(start) > 0.7, "keyboard drives inherited P1A physics")
	scene.queue_free()
	await process_frame
	_check(InputMap.get_actions() == actions_before, "scene input actions removed on exit")
	_check(shared_before == str(InputMap.action_get_events("move_left"), InputMap.action_get_events("move_right"), InputMap.action_get_events("move_up"), InputMap.action_get_events("move_down")), "global movement bindings preserved")
	return true


func _test_terrain_fixture() -> bool:
	# Explicit fixture covers terrain absent from the three depth-1 sample layouts.
	# It is test data only, never a replacement for generated runtime tiles.
	var scene := Scene.instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.geometry.free()
	scene.rects.clear()
	var data := DungeonLayout.new()
	data.init_grid(Vector2i(8, 5))
	data.player_spawn = Vector2i(1, 2)
	data.exit_tile = Vector2i(6, 2)
	for y in 5:
		for x in 8:
			data.set_tile(Vector2i(x, y), T.WALL if x == 0 or y == 0 or x == 7 or y == 4 else T.FLOOR, 0)
	data.set_tile(Vector2i(3, 1), T.PIT, 0)
	data.set_tile(Vector2i(3, 2), T.BRIDGE, 0)
	data.set_tile(Vector2i(3, 3), T.PIT, 0)
	data.set_tile(Vector2i(4, 2), T.WATER, 0)
	scene.layout = data
	scene._build_geometry()
	await _frames(3)
	var player: CharacterBody3D = scene.player
	for tile in [Vector2i(3, 2), Vector2i(4, 2)]:
		player.position = Grid.center(tile, 0.05)
		player.velocity = Vector3.ZERO
		await _frames(6)
		_check(player.is_on_floor(), "fixture bridge/water physically supports capsule")
	_check(player.move_speed == 2.5, "fixture water slowdown")
	player.position = Grid.center(Vector2i(3, 1), 0.05)
	player.velocity = Vector3.ZERO
	var resets: int = scene.resets
	await _frames(65)
	_check(scene.resets == resets + 1 and Grid.tile_at(player.position) == data.player_spawn, "fixture pit has no floor and fall returns to entry")
	# Cross the bridge with inherited movement; pits on either side stay open.
	player.position = Grid.center(Vector2i(2, 2), 0.05)
	player.velocity = Vector3.ZERO
	player.movement_camera = null
	await _frames(3)
	Input.action_press("move_right")
	await _frames(55)
	Input.action_release("move_right")
	_check(player.position.x > Grid.center(Vector2i(3, 2)).x and player.is_on_floor() and scene.resets == resets + 1, "bridge physically crossed with keyboard physics")
	Input.action_press("move_up")
	await _frames(90)
	Input.action_release("move_up")
	_check(player.is_on_wall() and player.position.z >= 2.34, "fixture boundary blocks capsule")
	scene.queue_free()
	await process_frame
	return true
