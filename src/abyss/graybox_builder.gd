extends Node3D
## Reusable box meshes/materials; simple static layer-1 collision, mask 2.
## Stair treads are visual: a continuous ramp supports the unchanged P1A body.

const Plan = preload("res://src/abyss/vertical_plan.gd")
var piece_count: int = 0
var build_msec: float = 0.0
var _meshes: Dictionary = {}
var _material: StandardMaterial3D


func _ready() -> void:
	var started := Time.get_ticks_usec()
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.32, 0.37, 0.41)
	var sockets := Plan.route()
	assert(Plan.validate(sockets).is_empty())
	for center in [sockets[0], sockets[3], sockets[7]]:
		_box(center - Vector3(0, 0.25, 0), Vector3(12, 0.5, 12))
		for side in [-1.0, 1.0]:
			_box(center + Vector3(0, 0.5, side * 6), Vector3(12.5, 1, 0.4))
			for end in [-1.0, 1.0]:
				_box(center + Vector3(end * 6, 0.5, side * 4), Vector3(0.4, 1, 4))
	# Close the two exterior ends; internal 4 m openings stay unobstructed.
	_box(Vector3(-6, 0.5, 0), Vector3(0.4, 1, 4))
	_box(Vector3(60, 8.5, 0), Vector3(0.4, 1, 4))
	_bridge(sockets[4], sockets[5])
	_stairs(sockets[1], sockets[2])
	_stairs(sockets[5], sockets[6])
	build_msec = (Time.get_ticks_usec() - started) / 1000.0
	print("ABYSS build: %.2f ms, %d boxes, %d unique meshes" % [build_msec, piece_count, _meshes.size()])


func _bridge(a: Vector3, b: Vector3) -> void:
	_box((a + b) * 0.5 - Vector3(0, 0.25, 0), Vector3(b.x - a.x, 0.5, 4))
	for side in [-1.0, 1.0]:
		_box((a + b) * 0.5 + Vector3(0, 0.5, side * 2), Vector3(b.x - a.x, 1, 0.3))


func _stairs(a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var angle := atan2(delta.y, delta.x)
	var basis := Basis(Vector3.BACK, angle)
	# Top surface follows socket line exactly. Small end overlaps avoid seams.
	var center := (a + b) * 0.5 - basis.y * 0.15
	_box(center, Vector3(delta.length() + 0.08, 0.3, 4), angle, false)
	for side in [-1.0, 1.0]:
		_box((a + b) * 0.5 + Vector3(0, 0.55, side * 2), Vector3(delta.length() + 0.08, 1.1, 0.3), angle)
	for i in 24:
		var t := (i + 0.5) / 24.0
		# Tread tops lie below the continuous collision surface.
		_box(a.lerp(b, t) - Vector3(0, 0.16, 0), Vector3(0.5, 0.16, 3.7), 0.0, true, false)


func _box(at: Vector3, size: Vector3, angle: float = 0.0,
		visible_mesh: bool = true, collision: bool = true) -> void:
	var node := Node3D.new()
	node.position = at
	node.rotation.z = angle
	add_child(node)
	if visible_mesh:
		if not _meshes.has(size):
			var mesh := BoxMesh.new()
			mesh.size = size
			mesh.material = _material
			_meshes[size] = mesh
		var instance := MeshInstance3D.new()
		instance.mesh = _meshes[size]
		node.add_child(instance)
	if collision:
		var body := StaticBody3D.new()
		body.collision_mask = 2
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		node.add_child(body)
	piece_count += 1
