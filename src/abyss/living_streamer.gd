extends "res://src/abyss/chunk_streamer.gd"

const Director = preload("res://src/abyss/castle_director.gd")
const RouteBridge = preload("res://src/abyss/director_bridge.gd")
const HOME := Vector2i.ZERO
const EAST := Vector2i.RIGHT
const SOUTH := Vector2i.DOWN
var director: RefCounted
@export_group("Castle Director")
@export_range(0.5, 2.0, 0.05) var zone_radius_cells: float = 1.15
@export_range(0.1, 30.0, 0.1) var trigger_seconds: float = 3.0
@export_range(1.0, 10.0, 0.1) var warning_seconds: float = 3.0
@export_range(1.0, 30.0, 0.1) var cooldown_seconds: float = 6.0
@export_range(1.0, 60.0, 0.1) var redirect_seconds: float = 18.0
@export_range(0.2, 5.0, 0.1) var movement_seconds: float = 2.0
var director_id: String = ""
var bridge: Node3D
var message: String = "The castle watches. Find the Wayfinder chamber at (1,0)."
var update_max_ms: float = 0
var assembly_max_ms: float = 0
var pose_updates: int = 0
var _gate_tick: int = -1
var _collision_tick: int = -1
var _goal := Vector3.ZERO


func _ready() -> void:
	super._ready()
	if catalog == null:
		return
	director_id = catalog.chunk_id(HOME) + ":castle-director:v1"
	if not world_state.has(director_id):
		world_state[director_id] = {}
	director = Director.new(world_state[director_id], catalog.world_id)
	director.trigger_seconds = trigger_seconds
	director.warning_seconds = warning_seconds
	director.cooldown_seconds = cooldown_seconds
	director.redirect_seconds = redirect_seconds
	_goal = catalog.room(EAST).center


func state() -> Dictionary:
	return director.state if director != null else {}


func _pair(a: Vector2i, b: Vector2i, endpoint: Vector2i) -> bool:
	return (a == HOME and b == endpoint) or (b == HOME and a == endpoint)


func logical_edge_open(a: Vector2i, b: Vector2i, mode: String = "") -> bool:
	var selected := str(state().get("stable", "direct")) if mode.is_empty() else mode
	if _pair(a, b, EAST):
		return selected in ["direct", "both"]
	if _pair(a, b, SOUTH):
		return selected in ["redirected", "both"]
	return true


func _edge_open(a: Vector2i, b: Vector2i) -> bool:
	var active_event: Dictionary = state().get("active", {})
	if not active_event.is_empty() and active_event.phase not in ["warning", "waiting"]:
		if _pair(a, b, EAST):
			return active_event.phase == "handover" and active_event.target == "direct" \
				and is_instance_valid(bridge) and bridge.deck.collision_layer == 1
		if _pair(a, b, SOUTH):
			return true
	if _pair(a, b, EAST):
		return logical_edge_open(a, b) and is_instance_valid(bridge) and bridge.deck.collision_layer == 1
	return logical_edge_open(a, b)


func _owned_links(cell: Vector2i, data: AbyssSpatialLayout) -> Array[int]:
	var result: Array[int] = []
	for id in super._owned_links(cell, data):
		if not (cell == HOME and data.connections[id].direction() == Vector3.RIGHT):
			result.append(id)
	return result


func _chunk_loaded(cell: Vector2i, record: Dictionary) -> void:
	if cell == HOME:
		var started := Time.get_ticks_usec()
		for link: AbyssSpatialLayout.Connection in record.data.connections:
			if link.direction() == Vector3.RIGHT:
				bridge = RouteBridge.new()
				record.geometry.add_child(bridge)
				bridge.setup(link)
				bridge.pose(state().pose)
				var phase: String = state().active.get("phase", "")
				bridge.deck.collision_layer = 1 if state().pose == 1 and phase != "moving" else 0
				record.geometry.box_count += 3
		_gate_tick = -1
		_collision_tick = _tick + 2
		assembly_max_ms = maxf(assembly_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
	elif cell == EAST:
		for child in record.geometry.get_node("Room_0").get_children():
			if child is Label3D:
				child.text = "WAYFINDER CHAMBER\nReach the center"
	elif cell == SOUTH or cell == Vector2i(1, 1):
		for child in record.geometry.get_node("Room_0").get_children():
			if child is Label3D:
				child.text = "SOUTHERN DETOUR %s" % cell


func _chunk_unloading(cell: Vector2i) -> void:
	if cell == HOME:
		bridge = null
		_gate_tick = -1
		_collision_tick = -1


func _occupied(bounds: AABB) -> bool:
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, bounds.get_center())
	query.collision_mask = 2
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func bridge_occupied() -> bool:
	return not is_instance_valid(bridge) or _occupied(bridge.swept_bounds().grow(0.4))


