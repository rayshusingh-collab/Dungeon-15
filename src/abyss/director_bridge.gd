extends "res://src/abyss/deploying_bridge.gd"
## Reuse Stage 5A poses, sweep and box construction, without a manual pedestal.


func setup(connection: AbyssSpatialLayout.Connection) -> void:
	link = connection
	var tangent := (link.end - link.start).normalized()
	var side := link.direction().cross(Vector3.UP)
	var normal := side.cross(tangent)
	_basis = Basis(tangent, normal, side)
	_final = (link.start + link.end) * 0.5 - normal * 0.25
	box_count = 3
	deck = StaticBody3D.new()
	deck.collision_layer = 0
	deck.collision_mask = 2
	add_child(deck)
	_box(deck, Vector3.ZERO, Vector3(link.start.distance_to(link.end) + 0.06, 0.5, 4), Color(0.45, 0.4, 0.55))
	for sign_value in [-1.0, 1.0]:
		_box(deck, Vector3(0, 0.85, sign_value * 2), Vector3(link.start.distance_to(link.end) + 0.06, 1.2, 0.3), Color(0.45, 0.4, 0.55))
	pose(1)
