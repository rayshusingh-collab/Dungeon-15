extends RefCounted
## The only conversion boundary. Generation stays in tiles/pixels; 3D uses metres.
const CELL := 2.0

static func center(tile: Vector2i, height: float = 0.0) -> Vector3:
	return Vector3((tile.x + 0.5) * CELL, height, (tile.y + 0.5) * CELL)

static func tile_at(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))

static func pixels(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) * DungeonLayout.TILE_SIZE / CELL
