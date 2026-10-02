class_name DungeonValidator
extends RefCounted
## Checks a generated floor before it is accepted. Anything reported here
## makes the generator retry (deterministically) or fail safely; a broken
## dungeon is never silently accepted. Checks run on the actual tile geometry,
## not just the graph.
##
## "Clear" tile = walkable with all eight neighbours walkable: a player-sized
## body fits there, and a 4-connected chain of clear tiles is a path it can
## physically follow. Two variants:
##   strict  timed hazards (spikes) count as blocked: where things stand
##           (player spawn, exit, enemy spawns, markers, event sockets)
##   route   spikes count as crossable (they have a safe window; regions are
##           capped so one window suffices): required routes
##   required  route, but tiles of risk hazards (optional risky routes) count
##           as blocked: every REQUIRED route (entry -> exit, every room,
##           corridors, doorway -> anchor) must exist on this mask, so a risky
##           route is never mandatory
## Pits and solids are never walkable; water is walkable (slow).
##
## Tactical fairness (Milestone 2.2, `_check_tactics` and friends): room roles
## fit their place and the depth, hazards have a purpose, threat stays within
## the room/floor budget, fights have maneuvering space, ambushes have another
## exit, rest rooms are safe, risk caches are reachable but optional, the
## spawn and every room entrance are free of damage, hazards never cover a
## room or leave no safe footing, and the main-path pacing holds. Enemy
## placement (SpawnPlanner) is fair from every doorway (ranged enemies far
## enough to react, no crossfire without cover) and puts the recipe's lead
## enemies where its terrain matters, seen from the approach doorway.

## Enemies never appear closer than this to the player when an encounter starts.
const MIN_SPAWN_DISTANCE := SpawnPlanner.MIN_SPAWN_DISTANCE
## Validation measures from the doorway, while the player triggers an encounter
## a little further in; the margin keeps the runtime guarantee.
const SPAWN_CHECK_MARGIN := 48.0
## Minimum Chebyshev distance (tiles) between a hazard or pit and a doorway.
const HAZARD_DOOR_CLEARANCE := 2
## No hazard or pit within this Chebyshev distance (tiles) of the player spawn.
const SPAWN_SAFE_RADIUS := 4
## Hazard + pit tiles may cover at most this share of a room's floor.
const MAX_DANGER_COVERAGE := 0.45
## Every hazard tile has safe footing (strict-clear) within this many tiles.
const SAFE_FOOTING_REACH := 4


static func validate(layout: DungeonLayout, profile: DepthProfile) -> PackedStringArray:
	var errors := PackedStringArray()
	_check_graph(layout, profile, errors)
	if not errors.is_empty():
		return errors
	_check_rooms(layout, errors)
	if not errors.is_empty():
		return errors
	var strict := clear_mask(layout, false)
	var route := clear_mask(layout, true)
	var required := required_mask(layout, route)
	var reached := _check_reachability(layout, strict, required, errors)
	_check_corridors(layout, required, errors)
	_check_room_interiors(layout, required, errors)
	_check_hazards(layout, errors)
	_check_pits(layout, errors)
	_check_encounters(layout, strict, errors)
	_check_spawn_plans(layout, strict, errors)
	var route_reached := flood(layout, route, layout.player_spawn)
	_check_markers(layout, strict, reached, route_reached, errors)
	_check_event_sockets(layout, strict, reached, errors)
	_check_spawn_safety(layout, errors)
	_check_room_entries(layout, strict, errors)
	_check_danger_coverage(layout, strict, errors)
	_check_dressing(layout, errors)
	_check_corridor_alcoves(layout, errors)
	_check_decor(layout, errors)
	_check_tactics(layout, profile, strict, route_reached, errors)
	_check_pacing(layout, profile, errors)
	return errors


