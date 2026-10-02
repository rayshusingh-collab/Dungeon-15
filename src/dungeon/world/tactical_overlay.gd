class_name TacticalOverlay
extends Node2D
## Developer-only design view drawn over the world (F4 / TAC, debug builds).
## For every room: its role, threat against its budget, recipe, enemy roles,
## and the decision it asks of the player; hazard purposes; risk tiles; the
## safe (green) and risky (orange) routes to a risk cache; where each enemy
## starts when the player arrives through the approach doorway and which lead
## enemies were placed for the terrain (yellow). Never shown to
## players; it only draws (no collision, no processing).

const RISK_COLOR := Color(1.0, 0.55, 0.15)
const SAFE_COLOR := Color(0.35, 0.95, 0.5)
## Spawn plan from the approach doorway (enemy letters, intent lines).
const PLAN_COLOR := Color(1.0, 0.85, 0.3)

var layout: DungeonLayout


func setup(p_layout: DungeonLayout) -> void:
	layout = p_layout
	name = "TacticalOverlay"
	z_index = 50
	visible = false
	queue_redraw()


func _draw() -> void:
	if layout == null:
		return
	var font := ThemeDB.fallback_font
	var tile := float(DungeonLayout.TILE_SIZE)
	for room in layout.rooms:
		for hazard in room.hazards:
			var risky: bool = hazard.get("purpose", &"") == RoomRole.PURPOSE_RISK_ROUTE
			for t: Vector2i in hazard.tiles:
				draw_rect(Rect2(Vector2(t) * tile, Vector2.ONE * tile), Color(RISK_COLOR if risky else Color(1, 0.3, 0.3), 0.6), false, 2.0)
		for pair: Array in [[room.risk_route, RISK_COLOR], [room.safe_route, SAFE_COLOR]]:
			var route: Array[Vector2i] = pair[0]
			if route.size() < 2:
				continue
			var points := PackedVector2Array()
			for t in route:
				points.append(layout.tile_center(t))
			draw_polyline(points, pair[1], 4.0)
		for t in room.spawn_candidates:
			draw_arc(layout.tile_center(t), 10.0, 0.0, TAU, 12, Color(1, 0.4, 0.4, 0.6), 2.0)
		# The note reads "situation: advice"; one line each keeps it legible.
		var lines := PackedStringArray([_title(room)])
		var split := room.design_note.find(": ")
		if split > 0:
			lines.append(room.design_note.substr(0, split + 1))
			lines.append(room.design_note.substr(split + 2))
		else:
			lines.append(room.design_note)
		var purposes := PackedStringArray()
		for hazard in room.hazards:
			var purpose := str(hazard.get("purpose", &""))
			if not purposes.has(purpose):
				purposes.append(purpose)
		if not purposes.is_empty():
			lines.append("hazards: " + ", ".join(purposes))
		if not room.enemy_ids.is_empty():
			var intents := _draw_spawn_plan(room, font)
			if not intents.is_empty():
				lines.append("from the approach: " + ", ".join(intents))
		if room.tactic == RoomRole.RISK_REWARD:
			lines.append("to the cache: risky %d tiles, safe %s" % [room.risk_route.size(),
				"%d tiles" % room.safe_route.size() if not room.safe_route.is_empty() else "none (guarded)"])
		var at := layout.tile_center(room.anchor) + Vector2(-320, -80)
		for i in lines.size():
			var line_at := at + Vector2(0, i * 18)
			draw_string_outline(font, line_at, lines[i], HORIZONTAL_ALIGNMENT_CENTER, 640, 14, 5, Color.BLACK)
			draw_string(font, line_at, lines[i], HORIZONTAL_ALIGNMENT_CENTER, 640, 14,
				Color(1, 0.9, 0.55) if i == 0 else Color(0.9, 0.92, 1.0))


## Where the enemies start when the player arrives through the approach
## doorway (SpawnPlanner, the same plan the room uses at runtime): a letter per
## enemy, a dashed line from the player to each lead enemy with an intent.
## Returns "letter intent" per placed lead enemy.
func _draw_spawn_plan(room: DungeonLayout.PlacedRoom, font: Font) -> PackedStringArray:
	var from := SpawnPlanner.entry_point(layout, SpawnPlanner.approach_door(layout, room))
	var plan := SpawnPlanner.plan(layout, room, from)
	var intents := PackedStringArray()
	draw_arc(from, 12.0, 0.0, TAU, 16, PLAN_COLOR, 2.0)
	for i in plan.size():
		if plan[i] == SpawnPlanner.NONE:
			continue
		var p := layout.tile_center(plan[i])
		var letter := EnemyCatalog.letter(room.enemy_ids[i])
		var intent := SpawnPlanner.intent_at(room, i)
		if intent != &"":
			draw_dashed_line(from, p, PLAN_COLOR, 2.0, 10.0)
			intents.append("%s %s" % [letter, intent])
		draw_string_outline(font, p + Vector2(-6, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
		draw_string(font, p + Vector2(-6, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PLAN_COLOR)
	return intents


static func _title(room: DungeonLayout.PlacedRoom) -> String:
	var title := "%s  threat %.1f/%.1f" % [RoomRole.name_of(room.tactic), room.threat, room.threat_budget]
	if room.planned_tactic != room.tactic:
		title += "  (planned %s)" % RoomRole.name_of(room.planned_tactic)
	if room.recipe != &"":
		var letters := ""
		for id in room.enemy_ids:
			letters += EnemyCatalog.letter(id)
		title += "  %s [%s]" % [room.recipe, letters]
	return title
