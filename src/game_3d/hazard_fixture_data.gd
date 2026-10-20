extends RefCounted
## Fixed test data only. Never used by DungeonGenerator or campaign scene.
static func create() -> DungeonLayout:
	var data := DungeonLayout.new()
	var t := DungeonLayout.Tile
	data.init_grid(Vector2i(21,15))
	data.run_seed = 1101
	data.depth = 1
	data.player_spawn = Vector2i(4,5)
	data.exit_tile = Vector2i(18,5)
	for y in data.size.y:
		for x in data.size.x:
			data.set_tile(Vector2i(x,y),t.WALL if x==0 or y==0 or x==20 or y==14 else t.FLOOR,0)
	for y in range(2,9):
		for x in range(7,13):
			data.set_tile(Vector2i(x,y),t.BRIDGE if y in [4,5,6] else t.PIT,0)
	for y in range(10,13):
		for x in range(7,13):
			data.set_tile(Vector2i(x,y),t.WATER,0)
	for y in range(4,7):
		for x in range(15,18):
			data.set_tile(Vector2i(x,y),t.HAZARD,0)
	for tile in [Vector2i(3,2),Vector2i(4,2),Vector2i(17,11),Vector2i(18,11)]:
		data.set_tile(tile,t.OBSTACLE,0)
	return data
