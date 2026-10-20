extends RefCounted
const Grid = preload("res://src/game_3d/grid_space.gd")
const T = DungeonLayout.Tile
var layout: DungeonLayout
var grid := AStarGrid2D.new()

func _init(data: DungeonLayout) -> void:
	layout=data
	grid.region=Rect2i(Vector2i.ZERO,data.size)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x,y)
			grid.set_point_solid(tile,not safe_tile(tile))

func safe_tile(tile: Vector2i) -> bool:
	return layout.get_tile(tile) in [T.FLOOR,T.CORRIDOR,T.DOOR,T.BRIDGE]

func clear_spawn(tile: Vector2i) -> bool:
	for y in range(-1,2):
		for x in range(-1,2):
			if not safe_tile(tile+Vector2i(x,y)):
				return false
	return true

func path(from: Vector3,to: Vector3) -> Array[Vector2i]:
	var a := Grid.tile_at(from)
	var b := Grid.tile_at(to)
	if not safe_tile(a) or not safe_tile(b):
		return []
	return grid.get_id_path(a,b)

func safe_step(from: Vector3,to: Vector3,radius: float=0.43) -> bool:
	var dir := to-from
	dir.y=0
	var side := Vector3(-dir.z,0,dir.x).normalized()*radius
	for p in [to,to+side,to-side]:
		if not safe_tile(Grid.tile_at(p)):
			return false
	return true

func plan_encounters(depth: int=1, descent: bool=false) -> Array[Dictionary]:
	# Selection scans the validated grid without editing it. Quiet rooms often have no legacy enemy candidates.
	var suitable: Array[Dictionary] = []
	for id in layout.graph.main_path:
		var room := layout.rooms[id]
		if id==layout.graph.entry_id() or id==layout.graph.objective_id() or room.special_rule!=null:
			continue
		var candidates: Array[Vector2i] = []
		var walkable := 0
		var area := room.bounds()
		for y in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				walkable+=int(layout.get_owner_of(Vector2i(x,y))==id and safe_tile(Vector2i(x,y)))
		if walkable<64:
			continue
		var ranked: Array[Dictionary] = []
		var entry: Vector2i=room.doors[0].inside
		var path_index := layout.graph.main_path.find(id)
		var prior_id: int=layout.graph.main_path[maxi(0,path_index-1)]
		for door in room.doors:
			var link: DungeonGraph.Link=layout.graph.links[door.link]
			if link.a==prior_id or link.b==prior_id:
				entry=door.inside
				break
		for y in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				var tile := Vector2i(x,y)
				var score := absf(Vector2(tile).distance_to(Vector2(entry))-5.0)
				score+=float(StableHash.hash62("M2|%d|%d|%d,%d" % [layout.run_seed,id,x,y])%10007)/10007.0
				ranked.append({"tile":tile,"score":score})
		ranked.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.score!=b.score:
				return a.score<b.score
			return a.tile.y<b.tile.y if a.tile.y!=b.tile.y else a.tile.x<b.tile.x)
		for item in ranked:
			var tile: Vector2i=item.tile
			if not clear_spawn(tile) or layout.get_owner_of(tile)!=id:
				continue
			if descent:
				var access := grid.get_id_path(entry,tile)
				if access.is_empty() or access.any(func(step: Vector2i) -> bool: return not area.grow(1).has_point(step)):
					continue
			var near_door := false
			for door in room.doors:
				if Vector2(tile).distance_to(Vector2(door.inside))<3.0:
					near_door=true
			if near_door or Vector2(tile).distance_to(Vector2(layout.exit_tile))<5 or Vector2(tile).distance_to(Vector2(layout.player_spawn))<8:
				continue
			# Spread enemies so the entrance and dodge lanes remain open.
			var separate := true
			for prior in candidates:
				if Vector2(prior).distance_to(Vector2(tile))<3:
					separate=false
			if separate:
				candidates.append(tile)
			if candidates.size()==3:
				break
		if candidates.size()>=2:
			suitable.append({"room":id,"tiles":candidates,"bounds":area,"entry":entry})
	if suitable.size()<3:
		return [] # Explicitly fail this combat floor instead of unsafe spawn fallbacks.
	var selected: Array[Dictionary] = [suitable[0],suitable[1],suitable[-1]]
	if descent:
		selected.clear()
		var count := mini(suitable.size(),depth+2)
		for i in count:
			selected.append(suitable[roundi(float(i)*(suitable.size()-1)/(count-1))])
	for i in selected.size():
		selected[i]=selected[i].duplicate(true)
		selected[i].kinds=[["basic"],["basic","ranged"],["brute","ranged"]][mini(i,2)]
		if descent:
			selected[i].kinds=["basic"] if i==0 else (["basic","ranged"] if i%2==1 else ["brute","basic"])
			if depth==3 and i==selected.size()-1 and selected[i].tiles.size()>=3:
				selected[i].kinds=["brute","basic","ranged"]
		selected[i].required=i==selected.size()-1
	return selected
