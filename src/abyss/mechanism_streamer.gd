extends "res://src/abyss/chunk_streamer.gd"
## Stage 5A only: one fixed optional destination edge; all other stream rules reused.

const Bridge = preload("res://src/abyss/deploying_bridge.gd")
const HOME := Vector2i.ZERO
const DESTINATION := Vector2i.RIGHT
@export_range(0.5, 4.0, 0.1) var interaction_range: float = 2.4
@export_range(0.2, 10.0, 0.1) var deployment_seconds: float = 3.0
var mechanism_id: String = ""
var bridge: Node3D
var status: String = "Approach the ancient mechanism"
var activation_count: int = 0
var transition_max_ms: float = 0
var mechanism_build_max_ms: float = 0
var _collision_tick: int = -1
var _destination_center := Vector3.ZERO


func _ready() -> void:
	super._ready()
	if catalog != null:
		_destination_center = catalog.room(DESTINATION).center
		mechanism_id = catalog.chunk_id(HOME) + ":mechanism:bridge-east:v1"
		if not world_state.has(mechanism_id):
			world_state[mechanism_id] = {"activated": false, "completed": false, "progress": 0.0, "destination_reached": false}


func state() -> Dictionary:
	return world_state.get(mechanism_id, {})


func logical_edge_open(a: Vector2i, b: Vector2i) -> bool:
	if a != DESTINATION and b != DESTINATION:
		return true
	return ((a == HOME and b == DESTINATION) or (b == HOME and a == DESTINATION)) and state().get("completed", false)


func _owned_links(cell: Vector2i, data: AbyssSpatialLayout) -> Array[int]:
	var owned := super._owned_links(cell, data)
	var result: Array[int] = []
	for id in owned:
		var direction := data.connections[id].direction()
		var other := cell + Vector2i(roundi(direction.x), roundi(direction.z))
		if cell != DESTINATION and other != DESTINATION:
			result.append(id)
	return result


func _edge_open(a: Vector2i, b: Vector2i) -> bool:
	if not logical_edge_open(a, b):
		return false
	if a == DESTINATION or b == DESTINATION:
		return is_instance_valid(bridge) and bridge.deck.collision_layer == 1
	return true


func _chunk_loaded(cell: Vector2i, record: Dictionary) -> void:
	if cell == HOME:
		var started := Time.get_ticks_usec()
		for link: AbyssSpatialLayout.Connection in record.data.connections:
			if link.direction() == Vector3.RIGHT:
				bridge = Bridge.new()
				record.geometry.add_child(bridge)
				bridge.setup(link)
				bridge.pose(state().get("progress", 0.0))
				if state().get("completed", false):
					bridge.deck.collision_layer = 1
				_collision_tick = -1
				record.geometry.box_count += bridge.box_count
				if state().activated:
					print("ABYSS mechanism restored ", mechanism_id, " ", state())
		mechanism_build_max_ms = maxf(mechanism_build_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
	elif cell == DESTINATION:
		for child in record.geometry.get_node("Room_0").get_children():
			if child is Label3D:
				child.text = "WAYFINDER CHAMBER\nReach its center"


func _chunk_unloading(cell: Vector2i) -> void:
	if cell == HOME:
		bridge = null
		_collision_tick = -1


func occupied() -> bool:
	if not is_instance_valid(bridge):
		return true
	var bounds: AABB = bridge.swept_bounds()
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, bounds.get_center())
	query.collision_mask = 2
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func activate() -> bool:
	if not is_instance_valid(bridge) or not is_ready(HOME) or not is_ready(DESTINATION):
		status = "Waiting for both chambers to load"
		return false
	if player.global_position.distance_to(bridge.mechanism_position) > interaction_range:
		status = "Move closer to the mechanism"
		return false
	if state().activated:
		status = "Route already open" if state().completed else "Bridge deployment already in progress"
		return false
	if occupied():
		status = "Stand clear of the bridge deployment area"
		return false
	state().activated = true
	activation_count += 1
	status = "Mechanism activated — bridge deploying"
	print("ABYSS mechanism activated ", mechanism_id, " ", state())
	return true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state().is_empty() or not is_instance_valid(bridge):
		return
	if state().completed:
		if is_ready(DESTINATION) and player.global_position.distance_to(_destination_center) < 1.5:
			state().destination_reached = true
			status = "Wayfinder chamber reached — a new route discovered"
		return
	if not state().activated or not is_ready(HOME) or not is_ready(DESTINATION):
		return
	var started := Time.get_ticks_usec()
	if occupied():
		status = "Deployment paused — stand clear"
		return
	state().progress = minf(1, state().progress + delta / maxf(deployment_seconds, 0.2))
	bridge.pose(state().progress)
	if state().progress >= 1:
		if _collision_tick < 0:
			bridge.deck.collision_layer = 1
			_collision_tick = _tick + 2
		elif _tick >= _collision_tick:
			state().completed = true
			status = "Bridge secured — route to the Wayfinder chamber is open"
			print("ABYSS mechanism completed ", mechanism_id, " ", state())
	transition_max_ms = maxf(transition_max_ms, (Time.get_ticks_usec() - started) / 1000.0)


func prompt() -> String:
	if not is_instance_valid(bridge):
		return status
	if state().activated:
		return status
	if player.global_position.distance_to(bridge.mechanism_position) <= interaction_range:
		return "E / south face button: activate ancient mechanism"
	return "Approach the gold mechanism beside the disconnected bridge"
