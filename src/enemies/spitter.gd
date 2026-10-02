class_name Spitter
extends Enemy
## Placeholder ranged-pressure archetype (Milestone 2.2, not final roster).
## Keeps its distance: approaches until the player is in range and in sight,
## backs off (never into pits or walls) when the player gets close, and fires
## a slow projectile after a readable telegraph (it swells and an aim line
## shows where the shot will go). Walls and pillars block both its sight and
## its shots, so cover is the counterplay. Uses the MeleeAttack phases purely
## as windup/recovery timing: its own hitbox never touches anything.

@export var retreat_distance: float = 120.0
@export var projectile_speed: float = 250.0
## Length of the aim line shown during the windup.
@export var aim_line_length: float = 240.0

var _aiming: bool = false


func _chase(delta: float) -> Vector2:
	if not _target_alive() or target.global_position.distance_to(home_position) > leash_range:
		_set_state(State.RETURN)
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	# Sight, not walkability: it shoots across pits and water (shots only stop on walls).
	var visible := navigator == null or navigator.clear_sight(global_position, target.global_position)
	var speed := move_speed * terrain.speed_scale()
	if not visible:
		var toward := _steer_toward(target.global_position, speed, delta)
		_face(toward)
		return toward
	_face(to_target)
	if distance < retreat_distance:
		var away := -to_target.normalized()
		if navigator == null or navigator.is_walkable_point(global_position + away * 40.0):
			return away * speed
	if distance <= attack_range:
		if melee.start(facing):
			_set_state(State.ATTACK)
			return Vector2.ZERO
		# Between shots: spread out from other enemies (no crossfire blob).
		return crowd_steer(to_target) * speed * hold_spread_ratio
	return _steer_toward(target.global_position, speed, delta)


func _physics_process(delta: float) -> void:
	super(delta)
	var aiming := state == State.ATTACK and melee.phase == MeleeAttack.Phase.WINDUP
	if aiming != _aiming:
		_aiming = aiming
		queue_redraw()


func _on_strike_started() -> void:
	# Fire instead of lunging.
	_visual.modulate = Color(2.0, 2.4, 1.6)
	_animate_visual(Color.WHITE, Vector2.ONE, 0.12)
	var shot := EnemyProjectile.new()
	shot.speed = projectile_speed
	shot.setup(global_position + facing * 20.0, facing)
	get_parent().add_child(shot)
	queue_redraw()


func _draw() -> void:
	if _aiming:
		draw_line(facing * 18.0, facing * aim_line_length, Color(0.6, 1.0, 0.45, 0.45), 2.0)
