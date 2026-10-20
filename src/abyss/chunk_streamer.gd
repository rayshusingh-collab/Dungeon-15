extends Node3D
## Bounded geometry/data residency. Operates on main thread, never rebuilds per tick.

const Catalog = preload("res://src/abyss/chunk_catalog.gd")
const Geometry = preload("res://src/abyss/spatial_geometry.gd")
@export var settings: AbyssStreamConfig = AbyssStreamConfig.new()
@export var world_seed: int = 12345
@export var player: CharacterBody3D
var catalog: RefCounted
var active: Dictionary = {}
var world_state: Dictionary = {}
var failures: Dictionary = {}
var current_cell := Vector2i.ZERO
var generation_max_ms: float = 0
var construction_max_ms: float = 0
var active_boxes: int = 0
var built_count: int = 0
var unloaded_count: int = 0
var max_resident: int = 0
var max_active_boxes: int = 0
var max_jobs: int = 0
var last_jobs: int = 0
var error_message: String = ""
## Test hook: force N failed build attempts for a coordinate; no random failures.
var debug_failures: Dictionary = {}
var _tick: int = 0
var _frame: int = 0
var _desired: Array[Vector2i] = []
var _gates: Dictionary = {}
var _last_cell := Vector2i(999, 999)
var _owns_pause: bool = false


func _ready() -> void:
	var errors := settings.errors()
	if not errors.is_empty():
		error_message = "; ".join(errors)
		player.set_physics_process(false)
		set_process(false)
		return
	catalog = Catalog.new(settings, world_seed)
	# Start with movement disabled until initial collision has passed readiness delay.
	player.set_physics_process(false)
	_owns_pause = true


func _physics_process(_delta: float) -> void:
	_tick += 1
	if catalog == null:
		# The player's script can register physics after this earlier sibling readies.
		# Enforce fail-closed state before the player's first physics callback too.
		player.set_physics_process(false)
		return
	current_cell = cell_at(player.global_position)
	if not is_ready(current_cell):
		player.set_physics_process(false)
		_owns_pause = true
	elif _owns_pause:
		player.velocity = Vector3.ZERO
		player.set_physics_process(true)
		_owns_pause = false
	if is_ready(current_cell) and current_cell != _last_cell:
		world_state[current_cell] = {"visited": true, "schema": 1}
		_last_cell = current_cell


func _process(_delta: float) -> void:
	if catalog == null:
		return
	_frame += 1
	_desired.clear()
	for z in range(-settings.load_radius, settings.load_radius + 1):
		for x in range(-settings.load_radius, settings.load_radius + 1):
			var cell := current_cell + Vector2i(x, z)
			if settings.contains(cell):
				_desired.append(cell)
	# Nearest first, with coordinate tie-breaks independent of dictionary iteration.
	_desired.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - current_cell).length_squared()
		var db := (b - current_cell).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for cell: Vector2i in active.keys():
		if not _desired.has(cell):
			_unload(cell)
	for cell: Vector2i in failures.keys():
		if not _desired.has(cell):
			failures.erase(cell)
	last_jobs = 0
	for cell in _desired:
		if active.has(cell):
			continue
		if failures.has(cell) and (failures[cell].attempts >= settings.max_attempts or _frame < failures[cell].next_frame):
			continue
		if last_jobs >= settings.jobs_per_frame or active.size() >= settings.capacity():
			break
		last_jobs += 1
		_load(cell)
	_update_gates()
	active_boxes = _gates.size()
	for record: Dictionary in active.values():
		active_boxes += record.geometry.box_count
	max_resident = maxi(max_resident, active.size())
	max_active_boxes = maxi(max_active_boxes, active_boxes)
	max_jobs = maxi(max_jobs, last_jobs)


