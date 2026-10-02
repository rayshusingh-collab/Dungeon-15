class_name EncounterGate
extends StaticBody2D
## Seals one doorway of a combat room while its encounter is active.
## DORMANT: open, faint red hint (a fight waits here). LOCKED: solid, barred.
## OPEN: cleared, faint green threshold.

enum State { DORMANT, LOCKED, OPEN }

var size: Vector2 = Vector2(96, 32)
var state: State = State.DORMANT

var _shape_node: CollisionShape2D


func setup(center: Vector2, gate_size: Vector2) -> void:
	position = center
	size = gate_size
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = gate_size
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = shape
	_shape_node.disabled = true
	add_child(_shape_node)


func set_state(new_state: State) -> void:
	state = new_state
	# Deferred: gates change while physics callbacks (trigger overlaps) run.
	_shape_node.set_deferred(&"disabled", new_state != State.LOCKED)
	queue_redraw()


func is_blocking() -> bool:
	return state == State.LOCKED


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	match state:
		State.DORMANT:
			draw_rect(rect, Color(0.85, 0.25, 0.25, 0.14))
			draw_rect(rect, Color(0.85, 0.3, 0.3, 0.35), false, 1.0)
		State.LOCKED:
			draw_rect(rect, Color("8e2a36"))
			var horizontal := size.x > size.y
			for i in 5:
				var t := (i + 1) / 6.0
				if horizontal:
					var x := rect.position.x + size.x * t
					draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0, 0, 0, 0.45), 3.0)
				else:
					var y := rect.position.y + size.y * t
					draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0, 0, 0, 0.45), 3.0)
			draw_rect(rect, Color(1, 0.6, 0.6, 0.8), false, 2.0)
		State.OPEN:
			draw_rect(rect, Color(0.3, 0.9, 0.5, 0.12))
