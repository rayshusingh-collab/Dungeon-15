extends "res://tools/test_harness.gd"
## Procedural-generation stress suite: hundreds of floors per depth,
## determinism (layout and tactical data), golden seeds, validator negatives
## (geometry and tactical fairness), retry handling, physical traversal of
## built worlds, runtime spawn validity, pacing/threat/role statistics, depth
## progression and performance.
## Run: godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd

const TEMPLATE_DIR := "res://data/rooms"
## `-- --quick` (user arg) runs a smaller sample, used for mutation testing.
var quick := OS.get_cmdline_user_args().has("--quick")
var stress_seeds_depth_1 := 150 if quick else 800
var stress_seeds_depth_2 := 80 if quick else 400
var stress_seeds_depth_3 := 60 if quick else 300
const DETERMINISM_SEEDS := 150
const VARIATION_SEEDS := 300
var traversal_seeds_depth_1 := 8 if quick else 30
var traversal_seeds_depth_2 := 3 if quick else 10
var traversal_seeds_depth_3 := 3 if quick else 10

## Pinned output of the current generator version. If these change without a GENERATOR_VERSION
## bump, existing shared seeds silently changed: bump the version and update.
const GOLDEN := {
	"1:1": "17b60b3be2426bcf",
	"1:42": "31476b85897e6431",
	"1:12345": "2994f8107a89ee44",
	"1:2147483647": "20df494dcb33fb41",
	"2:7": "2db76fd0872d3334",
	"3:5": "1de2c3f8a50242a4",
}


func _suite_name() -> String:
	return "GENERATION STRESS"


func _get_tests() -> Array[Callable]:
	return [
		_test_template_lint, _test_profiles, _test_walkable_tables, _test_threat_model, _test_pacing_director,
		_test_content_honesty,
		_test_stress_depth_1, _test_stress_depth_2, _test_stress_depth_3, _test_depth_progression,
		_test_determinism, _test_variation, _test_golden_seeds, _test_stream_independence,
		_test_validator_negatives, _test_tactical_negatives, _test_hazards_never_break_floors,
		_test_retry_and_failure, _test_physical_traversal,
		_test_runtime_spawn_choice, _test_spawn_planner_seeks_intent, _test_density, _test_density_negatives,
		_test_enemy_navigation_reach,
		_test_build_performance,
	]


func _test_template_lint() -> bool:
	var profiles := [DepthProfile.load_for_depth(1), DepthProfile.load_for_depth(2), DepthProfile.load_for_depth(3)]
	var max_enemies := 0
	for p: DepthProfile in profiles:
		for n in p.enemies_by_size:
			max_enemies = maxi(max_enemies, n)
	var count := 0
	for file in DirAccess.get_files_at(TEMPLATE_DIR):
		if not file.ends_with(".tres"):
			continue
		var template := load(TEMPLATE_DIR.path_join(file)) as RoomTemplate
		count += 1
		# lint() covers every variant: parsing, clear anchor/sockets, door approaches
		# with player clearance, bridge width, timed-hazard size, pit/spike door
		# clearance, one connected walkable area, variants matching the base doors.
		var problems := template.lint()
		_check(problems.is_empty(), "template %s (%d variant(s)) lints cleanly %s" % [template.id, template.variant_count(), problems])
		for v in template.variant_count():
			var shape := template.get_shape(v)
			if shape.sockets.size() < 2:
				_check(false, "template %s[%s] has at least two door sockets" % [template.id, template.variant_name(v)])
			if template.has_role("risk"):
				# A risk room needs a cache and a visible risk (spikes) guarding it.
				_check(shape.cache_sockets.size() == 1 and shape.count_cells(RoomShape.Cell.SPIKES) > 0
						and not template.combat_allowed,
						"risk template %s[%s] has one cache and a visible spike risk" % [template.id, template.variant_name(v)])
			if not template.combat_allowed:
				continue
			var needed: int = profiles[0].enemies_by_size[template.size_class]
			var worst := 999
			for socket in shape.sockets:
				var inside := Vector2(socket.center - RoomShape.SIDE_VECTORS[socket.side]) * DungeonLayout.TILE_SIZE
				var far := 0
				for spawn in shape.enemy_spawns:
					if (Vector2(spawn) * DungeonLayout.TILE_SIZE).distance_to(inside) \
							>= DungeonValidator.MIN_SPAWN_DISTANCE + DungeonValidator.SPAWN_CHECK_MARGIN:
						far += 1
				worst = mini(worst, far)
			_check(worst >= needed, "template %s[%s]: every doorway has >= %d far spawn points (%d)" % [
				template.id, template.variant_name(v), needed, worst])
	_check(count >= 13, "at least thirteen room templates exist (%d)" % count)
	# Structure sockets: the lint checks the FULLY DRESSED variant, so a socket
	# that would crowd a doorway, smother a spawn point or touch terrain is
	# caught at authoring time, whichever subset the generator later picks.
	var base := "######DDD######\n#.............#\n#.E.......E...#\n#.............#\nD.............D\nD......C......D\nD.............D\n#.............#\n#.E.......E...#\n#.............#\n######DDD######"
	_check(RoomShape.parse(base).errors.is_empty(), "dressing lint fixture is clean without sockets")
	var lines := base.split("\n")
	var at_door := lines.duplicate()
	at_door[1] = "#.....x.......#"
	_check(_has_error(RoomShape.parse("\n".join(at_door)).errors, "too close to a doorway"), "lint refuses a structure socket at a doorway")
	var at_spawn := lines.duplicate()
	at_spawn[3] = "#..x..........#"
	_check(_has_error(RoomShape.parse("\n".join(at_spawn)).errors, "fully dressed: socket"), "lint refuses a structure socket that smothers a spawn point")
	var lane := lines.duplicate()
	lane[4] = "D..o..........D"
	lane[6] = "D..o..........D"
	_check(_has_error(RoomShape.parse("\n".join(lane)).errors, "fully dressed: doorway"),
			"lint refuses structure that would choke a doorway lane when fully dressed")
	var by_terrain := lines.duplicate()
	by_terrain[7] = "#.....xH......#"
	_check(_has_error(RoomShape.parse("\n".join(by_terrain)).errors, "touches terrain"), "lint refuses a structure socket touching a hazard socket")
	var dressed := lines.duplicate()
	dressed[1] = "#...........xx#"
	var good := RoomShape.parse("\n".join(dressed))
	_check(good.errors.is_empty() and good.dressing_regions.size() == 1, "a well-placed structure socket lints cleanly %s" % good.errors)
	return true


func _test_profiles() -> bool:
	var d1 := DepthProfile.load_for_depth(1)
	var d2 := DepthProfile.load_for_depth(2)
	var d3 := DepthProfile.load_for_depth(3)
	_check(d1 != null and d2 != null and d3 != null, "depth 1-3 profiles load")
	_check(d1.depth == 1 and d2.depth == 2 and d3.depth == 3 and d1.theme_id != d2.theme_id and d2.theme_id != d3.theme_id,
			"profiles carry their depth and theme")
	_check(d2.grid_columns * d2.grid_rows > d1.grid_columns * d1.grid_rows and d2.max_loops > d1.max_loops
			and d2.objective_encounter != d1.objective_encounter, "profiles differ in size, loops and objective rules")
	_check(DepthProfile.load_for_depth(4) == null and not DepthProfile.exists_for_depth(4),
			"missing depth profiles return null (finite test campaign)")
	_check(d1.special_rooms.size() == 1 and d1.special_rooms[0].template.id == &"story_chamber",
			"depth 1 reserves the story chamber")
	for p: DepthProfile in [d1, d2, d3]:
		var ok := not p.design_goal.is_empty()
		for recipe in p.tactical_recipes:
			ok = ok and TacticalComposer.RECIPES.has(recipe)
		for id in p.enemy_pool:
			ok = ok and EnemyCatalog.has(id)
		for table: Dictionary in [p.main_role_weights, p.branch_role_weights, p.dead_end_role_weights]:
			for key: String in table:
				ok = ok and RoomRole.KEYS.has(key)
		_check(ok, "depth %d profile: design goal, known recipes, enemies and role keys" % p.depth)
	return true


## Mask building uses lookup tables; they must agree with is_walkable_kind.
func _test_walkable_tables() -> bool:
	var ok := DungeonLayout.WALKABLE_PLAIN.size() == DungeonLayout.Tile.size() \
		and DungeonLayout.WALKABLE_WITH_HAZARD.size() == DungeonLayout.Tile.size()
	for kind in DungeonLayout.Tile.size():
		ok = ok and (DungeonLayout.WALKABLE_PLAIN[kind] == 1) == DungeonLayout.is_walkable_kind(kind, false)
		ok = ok and (DungeonLayout.WALKABLE_WITH_HAZARD[kind] == 1) == DungeonLayout.is_walkable_kind(kind, true)
	_check(ok, "walkability lookup tables match is_walkable_kind for every tile kind")
	var layout := DungeonGenerator.new().generate(DepthProfile.load_for_depth(2), 77, 2).layout
	var fast := DungeonValidator.clear_mask(layout, true)
	var mismatches := 0
	for y in layout.size.y:
		for x in layout.size.x:
			if (fast[y * layout.size.x + x] == 1) != layout.is_clear(Vector2i(x, y), true):
				mismatches += 1
	_check(mismatches == 0, "the fast clearance mask equals the per-tile definition (%d mismatches)" % mismatches)
	return true


