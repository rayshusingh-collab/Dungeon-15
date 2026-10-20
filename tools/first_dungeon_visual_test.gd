extends "res://tools/test_harness.gd"
## Real rendered pixel probes, run WITHOUT --headless. Physical behavior has its own suite.
const Grid = preload("res://src/game_3d/grid_space.gd")

func _suite_name() -> String:
	return "M1.1 RENDERED HAZARD VISIBILITY"

func _get_tests() -> Array[Callable]:
	return [_test_rendered_fixture]

func _test_rendered_fixture() -> bool:
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1280,720)
	var scene := preload("res://src/game_3d/hazard_validation.tscn").instantiate()
	root.add_child(scene)
	await _frames(4)
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.camera.set_process(false)
	var floor_image := await _capture(scene,Vector2i(4,10),"safe_floor",0.2)
	var pit_image := await _capture(scene,Vector2i(9,2),"pit",0.2)
	var floor_dark := _count(floor_image,"dark")
	var pit_dark := _count(pit_image,"dark")
	print("PIXELS floor_dark=",floor_dark," pit_dark=",pit_dark)
	_check(pit_dark>floor_dark+1500, "pit is a dark recessed opening distinct from safe floor in real isometric render")
	var bridge_image := await _capture(scene,Vector2i(10,5),"bridge",0.2)
	var bridge_pixels := _count(bridge_image,"wood")
	print("PIXELS bridge_wood=",bridge_pixels)
	_check(bridge_pixels>1500, "bridge traversal surface clearly visible between pit openings")
	var water_image := await _capture(scene,Vector2i(10,11),"water",0.2)
	var water_pixels := _count(water_image,"water")
	print("PIXELS water=",water_pixels)
	_check(water_pixels>2000, "water occupies a substantial teal ripple region in isometric render")
	await _capture(scene,Vector2i(16,5),"spikes_safe",0.2)
	_check(not scene.spike_tips.visible and scene.geometry.has_node("RetractedSpikeSockets"), "retracted state retains visible socket geometry")
	var warning := await _capture(scene,Vector2i(16,5),"spikes_warning",scene.safe_seconds+0.1)
	var warning_pixels := _count(warning,"amber")
	var raised := await _capture(scene,Vector2i(16,5),"spikes_raised",scene.safe_seconds+0.7)
	var raised_pixels := _count(raised,"red")
	print("PIXELS warning_amber=",warning_pixels," raised_red=",raised_pixels)
	_check(warning_pixels>2000 and scene.spike_tips.visible, "warning state visibly amber")
	_check(raised_pixels>2000, "active state visibly red with raised tips")
	# Full entry view for manual readability assessment.
	await _capture(scene,scene.layout.player_spawn,"fixture_entry",0.2)
	scene.queue_free()
	await process_frame
	return true

func _capture(scene: Node3D,tile: Vector2i,label: String,time: float) -> Image:
	scene.elapsed=time
	scene._physics_process(0.0)
	scene.camera.position=Grid.center(tile)+scene.camera.follow_offset
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("res://.godot/m11_%s.png" % label)
	return result

func _count(img: Image,kind: String) -> int:
	var count := 0
	for y in range(280,480):
		for x in range(480,800):
			var c := img.get_pixel(x,y)
			match kind:
				"dark": count+=int(c.r<0.19 and c.g<0.19 and c.b<0.22)
				"wood": count+=int(c.r>0.3 and c.r>c.g*1.15 and c.g>c.b*1.4)
				"water": count+=int(c.g>0.2 and c.g>c.r*1.7 and c.b>c.r*1.8)
				"amber": count+=int(c.r>0.6 and c.g>0.4 and c.b<c.g*0.7)
				"red": count+=int(c.r>0.6 and c.g<c.r*0.5 and c.b<c.r*0.5)
	return count
