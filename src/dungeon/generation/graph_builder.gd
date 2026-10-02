class_name GraphBuilder
extends RefCounted
## Stage 1: builds the DungeonGraph on a macro grid from the "graph" stream.
##  1. Main path: self-avoiding random walk (turns favoured by turn_bias),
##     entry at the start, objective at the end, a minimum entry/exit distance.
##  2. Special rooms: reserved at a fraction of the main path.
##  3. Branches: short walks off the main path (sometimes off other branches);
##     their tips become dead ends.
##  4. Loops: a few extra links between adjacent spaces (never touching the
##     entry, objective or special rooms), giving alternative routes.
## On failure the returned graph has `error` set; the generator retries.


static func build(profile: DepthProfile, rng: RandomNumberGenerator) -> DungeonGraph:
	var graph := DungeonGraph.new()
	graph.grid_size = Vector2i(profile.grid_columns, profile.grid_rows)
	if not _build_main_path(graph, profile, rng):
		return graph
	if not _insert_special_rooms(graph, profile):
		return graph
	_add_branches(graph, profile, rng)
	_add_loops(graph, profile, rng)
	_refresh_dead_ends(graph)
	return graph


static func _build_main_path(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> bool:
	var length := rng.randi_range(profile.main_path_min, profile.main_path_max)
	if length < 3:
		graph.error = "main path shorter than 3"
		return false
	var cells: Array[Vector2i] = [Vector2i(rng.randi_range(0, graph.grid_size.x - 1), rng.randi_range(0, graph.grid_size.y - 1))]
	var visited: Dictionary = {cells[0]: true}
	var heading := Vector2i.ZERO
	while cells.size() < length:
		var current: Vector2i = cells.back()
		var options: Array[Vector2i] = []
		var weights := PackedFloat32Array()
		for d in DungeonGraph.DIRECTIONS:
			var next := current + d
			if not graph.in_bounds(next) or visited.has(next):
				continue
			var weight := 1.0 if (heading == Vector2i.ZERO or d == heading) else profile.turn_bias
			if _manhattan(next, cells[0]) > _manhattan(current, cells[0]):
				weight *= profile.outward_bias
			# Avoid walking into a pocket before the path is long enough.
			if cells.size() < length - 1 and _free_count(graph, next, visited) == 0:
				weight *= 0.05
			options.append(next)
			weights.append(weight)
		if options.is_empty():
			graph.error = "main path walk got stuck at length %d" % cells.size()
			return false
		var pick := options[SeedStreams.weighted_index(weights, rng)]
		heading = pick - current
		visited[pick] = true
		cells.append(pick)
	var start := cells[0]
	var end := cells.back() as Vector2i
	if absi(end.x - start.x) + absi(end.y - start.y) < profile.min_entry_exit_distance:
		graph.error = "entry and objective too close"
		return false
	for i in cells.size():
		var role := DungeonGraph.Role.MAIN
		if i == 0:
			role = DungeonGraph.Role.ENTRY
		elif i == cells.size() - 1:
			role = DungeonGraph.Role.OBJECTIVE
		var space := graph.add_space(cells[i], role)
		space.main_index = i
		graph.main_path.append(space.id)
		if i > 0:
			graph.connect_spaces(graph.main_path[i - 1], space.id, DungeonGraph.LinkKind.MAIN)
	return true


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _free_count(graph: DungeonGraph, cell: Vector2i, visited: Dictionary) -> int:
	var count := 0
	for d in DungeonGraph.DIRECTIONS:
		if graph.in_bounds(cell + d) and not visited.has(cell + d):
			count += 1
	return count


static func _insert_special_rooms(graph: DungeonGraph, profile: DepthProfile) -> bool:
	var length := graph.main_path.size()
	for rule in profile.special_rooms:
		if rule == null or rule.template == null:
			continue
		var index := clampi(roundi(rule.main_path_fraction * (length - 1)), 1, length - 2)
		# Walk forward to the next free main-path slot if another special took it.
		while index < length - 1 and graph.spaces[graph.main_path[index]].role != DungeonGraph.Role.MAIN:
			index += 1
		if index >= length - 1:
			if rule.required:
				graph.error = "no main-path slot for special room '%s'" % rule.id
				return false
			continue
		var space := graph.spaces[graph.main_path[index]]
		space.role = DungeonGraph.Role.SPECIAL
		space.special_rule = rule
	return true


static func _add_branches(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(profile.branch_min, profile.branch_max)
	for b in count:
		var from_branch := rng.randf() < profile.sub_branch_chance
		var anchors := _branch_anchors(graph, from_branch)
		if anchors.is_empty():
			anchors = _branch_anchors(graph, not from_branch)
		if anchors.is_empty():
			return
		var current := anchors[rng.randi_range(0, anchors.size() - 1)]
		var length := rng.randi_range(profile.branch_length_min, profile.branch_length_max)
		for step in length:
			var options := graph.free_neighbors(graph.spaces[current].cell)
			if options.is_empty():
				break
			var next := graph.add_space(options[rng.randi_range(0, options.size() - 1)], DungeonGraph.Role.BRANCH)
			graph.connect_spaces(current, next.id, DungeonGraph.LinkKind.BRANCH)
			current = next.id


static func _branch_anchors(graph: DungeonGraph, from_branch: bool) -> Array[int]:
	var result: Array[int] = []
	for space in graph.spaces:
		var eligible: bool
		if from_branch:
			eligible = space.role == DungeonGraph.Role.BRANCH or space.role == DungeonGraph.Role.DEAD_END
		else:
			eligible = space.role == DungeonGraph.Role.MAIN or space.role == DungeonGraph.Role.ENTRY
		if eligible and not graph.free_neighbors(space.cell).is_empty():
			result.append(space.id)
	return result


static func _add_loops(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	var candidates: Array = []
	for space in graph.spaces:
		if not _loop_eligible(space):
			continue
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other := graph.space_at(space.cell + d)
			if other != null and _loop_eligible(other) and not graph.are_linked(space.id, other.id):
				candidates.append([space.id, other.id])
	SeedStreams.shuffle(candidates, rng)
	var added := 0
	for pair: Array in candidates:
		if added >= profile.max_loops:
			break
		if rng.randf() < profile.loop_chance:
			graph.connect_spaces(pair[0], pair[1], DungeonGraph.LinkKind.LOOP)
			added += 1


static func _loop_eligible(space: DungeonGraph.Space) -> bool:
	return space.role == DungeonGraph.Role.MAIN or space.role == DungeonGraph.Role.BRANCH \
		or space.role == DungeonGraph.Role.DEAD_END


static func _refresh_dead_ends(graph: DungeonGraph) -> void:
	for space in graph.spaces:
		if space.role == DungeonGraph.Role.BRANCH and graph.degree(space.id) == 1:
			space.role = DungeonGraph.Role.DEAD_END
		elif space.role == DungeonGraph.Role.DEAD_END and graph.degree(space.id) > 1:
			space.role = DungeonGraph.Role.BRANCH