## The director's own output (before templates and validation) keeps the
## rhythm: the validator would reject violations, but the director must not
## rely on that (it would silently waste attempts).
func _test_pacing_director() -> bool:
	var violations := 0
	var graphs := 0
	var ambush_dead_ends := 0
	var rest_without_fight := 0
	for depth in [1, 2, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		for s in 150:
			var streams := SeedStreams.new(s, depth, 0, DungeonGenerator.GENERATOR_VERSION)
			var graph := GraphBuilder.build(profile, streams.stream("graph"))
			if not graph.error.is_empty():
				continue
			PacingDirector.direct(graph, profile, streams.stream("pacing"))
			graphs += 1
			var roles := PacingDirector.main_path_roles(graph)
			var heavy_run := 0
			var terrain_run := 0
			for i in roles.size():
				var fight := RoomRole.is_heavy(roles[i]) or (i == roles.size() - 1 and profile.objective_encounter)
				heavy_run = heavy_run + 1 if fight else 0
				terrain_run = terrain_run + 1 if RoomRole.is_terrain_challenge(roles[i]) else 0
				if heavy_run > profile.max_consecutive_combat or terrain_run > profile.max_consecutive_terrain:
					violations += 1
				if i >= 2 and roles[i] == roles[i - 1] and roles[i] == roles[i - 2]:
					violations += 1
				if roles[i] == RoomRole.REST and not RoomRole.is_heavy(roles[i - 1]):
					rest_without_fight += 1
			for space in graph.spaces:
				if space.tactic == RoomRole.AMBUSH and graph.degree(space.id) < 2:
					ambush_dead_ends += 1
	_check(violations == 0, "the director never stacks fights/terrain or repeats a role three times (%d graphs, %d violations)" % [
		graphs, violations])
	_check(rest_without_fight == 0, "the director only places main-path rest rooms after a fight")
	_check(ambush_dead_ends == 0, "the director never puts an ambush where there is no second exit")
	return true


## Content placement and composition keep their own promises on EVERY attempt
## (accepted or not): the validator must never be what stops an unsafe spawn,
## an over-budget or cramped fight, or a purposeless hazard.
func _test_content_honesty() -> bool:
	var attempts := 0
	var unsafe_spawns := 0
	var over_budget := 0
	var cramped := 0
	var purposeless := 0
	var content_rejections := 0
	for depth in [1, 2, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		for s in 60:
			for attempt in 2:
				var layout := DungeonGenerator.new().generate_attempt(profile, 3300 + s, depth, attempt)
				if layout.rooms.is_empty() or layout.player_spawn == Vector2i.ZERO:
					continue  # construction failed before content placement
				attempts += 1
				var strict := DungeonValidator.clear_mask(layout, false)
				for room in layout.rooms:
					for t in room.spawn_candidates:
						if strict[layout.index_of(t)] == 0:
							unsafe_spawns += 1
					if room.threat > room.threat_budget + 0.001:
						over_budget += 1
					if not room.enemy_ids.is_empty():
						var f := ThreatModel.features(layout, room, strict)
						if f.clear_tiles < ThreatModel.MANEUVER_BASE + ThreatModel.MANEUVER_PER_ENEMY * room.enemy_ids.size():
							cramped += 1
					for hazard in room.hazards:
						if not RoomRole.allowed_purposes(room.tactic).has(hazard.get("purpose", &"")):
							purposeless += 1
				for e in layout.errors:
					for fragment: String in ["invalid spawn point", "exceeds its budget", "maneuvering space",
							"without a valid purpose", "recorded threat", "where the terrain matters", "unavoidable",
							"entering from link", "dressing", "lane tile", "alcove", "decor:"]:
						if e.contains(fragment):
							content_rejections += 1
	_check(unsafe_spawns == 0, "content placement only offers strict-clear spawn points (%d attempts, %d unsafe)" % [attempts, unsafe_spawns])
	_check(over_budget == 0 and cramped == 0, "the composer never builds a fight over budget (%d) or without maneuvering space (%d)" % [
		over_budget, cramped])
	_check(purposeless == 0, "content placement never places a hazard without a valid purpose (%d)" % purposeless)
	_check(content_rejections == 0, "the validator never has to reject an attempt for a content-placement or enemy-placement error (%d)" % content_rejections)
	return true


## ThreatModel is explainable: each interaction adds exactly its documented
## weight, and explain() lists every contribution.
func _test_threat_model() -> bool:
	var open := ThreatModel.Features.new()
	open.clear_tiles = 200
	var chasers: Array[StringName] = [&"chaser", &"chaser"]
	_check(is_equal_approx(ThreatModel.score(open, chasers, false), 4.0), "two chasers in an open unlocked room score 4.0")
	_check(is_equal_approx(ThreatModel.score(open, chasers, true), 4.5), "locking the doors adds %.2f" % ThreatModel.LOCKED_ROOM)
	var pit := ThreatModel.Features.new()
	pit.clear_tiles = 200
	pit.pit = true
	var brute: Array[StringName] = [&"brute"]
	_check(is_equal_approx(ThreatModel.score(pit, brute, false) - ThreatModel.score(open, brute, false),
			ThreatModel.KNOCKBACK_NEAR_PIT + ThreatModel.PIT_IN_FIGHT), "a brute near a chasm is worth more (knockback + chasm)")
	var spitter: Array[StringName] = [&"spitter"]
	var cover := ThreatModel.Features.new()
	cover.clear_tiles = 200
	cover.cover = true
	_check(is_equal_approx(ThreatModel.score(open, spitter, false) - ThreatModel.score(cover, spitter, false),
			ThreatModel.RANGED_WITHOUT_COVER),
			"a spitter without cover is worth more than with pillars to hide behind")
	var cramped := ThreatModel.Features.new()
	cramped.clear_tiles = 20
	_check(is_equal_approx(ThreatModel.score(cramped, chasers, false) - ThreatModel.score(open, chasers, false), ThreatModel.CRAMPED),
			"a cramped arena adds %.2f" % ThreatModel.CRAMPED)
	_check(ThreatModel.maneuver_capacity(16) == 0 and ThreatModel.maneuver_capacity(48) == 4,
			"maneuvering capacity: %d tiles + %d per enemy" % [ThreatModel.MANEUVER_BASE, ThreatModel.MANEUVER_PER_ENEMY])
	var layout := DungeonGenerator.new().generate(DepthProfile.load_for_depth(3), 12345, 3).layout
	var explained := 0
	for room in layout.rooms:
		if not room.enemy_ids.is_empty() and ThreatModel.explain(layout, room).size() >= room.enemy_ids.size():
			explained += 1
	_check(explained > 0, "explain() lists every enemy's contribution (%d rooms)" % explained)
	return true


func _test_stress_depth_1() -> bool:
	_stress(DepthProfile.load_for_depth(1), stress_seeds_depth_1)
	return true


func _test_stress_depth_2() -> bool:
	_stress(DepthProfile.load_for_depth(2), stress_seeds_depth_2)
	return true


func _test_stress_depth_3() -> bool:
	_stress(DepthProfile.load_for_depth(3), stress_seeds_depth_3)
	return true


func _stress(profile: DepthProfile, seeds: int) -> void:
	var gen := DungeonGenerator.new()
	var fails := 0
	var revalidation_errors := 0
	var attempts := 0
	var max_attempts := 0
	var total_ms := 0.0
	var max_ms := 0.0
	var stats := {"turns": 0, "branches": 0, "dead_ends": 0, "loops": 0, "special_ok": 0,
		"purpose_ok": 0, "combat_ok": 0, "templates": 0, "rooms": 0, "enemy_cap_ok": 0, "hazards": 0,
		"environmental": 0, "water": 0, "pit": 0, "bridge_ok": 0, "bridge_rooms": 0, "interior": 0,
		"pacing_ok": 0, "events_ok": 0, "event_before_fight": 0, "variants": {},
		"roles": {}, "recipes": {}, "archetypes": {}, "purposes": {}, "purposeless": 0, "floors_with": {},
		"risk_rooms": 0, "risk_routes": 0, "risk_shorter": 0, "max_ratio": 0.0, "max_floor_ratio": 0.0,
		"floor_threat": 0.0, "fight_threat": 0.0, "fights": 0, "sequences": {}}
	var max_enemies := 0
	for n in profile.enemies_by_size:
		max_enemies = maxi(max_enemies, n)
	for seed_value in seeds:
		var result := gen.generate(profile, seed_value * 7919 + 3, profile.depth)
		attempts += result.attempts
		max_attempts = maxi(max_attempts, result.attempts)
		total_ms += result.msec
		max_ms = maxf(max_ms, result.msec)
		if not result.ok:
			fails += 1
			printerr("    failed seed %d: %s" % [seed_value * 7919 + 3, result.failure_log[-1]])
			continue
		var layout := result.layout
		if not DungeonValidator.validate(layout, profile).is_empty():
			revalidation_errors += 1
		var graph := layout.graph
		if graph.main_path_turns() > 0:
			stats.turns += 1
		if graph.count_links(DungeonGraph.LinkKind.BRANCH) > 0:
			stats.branches += 1
		var dead_ends := graph.ids_with_role(DungeonGraph.Role.DEAD_END)
		if not dead_ends.is_empty():
			stats.dead_ends += 1
		var purposes_ok := true
		for id in dead_ends:
			purposes_ok = purposes_ok and graph.spaces[id].purpose != DungeonGraph.Purpose.NONE \
				and not layout.rooms[id].markers.is_empty()
		if purposes_ok:
			stats.purpose_ok += 1
		if graph.count_links(DungeonGraph.LinkKind.LOOP) > 0:
			stats.loops += 1
		var specials := graph.ids_with_role(DungeonGraph.Role.SPECIAL)
		var expected_index := clampi(roundi(profile.special_rooms[0].main_path_fraction * (graph.main_path.size() - 1)),
				1, graph.main_path.size() - 2)
		if specials.size() == 1 and graph.spaces[specials[0]].main_index == expected_index \
				and layout.rooms[specials[0]].template == profile.special_rooms[0].template:
			stats.special_ok += 1
		var combat := 0
		var cap_ok := true
		var templates := {}
		for room in layout.rooms:
			templates[room.template.id] = true
			if RoomRole.is_heavy(room.tactic) and room.role == DungeonGraph.Role.MAIN:
				combat += 1
			cap_ok = cap_ok and room.enemy_ids.size() <= max_enemies
			stats.hazards += room.hazards.size()
		if combat >= profile.min_combat_rooms:
			stats.combat_ok += 1
		_tactical_stats(layout, profile, stats)
		if cap_ok:
			stats.enemy_cap_ok += 1
		stats.templates += templates.size()
		stats.rooms += layout.rooms.size()
		_environment_stats(layout, profile, stats)
	var ok := seeds - fails
	print("    depth %d: %d floors, avg %.2f attempts (max %d), avg %.1f ms (max %.1f), avg %.1f rooms, %.1f templates/floor, %d hazards" % [
		profile.depth, seeds, attempts / float(seeds), max_attempts, total_ms / seeds, max_ms,
		stats.rooms / float(maxi(ok, 1)), stats.templates / float(maxi(ok, 1)), stats.hazards])
	print("    turns %d  branches %d  dead-ends %d  loops %d  special %d  purposes %d  min-combat %d  enemy-cap %d (of %d)" % [
		stats.turns, stats.branches, stats.dead_ends, stats.loops, stats.special_ok, stats.purpose_ok,
		stats.combat_ok, stats.enemy_cap_ok, ok])
	_check(fails == 0, "depth %d: all %d seeds produce a valid floor (%d failed)" % [profile.depth, seeds, fails])
	_check(revalidation_errors == 0, "depth %d: every accepted floor re-validates cleanly" % profile.depth)
	_check(stats.special_ok == ok, "depth %d: special room inserted at its main-path slot in every floor" % profile.depth)
	_check(stats.purpose_ok == ok, "depth %d: every dead end has a purpose and a marker" % profile.depth)
	_check(stats.enemy_cap_ok == ok, "depth %d: encounters never exceed the per-size enemy cap" % profile.depth)
	_check(stats.turns >= ok * 0.97, "depth %d: main path turns (not a straight chain) in >= 97%% of floors" % profile.depth)
	_check(stats.branches >= ok * 0.95, "depth %d: branches in >= 95%% of floors" % profile.depth)
	_check(stats.dead_ends >= ok * 0.8, "depth %d: dead ends in >= 80%% of floors" % profile.depth)
	_check(stats.loops >= ok * 0.15, "depth %d: loops (alternate routes) in >= 15%% of floors" % profile.depth)
	_check(stats.combat_ok >= ok * 0.95, "depth %d: >= min combat rooms in >= 95%% of floors" % profile.depth)
	_check(stats.templates / float(maxi(ok, 1)) >= 4.0, "depth %d: >= 4 distinct room templates per floor on average" % profile.depth)
	_check(total_ms / seeds < 250.0, "depth %d: generation averages under 250 ms" % profile.depth)
	print("    terrain-challenge %d  water %d  pits %d  interior-geometry %d  pacing-ok %d  events-ok %d (before a fight %d)  variants used %d" % [
		stats.environmental, stats.water, stats.pit, stats.interior, stats.pacing_ok, stats.events_ok,
		stats.event_before_fight, stats.variants.size()])
	_check(stats.environmental >= ok * 0.75, "depth %d: terrain-challenge rooms (hazard / hazard fight / risk) in >= 75%% of floors" % profile.depth)
	_check(stats.interior >= ok * 0.9, "depth %d: rooms with interior walls/pillars/rubble in >= 90%% of floors" % profile.depth)
	_check(stats.water >= ok * 0.15 and stats.pit >= ok * 0.15, "depth %d: water and pit rooms each appear in >= 15%% of floors" % profile.depth)
	_check(stats.bridge_rooms > 0 and stats.bridge_ok == stats.bridge_rooms,
			"depth %d: every pit room keeps its doorways joined around/over the chasm (%d rooms)" % [profile.depth, stats.bridge_rooms])
	_check(stats.pacing_ok == ok, "depth %d: never more than %d fight(s) in a row on the main path" % [profile.depth, profile.max_consecutive_combat])
	_check(stats.events_ok == ok, "depth %d: event sockets in every floor, exactly %d armed in a quiet space" % [profile.depth, profile.armed_event_count])
	_check(stats.event_before_fight >= ok * 0.8, "depth %d: the armed event precedes a fight in >= 80%% of floors (uncertainty -> combat)" % profile.depth)
	_check(stats.variants.size() >= 16, "depth %d: >= 16 distinct template variants used (%d)" % [profile.depth, stats.variants.size()])
	_tactical_checks(profile, stats, ok)


## Tactical data per floor (Milestone 2.2): role mix, recipes, archetypes,
## threat against budgets, risk routes, rest rooms, hazard purposes.
func _tactical_stats(layout: DungeonLayout, profile: DepthProfile, stats: Dictionary) -> void:
	var seen_roles := {}
	var fight_threat := 0.0
	var fights := 0
	for room in layout.rooms:
		var role_name := RoomRole.name_of(room.tactic)
		stats.roles[role_name] = stats.roles.get(role_name, 0) + 1
		seen_roles[room.tactic] = true
		if room.recipe != &"":
			stats.recipes[room.recipe] = stats.recipes.get(room.recipe, 0) + 1
		for id in room.enemy_ids:
			stats.archetypes[id] = stats.archetypes.get(id, 0) + 1
		if not room.enemy_ids.is_empty():
			fights += 1
			fight_threat += room.threat
			stats.max_ratio = maxf(stats.max_ratio, room.threat / maxf(room.threat_budget, 0.01))
		for hazard in room.hazards:
			var purpose := str(hazard.get("purpose", &""))
			stats.purposes[purpose] = stats.purposes.get(purpose, 0) + 1
			if purpose.is_empty():
				stats.purposeless += 1
		if room.tactic == RoomRole.RISK_REWARD:
			stats.risk_rooms += 1
			if room.risk_route.size() > 1:
				stats.risk_routes += 1
			if room.safe_route.is_empty() or room.safe_route.size() > room.risk_route.size():
				stats.risk_shorter += 1
	for role: int in [RoomRole.REST, RoomRole.RISK_REWARD, RoomRole.AMBUSH, RoomRole.HAZARD_COMBAT, RoomRole.CHALLENGE]:
		if seen_roles.has(role):
			stats.floors_with[role] = stats.floors_with.get(role, 0) + 1
	stats.floor_threat += layout.total_threat()
	stats.max_floor_ratio = maxf(stats.max_floor_ratio, layout.total_threat() / profile.floor_threat_budget)
	stats.fight_threat += fight_threat
	stats.fights += fights
	# Variety of the main-path rhythm across seeds.
	var sequence := PackedStringArray()
	for id in layout.graph.main_path:
		sequence.append(RoomRole.name_of(layout.rooms[id].tactic))
	var key := ">".join(sequence)
	stats.sequences[key] = stats.sequences.get(key, 0) + 1


func _tactical_checks(profile: DepthProfile, stats: Dictionary, ok: int) -> void:
	var avg_fight: float = stats.fight_threat / float(maxi(stats.fights, 1))
	print("    roles %s" % stats.roles)
	print("    recipes %s" % stats.recipes)
	print("    archetypes %s  hazard purposes %s" % [stats.archetypes, stats.purposes])
	print("    avg fight threat %.2f (budget %.1f, max use %.0f%%), avg floor threat %.1f (budget %.1f, max use %.0f%%), %d distinct main-path rhythms" % [
		avg_fight, profile.room_threat_budget, stats.max_ratio * 100.0, stats.floor_threat / float(maxi(ok, 1)),
		profile.floor_threat_budget, stats.max_floor_ratio * 100.0, stats.sequences.size()])
	var common: Array = stats.sequences.keys()
	common.sort_custom(func(a: String, b: String) -> bool: return stats.sequences[a] > stats.sequences[b])
	for key: String in common.slice(0, 3):
		print("      %3d x %s" % [stats.sequences[key], key])
	print("    floors with: rest %d  risk %d  ambush %d  hazard-fight %d  challenge %d; risk rooms %d (risky route shorter or only way: %d)" % [
		stats.floors_with.get(RoomRole.REST, 0), stats.floors_with.get(RoomRole.RISK_REWARD, 0),
		stats.floors_with.get(RoomRole.AMBUSH, 0), stats.floors_with.get(RoomRole.HAZARD_COMBAT, 0),
		stats.floors_with.get(RoomRole.CHALLENGE, 0), stats.risk_rooms, stats.risk_shorter])
	_check(stats.max_ratio <= 1.0 + 0.001, "depth %d: no fight exceeds its threat budget (max %.0f%%)" % [profile.depth, stats.max_ratio * 100.0])
	_check(stats.max_floor_ratio <= 1.0 + 0.001, "depth %d: no floor exceeds its threat budget" % profile.depth)
	_check(avg_fight >= profile.room_threat_budget * 0.5, "depth %d: fights use their budget (avg %.2f >= half of %.1f)" % [
		profile.depth, avg_fight, profile.room_threat_budget])
	_check(stats.purposeless == 0, "depth %d: every hazard has a purpose" % profile.depth)
	# Short, tightly paced teaching floors have few possible rhythms, so the
	# measure is repetition: no single rhythm may dominate.
	var most := 0
	for key: String in stats.sequences:
		most = maxi(most, stats.sequences[key])
	_check(stats.sequences.size() >= mini(ok / 2, 20) and most <= ok * 0.15,
			"depth %d: main-path rhythms vary (%d distinct in %d floors, most common %.0f%%)" % [
				profile.depth, stats.sequences.size(), ok, most * 100.0 / maxi(ok, 1)])
	_check(stats.floors_with.get(RoomRole.REST, 0) >= ok * 0.1, "depth %d: recovery rooms in >= 10%% of floors" % profile.depth)
	# Every allowed recipe/archetype actually appears (nothing is dead framework).
	var unused := PackedStringArray()
	for recipe in profile.tactical_recipes:
		if not stats.recipes.has(StringName(recipe)):
			unused.append(recipe)
	for id in profile.enemy_pool:
		if not stats.archetypes.has(id):
			unused.append(str(id))
	_check(unused.is_empty(), "depth %d: every allowed recipe and enemy archetype is used %s" % [profile.depth, unused])
	var weights := {}
	for table: Dictionary in [profile.main_role_weights, profile.branch_role_weights, profile.dead_end_role_weights]:
		for key: String in table:
			if float(table[key]) > 0.0:
				weights[RoomRole.KEYS[key]] = true
	var missing := PackedStringArray()
	for role: int in weights:
		if not stats.roles.has(RoomRole.name_of(role)):
			missing.append(RoomRole.name_of(role))
	_check(missing.is_empty(), "depth %d: every weighted room role appears %s" % [profile.depth, missing])
	if weights.has(RoomRole.RISK_REWARD):
		_check(stats.floors_with.get(RoomRole.RISK_REWARD, 0) >= ok * 0.5 and stats.risk_routes == stats.risk_rooms
				and stats.risk_shorter == stats.risk_rooms,
				"depth %d: risk rooms in >= 50%% of floors, each with a risky route that is shorter than the safe one (or the only way to the cache)" % profile.depth)
	if weights.has(RoomRole.HAZARD_COMBAT):
		_check(stats.floors_with.get(RoomRole.HAZARD_COMBAT, 0) >= ok * 0.5, "depth %d: fights on terrain in >= 50%% of floors" % profile.depth)
	if weights.has(RoomRole.AMBUSH):
		_check(stats.floors_with.get(RoomRole.AMBUSH, 0) >= ok * 0.3, "depth %d: open-door ambushes in >= 30%% of floors" % profile.depth)


func _environment_stats(layout: DungeonLayout, profile: DepthProfile, stats: Dictionary) -> void:
	var has := {"env": false, "water": false, "pit": false, "interior": false}
	var route := PackedByteArray()
	for room in layout.rooms:
		stats.variants["%s/%d" % [room.template.id, room.variant]] = true
		if RoomRole.is_terrain_challenge(room.tactic):
			has.env = true
		var kinds := {}
		var bounds := room.bounds()
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				kinds[layout.get_tile(Vector2i(x, y))] = true
		if kinds.has(DungeonLayout.Tile.WATER):
			has.water = true
		if kinds.has(DungeonLayout.Tile.INNER_WALL) or kinds.has(DungeonLayout.Tile.OBSTACLE) or kinds.has(DungeonLayout.Tile.RUBBLE):
			has.interior = true
		if kinds.has(DungeonLayout.Tile.PIT):
			has.pit = true
			stats.bridge_rooms += 1
			if route.is_empty():
				route = DungeonValidator.required_mask(layout)
			if _pit_room_sides_joined(layout, room, route):
				stats.bridge_ok += 1
	for key: String in ["env", "water", "pit", "interior"]:
		if has[key]:
			stats[{"env": "environmental", "water": "water", "pit": "pit", "interior": "interior"}[key]] += 1
	# Pacing: count consecutive fights along the main path (the objective
	# fight counts like any other).
	var run := 0
	var worst := 0
	var path := layout.graph.main_path
	for i in path.size():
		var room := layout.rooms[path[i]]
		var fight := RoomRole.is_heavy(room.tactic) or (i == path.size() - 1 and room.encounter != DungeonGraph.Encounter.NONE)
		run = run + 1 if fight else 0
		worst = maxi(worst, run)
	if worst <= profile.max_consecutive_combat:
		stats.pacing_ok += 1
	var armed := 0
	var armed_quiet := true
	for socket in layout.event_sockets:
		if socket.armed:
			armed += 1
			var room := layout.room_for_space(socket.room)
			armed_quiet = armed_quiet and (room == null or not RoomRole.is_heavy(room.tactic))
			if ContentPlacer._leads_into_fight(layout, socket):
				stats.event_before_fight += 1
	if layout.event_sockets.size() >= layout.corridors.size() and armed == profile.armed_event_count and armed_quiet:
		stats.events_ok += 1


## In a pit room every doorway must reach every other through clear tiles
## (i.e. the bridges really connect the sides).
func _pit_room_sides_joined(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, route: PackedByteArray) -> bool:
	var reached := DungeonValidator.flood(layout, route, room.anchor)
	for door in room.doors:
		if reached[layout.index_of(door.center)] == 0:
			return false
	return true


## Depth progression is expressed through profiles: each depth keeps what the
## previous one taught and adds mechanics (roles, recipes, archetypes), with
## a larger budget; generated floors reflect it (more distinct recipes and
## terrain interactions), without inflating enemy counts.
func _test_depth_progression() -> bool:
	var previous: DepthProfile = null
	var previous_recipes := 0
	var previous_interactions := -1.0
	for depth in [1, 2, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		var recipes := {}
		var interactions := 0
		var fights := 0
		var max_enemies := 0
		for s in 40:
			var layout := DungeonGenerator.new().generate(profile, 4400 + s, depth).layout
			for room in layout.rooms:
				if room.enemy_ids.is_empty():
					continue
				fights += 1
				recipes[room.recipe] = true
				max_enemies = maxi(max_enemies, room.enemy_ids.size())
				if TacticalComposer.RECIPES[room.recipe].specific:
					interactions += 1
		var interaction_share := interactions / float(maxi(fights, 1))
		print("    depth %d: %d distinct recipes, %.0f%% of fights use a room-specific interaction, max %d enemies per fight" % [
			depth, recipes.size(), interaction_share * 100.0, max_enemies])
		if previous != null:
			var superset := true
			for role: int in previous.allowed_roles():
				superset = superset and profile.allowed_roles().has(role)
			for recipe in previous.tactical_recipes:
				superset = superset and profile.tactical_recipes.has(recipe)
			for id in previous.enemy_pool:
				superset = superset and profile.enemy_pool.has(id)
			_check(superset, "depth %d keeps every role, recipe and archetype depth %d taught" % [depth, depth - 1])
			_check(profile.room_threat_budget > previous.room_threat_budget
					and profile.floor_threat_budget > previous.floor_threat_budget,
					"depth %d has a larger threat budget than depth %d" % [depth, depth - 1])
			_check(recipes.size() > previous_recipes and interaction_share > previous_interactions,
					"depth %d fights are tactically richer than depth %d (recipes %d > %d, interactions %.0f%% > %.0f%%)" % [
						depth, depth - 1, recipes.size(), previous_recipes, interaction_share * 100.0, previous_interactions * 100.0])
		_check(max_enemies <= profile.enemies_by_size[profile.enemies_by_size.size() - 1],
				"depth %d never exceeds its enemy cap (%d)" % [depth, max_enemies])
		previous = profile
		previous_recipes = recipes.size()
		previous_interactions = interaction_share
	return true


func _test_determinism() -> bool:
	var profile := DepthProfile.load_for_depth(1)
	var mismatches := 0
	for seed_value in DETERMINISM_SEEDS:
		seed(1)
		var a := DungeonGenerator.new().generate(profile, seed_value, 1)
		# Perturb the global RNG: generation must not depend on it.
		seed(987654321)
		for i in 17:
			randi()
		var b := DungeonGenerator.new().generate(profile, seed_value, 1)
		if a.layout.fingerprint() != b.layout.fingerprint() or a.attempts != b.attempts:
			mismatches += 1
	_check(mismatches == 0, "same seed reproduces the same floor even with the global RNG disturbed (%d of %d mismatched)" % [
		mismatches, DETERMINISM_SEEDS])
	var d2 := DepthProfile.load_for_depth(2)
	_check(DungeonGenerator.new().generate(d2, 99, 2).layout.fingerprint()
			== DungeonGenerator.new().generate(d2, 99, 2).layout.fingerprint(), "depth 2 is deterministic too")
	_check(DungeonGenerator.new().generate(profile, 99, 1).layout.fingerprint()
			!= DungeonGenerator.new().generate(profile, 99, 2).layout.fingerprint(),
			"the same seed at another depth gives another floor")
	# Tactical data (roles, recipes, enemies, threat, hazard purposes, markers,
	# risk routes) must be identical too, at the depth that uses every system.
	var d3 := DepthProfile.load_for_depth(3)
	var tactical_mismatches := 0
	for seed_value in 60:
		seed(5)
		var a := DungeonGenerator.new().generate(d3, 700 + seed_value, 3).layout
		seed(424242)
		randf()
		var b := DungeonGenerator.new().generate(d3, 700 + seed_value, 3).layout
		if a.tactical_signature() != b.tactical_signature() or str(a.rooms.map(func(r: DungeonLayout.PlacedRoom) -> String:
				return str(r.risk_route) + str(r.safe_route))) != str(b.rooms.map(func(r: DungeonLayout.PlacedRoom) -> String:
				return str(r.risk_route) + str(r.safe_route))):
			tactical_mismatches += 1
	_check(tactical_mismatches == 0, "same seed reproduces identical tactical data at depth 3 (%d of 60 mismatched)" % tactical_mismatches)
	return true


func _test_variation() -> bool:
	var profile := DepthProfile.load_for_depth(1)
	var fingerprints := {}
	var shapes := {}
	for seed_value in VARIATION_SEEDS:
		var layout := DungeonGenerator.new().generate(profile, 50000 + seed_value, 1).layout
		fingerprints[layout.fingerprint()] = true
		var cells := PackedStringArray()
		var origin := layout.graph.spaces[layout.graph.entry_id()].cell
		for space in layout.graph.spaces:
			cells.append(str(space.cell - origin))
		cells.sort()
		shapes[",".join(cells)] = true
	_check(fingerprints.size() == VARIATION_SEEDS, "%d seeds -> %d distinct floors" % [VARIATION_SEEDS, fingerprints.size()])
	_check(shapes.size() >= VARIATION_SEEDS * 0.8, "%d distinct topologies (relative room arrangements)" % shapes.size())
	# Tactical variation: different seeds give different role rhythms and fights.
	var d3 := DepthProfile.load_for_depth(3)
	var signatures := {}
	var rhythms := {}
	var compositions := {}
	for seed_value in 100:
		var layout := DungeonGenerator.new().generate(d3, 60000 + seed_value, 3).layout
		signatures[layout.tactical_signature()] = true
		rhythms[layout.tactical_signature().get_slice("\n", 0)] = true
		for room in layout.rooms:
			if not room.enemy_ids.is_empty():
				compositions["%s:%s" % [room.recipe, ",".join(room.enemy_ids)]] = true
	_check(signatures.size() == 100, "100 seeds -> 100 distinct tactical layouts at depth 3 (%d)" % signatures.size())
	_check(rhythms.size() >= 60, "main-path role rhythms vary (%d distinct in 100)" % rhythms.size())
	_check(compositions.size() >= 15, "encounter compositions vary (%d distinct recipe/enemy mixes)" % compositions.size())
	return true


func _test_golden_seeds() -> bool:
	for key: String in GOLDEN:
		var parts := key.split(":")
		var depth := int(parts[0])
		var seed_value := int(parts[1])
		var layout := DungeonGenerator.new().generate(DepthProfile.load_for_depth(depth), seed_value, depth).layout
		var actual := layout.fingerprint()
		if GOLDEN[key] == "":
			print("    golden %s = %s (not pinned yet)" % [key, actual])
			_check(false, "golden fingerprint for %s is pinned" % key)
		else:
			_check(actual == GOLDEN[key], "golden seed %s unchanged (%s)" % [key, actual])
	return true


## Changing only content settings must not move rooms or corridors: topology,
## pacing and templates draw from their own streams, and content can never
## force a different attempt. Tactical composition ("tactics" stream) must not
## change hazards either, and hazards must not change the composition stream.
func _test_stream_independence() -> bool:
	var profile := (DepthProfile.load_for_depth(3).duplicate() as DepthProfile)
	profile.hazard_density = 1.0
	var no_hazards := profile.duplicate() as DepthProfile
	no_hazards.hazard_density = 0.0
	var tight := profile.duplicate() as DepthProfile
	tight.room_threat_budget = profile.room_threat_budget * 0.7
	var same_topology := 0
	var hazards_differ := 0
	var tight_same_topology := 0
	var tight_same_hazards := 0
	var enemies_differ := 0
	var n := 120
	for seed_value in n:
		var a := DungeonGenerator.new().generate(profile, seed_value, 3)
		var b := DungeonGenerator.new().generate(no_hazards, seed_value, 3)
		var c := DungeonGenerator.new().generate(tight, seed_value, 3)
		if a.attempts != b.attempts or a.attempts != c.attempts:
			continue  # a content setting may change which attempt validates first
		if a.layout.fingerprint(false) == b.layout.fingerprint(false):
			same_topology += 1
		if _hazard_text(a.layout) != _hazard_text(b.layout):
			hazards_differ += 1
		if a.layout.fingerprint(false) == c.layout.fingerprint(false):
			tight_same_topology += 1
		if _hazard_text(a.layout) == _hazard_text(c.layout):
			tight_same_hazards += 1
		if _enemy_text(a.layout) != _enemy_text(c.layout):
			enemies_differ += 1
	_check(same_topology >= 60 and tight_same_topology == same_topology,
			"hazard density and threat budget never change topology or room roles (%d floors compared)" % same_topology)
	_check(hazards_differ > 0, "hazard density does change hazards (%d floors)" % hazards_differ)
	_check(tight_same_hazards == tight_same_topology, "the threat budget never changes hazards (independent streams)")
	_check(enemies_differ > 0, "a tighter threat budget changes encounters (%d floors)" % enemies_differ)
	return true


func _hazard_text(layout: DungeonLayout) -> String:
	var parts := PackedStringArray()
	for room in layout.rooms:
		for hazard in room.hazards:
			parts.append(str(hazard.tiles))
	return "|".join(parts)


func _enemy_text(layout: DungeonLayout) -> String:
	var parts := PackedStringArray()
	for room in layout.rooms:
		parts.append(",".join(room.enemy_ids))
	return "|".join(parts)


func _test_validator_negatives() -> bool:
	var profile := DepthProfile.load_for_depth(1)
	var fresh := func() -> DungeonLayout: return DungeonGenerator.new().generate(profile, 4242, 1).layout
	var base: DungeonLayout = fresh.call()
	_check(DungeonValidator.validate(base, profile).is_empty(), "baseline floor validates")

	var layout: DungeonLayout = fresh.call()
	layout.graph.spaces[layout.graph.objective_id()].role = DungeonGraph.Role.MAIN
	_check(_has_error(DungeonValidator.validate(layout, profile), "objective"), "detects a missing objective")

	layout = fresh.call()
	var corridor := layout.corridors[0]
	var middle := corridor.rects[1]
	for y in range(middle.position.y, middle.end.y):
		for x in range(middle.position.x, middle.end.x):
			layout.set_tile(Vector2i(x, y), DungeonLayout.Tile.WALL, DungeonLayout.NO_OWNER)
	var errors := DungeonValidator.validate(layout, profile)
	_check(_has_error(errors, "not traversable") and _has_error(errors, "unreachable"), "detects a blocked corridor")

	layout = fresh.call()
	layout.rooms[1].origin = layout.rooms[0].origin + Vector2i(2, 2)
	_check(_has_error(DungeonValidator.validate(layout, profile), "overlap"), "detects overlapping rooms")

	layout = fresh.call()
	var entry := layout.entry_room()
	for t: Vector2i in entry.doors[0].tiles:
		layout.set_tile(t, DungeonLayout.Tile.HAZARD, entry.id)
	_check(_has_error(DungeonValidator.validate(layout, profile), "hazard on a doorway"), "detects a hazard on a doorway")

	layout = fresh.call()
	layout.set_tile(layout.entry_room().anchor + Vector2i(2, 0), DungeonLayout.Tile.HAZARD, layout.entry_room().id)
	_check(_has_error(DungeonValidator.validate(layout, profile), "unlisted hazard"), "detects an unlisted hazard tile")

	layout = fresh.call()
	var combat_room: DungeonLayout.PlacedRoom = null
	for room in layout.rooms:
		if not room.spawn_candidates.is_empty():
			combat_room = room
			break
	combat_room.spawn_candidates[0] = combat_room.origin
	_check(_has_error(DungeonValidator.validate(layout, profile), "invalid spawn point"), "detects a spawn point inside a wall")

	layout = fresh.call()
	layout.player_spawn = layout.entry_room().origin
	_check(_has_error(DungeonValidator.validate(layout, profile), "player spawn"), "detects a player spawn inside a wall")

	layout = fresh.call()
	for space in layout.graph.spaces:
		space.special_rule = null
	_check(_has_error(DungeonValidator.validate(layout, profile), "special room"), "detects a missing special room")

	layout = fresh.call()
	layout.graph.add_space(Vector2i(layout.graph.grid_size.x + 3, 0), DungeonGraph.Role.BRANCH)
	_check(_has_error(DungeonValidator.validate(layout, profile), "disconnected"), "detects a disconnected space")

	layout = fresh.call()
	layout.conflicts = 3
	_check(_has_error(DungeonValidator.validate(layout, profile), "claimed by two"), "detects carve conflicts")

	# --- environmental geometry (Milestone 2.1) ---
	layout = fresh.call()
	corridor = layout.corridors[0]
	middle = corridor.rects[1]
	for y in range(middle.position.y, middle.end.y):
		for x in range(middle.position.x, middle.end.x):
			layout.set_tile(Vector2i(x, y), DungeonLayout.Tile.PIT, DungeonLayout.NO_OWNER)
	errors = DungeonValidator.validate(layout, profile)
	_check(_has_error(errors, "not traversable") and _has_error(errors, "unreachable"), "detects a pit cutting a mandatory route")

	var pit_layout := _layout_with_template(&"pit_bridge_chamber")
	if pit_layout != null:
		for t in _tiles_of(pit_layout, DungeonLayout.Tile.BRIDGE):
			pit_layout.set_tile(t, DungeonLayout.Tile.PIT, pit_layout.get_owner_of(t))
		errors = DungeonValidator.validate(pit_layout, profile)
		_check(_has_error(errors, "cut off") or _has_error(errors, "unreachable"), "detects a removed bridge")
	else:
		_check(false, "found a floor with a pit/bridge room for the bridge test")

	layout = fresh.call()
	var room := layout.rooms[layout.graph.main_path[1]]
	var door: Dictionary = room.doors[0]
	var inward: Vector2i = -RoomShape.SIDE_VECTORS[door.side]
	var across := Vector2i(inward.y, inward.x)
	for k in range(-2, 3):
		layout.set_tile(door.inside + inward + across * k, DungeonLayout.Tile.INNER_WALL, room.id)
	_check(_has_error(DungeonValidator.validate(layout, profile), "cut off"), "detects an interior wall blocking a doorway")

	layout = fresh.call()
	var fight := _room_with_spawns(layout)
	var pillar := fight.spawn_candidates[0]
	layout.set_tile(pillar, DungeonLayout.Tile.OBSTACLE, fight.id)
	_check(_has_error(DungeonValidator.validate(layout, profile), "invalid spawn point"), "detects an enemy spawn inside an obstacle")

	layout = fresh.call()
	fight = _room_with_spawns(layout)
	layout.set_tile(fight.spawn_candidates[0], DungeonLayout.Tile.WATER, fight.id)
	var water_errors := DungeonValidator.validate(layout, profile)
	_check(not _has_error(water_errors, "invalid spawn point"), "water is walkable: a spawn in water stays valid")

	layout = fresh.call()
	layout.event_sockets[0].tile = layout.entry_room().origin
	_check(_has_error(DungeonValidator.validate(layout, profile), "event socket"), "detects an event socket inside a wall")

	layout = fresh.call()
	layout.event_sockets[0].tile = layout.player_spawn
	_check(_has_error(DungeonValidator.validate(layout, profile), "overlaps"), "detects an event socket on top of the player spawn")

	layout = fresh.call()
	# Paint the longest contiguous run of room floor on any row as one spike area.
	var hazard_room: DungeonLayout.PlacedRoom = null
	var band: Array[Vector2i] = []
	for candidate in layout.rooms:
		var hb := candidate.bounds()
		for y in range(hb.position.y, hb.end.y):
			var run: Array[Vector2i] = []
			for x in range(hb.position.x, hb.end.x + 1):
				var t := Vector2i(x, y)
				if x < hb.end.x and layout.get_tile(t) == DungeonLayout.Tile.FLOOR \
						and layout.get_owner_of(t) == candidate.id:
					run.append(t)
					continue
				if run.size() > band.size():
					band = run.duplicate()
					hazard_room = candidate
				run.clear()
	for t in band:
		layout.set_tile(t, DungeonLayout.Tile.HAZARD, hazard_room.id)
	hazard_room.hazards.append({"type": &"spikes", "tiles": band, "authored": false})
	_check(band.size() > RoomShape.MAX_TIMED_REGION and _has_error(DungeonValidator.validate(layout, profile), "too long"),
			"detects a spike area too long to cross in one safe window")
	return true


## Milestone 2.2 fairness rules: each case breaks exactly one rule on a valid
## floor and expects the validator to name it.
func _test_tactical_negatives() -> bool:
	var d1 := DepthProfile.load_for_depth(1)
	var d2 := DepthProfile.load_for_depth(2)
	var d3 := DepthProfile.load_for_depth(3)

	var layout := _find(1, RoomRole.COMBAT)
	_check(DungeonValidator.validate(layout, d1).is_empty(), "tactical baseline floor validates")
	var entry := layout.entry_room()
	var near_spawn: Array[Vector2i] = [layout.player_spawn + Vector2i(2, 0)]
	layout.set_tile(near_spawn[0], DungeonLayout.Tile.HAZARD, entry.id)
	entry.hazards.append({"type": &"spikes", "tiles": near_spawn, "authored": false, "purpose": RoomRole.PURPOSE_TIMING})
	_check(_has_error(DungeonValidator.validate(layout, d1), "hazard within"), "detects a hazard at the player spawn")

	layout = _find(1, RoomRole.COMBAT)
	var fight := _room_with_role(layout, RoomRole.COMBAT)
	var door: Dictionary = fight.doors[0]
	var inward: Vector2i = -RoomShape.SIDE_VECTORS[door.side]
	layout.set_tile(door.inside + inward * 2, DungeonLayout.Tile.PIT, fight.id)
	_check(_has_error(DungeonValidator.validate(layout, d1), "not safe to step into"),
			"detects unavoidable danger right after entering a room")

	layout = _find(1, RoomRole.HAZARD)
	var hazard_room := _room_with_role(layout, RoomRole.HAZARD)
	var hb := hazard_room.bounds()
	for y in range(hb.position.y + 1, hb.end.y - 1):
		for x in range(hb.position.x + 1, hb.end.x - 1):
			if layout.get_owner_of(Vector2i(x, y)) == hazard_room.id and layout.is_walkable(Vector2i(x, y)):
				layout.set_tile(Vector2i(x, y), DungeonLayout.Tile.PIT, hazard_room.id)
	_check(_has_error(DungeonValidator.validate(layout, d1), "too many stacked hazards"), "detects stacked hazards covering a room")

	layout = _find(2, RoomRole.COMBAT)
	fight = _room_with_role(layout, RoomRole.COMBAT)
	for i in 3:
		fight.enemy_ids.append(&"brute")
	fight.threat = ThreatModel.room_threat(layout, fight)
	var errors := DungeonValidator.validate(layout, d2)
	_check(_has_error(errors, "exceeds its budget") and not _has_error(errors, "recorded threat"),
			"detects a fight over its threat budget")

	layout = _find(2, RoomRole.COMBAT)
	fight = _room_with_role(layout, RoomRole.COMBAT)
	fight.threat -= 1.0
	_check(_has_error(DungeonValidator.validate(layout, d2), "recorded threat"), "detects a tampered threat record")

	layout = _find(2, RoomRole.COMBAT)
	var stingy := d2.duplicate() as DepthProfile
	stingy.floor_threat_budget = 5.0
	_check(_has_error(DungeonValidator.validate(layout, stingy), "floor threat"), "detects a floor over its threat budget")

	# A risk route may never be required: marking the timed spike strips of a
	# main-path trap gallery entered from its west or east end (the strips span
	# the hall between the end doors and the centre) as "risk" must break it.
	var crosses_strip := func(r: DungeonLayout.PlacedRoom) -> bool:
		for d in r.doors:
			if d.side == RoomShape.Side.WEST or d.side == RoomShape.Side.EAST:
				return true
		return false
	layout = _find(1, RoomRole.HAZARD, &"trap_gallery", true, crosses_strip)
	if layout != null:
		for room in layout.rooms:
			if room.template.id == &"trap_gallery" and layout.graph.main_path.has(room.id) and crosses_strip.call(room):
				for hazard in room.hazards:
					hazard.purpose = RoomRole.PURPOSE_RISK_ROUTE
		errors = DungeonValidator.validate(layout, d1)
		_check(_has_error(errors, "unreachable") or _has_error(errors, "cut off"), "detects a risky route that is mandatory")
	else:
		_check(false, "found a floor with a trap gallery on the main path")

	layout = _find(2, RoomRole.REWARD)
	var dead_end := _room_with_role(layout, RoomRole.REWARD, DungeonGraph.Role.DEAD_END)
	dead_end.tactic = RoomRole.AMBUSH
	dead_end.encounter = DungeonGraph.Encounter.AMBUSH
	_check(dead_end.doors.size() == 1 and _has_error(DungeonValidator.validate(layout, d2), "no alternate exit"),
			"detects an ambush without an escape route")

	layout = _find(1, RoomRole.COMBAT)
	fight = _room_with_role(layout, RoomRole.COMBAT)
	layout.set_tile(fight.spawn_candidates[0] + Vector2i(1, 0), DungeonLayout.Tile.PIT, fight.id)
	_check(_has_error(DungeonValidator.validate(layout, d1), "invalid spawn point"), "detects an enemy spawn beside a pit")

	layout = _find(1, RoomRole.COMBAT)
	fight = _room_with_role(layout, RoomRole.COMBAT)
	var patch: Array[Vector2i] = [fight.spawn_candidates[0]]
	layout.set_tile(patch[0], DungeonLayout.Tile.HAZARD, fight.id)
	fight.hazards.append({"type": &"spikes", "tiles": patch, "authored": false, "purpose": &""})
	_check(_has_error(DungeonValidator.validate(layout, d1), "without a valid purpose"), "detects a hazard without a purpose")

	layout = _find(1, RoomRole.COMBAT)
	for i in range(1, 4):
		var room := layout.rooms[layout.graph.main_path[i]]
		if room.role == DungeonGraph.Role.MAIN:
			room.tactic = RoomRole.COMBAT
	_check(_has_error(DungeonValidator.validate(layout, d1), "in a row"), "detects fights stacked back to back (pacing)")

	layout = _find(1, RoomRole.REST)
	var rest := _room_with_role(layout, RoomRole.REST)
	var rest_patch: Array[Vector2i] = [rest.anchor + Vector2i(3, 0)]
	layout.set_tile(rest_patch[0], DungeonLayout.Tile.HAZARD, rest.id)
	rest.hazards.append({"type": &"spikes", "tiles": rest_patch, "authored": false, "purpose": RoomRole.PURPOSE_TIMING})
	_check(_has_error(DungeonValidator.validate(layout, d1), "rest room %d is not safe" % rest.id), "detects an unsafe rest room")

	layout = _find(1, RoomRole.TRAVERSAL)
	_room_with_role(layout, RoomRole.TRAVERSAL).tactic = RoomRole.HAZARD_COMBAT
	_check(_has_error(DungeonValidator.validate(layout, d1), "not allowed at depth 1"), "detects a role the depth has not unlocked")

	layout = _find(1, RoomRole.COMBAT)
	fight = _room_with_role(layout, RoomRole.COMBAT)
	# More enemies than any arena has room for (the space rule, not the cap).
	for i in 40:
		fight.enemy_ids.append(&"chaser")
	_check(_has_error(DungeonValidator.validate(layout, d1), "maneuvering space"), "detects a fight without maneuvering space")

	layout = _find(2, RoomRole.RISK_REWARD)
	var risk := _room_with_role(layout, RoomRole.RISK_REWARD)
	var cache: Vector2i = risk.markers[0].tile
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				layout.set_tile(cache + Vector2i(dx, dy), DungeonLayout.Tile.INNER_WALL, risk.id)
	errors = DungeonValidator.validate(layout, d2)
	_check(_has_error(errors, "cannot be reached") or _has_error(errors, "cache marker"), "detects a risk cache that cannot be reached")

	layout = _find(2, RoomRole.RISK_REWARD)
	risk = _room_with_role(layout, RoomRole.RISK_REWARD)
	for hazard in risk.hazards:
		hazard.purpose = RoomRole.PURPOSE_TIMING
	_check(_has_error(DungeonValidator.validate(layout, d2), "no visible risk"), "detects a risk room without a risk")

	layout = _find(3, RoomRole.HAZARD_COMBAT)
	_room_with_role(layout, RoomRole.HAZARD_COMBAT).recipe = &"open_brawl"
	_check(_has_error(DungeonValidator.validate(layout, d3), "no terrain interaction"), "detects a hazard fight without a terrain interaction")

	layout = _find(1, RoomRole.COMBAT)
	for room in layout.rooms:
		if RoomRole.is_heavy(room.tactic) and room.role == DungeonGraph.Role.MAIN:
			room.tactic = RoomRole.TRAVERSAL
			room.encounter = DungeonGraph.Encounter.NONE
			room.enemy_ids.clear()
			room.threat = 0.0
	_check(_has_error(DungeonValidator.validate(layout, d1), "fights on the main path"), "detects a floor below its minimum fights")

	layout = _find(2, RoomRole.CHALLENGE)
	_room_with_role(layout, RoomRole.CHALLENGE).markers.clear()
	_check(_has_error(DungeonValidator.validate(layout, d2), "guards no reward"), "detects a challenge without its reward")

	# Placement (SpawnPlanner): a recipe whose lead enemy can no longer start
	# where its terrain matters (every spawn that would realize it removed).
	layout = _find(3, RoomRole.HAZARD_COMBAT, &"", false,
			func(r: DungeonLayout.PlacedRoom) -> bool: return SpawnPlanner.INTENTS.has(r.recipe))
	var placed := _room_with_recipe_intent(layout)
	var approach := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, placed))
	var lead_intent := SpawnPlanner.intent_at(placed, 0) if SpawnPlanner.intent_at(placed, 0) != &"" else SpawnPlanner.intent_at(placed, 1)
	var kept: Array[Vector2i] = []
	for t in placed.spawn_candidates:
		if not SpawnPlanner.satisfies(layout, lead_intent, t, approach):
			kept.append(t)
	placed.spawn_candidates = kept
	_check(_has_error(DungeonValidator.validate(layout, d3), "where the terrain matters"),
			"detects a recipe whose tactic is only a label (%s, intent %s)" % [placed.recipe, lead_intent])

	# Two ranged enemies in a room without cover: unavoidable crossfire.
	var crossfire_found := false
	for s in 60:
		layout = DungeonGenerator.new().generate(d3, 8800 + s, 3).layout
		var strict := DungeonValidator.clear_mask(layout, false)
		for room in layout.rooms:
			if room.encounter != DungeonGraph.Encounter.NONE and not ThreatModel.features(layout, room, strict).cover:
				var two: Array[StringName] = [&"spitter", &"spitter"]
				room.enemy_ids = two
				crossfire_found = true
				break
		if crossfire_found:
			break
	_check(crossfire_found and _has_error(DungeonValidator.validate(layout, d3), "unavoidable crossfire"),
			"detects ranged crossfire in a room without cover")

	# A spitter whose every spawn point is within reach of the approach doorway:
	# fair for a melee enemy, an unavoidable shot for a ranged one.
	layout = _find(3, RoomRole.COMBAT, &"", false,
			func(r: DungeonLayout.PlacedRoom) -> bool: return r.enemy_ids.has(&"spitter"))
	var shooter: DungeonLayout.PlacedRoom = null
	for room in layout.rooms:
		if room.enemy_ids.has(&"spitter"):
			shooter = room
			break
	var from := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, shooter))
	var close: Array[Vector2i] = []
	var sb := shooter.bounds()
	for y in range(sb.position.y, sb.end.y):
		for x in range(sb.position.x, sb.end.x):
			var t := Vector2i(x, y)
			var d := layout.tile_center(t).distance_to(from)
			if layout.get_owner_of(t) == shooter.id and layout.is_clear(t) \
					and d >= SpawnPlanner.MIN_SPAWN_DISTANCE and d < SpawnPlanner.RANGED_MIN_DISTANCE:
				close.append(t)
	shooter.spawn_candidates = close
	_check(close.size() >= shooter.enemy_ids.size()
			and _has_error(DungeonValidator.validate(layout, d3), "unavoidable shot"),
			"detects a ranged enemy that starts too close to react to (%d close tiles)" % close.size())
	return true


