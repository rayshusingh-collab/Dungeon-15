extends "res://src/game_3d/gamepad_input.gd"
## Private edge-triggered actions. Parent owns movement; no shared binding changes.
@export var attack_button: int = JOY_BUTTON_A
@export var dodge_button: int = JOY_BUTTON_B
var combat_actions: Array[StringName] = []
var _held := [false,false]
var _pending := [false,false]

func _ready() -> void:
	super._ready()
	for verb in ["attack","dodge"]:
		var action := StringName("d15_combat_%d_%s" % [get_instance_id(),verb])
		combat_actions.append(action)
		InputMap.add_action(action)
	_bind_combat()

func bind_device(selected: int) -> void:
	super.bind_device(selected)
	_bind_combat()

func _bind_combat() -> void:
	for i in combat_actions.size():
		var action := combat_actions[i]
		Input.action_release(action)
		InputMap.action_erase_events(action)
		_held[i]=false
		_pending[i]=false
		for code: int in ([KEY_SPACE,KEY_J] if i==0 else [KEY_SHIFT,KEY_K]):
			var key := InputEventKey.new()
			key.physical_keycode=code
			InputMap.action_add_event(action,key)
		if device_id>=0:
			var button := InputEventJoypadButton.new()
			button.device=device_id
			button.button_index=attack_button if i==0 else dodge_button
			InputMap.action_add_event(action,button)

func edges() -> Vector2i:
	var result := Vector2i.ZERO
	for i in combat_actions.size():
		var pressed := Input.is_action_pressed(combat_actions[i])
		# Rising edges only: held keys, autorepeat and alternating sources cannot spam.
		if _pending[i] or (pressed and not _held[i]):
			result[i]=1
		_held[i]=pressed
		_pending[i]=false
	return result

func _input(event: InputEvent) -> void:
	super._input(event)
	for i in combat_actions.size():
		if event.is_action_pressed(combat_actions[i],false):
			if not _held[i]:
				_pending[i]=true
			_held[i]=true
		elif event.is_action_released(combat_actions[i]):
			_held[i]=Input.is_action_pressed(combat_actions[i])

func _exit_tree() -> void:
	for action in combat_actions:
		Input.action_release(action)
		InputMap.erase_action(action)
	super._exit_tree()
