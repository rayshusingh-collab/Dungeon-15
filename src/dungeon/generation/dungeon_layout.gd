class_name DungeonLayout
extends RefCounted
## Complete generated floor as data: a tile grid (kind + owner per tile), the
## placed rooms with their content, the corridors and the event sockets.
## DungeonBuilder turns this into nodes; DungeonValidator checks it; tests
## read it directly.
##
## Terrain classes:
##   solid     WALL, OBSTACLE, INNER_WALL, RUBBLE        never walkable (collision)
##   blocking  PIT                                       never walkable (you fall)
##   slow      WATER                                     walkable, slows movement
##   timed     HAZARD (spikes)                           walkable in its safe window
##   plain     FLOOR, CORRIDOR, DOOR, BRIDGE             walkable

enum Tile { VOID, WALL, FLOOR, CORRIDOR, DOOR, HAZARD, OBSTACLE, INNER_WALL, RUBBLE, WATER, PIT, BRIDGE }

## Walkability by Tile (index = Tile value), for fast mask building. Must match
## is_walkable_kind (the generation stress suite checks this).
const WALKABLE_PLAIN := [0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1]
const WALKABLE_WITH_HAZARD := [0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1]

const TILE_SIZE := 32
## Corridor tiles are owned by CORRIDOR_OWNER_BASE + link id; room tiles by the room id.
const CORRIDOR_OWNER_BASE := 100000
const NO_OWNER := -1


class PlacedRoom:
	var id: int
	var template: RoomTemplate
	## Shape of the chosen variant (size and door sockets equal the base layout).
	var shape: RoomShape
	var variant: int = 0
	var origin: Vector2i
	var cell: Vector2i
	var role: int
	var encounter: int
	var purpose: int
	## RoomRole: why the room exists (pacing / tactics).
	var tactic: int = RoomRole.TRAVERSAL
	## The role the director planned; differs from `tactic` only when content
	## placement had to downgrade the room (debug views, tests).
	var planned_tactic: int = RoomRole.TRAVERSAL
	## TacticalComposer recipe of the encounter (&"" without enemies).
	var recipe: StringName = &""
	## ThreatModel score and the budget it had to fit.
	var threat: float = 0.0
	var threat_budget: float = 0.0
	## The decision this room asks of the player (debug views, docs).
	var design_note: String = ""
	var special_rule: SpecialRoomRule
	## {side: int, link: int, tiles: Array[Vector2i], center: Vector2i, inside: Vector2i}
	var doors: Array[Dictionary] = []
	var anchor: Vector2i
	var enemy_ids: Array[StringName] = []
	## World tiles, in the (seeded) order they should be tried.
	var spawn_candidates: Array[Vector2i] = []
	## {type: StringName, tiles: Array[Vector2i], authored: bool, purpose: StringName}
	var hazards: Array[Dictionary] = []
	## {kind: StringName, tile: Vector2i}; kinds: reward, lore, secret, story,
	## heal (recovery), cache (risk reward), power (future power-up socket).
	var markers: Array[Dictionary] = []
	## RISK_REWARD rooms (debug views): shortest door -> cache walk that avoids
	## risk tiles (empty if none: the cache is guarded) and the risky one.
	var safe_route: Array[Vector2i] = []
	var risk_route: Array[Vector2i] = []
	## Reserved decoration points (world tiles) for later environment art.
	var prop_sockets: Array[Vector2i] = []
	## Optional structure the "dressing" stream turned solid: {kind: Tile, tiles: Array[Vector2i]}.
	var dressing: Array[Dictionary] = []

	func bounds() -> Rect2i:
		return Rect2i(origin, shape.size)

	func to_world(local: Vector2i) -> Vector2i:
		return origin + local

	func has_marker(kind: StringName) -> bool:
		for marker in markers:
			if marker.kind == kind:
				return true
		return false

	## Tiles of hazards that exist to make an optional route risky.
	func risk_tiles() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for hazard in hazards:
			if hazard.get("purpose", &"") == RoomRole.PURPOSE_RISK_ROUTE:
				for t: Vector2i in hazard.tiles:
					result.append(t)
		return result


