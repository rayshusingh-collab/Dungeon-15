extends CanvasLayer
## Temporary, 5 Hz diagnostics. F3 toggles without altering project input actions.

@export var input_source: Node
@export var player: CharacterBody3D
var _label: Label
var _elapsed: float = 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 155)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	_elapsed += delta
	if visible and _elapsed >= 0.2:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	var lines := PackedStringArray(["Controller diagnostics (F3 to hide)"])
	var devices := Input.get_connected_joypads()
	lines.append("Connected IDs: %s | selected: %d" % [str(devices), input_source.device_id])
	if devices.is_empty():
		lines.append("DISCONNECTED / no controller detected; keyboard remains available")
	for device in devices:
		lines.append("ID %d: %s | known mapping: %s" % [device, Input.get_joy_name(device), Input.is_joy_known(device)])
		lines.append("GUID: %s" % Input.get_joy_guid(device))
		var axes := PackedStringArray()
		for axis in JOY_AXIS_MAX:
			axes.append("%d:%.2f" % [axis, Input.get_joy_axis(device, axis)])
		lines.append("Axes " + " ".join(axes))
		var buttons := PackedStringArray()
		for button in JOY_BUTTON_MAX:
			if Input.is_joy_button_pressed(device, button):
				buttons.append(str(button))
		lines.append("Held button indices: " + ", ".join(buttons))
	lines.append(input_source.connection_event + " | " + input_source.last_event)
	lines.append("Last button: " + input_source.last_button_event)
	lines.append("Input %s | deadzone %.2f | axes %d/%d" % [str(input_source.movement_vector()),
		input_source.deadzone, input_source.horizontal_axis, input_source.vertical_axis])
	lines.append("World velocity %s" % str(player.velocity))
	lines.append("World position %s | elevation %.2f m" % [str(player.global_position), player.global_position.y])
	_label.text = "\n".join(lines)
