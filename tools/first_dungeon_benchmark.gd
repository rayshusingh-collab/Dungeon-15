extends SceneTree
const MainScene = preload("res://src/game_3d/first_dungeon.tscn")
## Fixed 1280x720, seed 12345; four reproducible render scenarios. No project changes.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var scene_path := "res://src/game_3d/first_dungeon.tscn"
	if OS.get_cmdline_user_args().has("--before"):
		scene_path = "res://.godot/m11_baseline/first_dungeon.tscn"
		if not FileAccess.file_exists(scene_path):
			push_error("Before benchmark requires the M1 snapshot captured in .godot/m11_baseline before M1.1 edits")
			quit(1)
			return
	var packed := (load(scene_path) as PackedScene) if OS.get_cmdline_user_args().has("--before") else MainScene
	var scene := packed.instantiate()
	root.add_child(scene)
	var focus := Node3D.new()
	scene.add_child(focus)
	focus.position = scene.player.position
	scene.camera.target = focus
	scene.camera.set_process(false)
	var results: Array = []
	for scenario in ["entry_vsync", "entry_uncapped", "entry_hidden_geometry", "route_uncapped"]:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if scenario == "entry_vsync" else DisplayServer.VSYNC_DISABLED)
		scene.geometry.visible = scenario != "entry_hidden_geometry"
		focus.position = scene.player.position
		scene.camera.position = focus.position + scene.camera.follow_offset
		for i in 60:
			await process_frame
		var samples: Array[float] = []
		var physics: Array[float] = []
		var draws: Array[float] = []
		var nodes := get_node_count()
		var stamp := Time.get_ticks_usec()
		for i in 300:
			if scenario == "route_uncapped":
				var tile: Vector2i = scene.route[mini(floori(float(i) / 300 * scene.route.size()), scene.route.size() - 1)]
				focus.position = preload("res://src/game_3d/grid_space.gd").center(tile)
				scene.camera.position = focus.position + scene.camera.follow_offset
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - stamp) / 1000.0)
			stamp = now
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		samples.sort()
		var mean_ms := _mean(samples)
		var low_ms := _mean(samples.slice(297))
		var row := {"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "warmup_frames": 60, "scenario": scenario, "samples": samples.size(), "average_fps": 1000.0 / mean_ms, "one_percent_low_fps": 1000.0 / low_ms, "p50_ms": samples[150], "p95_ms": samples[285], "physics_mean_ms": _mean(physics), "draw_calls_mean": _mean(draws), "nodes_start": nodes, "nodes_end": get_node_count(), "collision_shapes": scene.geometry.get_shape_owners().size(), "build_ms": scene.build_msec, "static_peak_bytes": OS.get_static_memory_peak_usage(), "resolution": str(root.size), "renderer": RenderingServer.get_video_adapter_name(), "vsync_reported": DisplayServer.window_get_vsync_mode()}
		# StaticBody's one shape owner holds all CollisionShape children.
		row.collision_shapes = 0
		for owner in scene.geometry.get_shape_owners():
			row.collision_shapes += scene.geometry.shape_owner_get_shape_count(owner)
		results.append(row)
		print("M11_PERF ", JSON.stringify(row))
	var suffix := "after"
	if OS.get_cmdline_user_args().has("--before"):
		suffix = "before"
	var file := FileAccess.open("res://.godot/m11_perf_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	# Capture real rendered states from the current scene (no fake colour overrides).
	focus.position = scene.player.position
	scene.camera.position = focus.position + scene.camera.follow_offset
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m11_entry.png")
	scene.queue_free()
	await process_frame
	quit()

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1)
