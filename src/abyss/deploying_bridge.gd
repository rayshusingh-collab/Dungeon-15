extends Node3D
## One predefined vertical deployment. State/timing live in the streamer, not here.

var deck: StaticBody3D
var marker: MeshInstance3D
var mechanism_position: Vector3
var link: AbyssSpatialLayout.Connection
var box_count: int = 4
var _final: Vector3
var _basis: Basis


func setup(connection: AbyssSpatialLayout.Connection) -> void:
	link = connection
	var tangent := (link.end - link.start).normalized()
	var side := link.direction().cross(Vector3.UP)
	var normal := side.cross(tangent)
	_basis = Basis(tangent, normal, side)
	_final = (link.start + link.end) * 0.5 - normal * 0.25
	deck = StaticBody3D.new()
	deck.collision_layer = 0
	deck.collision_mask = 2
	add_child(deck)
	_box(deck, Vector3.ZERO, Vector3(link.start.distance_to(link.end) + 0.06, 0.5, 4), Color(0.4, 0.48, 0.52))
	for sign_value in [-1.0, 1.0]:
		_box(deck, Vector3(0, 0.85, sign_value * 2), Vector3(link.start.distance_to(link.end) + 0.06, 1.2, 0.3), Color(0.4, 0.48, 0.52))
	mechanism_position = link.start - link.direction() * 2 + side * -2.8
	var pedestal := StaticBody3D.new()
	pedestal.position = mechanism_position + Vector3.UP * 0.5
	pedestal.collision_mask = 2
	add_child(pedestal)
	_box(pedestal, Vector3.ZERO, Vector3(0.65, 1, 0.65), Color(0.65, 0.45, 0.15))
	var title := Label3D.new()
	title.text = "ANCIENT MECHANISM"
	title.position = mechanism_position + Vector3.UP * 2
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.font_size = 48
	title.pixel_size = 0.01
	add_child(title)
	pose(0)


func pose(progress: float) -> void:
	# Entire moving visual/body has layer zero until the streamer commits it.
	deck.transform = Transform3D(_basis, _final - Vector3.UP * 6 * (1 - smoothstep(0, 1, progress)))


func swept_bounds() -> AABB:
	var low := link.start.min(link.end) - Vector3(0.65, 6.7, 2.65)
	var high := link.start.max(link.end) + Vector3(0.65, 2, 2.65)
	return AABB(low, high - low)


func _box(body: StaticBody3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.position = at
	collider.shape = shape
	body.add_child(collider)
