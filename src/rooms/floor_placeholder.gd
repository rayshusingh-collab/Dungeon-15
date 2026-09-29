@tool
class_name FloorPlaceholder
extends Node2D
## Placeholder floor: a flat colour with a faint grid so movement reads
## clearly. Replace with a TileMapLayer when real tiles exist.

@export var size: Vector2 = Vector2(1152, 648):
	set(value):
		size = value
		queue_redraw()
@export var color: Color = Color(0.09, 0.094, 0.125):
	set(value):
		color = value
		queue_redraw()
@export var grid_color: Color = Color(1, 1, 1, 0.04):
	set(value):
		grid_color = value
		queue_redraw()
@export var cell_size: float = 64.0:
	set(value):
		cell_size = maxf(value, 8.0)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var x := cell_size
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
		x += cell_size
	var y := cell_size
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
		y += cell_size
