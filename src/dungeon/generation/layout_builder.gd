class_name LayoutBuilder
extends RefCounted
## Stage 3: turns the graph into tiles.
##  a. Template per space ("templates" stream): by RoomRole (PacingDirector),
##     required door sides and combat capability. Terrain-challenge roles use
##     variants with terrain; all others use clean variants. The structural
##     variant is picked per room from the "variants" stream.
##  b. Macro cell sizes ("layout" stream): each column/row is as wide/tall as
##     its largest room plus margins and random slack, so the grid is irregular.
##  c. Room placement ("layout"): jittered inside its cell, rasterised.
##  d. Corridors ("corridors" stream): from a door socket, straight out to the
##     shared cell boundary, along the boundary, and straight into the other
##     room's socket (straight, L or Z shaped, CORRIDOR_WIDTH wide). Because
##     rooms keep CELL_MARGIN tiles from cell edges and each boundary segment
##     stays within its row/column span, corridors cannot cross rooms or each
##     other; any tile claimed twice is still counted in `conflicts`.
##  e. Alcoves ("corridor_dressing" stream per corridor): recesses beside long
##     straight segments, outside the CORRIDOR_WIDTH lane, carved only into empty
##     space: an empty nook (future prop/torch spot) or a collapsed section
##     (floor, then rubble against the outer wall). The lane never changes.
##  f. Walls around every corridor tile (and corridor rubble).

const CELL_MARGIN := 4
const BORDER := 2
const EMPTY_CELL_SIZE := 6
## Corridor alcoves: segments at least this long get them, one chance per
## ALCOVE_SPACING tiles, ALCOVE_LENGTH tiles along the lane, kept this far
## from the segment ends (corners and doorways).
const ALCOVE_MIN_SEGMENT := 9
const ALCOVE_SPACING := 6
const ALCOVE_CHANCE := 0.85
const ALCOVE_LENGTH := 3
const ALCOVE_END_MARGIN := 4
## RoomShape.Cell -> DungeonLayout.Tile (authored spikes become HAZARD tiles).
static func tile_for_cell(cell: int) -> int:
	match cell:
		RoomShape.Cell.FLOOR:
			return DungeonLayout.Tile.FLOOR
		RoomShape.Cell.OBSTACLE:
			return DungeonLayout.Tile.OBSTACLE
		RoomShape.Cell.INNER_WALL:
			return DungeonLayout.Tile.INNER_WALL
		RoomShape.Cell.RUBBLE:
			return DungeonLayout.Tile.RUBBLE
		RoomShape.Cell.WATER:
			return DungeonLayout.Tile.WATER
		RoomShape.Cell.PIT:
			return DungeonLayout.Tile.PIT
		RoomShape.Cell.BRIDGE:
			return DungeonLayout.Tile.BRIDGE
		RoomShape.Cell.SPIKES:
			return DungeonLayout.Tile.HAZARD
	return DungeonLayout.Tile.WALL



static func build(graph: DungeonGraph, profile: DepthProfile, streams: SeedStreams) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.graph = graph
	var templates := _choose_templates(graph, profile, streams.stream("templates"), layout)
	if not layout.errors.is_empty():
		return layout

	var layout_rng := streams.stream("layout")
	var col_w := _track_sizes(graph, templates, true, profile, layout_rng)
	var row_h := _track_sizes(graph, templates, false, profile, layout_rng)
	var col_x := _prefix(col_w)
	var row_y := _prefix(row_h)
	layout.init_grid(Vector2i(col_x[col_x.size() - 1] + BORDER, row_y[row_y.size() - 1] + BORDER))

	for space in graph.spaces:
		var template: RoomTemplate = templates[space.id]
		var room := DungeonLayout.PlacedRoom.new()
		room.id = space.id
		room.template = template
		# Variants share size and sockets, so picking one (own per-room stream)
		# never changes placement or corridors.
		room.variant = maxi(template.pick_variant(streams.stream("variants", space.id), variant_filter(space.tactic)), 0)
		var shape := template.get_shape(room.variant)
		room.shape = shape
		room.cell = space.cell
		room.role = space.role
		room.tactic = space.tactic
		room.planned_tactic = space.tactic
		room.encounter = space.encounter
		room.purpose = space.purpose
		room.special_rule = space.special_rule
		var free_x := col_w[space.cell.x] - 2 * CELL_MARGIN - shape.size.x
		var free_y := row_h[space.cell.y] - 2 * CELL_MARGIN - shape.size.y
		room.origin = Vector2i(
			col_x[space.cell.x] + CELL_MARGIN + layout_rng.randi_range(0, maxi(free_x, 0)),
			row_y[space.cell.y] + CELL_MARGIN + layout_rng.randi_range(0, maxi(free_y, 0)))
		room.anchor = room.to_world(shape.anchor)
		layout.rooms.append(room)
		_rasterize_room(layout, room)

	var corridor_rng := streams.stream("corridors")
	for link in graph.links:
		_carve_corridor(layout, link, col_x, row_y, corridor_rng)
	for corridor in layout.corridors:
		_dress_corridor(layout, corridor, streams.stream("corridor_dressing", corridor.link))
	_wall_corridors(layout)
	return layout


