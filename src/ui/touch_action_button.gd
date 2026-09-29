class_name TouchActionButton
extends Control
## Multi-touch on-screen button that presses an InputMap action while held.
## The Control's rect is the touch area; a circle is drawn at its centre.

@export var action: StringName = &"attack"
@export var radius: float = 55.0
@export var idle_color: Color = Color(0.7, 0.2, 0.2, 0.65)
@export var pressed_color: Color = Color(0.9, 0.35, 0.35, 0.85)

var _touch_index: int = -1


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
		_touch_index = touch.index
		Input.action_press(action)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _touch_index:
		_release()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release()


func _draw() -> void:
	draw_circle(size / 2.0, radius, pressed_color if _touch_index != -1 else idle_color)


func _release() -> void:
	if _touch_index == -1:
		return
	_touch_index = -1
	Input.action_release(action)
	queue_redraw()
