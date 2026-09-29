@tool
class_name PlaceholderCircle
extends Node2D
## Temporary circle visual for actors. Gameplay code must not depend on this
## node; replace it with a sprite/animation scene when real art exists.

@export var radius: float = 16.0:
	set(value):
		radius = value
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
## Inner circle drawn on top of the body. 0 disables it.
@export var core_radius: float = 0.0:
	set(value):
		core_radius = value
		queue_redraw()
@export var core_color: Color = Color.BLACK:
	set(value):
		core_color = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	if core_radius > 0.0:
		draw_circle(Vector2.ZERO, core_radius, core_color)
