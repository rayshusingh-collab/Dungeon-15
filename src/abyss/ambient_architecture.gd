extends Node3D
## Fixed decorative budget, no bodies/collision/nav. Transforms update at 20 Hz.

@export var streamer: Node3D
const STRUCTURES := 12
var update_max_ms: float = 0
var construction_ms: float = 0
var update_count: int = 0
var _parts: Array[Dictionary] = []
var _elapsed: float = 0
var _anchor := Vector2i(999, 999)


func _ready() -> void:
	var started := Time.get_ticks_usec()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.14, 0.23)
	mesh.material = material
	for i in STRUCTURES:
		var structure := Node3D.new()
		add_child(structure)
		var angle := TAU * i / STRUCTURES
		var origin := Vector3(cos(angle) * 30, -18 - (i % 3) * 3, sin(angle) * 30)
		var phase := float(StableHash.hash62("ambient|%d|%d" % [streamer.world_seed, i]) % 1000) / 1000 * TAU
		for j in 2:
			var piece := MeshInstance3D.new()
			piece.mesh = mesh
			if i % 3 == 0:
				piece.scale = Vector3(4 - j, 9, 4 - j)
				piece.position.y = j * 8
			elif i % 3 == 1:
				piece.scale = Vector3(12, 0.6, 3)
				piece.position.y = j * 5
			else:
				piece.scale = Vector3(7, 0.8, 7)
				piece.position.y = j * 4
			structure.add_child(piece)
		_parts.append({"node": structure, "origin": origin, "phase": phase, "kind": i % 3})
	construction_ms = (Time.get_ticks_usec() - started) / 1000.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.05 or streamer.director == null:
		return
	_elapsed = 0
	var started := Time.get_ticks_usec()
	if streamer.current_cell != _anchor:
		_anchor = streamer.current_cell
		position = Vector3(_anchor.x * streamer.settings.cell_spacing, streamer.player.position.y,
			_anchor.y * streamer.settings.cell_spacing)
	var time: float = streamer.state().ambient_clock
	var intensity: float = streamer.state().ambient_intensity
	for part in _parts:
		var wave: float = time * 0.35 + part.phase
		var node: Node3D = part.node
		node.position = part.origin + Vector3.UP * sin(wave) * 2.5 * intensity
		node.rotation.y = sin(wave * 0.7) * 0.45 if part.kind == 1 else wave * 0.2
	update_count += 1
	update_max_ms = maxf(update_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
