class_name PlaceholderTileset
extends RefCounted
## Runtime-built placeholder TileSet: flat colours with simple patterns so
## every terrain reads at a glance (wall, interior wall, rubble, water, pit,
## bridge...). Final art replaces it with an authored TileSet that uses the
## same atlas coordinates (Look), so DungeonBuilder does not change.

enum Look {
	WALL, CORRIDOR, DOOR, FLOOR, FLOOR_ENTRY, FLOOR_COMBAT, FLOOR_OPTIONAL,
	FLOOR_OBJECTIVE, FLOOR_SPECIAL, HAZARD, OBSTACLE,
	INNER_WALL, RUBBLE, WATER, PIT, BRIDGE, FLOOR_ENVIRONMENT,
}

const COLORS: Array[Color] = [
	Color("5a5368"), # WALL (outer)
	Color("15161d"), # CORRIDOR
	Color("24252f"), # DOOR
	Color("1d1e27"), # FLOOR (traversal)
	Color("172433"), # FLOOR_ENTRY (blue)
	Color("2b1a1f"), # FLOOR_COMBAT (red)
	Color("221a2e"), # FLOOR_OPTIONAL (purple)
	Color("2e2816"), # FLOOR_OBJECTIVE (gold)
	Color("122b29"), # FLOOR_SPECIAL (teal)
	Color("2a1414"), # HAZARD base (the trap draws on top)
	Color("6a6278"), # OBSTACLE (pillar)
	Color("7a6a55"), # INNER_WALL (warm stone, differs from outer walls)
	Color("4a4640"), # RUBBLE (broken stone)
	Color("1f5a8c"), # WATER
	Color("030305"), # PIT
	Color("7a5230"), # BRIDGE (planks)
	Color("1f2320"), # FLOOR_ENVIRONMENT (grey-green)
]

static var _tileset: TileSet


static func get_tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var tile := DungeonLayout.TILE_SIZE
	var image := Image.create(tile * COLORS.size(), tile, false, Image.FORMAT_RGBA8)
	for look in COLORS.size():
		_paint(image, look, look * tile, tile)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(tile, tile)
	for look in COLORS.size():
		source.create_tile(Vector2i(look, 0))
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile, tile)
	tileset.add_source(source, 0)
	_tileset = tileset
	return tileset


static func _paint(image: Image, look: int, x0: int, tile: int) -> void:
	var base := COLORS[look]
	image.fill_rect(Rect2i(x0, 0, tile, tile), base)
	match look:
		Look.WALL, Look.OBSTACLE:
			image.fill_rect(Rect2i(x0, 0, tile, 4), base.lightened(0.18))
			image.fill_rect(Rect2i(x0, tile - 3, tile, 3), base.darkened(0.25))
		Look.INNER_WALL:
			# Brick courses: reads as built masonry inside a room.
			image.fill_rect(Rect2i(x0, 0, tile, 3), base.lightened(0.2))
			for y: int in [10, 21]:
				image.fill_rect(Rect2i(x0, y, tile, 2), base.darkened(0.3))
			image.fill_rect(Rect2i(x0 + 12, 3, 2, 7), base.darkened(0.3))
			image.fill_rect(Rect2i(x0 + 22, 12, 2, 9), base.darkened(0.3))
		Look.RUBBLE:
			for r: Rect2i in [Rect2i(3, 4, 11, 9), Rect2i(17, 2, 12, 10), Rect2i(6, 17, 13, 11), Rect2i(21, 18, 9, 9)]:
				image.fill_rect(Rect2i(x0 + r.position.x, r.position.y, r.size.x, r.size.y), base.lightened(0.25))
				image.fill_rect(Rect2i(x0 + r.position.x, r.position.y, r.size.x, 2), base.lightened(0.45))
		Look.WATER:
			for y: int in [8, 20]:
				for x in range(0, tile, 2):
					var wave := y + int(2.0 * sin(x * 0.4))
					image.fill_rect(Rect2i(x0 + x, wave, 2, 2), base.lightened(0.35))
		Look.PIT:
			# Dark void with a faint depth rim at the top edge.
			image.fill_rect(Rect2i(x0, 0, tile, 3), Color("1a1418"))
			for i in 6:
				image.fill_rect(Rect2i(x0 + i * 6, 10 + (i % 2) * 8, 2, 2), Color("0d0b10"))
		Look.BRIDGE:
			for y in range(0, tile, 8):
				image.fill_rect(Rect2i(x0, y, tile, 1), base.darkened(0.45))
			image.fill_rect(Rect2i(x0, 0, 3, tile), base.darkened(0.3))
			image.fill_rect(Rect2i(x0 + tile - 3, 0, 3, tile), base.darkened(0.3))
		_:
			var edge := base.lightened(0.08)
			image.fill_rect(Rect2i(x0, 0, tile, 1), edge)
			image.fill_rect(Rect2i(x0, 0, 1, tile), edge)
