extends Node3D
## Static M1 floor. No content scenes, encounters or Abyss systems are instantiated.
const Grid = preload("res://src/game_3d/grid_space.gd")
const T = DungeonLayout.Tile
@export var run_seed: int = 12345
var layout: DungeonLayout
var player: CharacterBody3D
var camera: Camera3D
var input_source: Node
var status: Label
var build_msec: float
var geometry: StaticBody3D
var spike_material: StandardMaterial3D
var spike_tips: MultiMeshInstance3D
var elapsed := 0.0
var spike_phase := 0
var safe_seconds := 4.0
const WARNING_SECONDS := 0.6
const RAISED_SECONDS := 0.5
var resets := 0
var reached_exit := false
var route: Array[Vector2i] = []
var rects: Array[Dictionary] = []
var detail_counts: Dictionary = {}
var materials: Dictionary = {}
var fixture_mode := false
var survey_visible := false
var terrain_counts: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			run_seed = int(arg.trim_prefix("--seed="))
	var started := Time.get_ticks_usec()
	layout = _create_layout()
	if layout == null:
		return
	for kind in layout.tiles:
		terrain_counts[kind] = terrain_counts.get(kind, 0) + 1
	route = find_route(layout)
	if route.is_empty():
		push_error("M1 rejected floor: no supported entrance-to-exit route")
		return
	# The 2D validator's eight-tile region limit assumed 230 px/s. Preserve
	# P1A's 5 m/s and budget for both that limit and this route's longest run.
	var hazard_run := 0
	for tile in route:
		hazard_run = hazard_run + 1 if layout.get_tile(tile) == T.HAZARD else 0
		safe_seconds = maxf(safe_seconds, (hazard_run + 2) * Grid.CELL / 5.0)
	_build_geometry()
	input_source = $ControllerInput
	player = preload("res://src/prototype_3d/player_3d.tscn").instantiate()
	player.set_script(preload("res://src/game_3d/player.gd"))
	player.movement_input = input_source
	player.position = Grid.center(layout.player_spawn, 0.05)
	add_child(player)
	camera = Camera3D.new()
	camera.set_script(preload("res://src/prototype_3d/isometric_camera_3d.gd"))
	camera.target = player
	camera.size = 27.0
	camera.far = 300.0
	add_child(camera)
	camera.current = true
	player.movement_camera = camera
	_marker(layout.player_spawn, "ENTRANCE", Color(0.3, 0.8, 1))
	_marker(layout.exit_tile, "EXIT", Color(0.4, 1, 0.5))
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	add_child(sun)
	var ui := CanvasLayer.new()
	add_child(ui)
	status = Label.new()
	status.position = Vector2(16, 16)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 6)
	ui.add_child(status)
	build_msec = (Time.get_ticks_usec() - started) / 1000.0
	print("M1 seed=%d fingerprint=%s build=%.2fms rectangles=%d nodes=%d static_memory=%d peak=%d" % [run_seed, layout.fingerprint(), build_msec, rects.size(), get_tree().get_node_count(), OS.get_static_memory_usage(), OS.get_static_memory_peak_usage()])

func _create_layout() -> DungeonLayout:
	var result := DungeonGenerator.new().generate(DepthProfile.load_for_depth(1), run_seed, 1)
	if not result.ok:
		push_error("M1 generation failed: " + str(result.failure_log))
		return null
	return result.layout

static func find_route(data: DungeonLayout) -> Array[Vector2i]:
	var previous := {data.player_spawn: data.player_spawn}
	var queue: Array[Vector2i] = [data.player_spawn]
	var cursor := 0
	while cursor < queue.size():
		var tile := queue[cursor]
		cursor += 1
		if tile == data.exit_tile:
			var path: Array[Vector2i] = [tile]
			while tile != data.player_spawn:
				tile = previous[tile]
				path.push_front(tile)
			return path
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := tile + step
			if not previous.has(next) and data.is_walkable(next, true):
				previous[next] = tile
				queue.append(next)
	return []

