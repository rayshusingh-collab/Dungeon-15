class_name HealthDisplay
extends Control
## Placeholder heart row + "current/max" text. Lost hearts flash when hit.

@export var heart_size: float = 26.0
@export var spacing: float = 6.0
@export var full_color: Color = Color(0.93, 0.25, 0.33)
@export var empty_color: Color = Color(0.25, 0.22, 0.28, 0.9)
@export var font_size: int = 20

var _current: int = 0
var _maximum: int = 0
var _flash: float = 0.0
var _flash_tween: Tween


func set_health(current: int, maximum: int) -> void:
	var lost := current < _current
	_current = current
	_maximum = maximum
	if lost:
		if _flash_tween != null:
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(_set_flash, 1.0, 0.0, 0.45)
	queue_redraw()


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


func _draw() -> void:
	var step := heart_size + spacing
	var center_y := size.y / 2.0
	for i in _maximum:
		var center := Vector2(heart_size / 2.0 + i * step, center_y)
		var color := full_color if i < _current else empty_color
		if i >= _current and _flash > 0.0:
			color = empty_color.lerp(Color.WHITE, _flash)
		_draw_heart(center, heart_size, color)
	var font := get_theme_default_font()
	var text := "%d/%d" % [_current, _maximum]
	var text_pos := Vector2(_maximum * step + 4.0, center_y + font_size * 0.35)
	draw_string_outline(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color.BLACK)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_heart(center: Vector2, s: float, color: Color) -> void:
	var lobe := s * 0.27
	draw_circle(center + Vector2(-s * 0.23, -s * 0.12), lobe, color)
	draw_circle(center + Vector2(s * 0.23, -s * 0.12), lobe, color)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-s * 0.49, -s * 0.04),
		center + Vector2(s * 0.49, -s * 0.04),
		center + Vector2(0.0, s * 0.46),
	]), color)
