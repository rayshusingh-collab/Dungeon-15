class_name WaterZone
extends Area2D
## Shallow water covering one room's water tiles. Bodies with a TerrainState
## child are slowed while inside. A small ripple marks entry (placeholder for
## splash VFX/audio later). Static: no per-frame work.

signal body_splashed(body: Node2D)

@export var speed_scale: float = 0.62


## `rects` are world-pixel rectangles (merged water tiles).
func setup(rects: Array[Rect2]) -> void:
	collision_layer = 0
	collision_mask = 2 | 4 # player + enemy bodies
	monitorable = false
	for rect in rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var node := CollisionShape2D.new()
		node.shape = shape
		node.position = rect.get_center()
		add_child(node)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	var terrain := body.get_node_or_null(^"TerrainState") as TerrainState
	if terrain == null:
		return
	terrain.enter_zone(get_instance_id(), &"water", speed_scale)
	BurstEffect.spawn(get_parent(), body.global_position, BurstEffect.Style.RING,
			Color(0.6, 0.85, 1.0, 0.7), 10.0, 30.0, 0.35)
	body_splashed.emit(body)


func _on_body_exited(body: Node2D) -> void:
	var terrain := body.get_node_or_null(^"TerrainState") as TerrainState
	if terrain != null:
		terrain.exit_zone(get_instance_id())