func _build_geometry() -> void:
	materials.clear()
	spike_material = null
	geometry = StaticBody3D.new()
	geometry.name = "StaticFloor"
	geometry.collision_mask = 0
	add_child(geometry)
	# Merge identical tile runs vertically. Every rectangle retains the source kind.
	var used := PackedByteArray()
	used.resize(layout.tiles.size())
	for y in layout.size.y:
		for x in layout.size.x:
			var tile := Vector2i(x, y)
			var index := layout.index_of(tile)
			var kind := layout.tiles[index]
			if used[index] or kind == T.VOID:
				continue
			var width := 1
			while x + width < layout.size.x and not used[index + width] and layout.tiles[index + width] == kind:
				width += 1
			var height := 1
			while y + height < layout.size.y:
				var valid := true
				for dx in width:
					var i := (y + height) * layout.size.x + x + dx
					if used[i] or layout.tiles[i] != kind:
						valid = false
						break
				if not valid:
					break
				height += 1
			for dy in height:
				for dx in width:
					used[(y + dy) * layout.size.x + x + dx] = 1
			var rect := Rect2i(x, y, width, height)
			rects.append({"rect": rect, "kind": kind})
			var solid := DungeonLayout.is_solid_kind(kind)
			var h := 1.0 if solid else 0.25
			var center := Vector3((x + width * 0.5) * Grid.CELL, h * 0.5 if solid else -h * 0.5, (y + height * 0.5) * Grid.CELL)
			if kind == T.PIT:
				center.y = -2.5
			var size := Vector3(width * Grid.CELL, h, height * Grid.CELL)
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			mesh.mesh = box
			mesh.position = center
			mesh.material_override = _material(kind)
			geometry.add_child(mesh)
			if kind != T.PIT:
				var shape := CollisionShape3D.new()
				var box_shape := BoxShape3D.new()
				box_shape.size = size
				shape.shape = box_shape
				shape.position = center
				geometry.add_child(shape)
	# One batched set of readable spike tips; the floor colour also telegraphs phase.
	var spike_tiles: Array[Vector2i] = []
	for y in layout.size.y:
		for x in layout.size.x:
			if layout.get_tile(Vector2i(x, y)) == T.HAZARD:
				spike_tiles.append(Vector2i(x, y))
	spike_tips = MultiMeshInstance3D.new()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.25
	tip.height = 0.6
	tip.material = spike_material
	batch.mesh = tip
	batch.instance_count = spike_tiles.size() * 4
	for i in spike_tiles.size():
		for j in 4:
			var offset := Vector3(-0.5 if j % 2 == 0 else 0.5, 0.3, -0.5 if j < 2 else 0.5)
			batch.set_instance_transform(i * 4 + j, Transform3D(Basis.IDENTITY, Grid.center(spike_tiles[i]) + offset))
	spike_tips.multimesh = batch
	geometry.add_child(spike_tips)
	var details := preload("res://src/game_3d/environment_details.gd").new()
	details.build(layout, geometry)
	detail_counts = details.counts

func _material(kind: int) -> Material:
	if materials.has(kind):
		return materials[kind]
	if kind == T.WATER:
		var water := ShaderMaterial.new()
		water.shader = preload("res://src/game_3d/water.gdshader")
		materials[kind] = water
		return water
	var material := StandardMaterial3D.new()
	var colors := {T.FLOOR: Color(0.36, 0.38, 0.4), T.CORRIDOR: Color(0.43, 0.44, 0.46), T.DOOR: Color(0.65, 0.6, 0.43), T.BRIDGE: Color(0.65, 0.43, 0.22), T.WATER: Color(0.12, 0.36, 0.55), T.PIT: Color(0.055, 0.025, 0.07), T.HAZARD: Color(0.55, 0.32, 0.12), T.RUBBLE: Color(0.35, 0.29, 0.26)}
	material.albedo_color = colors.get(kind, Color(0.55, 0.57, 0.6))
	if kind in [T.FLOOR,T.CORRIDOR,T.DOOR,T.WALL,T.INNER_WALL,T.OBSTACLE,T.RUBBLE]:
		var stone := ShaderMaterial.new()
		stone.shader = preload("res://src/game_3d/stone.gdshader")
		stone.set_shader_parameter("base_color", material.albedo_color)
		stone.set_shader_parameter("masonry", DungeonLayout.is_solid_kind(kind))
		materials[kind] = stone
		return stone
	if kind == T.HAZARD:
		spike_material = material
	materials[kind] = material
	return material

