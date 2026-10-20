extends SceneTree
const Floor = preload("res://src/game_3d/first_dungeon.gd")
const T = DungeonLayout.Tile

func _initialize() -> void:
	var report := {"coordinate_system": "integer tile [x,y]; 2 metres per tile, world centre=(2*x+1,0,2*y+1)", "depth": 1, "generator_version": DungeonGenerator.GENERATOR_VERSION, "seeds": []}
	for seed_value in [12345, 42, 7]:
		var result := DungeonGenerator.new().generate(DepthProfile.load_for_depth(1), seed_value, 1)
		if not result.ok:
			push_error("Audit generation failed")
			quit(1)
			return
		var data := result.layout
		var path := Floor.find_route(data)
		var distances := {data.player_spawn: 0}
		var queue: Array[Vector2i] = [data.player_spawn]
		var cursor := 0
		while cursor < queue.size():
			var tile := queue[cursor]
			cursor += 1
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := tile + step
				if data.is_walkable(next, true) and not distances.has(next):
					distances[next] = distances[tile] + 1
					queue.append(next)
		var row := {"seed": seed_value, "fingerprint": data.fingerprint(), "spawn": [data.player_spawn.x, data.player_spawn.y], "exit": [data.exit_tile.x, data.exit_tile.y], "shortest_route_tiles": path.size(), "accessible_walkable_tiles": distances.size(), "terrain": {}, "rooms": [], "special_rooms": []}
		for pair in [["pits", T.PIT], ["bridges", T.BRIDGE], ["water", T.WATER], ["spike_tiles", T.HAZARD], ["obstacles", T.OBSTACLE], ["inner_walls", T.INNER_WALL], ["rubble", T.RUBBLE]]:
			var positions: Array = []
			var on_route := 0
			var nearest := 2147483647
			var room_ids: Array = []
			for y in data.size.y:
				for x in data.size.x:
					var tile := Vector2i(x, y)
					if data.get_tile(tile) == pair[1]:
						positions.append([x, y])
						on_route += int(path.has(tile))
						nearest = mini(nearest, distances.get(tile, 2147483647))
						var owner := data.get_owner_of(tile)
						if not room_ids.has(owner):
							room_ids.append(owner)
			row.terrain[pair[0]] = {"count": positions.size(), "tiles": positions, "on_shortest_route": on_route, "nearest_walk_steps": nearest if nearest != 2147483647 else -1, "room_ids": room_ids}
		var trap_regions: Array = []
		for room in data.rooms:
			var bounds := room.bounds()
			var walkable := 0
			var plain := 0
			var route_count := 0
			var terrain := 0
			for y in range(bounds.position.y, bounds.end.y):
				for x in range(bounds.position.x, bounds.end.x):
					var tile := Vector2i(x, y)
					if data.get_owner_of(tile) != room.id:
						continue
					walkable += int(distances.has(tile))
					plain += int(distances.has(tile) and data.get_tile(tile) == T.FLOOR)
					terrain += int(DungeonLayout.is_terrain_kind(data.get_tile(tile)))
					route_count += int(path.has(tile))
			var info := {"id": room.id, "template": str(room.template.id), "variant": room.variant, "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "anchor": [room.anchor.x, room.anchor.y], "walkable_tiles": walkable, "accessible_area_m2": walkable * 4, "plain_floor_tiles": plain, "terrain_tiles": terrain, "tiles_on_shortest_route": route_count, "planned_role": RoomRole.name_of(room.tactic), "enemy_metadata_count_not_instantiated": room.enemy_ids.size(), "marker_metadata_count_not_instantiated": room.markers.size()}
			row.rooms.append(info)
			if room.special_rule != null:
				row.special_rooms.append(info)
			for hazard in room.hazards:
				if hazard.type == &"spikes":
					var tiles: Array = []
					for tile: Vector2i in hazard.tiles:
						tiles.append([tile.x, tile.y])
					trap_regions.append({"room": room.id, "tiles": tiles, "purpose": str(hazard.get("purpose", &""))})
		row.spike_trap_regions = trap_regions
		report.seeds.append(row)
		print("AUDIT seed=", seed_value, " spawn=", row.spawn, " exit=", row.exit, " accessible=", distances.size(), " rooms=", data.rooms.size(), " special=", JSON.stringify(row.special_rooms), " trap_regions=", trap_regions.size())
		for key in row.terrain:
			var item: Dictionary = row.terrain[key]
			print("  ", key, " count=", item.count, " on_route=", item.on_shortest_route, " steps=", item.nearest_walk_steps, " rooms=", item.room_ids)
	var file := FileAccess.open("res://docs/M1_LAYOUT_AUDIT.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	quit()
