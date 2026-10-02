class_name SpawnPlanner
extends RefCounted
## Where each enemy of an encounter appears (Milestone 2.2). A recipe's tactic
## only exists in play if its enemies start where the geometry matters, so
## recipes give some enemies a placement INTENT, judged from where the player
## triggers the fight:
##   across    the straight line to the player crosses a pit or water, with
##             nothing solid in between (it has a clear shot)
##             (sniper_nest: the spitter shoots over ground you can't rush)
##   screened  a pillar or wall breaks its line of sight to the player
##             (pillar_skirmish: you enter in cover and choose how to approach)
##   ledge     within LEDGE_REACH tiles of a pit (chasm_brawl, ledge_fight)
##   wade      it has to cross water to reach the player (wading_fight)
##   bait      it has to cross spikes to reach the player (spike_bait)
## Fairness: every enemy starts at least MIN_SPAWN_DISTANCE
## from the player, a ranged enemy at least RANGED_MIN_DISTANCE (time to see
## the telegraph and find cover), and a room without cover holds at most
## MAX_RANGED_WITHOUT_COVER ranged enemies (no unavoidable crossfire).
## A pure function of the room data and the trigger point: generation
## (composer, validator, tests) and runtime (DungeonRoom) use the same plan.
## (This script owns its data and references neither TacticalComposer nor
## DungeonValidator: a reference cycle trips the `--check-only` leak quirk.)

## Enemies never appear closer than this to the player when an encounter starts.
const MIN_SPAWN_DISTANCE := 150.0
const RANGED_MIN_DISTANCE := 224.0
const MAX_RANGED_WITHOUT_COVER := 1
## Chebyshev distance (tiles) from a pit that counts as "on the ledge".
const LEDGE_REACH := 3
## Sample spacing (px) when testing what lies between two points; runtime
## sight (DungeonNavigation.clear_sight) uses the same test.
const SIGHT_STEP := 8.0
const NONE := Vector2i(-1, -1)

## Tile kinds that block sight and shots / that make a crossing difficult.
const SOLID_MASK := (1 << DungeonLayout.Tile.WALL) | (1 << DungeonLayout.Tile.OBSTACLE) \
	| (1 << DungeonLayout.Tile.INNER_WALL) | (1 << DungeonLayout.Tile.RUBBLE)
const PIT_OR_WATER_MASK := (1 << DungeonLayout.Tile.PIT) | (1 << DungeonLayout.Tile.WATER)
const WATER_MASK := 1 << DungeonLayout.Tile.WATER
const SPIKES_MASK := 1 << DungeonLayout.Tile.HAZARD

const INTENT_ACROSS := &"across"
const INTENT_SCREENED := &"screened"
const INTENT_LEDGE := &"ledge"
const INTENT_WADE := &"wade"
const INTENT_BAIT := &"bait"

## Recipe (TacticalComposer.RECIPES key) -> {enemy id: intent} for its lead
## enemy of that type. Recipes not listed place everyone wherever is fair.
const INTENTS := {
	&"pillar_skirmish": {&"spitter": INTENT_SCREENED},
	&"sniper_nest": {&"spitter": INTENT_ACROSS},
	&"chasm_brawl": {&"brute": INTENT_LEDGE},
	&"ledge_fight": {&"chaser": INTENT_LEDGE},
	&"wading_fight": {&"chaser": INTENT_WADE},
	&"spike_bait": {&"chaser": INTENT_BAIT},
}


## Where the player stands when entering through `door` triggers the room
## (the encounter trigger is inset from the walls).
static func entry_point(layout: DungeonLayout, door: Dictionary) -> Vector2:
	return layout.tile_center(door.inside - RoomShape.SIDE_VECTORS[door.side] * 2)


## Placement intent of an enemy in a recipe (&"" = anywhere fair).
static func intent_of(recipe_id: StringName, enemy_id: StringName) -> StringName:
	var place: Dictionary = INTENTS.get(recipe_id, {})
	return place.get(enemy_id, &"")


## Intent of the enemy at index `i`: only the recipe's lead enemy of each type
## (its first occurrence) carries it; the others fill in wherever is fair.
static func intent_at(room: DungeonLayout.PlacedRoom, i: int) -> StringName:
	if room.enemy_ids.find(room.enemy_ids[i]) != i:
		return &""
	return intent_of(room.recipe, room.enemy_ids[i])


