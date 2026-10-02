class_name TacticalComposer
extends RefCounted
## Encounter composition ("tactics" stream per room, Milestone 2.2).
## A fight is built from a RECIPE: which enemy roles, in which kind of room,
## and the decision that combination forces on the player. Recipes need room
## features (cover, pit, water, spikes, a narrow hall) and enemies the depth
## allows, so the composition reasons about the actual geometry:
##   pillar_skirmish  ranged pressure + pillars/walls   -> use cover
##   chasm_brawl      knockback threat + pit            -> mind your back
##   spike_bait       melee + spikes                    -> bait them onto spikes
##   wading_fight     melee + water                     -> fight from dry ground
##   choke_hold       body-blocker + narrow hall        -> don't get pinned
##   ambush_pincer    unlocked ambush                   -> funnel them in a doorway, or run
## Enemies are added (core first, then fill) while the room's ThreatModel
## score stays within its budget, the arena keeps enough maneuvering space and
## every doorway has enough far spawn points. SpawnPlanner must be able to
## place the enemies fairly from every doorway and, from the approach doorway,
## where the recipe needs them (the spitter across the chasm, the brute on the
## ledge...: SpawnPlanner.INTENTS); a recipe that only works on paper is
## skipped. Counts are never scaled up to
## make a depth harder: depth adds recipes, archetypes and interactions.

const RECIPES: Dictionary = {
	&"open_brawl": {"roles": ["COMBAT", "OBJECTIVE", "AMBUSH", "CHALLENGE"], "needs": [],
		"core": [&"chaser", &"chaser"], "fill": [&"chaser"], "specific": false,
		"note": "Several melee attackers: keep moving, don't get surrounded, strike while they recover."},
	&"pillar_skirmish": {"roles": ["COMBAT", "OBJECTIVE", "CHALLENGE"], "needs": ["cover"],
		"core": [&"spitter", &"chaser"], "fill": [&"chaser", &"spitter"], "specific": true,
		"note": "A spitter shoots from range: break its line of sight behind pillars, then close in."},
	&"choke_hold": {"roles": ["COMBAT", "OBJECTIVE"], "needs": ["narrow"],
		"core": [&"brute", &"chaser"], "fill": [&"chaser"], "specific": true,
		"note": "Narrow hall: the brute blocks the lane - don't get pinned against a wall."},
	&"chasm_brawl": {"roles": ["HAZARD_COMBAT"], "needs": ["pit"],
		"core": [&"brute", &"chaser"], "fill": [&"chaser"], "specific": true,
		"note": "The brute's blows throw you far: keep your back away from the chasm - knock them in instead."},
	&"ledge_fight": {"roles": ["HAZARD_COMBAT"], "needs": ["pit"],
		"core": [&"chaser", &"chaser"], "fill": [&"chaser"], "specific": true,
		"note": "Fighting beside a chasm: dodge along the edge, never toward it; your hits can knock them in."},
	&"spike_bait": {"roles": ["HAZARD_COMBAT"], "needs": ["spikes"],
		"core": [&"chaser", &"chaser"], "fill": [&"chaser"], "specific": true,
		"note": "Spikes hurt enemies too: fight beside them, not on them, and lure attackers across as they rise."},
	&"wading_fight": {"roles": ["HAZARD_COMBAT"], "needs": ["water"],
		"core": [&"chaser", &"chaser"], "fill": [&"chaser", &"brute"], "specific": true,
		"note": "Water slows everyone: hold dry ground and let them wade to you."},
	&"sniper_nest": {"roles": ["HAZARD_COMBAT"], "needs": ["pit_or_water"],
		"core": [&"spitter", &"chaser"], "fill": [&"spitter"], "specific": true,
		"note": "A spitter across difficult ground: cross between its shots, or fight the chaser first."},
	&"ambush_pincer": {"roles": ["AMBUSH"], "needs": [],
		"core": [&"chaser", &"chaser"], "fill": [&"chaser", &"spitter"], "specific": true,
		"note": "Ambush, doors open: back into a doorway so they come one at a time - or run."},
	&"elite_guard": {"roles": ["CHALLENGE"], "needs": [],
		"core": [&"brute", &"chaser"], "fill": [&"chaser", &"spitter"], "specific": true,
		"note": "Optional elite fight guarding a better reward: skip it if you are hurt."},
}

