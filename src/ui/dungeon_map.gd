class_name DungeonMap
extends Control
## Two maps in one view:
##   EXPLORATION  player-facing: only rooms and corridors the player has stood
##                in, plus doorway stubs that point at unexplored passages.
##   DEBUG_FULL   development: the whole floor with room roles, threat vs
##                budget, enemy roles, recipes, risk tiles, safe/risky routes
##                to caches, markers, loops, event sockets, the main-path
##                pacing and the reasons earlier attempts were rejected.
## The floor is rendered to a small image (1 px per tile, so interior walls,
## water, pits and bridges show) that is rebuilt only when discovery or mode
## changes; overlays are drawn on top. Not the final minimap UI.

enum Mode { EXPLORATION, DEBUG_FULL }

const ROLE_COLORS := {
	DungeonGraph.Role.ENTRY: Color(0.35, 0.6, 1.0),
	DungeonGraph.Role.OBJECTIVE: Color(1.0, 0.85, 0.35),
	DungeonGraph.Role.SPECIAL: Color(0.3, 0.9, 0.85),
	DungeonGraph.Role.MAIN: Color(0.55, 0.55, 0.62),
	DungeonGraph.Role.BRANCH: Color(0.6, 0.42, 0.85),
	DungeonGraph.Role.DEAD_END: Color(0.6, 0.42, 0.85),
}
const TILE_COLORS := {
	DungeonLayout.Tile.WALL: Color(0.42, 0.4, 0.5),
	DungeonLayout.Tile.OBSTACLE: Color(0.55, 0.52, 0.62),
	DungeonLayout.Tile.INNER_WALL: Color(0.62, 0.52, 0.4),
	DungeonLayout.Tile.RUBBLE: Color(0.45, 0.43, 0.4),
	DungeonLayout.Tile.CORRIDOR: Color(0.24, 0.24, 0.3),
	DungeonLayout.Tile.DOOR: Color(0.32, 0.32, 0.4),
	DungeonLayout.Tile.WATER: Color(0.2, 0.45, 0.85),
	DungeonLayout.Tile.PIT: Color(0.08, 0.02, 0.12),
	DungeonLayout.Tile.BRIDGE: Color(0.6, 0.4, 0.22),
	DungeonLayout.Tile.HAZARD: Color(0.75, 0.2, 0.2),
}
const COMBAT_COLOR := Color(0.9, 0.3, 0.3)
const LOOP_COLOR := Color(0.3, 0.8, 1.0)
const MAIN_PATH_COLOR := Color(0.85, 0.8, 0.4)
const RISK_COLOR := Color(1.0, 0.55, 0.15)
const SAFE_COLOR := Color(0.35, 0.95, 0.5)
const MARKER_COLORS := {
	&"reward": Color(0.95, 0.75, 0.25), &"cache": Color(1.0, 0.55, 0.2), &"power": Color(0.75, 0.5, 1.0),
	&"heal": Color(0.4, 0.95, 0.55), &"lore": Color(0.75, 0.78, 0.9), &"secret": Color(0.6, 0.55, 0.75),
	&"story": Color(0.3, 0.9, 0.85),
}

## Generation log of rejected attempts (debug map only).
var generation_log: PackedStringArray = []

var mode: Mode = Mode.EXPLORATION
var layout: DungeonLayout
var revealed_rooms: Dictionary = {}
var revealed_corridors: Dictionary = {}
var cleared: Dictionary = {}
var player_position: Vector2 = Vector2.INF

var _texture: ImageTexture
var _texture_dirty: bool = true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_layout(new_layout: DungeonLayout) -> void:
	layout = new_layout
	revealed_rooms.clear()
	revealed_corridors.clear()
	cleared.clear()
	_invalidate()


func set_mode(new_mode: Mode) -> void:
	if mode != new_mode:
		mode = new_mode
		_invalidate()


func discover_room(space_id: int) -> void:
	if not revealed_rooms.has(space_id):
		revealed_rooms[space_id] = true
		_invalidate()


func discover_corridor(link_id: int) -> void:
	if not revealed_corridors.has(link_id):
		revealed_corridors[link_id] = true
		_invalidate()