## Route mask with every risk-route tile blocked: what a REQUIRED route may use.
## `route` (optional) is reused when the floor has no risk tiles.
static func required_mask(layout: DungeonLayout, route: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var blocked: Dictionary = {}
	for room in layout.rooms:
		for t in room.risk_tiles():
			blocked[layout.index_of(t)] = true
	if blocked.is_empty() and not route.is_empty():
		return route
	return clear_mask(layout, true, blocked)


## Shortest 4-connected walk over `mask` from `from` to `to` (inclusive), or
## empty if there is none. A non-empty `within` limits the search to that rect.
static func shortest_path(layout: DungeonLayout, mask: PackedByteArray, from: Vector2i, to: Vector2i,
		within: Rect2i = Rect2i()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not layout.in_bounds(from) or not layout.in_bounds(to):
		return result
	var w := layout.size.x
	var start := layout.index_of(from)
	var goal := layout.index_of(to)
	if mask[start] == 0 or mask[goal] == 0:
		return result
	var parent := PackedInt32Array()
	parent.resize(mask.size())
	parent.fill(-1)
	parent[start] = start
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		if i == goal:
			break
		for n in [i - 1, i + 1, i - w, i + w]:
			if n >= 0 and n < mask.size() and mask[n] == 1 and parent[n] == -1:
				if within.has_area() and not within.has_point(Vector2i(n % w, n / w)):
					continue
				parent[n] = i
				queue.append(n)
	if parent[goal] == -1:
		return result
	var at := goal
	while at != start:
		result.append(Vector2i(at % w, at / w))
		at = parent[at]
	result.append(from)
	result.reverse()
	return result


## 1 where a player-sized body can stand. `allow_hazard` makes timed hazards
## (spikes) count as walkable; `blocked` (tile indices) never counts.
static func clear_mask(layout: DungeonLayout, allow_hazard: bool = false, blocked: Dictionary = {}) -> PackedByteArray:
	var w := layout.size.x
	var h := layout.size.y
	var table: Array = DungeonLayout.WALKABLE_WITH_HAZARD if allow_hazard else DungeonLayout.WALKABLE_PLAIN
	var walkable := PackedByteArray()
	walkable.resize(w * h)
	var tiles := layout.tiles
	for i in w * h:
		walkable[i] = table[tiles[i]]
	for i: int in blocked:
		walkable[i] = 0
	# Separable 3x3 test: a horizontal 3-wide AND, then a vertical one.
	var across := PackedByteArray()
	across.resize(w * h)
	for y in h:
		var row := y * w
		for x in range(1, w - 1):
			var i := row + x
			across[i] = walkable[i - 1] & walkable[i] & walkable[i + 1]
	var clear := PackedByteArray()
	clear.resize(w * h)
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			var i := row + x
			clear[i] = across[i - w] & across[i] & across[i + w]
	return clear


## Tiles reachable from `start` through 4-connected mask tiles.
static func flood(layout: DungeonLayout, mask: PackedByteArray, start: Vector2i) -> PackedByteArray:
	var w := layout.size.x
	var reached := PackedByteArray()
	reached.resize(mask.size())
	if not layout.in_bounds(start) or mask[layout.index_of(start)] == 0:
		return reached
	var queue := PackedInt32Array([layout.index_of(start)])
	reached[queue[0]] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for n in [i - 1, i + 1, i - w, i + w]:
			if n >= 0 and n < mask.size() and mask[n] == 1 and reached[n] == 0:
				reached[n] = 1
				queue.append(n)
	return reached


static func _check_graph(layout: DungeonLayout, profile: DepthProfile, errors: PackedStringArray) -> void:
	var graph := layout.graph
	if graph == null:
		errors.append("no graph")
		return
	if not graph.error.is_empty():
		errors.append("graph: " + graph.error)
		return
	if graph.ids_with_role(DungeonGraph.Role.ENTRY).size() != 1:
		errors.append("expected exactly one entry")
	if graph.ids_with_role(DungeonGraph.Role.OBJECTIVE).size() != 1:
		errors.append("expected exactly one objective")
	if graph.main_path.size() < 2 \
			or graph.spaces[graph.entry_id()].role != DungeonGraph.Role.ENTRY \
			or graph.spaces[graph.objective_id()].role != DungeonGraph.Role.OBJECTIVE:
		errors.append("main path must run from entry to objective")
		return
	for i in range(1, graph.main_path.size()):
		if not graph.are_linked(graph.main_path[i - 1], graph.main_path[i]):
			errors.append("main path broken between %d and %d" % [graph.main_path[i - 1], graph.main_path[i]])
	var seen: Dictionary = {graph.entry_id(): true}
	var stack: Array[int] = [graph.entry_id()]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		for link_id in graph.spaces[id].link_ids:
			var other := graph.other_end(graph.links[link_id], id)
			if not seen.has(other):
				seen[other] = true
				stack.append(other)
	if seen.size() != graph.spaces.size():
		errors.append("%d space(s) disconnected from the entry" % (graph.spaces.size() - seen.size()))
	for rule in profile.special_rooms:
		if rule == null or not rule.required:
			continue
		var found := false
		for space in graph.spaces:
			if space.special_rule != rule:
				continue
			found = true
			if space.main_index <= 0 or space.main_index >= graph.main_path.size() - 1:
				errors.append("special room '%s' is not inside the main path" % rule.id)
			if graph.degree(space.id) != 2:
				errors.append("special room '%s' must have exactly 2 connections" % rule.id)
			if space.id < layout.rooms.size() and layout.rooms[space.id].template != rule.template:
				errors.append("special room '%s' uses the wrong template" % rule.id)
		if not found:
			errors.append("required special room '%s' missing" % rule.id)
	if layout.rooms.size() != graph.spaces.size():
		errors.append("room count %d != space count %d" % [layout.rooms.size(), graph.spaces.size()])


static func _check_rooms(layout: DungeonLayout, errors: PackedStringArray) -> void:
	if layout.conflicts > 0:
		errors.append("%d tile(s) claimed by two features" % layout.conflicts)
	var grid := Rect2i(Vector2i.ZERO, layout.size)
	for i in layout.rooms.size():
		var room := layout.rooms[i]
		if not grid.encloses(room.bounds()):
			errors.append("room %d outside the map" % room.id)
		for j in range(i + 1, layout.rooms.size()):
			if room.bounds().grow(1).intersects(layout.rooms[j].bounds()):
				errors.append("rooms %d and %d overlap or touch" % [room.id, layout.rooms[j].id])
		for link_id in layout.graph.spaces[room.id].link_ids:
			var has_door := false
			for door in room.doors:
				if door.link == link_id:
					has_door = true
			if not has_door:
				errors.append("room %d has no doorway for link %d" % [room.id, link_id])
	if layout.room_at_tile(layout.player_spawn) != layout.entry_room():
		errors.append("player spawn is not in the entry room")
	if layout.room_at_tile(layout.exit_tile) != layout.objective_room():
		errors.append("exit is not in the objective room")


## Entry -> exit and entry -> every room on the route mask. Returns the reached map.
static func _check_reachability(layout: DungeonLayout, strict: PackedByteArray, route: PackedByteArray,
		errors: PackedStringArray) -> PackedByteArray:
	if strict[layout.index_of(layout.player_spawn)] == 0:
		errors.append("player spawn is not clear of walls/pits/hazards")
	if strict[layout.index_of(layout.exit_tile)] == 0:
		errors.append("exit is not clear of walls/pits/hazards")
	var reached := flood(layout, route, layout.player_spawn)
	if reached[layout.index_of(layout.exit_tile)] == 0:
		errors.append("objective exit unreachable from the entry")
	for room in layout.rooms:
		if reached[layout.index_of(room.anchor)] == 0:
			errors.append("room %d unreachable from the entry" % room.id)
	return reached


## Each graph link must have its own traversable corridor between its two doorways.
static func _check_corridors(layout: DungeonLayout, route: PackedByteArray, errors: PackedStringArray) -> void:
	if layout.corridors.size() != layout.graph.links.size():
		errors.append("corridor count %d != link count %d" % [layout.corridors.size(), layout.graph.links.size()])
	for corridor in layout.corridors:
		var owner_id := DungeonLayout.CORRIDOR_OWNER_BASE + corridor.link
		var door_a := _door_for_link(layout.rooms[corridor.a], corridor.link)
		var door_b := _door_for_link(layout.rooms[corridor.b], corridor.link)
		if door_a.is_empty() or door_b.is_empty():
			errors.append("corridor %d is missing a doorway" % corridor.link)
			continue
		var allowed := PackedByteArray()
		allowed.resize(route.size())
		var bounds := Rect2i(corridor.rects[0])
		for rect in corridor.rects:
			bounds = bounds.merge(rect)
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var i := y * layout.size.x + x
				if route[i] == 1 and layout.owners[i] == owner_id:
					allowed[i] = 1
		for door: Dictionary in [door_a, door_b]:
			for t: Vector2i in door.tiles:
				allowed[layout.index_of(t)] = route[layout.index_of(t)]
		var reached := flood(layout, allowed, door_a.center)
		if reached[layout.index_of(door_b.center)] == 0:
			errors.append("corridor for link %d (%d-%d) is not traversable" % [corridor.link, corridor.a, corridor.b])


static func _door_for_link(room: DungeonLayout.PlacedRoom, link_id: int) -> Dictionary:
	for door in room.doors:
		if door.link == link_id:
			return door
	return {}


## Inside each room: every doorway connects to the anchor through clear route
## tiles (interior walls, pits and water never cut a doorway off), and all
## walkable tiles are one piece (no stranded pockets).
static func _check_room_interiors(layout: DungeonLayout, route: PackedByteArray, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		var bounds := room.bounds()
		var inside := PackedByteArray()
		inside.resize(layout.tiles.size())
		var walk_mask := PackedByteArray()
		walk_mask.resize(layout.tiles.size())
		var total := 0
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var i := y * layout.size.x + x
				if layout.owners[i] != room.id:
					continue
				if route[i] == 1:
					inside[i] = 1
				if DungeonLayout.is_walkable_kind(layout.tiles[i], true):
					walk_mask[i] = 1
					total += 1
		var routed := flood(layout, inside, room.anchor)
		for door in room.doors:
			if routed[layout.index_of(door.center)] == 0:
				errors.append("room %d: doorway to link %d is cut off inside the room" % [room.id, door.link])
		var walk := flood(layout, walk_mask, room.anchor)
		var count := 0
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				count += walk[y * layout.size.x + x]
		if count != total:
			errors.append("room %d floor is split (%d of %d tiles connected)" % [room.id, count, total])


static func _check_hazards(layout: DungeonLayout, errors: PackedStringArray) -> void:
	# Every hazard tile must belong to a listed hazard (so its size and door
	# clearance are checked below) and doorways are never hazardous.
	var listed: Dictionary = {}
	for room in layout.rooms:
		for hazard in room.hazards:
			for t: Vector2i in hazard.tiles:
				listed[t] = true
		for door in room.doors:
			for t: Vector2i in door.tiles:
				if layout.get_tile(t) == DungeonLayout.Tile.HAZARD:
					errors.append("hazard on a doorway of room %d" % room.id)
	for i in layout.tiles.size():
		if layout.tiles[i] == DungeonLayout.Tile.HAZARD:
			var tile := Vector2i(i % layout.size.x, i / layout.size.x)
			if not listed.has(tile):
				errors.append("unlisted hazard tile %s" % tile)
	for room in layout.rooms:
		var room_hazard_tiles: Dictionary = {}
		for hazard in room.hazards:
			for t: Vector2i in hazard.tiles:
				room_hazard_tiles[t] = true
				if layout.get_tile(t) != DungeonLayout.Tile.HAZARD:
					errors.append("hazard tile %s of room %d is not marked" % [t, room.id])
				if t == room.anchor:
					errors.append("hazard on the anchor of room %d" % room.id)
				for door in room.doors:
					var inside: Vector2i = door.inside
					if maxi(absi(t.x - inside.x), absi(t.y - inside.y)) < HAZARD_DOOR_CLEARANCE:
						errors.append("hazard too close to a doorway in room %d" % room.id)
		for region: Array in RoomShape._group_regions(room_hazard_tiles):
			var box := RoomShape.region_bounds(region)
			if maxi(box.size.x, box.size.y) > RoomShape.MAX_TIMED_REGION:
				errors.append("room %d: hazard area %s too long to cross in one safe window" % [room.id, box.size])


static func _check_pits(layout: DungeonLayout, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		var bounds := room.bounds()
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				if layout.get_tile(Vector2i(x, y)) != DungeonLayout.Tile.PIT:
					continue
				for door in room.doors:
					var inside: Vector2i = door.inside
					if maxi(absi(x - inside.x), absi(y - inside.y)) < HAZARD_DOOR_CLEARANCE:
						errors.append("pit too close to a doorway in room %d" % room.id)


static func _check_encounters(layout: DungeonLayout, strict: PackedByteArray, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		if room.encounter == DungeonGraph.Encounter.NONE:
			continue
		if room.enemy_ids.is_empty():
			errors.append("encounter room %d has no enemies" % room.id)
		for enemy_id in room.enemy_ids:
			if not EnemyCatalog.has(enemy_id):
				errors.append("unknown enemy '%s' in room %d" % [enemy_id, room.id])
		# Enemies walk water and spikes but never pits or walls: every spawn must
		# share the anchor's walkable area, so the fight can always reach the player.
		var bounds := room.bounds()
		var enemy_mask := PackedByteArray()
		enemy_mask.resize(layout.tiles.size())
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var i := y * layout.size.x + x
				if layout.owners[i] == room.id and DungeonLayout.is_walkable_kind(layout.tiles[i], true):
					enemy_mask[i] = 1
		var enemy_reach := flood(layout, enemy_mask, room.anchor)
		for t in room.spawn_candidates:
			var i := layout.index_of(t)
			if strict[i] == 0 or layout.get_owner_of(t) != room.id:
				errors.append("invalid spawn point %s in room %d" % [t, room.id])
			elif enemy_reach[i] == 0:
				errors.append("spawn point %s in room %d cannot reach the player" % [t, room.id])
		# Whichever doorway the player uses, enough spawns must be far enough away.
		for door in room.doors:
			var inside := layout.tile_center(door.inside)
			var far := 0
			for t in room.spawn_candidates:
				if layout.tile_center(t).distance_to(inside) >= MIN_SPAWN_DISTANCE + SPAWN_CHECK_MARGIN:
					far += 1
			if far < room.enemy_ids.size():
				errors.append("room %d: only %d spawn point(s) far from a doorway, %d needed" % [room.id, far, room.enemy_ids.size()])


## The runtime spawn plan, checked from every doorway: all enemies placed, at a
## fair distance (ranged ones far enough to read the telegraph), no ranged
## crossfire in a room without cover, and the recipe's tactic realized from
## the approach doorway (not just a label).
static func _check_spawn_plans(layout: DungeonLayout, strict: PackedByteArray, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		if room.encounter == DungeonGraph.Encounter.NONE or room.enemy_ids.is_empty():
			continue
		if SpawnPlanner.ranged_count(room.enemy_ids) > SpawnPlanner.MAX_RANGED_WITHOUT_COVER \
				and not ThreatModel.features(layout, room, strict).cover:
			errors.append("room %d: %d ranged enemies without cover (unavoidable crossfire)" % [
				room.id, SpawnPlanner.ranged_count(room.enemy_ids)])
		for door in room.doors:
			var from := SpawnPlanner.entry_point(layout, door)
			var reason := SpawnPlanner.unfair_reason(layout, room, from, SpawnPlanner.plan(layout, room, from))
			if reason != "":
				errors.append("room %d: entering from link %d, %s" % [room.id, door.link, reason])
		var approach := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, room))
		if not SpawnPlanner.realizes(layout, room, approach, SpawnPlanner.plan(layout, room, approach)):
			errors.append("room %d: recipe '%s' does not place its enemies where the terrain matters" % [room.id, room.recipe])


## Markers stand on clear floor reachable without risk; a risk cache only has
## to be reachable at all (through its risk: that is the point).
static func _check_markers(layout: DungeonLayout, strict: PackedByteArray, reached: PackedByteArray,
		route_reached: PackedByteArray, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		for marker in room.markers:
			var t: Vector2i = marker.tile
			var i := layout.index_of(t)
			var reach := route_reached if marker.kind == &"cache" else reached
			if layout.get_owner_of(t) != room.id or not layout.is_walkable(t):
				errors.append("%s marker in room %d is not on safe floor" % [marker.kind, room.id])
			elif marker.kind != &"secret" and (strict[i] == 0 or reach[i] == 0):
				errors.append("%s marker in room %d is not clear or not reachable" % [marker.kind, room.id])


static func _check_event_sockets(layout: DungeonLayout, strict: PackedByteArray, reached: PackedByteArray,
		errors: PackedStringArray) -> void:
	var taken: Dictionary = {layout.player_spawn: "player spawn", layout.exit_tile: "exit"}
	for room in layout.rooms:
		for marker in room.markers:
			taken[marker.tile] = "marker"
	for socket in layout.event_sockets:
		var t: Vector2i = socket.tile
		var i := layout.index_of(t)
		if strict[i] == 0 or reached[i] == 0:
			errors.append("event socket %s is not clear or not reachable" % t)
		elif socket.room >= 0 and layout.get_owner_of(t) != socket.room:
			errors.append("event socket %s is outside its room" % t)
		elif socket.room < 0 and layout.corridor_at_tile(t) != socket.link:
			errors.append("event socket %s is outside its corridor" % t)
		if taken.has(t):
			errors.append("event socket %s overlaps the %s" % [t, taken[t]])


## "No hazard at the player spawn": the entry holds no fight and no hazard or
## pit lies within SPAWN_SAFE_RADIUS tiles of where the player appears.
static func _check_spawn_safety(layout: DungeonLayout, errors: PackedStringArray) -> void:
	var entry := layout.entry_room()
	if not entry.enemy_ids.is_empty() or entry.encounter != DungeonGraph.Encounter.NONE:
		errors.append("the entry room holds enemies")
	var r := SPAWN_SAFE_RADIUS
	for y in range(layout.player_spawn.y - r, layout.player_spawn.y + r + 1):
		for x in range(layout.player_spawn.x - r, layout.player_spawn.x + r + 1):
			var kind := layout.get_tile(Vector2i(x, y))
			if kind == DungeonLayout.Tile.HAZARD or kind == DungeonLayout.Tile.PIT:
				errors.append("hazard within %d tiles of the player spawn" % r)
				return


## "No unavoidable damage right after entering": the first two tiles inside
## every doorway are strict-clear (no spikes, pit or wall within reach).
static func _check_room_entries(layout: DungeonLayout, strict: PackedByteArray, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		for door in room.doors:
			var inward: Vector2i = -RoomShape.SIDE_VECTORS[door.side]
			var inside: Vector2i = door.inside
			for step in 2:
				if strict[layout.index_of(inside + inward * step)] == 0:
					errors.append("room %d: the entrance from link %d is not safe to step into" % [room.id, door.link])
					break


## Hazards never swallow a room: hazard + pit tiles cover at most
## MAX_DANGER_COVERAGE of its floor, and every hazard tile has safe footing
## (a strict-clear tile) within SAFE_FOOTING_REACH tiles.
static func _check_danger_coverage(layout: DungeonLayout, strict: PackedByteArray, errors: PackedStringArray) -> void:
	var w := layout.size.x
	var walkable := DungeonLayout.WALKABLE_WITH_HAZARD
	for room in layout.rooms:
		var bounds := room.bounds()
		var floor_tiles := 0
		var danger := 0
		var no_footing := false
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var i := y * w + x
				if layout.owners[i] != room.id:
					continue
				var kind := layout.tiles[i]
				if kind == DungeonLayout.Tile.PIT or kind == DungeonLayout.Tile.HAZARD:
					danger += 1
					floor_tiles += 1
					if kind == DungeonLayout.Tile.HAZARD and not no_footing:
						no_footing = not _has_footing(layout, strict, x, y)
				elif walkable[kind] == 1:
					floor_tiles += 1
		if floor_tiles > 0 and danger > floor_tiles * MAX_DANGER_COVERAGE:
			errors.append("room %d: hazards cover %d of %d floor tiles (too many stacked hazards)" % [room.id, danger, floor_tiles])
		if no_footing:
			errors.append("room %d: a hazard area leaves no safe footing nearby" % room.id)


static func _has_footing(layout: DungeonLayout, strict: PackedByteArray, tx: int, ty: int) -> bool:
	var r := SAFE_FOOTING_REACH
	var w := layout.size.x
	for y in range(maxi(ty - r, 0), mini(ty + r + 1, layout.size.y)):
		var row := y * w
		for x in range(maxi(tx - r, 0), mini(tx + r + 1, w)):
			if strict[row + x] == 1:
				return true
	return false


## Room roles, hazard purposes, threat budgets, maneuvering space, escape
## routes, rest-room safety and risk caches.
static func _check_tactics(layout: DungeonLayout, profile: DepthProfile, strict: PackedByteArray,
		route_reached: PackedByteArray, errors: PackedStringArray) -> void:
	var allowed := profile.allowed_roles()
	var structural := {DungeonGraph.Role.ENTRY: RoomRole.ENTRY, DungeonGraph.Role.OBJECTIVE: RoomRole.OBJECTIVE,
		DungeonGraph.Role.SPECIAL: RoomRole.STORY}
	var floor_total := 0.0
	for room in layout.rooms:
		var role_name := RoomRole.name_of(room.tactic)
		if structural.has(room.role):
			if room.tactic != structural[room.role]:
				errors.append("room %d: role %s does not fit its place in the graph" % [room.id, role_name])
		elif structural.values().has(room.tactic):
			errors.append("room %d: role %s outside its reserved place" % [room.id, role_name])
		if not allowed.has(room.tactic):
			errors.append("room %d: role %s is not allowed at depth %d" % [room.id, role_name, profile.depth])
		var expected := RoomRole.encounter_for(room.tactic)
		if room.tactic == RoomRole.OBJECTIVE and profile.objective_encounter:
			expected = DungeonGraph.Encounter.COMBAT
		if room.encounter != expected:
			errors.append("room %d: encounter does not match its role %s" % [room.id, role_name])
		if room.encounter == DungeonGraph.Encounter.NONE and not room.enemy_ids.is_empty():
			errors.append("room %d: a quiet %s room holds enemies" % [room.id, role_name])
		# Dangerous terrain only where it is the point of the room.
		var fixed := room.tactic == RoomRole.ENTRY or room.tactic == RoomRole.OBJECTIVE or room.tactic == RoomRole.STORY
		var f := ThreatModel.features(layout, room, strict)
		var has_terrain := f.pit or f.water or not room.hazards.is_empty()
		if not fixed and not RoomRole.wants_terrain(room.tactic) and has_terrain:
			errors.append("room %d: %s room has pits/water/spikes without a reason" % [room.id, role_name])
		if RoomRole.wants_terrain(room.tactic) and not has_terrain:
			errors.append("room %d: %s room has no terrain to use" % [room.id, role_name])
		var purposes := RoomRole.allowed_purposes(room.tactic)
		for hazard in room.hazards:
			if not purposes.has(hazard.get("purpose", &"")):
				errors.append("room %d: hazard without a valid purpose ('%s' in a %s room)" % [
					room.id, hazard.get("purpose", &""), role_name])
		_check_role_rules(layout, room, route_reached, errors)
		# Threat: recomputed independently of what the generator recorded.
		var threat := ThreatModel.score(f, room.enemy_ids, ThreatModel.is_locked(room))
		if absf(threat - room.threat) > 0.01:
			errors.append("room %d: recorded threat %.2f differs from the computed %.2f" % [room.id, room.threat, threat])
		var budget := profile.threat_budget_for(room.tactic)
		if threat > budget + 0.001:
			errors.append("room %d (%s): threat %.2f exceeds its budget %.2f" % [room.id, role_name, threat, budget])
		floor_total += threat
		if not room.enemy_ids.is_empty():
			var needed := ThreatModel.MANEUVER_BASE + ThreatModel.MANEUVER_PER_ENEMY * room.enemy_ids.size()
			if f.clear_tiles < needed:
				errors.append("room %d: not enough maneuvering space for %d enemies (%d of %d clear tiles)" % [
					room.id, room.enemy_ids.size(), f.clear_tiles, needed])
	if floor_total > profile.floor_threat_budget + 0.001:
		errors.append("floor threat %.2f exceeds the depth budget %.2f" % [floor_total, profile.floor_threat_budget])


static func _check_role_rules(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, route_reached: PackedByteArray,
		errors: PackedStringArray) -> void:
	match room.tactic:
		RoomRole.AMBUSH:
			# The doors stay open: there must be another way out to retreat to.
			if room.doors.size() < 2:
				errors.append("ambush room %d has no alternate exit (escape route)" % room.id)
		RoomRole.REST:
			if not room.has_marker(&"heal"):
				errors.append("rest room %d has no recovery socket" % room.id)
			if not room.hazards.is_empty() or not room.enemy_ids.is_empty():
				errors.append("rest room %d is not safe" % room.id)
		RoomRole.RISK_REWARD:
			if not room.has_marker(&"cache"):
				errors.append("risk room %d has no cache" % room.id)
			if room.risk_tiles().is_empty():
				errors.append("risk room %d has no visible risk" % room.id)
			for marker in room.markers:
				if marker.kind == &"cache" and route_reached[layout.index_of(marker.tile)] == 0:
					errors.append("risk room %d: the cache cannot be reached even through the risk" % room.id)
		RoomRole.HAZARD_COMBAT:
			var recipe: Dictionary = TacticalComposer.RECIPES.get(room.recipe, {})
			if recipe.is_empty() or not (recipe.roles as Array).has("HAZARD_COMBAT"):
				errors.append("hazard fight %d has no terrain interaction (recipe '%s')" % [room.id, room.recipe])
		RoomRole.CHALLENGE:
			if not room.has_marker(&"power"):
				errors.append("challenge room %d guards no reward" % room.id)
		RoomRole.REWARD:
			if not room.has_marker(&"reward"):
				errors.append("reward room %d has no reward" % room.id)
	if room.recipe != &"" and not TacticalComposer.RECIPES.has(room.recipe):
		errors.append("room %d uses an unknown recipe '%s'" % [room.id, room.recipe])


## Main-path rhythm: no more than max_consecutive_combat fights in a row (an
## objective fight counts like any other), no more than max_consecutive_terrain
## terrain challenges in a row, no role three times in a row, REST only after
## a fight, at least min_combat_rooms fights.
static func _check_pacing(layout: DungeonLayout, profile: DepthProfile, errors: PackedStringArray) -> void:
	var heavy_run := 0
	var terrain_run := 0
	var path := layout.graph.main_path
	for i in path.size():
		var room := layout.rooms[path[i]]
		var role := room.tactic
		var last := i == path.size() - 1
		var heavy := RoomRole.is_heavy(role) or (last and room.encounter != DungeonGraph.Encounter.NONE)
		heavy_run = heavy_run + 1 if heavy else 0
		terrain_run = terrain_run + 1 if RoomRole.is_terrain_challenge(role) else 0
		if heavy_run > profile.max_consecutive_combat:
			errors.append("pacing: %d fights in a row on the main path (max %d)" % [heavy_run, profile.max_consecutive_combat])
		if terrain_run > profile.max_consecutive_terrain:
			errors.append("pacing: %d terrain challenges in a row (max %d)" % [terrain_run, profile.max_consecutive_terrain])
		if i >= 2 and role == layout.rooms[path[i - 1]].tactic and role == layout.rooms[path[i - 2]].tactic:
			errors.append("pacing: %s three times in a row on the main path" % RoomRole.name_of(role))
		if role == RoomRole.REST and (i == 0 or not RoomRole.is_heavy(layout.rooms[path[i - 1]].tactic)):
			errors.append("pacing: rest room %d does not follow a fight" % room.id)
	var rests := 0
	for room in layout.rooms:
		if room.tactic == RoomRole.REST:
			rests += 1
	if rests > profile.max_rest_rooms:
		errors.append("pacing: %d rest rooms (max %d)" % [rests, profile.max_rest_rooms])
	var fights := 0
	for i in range(1, path.size() - 1):
		if RoomRole.is_heavy(layout.rooms[path[i]].tactic):
			fights += 1
	if fights < profile.min_combat_rooms:
		errors.append("pacing: only %d fights on the main path (min %d)" % [fights, profile.min_combat_rooms])
	var terrain := 0
	for id in path:
		if RoomRole.is_terrain_challenge(layout.rooms[id].tactic):
			terrain += 1
	if terrain < profile.min_terrain_rooms:
		errors.append("pacing: only %d terrain challenges on the main path (min %d)" % [terrain, profile.min_terrain_rooms])


## Optional structure (M2.2 play-test polish): only where the role furnishes
## rooms, solid where recorded, never within DOOR_CLEARANCE of a doorway, never
## touching terrain. (Reachability, clearance and maneuvering space are
## checked by the general rules above.)
static func _check_dressing(layout: DungeonLayout, errors: PackedStringArray) -> void:
	for room in layout.rooms:
		if room.dressing.is_empty():
			continue
		if RoomRole.dressing_density(room.tactic) <= 0.0:
			errors.append("room %d: structure dressing in a %s room" % [room.id, RoomRole.name_of(room.tactic)])
		for piece in room.dressing:
			for t: Vector2i in piece.tiles:
				if layout.get_tile(t) != piece.kind or layout.get_owner_of(t) != room.id:
					errors.append("room %d: dressing tile %s is not where it was recorded" % [room.id, t])
				for door in room.doors:
					var inside: Vector2i = door.inside
					if maxi(absi(t.x - inside.x), absi(t.y - inside.y)) < RoomShape.DOOR_CLEARANCE:
						errors.append("room %d: dressing at %s crowds a doorway" % [room.id, t])
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if DungeonLayout.is_terrain_kind(layout.get_tile(t + Vector2i(dx, dy))):
							errors.append("room %d: dressing at %s touches terrain" % [room.id, t])


## Corridor alcoves sit beside the lane, never in it: every lane tile is still
## open corridor, and alcove tiles belong to their corridor.
static func _check_corridor_alcoves(layout: DungeonLayout, errors: PackedStringArray) -> void:
	for corridor in layout.corridors:
		var owner_id := DungeonLayout.CORRIDOR_OWNER_BASE + corridor.link
		for rect in corridor.rects:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if layout.get_tile(Vector2i(x, y)) != DungeonLayout.Tile.CORRIDOR:
						errors.append("corridor %d: lane tile %s is blocked" % [corridor.link, Vector2i(x, y)])
		for alcove in corridor.alcoves:
			for t: Vector2i in alcove.tiles + alcove.rubble:
				if layout.get_owner_of(t) != owner_id:
					errors.append("corridor %d: alcove tile %s is not part of the corridor" % [corridor.link, t])
				for rect in corridor.rects:
					if rect.has_point(t):
						errors.append("corridor %d: alcove tile %s is inside the lane" % [corridor.link, t])


## Placeholder decor is cosmetic but still follows its rules: torches only on
## walls, floor marks only on plain floor, off terrain, sockets and doorways.
static func _check_decor(layout: DungeonLayout, errors: PackedStringArray) -> void:
	var reserved := DecorPlacer.reserved_tiles(layout)
	for item in layout.decor:
		var t: Vector2i = item.tile
		if item.kind == &"torch":
			if layout.get_tile(t) != DungeonLayout.Tile.WALL:
				errors.append("decor: torch socket %s is not on a wall" % t)
		elif not DecorPlacer.floor_mark_ok(layout, t, reserved):
			errors.append("decor: %s at %s is on terrain, a socket or a doorway approach" % [item.kind, t])
