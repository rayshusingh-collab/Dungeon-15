class_name PacingDirector
extends RefCounted
## Stage 2 ("pacing" stream): gives every space a RoomRole before templates
## are chosen. Replaces the Milestone 2 EncounterPlanner.
##
## Main path (entry -> objective), in order, like a director reading the room
## sequence so far:
##   - never more than max_consecutive_combat heavy rooms (fights) in a row
##   - never more than max_consecutive_terrain terrain challenges in a row
##   - never the same role three times in a row
##   - REST only right after a heavy room (and max_rest_rooms per floor)
##   - after two quiet rooms, a fight becomes more likely (tension -> release)
##   - peaceful 3+ link spaces may become TRANSITION rooms (junctions)
##   - topped up to min_combat_rooms with spaces that keep the rhythm (the
##     validator rejects floors that still fall short; they are regenerated)
## Branches read their neighbours: a room next to a fight is unlikely to be
## another fight. Dead ends always get a purpose (reward, lore, secret, risk
## cache, optional challenge or recovery).
## Weights come from the depth profile; a role with no weight never appears,
## which is how depths unlock mechanics.

const DEAD_END_KEYS := ["reward", "exploration", "secret", "challenge", "risk_reward", "rest"]


static func direct(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	for space in graph.spaces:
		match space.role:
			DungeonGraph.Role.ENTRY:
				space.tactic = RoomRole.ENTRY
			DungeonGraph.Role.OBJECTIVE:
				space.tactic = RoomRole.OBJECTIVE
			DungeonGraph.Role.SPECIAL:
				space.tactic = RoomRole.STORY
	_direct_main_path(graph, profile, rng)
	_ensure_min_combat(graph, profile, rng)
	_ensure_min_terrain(graph, profile, rng)
	for space in graph.spaces:
		if space.role == DungeonGraph.Role.BRANCH or space.role == DungeonGraph.Role.DEAD_END:
			_direct_branch_space(graph, space, profile, rng)
	apply_encounters(graph, profile)


## Encounter kind follows the role; the objective fight is a profile rule.
static func apply_encounters(graph: DungeonGraph, profile: DepthProfile) -> void:
	for space in graph.spaces:
		space.encounter = RoomRole.encounter_for(space.tactic)
	if profile.objective_encounter:
		graph.spaces[graph.objective_id()].encounter = DungeonGraph.Encounter.COMBAT


## Main-path roles in order (entry first), as the director saw them.
static func main_path_roles(graph: DungeonGraph) -> Array[int]:
	var roles: Array[int] = []
	for id in graph.main_path:
		roles.append(graph.spaces[id].tactic)
	return roles


static func heavy_count(graph: DungeonGraph) -> int:
	var count := 0
	for id in graph.main_path:
		if RoomRole.is_heavy(graph.spaces[id].tactic):
			count += 1
	return count


static func rest_count(graph: DungeonGraph) -> int:
	var count := 0
	for space in graph.spaces:
		if space.tactic == RoomRole.REST:
			count += 1
	return count


static func _direct_main_path(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	var recent: Array[int] = [RoomRole.ENTRY]
	for i in range(1, graph.main_path.size() - 1):
		var space := graph.spaces[graph.main_path[i]]
		if space.role == DungeonGraph.Role.MAIN:
			var transitions_repeated := recent.size() >= 2 and recent[-1] == RoomRole.TRANSITION \
				and recent[-2] == RoomRole.TRANSITION
			if graph.degree(space.id) >= 3 and not transitions_repeated and rng.randf() < profile.junction_chance:
				_assign(space, "transition")
			else:
				# Right before an objective fight, one less fight fits in the run.
				var before_final_fight := i == graph.main_path.size() - 2 and profile.objective_encounter
				var weights := _weights(profile.main_role_weights, graph, space, profile, recent, false,
					1 if before_final_fight else 0)
				_assign(space, _pick(weights, rng, "traversal"))
		recent.append(space.tactic)


static func _direct_branch_space(graph: DungeonGraph, space: DungeonGraph.Space, profile: DepthProfile,
		rng: RandomNumberGenerator) -> void:
	var dead_end := space.role == DungeonGraph.Role.DEAD_END
	if not dead_end and graph.degree(space.id) >= 3 and rng.randf() < profile.junction_chance:
		_assign(space, "transition")
		return
	var table := profile.dead_end_role_weights if dead_end else profile.branch_role_weights
	var weights := _weights(table, graph, space, profile, [], dead_end)
	_assign(space, _pick(weights, rng, "reward" if dead_end else "traversal"))


## Candidate weights after the pacing rules. `recent` is the main-path role
## sequence so far (empty for branch spaces, which read their neighbours).
static func _weights(table: Dictionary, graph: DungeonGraph, space: DungeonGraph.Space, profile: DepthProfile,
		recent: Array[int], dead_end: bool, fights_after: int = 0) -> Dictionary:
	var heavy_run := _trailing(recent, 0) + fights_after
	var terrain_run := _trailing(recent, 1)
	var quiet_run := _trailing(recent, 2)
	var last: int = recent.back() if not recent.is_empty() else -1
	var repeated := recent.size() >= 2 and recent[-1] == recent[-2]
	var neighbour_heavy := false
	var neighbour_rest := false
	for link_id in space.link_ids:
		var other := graph.spaces[graph.other_end(graph.links[link_id], space.id)]
		neighbour_heavy = neighbour_heavy or RoomRole.is_heavy(other.tactic)
		neighbour_rest = neighbour_rest or other.tactic == RoomRole.REST
	var rests := rest_count(graph)
	var result := {}
	var keys: Array = table.keys()
	keys.sort()
	for key: String in keys:
		var w := float(table[key])
		if w <= 0.0 or not RoomRole.KEYS.has(key):
			continue
		if dead_end and not DEAD_END_KEYS.has(key):
			continue
		var role: int = RoomRole.KEYS[key]
		if RoomRole.is_heavy(role) and heavy_run >= profile.max_consecutive_combat:
			continue
		if RoomRole.is_terrain_challenge(role) and terrain_run >= profile.max_consecutive_terrain:
			continue
		if repeated and role == last:
			continue
		if role == RoomRole.AMBUSH and graph.degree(space.id) < 2:
			continue  # an ambush always leaves another way out
		if role == RoomRole.REST:
			if rests >= profile.max_rest_rooms or neighbour_rest:
				continue
			if not recent.is_empty() and not RoomRole.is_heavy(last):
				continue  # recovery follows a fight
			if recent.is_empty() and not neighbour_heavy:
				continue
		if RoomRole.is_heavy(role):
			if quiet_run >= 2:
				w *= 2.0  # tension -> release: something happens after a lull
			if recent.is_empty() and neighbour_heavy:
				w *= 0.25  # side rooms next to a fight rarely fight too
		result[key] = w
	return result


## Length of the trailing run in `roles`: mode 0 heavy, 1 terrain, 2 quiet.
static func _trailing(roles: Array[int], mode: int) -> int:
	var count := 0
	for i in range(roles.size() - 1, -1, -1):
		var role := roles[i]
		var hit := RoomRole.is_heavy(role) if mode == 0 \
			else (RoomRole.is_terrain_challenge(role) if mode == 1 else not RoomRole.is_heavy(role))
		if not hit:
			break
		count += 1
	return count


static func _pick(weights: Dictionary, rng: RandomNumberGenerator, fallback: String) -> String:
	if weights.is_empty():
		return fallback
	var keys: Array = weights.keys()
	var values := PackedFloat32Array()
	for key: String in keys:
		values.append(weights[key])
	var index := SeedStreams.weighted_index(values, rng)
	return keys[index] if index >= 0 else fallback


static func _assign(space: DungeonGraph.Space, key: String) -> void:
	space.purpose = DungeonGraph.Purpose.NONE
	match key:
		"transition":
			space.tactic = RoomRole.TRANSITION
		"secret":
			space.tactic = RoomRole.EXPLORATION
			space.purpose = DungeonGraph.Purpose.SECRET
		"exploration":
			space.tactic = RoomRole.EXPLORATION
			space.purpose = DungeonGraph.Purpose.LORE
		"reward", "risk_reward":
			space.tactic = RoomRole.KEYS[key]
			space.purpose = DungeonGraph.Purpose.REWARD
		"challenge":
			space.tactic = RoomRole.CHALLENGE
			space.purpose = DungeonGraph.Purpose.OPTIONAL_COMBAT
		"rest":
			space.tactic = RoomRole.REST
			space.purpose = DungeonGraph.Purpose.RECOVERY
		_:
			space.tactic = RoomRole.KEYS.get(key, RoomRole.TRAVERSAL)


static func _ensure_min_combat(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	var heavy := heavy_count(graph)
	if heavy >= profile.min_combat_rooms:
		return
	var eligible: Array = []
	for id in graph.main_path:
		var space := graph.spaces[id]
		if space.role == DungeonGraph.Role.MAIN and not RoomRole.is_heavy(space.tactic) and space.tactic != RoomRole.REST:
			eligible.append(id)
	SeedStreams.shuffle(eligible, rng)
	# Only spaces that keep the rhythm. If the minimum still is not met the
	# validator rejects the floor and the next attempt tries another layout:
	# pacing is never broken to reach a quota.
	for id: int in eligible:
		if heavy >= profile.min_combat_rooms:
			return
		if _heavy_run_with(graph, id, profile) > profile.max_consecutive_combat:
			continue
		_assign(graph.spaces[id], "combat")
		heavy += 1


static func terrain_count(graph: DungeonGraph) -> int:
	var count := 0
	for id in graph.main_path:
		if RoomRole.is_terrain_challenge(graph.spaces[id].tactic):
			count += 1
	return count


## Every floor teaches terrain: quiet main-path spaces become HAZARD rooms
## until min_terrain_rooms is met, keeping the terrain rhythm and never
## repeating a role three times. Short floors are rejected by the validator.
static func _ensure_min_terrain(graph: DungeonGraph, profile: DepthProfile, rng: RandomNumberGenerator) -> void:
	var terrain := terrain_count(graph)
	if terrain >= profile.min_terrain_rooms or float(profile.main_role_weights.get("hazard", 0.0)) <= 0.0:
		return
	var eligible: Array = []
	for id in graph.main_path:
		var space := graph.spaces[id]
		if space.role == DungeonGraph.Role.MAIN and (space.tactic == RoomRole.TRAVERSAL
				or space.tactic == RoomRole.EXPLORATION or space.tactic == RoomRole.TRANSITION):
			eligible.append(id)
	SeedStreams.shuffle(eligible, rng)
	var path := graph.main_path
	for id: int in eligible:
		if terrain >= profile.min_terrain_rooms:
			return
		var at := path.find(id)
		var run := 1
		for step: int in [-1, 1]:
			var i := at + step
			while i >= 0 and i < path.size() and RoomRole.is_terrain_challenge(graph.spaces[path[i]].tactic):
				run += 1
				i += step
		if run > profile.max_consecutive_terrain:
			continue
		var before := graph.spaces[path[at - 1]].tactic if at >= 1 else -1
		var after := graph.spaces[path[at + 1]].tactic if at + 1 < path.size() else -1
		if before == RoomRole.HAZARD and after == RoomRole.HAZARD:
			continue
		_assign(graph.spaces[id], "hazard")
		terrain += 1


## Length of the main-path heavy run through `id` if it became a fight (an
## objective fight counts like any other fight).
static func _heavy_run_with(graph: DungeonGraph, id: int, profile: DepthProfile) -> int:
	var path := graph.main_path
	var at := path.find(id)
	var run := 1
	for step: int in [-1, 1]:
		var i := at + step
		while i >= 0 and i < path.size() and _is_fight(graph, path[i], profile):
			run += 1
			i += step
	return run


static func _is_fight(graph: DungeonGraph, id: int, profile: DepthProfile) -> bool:
	if id == graph.objective_id():
		return profile.objective_encounter
	return RoomRole.is_heavy(graph.spaces[id].tactic)
