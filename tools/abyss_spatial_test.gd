extends "res://tools/test_harness.gd"

const Composer = preload("res://src/abyss/spatial_composer.gd")
const Validator = preload("res://src/abyss/spatial_validator.gd")
const Geometry = preload("res://src/abyss/spatial_geometry.gd")
var _worst_generation_ms: float = 0
var _worst_build_ms: float = 0
var _max_boxes: int = 0
var _physical_links: int = 0
var _ray_probes: int = 0


func _suite_name() -> String:
	return "ABYSS SPATIAL"


func _get_tests() -> Array[Callable]:
	return [_test_seed_contract, _test_failures, _test_physical_geometry]


func _test_seed_contract() -> bool:
	var config := AbyssSpatialConfig.new()
	var signatures: Dictionary = {}
	var topology: Dictionary = {}
	var spatial: Dictionary = {}
	var all_valid := true
	var all_repeat := true
	var all_multilevel := true
	var max_attempts := 0
	for seed_value in 100:
		var a := Composer.new().generate(config, seed_value)
		seed(917)
		for i in 13:
			randi()
		var b := Composer.new().generate(config, seed_value)
		_worst_generation_ms = maxf(_worst_generation_ms, maxf(a.msec, b.msec))
		max_attempts = maxi(max_attempts, a.attempts)
		all_valid = all_valid and a.ok and b.ok
		if not a.ok or not b.ok:
			continue
		all_repeat = all_repeat and a.layout.fingerprint() == b.layout.fingerprint() and a.attempts == b.attempts
		all_valid = all_valid and Validator.validate(a.layout).is_empty()
		var heights: Dictionary = {}
		var cell_parts := PackedStringArray()
		var room_parts := PackedStringArray()
		for room in a.layout.rooms:
			heights[room.center.y] = true
			cell_parts.append(str(a.layout.graph.spaces[room.id].cell))
			room_parts.append(str(room.size) + str(room.center.y))
		all_multilevel = all_multilevel and heights.size() >= 2 and heights.size() <= config.level_count
		signatures[a.layout.fingerprint()] = true
		topology[str(cell_parts)] = true
		spatial[str(room_parts)] = true
	_check(all_valid, "100 seeds generate validated rooms, links, spawn and connected exit")
	_check(all_repeat, "100 repeated seeds preserve logical/spatial output despite global RNG disturbance")
	_check(signatures.size() == 100 and topology.size() > 80 and spatial.size() > 80,
		"meaningful topology/size/elevation variation across seeds")
	_check(all_multilevel, "all sampled layouts occupy multiple configured elevations")
	_check(max_attempts <= config.max_attempts, "all generation remains within bounded retries")
	var alternate := AbyssSpatialConfig.new()
	alternate.min_room_size = Vector2i(8, 9)
	alternate.max_room_size = Vector2i(20, 18)
	alternate.level_count = 5
	alternate.level_height = 3
	alternate.cell_spacing = 40
	alternate.connection_width = 3
	var alternate_valid := true
	for value in 12:
		var result := Composer.new().generate(alternate, value)
		alternate_valid = alternate_valid and result.ok
	_check(alternate_valid, "alternate rectangular sizes, five levels and 3m connections validate")
	var profiles_valid := true
	for depth in [2, 3]:
		var configured := AbyssSpatialConfig.new()
		configured.profile = DepthProfile.load_for_depth(depth)
		var result := Composer.new().generate(configured, 99)
		profiles_valid = profiles_valid and result.ok
	_check(profiles_valid, "existing depth-2 and depth-3 graph/pacing profiles also compose")
	print("ABYSS seed sample: 100 unique signatures, topology_variants=", topology.size(),
		" spatial_variants=", spatial.size(), " max_attempts=", max_attempts, " worst_generation_ms=", _worst_generation_ms)
	return true


func _fresh() -> AbyssSpatialLayout:
	return Composer.new().generate(AbyssSpatialConfig.new(), 12345).layout


