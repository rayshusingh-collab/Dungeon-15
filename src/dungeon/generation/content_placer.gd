class_name ContentPlacer
extends RefCounted
## Stage 4: per-room content, driven by each room's RoomRole. Rooms draw from
## their own substreams ("hazards"/"spawns"/"tactics" + room id), so content
## in one room never depends on how many numbers another room consumed.
## - Markers: reward / lore / secret by purpose; risk cache ('$') in
##   RISK_REWARD rooms, heal shrine in REST rooms, power socket in CHALLENGE
##   rooms, story marker in special rooms.
## - Hazards always have a purpose: authored spikes ('^') are "timing" (or
##   "risk_route" in risk rooms); optional sockets ('H') are only filled where
##   the role wants them (HAZARD: route shaping by density; HAZARD_COMBAT: all
##   that keep the room intact, as area denial). Everywhere else they stay floor.
## - Encounters: TacticalComposer picks a recipe and enemies under the room's
##   threat budget (and what is left of the floor budget); spawn candidates are
##   'E' tiles still clear after hazards, in seeded order.
## - Threat and the design note of every room are recorded (ThreatModel).
## - Risk rooms get their safe/risky routes to the cache analysed (debug).
## - Event sockets: 'T' tiles in rooms plus the middle of every corridor; one
##   ("events" stream) is armed, preferably just before a fight (tension).
## Also records the player spawn (entry anchor) and exit tile (objective anchor).


static func place(layout: DungeonLayout, profile: DepthProfile, streams: SeedStreams) -> void:
	layout.floor_threat_budget = profile.floor_threat_budget
	for room in layout.rooms:
		_place_markers(room)
		_place_authored_spikes(room)
		_place_hazards(layout, room, profile, streams.stream("hazards", room.id))
		_downgrade_if_no_terrain(layout, room)
		_place_dressing(layout, room, profile, streams.stream("dressing", room.id))
		for local in room.shape.prop_sockets:
			room.prop_sockets.append(room.to_world(local))
	layout.player_spawn = layout.entry_room().anchor
	layout.exit_tile = layout.objective_room().anchor
	# Fights are composed after all terrain exists, main path first, so the
	# floor budget is spent where the pacing put the fights. Composition never
	# changes tiles, so one clearance mask serves every room.
	var strict := DungeonValidator.clear_mask(layout, false)
	var spent := 0.0
	for id in encounter_order(layout):
		var room := layout.rooms[id]
		var features := ThreatModel.features(layout, room, strict)
		room.threat_budget = profile.threat_budget_for(room.tactic)
		if room.encounter != DungeonGraph.Encounter.NONE:
			_place_spawn_candidates(layout, room, streams.stream("spawns", room.id))
			var budget := minf(room.threat_budget, maxf(profile.floor_threat_budget - spent, 0.0))
			TacticalComposer.compose(layout, room, profile, streams.stream("tactics", room.id), budget, features)
		room.threat = ThreatModel.score(features, room.enemy_ids, ThreatModel.is_locked(room))
		room.design_note = TacticalComposer.design_note(room, features)
		spent += room.threat
	_analyse_risk_routes(layout)
	_place_event_sockets(layout, profile, streams.stream("events"))
	DecorPlacer.place(layout, streams)


## Main path first (entry -> objective), then the other rooms by id.
static func encounter_order(layout: DungeonLayout) -> Array[int]:
	var order: Array[int] = []
	for id in layout.graph.main_path:
		order.append(id)
	for room in layout.rooms:
		if not order.has(room.id):
			order.append(room.id)
	return order


static func _place_markers(room: DungeonLayout.PlacedRoom) -> void:
	var shape := room.shape
	match room.purpose:
		DungeonGraph.Purpose.REWARD:
			if room.tactic == RoomRole.RISK_REWARD:
				room.markers.append({"kind": &"cache", "tile": _socket_or_anchor(room, shape.cache_sockets)})
			else:
				room.markers.append({"kind": &"reward", "tile": _socket_or_anchor(room, shape.reward_sockets)})
		DungeonGraph.Purpose.OPTIONAL_COMBAT:
			room.markers.append({"kind": &"power", "tile": _socket_or_anchor(room, shape.reward_sockets)})
		DungeonGraph.Purpose.LORE:
			room.markers.append({"kind": &"lore", "tile": _socket_or_anchor(room, shape.lore_sockets)})
		DungeonGraph.Purpose.SECRET:
			room.markers.append({"kind": &"secret", "tile": _socket_or_anchor(room, shape.secret_sockets)})
		DungeonGraph.Purpose.RECOVERY:
			room.markers.append({"kind": &"heal", "tile": _socket_or_anchor(room, shape.reward_sockets)})
	if room.role == DungeonGraph.Role.SPECIAL:
		room.markers.append({"kind": &"story", "tile": room.anchor})


