extends RefCounted
## Conservative XZ separation: stacked overlapping rooms are intentionally rejected.

static func validate(layout: AbyssSpatialLayout) -> PackedStringArray:
	var errors := PackedStringArray()
	if layout == null or layout.graph == null or not layout.graph.error.is_empty():
		return PackedStringArray(["missing/failed graph"])
	var graph := layout.graph
	if layout.rooms.size() != graph.spaces.size() or layout.rooms.size() < 3 or layout.rooms.size() > 64 \
			or graph.entry_id() < 0 or graph.objective_id() < 0 \
			or graph.entry_id() >= layout.rooms.size() or graph.objective_id() >= layout.rooms.size():
		return PackedStringArray(["invalid room/entry/exit count"])
	if layout.connections.size() != graph.links.size():
		errors.append("graph links and spatial connections differ")
	for i in layout.rooms.size():
		var room := layout.rooms[i]
		if room.id != i or not room.center.is_finite() or not room.size.is_finite() \
				or room.size.x < 8 or room.size.y < 8 or room.size.x > 24 or room.size.y > 24:
			return PackedStringArray(["invalid room bounds"])
		for j in i:
			if room.footprint().grow(0.2).intersects(layout.rooms[j].footprint().grow(0.2)):
				errors.append("room overlap")
	var adjacency: Array[Array] = []
	for room in layout.rooms:
		adjacency.append([])
	var sides: Dictionary = {}
	for i in layout.connections.size():
		var link := layout.connections[i]
		if link.id != i or link.a < 0 or link.b < 0 or link.a >= layout.rooms.size() \
				or link.b >= layout.rooms.size() or link.a == link.b or not link.start.is_finite() \
				or not link.end.is_finite() or not is_finite(link.width) or link.width < 3 or link.width > 4:
			return PackedStringArray(["invalid connection data"])
		if i >= graph.links.size() or graph.links[i].a != link.a or graph.links[i].b != link.b:
			errors.append("connection identity differs from graph")
		var delta := link.end - link.start
		var run := Vector2(delta.x, delta.z).length()
		if run < 2 or (absf(delta.x) > 0.001 and absf(delta.z) > 0.001) or absf(delta.y) > run * 0.35:
			errors.append("invalid connection alignment/slope")
		var direction := link.direction()
		if not layout.rooms[link.a].socket(direction).is_equal_approx(link.start) \
				or not layout.rooms[link.b].socket(-direction).is_equal_approx(link.end):
			errors.append("connection does not meet room sockets")
		for pair in [[link.a, direction], [link.b, -direction]]:
			var key := str(pair)
			if sides.has(key):
				errors.append("duplicate doorway")
			sides[key] = true
		for room in layout.rooms:
			if room.id != link.a and room.id != link.b and link.footprint().intersects(room.footprint().grow(0.2)):
				errors.append("connection intersects unrelated room")
		for j in i:
			var other := layout.connections[j]
			if other.a != link.a and other.a != link.b and other.b != link.a and other.b != link.b \
					and link.footprint().intersects(other.footprint()):
				errors.append("connection crossing")
		adjacency[link.a].append(link.b)
		adjacency[link.b].append(link.a)
	var visited := {graph.entry_id(): true}
	var pending: Array[int] = [graph.entry_id()]
	while not pending.is_empty():
		var current: int = pending.pop_back()
		for next: int in adjacency[current]:
			if not visited.has(next):
				visited[next] = true
				pending.append(next)
	if visited.size() != layout.rooms.size() or not visited.has(graph.objective_id()):
		errors.append("entry cannot reach every room and exit")
	for pair in [[layout.spawn, graph.entry_id()], [layout.exit, graph.objective_id()]]:
		var point: Vector3 = pair[0]
		var room := layout.rooms[pair[1]]
		if not point.is_finite() or not room.footprint().grow(-1).has_point(Vector2(point.x, point.z)) \
				or absf(point.y - room.center.y) > 0.01:
			errors.append("unsafe spawn/exit")
	return errors
