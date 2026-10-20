extends SceneTree
## Run with --fixed-fps 60. Fixed simulation steps make on/off AI schedules comparable.
const Scene = preload("res://src/game_3d/the_descent.tscn")
const Grid = preload("res://src/game_3d/grid_space.gd")
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size=Vector2i(1280,720)
	var run := Scene.instantiate()
	root.add_child(run)
	# Benchmark only: build Depth 3 directly, with a fresh stationary target.
	run.floor_node.free()
	run.depth=3
	run._build_floor()
	var scene: Node3D=run.floor_node
	await process_frame
	scene.camera.set_process(false)
	var results: Array = []
	var realtime := OS.get_cmdline_user_args().has("--realtime")
	for mode in ["entry_vsync","entry_uncapped","active_vsync","active_uncapped"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if mode.ends_with("vsync") else DisplayServer.VSYNC_DISABLED)
		for shot in scene.projectile_root.get_children():
			shot.queue_free()
		scene.elapsed=0
		scene.player.position=Grid.center(scene.layout.player_spawn,0.05)
		scene.player.reset_combat()
		for enemy in scene.enemies:
			enemy.reset_enemy()
		await process_frame
		await process_frame
		if mode.begins_with("active"):
			scene.player.position=_active_target(scene)
			# Benchmark-only stationary invulnerable target keeps AI running for all samples.
			scene.player.hurt_grace=999
		scene.camera.position=scene.player.position+scene.camera.follow_offset
		var warm_start := Time.get_ticks_usec()
		var warm_frames := 0
		while (Time.get_ticks_usec()-warm_start<1000000 if realtime else warm_frames<60):
			await process_frame
			warm_frames+=1
		var samples: Array[float] = []
		var draws: Array[float] = []
		var nodes_min := get_node_count()
		var nodes_max := nodes_min
		var shots_max := 0
		var stamp := Time.get_ticks_usec()
		var sample_start := stamp
		var physics_start := Engine.get_physics_frames()
		while (Time.get_ticks_usec()-sample_start<5000000 if realtime else samples.size()<300):
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-stamp)/1000.0)
			stamp=now
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			nodes_min=mini(nodes_min,get_node_count())
			nodes_max=maxi(nodes_max,get_node_count())
			shots_max=maxi(shots_max,scene.projectile_root.get_child_count())
		samples.sort()
		var shapes := 0
		for owner in scene.geometry.get_shape_owners():
			shapes+=scene.geometry.shape_owner_get_shape_count(owner)
		var n := samples.size()
		var physics_steps := Engine.get_physics_frames()-physics_start
		var elapsed_seconds := (Time.get_ticks_usec()-sample_start)/1000000.0
		# Godot consumes some engine flags before OS.get_cmdline_args(). Validate the
		# observed clock instead of claiming that a command-line tag proves timing.
		if (not realtime and absi(physics_steps-n)>2) or (realtime and absf(physics_steps/60.0-elapsed_seconds)>0.15):
			push_error("Benchmark clock mismatch: use --fixed-fps 60, or omit it and pass -- --realtime")
			run.queue_free()
			await process_frame
			quit(1)
			return
		var row := {"clock":"realtime" if realtime else "fixed_60","scenario":mode,"seed":scene.run_seed,"renderer":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),"warmup_frames":warm_frames,"sample_frames":n,"average_fps":1000/_mean(samples),"one_percent_low_fps":1000/_mean(samples.slice(n-maxi(1,ceili(n*0.01)))),"p50_ms":samples[floori(n*0.5)],"p95_ms":samples[mini(n-1,floori(n*0.95))],"draw_calls_mean":_mean(draws),"nodes_min":nodes_min,"nodes_max":nodes_max,"projectiles_max":shots_max,"enemies":scene.enemies.size(),"world_collision_shapes":shapes,"actor_collision_shapes":scene.enemies.size()+1,"complete_build_ms":run.builds[-1].build_ms,"static_peak_bytes":OS.get_static_memory_peak_usage(),"player_point":str(scene.player.position),"enemy_states":scene.enemies.map(func(e: CharacterBody3D) -> int: return e.state)}
		row.physics_steps=physics_steps
		row.logical_canvas=str(root.get_visible_rect().size)
		results.append(row)
		print("M3_PERF ",JSON.stringify(row))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m3_benchmark_%s.png" % mode)
	var file := FileAccess.open("res://.godot/m3_performance%s.json" % ("_realtime" if realtime else ""),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	run.queue_free()
	await process_frame
	await process_frame
	quit()

func _active_target(scene: Node3D) -> Vector3:
	var encounter: Dictionary=scene.encounters[-1]
	var first := Grid.center(encounter.tiles[0])
	var second := Grid.center(encounter.tiles[1])
	var middle := (first+second)*0.5
	var best := Grid.center(encounter.tiles[2],0.05)
	var distance := INF
	var area: Rect2i=encounter.bounds
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var tile := Vector2i(x,y)
			var point := Grid.center(tile,0.05)
			if scene.navigation.clear_spawn(tile) and point.distance_to(first)>3 and point.distance_to(second)>3 and point.distance_to(middle)<distance:
				best=point
				distance=point.distance_to(middle)
	return best

func _mean(values: Array[float]) -> float:
	var sum := 0.0
	for value in values:
		sum+=value
	return sum/maxi(1,values.size())
