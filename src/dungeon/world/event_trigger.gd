class_name EventTrigger
extends Area2D
## An armed tension/event socket. Fires `triggered` once when the player
## steps near it. Milestone 2.1 only uses this for a debug proof event; later
## milestones attach real thriller beats (sounds, silhouettes, flickers,
## scripted story moments) to the same sockets.

signal triggered(trigger: EventTrigger)

const RADIUS := 56.0

var kind: StringName = &"room"
var socket_tile: Vector2i
var fired: bool = false


func setup(center: Vector2, tile: Vector2i, socket_kind: StringName) -> void:
	position = center
	socket_tile = tile
	kind = socket_kind
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var node := CollisionShape2D.new()
	node.shape = shape
	add_child(node)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if fired or not body is Player:
		return
	fired = true
	triggered.emit(self)
