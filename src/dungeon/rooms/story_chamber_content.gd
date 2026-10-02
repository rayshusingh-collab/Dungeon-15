@tool
extends Node2D
## Placeholder authored content for the special story chamber: a monument at
## the room anchor. Proves handcrafted content can ride on a generated room.
## Decoration only: it adds no collision (the layout owns geometry).

@export var color: Color = Color(0.35, 0.9, 0.85, 0.9)

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	draw_circle(Vector2.ZERO, 46.0, Color(color, 0.08 + 0.06 * pulse))
	draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 48, Color(color, 0.6), 2.0)
	draw_arc(Vector2.ZERO, 30.0 + 4.0 * pulse, 0.0, TAU, 40, Color(color, 0.45), 2.0)
	draw_rect(Rect2(-10, -18, 20, 36), Color(color, 0.85))
