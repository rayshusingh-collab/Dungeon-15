class_name SpawnPlacer
extends RefCounted
## Deterministic spawn-point picker (rejection sampling). The same rng state and
## inputs always give the same output. Hard constraints: inside `area`, at least
## `avoid_radius` from `avoid_point`, outside every `blocked` rect. Soft
## constraint: `separation` between points (relaxed to the best candidate found
## when the area is crowded). Kept separate from Room so Milestone 2's
## generator can reuse or replace it.

const ATTEMPTS_PER_POINT := 40


static func pick_positions(rng: RandomNumberGenerator, area: Rect2, count: int,
		avoid_point: Vector2, avoid_radius: float, separation: float,
		blocked: Array[Rect2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in count:
		var best := Vector2.ZERO
		var best_gap := -1.0
		for attempt in ATTEMPTS_PER_POINT:
			var candidate := Vector2(
					rng.randf_range(area.position.x, area.end.x),
					rng.randf_range(area.position.y, area.end.y))
			if candidate.distance_to(avoid_point) < avoid_radius or _is_blocked(candidate, blocked):
				continue
			var gap := _nearest_distance(candidate, result)
			if gap > best_gap:
				best = candidate
				best_gap = gap
			if gap >= separation:
				break
		if best_gap >= 0.0:
			result.append(best)
	return result


static func _is_blocked(point: Vector2, blocked: Array[Rect2]) -> bool:
	for rect in blocked:
		if rect.has_point(point):
			return true
	return false


static func _nearest_distance(point: Vector2, others: PackedVector2Array) -> float:
	var nearest := INF
	for other in others:
		nearest = minf(nearest, point.distance_to(other))
	return nearest