static func _socket_or_anchor(room: DungeonLayout.PlacedRoom, sockets: Array[Vector2i]) -> Vector2i:
	return room.to_world(sockets[0]) if not sockets.is_empty() else room.anchor


static func _place_authored_spikes(room: DungeonLayout.PlacedRoom) -> void:
	var purpose := RoomRole.PURPOSE_RISK_ROUTE if room.tactic == RoomRole.RISK_REWARD else RoomRole.PURPOSE_TIMING
	for region: Array in room.shape.spike_regions:
		var world_tiles: Array[Vector2i] = []
		for local: Vector2i in region:
			world_tiles.append(room.to_world(local))
		room.hazards.append({"type": &"spikes", "tiles": world_tiles, "authored": true, "purpose": purpose})


static func _place_hazards(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, profile: DepthProfile,
		rng: RandomNumberGenerator) -> void:
	if profile.hazard_types.is_empty():
		return
	var purpose: StringName
	var density := profile.hazard_density
	match room.tactic:
		RoomRole.HAZARD:
			purpose = RoomRole.PURPOSE_ROUTE_SHAPING
		RoomRole.HAZARD_COMBAT:
			# The fight is about this terrain: use every socket that keeps the room intact.
			purpose = RoomRole.PURPOSE_AREA_DENIAL
			density = 1.0
		_:
			return  # no reason for a hazard here: sockets stay plain floor
	var regions := room.shape.hazard_regions
	for r in regions.size():
		var region: Array = regions[r]
		# Density decides how many sockets are used; a terrain room whose only
		# terrain is its sockets always gets at least one.
		var must := r == regions.size() - 1 and room.hazards.is_empty() and room.shape.is_clean()
		if rng.randf() >= density and not must:
			continue
		var hazard_type: StringName = profile.hazard_types[rng.randi_range(0, profile.hazard_types.size() - 1)]
		var world_tiles: Array[Vector2i] = []
		for local: Vector2i in region:
			var t := room.to_world(local)
			layout.set_tile(t, DungeonLayout.Tile.HAZARD, room.id)
			world_tiles.append(t)
		# Content placement never makes a floor invalid, whatever the template's
		# hazard sockets look like: keep the hazard only if the room stays intact.
		if hazard_keeps_room_intact(layout, room):
			room.hazards.append({"type": hazard_type, "tiles": world_tiles, "authored": false, "purpose": purpose})
		else:
			for t in world_tiles:
				layout.set_tile(t, DungeonLayout.Tile.FLOOR, room.id)


## Optional structure ('x' rubble, 'o' pillar sockets): each region is used
## with the room role's dressing density ("dressing" stream, one draw per
## region). The template lint already proves any subset keeps doorways,
## sockets and lanes clear (the validator re-checks the floor); here a region
## is also refused if it would touch placed terrain or, in a fight room, cut
## the clear floor below what the room's size class needs for its full enemy
## count (open arenas stay open).
static func _place_dressing(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, profile: DepthProfile,
		rng: RandomNumberGenerator) -> void:
	var regions := room.shape.dressing_regions
	var density := RoomRole.dressing_density(room.tactic)
	if regions.is_empty() or density <= 0.0:
		return
	var min_clear := 0
	if room.encounter != DungeonGraph.Encounter.NONE:
		var sizes := profile.enemies_by_size
		var cap := sizes[clampi(room.template.size_class, 0, sizes.size() - 1)] if not sizes.is_empty() else 1
		min_clear = ThreatModel.MANEUVER_BASE + ThreatModel.MANEUVER_PER_ENEMY * cap
	var clear := _clear_tiles(layout, room) if min_clear > 0 else 0
	for r in regions.size():
		if rng.randf() >= density:
			continue
		var kind := LayoutBuilder.tile_for_cell(room.shape.dressing_kinds[r])
		var world_tiles: Array[Vector2i] = []
		for local: Vector2i in regions[r]:
			world_tiles.append(room.to_world(local))
		if not _dressing_clear_of_terrain(layout, world_tiles):
			continue
		# Only tiles within one step of the region can stop being clear.
		var before := _clear_around(layout, world_tiles) if min_clear > 0 else 0
		for t in world_tiles:
			layout.set_tile(t, kind, room.id)
		var after := clear - before + _clear_around(layout, world_tiles) if min_clear > 0 else 0
		if min_clear == 0 or after >= min_clear:
			room.dressing.append({"kind": kind, "tiles": world_tiles})
			clear = after
		else:
			for t in world_tiles:
				layout.set_tile(t, DungeonLayout.Tile.FLOOR, room.id)