## Spawn tile per enemy (index = room.enemy_ids index), seen from `from`.
## Enemies with an intent pick first, from the seeded candidate order; the
## rest take the next fair candidates. If too few candidates are far enough
## (validation prevents this), the farthest remaining ones are used.
static func plan(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, from: Vector2) -> Array[Vector2i]:
	var ids := room.enemy_ids
	var result: Array[Vector2i] = []
	result.resize(ids.size())
	result.fill(NONE)
	var taken: Dictionary = {}
	for i in ids.size():
		var intent := intent_at(room, i)
		if intent == &"":
			continue
		for t in room.spawn_candidates:
			if not taken.has(t) and distance_ok(layout, ids[i], t, from) and satisfies(layout, intent, t, from):
				result[i] = t
				taken[t] = true
				break
	for strict_distance: bool in [true, false]:
		for i in ids.size():
			if result[i] != NONE:
				continue
			for t in room.spawn_candidates:
				if taken.has(t):
					continue
				var far := layout.tile_center(t).distance_to(from) >= MIN_SPAWN_DISTANCE
				if (strict_distance and distance_ok(layout, ids[i], t, from)) or (not strict_distance and far):
					result[i] = t
					taken[t] = true
					break
	for i in ids.size():
		if result[i] != NONE:
			continue
		var farthest := -1.0
		for t in room.spawn_candidates:
			var d := layout.tile_center(t).distance_to(from)
			if not taken.has(t) and d > farthest:
				farthest = d
				result[i] = t
		if result[i] != NONE:
			taken[result[i]] = true
	return result


static func distance_ok(layout: DungeonLayout, enemy_id: StringName, t: Vector2i, from: Vector2) -> bool:
	var d := layout.tile_center(t).distance_to(from)
	if EnemyCatalog.has_tag(enemy_id, &"ranged"):
		return d >= RANGED_MIN_DISTANCE
	return d >= MIN_SPAWN_DISTANCE


static func satisfies(layout: DungeonLayout, intent: StringName, t: Vector2i, from: Vector2) -> bool:
	match intent:
		INTENT_ACROSS:
			return layout.segment_hits(from, layout.tile_center(t), PIT_OR_WATER_MASK, SIGHT_STEP) \
				and not layout.segment_hits(from, layout.tile_center(t), SOLID_MASK, SIGHT_STEP)
		INTENT_SCREENED:
			return layout.segment_hits(from, layout.tile_center(t), SOLID_MASK, SIGHT_STEP)
		INTENT_WADE:
			return layout.segment_hits(from, layout.tile_center(t), WATER_MASK, SIGHT_STEP)
		INTENT_BAIT:
			return layout.segment_hits(from, layout.tile_center(t), SPIKES_MASK, SIGHT_STEP)
		INTENT_LEDGE:
			for dy in range(-LEDGE_REACH, LEDGE_REACH + 1):
				for dx in range(-LEDGE_REACH, LEDGE_REACH + 1):
					if layout.get_tile(t + Vector2i(dx, dy)) == DungeonLayout.Tile.PIT:
						return true
			return false
	return true


## The recipe's tactic exists from `from`: every enemy with an intent got a
## tile that satisfies it. Rooms whose recipe has no intents always realize it.
static func realizes(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, from: Vector2,
		tiles: Array[Vector2i]) -> bool:
	for i in room.enemy_ids.size():
		var intent := intent_at(room, i)
		if intent != &"" and (i >= tiles.size() or tiles[i] == NONE or not satisfies(layout, intent, tiles[i], from)):
			return false
	return true


## Fairness of a plan from `from`; returns the first problem or "".
static func unfair_reason(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, from: Vector2,
		tiles: Array[Vector2i]) -> String:
	for i in room.enemy_ids.size():
		if i >= tiles.size() or tiles[i] == NONE:
			return "no spawn point for enemy %d" % i
		var d := layout.tile_center(tiles[i]).distance_to(from)
		if d < MIN_SPAWN_DISTANCE:
			return "%s appears %d px from the player" % [room.enemy_ids[i], d]
		if EnemyCatalog.has_tag(room.enemy_ids[i], &"ranged") and d < RANGED_MIN_DISTANCE:
			return "ranged %s starts %d px from the player (unavoidable shot)" % [room.enemy_ids[i], d]
	return ""


static func ranged_count(enemy_ids: Array[StringName]) -> int:
	var n := 0
	for id in enemy_ids:
		if EnemyCatalog.has_tag(id, &"ranged"):
			n += 1
	return n


## The doorway a player normally arrives through: the one whose link leads
## toward the entry (fewest rooms from the entry; ties by link id).
static func approach_door(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> Dictionary:
	var graph := layout.graph
	var dist: Dictionary = {graph.entry_id(): 0}
	var queue: Array[int] = [graph.entry_id()]
	while not queue.is_empty():
		var id: int = queue.pop_front()
		for link_id in graph.spaces[id].link_ids:
			var other := graph.other_end(graph.links[link_id], id)
			if not dist.has(other):
				dist[other] = dist[id] + 1
				queue.append(other)
	var best: Dictionary = {}
	var best_key := Vector2i(1 << 30, 1 << 30)
	for door in room.doors:
		var other := graph.other_end(graph.links[door.link], room.id)
		var key := Vector2i(dist.get(other, 1 << 29), door.link)
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = door
	return best

