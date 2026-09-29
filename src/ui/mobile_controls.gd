class_name MobileControls
extends CanvasLayer
## On-screen touch controls: native VirtualJoystick (move_*) plus labelled
## TouchActionButtons (attack, dodge). Gameplay never references this node;
## it only presses InputMap actions.


func set_cooldown(action: StringName, ratio: float) -> void:
	for button in _buttons():
		if button.action == action:
			button.cooldown_ratio = ratio


## Shows/hides all controls. Hiding releases any held button.
func set_active(active: bool) -> void:
	for child in get_children():
		var control := child as Control
		if control != null:
			control.visible = active
	if not active:
		for button in _buttons():
			button.release()


func is_active() -> bool:
	for child in get_children():
		var control := child as Control
		if control != null and control.visible:
			return true
	return false


func _buttons() -> Array[TouchActionButton]:
	var result: Array[TouchActionButton] = []
	for child in get_children():
		if child is TouchActionButton:
			result.append(child)
	return result