## Part of the budget a fight aims for (seeded per room), so not every fight
## sits exactly at the cap.
const MIN_BUDGET_USE := 0.75


## Fills room.enemy_ids and room.recipe. `budget` is the room's threat budget
## (already reduced to what is left of the floor budget).
static func compose(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, profile: DepthProfile,
		rng: RandomNumberGenerator, budget: float, f: ThreatModel.Features) -> void:
	var locked := ThreatModel.is_locked(room)
	var cap := capacity(layout, room, profile, f)
	var target := budget * rng.randf_range(MIN_BUDGET_USE, 1.0)
	for recipe_id in _ordered_recipes(room, profile, f, rng):
		var ids := _fill(layout, room, recipe_id, profile, f, locked, budget, target, cap)
		if not ids.is_empty():
			room.recipe = recipe_id
			room.enemy_ids = ids
			return
	# Nothing fits the budget/space: the smallest possible fight. The validator
	# still checks the result (and rejects it if it is over budget).
	room.recipe = &"open_brawl"
	var single: Array[StringName] = [profile.enemy_pool[0]]
	room.enemy_ids = single


## Enemy limit from the size class, the maneuvering space and the far spawn
## points behind every doorway.
static func capacity(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, profile: DepthProfile,
		f: ThreatModel.Features) -> int:
	var sizes := profile.enemies_by_size
	var cap := sizes[clampi(room.template.size_class, 0, sizes.size() - 1)] if not sizes.is_empty() else 1
	cap = mini(cap, ThreatModel.maneuver_capacity(f.clear_tiles))
	for door in room.doors:
		var inside := layout.tile_center(door.inside)
		var far := 0
		for t in room.spawn_candidates:
			if layout.tile_center(t).distance_to(inside) >= DungeonValidator.MIN_SPAWN_DISTANCE + DungeonValidator.SPAWN_CHECK_MARGIN:
				far += 1
		cap = mini(cap, far)
	return maxi(cap, 1)


