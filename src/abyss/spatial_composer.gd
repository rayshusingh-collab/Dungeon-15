extends RefCounted
## Separate versioned RNG namespace. Legacy graph/pacing code and profiles unchanged.

const Validator = preload("res://src/abyss/spatial_validator.gd")

class Result:
	var ok: bool = false
	var layout: AbyssSpatialLayout
	var attempts: int = 0
	var errors: PackedStringArray = []
	var msec: float = 0


func generate(config: AbyssSpatialConfig, run_seed: int) -> Result:
	var result := Result.new()
	var started := Time.get_ticks_usec()
	if config == null:
		result.errors.append("missing spatial config")
	else:
		result.errors = config.errors()
	if result.errors.is_empty():
		for attempt in config.max_attempts:
			result.attempts = attempt + 1
			var layout := _attempt(config, run_seed, attempt)
			var errors := Validator.validate(layout)
			if errors.is_empty():
				var heights: Dictionary = {}
				for room in layout.rooms:
					heights[room.center.y] = true
				if heights.size() < 2:
					errors.append("composition needs multiple elevations")
			if errors.is_empty():
				result.ok = true
				result.layout = layout
				break
			result.errors.append("attempt %d: %s" % [attempt, errors[0]])
	result.msec = (Time.get_ticks_usec() - started) / 1000.0
	return result


func _rng(run_seed: int, attempt: int, stream: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = StableHash.hash62("abyss-spatial|v1|%d|%d|%s" % [run_seed, attempt, stream])
	return rng


func _attempt(config: AbyssSpatialConfig, run_seed: int, attempt: int) -> AbyssSpatialLayout:
	var layout := AbyssSpatialLayout.new()
	layout.run_seed = run_seed
	layout.attempt = attempt
	layout.graph = GraphBuilder.build(config.profile, _rng(run_seed, attempt, "graph"))
	if not layout.graph.error.is_empty():
		return layout
	PacingDirector.direct(layout.graph, config.profile, _rng(run_seed, attempt, "pacing"))
	var rng := _rng(run_seed, attempt, "spatial")
	var axis := rng.randi_range(0, 1)
	var phase := rng.randi_range(0, config.level_count * 2 - 3)
	var entry_cell := layout.graph.spaces[layout.graph.entry_id()].cell
	var base_level := _level(entry_cell[axis], phase, config.level_count)
	for space in layout.graph.spaces:
		var room := AbyssSpatialLayout.Room.new()
		room.id = space.id
		var offset := space.cell - entry_cell
		room.center = Vector3(offset.x * config.cell_spacing,
			(_level(space.cell[axis], phase, config.level_count) - base_level) * config.level_height,
			offset.y * config.cell_spacing)
		room.size = Vector2(rng.randi_range(config.min_room_size.x, config.max_room_size.x),
			rng.randi_range(config.min_room_size.y, config.max_room_size.y))
		layout.rooms.append(room)
	for edge in layout.graph.links:
		var connection := AbyssSpatialLayout.Connection.new()
		connection.id = edge.id
		connection.a = edge.a
		connection.b = edge.b
		var direction := layout.rooms[edge.b].center - layout.rooms[edge.a].center
		direction.y = 0
		direction = direction.normalized()
		connection.start = layout.rooms[edge.a].socket(direction)
		connection.end = layout.rooms[edge.b].socket(-direction)
		connection.width = config.connection_width
		layout.connections.append(connection)
	layout.spawn = layout.rooms[layout.graph.entry_id()].center
	layout.exit = layout.rooms[layout.graph.objective_id()].center
	return layout


func _level(coordinate: int, phase: int, count: int) -> int:
	var period := 2 * (count - 1)
	var position := posmod(coordinate + phase, period)
	return mini(position, period - position)
