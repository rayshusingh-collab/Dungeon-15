extends CanvasLayer

@onready var joystick_base = $JoystickBase
@onready var joystick_knob = $JoystickKnob

var joystick_direction := Vector2.ZERO
var joystick_radius := 60.0

var active_touch_id := -1
var joystick_center := Vector2.ZERO


func _ready():
	joystick_center = joystick_base.position
	joystick_knob.position = joystick_center


func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if active_touch_id == -1:
				if event.position.distance_to(joystick_center) <= joystick_radius:
					active_touch_id = event.index
					update_joystick(event.position)
		else:
			if event.index == active_touch_id:
				active_touch_id = -1
				reset_joystick()

	elif event is InputEventScreenDrag:
		if event.index == active_touch_id:
			update_joystick(event.position)


func update_joystick(touch_position: Vector2):
	var offset = touch_position - joystick_center

	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius

	joystick_knob.position = joystick_center + offset

	if offset.length() < 8.0:
		joystick_direction = Vector2.ZERO
	else:
		joystick_direction = offset.normalized()


func reset_joystick():
	joystick_knob.position = joystick_center
	joystick_direction = Vector2.ZERO