func _marker(tile: Vector2i, text: String, color: Color, ring: bool = true) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Grid.center(tile, 2.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.02
	label.modulate = color
	label.no_depth_test = true
	add_child(label)
	if not ring:
		return
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.65
	cylinder.bottom_radius = 0.65
	cylinder.height = 0.06
	mesh.mesh = cylinder
	mesh.position = Grid.center(tile, 0.04)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)

func reset_to_entry() -> void:
	resets += 1
	player.position = Grid.center(layout.player_spawn, 0.05)
	player.velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if player == null:
		return
	elapsed += delta
	var cycle := fmod(elapsed, safe_seconds + WARNING_SECONDS + RAISED_SECONDS)
	spike_phase = 0 if cycle < safe_seconds else (1 if cycle < safe_seconds + WARNING_SECONDS else 2)
	if spike_material != null:
		spike_material.albedo_color = [Color(0.5, 0.3, 0.1), Color(1, 0.65, 0.1), Color(1, 0.12, 0.08)][spike_phase]
		spike_tips.visible = spike_phase != 0
		spike_tips.scale.y = 0.25 if spike_phase == 1 else 1.0
	var kind := layout.get_tile(Grid.tile_at(player.position))
	player.move_speed = 2.5 if kind == T.WATER else 5.0
	if player.position.y < -3.0 or (kind == T.HAZARD and spike_phase == 2):
		reset_to_entry()
	if Grid.tile_at(player.position) == layout.exit_tile:
		reached_exit = true
	status.text = "DUNGEON15 / Depth 1 of 15 / Seed %d\nWASD / arrows / left stick / D-pad | R: return to entrance\nBlue: water slows | Brown: bridge | Dark drop: pit resets\nSpikes: brown safe / amber warning / RED resets | %s\nController: %s | %s\nBuild %.1f ms | resets %d%s" % [run_seed, ["SAFE", "WARNING", "RAISED"][spike_phase], str(input_source.device_id), input_source.last_event, build_msec, resets, "\nEXIT REACHED - M1 complete (no next depth)" if reached_exit else ""]
	if fixture_mode:
		status.text = "HAZARD VALIDATION FIXTURE - NOT A CAMPAIGN FLOOR\nWASD / arrows / stick / D-pad | 1: bridge/pit | 2: water | 3: spikes | R: entry\nSpikes: brown safe / amber warning / RED resets | %s\nController %d | Build %.1f ms | resets %d | H: diagnostics" % [["SAFE","WARNING","RAISED"][spike_phase],input_source.device_id,build_msec,resets]
	else:
		status.text += "\nH: survey generated terrain"
	if survey_visible or fixture_mode:
		status.text += "\nThis layout: pit %d | bridge %d | water %d | spike tiles %d" % [terrain_counts.get(T.PIT,0),terrain_counts.get(T.BRIDGE,0),terrain_counts.get(T.WATER,0),terrain_counts.get(T.HAZARD,0)]
	if survey_visible:
		status.text += "\nPad %s | combined %s | deadzone %.2f\n%s\n%s | %s" % [str(input_source.stick_vector()),str(input_source.movement_vector()),input_source.deadzone,input_source.last_event,input_source.last_button_event,input_source.connection_event]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and player != null:
		reset_to_entry()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		survey_visible = not survey_visible
