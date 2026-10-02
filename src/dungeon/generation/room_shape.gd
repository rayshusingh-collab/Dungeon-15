class_name RoomShape
extends RefCounted
## Parsed geometry of one RoomTemplate layout (base or variant), in local tile
## coordinates. Legend (full table in docs/DUNGEON_GENERATION.md):
##   structure  '#' outer wall  'I' interior wall  'O' pillar  '%' rubble   (all solid)
##              '.' floor  ' ' outside (irregular shapes)
##   terrain    'W' shallow water (walkable, slow)  'P' pit (fall)  '=' bridge (walkable over pit)
##              '^' authored spikes (timed hazard, always present)
##   doors      'D' door socket: wall unless a corridor attaches; exactly CORRIDOR_WIDTH
##              contiguous tiles on the outer bounding-box edge, not on a corner
##   sockets    'C' anchor (exactly one)  'E' enemy spawn  'H' optional hazard  'R' reward
##              'L' lore  'T' tension/event  '+' prop  '?' secret
##              '$' risk cache (optional high-value reward behind a visible risk)  (all on floor)
##   dressing   'x' optional rubble / broken wall   'o' optional pillar  (floor unless the
##              room's "dressing" stream turns a region solid; see ContentPlacer). The lint
##              also checks the FULLY DRESSED variant (every x/o solid), so any subset is safe.
## Parsing never throws: problems are collected in `errors` (linted by tests).

enum Side { NORTH, EAST, SOUTH, WEST }
enum Cell { OUTSIDE, WALL, FLOOR, OBSTACLE, INNER_WALL, RUBBLE, WATER, PIT, BRIDGE, SPIKES }

const CORRIDOR_WIDTH := 3
const SIDE_VECTORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Timed hazards (spikes) must be crossable within one safe window: no region may
## be longer than this in either direction (8 tiles = 256 px ~ 1.1 s of walking).
const MAX_TIMED_REGION := 8
## Pits and spikes keep at least this Chebyshev distance from doorway insides.
const DOOR_CLEARANCE := 2
## Bridges must be at least this wide (mobile-friendly crossings).
const MIN_BRIDGE_WIDTH := 3


class Socket:
	var side: int
	var tiles: Array[Vector2i] = []
	var center: Vector2i


var size: Vector2i
var cells: PackedByteArray
var sockets: Array[Socket] = []
var anchor: Vector2i = Vector2i(-1, -1)
var enemy_spawns: Array[Vector2i] = []
## Optional hazard sockets ('H'): Array of Array[Vector2i] (4-connected regions).
var hazard_regions: Array = []
## Authored spikes ('^'): Array of Array[Vector2i], always placed.
var spike_regions: Array = []
var reward_sockets: Array[Vector2i] = []
var lore_sockets: Array[Vector2i] = []
var event_sockets: Array[Vector2i] = []
var prop_sockets: Array[Vector2i] = []
var secret_sockets: Array[Vector2i] = []
var cache_sockets: Array[Vector2i] = []
## Optional structure sockets ('x' rubble, 'o' pillar): 4-connected regions of one
## kind (Array of Array[Vector2i]) and the Cell each region becomes when used.
var dressing_regions: Array = []
var dressing_kinds: Array[int] = []
var errors: PackedStringArray = []

var _clean: bool = true


