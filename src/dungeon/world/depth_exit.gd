class_name DepthExit
extends Area2D
## The objective of a depth: stepping on it completes the depth. Sealed while
## the objective room's encounter (if any) is unresolved.

signal reached

const SIZE := Vector2(64, 64)

var sealed: bool = false

var _used: bool = false
var _time: float = 0.0


func setup(center: Vector2, start_sealed: bool) -> void:
	position = center
	sealed = start_sealed
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = SIZE * 0.7
	var node := CollisionShape2D.new()
	node.shape = shape
	add_child(node)
	body_entered.connect(_on_body_entered)


func set_sealed(value: bool) -> void:
	sealed = value
	queue_redraw()
	# The player may already be standing on it when it unseals.
	if not sealed:
		for body in get_overlapping_bodies():
			_on_body_entered(body)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if sealed or _used or not body is Player:
		return
	_used = true
	reached.emit()


func _draw() -> void:
	var half := SIZE / 2.0
	var font := ThemeDB.fallback_font
	if sealed:
		draw_rect(Rect2(-half, SIZE), Color(0.3, 0.3, 0.35))
		draw_line(-half * 0.6, half * 0.6, Color(0.9, 0.3, 0.3), 4.0)
		draw_line(Vector2(half.x, -half.y) * 0.6, Vector2(-half.x, half.y) * 0.6, Color(0.9, 0.3, 0.3), 4.0)
		_label(font, "SEALED", Color(0.9, 0.4, 0.4))
		return
	var glow := 0.6 + 0.4 * sin(_time * 3.0)
	# Descending steps: nested squares getting darker toward the centre.
	for i in 4:
		var s := SIZE * (1.0 - i * 0.22)
		draw_rect(Rect2(-s / 2.0, s), Color(0.95, 0.8, 0.3).darkened(i * 0.22))
	draw_rect(Rect2(-half, SIZE), Color(1, 0.9, 0.5, glow), false, 3.0)
	_label(font, "EXIT", Color(1, 0.9, 0.5))


func _label(font: Font, text: String, color: Color) -> void:
	var pos := Vector2(-60, -SIZE.y / 2.0 - 10)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 5, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, color)