## Template per space from its RoomRole (pool, door sides, combat capability
## and a variant that suits the role). If nothing fits, the role is downgraded
## along a fixed chain (e.g. HAZARD_COMBAT -> COMBAT, RISK_REWARD -> REWARD)
## and the encounters are re-derived, so pacing only ever gets lighter.
static func _choose_templates(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator,
		layout: DungeonLayout) -> Array[RoomTemplate]:
	var chosen: Array[RoomTemplate] = []
	for space in graph.spaces:
		var sides: Array[int] = []
		for link_id in space.link_ids:
			sides.append(graph.side_between(space.id, graph.other_end(graph.links[link_id], space.id)))
		var template := _choose_for_role(space, sides, profile, rng)
		while template == null:
			var fallback := _fallback_role(space)
			if fallback < 0:
				break
			space.tactic = fallback
			space.purpose = _purpose_after_fallback(space)
			template = _choose_for_role(space, sides, profile, rng)
		if template == null:
			layout.errors.append("no template fits space %d (role %s, sides %s)" % [
				space.id, RoomRole.name_of(space.tactic), sides])
			return chosen
		chosen.append(template)
	PacingDirector.apply_encounters(graph, profile)
	return chosen


static func _choose_for_role(space: DungeonGraph.Space, sides: Array[int], profile: DepthProfile,
		rng: RandomNumberGenerator) -> RoomTemplate:
	var pool: Array[RoomTemplate] = []
	match space.role:
		DungeonGraph.Role.ENTRY:
			pool = profile.entry_templates.duplicate()
		DungeonGraph.Role.OBJECTIVE:
			pool = profile.objective_templates.duplicate()
		DungeonGraph.Role.SPECIAL:
			pool.append(space.special_rule.template)
		_:
			for template in profile.room_templates:
				if template != null and template.suits(space.tactic, space.role):
					pool.append(template)
	var filter := variant_filter(space.tactic)
	var fitting: Array[RoomTemplate] = []
	var weights := PackedFloat32Array()
	for template in pool:
		if template == null:
			continue
		var shape := template.get_shape()
		var ok := shape.errors.is_empty() and not template.matching_variants(filter).is_empty()
		for side in sides:
			ok = ok and shape.has_side(side)
		if RoomRole.is_heavy(space.tactic):
			ok = ok and template.combat_allowed
		if ok:
			fitting.append(template)
			# Room size follows purpose (RoomRole.size_weight). Hazard rooms
			# prefer dedicated environmental rooms (pits, water,
			# trap galleries) over normal rooms with spike sockets.
			var preferred := space.tactic == RoomRole.HAZARD and template.has_role("environmental")
			weights.append(template.weight * (3.0 if preferred else 1.0) * RoomRole.size_weight(space.tactic, template.size_class))
	if fitting.is_empty():
		return null
	return fitting[SeedStreams.weighted_index(weights, rng)]


## Interiors that suit the role: terrain challenges need terrain, everything
## else uses clean variants (walls/pillars only; optional hazard sockets stay
## floor), fixed rooms take any.
static func variant_filter(role: int) -> int:
	if RoomRole.wants_terrain(role):
		return RoomTemplate.VariantFilter.TERRAIN
	if role == RoomRole.ENTRY or role == RoomRole.OBJECTIVE or role == RoomRole.STORY:
		return RoomTemplate.VariantFilter.ANY
	return RoomTemplate.VariantFilter.CLEAN


static func _fallback_role(space: DungeonGraph.Space) -> int:
	match space.tactic:
		RoomRole.HAZARD_COMBAT, RoomRole.AMBUSH:
			return RoomRole.COMBAT
		RoomRole.CHALLENGE, RoomRole.RISK_REWARD:
			return RoomRole.REWARD
		RoomRole.REST:
			return RoomRole.REWARD if space.role == DungeonGraph.Role.DEAD_END else RoomRole.TRAVERSAL
		RoomRole.HAZARD, RoomRole.TRANSITION:
			return RoomRole.TRAVERSAL
	return -1


static func _purpose_after_fallback(space: DungeonGraph.Space) -> int:
	if space.tactic == RoomRole.REWARD:
		return DungeonGraph.Purpose.REWARD
	return DungeonGraph.Purpose.NONE