func detour_occupied() -> bool:
	if not active.has(HOME):
		return true
	for link: AbyssSpatialLayout.Connection in active[HOME].data.connections:
		if link.direction() == Vector3.BACK:
			var low := link.start.min(link.end) - Vector3(3, 1, 1)
			var high := link.start.max(link.end) + Vector3(3, 2, 1)
			return _occupied(AABB(low, high - low))
	return true


func required_route_valid(mode: String) -> bool:
	var seen := {HOME: true}
	var pending: Array[Vector2i] = [HOME]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + offset
			if settings.contains(next) and not seen.has(next) and logical_edge_open(cell, next, mode):
				seen[next] = true
				pending.append(next)
	return seen.size() == (2 * settings.world_radius + 1) * (2 * settings.world_radius + 1)


func _direct_gates_present() -> bool:
	var prefix: String = catalog.edge_id(HOME, EAST) + ":gate:"
	return _gates.has(prefix + str(HOME)) and _gates.has(prefix + str(EAST))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if director == null:
		return
	var started := Time.get_ticks_usec()
	var nearby := is_instance_valid(bridge) and is_ready(HOME) and is_ready(EAST) and is_ready(SOUTH) \
		and Vector2(player.position.x, player.position.z).length() < settings.cell_spacing * zone_radius_cells
	var milestone := player.position.distance_to(_goal) < 1.5
	director.advance(delta, nearby, milestone)
	if not nearby or state().active.is_empty():
		update_max_ms = maxf(update_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
		return
	var event: Dictionary = state().active
	if event.phase == "warning":
		message = "CASTLE MASTER: East bridge will withdraw; the southern passage will open. Stand clear." if event.target == "redirected" \
			else "CASTLE MASTER: East bridge will return; the southern entrance will close once clear."
	elif event.phase == "waiting":
		message = "Shift deferred: leave the east bridge and its approaches."
		if not bridge_occupied() and required_route_valid(event.target):
			event.phase = "gating"
			_gate_tick = -1
	elif event.phase == "gating":
		message = "Southern detour open. East bridge secured for movement."
		if _direct_gates_present():
			if _gate_tick < 0:
				_gate_tick = _tick + 2
			elif _tick >= _gate_tick and not bridge_occupied():
				bridge.deck.collision_layer = 0
				event.phase = "moving"
	elif event.phase == "moving":
		message = "Use the southern detour: (0,1) > (1,1) > (1,0)."
		if not bridge_occupied():
			state().pose = move_toward(state().pose, 0.0 if event.target == "redirected" else 1.0, delta / maxf(movement_seconds, 0.2))
			bridge.pose(state().pose)
			pose_updates += 1
			if (event.target == "redirected" and state().pose == 0) or (event.target == "direct" and state().pose == 1):
				if event.target == "direct":
					bridge.deck.collision_layer = 1
				_collision_tick = _tick + 2
				event.phase = "settling"
	elif event.phase == "settling":
		if _tick >= _collision_tick and not bridge_occupied():
			event.phase = "handover"
	elif event.phase == "handover":
		message = "Both routes available; waiting for the southern passage to clear." if event.target == "direct" else "Southern detour now leads to the Wayfinder chamber."
		if (event.target == "redirected" or not detour_occupied()) and required_route_valid(event.target):
			print("CASTLE DIRECTOR completed ", event.id, " target=", event.target)
			director.complete()
			message = "East bridge restored. Southern shortcut sealed; all other routes remain." if state().stable == "direct" \
				else "East bridge withdrawn. Southern detour: (0,1) > (1,1) > Wayfinder (1,0)."
	update_max_ms = maxf(update_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
