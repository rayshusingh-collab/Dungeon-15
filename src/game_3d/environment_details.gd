extends RefCounted
## Cosmetic only. Single batched box mesh and socket mesh, no colliders/lights/RNG.
const Grid = preload("res://src/game_3d/grid_space.gd")
const T = DungeonLayout.Tile
var boxes: Array[Dictionary] = []
var sockets: Array[Transform3D] = []
var counts := {"pit_recess_sides": 0, "water_shore_edges": 0, "bridge_edge_beams": 0, "bridge_planks": 0, "spike_sockets": 0, "door_sills": 0, "room_inlays": 0}

func build(data: DungeonLayout, parent: Node3D) -> void:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x,y)
			var kind := data.get_tile(tile)
			var center := Grid.center(tile)
			if kind == T.HAZARD:
				for j in 4:
					sockets.append(Transform3D(Basis.IDENTITY, center+Vector3(-0.5 if j%2==0 else 0.5,0.012,-0.5 if j<2 else 0.5)))
					counts.spike_sockets += 1
			if kind == T.BRIDGE:
				for j in 3:
					_box(center+Vector3(0,0.013,(j-1)*0.63),Vector3(1.91,0.022,0.055),Color(0.24,0.15,0.08))
					counts.bridge_planks += 1
			if kind == T.DOOR:
				_box(center+Vector3(0,0.012,0),Vector3(1.85,0.02,0.14),Color(0.52,0.44,0.25))
				counts.door_sills += 1
			if kind not in [T.PIT,T.WATER,T.BRIDGE]:
				continue
			for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var adjacent := data.get_tile(tile+step)
				var along_x := step.y != 0
				var edge := center+Vector3(step.x,0,step.y)*Grid.CELL*0.5
				if kind == T.PIT and adjacent != T.PIT:
					# Vertical recess makes this an opening; no horizontal surface at Y=0.
					_box(edge+Vector3(0,-1.25,0),Vector3(2,2.5,0.045) if along_x else Vector3(0.045,2.5,2),Color(0.18,0.21,0.25))
					counts.pit_recess_sides += 1
				if kind == T.WATER and adjacent != T.WATER:
					_box(edge+Vector3(0,0.018,0),Vector3(1.98,0.03,0.075) if along_x else Vector3(0.075,0.03,1.98),Color(0.35,0.78,0.82))
					counts.water_shore_edges += 1
				if kind == T.BRIDGE and adjacent in [T.PIT,T.VOID,T.WATER]:
					_box(edge+Vector3(0,0.05,0),Vector3(2,0.1,0.14) if along_x else Vector3(0.14,0.1,2),Color(0.83,0.63,0.32))
					counts.bridge_edge_beams += 1
	for room in data.rooms:
		# Existing reserved anchor: a flat, neutral inlay and numbered architectural label.
		var center := Grid.center(room.anchor)
		for axis in [Vector3(2.5,0.012,0.08),Vector3(0.08,0.012,2.5)]:
			_box(center+Vector3(0,0.008,0),axis,Color(0.47,0.49,0.51))
			counts.room_inlays += 1
		var label := Label3D.new()
		label.name = "Chamber%02d" % room.id
		label.text = "HALL %02d" % room.id if room.special_rule == null else "INSCRIPTION HALL %02d" % room.id
		label.position = center+Vector3(0,0.04,-2)
		label.rotation_degrees.x = -90
		label.font_size = 48
		label.pixel_size = 0.014
		label.modulate = Color(0.7,0.72,0.74)
		label.outline_size = 0
		parent.add_child(label)
		if room.special_rule != null:
			# Quiet architectural motif on the existing safe floor, no story trigger/reward.
			for i in 5:
				_box(center+Vector3((i-2)*0.45,0.012,1.2),Vector3(0.16,0.02,0.6+absf(i-2)*0.18),Color(0.6,0.62,0.65))
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = boxes.size()
	for i in boxes.size():
		batch.set_instance_transform(i,boxes[i].transform)
		batch.set_instance_color(i,boxes[i].color)
	var node := MultiMeshInstance3D.new()
	node.name = "ArchitecturalDetails"
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	if not sockets.is_empty():
		var socket_mesh := CylinderMesh.new()
		socket_mesh.top_radius = 0.31
		socket_mesh.bottom_radius = 0.31
		socket_mesh.height = 0.018
		socket_mesh.radial_segments = 8
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.045,0.055,0.06)
		socket_mesh.material = dark
		var socket_batch := MultiMesh.new()
		socket_batch.transform_format = MultiMesh.TRANSFORM_3D
		socket_batch.mesh = socket_mesh
		socket_batch.instance_count = sockets.size()
		for i in sockets.size():
			socket_batch.set_instance_transform(i,sockets[i])
		var socket_node := MultiMeshInstance3D.new()
		socket_node.name = "RetractedSpikeSockets"
		socket_node.multimesh = socket_batch
		parent.add_child(socket_node)

func _box(center: Vector3, size: Vector3, color: Color) -> void:
	boxes.append({"transform": Transform3D(Basis.IDENTITY.scaled(size),center), "color": color})