func _room_with_recipe_intent(layout: DungeonLayout) -> DungeonLayout.PlacedRoom:
	for room in layout.rooms:
		if room.tactic == RoomRole.HAZARD_COMBAT and SpawnPlanner.INTENTS.has(room.recipe):
			return room
	return null


## First generated floor (fixed seed scan) with a room of `role` (and, if
## given, that template, optionally on the main path).
func _find(depth: int, role: int, template_id: StringName = &"", on_main_path: bool = false,
		room_test: Callable = Callable()) -> DungeonLayout:
	var profile := DepthProfile.load_for_depth(depth)
	for s in 400:
		var layout := DungeonGenerator.new().generate(profile, 8800 + s, depth).layout
		for room in layout.rooms:
			if room.tactic != role:
				continue
			if template_id != &"" and room.template.id != template_id:
				continue
			if on_main_path and not layout.graph.main_path.has(room.id):
				continue
			if room_test.is_valid() and not room_test.call(room):
				continue
			return layout
	return null


func _room_with_role(layout: DungeonLayout, role: int, graph_role: int = -1) -> DungeonLayout.PlacedRoom:
	for room in layout.rooms:
		if room.tactic == role and (graph_role < 0 or room.role == graph_role):
			return room
	return null


func _layout_with_template(template_id: StringName) -> DungeonLayout:
	var profile := DepthProfile.load_for_depth(1)
	for s in 200:
		var layout := DungeonGenerator.new().generate(profile, s, 1).layout
		for room in layout.rooms:
			if room.template.id == template_id:
				return layout
	return null


