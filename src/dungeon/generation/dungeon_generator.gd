class_name DungeonGenerator
extends RefCounted
## Deterministic floor generation:
##   seed -> graph -> pacing (room roles) -> layout (templates, placement,
##   corridors) -> content (hazards, tactics, threat) -> validation -> accepted layout
## Attempt k uses streams derived from (version, seed, depth, k). If attempt k
## fails construction or validation, attempt k+1 runs; the same inputs always
## take the same attempts and give the same result. After MAX_ATTEMPTS the
## result is a failure (never a broken dungeon).
##
## Bump GENERATOR_VERSION whenever a change alters output for existing seeds;
## the golden-seed test pins the current output.

## v2 (Milestone 2.1): structural variants, interior geometry, water, pits,
## bridges, authored spikes, event sockets, pacing (environmental rooms).
## v3 (Milestone 2.2): PacingDirector room roles ("pacing" stream), role-based
## templates/variants, TacticalComposer encounters ("tactics" stream) under a
## ThreatModel budget, hazard purposes, risk/reward rooms, heal/cache/power
## sockets, tactical validation.
## v4 (Milestone 2.2): SpawnPlanner placement intents (recipes put their lead
## enemies where the terrain matters; ranged fairness), composer skips recipes
## that cannot be placed fairly or realized.
## v5 (M2.2 play-test polish): optional structure sockets ("dressing" stream),
## room size by purpose, corridor alcoves ("corridor_dressing"), decor ("decor").
const GENERATOR_VERSION := 5
const MAX_ATTEMPTS := 24


class Result:
	var ok: bool = false
	var layout: DungeonLayout
	## Attempts used, including the successful one.
	var attempts: int = 0
	## One line per failed attempt: "attempt N: <first error>".
	var failure_log: PackedStringArray = []
	var msec: float = 0.0


## Test hook: treat the first N attempts as failed, to exercise the retry path.
var debug_forced_failures: int = 0


func generate(profile: DepthProfile, run_seed: int, depth: int) -> Result:
	var result := Result.new()
	var started := Time.get_ticks_usec()
	for attempt in MAX_ATTEMPTS:
		result.attempts = attempt + 1
		var layout := generate_attempt(profile, run_seed, depth, attempt)
		if layout.errors.is_empty() and attempt < debug_forced_failures:
			layout.errors.append("forced failure (test hook)")
		if layout.errors.is_empty():
			result.ok = true
			result.layout = layout
			break
		result.failure_log.append("attempt %d: %s" % [attempt, layout.errors[0]])
		result.layout = layout
	result.msec = (Time.get_ticks_usec() - started) / 1000.0
	return result


## One full attempt, validated. Errors (if any) are in layout.errors.
func generate_attempt(profile: DepthProfile, run_seed: int, depth: int, attempt: int) -> DungeonLayout:
	var streams := SeedStreams.new(run_seed, depth, attempt, GENERATOR_VERSION)
	var graph := GraphBuilder.build(profile, streams.stream("graph"))
	var layout: DungeonLayout
	if graph.error.is_empty():
		PacingDirector.direct(graph, profile, streams.stream("pacing"))
		layout = LayoutBuilder.build(graph, profile, streams)
		if layout.errors.is_empty():
			ContentPlacer.place(layout, profile, streams)
			layout.errors = DungeonValidator.validate(layout, profile)
	else:
		layout = DungeonLayout.new()
		layout.graph = graph
		layout.errors.append("graph: " + graph.error)
	layout.run_seed = run_seed
	layout.depth = depth
	layout.attempt = attempt
	layout.generator_version = GENERATOR_VERSION
	return layout
