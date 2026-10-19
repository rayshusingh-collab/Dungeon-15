extends "res://tools/test_harness.gd"

const Catalog = preload("res://src/abyss/chunk_catalog.gd")
const Validator = preload("res://src/abyss/spatial_validator.gd")
const Scene = preload("res://src/abyss/streaming_demo.tscn")
var _safe: bool = true
var _budget: bool = true
var _probes: int = 0


func _suite_name() -> String:
	return "ABYSS STREAM"


func _get_tests() -> Array[Callable]:
	return [_test_catalog, _test_startup_failure, _test_travel_and_revisit, _test_gated_failure, _test_world_edges]


func _test_catalog() -> bool:
	var config := AbyssStreamConfig.new()
	var a := Catalog.new(config, 12345)
	var b := Catalog.new(config, 12345)
	var valid := true
	var stable := true
	var seams := true
	var owners := true
	var ids: Dictionary = {}
	for z in range(-config.world_radius, config.world_radius + 1):
		for x in range(-config.world_radius, config.world_radius + 1):
			var cell := Vector2i(x, z)
			var data := a.compose(cell)
			valid = valid and data != null and Validator.validate(data).is_empty()
			if data == null:
				continue
			stable = stable and data.fingerprint() == b.compose(cell).fingerprint()
			ids[a.chunk_id(cell)] = true
			for link in data.connections:
				var dir := link.direction()
				var neighbour := cell + Vector2i(roundi(dir.x), roundi(dir.z))
				var other := a.compose(neighbour)
				var matched := false
				for counterpart in other.connections:
					if counterpart.direction().is_equal_approx(-dir):
						matched = counterpart.start.is_equal_approx(link.end) and counterpart.end.is_equal_approx(link.start)
						var count := int(a.owned_links(cell, data).has(link.id)) + int(a.owned_links(neighbour, other).has(counterpart.id))
						owners = owners and count == 1
				seams = seams and matched and a.edge_id(cell, neighbour) == a.edge_id(neighbour, cell)
	_check(valid, "all 289 default world coordinates produce validated bounded logical neighbourhoods")
	_check(stable and ids.size() == 289, "stable unique chunk IDs and deterministic reconstruction across catalog instances")
	_check(seams, "every adjacent pair agrees on world-coordinate endpoints and connection identity")
	_check(owners, "every shared bridge/ramp has exactly one owner")
	_check(a.compose(Vector2i(99, 99)) == null, "outside-world requests fail safely")
	var other_seed := Catalog.new(config, 42)
	_check(a.chunk_id(Vector2i.ZERO) != other_seed.chunk_id(Vector2i.ZERO)
		and a.compose(Vector2i.ZERO).fingerprint() != other_seed.compose(Vector2i.ZERO).fingerprint(), "seed changes world identity and geometry")
	config.cell_spacing = 18
	_check(not config.errors().is_empty() and a.compose(Vector2i.ZERO) == null, "unsafe spacing rejected without geometry")
	return true


func _test_startup_failure() -> bool:
	var demo := Scene.instantiate()
	var streamer: Node3D = demo.get_node("Streamer")
	streamer.settings = AbyssStreamConfig.new()
	streamer.settings.retry_frames = 4
	streamer.debug_failures[Vector2i.ZERO] = 1
	root.add_child(demo)
	var player: CharacterBody3D = demo.get_node("Player3D")
	await _frames(2)
	_check(not player.is_physics_processing() and player.position.y > -0.01, "startup failure pauses player before unsupported movement")
	_check(await _wait_until(func() -> bool: return streamer.is_ready(Vector2i.ZERO) and player.is_physics_processing(), 100),
		"transient initial load failure recovers after bounded retry and collision delay")
	await _frames(10)
	_check(player.is_on_floor(), "recovered startup provides actual capsule support")
	demo.queue_free()
	await process_frame
	return true


func _test_travel_and_revisit() -> bool:
	var demo := Scene.instantiate()
	root.add_child(demo)
	var streamer: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	_check(await _wait_until(func() -> bool: return streamer.active.size() == 9 and streamer.is_ready(Vector2i.ZERO), 100), "initial 3x3 neighbourhood loads incrementally")
	await _frames(10)
	var original_id: String = streamer.active[Vector2i.ZERO].id
	var original: String = streamer.active[Vector2i.ZERO].fingerprint
	var original_node: WeakRef = weakref(streamer.active[Vector2i.ZERO].geometry)
	var walked := true
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2)]:
		walked = await _walk(streamer, player, camera, cell) and walked
	_check(walked and _safe, "player crosses ramps, bridges and chunk boundaries without missing collision or support")
	_check(not streamer.active.has(Vector2i.ZERO) and original_node.get_ref() == null and streamer.unloaded_count > 0,
		"distant geometry/data unload and original geometry is freed")
	_check(streamer.world_state.has(Vector2i.ZERO) and streamer.world_state[Vector2i.ZERO].visited,
		"bounded world state survives geometry eviction")
	for cell in [Vector2i(3, 1), Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0), Vector2i.ZERO]:
		walked = await _walk(streamer, player, camera, cell) and walked
	_check(walked and streamer.active[Vector2i.ZERO].fingerprint == original and streamer.active[Vector2i.ZERO].id == original_id,
		"return trip reconstructs identical geometry identity from seed and retained state")
	_check(_budget and streamer.max_resident <= 9 and streamer.active.size() <= 9,
		"generation jobs and resident chunk counts stay within configured limits throughout travel")
	_check(streamer.world_state.size() <= 289 and streamer.failures.size() <= 9 and streamer.max_active_boxes <= 171,
		"world-state, failure records and active geometry remain bounded")
	# Verify real collision at every active link socket/width after reconstruction.
	var surfaces := true
	for cell: Vector2i in streamer.active:
		var record: Dictionary = streamer.active[cell]
		for id in streamer.catalog.owned_links(cell, record.data):
			var link: AbyssSpatialLayout.Connection = record.data.connections[id]
			var side := link.direction().cross(Vector3.UP)
			for i in 25:
				for offset in [-1.0, 0.0, 1.0]:
					var expected: Vector3 = link.start.lerp(link.end, float(i) / 24) + side * offset
					var query := PhysicsRayQueryParameters3D.create(expected + Vector3.UP * 0.3, expected - Vector3.UP * 0.5, 1)
					var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
					surfaces = surfaces and not hit.is_empty() and absf(hit.position.y - expected.y) < 0.07
					_probes += 1
	_check(surfaces, "reconstructed active connectors retain continuous floor width and endpoint seams")
	print("STREAM measurements: ", streamer.diagnostic_text(), " probes=", _probes,
		" process_static_bytes=", OS.get_static_memory_usage(), " FPS=not_measured")
	demo.queue_free()
	await process_frame
	return true