static func is_applicable(recipe_id: StringName, room: DungeonLayout.PlacedRoom, profile: DepthProfile,
		f: ThreatModel.Features) -> bool:
	if not RECIPES.has(recipe_id) or not profile.tactical_recipes.has(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	if not (recipe.roles as Array).has(RoomRole.name_of(room.tactic)):
		return false
	for id: StringName in recipe.core:
		if not profile.enemy_pool.has(id):
			return false
	for need: String in recipe.needs:
		var ok := false
		match need:
			"cover":
				ok = f.cover
			"pit":
				ok = f.pit
			"water":
				ok = f.water
			"spikes":
				ok = f.spike_regions > 0
			"pit_or_water":
				ok = f.pit or f.water
			"narrow":
				ok = f.narrow
		if not ok:
			return false
	return true


## Applicable recipes in a seeded order. Recipes dedicated to the room's role
## (the ambush pincer for AMBUSH, the elite guard for CHALLENGE) come first;
## among the rest, recipes that use the room's features ("specific") are twice
## as likely to come first as open brawls. Later entries are fallbacks for
## when an earlier one does not fit the budget or space.
static func _ordered_recipes(room: DungeonLayout.PlacedRoom, profile: DepthProfile, f: ThreatModel.Features,
		rng: RandomNumberGenerator) -> Array[StringName]:
	var dedicated: Array[StringName] = []
	var pool: Array[StringName] = []
	var keys: Array = RECIPES.keys()
	keys.sort()
	for recipe_id: StringName in keys:
		if not is_applicable(recipe_id, room, profile, f):
			continue
		if (RECIPES[recipe_id].roles as Array).size() == 1:
			dedicated.append(recipe_id)
		else:
			pool.append(recipe_id)
	var ordered: Array[StringName] = []
	for group: Array[StringName] in [dedicated, pool]:
		var group_weights := PackedFloat32Array()
		for recipe_id in group:
			group_weights.append(2.0 if RECIPES[recipe_id].specific else 1.0)
		var remaining := group.duplicate()
		while not remaining.is_empty():
			var i := SeedStreams.weighted_index(group_weights, rng)
			ordered.append(remaining[i])
			remaining.remove_at(i)
			group_weights.remove_at(i)
	return ordered


static func _fill(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, recipe_id: StringName,
		profile: DepthProfile, f: ThreatModel.Features, locked: bool,
		budget: float, target: float, cap: int) -> Array[StringName]:
	var recipe: Dictionary = RECIPES[recipe_id]
	var ids: Array[StringName] = []
	for id: StringName in recipe.core:
		ids.append(id)
		if ids.size() > cap or ThreatModel.score(f, ids, locked) > budget:
			return []
	if not placement_ok(layout, room, recipe_id, ids, f):
		return []
	var fill: Array[StringName] = []
	for id: StringName in recipe.fill:
		if profile.enemy_pool.has(id):
			fill.append(id)
	var i := 0
	while not fill.is_empty() and ids.size() < cap:
		var next := fill[i % fill.size()]
		ids.append(next)
		if ThreatModel.score(f, ids, locked) > target or not placement_ok(layout, room, recipe_id, ids, f):
			ids.pop_back()
			break
		i += 1
	return ids


## SpawnPlanner can place `ids` fairly from every doorway, with no ranged
## crossfire in a room without cover, and the recipe's tactic is realized from
## the approach doorway. (The room's recipe and enemies are set only while
## checking, since the planner reads them from the room.)
static func placement_ok(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, recipe_id: StringName,
		ids: Array[StringName], f: ThreatModel.Features) -> bool:
	if not f.cover and SpawnPlanner.ranged_count(ids) > SpawnPlanner.MAX_RANGED_WITHOUT_COVER:
		return false
	var saved_recipe := room.recipe
	var saved_ids := room.enemy_ids
	room.recipe = recipe_id
	room.enemy_ids = ids
	var ok := true
	for door in room.doors:
		var from := SpawnPlanner.entry_point(layout, door)
		if SpawnPlanner.unfair_reason(layout, room, from, SpawnPlanner.plan(layout, room, from)) != "":
			ok = false
			break
	if ok:
		var approach := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, room))
		ok = SpawnPlanner.realizes(layout, room, approach, SpawnPlanner.plan(layout, room, approach))
	room.recipe = saved_recipe
	room.enemy_ids = saved_ids
	return ok


## The decision a room asks of the player (debug overlay, debug map).
static func design_note(room: DungeonLayout.PlacedRoom, f: ThreatModel.Features) -> String:
	if room.recipe != &"" and RECIPES.has(room.recipe):
		return RECIPES[room.recipe].note
	match room.tactic:
		RoomRole.ENTRY:
			return "Safe start: no hazards, no enemies."
		RoomRole.OBJECTIVE:
			return "The way down."
		RoomRole.STORY:
			return "Story chamber (reserved)."
		RoomRole.TRANSITION:
			return "Crossroads: choose which way to push."
		RoomRole.EXPLORATION:
			return "Look around: something here tells the dungeon's story."
		RoomRole.REWARD:
			return "Optional reward, worth the detour."
		RoomRole.REST:
			return "Recovery shrine: heal before pushing on."
		RoomRole.RISK_REWARD:
			return "A cache behind a visible risk: take the safe way round, or time the spikes for the prize."
		RoomRole.HAZARD:
			if f.spike_regions > 0:
				return "Timed spikes: watch the warning bar and cross in the safe window."
			if f.pit:
				return "Chasm: cross on the bridge, don't cut the corners."
			if f.water:
				return "Flooded floor: plan a route through the slow water."
	return "Quiet passage: catch your breath."