static func parse(text: String) -> RoomShape:
	var shape := RoomShape.new()
	var lines: Array[String] = []
	for raw in text.split("\n"):
		lines.append(raw.trim_suffix("\r"))
	while not lines.is_empty() and lines[0].strip_edges().is_empty():
		lines.pop_front()
	while not lines.is_empty() and lines.back().strip_edges().is_empty():
		lines.pop_back()
	var width := 0
	for line in lines:
		width = maxi(width, line.length())
	shape.size = Vector2i(width, lines.size())
	shape.cells.resize(width * lines.size())
	if width == 0:
		shape.errors.append("empty layout")
		return shape
	var door_tiles: Array[Vector2i] = []
	var hazard_tiles: Dictionary = {}
	var spike_tiles: Dictionary = {}
	var rubble_tiles: Dictionary = {}
	var pillar_tiles: Dictionary = {}
	for y in lines.size():
		var line := lines[y]
		for x in width:
			var ch := line[x] if x < line.length() else " "
			var p := Vector2i(x, y)
			match ch:
				"#":
					shape._set_cell(p, Cell.WALL)
				"D":
					shape._set_cell(p, Cell.WALL)
					door_tiles.append(p)
				"I":
					shape._set_cell(p, Cell.INNER_WALL)
				"O":
					shape._set_cell(p, Cell.OBSTACLE)
				"%":
					shape._set_cell(p, Cell.RUBBLE)
				"W":
					shape._set_cell(p, Cell.WATER)
				"P":
					shape._set_cell(p, Cell.PIT)
				"=":
					shape._set_cell(p, Cell.BRIDGE)
				"^":
					shape._set_cell(p, Cell.SPIKES)
					spike_tiles[p] = true
				".":
					shape._set_cell(p, Cell.FLOOR)
				"x":
					shape._set_cell(p, Cell.FLOOR)
					rubble_tiles[p] = true
				"o":
					shape._set_cell(p, Cell.FLOOR)
					pillar_tiles[p] = true
				"E":
					shape._set_cell(p, Cell.FLOOR)
					shape.enemy_spawns.append(p)
				"H":
					shape._set_cell(p, Cell.FLOOR)
					hazard_tiles[p] = true
				"R":
					shape._set_cell(p, Cell.FLOOR)
					shape.reward_sockets.append(p)
				"L":
					shape._set_cell(p, Cell.FLOOR)
					shape.lore_sockets.append(p)
				"T":
					shape._set_cell(p, Cell.FLOOR)
					shape.event_sockets.append(p)
				"+":
					shape._set_cell(p, Cell.FLOOR)
					shape.prop_sockets.append(p)
				"?":
					shape._set_cell(p, Cell.FLOOR)
					shape.secret_sockets.append(p)
				"$":
					shape._set_cell(p, Cell.FLOOR)
					shape.cache_sockets.append(p)
				"C":
					shape._set_cell(p, Cell.FLOOR)
					if shape.anchor != Vector2i(-1, -1):
						shape.errors.append("more than one anchor 'C'")
					shape.anchor = p
				" ":
					pass
				_:
					shape.errors.append("unknown character '%s' at %s" % [ch, p])
	shape._group_sockets(door_tiles)
	shape.hazard_regions = _group_regions(hazard_tiles)
	shape.spike_regions = _group_regions(spike_tiles)
	for pair: Array in [[rubble_tiles, Cell.RUBBLE], [pillar_tiles, Cell.OBSTACLE]]:
		for region: Array in _group_regions(pair[0]):
			shape.dressing_regions.append(region)
			shape.dressing_kinds.append(pair[1])
	shape._clean = shape.count_cells(Cell.PIT) == 0 and shape.count_cells(Cell.WATER) == 0 \
		and shape.count_cells(Cell.SPIKES) == 0
	shape._lint()
	if not shape.dressing_regions.is_empty():
		shape._lint_dressing(hazard_tiles)
		# Removing structure never breaks connectivity or clearance, so if the
		# fully dressed variant passes every check, any subset does too.
		var dressed := parse(text.replace("x", "%").replace("o", "O"))
		for e in dressed.errors:
			shape.errors.append("fully dressed: " + e)
	return shape