## Clear tiles within one step of `tiles` (each counted once).
static func _clear_around(layout: DungeonLayout, tiles: Array[Vector2i]) -> int:
	var seen: Dictionary = {}
	for t in tiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := t + Vector2i(dx, dy)
				if not seen.has(n):
					seen[n] = true
	var count := 0
	for n: Vector2i in seen:
		if layout.is_clear(n):
			count += 1
	return count


## No pit, water, bridge or hazard tile within one tile of the region.
static func _dressing_clear_of_terrain(layout: DungeonLayout, tiles: Array[Vector2i]) -> bool:
	for t in tiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if DungeonLayout.is_terrain_kind(layout.get_tile(t + Vector2i(dx, dy))):
					return false
	return true


## Strict-clear tiles of the room (where a body can stand away from walls).
static func _clear_tiles(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> int:
	var count := 0
	var bounds := room.bounds()
	for y in range(bounds.position.y + 1, bounds.end.y - 1):
		for x in range(bounds.position.x + 1, bounds.end.x - 1):
			var t := Vector2i(x, y)
			if layout.get_owner_of(t) == room.id and layout.is_clear(t):
				count += 1
	return count


## A terrain room whose only terrain was hazard sockets that all had to be
## refused (unsafe) keeps its place in the pacing as the closest safe role:
## HAZARD -> TRAVERSAL, HAZARD_COMBAT -> COMBAT (same fight weight). The
## validator still enforces the minimum terrain count per floor.
static func _downgrade_if_no_terrain(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> void:
	if not RoomRole.wants_terrain(room.tactic) or not room.hazards.is_empty() or not room.shape.is_clean():
		return
	room.tactic = RoomRole.COMBAT if room.tactic == RoomRole.HAZARD_COMBAT else RoomRole.TRAVERSAL
	room.encounter = RoomRole.encounter_for(room.tactic)
	layout.graph.spaces[room.id].tactic = room.tactic
	layout.graph.spaces[room.id].encounter = room.encounter


## True if the room's hazards leave it intact:
## (a) every connected hazard area fits RoomShape.MAX_TIMED_REGION (crossable
##     within one safe window of a timed trap);
## (b) the anchor, doorway insides and required sockets (reward, lore, event)
##     stay clear of hazards, so they are safe to stand on;
## (c) the anchor and every doorway connect through clear tiles when timed
##     hazards are crossable, and all walkable tiles are one piece.
static func hazard_keeps_room_intact(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> bool:
	var bounds := room.bounds()
	var hazard_tiles: Dictionary = {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if layout.get_tile(Vector2i(x, y)) == DungeonLayout.Tile.HAZARD:
				hazard_tiles[Vector2i(x, y)] = true
	for region: Array in RoomShape._group_regions(hazard_tiles):
		var region_box := RoomShape.region_bounds(region)
		if maxi(region_box.size.x, region_box.size.y) > RoomShape.MAX_TIMED_REGION:
			return false
	var must_be_clear: Array[Vector2i] = [room.anchor]
	for door in room.doors:
		must_be_clear.append(door.inside)
	for group: Array in [room.shape.reward_sockets, room.shape.lore_sockets, room.shape.event_sockets]:
		for local: Vector2i in group:
			must_be_clear.append(room.to_world(local))
	for t in must_be_clear:
		if not layout.is_clear(t):
			return false
	var seen: Dictionary = {room.anchor: true}
	var stack: Array[Vector2i] = [room.anchor]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in RoomShape.SIDE_VECTORS:
			var n := p + d
			if not seen.has(n) and bounds.has_point(n) and layout.is_clear(n, true):
				seen[n] = true
				stack.append(n)
	for door in room.doors:
		if not seen.has(door.center):
			return false
	var total := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var t := Vector2i(x, y)
			if layout.get_owner_of(t) == room.id and layout.is_walkable(t, true):
				total += 1
	var walkable: Dictionary = {room.anchor: true}
	stack = [room.anchor]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in RoomShape.SIDE_VECTORS:
			var n := p + d
			if not walkable.has(n) and layout.get_owner_of(n) == room.id and layout.is_walkable(n, true):
				walkable[n] = true
				stack.append(n)
	return walkable.size() == total


static func _place_spawn_candidates(layout: DungeonLayout, room: DungeonLayout.PlacedRoom,
		rng: RandomNumberGenerator) -> void:
	var candidates: Array = []
	for local in room.shape.enemy_spawns:
		var t := room.to_world(local)
		if layout.is_clear(t):
			candidates.append(t)
	SeedStreams.shuffle(candidates, rng)
	for t: Vector2i in candidates:
		room.spawn_candidates.append(t)


## Debug/design analysis of risk rooms: the shortest walk from any doorway to
## the cache avoiding the risk tiles (empty = the cache is guarded) and the
## shortest walk allowed to cross them.
static func _analyse_risk_routes(layout: DungeonLayout) -> void:
	var risk_room_found := false
	for room in layout.rooms:
		risk_room_found = risk_room_found or room.tactic == RoomRole.RISK_REWARD
	if not risk_room_found:
		return
	var route := DungeonValidator.clear_mask(layout, true)
	var required := DungeonValidator.required_mask(layout, route)
	for room in layout.rooms:
		if room.tactic != RoomRole.RISK_REWARD or not room.has_marker(&"cache"):
			continue
		var cache: Vector2i = room.markers[0].tile
		for marker in room.markers:
			if marker.kind == &"cache":
				cache = marker.tile
		var area := room.bounds()
		for door in room.doors:
			var safe := DungeonValidator.shortest_path(layout, required, door.center, cache, area)
			if not safe.is_empty() and (room.safe_route.is_empty() or safe.size() < room.safe_route.size()):
				room.safe_route = safe
			var risky := DungeonValidator.shortest_path(layout, route, door.center, cache, area)
			if not risky.is_empty() and (room.risk_route.is_empty() or risky.size() < room.risk_route.size()):
				room.risk_route = risky


## Reserved, validated spots where future tension/thriller events may happen
## (distant sounds, silhouettes, flickers, story beats...). Nothing uses them
## yet except one armed debug proof event per floor, placed in a quiet space
## (preferably the one right before a fight: uncertainty -> combat).
static func _place_event_sockets(layout: DungeonLayout, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	for room in layout.rooms:
		for local in room.shape.event_sockets:
			layout.event_sockets.append({"tile": room.to_world(local), "room": room.id, "link": -1,
				"kind": &"room", "armed": false})
	for corridor in layout.corridors:
		var middle := corridor.rects[1]
		layout.event_sockets.append({"tile": middle.position + middle.size / 2, "room": -1,
			"link": corridor.link, "kind": &"corridor", "armed": false})
	var quiet := [RoomRole.TRAVERSAL, RoomRole.TRANSITION, RoomRole.EXPLORATION, RoomRole.HAZARD, RoomRole.REWARD]
	var eligible: Array[int] = []
	var before_fight: Array[int] = []
	for i in layout.event_sockets.size():
		var socket: Dictionary = layout.event_sockets[i]
		var room := layout.room_for_space(socket.room)
		if room != null and not quiet.has(room.tactic):
			continue
		eligible.append(i)
		if _leads_into_fight(layout, socket):
			before_fight.append(i)
	for n in profile.armed_event_count:
		var pool := before_fight if not before_fight.is_empty() else eligible
		if pool.is_empty():
			break
		var chosen: int = pool[rng.randi_range(0, pool.size() - 1)]
		layout.event_sockets[chosen].armed = true
		eligible.erase(chosen)
		before_fight.erase(chosen)


## A socket in a main-path room whose next main-path room is a fight, or in a
## corridor that opens into a fight room.
static func _leads_into_fight(layout: DungeonLayout, socket: Dictionary) -> bool:
	if socket.room >= 0:
		var at := layout.graph.main_path.find(socket.room)
		if at < 0 or at + 1 >= layout.graph.main_path.size():
			return false
		return RoomRole.is_heavy(layout.rooms[layout.graph.main_path[at + 1]].tactic)
	var corridor := layout.corridors[socket.link]
	return RoomRole.is_heavy(layout.rooms[corridor.a].tactic) or RoomRole.is_heavy(layout.rooms[corridor.b].tactic)
