class_name AbyssSpatialLayout
extends RefCounted
## Pure spatial data. IDs match the reused logical graph. No nodes/resources owned.

class Room:
	var id: int
	var center: Vector3
	var size: Vector2

	func footprint() -> Rect2:
		return Rect2(Vector2(center.x, center.z) - size * 0.5, size)

	func socket(direction: Vector3) -> Vector3:
		return center + direction * (size.x * 0.5 if absf(direction.x) > 0.5 else size.y * 0.5)


class Connection:
	var id: int
	var a: int
	var b: int
	var start: Vector3
	var end: Vector3
	var width: float

	func direction() -> Vector3:
		var delta := end - start
		delta.y = 0
		return delta.normalized()

	func footprint() -> Rect2:
		var p := Vector2(start.x, start.z)
		var q := Vector2(end.x, end.z)
		var pad := Vector2(width * 0.5 + 0.2, 0) if absf(direction().z) > 0.5 else Vector2(0, width * 0.5 + 0.2)
		return Rect2(p.min(q) - pad, (q - p).abs() + pad * 2)


var graph: DungeonGraph
var rooms: Array[Room] = []
var connections: Array[Connection] = []
var spawn: Vector3
var exit: Vector3
var run_seed: int
var attempt: int


func fingerprint() -> String:
	var parts := PackedStringArray(["abyss-spatial-v1|%d" % run_seed, str(graph.main_path)])
	for room in rooms:
		var space := graph.spaces[room.id]
		parts.append("%d|%s|%d|%d|%d|%d|%s|%s" % [room.id, space.cell, space.role,
			space.tactic, space.encounter, space.purpose, room.center, room.size])
	for connection in connections:
		parts.append("%d|%d|%d|%d|%s|%s|%.3f" % [connection.id, connection.a, connection.b,
			graph.links[connection.id].kind, connection.start, connection.end, connection.width])
	parts.append(str(spawn) + str(exit))
	return "%016x" % StableHash.hash62("\n".join(parts))