func mark_cleared(space_id: int) -> void:
	cleared[space_id] = true
	queue_redraw()


func set_player_position(point: Vector2) -> void:
	player_position = point
	if visible:
		queue_redraw()


## Whether the room appears on the map in the current mode.
func is_room_shown(space_id: int) -> bool:
	return mode == Mode.DEBUG_FULL or revealed_rooms.has(space_id)


func is_corridor_shown(link_id: int) -> bool:
	return mode == Mode.DEBUG_FULL or revealed_corridors.has(link_id)


## Whether a tile is drawn in the current mode (walls show next to revealed space).
func is_tile_shown(t: Vector2i) -> bool:
	if mode == Mode.DEBUG_FULL:
		return layout.get_tile(t) != DungeonLayout.Tile.VOID
	var owner_id := layout.get_owner_of(t)
	if owner_id >= DungeonLayout.CORRIDOR_OWNER_BASE:
		return revealed_corridors.has(owner_id - DungeonLayout.CORRIDOR_OWNER_BASE)
	if owner_id >= 0:
		return revealed_rooms.has(owner_id)
	if layout.get_tile(t) != DungeonLayout.Tile.WALL:
		return false
	for d in RoomShape.SIDE_VECTORS:
		var n := layout.get_owner_of(t + d)
		if n >= DungeonLayout.CORRIDOR_OWNER_BASE and revealed_corridors.has(n - DungeonLayout.CORRIDOR_OWNER_BASE):
			return true
	return false


func shown_tile_count() -> int:
	var count := 0
	for y in layout.size.y:
		for x in layout.size.x:
			if is_tile_shown(Vector2i(x, y)):
				count += 1
	return count


func _invalidate() -> void:
	_texture_dirty = true
	queue_redraw()


