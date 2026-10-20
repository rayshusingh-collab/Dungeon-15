extends Node
## Scene-owned action. Unknown pads require actual button capture, never Xbox IDs.

signal interacted
@export var movement_input: Node
var action: StringName
var device_id: int = -1
var button_index: int = -1
var mapping_status: String = "Keyboard E; no controller selected"
var calibrating: bool = false
var _guid: String = ""
var _captured: Dictionary = {}


func _ready() -> void:
	action = StringName("abyss_interact_%d" % get_instance_id())
	InputMap.add_action(action)
	configure_device(-1, false, "")


func _process(_delta: float) -> void:
	var selected: int = movement_input.device_id
	if selected != device_id:
		configure_device(selected, Input.is_joy_known(selected) if selected >= 0 else false,
			Input.get_joy_guid(selected) if selected >= 0 else "")


func configure_device(device: int, known: bool, guid: String) -> void:
	device_id = device
	_guid = guid if not guid.is_empty() else "device:%d" % device
	calibrating = false
	button_index = _captured.get(_guid, JOY_BUTTON_A if known else -1) if device >= 0 else -1
	_rebind()
	if device < 0:
		mapping_status = "Keyboard E; no controller selected"
	elif button_index < 0:
		mapping_status = "Unknown pad: F4, then press its SOUTH face button"
	else:
		mapping_status = "Device %d south = Godot button %d (%s); F4 to verify/rebind" % [
			device, button_index, "captured" if _captured.has(_guid) else "recognized mapping"]


func _rebind() -> void:
	Input.action_release(action)
	InputMap.action_erase_events(action)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	InputMap.action_add_event(action, key)
	if device_id >= 0 and button_index >= 0:
		var button := InputEventJoypadButton.new()
		button.device = device_id
		button.button_index = button_index
		InputMap.action_add_event(action, button)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		if device_id >= 0:
			calibrating = true
			mapping_status = "Press the physical SOUTH face button now; release, then press again to interact"
		return
	if calibrating and event is InputEventJoypadButton and event.device == device_id and event.pressed:
		_captured[_guid] = event.button_index
		configure_device(device_id, false, _guid)
		return
	if not calibrating and event.is_action_pressed(action) and not event.is_echo():
		interacted.emit()


func _exit_tree() -> void:
	if InputMap.has_action(action):
		Input.action_release(action)
		InputMap.erase_action(action)
