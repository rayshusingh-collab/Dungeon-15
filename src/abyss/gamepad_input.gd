extends Node
## Scene-owned actions: shared 2D/P1A move_* bindings are never edited.
## Indices below are Godot logical mappings, not assumed physical button labels.

@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.22
@export var preferred_device: int = -1
@export var horizontal_axis: int = JOY_AXIS_LEFT_X
@export var vertical_axis: int = JOY_AXIS_LEFT_Y
@export var invert_horizontal: bool = false
@export var invert_vertical: bool = false
@export var dpad_left: int = JOY_BUTTON_DPAD_LEFT
@export var dpad_right: int = JOY_BUTTON_DPAD_RIGHT
@export var dpad_up: int = JOY_BUTTON_DPAD_UP
@export var dpad_down: int = JOY_BUTTON_DPAD_DOWN
## Optional hat axes for devices exposing the D-pad as motion rather than buttons.
@export var dpad_horizontal_axis: int = -1
@export var dpad_vertical_axis: int = -1
@export var invert_dpad_horizontal: bool = false
@export var invert_dpad_vertical: bool = false

var device_id: int = -1
var actions: Array[StringName] = []
var last_event: String = "No joypad events yet"
var last_button_event: String = "No button events yet"
var connection_event: String = "Startup"


func _ready() -> void:
	for direction in ["left", "right", "up", "down"]:
		var action := StringName("abyss_%d_%s" % [get_instance_id(), direction])
		actions.append(action)
		InputMap.add_action(action, deadzone)
	Input.joy_connection_changed.connect(_connection_changed)
	select_connected_device()


func select_connected_device() -> void:
	var devices := Input.get_connected_joypads()
	var selected := -1
	if preferred_device >= 0:
		if devices.has(preferred_device):
			selected = preferred_device
	elif devices.has(device_id):
		selected = device_id
	elif not devices.is_empty():
		selected = devices[0]
	if selected != device_id:
		bind_device(selected)


func bind_device(selected: int) -> void:
	device_id = selected
	var axes := [horizontal_axis, horizontal_axis, vertical_axis, vertical_axis]
	var signs := [-1.0, 1.0, -1.0, 1.0]
	var buttons := [dpad_left, dpad_right, dpad_up, dpad_down]
	var hat_axes := [dpad_horizontal_axis, dpad_horizontal_axis, dpad_vertical_axis, dpad_vertical_axis]
	for i in actions.size():
		Input.action_release(actions[i])
		InputMap.action_erase_events(actions[i])
		InputMap.action_set_deadzone(actions[i], deadzone)
		if device_id < 0:
			continue
		if axes[i] >= 0 and axes[i] < JOY_AXIS_MAX:
			var motion := InputEventJoypadMotion.new()
			motion.device = device_id
			motion.axis = axes[i]
			var inverted := invert_horizontal if i < 2 else invert_vertical
			motion.axis_value = signs[i] * (-1.0 if inverted else 1.0)
			InputMap.action_add_event(actions[i], motion)
		if hat_axes[i] >= 0 and hat_axes[i] < JOY_AXIS_MAX:
			var hat := InputEventJoypadMotion.new()
			hat.device = device_id
			hat.axis = hat_axes[i]
			var hat_inverted := invert_dpad_horizontal if i < 2 else invert_dpad_vertical
			hat.axis_value = signs[i] * (-1.0 if hat_inverted else 1.0)
			InputMap.action_add_event(actions[i], hat)
		if buttons[i] >= 0 and buttons[i] < JOY_BUTTON_MAX:
			var button := InputEventJoypadButton.new()
			button.device = device_id
			button.button_index = buttons[i]
			InputMap.action_add_event(actions[i], button)


func movement_vector() -> Vector2:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var joy := Vector2.ZERO
	if device_id >= 0 and actions.size() == 4:
		joy = Input.get_vector(actions[0], actions[1], actions[2], actions[3], deadzone)
	return (keyboard + joy).limit_length(1.0)


func _connection_changed(device: int, connected: bool) -> void:
	connection_event = "Device %d %s" % [device, "connected" if connected else "disconnected"]
	print("ABYSS controller: ", connection_event)
	select_connected_device()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		last_event = "device %d axis %d = %.3f" % [event.device, event.axis, event.axis_value]
	elif event is InputEventJoypadButton:
		last_event = "device %d button %d %s pressure %.3f" % [event.device,
			event.button_index, "pressed" if event.pressed else "released", event.pressure]
		last_button_event = last_event


func _exit_tree() -> void:
	for action in actions:
		Input.action_release(action)
		InputMap.erase_action(action)