func _test_gated_failure() -> bool:
	var demo := Scene.instantiate()
	var streamer: Node3D = demo.get_node("Streamer")
	streamer.settings = AbyssStreamConfig.new()
	streamer.settings.retry_frames = 4
	streamer.debug_failures[Vector2i.RIGHT] = 99
	root.add_child(demo)
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	await _frames(50)
	_check(not streamer.is_ready(Vector2i.RIGHT) and streamer.failures[Vector2i.RIGHT].attempts == 3,
		"persistent neighbour failure stops after configured attempt cap")
	var before: int = streamer.failures[Vector2i.RIGHT].attempts
	_drive(camera, Vector3.RIGHT)
	await _frames(150)
	_release()
	var room: AbyssSpatialLayout.Room = streamer.catalog.room(Vector2i.ZERO)
	_check(player.position.x < room.size.x * 0.5 and player.is_on_wall() and player.is_on_floor(),
		"closed load gate blocks entry toward failed chunk without falling")
	_check(streamer.failures[Vector2i.RIGHT].attempts == before, "exhausted failures do not retry indefinitely")
	streamer.debug_failures[Vector2i.RIGHT] = 0
	streamer.retry_failed()
	_check(await _wait_until(func() -> bool: return streamer.is_ready(Vector2i.RIGHT), 100), "explicit retry recovers failed neighbour")
	await _frames(4)
	_check(await _walk(streamer, player, camera, Vector2i.RIGHT), "recovered gate opens onto physically navigable collision")
	demo.queue_free()
	await process_frame
	return true


func _walk(streamer: Node3D, player: CharacterBody3D, camera: Camera3D, cell: Vector2i) -> bool:
	var target: Vector3 = streamer.catalog.room(cell).center
	for frame in 800:
		var delta := target - player.position
		delta.y = 0
		if delta.length() < 0.18:
			_release()
			await _frames(4)
			return player.is_on_floor() and absf(player.position.y - target.y) < 0.1
		_drive(camera, delta.normalized())
		await physics_frame
		_safe = _safe and player.is_on_floor() and absf(player.position.y) < 20
		_budget = _budget and streamer.active.size() <= streamer.settings.capacity() \
			and streamer.last_jobs <= streamer.settings.jobs_per_frame
	_release()
	return false


func _test_world_edges() -> bool:
	var demo := Scene.instantiate()
	var streamer: Node3D = demo.get_node("Streamer")
	streamer.settings = AbyssStreamConfig.new()
	streamer.settings.world_radius = 2
	streamer.settings.load_radius = 2
	streamer.settings.jobs_per_frame = 2
	root.add_child(demo)
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	_check(await _wait_until(func() -> bool: return streamer.active.size() == 25, 100), "configurable 5x5 load radius respects 25-chunk cap")
	await _frames(5)
	var reached := true
	for cell in [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-2, -2)]:
		reached = await _walk(streamer, player, camera, cell) and reached
	_check(reached and _budget and _safe, "negative coordinates and finite-world corners remain navigable with two jobs per frame")
	_drive(camera, Vector3.LEFT)
	await _frames(150)
	_release()
	var room: AbyssSpatialLayout.Room = streamer.catalog.room(Vector2i(-2, -2))
	_check(player.position.x > room.center.x - room.size.x * 0.5 and player.is_on_wall() and player.is_on_floor(),
		"permanent outer wall safely closes the finite world edge")
	_check(streamer.world_state.size() <= 25 and streamer.active.size() <= 25 and streamer.active_boxes <= 475,
		"alternate configuration preserves all count and state bounds")
	demo.queue_free()
	await process_frame
	var invalid_demo := Scene.instantiate()
	var invalid_streamer: Node3D = invalid_demo.get_node("Streamer")
	invalid_streamer.settings = AbyssStreamConfig.new()
	invalid_streamer.settings.jobs_per_frame = 0
	root.add_child(invalid_demo)
	await _frames(5)
	_check(invalid_streamer.active.is_empty() and not invalid_demo.get_node("Player3D").is_physics_processing()
		and not invalid_streamer.error_message.is_empty(), "invalid streaming configuration fails closed with player disabled")
	invalid_demo.queue_free()
	await process_frame
	return true


func _drive(camera: Camera3D, direction: Vector3) -> void:
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0
	forward.y = 0
	var vector := Vector2(direction.dot(right.normalized()), -direction.dot(forward.normalized()))
	_release()
	Input.action_press("move_left" if vector.x < 0 else "move_right", absf(vector.x))
	Input.action_press("move_up" if vector.y < 0 else "move_down", absf(vector.y))


func _release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