class Corridor:
	var link: int
	var a: int
	var b: int
	var kind: int
	var rects: Array[Rect2i] = []
	## Recesses beside the lane (M2.2 play-test polish): {kind: &"nook" or
	## &"collapse", tiles: Array[Vector2i] (floor), rubble: Array[Vector2i]}.
	var alcoves: Array[Dictionary] = []


var run_seed: int
var depth: int
var attempt: int
var generator_version: int
var graph: DungeonGraph
var size: Vector2i
var tiles: PackedByteArray
var owners: PackedInt32Array
var rooms: Array[PlacedRoom] = []
var corridors: Array[Corridor] = []
var player_spawn: Vector2i
var exit_tile: Vector2i
## Floor threat budget the rooms' threat had to fit (profile).
var floor_threat_budget: float = 0.0
## Validated places where future tension/thriller events may safely happen:
## {tile: Vector2i, room: int (-1 in corridors), link: int, kind: StringName, armed: bool}
var event_sockets: Array[Dictionary] = []
## Non-colliding placeholder decoration (M2.2 play-test polish), {kind, tile}:
## floor marks (&"crack", &"stones", &"bones"), &"remains" in corridor nooks,
## &"torch" sockets on walls (future light sources). Cosmetic, but seeded and
## validated (never on terrain, sockets or doorway approaches).
var decor: Array[Dictionary] = []
## Tiles that two features tried to claim while carving (must stay 0).
var conflicts: int = 0
## Problems found during construction or validation.
var errors: PackedStringArray = []


func init_grid(grid_size: Vector2i) -> void:
	size = grid_size
	tiles = PackedByteArray()
	tiles.resize(size.x * size.y)
	owners = PackedInt32Array()
	owners.resize(size.x * size.y)
	owners.fill(NO_OWNER)


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < size.x and t.y < size.y


func index_of(t: Vector2i) -> int:
	return t.y * size.x + t.x


func get_tile(t: Vector2i) -> int:
	return tiles[index_of(t)] if in_bounds(t) else Tile.VOID


func get_owner_of(t: Vector2i) -> int:
	return owners[index_of(t)] if in_bounds(t) else NO_OWNER


func set_tile(t: Vector2i, kind: int, owner_id: int) -> void:
	var i := index_of(t)
	tiles[i] = kind
	owners[i] = owner_id


## Walkable terrain. `allow_hazard` also counts timed hazards (spikes), which
## can be crossed in their safe window; pits and solids never count.
static func is_walkable_kind(kind: int, allow_hazard: bool) -> bool:
	return kind == Tile.FLOOR or kind == Tile.CORRIDOR or kind == Tile.DOOR \
		or kind == Tile.WATER or kind == Tile.BRIDGE or (allow_hazard and kind == Tile.HAZARD)


static func is_solid_kind(kind: int) -> bool:
	return kind == Tile.WALL or kind == Tile.OBSTACLE or kind == Tile.INNER_WALL or kind == Tile.RUBBLE


## Pits, water, bridges and timed hazards: terrain that structure and decor
## keep clear of (readability, unobstructed crossings).
static func is_terrain_kind(kind: int) -> bool:
	return kind == Tile.PIT or kind == Tile.WATER or kind == Tile.BRIDGE or kind == Tile.HAZARD


func is_walkable(t: Vector2i, allow_hazard: bool = false) -> bool:
	return is_walkable_kind(get_tile(t), allow_hazard)


## Walkable with all 8 neighbours walkable: a player-sized body (radius < 1
## tile) centred here cannot touch a wall, pit or (unless allowed) hazard.
func is_clear(t: Vector2i, allow_hazard: bool = false) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not is_walkable(t + Vector2i(dx, dy), allow_hazard):
				return false
	return true


## True if a tile whose kind is in `mask` (bit per Tile) lies on the segment
## a-b, sampled every `step` px. Used for sight (DungeonNavigation) and spawn
## planning, so both judge the same line the same way.
func segment_hits(a: Vector2, b: Vector2, mask: int, step: float) -> bool:
	var steps := maxi(ceili(a.distance_to(b) / step), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var x := floori(p.x / TILE_SIZE)
		var y := floori(p.y / TILE_SIZE)
		if x >= 0 and y >= 0 and x < size.x and y < size.y and (mask >> tiles[y * size.x + x]) & 1:
			return true
	return false


func tile_center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE_SIZE, (t.y + 0.5) * TILE_SIZE)


