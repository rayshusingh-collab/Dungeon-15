class_name PitZone
extends Area2D
## A room's pits/chasms. A body falls when its centre is over a pit tile
## (a few pixels of edge forgiveness), not when it merely brushes the edge.
## - Player: takes `player_damage` through the normal Hitbox -> Hurtbox path,
##   then `player_fell` asks Main to run the fall and respawn on safe ground.
## - Enemy: takes lethal damage (knocking enemies into pits is a tactic, and a
##   fallen enemy still counts as defeated, so encounters cannot softlock).
## Only processes while something overlaps it.

signal player_fell(player: Player)
signal enemy_fell(enemy: Enemy)

@export var player_damage: int = 1
@export var enemy_damage: int = 999
## Pixels a body's centre must be inside a pit tile before it falls.
@export var edge_forgiveness: float = 6.0

var _rects: Array[Rect2] = []
## Pit edges bordering walkable ground: [from, to] pixel segments.
var _edges: Array[PackedVector2Array] = []
var _falling: Dictionary = {}
var _hitbox: Hitbox


## `rects` are world-pixel rectangles (merged pit tiles); `edges` are the
## segments where a pit meets walkable ground (drawn as a visible lip).
func setup(rects: Array[Rect2], edges: Array[PackedVector2Array] = []) -> void:
	_rects = rects
	_edges = edges
	collision_layer = 0
	collision_mask = 2 | 4
	monitorable = false
	for rect in rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var node := CollisionShape2D.new()
		node.shape = shape
		node.position = rect.get_center()
		add_child(node)
	# Damage source (never monitors; hits are delivered directly to the victim).
	_hitbox = Hitbox.new()
	_hitbox.requires_line_of_sight = false
	_hitbox.directional_bias = 0.0
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 0
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	add_child(_hitbox)
	set_physics_process(false)
	body_entered.connect(func(_b: Node2D) -> void: set_physics_process(true))


func _draw() -> void:
	# Placeholder readability: a dark drop with a light crumbling lip on every
	# edge you could walk off, and a shadow band just inside it.
	for rect in _rects:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.55))
	for edge in _edges:
		var inward := (edge[2] - (edge[0] + edge[1]) / 2.0).normalized()
		draw_line(edge[0] + inward * 5.0, edge[1] + inward * 5.0, Color(0, 0, 0, 0.8), 6.0)
		draw_line(edge[0], edge[1], Color(0.78, 0.62, 0.42), 3.0)


func contains_point(point: Vector2) -> bool:
	for rect in _rects:
		if rect.grow(-edge_forgiveness).has_point(point):
			return true
	return false


func _physics_process(_delta: float) -> void:
	var bodies := get_overlapping_bodies()
	if bodies.is_empty():
		set_physics_process(false)
		return
	for body in bodies:
		var id := body.get_instance_id()
		if not contains_point(body.global_position):
			_falling.erase(id)
			continue
		if _falling.has(id):
			continue
		_falling[id] = true
		_drop(body)


func _drop(body: Node2D) -> void:
	var hurtbox := body.get_node_or_null(^"Hurtbox") as Hurtbox
	var player := body as Player
	if player != null:
		if player.is_dead() or player.is_falling():
			return
		_hitbox.global_position = body.global_position
		_hitbox.damage = player_damage
		if hurtbox != null:
			hurtbox.receive_hit(_hitbox)
		if not player.is_dead():
			player_fell.emit(player)
		return
	var enemy := body as Enemy
	if enemy != null and enemy.state != Enemy.State.DEAD:
		_hitbox.global_position = body.global_position
		_hitbox.damage = enemy_damage
		if hurtbox != null:
			hurtbox.receive_hit(_hitbox)
		enemy_fell.emit(enemy)