func _tiles_of(layout: DungeonLayout, kind: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in layout.size.y:
		for x in layout.size.x:
			if layout.get_tile(Vector2i(x, y)) == kind:
				result.append(Vector2i(x, y))
	return result


func _room_with_spawns(layout: DungeonLayout) -> DungeonLayout.PlacedRoom:
	for room in layout.rooms:
		if not room.spawn_candidates.is_empty():
			return room
	return null


## A deliberately hostile (but lint-clean) template: its hazard socket touches
## the anchor, where the player spawns / markers sit. Content placement must
## refuse it every time, so optional hazards can never make a floor invalid,
## whatever a template's sockets look like. (Oversized hazard areas are caught
## by template lint and by the validator; see the negatives test.)
func _test_hazards_never_break_floors() -> bool:
	var hostile := RoomTemplate.new()
	hostile.id = &"test_hazard_at_anchor"
	hostile.roles = PackedStringArray(["main", "branch", "dead_end"])
	hostile.size_class = 0
	hostile.layout = "\n".join(PackedStringArray([
		"####DDD#####",
		"#..........#",
		"#.E......E.#",
		"D..........D",
		"D...HHC....D",
		"D..........D",
		"#..........#",
		"#..........#",
		"#.E......E.#",
		"#..........#",
		"####DDD#####",
	]))
	_check(hostile.get_shape().errors.is_empty(), "hostile fixture template is lint-clean %s" % hostile.get_shape().errors)
	# Hazard sockets are only filled in terrain rooms: offer the hostile room to
	# those roles (and weight it heavily) at the depth that uses them all.
	hostile.roles = PackedStringArray(["main", "branch", "dead_end", "arena", "environmental"])
	hostile.weight = 6.0
	var profile := DepthProfile.load_for_depth(3).duplicate() as DepthProfile
	var templates: Array[RoomTemplate] = profile.room_templates.duplicate()
	templates.append(hostile)
	profile.room_templates = templates
	profile.hazard_density = 1.0
	var offered := 0
	var kept_bands := 0
	for seed_value in 60:
		for attempt in 3:
			var layout := DungeonGenerator.new().generate_attempt(profile, seed_value, 3, attempt)
			for room in layout.rooms:
				if room.template == hostile and RoomRole.wants_terrain(room.planned_tactic):
					offered += 1
					kept_bands += room.hazards.size()
	var failures := 0
	var accepted_hostile_terrain := 0
	for seed_value in 40:
		var result := DungeonGenerator.new().generate(profile, seed_value, 3)
		if not result.ok:
			failures += 1
			continue
		for room in result.layout.rooms:
			if room.template == hostile and RoomRole.wants_terrain(room.tactic):
				accepted_hostile_terrain += 1
	_check(offered > 20 and kept_bands == 0,
			"the unsafe hazard is refused in all %d terrain rooms that offered it (%d kept)" % [offered, kept_bands])
	_check(failures == 0 and accepted_hostile_terrain == 0,
			"floors stay valid with an anchor-touching hazard socket at density 1.0 (%d failed); a terrain room left without terrain is never accepted (%d)" % [
				failures, accepted_hostile_terrain])

	# The placer's own size limit (template lint normally prevents oversized
	# regions, so exercise the placer directly). Control: the first
	# MAX_TIMED_REGION tiles of the run are accepted, so only size rejects the rest.
	var tested := 0
	var accepted_short := 0
	var refused_long := 0
	for seed_value in 20:
		var layout := DungeonGenerator.new().generate(DepthProfile.load_for_depth(1), 9100 + seed_value, 1).layout
		for room in layout.rooms:
			var run := _long_safe_floor_run(layout, room, RoomShape.MAX_TIMED_REGION + 2)
			if run.is_empty():
				continue
			for i in RoomShape.MAX_TIMED_REGION:
				layout.set_tile(run[i], DungeonLayout.Tile.HAZARD, room.id)
			var short_ok := ContentPlacer.hazard_keeps_room_intact(layout, room)
			for t in run:
				layout.set_tile(t, DungeonLayout.Tile.HAZARD, room.id)
			var long_ok := ContentPlacer.hazard_keeps_room_intact(layout, room)
			for t in run:
				layout.set_tile(t, DungeonLayout.Tile.FLOOR, room.id)
			if not short_ok:
				continue
			tested += 1
			accepted_short += 1
			if not long_ok:
				refused_long += 1
	_check(tested >= 10 and refused_long == accepted_short,
			"the placer refuses spike runs longer than %d tiles (%d of %d refused)" % [
				RoomShape.MAX_TIMED_REGION, refused_long, tested])
	return true


## A horizontal run of plain room floor of at least `length` tiles, away from
## the room's anchor row and hazards (empty if the room has none).
func _long_safe_floor_run(layout: DungeonLayout, room: DungeonLayout.PlacedRoom, length: int) -> Array[Vector2i]:
	var bounds := room.bounds()
	for y in range(bounds.position.y + 2, bounds.end.y - 2):
		if absi(y - room.anchor.y) <= 2:
			continue
		var run: Array[Vector2i] = []
		for x in range(bounds.position.x, bounds.end.x):
			var t := Vector2i(x, y)
			if layout.get_tile(t) == DungeonLayout.Tile.FLOOR and layout.get_owner_of(t) == room.id:
				run.append(t)
				if run.size() >= length:
					return run
			else:
				run.clear()
	return []


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for e in errors:
		if e.contains(fragment):
			return true
	return false


func _test_retry_and_failure() -> bool:
	var profile := DepthProfile.load_for_depth(1)
	var normal := DungeonGenerator.new().generate(profile, 555, 1)
	var forced := DungeonGenerator.new()
	forced.debug_forced_failures = 3
	var retried := forced.generate(profile, 555, 1)
	var retried_again := forced.generate(profile, 555, 1)
	_check(retried.ok and retried.attempts >= 4 and retried.layout.attempt >= 3,
			"after failed attempts the generator retries (attempt %d)" % retried.layout.attempt)
	_check(retried.layout.fingerprint() == retried_again.layout.fingerprint(), "retries are deterministic")
	_check(retried.layout.fingerprint() != normal.layout.fingerprint(), "a retry is a genuinely different attempt")
	_check(retried.failure_log.size() == retried.attempts - 1, "each failed attempt is logged")
	var impossible := profile.duplicate() as DepthProfile
	impossible.grid_columns = 2
	impossible.grid_rows = 2
	impossible.main_path_min = 8
	impossible.main_path_max = 8
	var failed := DungeonGenerator.new().generate(impossible, 1, 1)
	_check(not failed.ok and failed.attempts == DungeonGenerator.MAX_ATTEMPTS
			and failed.failure_log.size() == DungeonGenerator.MAX_ATTEMPTS,
			"an impossible profile fails safely after %d attempts" % DungeonGenerator.MAX_ATTEMPTS)
	return true


## Builds real worlds and moves a player-sized body along the validated
## clearance path from the entry to the exit and to every room, using physics
## test_move: the collision geometry must match the tile data.
func _test_physical_traversal() -> bool:
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = 1
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var node := CollisionShape2D.new()
	node.shape = shape
	probe.add_child(node)
	root.add_child(probe)
	var floors := 0
	var segments := 0
	var blocked := 0
	var pit_steps := 0
	var risk_steps := 0
	var plans := [[1, traversal_seeds_depth_1], [2, traversal_seeds_depth_2], [3, traversal_seeds_depth_3]]
	for plan: Array in plans:
		var profile := DepthProfile.load_for_depth(plan[0])
		for i in int(plan[1]):
			var layout := DungeonGenerator.new().generate(profile, 900 + i, plan[0]).layout
			var world := DungeonBuilder.build(layout)
			root.add_child(world)
			await physics_frame
			await physics_frame
			# Required routes may cross timed spikes (safe window), never pits,
			# and never the tiles of an optional risky route.
			var clear := DungeonValidator.required_mask(layout)
			var risk := {}
			for room in layout.rooms:
				for t in room.risk_tiles():
					risk[t] = true
			var parents := _bfs_parents(layout, clear, layout.player_spawn)
			var targets: Array[Vector2i] = [layout.exit_tile]
			for room in layout.rooms:
				targets.append(room.anchor)
			for target in targets:
				var path := _path_to(layout, parents, target)
				if path.is_empty():
					blocked += 1
					continue
				for k in range(1, path.size()):
					if layout.get_tile(path[k]) == DungeonLayout.Tile.PIT:
						pit_steps += 1
					if risk.has(path[k]):
						risk_steps += 1
					var from := layout.tile_center(path[k - 1])
					probe.global_position = from
					segments += 1
					if probe.test_move(probe.global_transform, layout.tile_center(path[k]) - from):
						blocked += 1
			floors += 1
			world.free()
	probe.free()
	print("    %d floors, %d path segments swept with a player-sized body" % [floors, segments])
	_check(blocked == 0, "entry -> exit and entry -> every room are physically walkable (%d blocked)" % blocked)
	_check(pit_steps == 0, "no required route steps over a pit (%d)" % pit_steps)
	_check(risk_steps == 0, "no required route crosses an optional risky route (%d)" % risk_steps)
	return true


func _bfs_parents(layout: DungeonLayout, mask: PackedByteArray, start: Vector2i) -> PackedInt32Array:
	var w := layout.size.x
	var parents := PackedInt32Array()
	parents.resize(mask.size())
	parents.fill(-1)
	var s := layout.index_of(start)
	parents[s] = s
	var queue := PackedInt32Array([s])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for n in [i - 1, i + 1, i - w, i + w]:
			if n >= 0 and n < mask.size() and mask[n] == 1 and parents[n] == -1:
				parents[n] = i
				queue.append(n)
	return parents


func _path_to(layout: DungeonLayout, parents: PackedInt32Array, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var i := layout.index_of(target)
	if parents[i] == -1:
		return path
	while true:
		path.push_front(Vector2i(i % layout.size.x, i / layout.size.x))
		if parents[i] == i:
			break
		i = parents[i]
	return path


## Whichever doorway the player uses, the room can place all its enemies at
## least MIN_SPAWN_DISTANCE away from where the player triggers it.
func _test_runtime_spawn_choice() -> bool:
	var checks := 0
	var bad := 0
	var mismatched := 0
	var ranged_close := 0
	var intent_rooms := {}
	var realized_approach := {}
	var realized_any_door := {}
	var door_checks := {}
	var door_realized := {}
	var sniper_sight := 0
	var sniper_rooms := 0
	for depth in [1, 2, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		for i in (25 if depth < 3 else 120):
			var layout := DungeonGenerator.new().generate(profile, 3000 + i, depth).layout
			var actors := Node2D.new()
			var navigation: DungeonNavigation = null
			for data in layout.rooms:
				if data.encounter == DungeonGraph.Encounter.NONE:
					continue
				var room := DungeonRoom.new()
				room.setup(data, layout, actors)
				var recipe_has_intent := SpawnPlanner.INTENTS.has(data.recipe)
				for door in data.doors:
					var trigger_point := SpawnPlanner.entry_point(layout, door)
					var points := room.choose_spawn_points(trigger_point)
					var plan := SpawnPlanner.plan(layout, data, trigger_point)
					checks += 1
					var ok := points.size() == data.enemy_ids.size()
					for k in points.size():
						var p := points[k]
						ok = ok and p.distance_to(trigger_point) >= DungeonValidator.MIN_SPAWN_DISTANCE \
							and layout.room_at_tile(Vector2i(p / DungeonLayout.TILE_SIZE)) == data
						if k >= plan.size() or layout.tile_center(plan[k]) != p:
							mismatched += 1
						if EnemyCatalog.has_tag(data.enemy_ids[k], &"ranged") \
								and p.distance_to(trigger_point) < SpawnPlanner.RANGED_MIN_DISTANCE:
							ranged_close += 1
					if not ok:
						bad += 1
					if recipe_has_intent:
						door_checks[data.recipe] = door_checks.get(data.recipe, 0) + 1
						if SpawnPlanner.realizes(layout, data, trigger_point, plan):
							door_realized[data.recipe] = door_realized.get(data.recipe, 0) + 1
							realized_any_door[data.recipe] = true
				if recipe_has_intent:
					intent_rooms[data.recipe] = intent_rooms.get(data.recipe, 0) + 1
					var approach := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, data))
					var approach_plan := SpawnPlanner.plan(layout, data, approach)
					if SpawnPlanner.realizes(layout, data, approach, approach_plan):
						realized_approach[data.recipe] = realized_approach.get(data.recipe, 0) + 1
					if data.recipe == &"sniper_nest":
						# The runtime spitter really has a shot across the chasm/pool.
						sniper_rooms += 1
						var si := data.enemy_ids.find(&"spitter")
						if navigation == null:
							navigation = DungeonNavigation.new(layout)
						if navigation.clear_sight(layout.tile_center(approach_plan[si]), approach):
							sniper_sight += 1
				room.free()
			actors.free()
	_check(bad == 0, "every encounter/doorway combination spawns all enemies far from the player (%d checked)" % checks)
	_check(mismatched == 0, "runtime spawn points are exactly the generation-time SpawnPlanner plan (%d mismatches)" % mismatched)
	_check(ranged_close == 0, "no ranged enemy ever starts within %d px of the player, from any doorway (%d)" % [
		SpawnPlanner.RANGED_MIN_DISTANCE, ranged_close])
	var all_realized := true
	var lines := PackedStringArray()
	for recipe: StringName in SpawnPlanner.INTENTS:
		var n: int = intent_rooms.get(recipe, 0)
		all_realized = all_realized and n > 0 and realized_approach.get(recipe, 0) == n
		lines.append("%s %d/%d (any door %d%%)" % [recipe, realized_approach.get(recipe, 0), n,
			roundi(100.0 * door_realized.get(recipe, 0) / maxi(door_checks.get(recipe, 0), 1))])
	_check(all_realized, "every terrain recipe puts its lead enemy where the terrain matters, from the approach doorway: %s" % ", ".join(lines))
	_check(sniper_rooms > 0 and sniper_sight == sniper_rooms,
			"sniper_nest spitters have a clear shot across the terrain at the approach (%d/%d)" % [sniper_sight, sniper_rooms])
	return true


## Dungeon density (M2.2 play-test polish): rooms are furnished by purpose,
## corridors get alcoves and decor, and big empty floor is gone, while every
## floor still validates (reachability, lanes, spawns and maneuvering space are
## checked by the validator on every accepted floor above).
func _test_density() -> bool:
	var floors := 0
	var open := 0
	var floor_tiles := 0
	var entry_open := 0
	var entry_tiles := 0
	var with_structure := 0
	var with_alcoves := 0
	var with_decor := 0
	var forbidden_dressing := 0
	var dressed_by_role := {}
	var sockets_by_role := {}
	for depth in [1, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		for s in 40:
			var layout := DungeonGenerator.new().generate(profile, 6100 + s, depth).layout
			floors += 1
			var pieces := 0
			for room in layout.rooms:
				pieces += room.dressing.size()
				var role := RoomRole.name_of(room.tactic)
				dressed_by_role[role] = dressed_by_role.get(role, 0) + room.dressing.size()
				sockets_by_role[role] = sockets_by_role.get(role, 0) + room.shape.dressing_regions.size()
				if not room.dressing.is_empty() and RoomRole.dressing_density(room.tactic) <= 0.0:
					forbidden_dressing += 1
				var counts := _open_field(layout, room)
				open += counts.x
				floor_tiles += counts.y
				if room.tactic == RoomRole.ENTRY:
					entry_open += counts.x
					entry_tiles += counts.y
			var alcoves := 0
			for corridor in layout.corridors:
				alcoves += corridor.alcoves.size()
			with_structure += int(pieces > 0)
			with_alcoves += int(alcoves > 0)
			with_decor += int(layout.decor.size() >= 40)
	var share := 100.0 * open / floor_tiles
	var entry_share := 100.0 * entry_open / entry_tiles
	print("    open-field share %.1f%% (entry hall %.1f%%); structure used/offered by role %s / %s" % [
		share, entry_share, dressed_by_role, sockets_by_role])
	_check(share <= 9.0, "little pointless open floor: %.1f%% of room floor is a 7x7 empty field (was ~13%%)" % share)
	_check(entry_share <= 15.0, "the entry hall is composed, not an empty box (%.1f%% open field, was 43%%)" % entry_share)
	_check(with_structure == floors, "every floor has optional structure in its rooms (%d/%d)" % [with_structure, floors])
	_check(with_alcoves >= floors * 0.8, "corridors have alcoves in >= 80%% of floors (%d/%d)" % [with_alcoves, floors])
	_check(with_decor == floors, "every floor has decor (>= 40 items) (%d/%d)" % [with_decor, floors])
	_check(forbidden_dressing == 0, "risk rooms and story chambers are never dressed (%d)" % forbidden_dressing)
	var quiet := float(dressed_by_role.get("TRAVERSAL", 0)) / maxi(sockets_by_role.get("TRAVERSAL", 0), 1)
	var fights := float(dressed_by_role.get("COMBAT", 0)) / maxi(sockets_by_role.get("COMBAT", 0), 1)
	_check(quiet > fights, "quiet rooms are furnished more than fight arenas (%.0f%% vs %.0f%% of sockets)" % [100 * quiet, 100 * fights])
	return true


## (open-field tiles, plain floor tiles) of a room: a floor tile is open field
## when nothing but plain floor lies within 3 tiles.
func _open_field(layout: DungeonLayout, room: DungeonLayout.PlacedRoom) -> Vector2i:
	var open := 0
	var total := 0
	var b := room.bounds()
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var t := Vector2i(x, y)
			if layout.get_owner_of(t) != room.id or layout.get_tile(t) != DungeonLayout.Tile.FLOOR:
				continue
			total += 1
			var empty := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					empty = empty and layout.get_tile(t + Vector2i(dx, dy)) == DungeonLayout.Tile.FLOOR
			open += int(empty)
	return Vector2i(open, total)


## The validator catches broken composition: structure at a doorway, next to
## terrain, in a room that must stay clean; a blocked corridor lane; decor on
## terrain or on a socket.
func _test_density_negatives() -> bool:
	var d1 := DepthProfile.load_for_depth(1)
	var d3 := DepthProfile.load_for_depth(3)
	var layout := _find(1, RoomRole.TRAVERSAL, &"", false,
			func(r: DungeonLayout.PlacedRoom) -> bool: return not r.dressing.is_empty())
	_check(DungeonValidator.validate(layout, d1).is_empty(), "density baseline floor validates")
	var room := _room_with_dressing(layout)
	var door: Dictionary = room.doors[0]
	var at_door: Array[Vector2i] = [door.inside - RoomShape.SIDE_VECTORS[door.side]]
	layout.set_tile(at_door[0], DungeonLayout.Tile.RUBBLE, room.id)
	room.dressing.append({"kind": DungeonLayout.Tile.RUBBLE, "tiles": at_door})
	_check(_has_error(DungeonValidator.validate(layout, d1), "crowds a doorway"), "detects structure crowding a doorway")

	layout = _find(1, RoomRole.TRAVERSAL, &"", false,
			func(r: DungeonLayout.PlacedRoom) -> bool: return not r.dressing.is_empty())
	room = _room_with_dressing(layout)
	var piece: Dictionary = room.dressing[0]
	var beside: Vector2i = piece.tiles[0] + Vector2i(0, 1)
	if layout.get_tile(beside) != DungeonLayout.Tile.FLOOR:
		beside = piece.tiles[0] + Vector2i(1, 0)
	layout.set_tile(beside, DungeonLayout.Tile.WATER, room.id)
	_check(_has_error(DungeonValidator.validate(layout, d1), "touches terrain"), "detects structure touching terrain")

	layout = _find(1, RoomRole.TRAVERSAL, &"", false,
			func(r: DungeonLayout.PlacedRoom) -> bool: return not r.dressing.is_empty())
	room = _room_with_dressing(layout)
	room.tactic = RoomRole.STORY
	_check(_has_error(DungeonValidator.validate(layout, d1), "structure dressing in a STORY room"),
			"detects structure in a room that must stay as authored")

	layout = DungeonGenerator.new().generate(d3, 6200, 3).layout
	var lane_tile := layout.corridors[0].rects[0].get_center()
	layout.set_tile(lane_tile, DungeonLayout.Tile.RUBBLE, DungeonLayout.CORRIDOR_OWNER_BASE + layout.corridors[0].link)
	_check(_has_error(DungeonValidator.validate(layout, d3), "lane tile"), "detects rubble in a corridor lane")

	layout = DungeonGenerator.new().generate(d3, 6201, 3).layout
	var socket_decor := {"kind": &"bones", "tile": layout.player_spawn}
	layout.decor.append(socket_decor)
	_check(_has_error(DungeonValidator.validate(layout, d3), "decor:"), "detects decor on a socket (the player spawn)")
	var hazard_tile := Vector2i(-1, -1)
	for r in layout.rooms:
		for hazard in r.hazards:
			hazard_tile = hazard.tiles[0]
	if hazard_tile.x < 0:
		hazard_tile = _tiles_of(layout, DungeonLayout.Tile.WATER)[0]
	layout.decor.erase(socket_decor)
	layout.decor.append({"kind": &"crack", "tile": hazard_tile})
	_check(_has_error(DungeonValidator.validate(layout, d3), "decor:"), "detects decor on terrain")
	layout.decor.pop_back()
	layout.decor.append({"kind": &"torch", "tile": layout.player_spawn})
	_check(_has_error(DungeonValidator.validate(layout, d3), "torch socket"), "detects a torch socket off the wall")
	return true


func _room_with_dressing(layout: DungeonLayout) -> DungeonLayout.PlacedRoom:
	for room in layout.rooms:
		if room.tactic == RoomRole.TRAVERSAL and not room.dressing.is_empty():
			return room
	return null


## SpawnPlanner seeks out the candidate that realizes an intent, wherever it
## sits in the seeded order: with every non-satisfying candidate moved to the
## front, the plan from the approach doorway must still realize the recipe.
func _test_spawn_planner_seeks_intent() -> bool:
	var profile := DepthProfile.load_for_depth(3)
	var rooms := 0
	var realized := 0
	for s in 60:
		var layout := DungeonGenerator.new().generate(profile, 4100 + s, 3).layout
		for room in layout.rooms:
			if not SpawnPlanner.INTENTS.has(room.recipe):
				continue
			var from := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, room))
			var lead := 0
			while SpawnPlanner.intent_at(room, lead) == &"":
				lead += 1
			var intent := SpawnPlanner.intent_at(room, lead)
			var reordered: Array[Vector2i] = []
			for t in room.spawn_candidates:
				if not SpawnPlanner.satisfies(layout, intent, t, from):
					reordered.append(t)
			for t in room.spawn_candidates:
				if SpawnPlanner.satisfies(layout, intent, t, from):
					reordered.append(t)
			room.spawn_candidates = reordered
			rooms += 1
			if SpawnPlanner.realizes(layout, room, from, SpawnPlanner.plan(layout, room, from)):
				realized += 1
	_check(rooms > 0 and realized == rooms,
			"the planner finds the intent's spawn point even when it comes last in the seeded order (%d/%d rooms)" % [realized, rooms])
	return true