func tile_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))


func pixel_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size * TILE_SIZE))


func room_for_space(space_id: int) -> PlacedRoom:
	return rooms[space_id] if space_id >= 0 and space_id < rooms.size() else null


func entry_room() -> PlacedRoom:
	return room_for_space(graph.entry_id())


func objective_room() -> PlacedRoom:
	return room_for_space(graph.objective_id())


## Room owning the tile, or null (corridors, walls, void).
func room_at_tile(t: Vector2i) -> PlacedRoom:
	var owner_id := get_owner_of(t)
	return rooms[owner_id] if owner_id >= 0 and owner_id < rooms.size() else null


## Link id of the corridor owning the tile, or -1.
func corridor_at_tile(t: Vector2i) -> int:
	var owner_id := get_owner_of(t)
	return owner_id - CORRIDOR_OWNER_BASE if owner_id >= CORRIDOR_OWNER_BASE else -1


## Stable identity of the generated dungeon. Equal fingerprints mean the same
## dungeon. It hashes the full tile grid, so interior geometry and variants
## count. `include_content` = false covers topology/geometry only: hazards
## are hashed as plain floor and encounters/spawns/sockets are left out.
func fingerprint(include_content: bool = true) -> String:
	var parts := PackedStringArray()
	parts.append("v%d|d%d|%dx%d" % [generator_version, depth, size.x, size.y])
	var grid := tiles.duplicate()
	if not include_content:
		for i in grid.size():
			if grid[i] == Tile.HAZARD:
				grid[i] = Tile.FLOOR
	parts.append("t%08x" % StableHash.fnv1a32_bytes(grid))
	for room in rooms:
		parts.append("r%d:%s/%d@%d,%d:%d" % [room.id, room.template.id, room.variant, room.origin.x, room.origin.y, room.role])
		if include_content:
			parts.append("e%d:%d:%d:%s:%s:%s:%.2f" % [room.encounter, room.purpose, room.tactic,
				",".join(room.enemy_ids), str(room.spawn_candidates), room.recipe, room.threat])
			for hazard in room.hazards:
				parts.append("h%s:%s:%s" % [hazard.type, hazard.get("purpose", &""), str(hazard.tiles)])
			for marker in room.markers:
				parts.append("m%s:%s" % [marker.kind, marker.tile])
			for piece in room.dressing:
				parts.append("s%d:%s" % [piece.kind, str(piece.tiles)])
	for corridor in corridors:
		parts.append("c%d-%d:%d:%s" % [corridor.a, corridor.b, corridor.kind, str(corridor.rects)])
	if include_content:
		parts.append("decor%d:%08x" % [decor.size(), StableHash.fnv1a32_bytes(str(decor).to_utf8_buffer())])
		for socket in event_sockets:
			parts.append("ev%s:%s:%s" % [socket.tile, socket.kind, socket.armed])
	return "%016x" % StableHash.hash62("\n".join(parts))


## Tactical data only (roles along the main path, per-room role, recipe,
## enemies, threat, hazard purposes, markers): for determinism/variation tests
## and debug output.
func tactical_signature() -> String:
	var parts := PackedStringArray()
	var main_roles := PackedStringArray()
	for id in graph.main_path:
		main_roles.append(RoomRole.name_of(rooms[id].tactic))
	parts.append("path:" + ">".join(main_roles))
	for room in rooms:
		var purposes := PackedStringArray()
		for hazard in room.hazards:
			purposes.append(str(hazard.get("purpose", &"")))
		var markers_text := PackedStringArray()
		for marker in room.markers:
			markers_text.append(str(marker.kind))
		parts.append("%d:%s:%s:%s:%.2f/%.2f:%s:%s" % [room.id, RoomRole.name_of(room.tactic), room.recipe,
			",".join(room.enemy_ids), room.threat, room.threat_budget, ",".join(purposes), ",".join(markers_text)])
	return "\n".join(parts)


func total_threat() -> float:
	var total := 0.0
	for room in rooms:
		total += room.threat
	return total
