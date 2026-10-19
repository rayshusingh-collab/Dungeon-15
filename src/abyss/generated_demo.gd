extends Node3D

const Composer = preload("res://src/abyss/spatial_composer.gd")
const Geometry = preload("res://src/abyss/spatial_geometry.gd")
@export var world_seed: int = 12345
@export var spatial_config: AbyssSpatialConfig = AbyssSpatialConfig.new()
var layout: AbyssSpatialLayout
var geometry: Node3D
var generation_msec: float = 0
var _complete: bool = false


func _ready() -> void:
	for seed_value in [12345, 42, 7]:
		get_node("Instructions/SeedSelector/Seed%d" % seed_value).pressed.connect(select_seed.bind(seed_value))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--abyss-seed="):
			var value := argument.trim_prefix("--abyss-seed=")
			world_seed = int(value) if value.is_valid_int() else StableHash.hash62(value)
	_generate()


func select_seed(value: int) -> void:
	world_seed = value
	_generate()


func _generate() -> void:
	var result := Composer.new().generate(spatial_config, world_seed)
	generation_msec = result.msec
	if not result.ok:
		_fail("Generation failed safely: " + "; ".join(result.errors))
		return
	var replacement := Geometry.new()
	add_child(replacement)
	if not replacement.build(result.layout):
		replacement.free()
		_fail("Geometry refused invalid layout")
		return
	# Explicit full-demo restart: replace static geometry between physics frames.
	# This is seed selection, not an in-world architectural transformation.
	if is_instance_valid(geometry):
		geometry.free()
	geometry = replacement
	geometry.name = "GeneratedGeometry"
	layout = result.layout
	_complete = false
	set_physics_process(true)
	$Player3D.set_physics_process(true)
	$Player3D.velocity = Vector3.ZERO
	$Player3D.global_position = layout.spawn + Vector3.UP * 0.05
	# Camera was readied before generation: recenter without altering fixed rotation.
	$Camera.global_position = $Player3D.global_position + $Camera.follow_offset
	for seed_value in [12345, 42, 7]:
		get_node("Instructions/SeedSelector/Seed%d" % seed_value).disabled = seed_value == world_seed
	$Instructions/Label.text = "The Shifting Abyss / seed %d\nWASD / arrows / left stick / D-pad | F3: diagnostics\nExplore linked chambers; find the EXIT marker\n%d chambers / %d links / %.1f ms generation / %.1f ms build" % [
		world_seed, layout.rooms.size(), layout.connections.size(), generation_msec, geometry.build_msec]
	print("ABYSS spatial seed=%d fingerprint=%s attempts=%d generation_ms=%.3f build_ms=%.3f rooms=%d links=%d boxes=%d meshes=%d" % [
		world_seed, layout.fingerprint(), result.attempts, generation_msec, geometry.build_msec,
		layout.rooms.size(), layout.connections.size(), geometry.box_count, geometry.mesh_count])


func _physics_process(_delta: float) -> void:
	if layout != null and not _complete and $Player3D.global_position.distance_to(layout.exit) < 1.5:
		_complete = true
		$Instructions/Label.text += "\nEXIT REACHED — layout traversal complete"


func _fail(message: String) -> void:
	$Player3D.set_physics_process(false)
	$Instructions/Label.text = message
	set_physics_process(false)
	print("ABYSS: ", message)
