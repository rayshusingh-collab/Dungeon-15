class_name DecorPlacer
extends RefCounted
## Non-colliding placeholder decoration (M2.2 play-test polish): breaks up flat
## floors and bare corridors without touching gameplay. Seeded per room
## ("decor" stream) and per corridor ("corridor_decor"); every tile visited
## draws the same numbers whatever is placed, so decor never shifts other
## content. Writes DungeonLayout.decor ({kind, tile}):
##   floor marks   &"crack", &"stones", &"bones" on plain floor/corridor
##   &"remains"    in corridor nooks (future environmental-storytelling spot)
##   &"torch"      sockets on walls beside walkable floor (future light sources)
## Rules (validated): floor marks never on terrain or next to it, never on a
## socket tile (anchor, spawn, exit, markers, spawn candidates, event
## sockets), never in a doorway approach; torches only on walls, spaced.
## Art later swaps the placeholder look without changing this data.

## Chance per eligible floor tile, by purpose: lived-in quiet rooms show more
## remains of the dungeon's past; fight and terrain rooms stay readable.
const FLOOR_RATE := 0.05
const CORRIDOR_RATE := 0.035
const TORCH_RATE := 0.12
## Minimum Chebyshev distance between torches of the same room or corridor.
const TORCH_SPACING := 8
## Floor marks keep this Chebyshev distance from doorway insides.
const DOOR_MARGIN := 2


static func place(layout: DungeonLayout, streams: SeedStreams) -> void:
	var reserved := reserved_tiles(layout)
	for room in layout.rooms:
		_decorate_room(layout, room, reserved, streams.stream("decor", room.id))
	for corridor in layout.corridors:
		_decorate_corridor(layout, corridor, reserved, streams.stream("corridor_decor", corridor.link))


## Tiles decor must leave alone: every socket and the doorway approaches.
static func reserved_tiles(layout: DungeonLayout) -> Dictionary:
	var reserved: Dictionary = {layout.player_spawn: true, layout.exit_tile: true}
	for room in layout.rooms:
		reserved[room.anchor] = true
		for t in room.spawn_candidates:
			reserved[t] = true
		for marker in room.markers:
			reserved[marker.tile] = true
		for door in room.doors:
			var inside: Vector2i = door.inside
			for dy in range(-DOOR_MARGIN + 1, DOOR_MARGIN):
				for dx in range(-DOOR_MARGIN + 1, DOOR_MARGIN):
					reserved[inside + Vector2i(dx, dy)] = true
			for t: Vector2i in door.tiles:
				reserved[t] = true
	for socket in layout.event_sockets:
		reserved[socket.tile] = true
	return reserved


## A floor mark may sit here: plain floor or corridor, not reserved, no terrain within one tile.
static func floor_mark_ok(layout: DungeonLayout, t: Vector2i, reserved: Dictionary) -> bool:
	var kind := layout.get_tile(t)
	if (kind != DungeonLayout.Tile.FLOOR and kind != DungeonLayout.Tile.CORRIDOR) or reserved.has(t):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if DungeonLayout.is_terrain_kind(layout.get_tile(t + Vector2i(dx, dy))):
				return false
	return true


static func _decorate_room(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, reserved: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var rate := FLOOR_RATE * _purpose_factor(room.tactic)
	var torches: Array[Vector2i] = []
	var bounds := room.bounds()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var t := Vector2i(x, y)
			if layout.get_owner_of(t) != room.id:
				continue
			var kind := layout.get_tile(t)
			if kind == DungeonLayout.Tile.FLOOR:
				var roll := rng.randf()
				var pick := rng.randf()
				if roll < rate and floor_mark_ok(layout, t, reserved):
					layout.decor.append({"kind": _floor_kind(room.tactic, pick), "tile": t})
			elif kind == DungeonLayout.Tile.WALL and _faces(layout, t, DungeonLayout.Tile.FLOOR, room.id):
				var roll := rng.randf()
				if roll < TORCH_RATE and _spaced(t, torches) and not _near_door(room, t):
					torches.append(t)
					layout.decor.append({"kind": &"torch", "tile": t})


static func _decorate_corridor(layout: DungeonLayout, corridor: DungeonLayout.Corridor, reserved: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var owner_id := DungeonLayout.CORRIDOR_OWNER_BASE + corridor.link
	var torches: Array[Vector2i] = []
	for rect in corridor.rects:
		var around := rect.grow(1)
		for y in range(around.position.y, around.end.y):
			for x in range(around.position.x, around.end.x):
				var t := Vector2i(x, y)
				var kind := layout.get_tile(t)
				if rect.has_point(t):
					var roll := rng.randf()
					var pick := rng.randf()
					if kind == DungeonLayout.Tile.CORRIDOR and roll < CORRIDOR_RATE and floor_mark_ok(layout, t, reserved):
						layout.decor.append({"kind": _floor_kind(RoomRole.TRAVERSAL, pick), "tile": t})
				elif kind == DungeonLayout.Tile.WALL and _faces(layout, t, DungeonLayout.Tile.CORRIDOR, owner_id):
					var roll := rng.randf()
					if roll < TORCH_RATE and _spaced(t, torches):
						torches.append(t)
						layout.decor.append({"kind": &"torch", "tile": t})
	for alcove in corridor.alcoves:
		var roll := rng.randf()
		if alcove.kind == &"nook" and roll < 0.7:
			var spot: Vector2i = alcove.tiles[alcove.tiles.size() / 2]
			if floor_mark_ok(layout, spot, reserved):
				layout.decor.append({"kind": &"remains", "tile": spot})


static func _purpose_factor(role: int) -> float:
	match role:
		RoomRole.EXPLORATION, RoomRole.TRAVERSAL, RoomRole.TRANSITION, RoomRole.REWARD:
			return 1.3
		RoomRole.HAZARD, RoomRole.HAZARD_COMBAT, RoomRole.RISK_REWARD:
			return 0.5
		RoomRole.STORY:
			return 0.0
	return 1.0


## Quiet places show more remains; fights and rest rooms show wear, not bodies.
static func _floor_kind(role: int, pick: float) -> StringName:
	var bones := 0.25 if role == RoomRole.EXPLORATION or role == RoomRole.TRAVERSAL else 0.08
	if role == RoomRole.REST:
		bones = 0.0
	if pick < bones:
		return &"bones"
	return &"crack" if pick < bones + (1.0 - bones) * 0.55 else &"stones"


## The wall tile has a 4-neighbour of `kind` owned by `owner_id`.
static func _faces(layout: DungeonLayout, t: Vector2i, kind: int, owner_id: int) -> bool:
	for d in RoomShape.SIDE_VECTORS:
		var n := t + d
		if layout.get_tile(n) == kind and layout.get_owner_of(n) == owner_id:
			return true
	return false


static func _spaced(t: Vector2i, others: Array[Vector2i]) -> bool:
	for o in others:
		if maxi(absi(t.x - o.x), absi(t.y - o.y)) < TORCH_SPACING:
			return false
	return true


static func _near_door(room: DungeonLayout.PlacedRoom, t: Vector2i) -> bool:
	for door in room.doors:
		for d: Vector2i in door.tiles:
			if maxi(absi(t.x - d.x), absi(t.y - d.y)) <= 1:
				return true
	return false
