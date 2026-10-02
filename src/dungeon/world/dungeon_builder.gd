class_name DungeonBuilder
extends RefCounted
## Turns a validated DungeonLayout into a DungeonWorld node tree. This is pure
## instantiation: every decision was already made (and validated) by the
## generator, so the same layout always builds the same world.
## Static geometry is batched: one TileMapLayer for visuals, one wall body with
## greedy-merged rectangles, one water zone and one pit zone per room.


static func build(layout: DungeonLayout) -> DungeonWorld:
	var world := DungeonWorld.new()
	world.name = "DungeonWorld"
	world.layout = layout
	world.player_spawn = layout.tile_center(layout.player_spawn)
	world.navigation = DungeonNavigation.new(layout)

	var tiles := TileMapLayer.new()
	tiles.name = "Tiles"
	tiles.tile_set = PlaceholderTileset.get_tileset()
	_paint_tiles(layout, tiles)
	world.add_child(tiles)

	var decor := DecorLayer.new()
	decor.setup(layout)
	world.add_child(decor)

	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	var solid_rects := merge_rects(layout, Rect2i(Vector2i.ZERO, layout.size),
			func(i: int) -> bool: return DungeonLayout.is_solid_kind(layout.tiles[i]))
	for rect in solid_rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var owner_id := walls.create_shape_owner(walls)
		walls.shape_owner_add_shape(owner_id, shape)
		walls.shape_owner_set_transform(owner_id, Transform2D(0.0, rect.get_center()))
	world.wall_shape_count = solid_rects.size()
	world.add_child(walls)

	var terrain := Node2D.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	var hazards := Node2D.new()
	hazards.name = "Hazards"
	world.add_child(hazards)
	var content := Node2D.new()
	content.name = "Content"
	world.add_child(content)
	var rooms_node := Node2D.new()
	rooms_node.name = "Rooms"
	world.add_child(rooms_node)
	world.actors = Node2D.new()
	world.actors.name = "Actors"
	world.add_child(world.actors)

	for data in layout.rooms:
		var room := DungeonRoom.new()
		room.setup(data, layout, world.actors, world.navigation)
		rooms_node.add_child(room)
		world.rooms.append(room)
		room.entered.connect(world.room_entered.emit)
		room.encounter_started.connect(world.encounter_started.emit)
		room.enemies_remaining_changed.connect(world.enemies_remaining_changed.emit)
		room.encounter_cleared.connect(world._on_room_encounter_cleared)
		_add_terrain(layout, data, world, terrain)
		for hazard in data.hazards:
			if hazard.type == &"spikes":
				var trap := SpikeTrap.new()
				var hazard_tiles: Array[Vector2i] = hazard.tiles
				var first: Vector2i = hazard_tiles[0]
				trap.setup(hazard_tiles, float((first.x * 7 + first.y * 13) % 17) * 0.1)
				hazards.add_child(trap)
				world.hazards.append(trap)
		for marker_data in data.markers:
			if marker_data.kind == &"story":
				continue
			var marker := RoomMarker.new()
			marker.setup(layout.tile_center(marker_data.tile), marker_data.kind)
			marker.collected.connect(world.marker_collected.emit)
			content.add_child(marker)
			world.markers.append(marker)
		if data.template.content_scene != null:
			var authored := data.template.content_scene.instantiate() as Node2D
			authored.position = layout.tile_center(data.anchor)
			content.add_child(authored)
		if data.role == DungeonGraph.Role.ENTRY:
			content.add_child(_label("ENTRY", layout.tile_center(data.anchor) + Vector2(0, -70), Color(0.6, 0.8, 1.0)))

	for socket in layout.event_sockets:
		if not socket.armed:
			continue
		var trigger := EventTrigger.new()
		trigger.setup(layout.tile_center(socket.tile), socket.tile, socket.kind)
		trigger.triggered.connect(world.tension_event.emit)
		content.add_child(trigger)
		world.event_triggers.append(trigger)

	var objective := layout.objective_room()
	world.depth_exit = DepthExit.new()
	world.depth_exit.name = "DepthExit"
	world.depth_exit.setup(layout.tile_center(layout.exit_tile), objective.encounter != DungeonGraph.Encounter.NONE)
	world.depth_exit.reached.connect(world.exit_reached.emit)
	content.add_child(world.depth_exit)
	return world


## Floor tint by room role (placeholder readability): red = locked fight,
## green-grey = terrain challenge, purple = optional side content. Ambush
## rooms deliberately look like quiet rooms; their fairness comes from open
## doors, the spawn telegraph and the spawn distance, not from a tint.
static func floor_look(data: DungeonLayout.PlacedRoom) -> int:
	match data.tactic:
		RoomRole.ENTRY:
			return PlaceholderTileset.Look.FLOOR_ENTRY
		RoomRole.OBJECTIVE:
			return PlaceholderTileset.Look.FLOOR_OBJECTIVE
		RoomRole.STORY:
			return PlaceholderTileset.Look.FLOOR_SPECIAL
		RoomRole.COMBAT, RoomRole.HAZARD_COMBAT, RoomRole.CHALLENGE:
			return PlaceholderTileset.Look.FLOOR_COMBAT
		RoomRole.REWARD, RoomRole.RISK_REWARD, RoomRole.REST, RoomRole.EXPLORATION:
			return PlaceholderTileset.Look.FLOOR_OPTIONAL
		RoomRole.HAZARD:
			return PlaceholderTileset.Look.FLOOR_ENVIRONMENT
	if data.role == DungeonGraph.Role.BRANCH or data.role == DungeonGraph.Role.DEAD_END:
		return PlaceholderTileset.Look.FLOOR_OPTIONAL
	return PlaceholderTileset.Look.FLOOR


