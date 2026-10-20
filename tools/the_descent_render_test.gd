extends "res://tools/the_descent_test.gd"

func _suite_name() -> String:
	return "M3 RENDERED UI"

func _get_tests() -> Array[Callable]:
	return [_rendered_run]

func _capture(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width()==1280,"rendered capture "+tag)
	image.save_png("res://.godot/m3_%s.png" % tag)

func _rendered_run() -> bool:
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size=Vector2i(1280,720)
	var run := _start()
	await _ticks(3)
	await _capture("entrance")
	for d in range(1,4):
		await _clear_required(run)
		_check(run.panel.visible and run.buttons[0].visible,"reward panel visible at depth %d" % d)
		await _capture("reward_%d" % d)
		if d==1:
			# Actual mouse press/release on the second reward button.
			var event := InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_LEFT
			event.position=run.buttons[1].get_global_rect().get_center()
			event.pressed=true
			root.push_input(event,true)
			event=event.duplicate()
			event.pressed=false
			root.push_input(event,true)
			_check(run.ranks[1]==1 and run.phase==Run.Phase.PLAYING,"mouse selects Reinforced Guard")
		else:
			_key(KEY_ENTER)
			_key(KEY_ENTER,false)
			_check(run.phase==Run.Phase.PLAYING,"keyboard selects visible reward")
		run.floor_node.player.position=Grid.center(run.floor_node.layout.exit_tile,0.05)
		_key(KEY_E)
		_key(KEY_E,false)
		await _ticks(4)
	_check(run.phase==Run.Phase.VICTORY and run.panel.visible and run.hud.text.contains("completed 3/3") and not run.hud.text.contains("descend"),"vertical-slice victory rendered with completed progress and restart controls")
	await _capture("victory")
	_key(KEY_R)
	_key(KEY_R,false)
	await _ticks(4)
	run.floor_node.player.receive_damage(99,Vector3.ZERO)
	await _ticks(3)
	_check(run.phase==Run.Phase.DEAD and run.panel.visible,"death confirmation rendered")
	await _capture("death")
	return true