func _rebuild_texture() -> void:
	var image := Image.create(layout.size.x, layout.size.y, false, Image.FORMAT_RGBA8)
	var floor_colors: Array[Color] = []
	for room in layout.rooms:
		floor_colors.append(PlaceholderTileset.COLORS[DungeonBuilder.floor_look(room)].lightened(0.35))
	for y in layout.size.y:
		for x in layout.size.x:
			var t := Vector2i(x, y)
			if not is_tile_shown(t):
				continue
			var kind := layout.get_tile(t)
			var color: Color
			if kind == DungeonLayout.Tile.FLOOR:
				var owner_id := layout.get_owner_of(t)
				color = floor_colors[owner_id] if owner_id >= 0 and owner_id < floor_colors.size() else Color(0.3, 0.3, 0.35)
			else:
				color = TILE_COLORS.get(kind, Color(0.3, 0.3, 0.35))
			image.set_pixel(x, y, color)
	_texture = ImageTexture.create_from_image(image)
	_texture_dirty = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 2.0)
	if layout == null:
		return
	if _texture_dirty or _texture == null:
		_rebuild_texture()
	var font := get_theme_default_font()
	var graph := layout.graph
	var header: String
	if mode == Mode.DEBUG_FULL:
		header = "DEBUG FULL MAP   seed %d   depth %d   attempt %d   rooms %d   main path %d   loops %d   dead ends %d   events %d" % [
			layout.run_seed, layout.depth, layout.attempt + 1, layout.rooms.size(), graph.main_path.size(),
			graph.count_links(DungeonGraph.LinkKind.LOOP), graph.ids_with_role(DungeonGraph.Role.DEAD_END).size(),
			layout.event_sockets.size()]
	else:
		header = "MAP   explored %d / ? rooms   (F3: debug full map)" % revealed_rooms.size()
	draw_string(font, Vector2(16, 28), header, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 16, Color(0.9, 0.9, 1.0))

	var area := Rect2(Vector2(16, 44), size - Vector2(32, 44 + 64))
	var world := Vector2(layout.size)
	var scale := minf(area.size.x / world.x, area.size.y / world.y)
	var origin := area.position + (area.size - world * scale) / 2.0
	draw_texture_rect(_texture, Rect2(origin, world * scale), false)

	var to_map := func(t: Vector2) -> Vector2: return origin + t * scale
	for room in layout.rooms:
		if not is_room_shown(room.id):
			continue
		var bounds := room.bounds()
		var rect := Rect2(to_map.call(Vector2(bounds.position)), Vector2(bounds.size) * scale)
		var outline: Color = ROLE_COLORS.get(room.role, Color.GRAY)
		if room.encounter != DungeonGraph.Encounter.NONE:
			outline = COMBAT_COLOR
		draw_rect(rect, outline, false, 2.0)
		var tag := _room_tag(room)
		if cleared.has(room.id):
			tag += " ok"
		if tag != "":
			draw_string_outline(font, rect.get_center() + Vector2(-80, 0), tag, HORIZONTAL_ALIGNMENT_CENTER, 160, 11, 4, Color.BLACK)
			draw_string(font, rect.get_center() + Vector2(-80, 0), tag, HORIZONTAL_ALIGNMENT_CENTER, 160, 11, Color.WHITE)
		if mode == Mode.DEBUG_FULL:
			var detail := _room_detail(room)
			draw_string_outline(font, rect.get_center() + Vector2(-80, 13), detail, HORIZONTAL_ALIGNMENT_CENTER, 160, 10, 4, Color.BLACK)
			draw_string(font, rect.get_center() + Vector2(-80, 13), detail, HORIZONTAL_ALIGNMENT_CENTER, 160, 10, Color(0.8, 0.85, 1.0))
		# Doorway stubs toward passages not explored yet.
		if mode == Mode.EXPLORATION:
			for door in room.doors:
				if not revealed_corridors.has(door.link):
					var c: Vector2 = to_map.call(Vector2(door.center) + Vector2(0.5, 0.5))
					var out := Vector2(RoomShape.SIDE_VECTORS[door.side]) * 6.0
					draw_line(c, c + out, Color(1, 0.9, 0.5), 3.0)

	if mode == Mode.DEBUG_FULL:
		for corridor in layout.corridors:
			if corridor.kind == DungeonGraph.LinkKind.LOOP:
				for rect in corridor.rects:
					draw_rect(Rect2(to_map.call(Vector2(rect.position)), Vector2(rect.size) * scale), LOOP_COLOR, false, 1.0)
		for i in range(1, graph.main_path.size()):
			var a := Vector2(layout.rooms[graph.main_path[i - 1]].bounds().get_center())
			var b := Vector2(layout.rooms[graph.main_path[i]].bounds().get_center())
			draw_line(to_map.call(a), to_map.call(b), Color(MAIN_PATH_COLOR, 0.55), 2.0)
		for socket in layout.event_sockets:
			var p: Vector2 = to_map.call(Vector2(socket.tile) + Vector2(0.5, 0.5))
			var color := Color(1, 0.9, 0.2) if socket.armed else Color(0.8, 0.6, 1.0, 0.8)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), color)
		# Risk rooms: the risky route (orange) and the safe route (green) to the cache.
		for room in layout.rooms:
			for pair: Array in [[room.risk_route, RISK_COLOR], [room.safe_route, SAFE_COLOR]]:
				var route: Array[Vector2i] = pair[0]
				if route.size() < 2:
					continue
				var points := PackedVector2Array()
				for t in route:
					points.append(to_map.call(Vector2(t) + Vector2(0.5, 0.5)))
				draw_polyline(points, pair[1], 2.0)
			for t in room.risk_tiles():
				draw_rect(Rect2(to_map.call(Vector2(t)), Vector2.ONE * scale), Color(RISK_COLOR, 0.5), false, 1.0)
			for marker in room.markers:
				var m: Vector2 = to_map.call(Vector2(marker.tile) + Vector2(0.5, 0.5))
				draw_circle(m, 4.0, MARKER_COLORS.get(marker.kind, Color.WHITE))
		_draw_debug_notes(font)

	if player_position != Vector2.INF:
		var p: Vector2 = to_map.call(player_position / DungeonLayout.TILE_SIZE)
		draw_circle(p, 6.0, Color(0.4, 0.8, 1.0))
		draw_arc(p, 9.0, 0.0, TAU, 16, Color.WHITE, 1.5)

	_draw_legend(font, Vector2(16, size.y - 40))


