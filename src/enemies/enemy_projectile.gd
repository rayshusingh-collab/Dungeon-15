class_name EnemyProjectile
extends Node2D
## Slow, glowing enemy shot (placeholder art). Flies straight, is stopped by
## walls, pillars and locked gates (world layer: each step is swept with a
## physics ray, so it can never tunnel through), flies over pits and water,
## and damages the player through the normal Hitbox -> Hurtbox path, so dodge
## invulnerability works. Slow enough to side-step after the telegraph.

@export var speed: float = 250.0
@export var lifetime: float = 3.0
@export var radius: float = 7.0
@export var damage: int = 1

var velocity: Vector2 = Vector2.ZERO

var _hitbox: Hitbox
var _age: float = 0.0


## `direction` must be normalized.
func setup(from: Vector2, direction: Vector2) -> void:
	position = from
	velocity = direction * speed
	_hitbox = Hitbox.new()
	_hitbox.damage = damage
	_hitbox.knockback_scale = 0.6
	_hitbox.requires_line_of_sight = false  # the shot is physically stopped by walls instead
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 8  # player_hurtbox
	_hitbox.monitorable = false
	_hitbox.rotation = direction.angle()
	var hit_shape := CircleShape2D.new()
	hit_shape.radius = radius + 2.0
	var hit_node := CollisionShape2D.new()
	hit_node.shape = hit_shape
	_hitbox.add_child(hit_node)
	add_child(_hitbox)
	_hitbox.hit_landed.connect(_on_hit_landed)


func _ready() -> void:
	_hitbox.activate(true)


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + step.normalized() * radius, 1)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position - step.normalized() * radius
		_pop()
		return
	position += step
	_age += delta
	if _age >= lifetime:
		_pop()
	queue_redraw()


func _draw() -> void:
	var back := -velocity.normalized() if velocity != Vector2.ZERO else Vector2.ZERO
	for i in 3:
		draw_circle(back * (6.0 + i * 6.0), radius * (0.7 - i * 0.18), Color(0.6, 1.0, 0.45, 0.35 - i * 0.1))
	draw_circle(Vector2.ZERO, radius, Color(0.55, 0.95, 0.4))
	draw_circle(Vector2.ZERO, radius * 0.5, Color(0.95, 1.0, 0.85))


func _on_hit_landed(_hurtbox: Hurtbox) -> void:
	_pop()


func _pop() -> void:
	if is_queued_for_deletion():
		return
	set_physics_process(false)
	_hitbox.deactivate()
	BurstEffect.spawn(get_parent(), global_position, BurstEffect.Style.RING, Color(0.6, 1.0, 0.45, 0.8), 4.0, 18.0, 0.18)
	queue_free()