## Enemies must be able to walk (around walls, over water and spikes, never
## over pits) from every spawn point to every doorway of their room.
func _test_enemy_navigation_reach() -> bool:
	var checks := 0
	var unreachable := 0
	for depth in [1, 2, 3]:
		var profile := DepthProfile.load_for_depth(depth)
		for i in 20:
			var layout := DungeonGenerator.new().generate(profile, 5000 + i, depth).layout
			var nav := DungeonNavigation.new(layout)
			for room in layout.rooms:
				for spawn in room.spawn_candidates:
					for door in room.doors:
						checks += 1
						var inside: Vector2i = door["inside"]
						if nav.path(layout.tile_center(spawn), layout.tile_center(inside)).is_empty():
							unreachable += 1
	_check(unreachable == 0, "enemy navigation reaches every doorway from every spawn (%d paths checked)" % checks)
	return true


func _test_build_performance() -> bool:
	var profile := DepthProfile.load_for_depth(3)
	var max_nodes := 0
	var max_shapes := 0
	var max_build := 0.0
	var max_nav := 0.0
	for i in 10:
		var layout := DungeonGenerator.new().generate(profile, 7000 + i, 3).layout
		var nav_started := Time.get_ticks_usec()
		DungeonNavigation.new(layout)
		max_nav = maxf(max_nav, (Time.get_ticks_usec() - nav_started) / 1000.0)
		var started := Time.get_ticks_usec()
		var world := DungeonBuilder.build(layout)
		max_build = maxf(max_build, (Time.get_ticks_usec() - started) / 1000.0)
		max_nodes = maxi(max_nodes, _count_nodes(world))
		max_shapes = maxi(max_shapes, world.wall_shape_count)
		world.free()
	print("    depth 3 worlds: max %d nodes, max %d wall shapes, max build %.1f ms (navigation grid alone max %.1f ms)" % [
		max_nodes, max_shapes, max_build, max_nav])
	_check(max_nodes < 600, "built worlds stay under 600 nodes (%d)" % max_nodes)
	_check(max_shapes < 1500, "wall collision stays under 1500 merged shapes (%d)" % max_shapes)
	_check(max_build < 500.0, "building a world takes under 500 ms (%.1f)" % max_build)
	return true


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