static func _track_sizes(graph: DungeonGraph, templates: Array[RoomTemplate], columns: bool,
		profile: DepthProfile, rng: RandomNumberGenerator) -> PackedInt32Array:
	var count := graph.grid_size.x if columns else graph.grid_size.y
	var needed := PackedInt32Array()
	needed.resize(count)
	for space in graph.spaces:
		var shape := templates[space.id].get_shape()
		var track := space.cell.x if columns else space.cell.y
		needed[track] = maxi(needed[track], shape.size.x if columns else shape.size.y)
	var sizes := PackedInt32Array()
	sizes.resize(count)
	for i in count:
		sizes[i] = EMPTY_CELL_SIZE if needed[i] == 0 \
			else needed[i] + 2 * CELL_MARGIN + rng.randi_range(0, profile.cell_slack)
	return sizes


## Start coordinate of every track, plus the end coordinate as the last element.
static func _prefix(sizes: PackedInt32Array) -> PackedInt32Array:
	var starts := PackedInt32Array([BORDER])
	for s in sizes:
		starts.append(starts[starts.size() - 1] + s)
	return starts


static func _rasterize_room(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> void:
	var shape := room.shape
	for y in shape.size.y:
		for x in shape.size.x:
			var local := Vector2i(x, y)
			var cell := shape.get_cell(local)
			if cell == RoomShape.Cell.OUTSIDE:
				continue
			var world := room.to_world(local)
			if not layout.in_bounds(world) or layout.get_tile(world) != DungeonLayout.Tile.VOID:
				layout.conflicts += 1
				continue
			layout.set_tile(world, tile_for_cell(cell), room.id)


static func _carve_corridor(layout: DungeonLayout, link: DungeonGraph.Link, col_x: PackedInt32Array,
		row_y: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var room_a := layout.rooms[link.a]
	var room_b := layout.rooms[link.b]
	var side := layout.graph.side_between(link.a, link.b)
	var opposite := (side + 2) % 4
	var sockets_a := room_a.shape.sockets_on(side)
	var sockets_b := room_b.shape.sockets_on(opposite)
	if sockets_a.is_empty() or sockets_b.is_empty():
		layout.errors.append("link %d has no matching door sockets" % link.id)
		return
	var socket_a: RoomShape.Socket = sockets_a[rng.randi_range(0, sockets_a.size() - 1)]
	var socket_b: RoomShape.Socket = sockets_b[rng.randi_range(0, sockets_b.size() - 1)]
	_open_door(layout, room_a, socket_a, link.id)
	_open_door(layout, room_b, socket_b, link.id)

	var start := room_a.to_world(socket_a.center) + RoomShape.SIDE_VECTORS[side]
	var end := room_b.to_world(socket_b.center) + RoomShape.SIDE_VECTORS[opposite]
	var corridor := DungeonLayout.Corridor.new()
	corridor.link = link.id
	corridor.a = link.a
	corridor.b = link.b
	corridor.kind = link.kind
	var half := RoomShape.CORRIDOR_WIDTH / 2
	if side == RoomShape.Side.EAST or side == RoomShape.Side.WEST:
		var boundary := col_x[maxi(room_a.cell.x, room_b.cell.x)]
		corridor.rects.append(_span(Vector2i(start.x, start.y), Vector2i(boundary, start.y), half, false))
		corridor.rects.append(_span(Vector2i(boundary, start.y), Vector2i(boundary, end.y), half, true))
		corridor.rects.append(_span(Vector2i(boundary, end.y), Vector2i(end.x, end.y), half, false))
	else:
		var boundary := row_y[maxi(room_a.cell.y, room_b.cell.y)]
		corridor.rects.append(_span(Vector2i(start.x, start.y), Vector2i(start.x, boundary), half, false))
		corridor.rects.append(_span(Vector2i(start.x, boundary), Vector2i(end.x, boundary), half, true))
		corridor.rects.append(_span(Vector2i(end.x, boundary), Vector2i(end.x, end.y), half, false))
	var owner_id := DungeonLayout.CORRIDOR_OWNER_BASE + link.id
	for rect in corridor.rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var t := Vector2i(x, y)
				if not layout.in_bounds(t):
					layout.conflicts += 1
					continue
				var kind := layout.get_tile(t)
				if kind == DungeonLayout.Tile.VOID:
					layout.set_tile(t, DungeonLayout.Tile.CORRIDOR, owner_id)
				elif not (kind == DungeonLayout.Tile.CORRIDOR and layout.get_owner_of(t) == owner_id):
					layout.conflicts += 1
	layout.corridors.append(corridor)


## Axis-aligned segment from a to b (inclusive), `half` tiles thick on each
## side. `pad_ends` also extends it by `half` along its length; only the
## middle (boundary) segment does that, to fill the two corners. Door segments
## must not, or they would run into their own doorway.
static func _span(a: Vector2i, b: Vector2i, half: int, pad_ends: bool) -> Rect2i:
	var horizontal := a.y == b.y and a.x != b.x
	var vertical := a.x == b.x and a.y != b.y
	var pad_x := half if (not horizontal or pad_ends) else 0
	var pad_y := half if (not vertical or pad_ends) else 0
	var top_left := Vector2i(mini(a.x, b.x) - pad_x, mini(a.y, b.y) - pad_y)
	var bottom_right := Vector2i(maxi(a.x, b.x) + pad_x, maxi(a.y, b.y) + pad_y)
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


static func _open_door(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, socket: RoomShape.Socket, link_id: int) -> void:
	var door_tiles: Array[Vector2i] = []
	for local in socket.tiles:
		var world := room.to_world(local)
		layout.set_tile(world, DungeonLayout.Tile.DOOR, room.id)
		door_tiles.append(world)
	var center := room.to_world(socket.center)
	room.doors.append({
		"side": socket.side,
		"link": link_id,
		"tiles": door_tiles,
		"center": center,
		"inside": center - RoomShape.SIDE_VECTORS[socket.side],
	})


## Alcoves beside the straight segments of one corridor. Every draw happens
## whether or not the alcove fits, so a refused alcove never shifts the next.
static func _dress_corridor(layout: DungeonLayout, corridor: DungeonLayout.Corridor,
		rng: RandomNumberGenerator) -> void:
	for rect in corridor.rects:
		var horizontal := rect.size.x > rect.size.y
		var length := rect.size.x if horizontal else rect.size.y
		if length < ALCOVE_MIN_SEGMENT:
			continue
		for slot in length / ALCOVE_SPACING:
			var roll := rng.randf()
			var along := rng.randi_range(ALCOVE_END_MARGIN, length - ALCOVE_END_MARGIN - ALCOVE_LENGTH)
			var side := 1 if rng.randf() < 0.5 else -1
			var collapsed := rng.randf() < 0.5
			var depth := 2 if collapsed else rng.randi_range(1, 2)
			if roll >= ALCOVE_CHANCE:
				continue
			_try_alcove(layout, corridor, rect, horizontal, along, side, depth, collapsed)


static func _try_alcove(layout: DungeonLayout, corridor: DungeonLayout.Corridor, rect: Rect2i, horizontal: bool,
		along: int, side: int, depth: int, collapsed: bool) -> void:
	var floor_tiles: Array[Vector2i] = []
	var rubble: Array[Vector2i] = []
	for i in ALCOVE_LENGTH:
		for d in range(1, depth + 1):
			var t: Vector2i
			if horizontal:
				t = Vector2i(rect.position.x + along + i, rect.end.y - 1 + d if side > 0 else rect.position.y - d)
			else:
				t = Vector2i(rect.end.x - 1 + d if side > 0 else rect.position.x - d, rect.position.y + along + i)
			if collapsed and d == depth:
				rubble.append(t)
			else:
				floor_tiles.append(t)
	# Only into empty space: everything within two tiles is void or this lane,
	# so the alcove (and the wall that will close it) touches nothing else.
	for t in floor_tiles + rubble:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := t + Vector2i(dx, dy)
				if not layout.in_bounds(n):
					return
				if layout.get_tile(n) != DungeonLayout.Tile.VOID and not rect.has_point(n):
					return
	var owner_id := DungeonLayout.CORRIDOR_OWNER_BASE + corridor.link
	for t in floor_tiles:
		layout.set_tile(t, DungeonLayout.Tile.CORRIDOR, owner_id)
	for t in rubble:
		layout.set_tile(t, DungeonLayout.Tile.RUBBLE, owner_id)
	corridor.alcoves.append({"kind": &"collapse" if collapsed else &"nook", "tiles": floor_tiles, "rubble": rubble})


static func _wall_corridors(layout: DungeonLayout) -> void:
	for y in layout.size.y:
		for x in layout.size.x:
			var i := y * layout.size.x + x
			var corridor_rubble := layout.tiles[i] == DungeonLayout.Tile.RUBBLE and layout.owners[i] >= DungeonLayout.CORRIDOR_OWNER_BASE
			if layout.tiles[i] != DungeonLayout.Tile.CORRIDOR and not corridor_rubble:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := Vector2i(x + dx, y + dy)
					if layout.in_bounds(n) and layout.get_tile(n) == DungeonLayout.Tile.VOID:
						layout.set_tile(n, DungeonLayout.Tile.WALL, DungeonLayout.NO_OWNER)
