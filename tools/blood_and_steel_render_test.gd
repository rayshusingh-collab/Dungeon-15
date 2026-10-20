extends "res://tools/test_harness.gd"
const Scene = preload("res://src/game_3d/blood_and_steel.tscn")
const Grid = preload("res://src/game_3d/grid_space.gd")
const S = preload("res://src/game_3d/combat/samurai.gd")
const E = preload("res://src/game_3d/combat/demon.gd")

func _suite_name() -> String:
	return "M2 RENDERED COMBAT"

func _get_tests() -> Array[Callable]:
	return [_test_combat_render]

func _capture(label: String) -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://.godot/m2_%s.png" % label)
	return image

func _test_combat_render() -> bool:
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1280,720)
	var scene := Scene.instantiate()
	root.add_child(scene)
	await _frames(3)
	var player: CharacterBody3D=scene.player
	var basic: CharacterBody3D=scene.enemies[0]
	player.position=basic.home+Vector3(0,0,2.15)
	player.facing=Vector3.FORWARD
	scene.camera.set_process(false)
	scene.camera.position=player.position+scene.camera.follow_offset
	await _frames(3)
	await _capture("ready")
	Input.action_press(scene.input_source.combat_actions[0])
	var struck: bool=await _wait_until(func() -> bool: return player.hits_landed==1,20)
	_check(struck and basic.health==2,"real input sword strike contacts visible demon")
	_check(player._arc.visible and scene._contact_fx.visible,"sword sweep and pooled contact burst are visible")
	await _capture("sword_contact")
	Input.action_release(scene.input_source.combat_actions[0])
	await _frames(35)
	for enemy in scene.enemies:
		enemy.set_physics_process(false)
	player.set_physics_process(false)
	var brute: CharacterBody3D=scene.enemies[3]
	player.reset_combat()
	player.position=brute.home+Vector3(0,0,2.5)
	brute._start_attack(player.position)
	brute.set_physics_process(true)
	scene.camera.position=player.position+scene.camera.follow_offset
	await _frames(5)
	_check(brute._telegraph.visible and brute.state==E.State.WINDUP,"brute ground anticipation is visible in the live scene")
	await _capture("brute_warning")
	brute.set_physics_process(false)
	var ranged: CharacterBody3D=scene.enemies[2]
	var found := false
	var room: DungeonLayout.PlacedRoom=scene.layout.rooms[ranged.room_id]
	var bounds := room.bounds()
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var tile := Vector2i(x,y)
			var point := Grid.center(tile,0.05)
			if scene.navigation.clear_spawn(tile) and point.distance_to(ranged.position)>5.5 and point.distance_to(ranged.position)<8 and scene.clear_attack_line(point,ranged.position):
				player.position=point
				found=true
				break
		if found:
			break
	_check(found,"ranged render scenario has a real safe firing lane")
	ranged.reset_enemy()
	ranged.set_physics_process(true)
	scene.camera.position=(player.position+ranged.position)*0.5+scene.camera.follow_offset
	var fired: bool=await _wait_until(func() -> bool: return scene.projectile_root.get_child_count()>0,90)
	_check(fired,"ranged anticipation produces a visible projectile")
	await _frames(20)
	var visible_shot: Node3D=scene.projectile_root.get_child(0)
	# Freeze after real flight so render-thread latency cannot offset the pixel probe.
	visible_shot.set_physics_process(false)
	var image := await _capture("ranged_shot")
	var logical: Vector2=scene.camera.unproject_position(visible_shot.global_position)
	# Project canvas stretch maps logical camera coordinates into screenshot pixels.
	var point: Vector2i=Vector2i(root.get_final_transform()*logical)
	var bright := 0
	for dy in range(-1,2):
		for dx in range(-1,2):
			var color := image.get_pixelv(point+Vector2i(dx,dy))
			bright+=int(color.r>0.7 and color.r>color.b*1.4)
	print("M2_PROJECTILE_PIXEL at=",point," orange_pixels=",bright," logical_view=",root.get_visible_rect().size," output=",image.get_size())
	_check(bright>=2,"projectile core is visibly orange at its actual projected position")
	ranged.set_physics_process(false)
	for shot in scene.projectile_root.get_children():
		shot.queue_free()
	player.reset_combat()
	player.receive_damage(1,Vector3.ZERO)
	await _frames(2)
	_check(scene.damage_overlay.color.a>0 and scene.health_bar.value==7,"damage flash and health display update together")
	await _capture("hurt")
	player.reset_combat()
	player.set_physics_process(true)
	player.receive_damage(99,Vector3.ZERO)
	await _frames(20)
	_check(scene.status.text.contains("YOU DIED") and player.visual.rotation.z<-1,"death pose and restart instruction are visible")
	await _capture("death")
	var key := InputEventKey.new()
	key.physical_keycode=KEY_R
	key.pressed=true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	key=key.duplicate()
	key.pressed=false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _frames(5)
	scene.camera.position=player.position+scene.camera.follow_offset
	_check(player.health==8 and scene.enemies.all(func(e: CharacterBody3D) -> bool: return not e.is_dead()),"rendered R restart restores the playable floor")
	await _capture("restart")
	scene.queue_free()
	await process_frame
	return true
