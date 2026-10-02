class_name DungeonNavigation
extends RefCounted
## Enemy pathfinding on the dungeon tile grid (AStarGrid2D, native code).
## Built once per floor from the layout: walls, obstacles and pits are solid;
## water and spikes are walkable but cost more (enemies prefer to go around);
## tiles next to solids cost a little more so paths keep off walls.
## Enemies use line_of_sight() to steer straight when nothing is in the way
## and path() otherwise. Queries are cheap; enemies re-plan a few times per second.

const WATER_WEIGHT := 2.0
const HAZARD_WEIGHT := 2.5
const WALL_HUG_WEIGHT := 1.4
## Half-width used when testing a straight line for an actor (px).
const ACTOR_HALF_WIDTH := 14.0
## Sample spacing (px) of clear_sight().
const SIGHT_STEP := SpawnPlanner.SIGHT_STEP

var layout: DungeonLayout

var _astar := AStarGrid2D.new()


func _init(p_layout: DungeonLayout) -> void:
	layout = p_layout
	var tile := DungeonLayout.TILE_SIZE
	_astar.region = Rect2i(Vector2i.ZERO, layout.size)
	_astar.cell_size = Vector2(tile, tile)
	_astar.offset = Vector2(tile, tile) / 2.0
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in layout.size.y:
		for x in layout.size.x:
			var t := Vector2i(x, y)
			var kind := layout.get_tile(t)
			if not DungeonLayout.is_walkable_kind(kind, true):
				_astar.set_point_solid(t, true)
				continue
			var weight := 1.0
			if kind == DungeonLayout.Tile.WATER:
				weight = WATER_WEIGHT
			elif kind == DungeonLayout.Tile.HAZARD:
				weight = HAZARD_WEIGHT
			elif _next_to_solid(t):
				weight = WALL_HUG_WEIGHT
			_astar.set_point_weight_scale(t, weight)


func is_walkable_point(point: Vector2) -> bool:
	var t := layout.tile_at(point)
	return layout.in_bounds(t) and not _astar.is_point_solid(t)


## World-space waypoints from `from` to `to` (tile centres), or empty if unreachable.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := layout.tile_at(from)
	var b := layout.tile_at(to)
	if not layout.in_bounds(a) or not layout.in_bounds(b) or _astar.is_point_solid(a) or _astar.is_point_solid(b):
		return PackedVector2Array()
	return _astar.get_point_path(a, b)


## True if an actor could move in a straight line from a to b: samples the
## segment and two parallel offsets (actor width) against non-walkable tiles.
func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return true
	var side := Vector2(-delta.y, delta.x) / length * ACTOR_HALF_WIDTH
	var steps := int(ceil(length / 12.0))
	for i in steps + 1:
		var p := a + delta * (float(i) / steps)
		for offset: Vector2 in [Vector2.ZERO, side, -side]:
			if not is_walkable_point(p + offset):
				return false
	return true


## True if nothing solid (walls, pillars, rubble) lies on the segment: what an
## enemy can see and shoot through. Unlike line_of_sight() (can an actor WALK
## straight there?), pits and water do not block sight or projectiles.
func clear_sight(a: Vector2, b: Vector2) -> bool:
	return not layout.segment_hits(a, b, SpawnPlanner.SOLID_MASK, SIGHT_STEP)


func _next_to_solid(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if DungeonLayout.is_solid_kind(layout.get_tile(t + Vector2i(dx, dy))):
				return true
	return false
