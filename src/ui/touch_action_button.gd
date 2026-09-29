class_name TouchActionButton
extends Control
## Multi-touch on-screen button that holds an InputMap action while touched.
## The Control's rect is the touch area; a labelled circle is drawn at its
## centre, with a dark pie overlay while the action is on cooldown.

enum Icon { NONE, SWORD, DODGE }

@export var action: StringName = &"attack"
@export var label: String = "ATTACK"
@export var icon: Icon = Icon.NONE
@export var radius: float = 60.0
@export var fill_color: Color = Color(0.75, 0.22, 0.22, 0.6)
@export var label_font_size: int = 16

## 0 = ready, 1 = just used.
var cooldown_ratio: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, cooldown_ratio):
			cooldown_ratio = value
			queue_redraw()

var _touch_index: int = -1


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not is_visible_in_tree():
		return
	if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
		_touch_index = touch.index
		Input.action_press(action)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _touch_index:
		release()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release()


func _exit_tree() -> void:
	release()


func is_pressed() -> bool:
	return _touch_index != -1


func release() -> void:
	if _touch_index == -1:
		return
	_touch_index = -1
	Input.action_release(action)
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var r := radius * (0.92 if is_pressed() else 1.0)
	draw_circle(center, r, fill_color.lightened(0.3) if is_pressed() else fill_color)
	if cooldown_ratio > 0.0:
		_draw_pie(center, r, minf(cooldown_ratio, 0.999), Color(0, 0, 0, 0.55))
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 3.0, true)
	_draw_icon(center + Vector2(0.0, -r * 0.16), r * 0.32)
	var font := get_theme_default_font()
	var text_pos := Vector2(center.x - r, center.y + r * 0.55)
	draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, label_font_size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, label_font_size, Color.WHITE)


func _draw_icon(c: Vector2, s: float) -> void:
	var white := Color(1, 1, 1, 0.95)
	match icon:
		Icon.SWORD:
			draw_line(c + Vector2(-0.6, 0.6) * s, c + Vector2(0.85, -0.85) * s, white, 5.0)
			draw_line(c + Vector2(-0.75, 0.05) * s, c + Vector2(-0.05, 0.75) * s, white, 5.0)
			draw_line(c + Vector2(-0.6, 0.6) * s, c + Vector2(-0.95, 0.95) * s, white, 6.0)
		Icon.DODGE:
			for x: float in [-0.55, 0.15]:
				draw_polyline(PackedVector2Array([
					c + Vector2(x - 0.2, -0.65) * s,
					c + Vector2(x + 0.4, 0.0) * s,
					c + Vector2(x - 0.2, 0.65) * s,
				]), white, 5.0)


func _draw_pie(center: Vector2, r: float, ratio: float, color: Color) -> void:
	var segments := maxi(3, int(48.0 * ratio))
	var points := PackedVector2Array([center])
	for i in segments + 1:
		points.append(center + Vector2.from_angle(-PI / 2.0 + TAU * ratio * i / segments) * r)
	draw_colored_polygon(points, color)