func get_cell(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
		return Cell.OUTSIDE
	return cells[p.y * size.x + p.x]


## Walkable at all (spikes are walkable: timed hazard).
func is_walkable(p: Vector2i) -> bool:
	var c := get_cell(p)
	return c == Cell.FLOOR or c == Cell.WATER or c == Cell.BRIDGE or c == Cell.SPIKES


## Walkable and not hazardous (safe to stand: spawns, sockets, anchor).
func is_safe(p: Vector2i) -> bool:
	var c := get_cell(p)
	return c == Cell.FLOOR or c == Cell.WATER or c == Cell.BRIDGE


## Safe here and on all 8 neighbours (a player-sized body fits).
func is_clear(p: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not is_safe(p + Vector2i(dx, dy)):
				return false
	return true


## Kept for existing callers: plain floor (not water/bridge/spikes).
func is_floor(p: Vector2i) -> bool:
	return get_cell(p) == Cell.FLOOR


func count_cells(cell: int) -> int:
	var count := 0
	for c in cells:
		if c == cell:
			count += 1
	return count


## No pits, water or authored spikes: walls, pillars and rubble only. Rooms
## whose role is not a terrain challenge use clean variants, so dangerous
## terrain only appears where it is the point of the room. (Cached at parse.)
func is_clean() -> bool:
	return _clean


## Has terrain a terrain-challenge role can use (pits, water, spikes or
## optional hazard sockets).
func has_terrain() -> bool:
	return not is_clean() or not hazard_regions.is_empty()


func sockets_on(side: int) -> Array[Socket]:
	var result: Array[Socket] = []
	for socket in sockets:
		if socket.side == side:
			result.append(socket)
	return result


func has_side(side: int) -> bool:
	return not sockets_on(side).is_empty()


## Door layout signature: variants of one template must share it.
func socket_signature() -> String:
	var parts := PackedStringArray()
	for socket in sockets:
		parts.append("%d:%s" % [socket.side, socket.tiles])
	return "%s|%s" % [size, ",".join(parts)]


func _set_cell(p: Vector2i, cell: int) -> void:
	cells[p.y * size.x + p.x] = cell


func _group_sockets(door_tiles: Array[Vector2i]) -> void:
	var by_side: Array = [[], [], [], []]
	for p in door_tiles:
		var on_x_edge := p.x == 0 or p.x == size.x - 1
		var on_y_edge := p.y == 0 or p.y == size.y - 1
		if on_x_edge and on_y_edge:
			errors.append("door socket on a corner at %s" % p)
		elif p.y == 0:
			by_side[Side.NORTH].append(p)
		elif p.y == size.y - 1:
			by_side[Side.SOUTH].append(p)
		elif p.x == 0:
			by_side[Side.WEST].append(p)
		elif p.x == size.x - 1:
			by_side[Side.EAST].append(p)
		else:
			errors.append("door socket not on the outer edge at %s" % p)
	for side in 4:
		var tiles: Array = by_side[side]
		var horizontal := side == Side.NORTH or side == Side.SOUTH
		tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if horizontal else a.y < b.y)
		var run: Array[Vector2i] = []
		for p: Vector2i in tiles:
			if not run.is_empty():
				var prev := run.back() as Vector2i
				var contiguous := (p.x == prev.x + 1) if horizontal else (p.y == prev.y + 1)
				if not contiguous:
					_add_socket(side, run)
					run = []
			run.append(p)
		if not run.is_empty():
			_add_socket(side, run)


func _add_socket(side: int, run: Array[Vector2i]) -> void:
	if run.size() != CORRIDOR_WIDTH:
		errors.append("door socket at %s is %d tiles wide (must be %d)" % [run[0], run.size(), CORRIDOR_WIDTH])
		return
	var socket := Socket.new()
	socket.side = side
	socket.tiles = run.duplicate()
	socket.center = run[run.size() / 2]
	sockets.append(socket)


static func _group_regions(tiles: Dictionary) -> Array:
	var regions: Array = []
	var seen: Dictionary = {}
	var keys: Array = tiles.keys()
	keys.sort()
	for start: Vector2i in keys:
		if seen.has(start):
			continue
		var region: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			region.append(p)
			for d in SIDE_VECTORS:
				var n := p + d
				if tiles.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		region.sort()
		regions.append(region)
	return regions


static func region_bounds(region: Array) -> Rect2i:
	var bounds := Rect2i(region[0], Vector2i.ONE)
	for p: Vector2i in region:
		bounds = bounds.merge(Rect2i(p, Vector2i.ONE))
	return bounds


func _lint() -> void:
	if anchor == Vector2i(-1, -1):
		errors.append("missing anchor 'C'")
	elif not is_clear(anchor):
		errors.append("anchor %s is not clear (needs safe floor on all 8 neighbours)" % anchor)
	if sockets.is_empty():
		errors.append("no door sockets")
	var door_insides: Array[Vector2i] = []
	for socket in sockets:
		for tile in socket.tiles:
			var inside := tile - SIDE_VECTORS[socket.side]
			door_insides.append(inside)
			if not is_floor(inside):
				errors.append("door socket tile %s has no plain floor behind it" % tile)
	for group: Array in [enemy_spawns, reward_sockets, lore_sockets, event_sockets, cache_sockets]:
		for p: Vector2i in group:
			if not is_clear(p):
				errors.append("socket %s is not clear" % p)
	for region: Array in hazard_regions + spike_regions:
		var bounds := region_bounds(region)
		if maxi(bounds.size.x, bounds.size.y) > MAX_TIMED_REGION:
			errors.append("timed hazard region at %s is %s (max %d)" % [bounds.position, bounds.size, MAX_TIMED_REGION])
	# Pits and spikes keep away from doorways.
	for y in size.y:
		for x in size.x:
			var c := get_cell(Vector2i(x, y))
			if c != Cell.PIT and c != Cell.SPIKES:
				continue
			for inside in door_insides:
				if maxi(absi(x - inside.x), absi(y - inside.y)) < DOOR_CLEARANCE:
					errors.append("pit/spike at %s too close to a doorway" % Vector2i(x, y))
	_lint_bridges()
	_lint_door_approaches()
	# All walkable tiles must form one 4-connected area.
	var walkable: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			if is_walkable(Vector2i(x, y)):
				walkable.append(Vector2i(x, y))
	if walkable.is_empty():
		errors.append("no floor")
		return
	var seen: Dictionary = {walkable[0]: true}
	var stack: Array[Vector2i] = [walkable[0]]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in SIDE_VECTORS:
			var n := p + d
			if is_walkable(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	if seen.size() != walkable.size():
		errors.append("walkable area is not connected (%d of %d tiles reachable)" % [seen.size(), walkable.size()])


## Dressing sockets keep DOOR_CLEARANCE from doorway insides (no clutter at an
## entrance) and never touch terrain (pits, water, bridges, spikes, hazard
## sockets), so hazards stay readable and crossings unobstructed.
func _lint_dressing(hazard_tiles: Dictionary) -> void:
	var door_insides: Array[Vector2i] = []
	for socket in sockets:
		for tile in socket.tiles:
			door_insides.append(tile - SIDE_VECTORS[socket.side])
	for region: Array in dressing_regions:
		for p: Vector2i in region:
			for inside in door_insides:
				if maxi(absi(p.x - inside.x), absi(p.y - inside.y)) < DOOR_CLEARANCE:
					errors.append("dressing at %s too close to a doorway" % p)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := p + Vector2i(dx, dy)
					var c := get_cell(n)
					if c == Cell.PIT or c == Cell.WATER or c == Cell.BRIDGE or c == Cell.SPIKES or hazard_tiles.has(n):
						errors.append("dressing at %s touches terrain at %s" % [p, n])


## Every doorway must connect to the anchor through tiles where a player-sized
## body fits (walkable incl. timed spikes, all 8 neighbours walkable; socket
## tiles count as open). Interior walls, rubble, pits and water edges must never
## choke a doorway to less than CORRIDOR_WIDTH.
func _lint_door_approaches() -> void:
	if anchor == Vector2i(-1, -1):
		return
	var open: Dictionary = {}
	for socket in sockets:
		for tile in socket.tiles:
			open[tile] = true
	var seen: Dictionary = {anchor: true}
	var stack: Array[Vector2i] = [anchor]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in SIDE_VECTORS:
			var n := p + d
			if seen.has(n) or not (is_walkable(n) or open.has(n)) or not _body_fits(n, open):
				continue
			seen[n] = true
			stack.append(n)
	for socket in sockets:
		if not seen.has(socket.center):
			errors.append("doorway at %s is not reachable from the anchor with player clearance" % socket.center)


## A player-sized body centred on `p` touches only walkable or open-door tiles
## (beyond an open door lies corridor, counted as open).
func _body_fits(p: Vector2i, open: Dictionary) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := p + Vector2i(dx, dy)
			if not (is_walkable(n) or open.has(n) or (open.has(p) and get_cell(n) == Cell.OUTSIDE)):
				return false
	return true


func _lint_bridges() -> void:
	var bridge_tiles: Dictionary = {}
	for y in size.y:
		for x in size.x:
			if get_cell(Vector2i(x, y)) == Cell.BRIDGE:
				bridge_tiles[Vector2i(x, y)] = true
	for region: Array in _group_regions(bridge_tiles):
		var bounds := region_bounds(region)
		if mini(bounds.size.x, bounds.size.y) < MIN_BRIDGE_WIDTH:
			errors.append("bridge at %s is narrower than %d tiles" % [bounds.position, MIN_BRIDGE_WIDTH])