func _load(cell: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	var data: AbyssSpatialLayout = catalog.compose(cell)
	generation_max_ms = maxf(generation_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
	if debug_failures.get(cell, 0) > 0:
		debug_failures[cell] -= 1
		data = null
	if data == null:
		var attempts: int = failures.get(cell, {"attempts": 0}).attempts + 1
		failures[cell] = {"attempts": attempts, "next_frame": _frame + settings.retry_frames}
		error_message = "Chunk %s failed (%d/%d); boundary stays closed. R retries." % [cell, attempts, settings.max_attempts]
		return
	var geometry := Geometry.new()
	add_child(geometry)
	var owned: Array[int] = _owned_links(cell, data)
	started = Time.get_ticks_usec()
	if not geometry.build(data, [0], owned, true):
		geometry.free()
		# Catalog validation and geometry validation should agree; treat refusal as failure.
		var attempts: int = failures.get(cell, {"attempts": 0}).attempts + 1
		failures[cell] = {"attempts": attempts, "next_frame": _frame + settings.retry_frames}
		error_message = "Chunk geometry refused; boundary stays closed. R retries."
		return
	construction_max_ms = maxf(construction_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
	geometry.name = "Chunk_%d_%d" % [cell.x, cell.y]
	for child in geometry.get_node("Room_0").get_children():
		if child is Label3D:
			child.text = "CHUNK %s / %.0f m" % [cell, data.rooms[0].center.y]
	active[cell] = {"data": data, "geometry": geometry, "ready_tick": _tick + 2,
		"fingerprint": data.fingerprint(), "id": catalog.chunk_id(cell)}
	_chunk_loaded(cell, active[cell])
	failures.erase(cell)
	if failures.is_empty():
		error_message = ""
	built_count += 1


func _unload(cell: Vector2i) -> void:
	_chunk_unloading(cell)
	active[cell].geometry.free()
	active.erase(cell)
	unloaded_count += 1


func is_ready(cell: Vector2i) -> bool:
	return active.has(cell) and _tick >= active[cell].ready_tick


func cell_at(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / settings.cell_spacing + 0.5), floori(point.z / settings.cell_spacing + 0.5))


func retry_failed() -> void:
	failures.clear()
	error_message = ""


func _update_gates() -> void:
	var wanted: Dictionary = {}
	for cell: Vector2i in active:
		var data: AbyssSpatialLayout = active[cell].data
		for link in data.connections:
			var direction := link.direction()
			var neighbour := cell + Vector2i(roundi(direction.x), roundi(direction.z))
			if is_ready(cell) and is_ready(neighbour) and _edge_open(cell, neighbour):
				continue
			var id: String = catalog.edge_id(cell, neighbour) + ":gate:" + str(cell)
			wanted[id] = true
			if not _gates.has(id):
				var gate := StaticBody3D.new()
				gate.position = link.start + Vector3.UP * 0.8
				gate.collision_mask = 2
				var size := Vector3(0.4, 1.6, 4) if absf(direction.x) > 0.5 else Vector3(4, 1.6, 0.4)
				var shape := BoxShape3D.new()
				shape.size = size
				var collision := CollisionShape3D.new()
				collision.shape = shape
				gate.add_child(collision)
				var mesh := BoxMesh.new()
				mesh.size = size
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.65, 0.3, 0.12)
				mesh.material = material
				var visual := MeshInstance3D.new()
				visual.mesh = mesh
				gate.add_child(visual)
				add_child(gate)
				_gates[id] = gate
	for id: String in _gates.keys():
		if not wanted.has(id):
			_gates[id].free()
			_gates.erase(id)


func diagnostic_text() -> String:
	return "Chunk %s | resident %d/%d | boxes %d (peak %d)\nBuilt %d / unloaded %d / state records %d / jobs %d (peak %d)\nMax generation %.2f ms / construction %.2f ms\n%s" % [
		current_cell, active.size(), settings.capacity(), active_boxes, max_active_boxes, built_count, unloaded_count,
		world_state.size(), last_jobs, max_jobs, generation_max_ms, construction_max_ms, error_message]


func _owned_links(cell: Vector2i, data: AbyssSpatialLayout) -> Array[int]:
	return catalog.owned_links(cell, data)


func _edge_open(_cell: Vector2i, _neighbour: Vector2i) -> bool:
	return true


func _chunk_loaded(_cell: Vector2i, _record: Dictionary) -> void:
	pass


func _chunk_unloading(_cell: Vector2i) -> void:
	pass