func _room_tag(room: DungeonLayout.PlacedRoom) -> String:
	if mode == Mode.EXPLORATION:
		match room.role:
			DungeonGraph.Role.ENTRY:
				return "ENTRY"
			DungeonGraph.Role.OBJECTIVE:
				return "EXIT" + (" !" if room.encounter != DungeonGraph.Encounter.NONE else "")
			DungeonGraph.Role.SPECIAL:
				return "STORY"
		return ""
	# Debug: role, threat against its budget and the enemy roles (letters).
	var tag := RoomRole.name_of(room.tactic)
	if room.threat > 0.0 or room.threat_budget > 0.0:
		tag += " %.1f/%.1f" % [room.threat, room.threat_budget]
	if not room.enemy_ids.is_empty():
		var letters := ""
		for id in room.enemy_ids:
			letters += EnemyCatalog.letter(id)
		tag += " " + letters
	return tag


## Second debug line: recipe (or the variant) of the room.
func _room_detail(room: DungeonLayout.PlacedRoom) -> String:
	var detail := String(room.recipe) if room.recipe != &"" else room.template.variant_name(room.variant)
	if room.planned_tactic != room.tactic:
		detail += " (planned %s)" % RoomRole.name_of(room.planned_tactic)
	return detail


## Debug: the floor's threat against its budget, the pacing along the main path
## and why earlier attempts of this seed were rejected.
func _draw_debug_notes(font: Font) -> void:
	var roles := PackedStringArray()
	for id in layout.graph.main_path:
		roles.append(RoomRole.name_of(layout.rooms[id].tactic).substr(0, 4))
	var lines := PackedStringArray([
		"threat %.1f / %.1f   pacing: %s" % [layout.total_threat(), layout.floor_threat_budget, " > ".join(roles)],
		"letters: C chaser  B brute  S spitter   routes to a cache: orange risky, green safe",
	])
	for line in generation_log:
		lines.append("rejected " + line)
	var y := 44.0
	for line in lines:
		draw_string_outline(font, Vector2(size.x - 16 - 520, y), line, HORIZONTAL_ALIGNMENT_RIGHT, 520, 11, 4, Color.BLACK)
		draw_string(font, Vector2(size.x - 16 - 520, y), line, HORIZONTAL_ALIGNMENT_RIGHT, 520, 11, Color(1, 0.85, 0.7))
		y += 14.0


func _draw_legend(font: Font, at: Vector2) -> void:
	var entries := [
		["wall", TILE_COLORS[DungeonLayout.Tile.WALL]], ["inner wall", TILE_COLORS[DungeonLayout.Tile.INNER_WALL]],
		["water", TILE_COLORS[DungeonLayout.Tile.WATER]], ["pit", Color(0.3, 0.1, 0.4)],
		["bridge", TILE_COLORS[DungeonLayout.Tile.BRIDGE]], ["spikes", TILE_COLORS[DungeonLayout.Tile.HAZARD]],
		["encounter", COMBAT_COLOR], ["entry", ROLE_COLORS[DungeonGraph.Role.ENTRY]],
		["exit", ROLE_COLORS[DungeonGraph.Role.OBJECTIVE]], ["story", ROLE_COLORS[DungeonGraph.Role.SPECIAL]],
	]
	if mode == Mode.DEBUG_FULL:
		entries.append(["loop", LOOP_COLOR])
		entries.append(["event socket", Color(0.8, 0.6, 1.0)])
		entries.append(["risk", RISK_COLOR])
		entries.append(["safe route", SAFE_COLOR])
	var x := at.x
	for entry: Array in entries:
		draw_rect(Rect2(x, at.y, 12, 12), entry[1])
		draw_string(font, Vector2(x + 16, at.y + 11), entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9))
		x += 20 + font.get_string_size(entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10
	var hint := "M / Tab or MAP: close" if mode == Mode.EXPLORATION else "F3: close debug map"
	draw_string(font, Vector2(at.x, at.y + 30), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.8))
