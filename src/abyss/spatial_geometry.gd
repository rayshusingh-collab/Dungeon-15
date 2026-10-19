extends Node3D
## One static section per logical room/link. No streaming or per-frame generation.

const Validator = preload("res://src/abyss/spatial_validator.gd")
var box_count: int = 0
var build_msec: float = 0
var mesh_count: int = 0
var _meshes: Dictionary = {}
var _material: StandardMaterial3D


func build(layout: AbyssSpatialLayout) -> bool:
	# Fail before creating any nodes. A builder instance owns one immutable build.
	if not Validator.validate(layout).is_empty() or get_child_count() != 0:
		return false
	var started := Time.get_ticks_usec()
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.32, 0.37, 0.41)
	for room in layout.rooms:
		var section := Node3D.new()
		section.name = "Room_%d" % room.id
		section.position = room.center
		add_child(section)
		_box(section, Vector3(0, -0.25, 0), Vector3(room.size.x, 0.5, room.size.y))
		var openings: Dictionary = {}
		for link in layout.connections:
			if link.a == room.id:
				openings[link.direction()] = link.width
			elif link.b == room.id:
				openings[-link.direction()] = link.width
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var along_x: bool = absf(direction.z) > 0.5
			var length: float = room.size.x if along_x else room.size.y
			var side_center: Vector3 = room.socket(direction) - room.center + Vector3.UP * 0.6
			var width: float = openings.get(direction, 0.0)
			if width == 0:
				_box(section, side_center, Vector3(length + 0.3, 1.2, 0.3) if along_x else Vector3(0.3, 1.2, length + 0.3))
			else:
				var segment := (length - width) * 0.5
				for sign_value in [-1.0, 1.0]:
					var offset: float = sign_value * (length + width) * 0.25
					_box(section, side_center + (Vector3.RIGHT if along_x else Vector3.BACK) * offset,
						Vector3(segment, 1.2, 0.3) if along_x else Vector3(0.3, 1.2, segment))
		var title := "CHAMBER %d" % room.id
		if room.id == layout.graph.entry_id():
			title = "ENTRY"
		elif room.id == layout.graph.objective_id():
			title = "EXIT"
		_label(section, title + " / %.0f m" % room.center.y, Vector3(0, 2, 0))
	for link in layout.connections:
		var section := Node3D.new()
		section.name = "Link_%d" % link.id
		add_child(section)
		var tangent := (link.end - link.start).normalized()
		var side := link.direction().cross(Vector3.UP)
		var normal := side.cross(tangent)
		var basis := Basis(tangent, normal, side)
		var length := link.start.distance_to(link.end)
		var center := (link.start + link.end) * 0.5
		_box(section, center - normal * 0.25, Vector3(length + 0.06, 0.5, link.width), basis)
		for sign_value in [-1.0, 1.0]:
			_box(section, center + Vector3.UP * 0.6 + side * link.width * 0.5 * sign_value,
				Vector3(length + 0.06, 1.2, 0.3), basis)
	build_msec = (Time.get_ticks_usec() - started) / 1000.0
	mesh_count = _meshes.size()
	return true


func _box(parent: Node3D, at: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	if not _meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _material
		_meshes[size] = mesh
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, at)
	body.collision_mask = 2
	parent.add_child(body)
	var instance := MeshInstance3D.new()
	instance.mesh = _meshes[size]
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	box_count += 1


func _label(parent: Node3D, title: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = title
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.012
	parent.add_child(label)
