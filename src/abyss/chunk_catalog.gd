extends RefCounted
## Stateless, lazy logical chunk catalog. No world-sized layout or history cache.

const Validator = preload("res://src/abyss/spatial_validator.gd")
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var config: AbyssStreamConfig
var world_seed: int
var world_id: String


func _init(settings: AbyssStreamConfig, seed_value: int) -> void:
	config = settings
	world_seed = seed_value
	world_id = "%016x" % StableHash.hash62("abyss-stream|v1|%d|%s" % [world_seed, config.identity()])


func chunk_id(cell: Vector2i) -> String:
	return "%s:%d:%d" % [world_id, cell.x, cell.y]


func edge_id(cell: Vector2i, other: Vector2i) -> String:
	var first := cell if cell.x < other.x or (cell.x == other.x and cell.y < other.y) else other
	var second := other if first == cell else cell
	return chunk_id(first) + ":to:%d:%d" % [second.x, second.y]


func room(cell: Vector2i) -> AbyssSpatialLayout.Room:
	var rng := RandomNumberGenerator.new()
	rng.seed = StableHash.hash62(chunk_id(cell) + "|room")
	var value := AbyssSpatialLayout.Room.new()
	var period := 2 * (config.level_count - 1)
	var phase := int(StableHash.hash62(world_id + "|phase") % period)
	var step := posmod(cell.x + phase, period)
	var base := mini(phase, period - phase)
	value.center = Vector3(cell.x * config.cell_spacing,
		(mini(step, period - step) - base) * config.level_height, cell.y * config.cell_spacing)
	value.size = Vector2(rng.randi_range(config.min_room_size, config.max_room_size),
		rng.randi_range(config.min_room_size, config.max_room_size))
	return value


func compose(cell: Vector2i) -> AbyssSpatialLayout:
	if not config.errors().is_empty() or not config.contains(cell):
		return null
	var layout := AbyssSpatialLayout.new()
	layout.run_seed = StableHash.hash62(chunk_id(cell))
	layout.graph = DungeonGraph.new()
	layout.graph.grid_size = Vector2i(3, 3)
	var center := room(cell)
	center.id = 0
	layout.rooms.append(center)
	layout.graph.add_space(Vector2i(1, 1), DungeonGraph.Role.ENTRY)
	layout.graph.main_path.append(0)
	for offset in SIDES:
		if not config.contains(cell + offset):
			continue
		var adjacent := room(cell + offset)
		adjacent.id = layout.rooms.size()
		layout.rooms.append(adjacent)
		layout.graph.add_space(Vector2i(1, 1) + offset, DungeonGraph.Role.BRANCH)
		var edge := layout.graph.connect_spaces(0, adjacent.id, DungeonGraph.LinkKind.BRANCH)
		var link := AbyssSpatialLayout.Connection.new()
		link.id = edge.id
		link.a = 0
		link.b = adjacent.id
		var direction := Vector3(offset.x, 0, offset.y)
		link.start = center.socket(direction)
		link.end = adjacent.socket(-direction)
		link.width = 4
		layout.connections.append(link)
	layout.graph.main_path.append(layout.rooms.size() - 1)
	layout.graph.spaces.back().role = DungeonGraph.Role.OBJECTIVE
	layout.spawn = center.center
	layout.exit = layout.rooms.back().center
	return layout if Validator.validate(layout).is_empty() else null


func owned_links(cell: Vector2i, layout: AbyssSpatialLayout) -> Array[int]:
	var result: Array[int] = []
	for link in layout.connections:
		var direction := link.direction()
		# West/north chunk owns each shared connector exactly once.
		if direction.x > 0.5 or direction.z > 0.5:
			result.append(link.id)
	return result