## Greedy merge of the tiles in `area` for which `accept(index)` is true into
## a few large pixel rectangles (rows first, then extended downwards).
static func merge_rects(layout: DungeonLayout, area: Rect2i, accept: Callable) -> Array[Rect2]:
	var w := layout.size.x
	var used := PackedByteArray()
	used.resize(layout.tiles.size())
	var result: Array[Rect2] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := y * w + x
			if used[i] == 1 or not accept.call(i):
				continue
			var run := 1
			while x + run < area.end.x and used[i + run] == 0 and accept.call(i + run):
				run += 1
			var rows := 1
			var extend := true
			while extend and y + rows < area.end.y:
				for k in run:
					var j := (y + rows) * w + x + k
					if used[j] == 1 or not accept.call(j):
						extend = false
						break
				if extend:
					rows += 1
			for yy in rows:
				for xx in run:
					used[(y + yy) * w + x + xx] = 1
			var tile := DungeonLayout.TILE_SIZE
			result.append(Rect2(Vector2(x, y) * tile, Vector2(run, rows) * tile))
	return result


static func _add_terrain(layout: DungeonLayout, data: DungeonLayout.PlacedRoom, world: DungeonWorld,
		parent: Node2D) -> void:
	var bounds := data.bounds()
	var water_rects := merge_rects(layout, bounds, func(i: int) -> bool:
			return layout.tiles[i] == DungeonLayout.Tile.WATER and layout.owners[i] == data.id)
	if not water_rects.is_empty():
		var water := WaterZone.new()
		water.name = "Water%d" % data.id
		water.setup(water_rects)
		parent.add_child(water)
		world.water_zones.append(water)
	var pit_rects := merge_rects(layout, bounds, func(i: int) -> bool:
			return layout.tiles[i] == DungeonLayout.Tile.PIT and layout.owners[i] == data.id)
	if not pit_rects.is_empty():
		var pit := PitZone.new()
		pit.name = "Pit%d" % data.id
		pit.setup(pit_rects, _pit_edges(layout, bounds, data.id))
		pit.player_fell.connect(world.player_fell.emit)
		parent.add_child(pit)
		world.pit_zones.append(pit)


## Tile edges where a pit meets walkable ground, as [from, to, inward_point].
static func _pit_edges(layout: DungeonLayout, bounds: Rect2i, room_id: int) -> Array[PackedVector2Array]:
	var edges: Array[PackedVector2Array] = []
	var tile := float(DungeonLayout.TILE_SIZE)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var t := Vector2i(x, y)
			if layout.get_tile(t) != DungeonLayout.Tile.PIT or layout.get_owner_of(t) != room_id:
				continue
			var origin := Vector2(t) * tile
			var center := origin + Vector2(tile, tile) / 2.0
			for side in 4:
				if not layout.is_walkable(t + RoomShape.SIDE_VECTORS[side], true):
					continue
				var a: Vector2
				var b: Vector2
				match side:
					RoomShape.Side.NORTH:
						a = origin
						b = origin + Vector2(tile, 0)
					RoomShape.Side.EAST:
						a = origin + Vector2(tile, 0)
						b = origin + Vector2(tile, tile)
					RoomShape.Side.SOUTH:
						a = origin + Vector2(0, tile)
						b = origin + Vector2(tile, tile)
					_:
						a = origin
						b = origin + Vector2(0, tile)
				edges.append(PackedVector2Array([a, b, center]))
	return edges


static func _paint_tiles(layout: DungeonLayout, tiles: TileMapLayer) -> void:
	var floor_looks := PackedInt32Array()
	for data in layout.rooms:
		floor_looks.append(floor_look(data))
	for y in layout.size.y:
		for x in layout.size.x:
			var i := y * layout.size.x + x
			var look := -1
			match layout.tiles[i]:
				DungeonLayout.Tile.WALL:
					look = PlaceholderTileset.Look.WALL
				DungeonLayout.Tile.OBSTACLE:
					look = PlaceholderTileset.Look.OBSTACLE
				DungeonLayout.Tile.INNER_WALL:
					look = PlaceholderTileset.Look.INNER_WALL
				DungeonLayout.Tile.RUBBLE:
					look = PlaceholderTileset.Look.RUBBLE
				DungeonLayout.Tile.WATER:
					look = PlaceholderTileset.Look.WATER
				DungeonLayout.Tile.PIT:
					look = PlaceholderTileset.Look.PIT
				DungeonLayout.Tile.BRIDGE:
					look = PlaceholderTileset.Look.BRIDGE
				DungeonLayout.Tile.CORRIDOR:
					look = PlaceholderTileset.Look.CORRIDOR
				DungeonLayout.Tile.DOOR:
					look = PlaceholderTileset.Look.DOOR
				DungeonLayout.Tile.HAZARD:
					look = PlaceholderTileset.Look.HAZARD
				DungeonLayout.Tile.FLOOR:
					var owner_id := layout.owners[i]
					look = floor_looks[owner_id] if owner_id >= 0 and owner_id < floor_looks.size() \
						else PlaceholderTileset.Look.FLOOR
			if look >= 0:
				tiles.set_cell(Vector2i(x, y), 0, Vector2i(look, 0))


static func _label(text: String, at: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at - Vector2(100, 16)
	label.size = Vector2(200, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	return label