func _test_failures() -> bool:
	var invalid := AbyssSpatialConfig.new()
	invalid.min_room_size = Vector2i(2, 2)
	var result := Composer.new().generate(invalid, 1)
	_check(not result.ok and result.layout == null and result.attempts == 0, "invalid configuration returns no partial layout")
	invalid = AbyssSpatialConfig.new()
	invalid.cell_spacing = NAN
	_check(not Composer.new().generate(invalid, 1).ok, "non-finite spacing fails safely")
	invalid = AbyssSpatialConfig.new()
	invalid.cell_spacing = 18
	_check(not Composer.new().generate(invalid, 1).ok, "insufficient ramp run fails before building")
	invalid = AbyssSpatialConfig.new()
	invalid.profile = invalid.profile.duplicate(true)
	invalid.profile.min_entry_exit_distance = 1000
	invalid.max_attempts = 3
	result = Composer.new().generate(invalid, 123)
	_check(not result.ok and result.layout == null and result.attempts == 3 and result.errors.size() == 3,
		"impossible topology exhausts exactly three attempts without partial layout")
	var layout := _fresh()
	layout.rooms[1].center = layout.rooms[0].center
	_check(Validator.validate(layout).has("room overlap"), "reject overlapping rooms")
	layout = _fresh()
	layout.connections[0].end += Vector3(0, 0, 1)
	_check(not Validator.validate(layout).is_empty(), "reject misaligned or disconnected bridge socket")
	layout = _fresh()
	layout.connections[0].end.y += 50
	_check(Validator.validate(layout).has("invalid connection alignment/slope"), "reject excessive slope")
	layout = _fresh()
	layout.connections[0].width = 0.5
	_check(not Validator.validate(layout).is_empty(), "reject insufficient capsule clearance")
	layout = _fresh()
	var unrelated: int = 0
	while unrelated == layout.connections[0].a or unrelated == layout.connections[0].b:
		unrelated += 1
	layout.rooms[unrelated].center = (layout.connections[0].start + layout.connections[0].end) * 0.5
	layout.rooms[unrelated].size = Vector2(8, 8)
	_check(Validator.validate(layout).has("connection intersects unrelated room"), "reject a room obstructing an unrelated link")
	layout = _fresh()
	layout.spawn += Vector3(100, 0, 0)
	_check(not Validator.validate(layout).is_empty(), "reject unsafe spawn")
	layout = _fresh()
	layout.exit.y += 2
	_check(not Validator.validate(layout).is_empty(), "reject floating exit")
	layout = _fresh()
	layout.connections.clear()
	_check(not Validator.validate(layout).is_empty(), "reject inaccessible platforms and disconnected exit")
	var geometry := Geometry.new()
	root.add_child(geometry)
	_check(not geometry.build(layout) and geometry.get_child_count() == 0, "builder refuses invalid data without partial geometry")
	geometry.queue_free()
	await process_frame
	var failed_demo := preload("res://src/abyss/generated_demo.tscn").instantiate()
	var failed_config := AbyssSpatialConfig.new()
	failed_config.cell_spacing = 18
	failed_demo.spatial_config = failed_config
	root.add_child(failed_demo)
	await _frames(3)
	_check(failed_demo.layout == null and not failed_demo.get_node("Player3D").is_physics_processing()
		and "failed safely" in str(failed_demo.get_node("Instructions/Label").text),
		"invalid demo disables movement and displays failure instead of spawning into void")
	failed_demo.queue_free()
	await process_frame
	return true


func _test_physical_geometry() -> bool:
	var demo_scene := preload("res://src/abyss/generated_demo.tscn")
	var all_surfaces := true
	var all_walks := true
	var all_guards := true
	var exit_reached := true
	for value in [12345, 42, 7, 91]:
		var demo := demo_scene.instantiate()
		demo.world_seed = value
		if value == 91:
			var config := AbyssSpatialConfig.new()
			config.min_room_size = Vector2i(8, 9)
			config.max_room_size = Vector2i(20, 18)
			config.level_count = 5
			config.level_height = 3
			config.cell_spacing = 40
			config.connection_width = 3
			demo.spatial_config = config
		root.add_child(demo)
		var layout: AbyssSpatialLayout = demo.layout
		_check(layout != null, "generated scene seed %d has a validated layout" % value)
		if layout == null:
			demo.queue_free()
			await process_frame
			continue
		var player: CharacterBody3D = demo.get_node("Player3D")
		var camera: Camera3D = demo.get_node("Camera")
		var input_source: Node = demo.get_node("MovementInput")
		input_source.bind_device(-1)
		await _frames(12)
		var geometry: Node3D = demo.geometry
		_worst_build_ms = maxf(_worst_build_ms, geometry.build_msec)
		_max_boxes = maxi(_max_boxes, geometry.box_count)
		for room in layout.rooms:
			for x in [-0.3, 0.0, 0.3]:
				for z in [-0.3, 0.0, 0.3]:
					all_surfaces = _probe(player, room.center + Vector3(x * room.size.x, 0, z * room.size.y)) and all_surfaces
		for link in layout.connections:
			var steps := ceili(link.start.distance_to(link.end))
			var side := link.direction().cross(Vector3.UP)
			for i in steps + 1:
				for lateral in [-1.0, 0.0, 1.0]:
					all_surfaces = _probe(player, link.start.lerp(link.end, float(i) / steps) + side * lateral) and all_surfaces
			# Walk from each endpoint's room center through its doorway/ramp to the
			# opposite room center in both directions, using the real camera mapping.
			for reverse in [false, true]:
				var start_id: int = link.b if reverse else link.a
				var end_id: int = link.a if reverse else link.b
				player.position = layout.rooms[start_id].center + Vector3.UP * 0.05
				player.velocity = Vector3.ZERO
				await _frames(12)
				all_walks = await _walk(player, camera, layout.rooms[end_id].center) and all_walks
				_physical_links += 1
			# Push sideways at the middle of every bridge/ramp into its guardrail.
			player.position = (link.start + link.end) * 0.5 + Vector3.UP * 0.05
			player.velocity = Vector3.ZERO
			await _frames(12)
			_drive(camera, side)
			await _frames(70)
			_release()
			var lateral_distance := absf((player.position - (link.start + link.end) * 0.5).dot(side))
			all_guards = all_guards and lateral_distance < link.width * 0.5 and player.is_on_wall() and player.is_on_floor()
		# Continuous main-path walk: no teleport between entry and exit.
		player.position = layout.spawn + Vector3.UP * 0.05
		player.velocity = Vector3.ZERO
		await _frames(12)
		for id in layout.graph.main_path:
			exit_reached = await _walk(player, camera, layout.rooms[id].center) and exit_reached
		await _frames(5)
		exit_reached = exit_reached and player.position.distance_to(layout.exit) < 0.3 \
			and "EXIT REACHED" in str(demo.get_node("Instructions/Label").text)
		demo.queue_free()
		await process_frame
	_check(all_surfaces, "sampled room floors, ramp/bridge widths and endpoint seams have physical support")
	_check(all_walks, "every link in four configurations traversed both directions by original capsule physics")
	_check(all_guards, "every sampled bridge/ramp guardrail blocks movement without loss of floor support")
	_check(exit_reached, "continuous camera-relative entry-to-exit walks reach demo completion in four configurations")
	_check(_max_boxes < 800, "sampled geometry remains below provisional 800-box cap")
	print("ABYSS measured generation_max_ms=", _worst_generation_ms, " build_max_ms=", _worst_build_ms,
		" max_boxes=", _max_boxes, " link_traversals=", _physical_links, " support_probes=", _ray_probes,
		" process_static_bytes=", OS.get_static_memory_usage(), " FPS=not_measured")
	return true


func _probe(player: CharacterBody3D, expected: Vector3) -> bool:
	_ray_probes += 1
	var query := PhysicsRayQueryParameters3D.create(expected + Vector3.UP * 2,
		expected - Vector3.UP * 2, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(hit.position.y - expected.y) < 0.06


func _walk(player: CharacterBody3D, camera: Camera3D, target: Vector3) -> bool:
	var distance := Vector2(target.x - player.position.x, target.z - player.position.z).length()
	for frame in ceili(distance / 4.0 * 60) + 90:
		var delta := target - player.position
		delta.y = 0
		if delta.length() < 0.18:
			_release()
			await _frames(3)
			return absf(player.position.y - target.y) < 0.1 and player.is_on_floor()
		_drive(camera, delta.normalized())
		await physics_frame
	_release()
	return false


func _drive(camera: Camera3D, direction: Vector3) -> void:
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0
	forward.y = 0
	var vector := Vector2(direction.dot(right.normalized()), -direction.dot(forward.normalized()))
	_release()
	if vector.x < 0:
		Input.action_press("move_left", -vector.x)
	else:
		Input.action_press("move_right", vector.x)
	if vector.y < 0:
		Input.action_press("move_up", -vector.y)
	else:
		Input.action_press("move_down", vector.y)


func _release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
