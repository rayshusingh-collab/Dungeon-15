class_name Player
extends CharacterBody2D
## Player controller: NORMAL / ATTACK / DODGE / DEAD.
## Reads only InputMap actions (keyboard and touch controls share one path).
## Combat goes through the MeleeAttack, Hurtbox and HealthComponent children;
## $Visual and $FacingMarker are placeholder art, only touched for feedback
## (modulate / scale / visible), so a sprite can replace them later.

signal died
signal dodge_started
## Emitted on every damaging hit (including the lethal one) for camera/hit-stop.
signal hurt(knockback_direction: Vector2)

enum State { NORMAL, ATTACK, DODGE, DEAD }

@export_group("Movement")
@export var move_speed: float = 230.0
@export_group("Attack")
## Speed multiplier while swinging (windup to recovery): a small commitment.
@export var attack_move_multiplier: float = 0.35
## Forward step on the strike frame; makes swings directional and deliberate.
@export var attack_lunge_speed: float = 320.0
@export var attack_lunge_decay: float = 3600.0
@export_group("Dodge")
@export var dodge_speed: float = 620.0
@export var dodge_duration: float = 0.2
## Measured from the start of a dodge.
@export var dodge_cooldown: float = 0.6
@export var dodge_invulnerability: float = 0.25
@export_group("Hit reaction")
@export var knockback_strength: float = 360.0
@export var knockback_decay: float = 2400.0
## Movement input is ignored this long after being hit (dodge still works).
@export var hurt_stagger_time: float = 0.12
@export_group("Input")
## A press shortly before an action is available is remembered this long.
@export var input_buffer_time: float = 0.15

var state: State = State.NORMAL
var facing: Vector2 = Vector2.RIGHT
## Turned off during room transitions.
var controls_enabled: bool = true

var _dodge_direction: Vector2 = Vector2.ZERO
var _dodge_time_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _attack_buffer_left: float = 0.0
var _dodge_buffer_left: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _lunge: Vector2 = Vector2.ZERO
var _stagger_left: float = 0.0
var _hurt_blink_left: float = 0.0
var _ghost_timer: float = 0.0
var _flash_tween: Tween
var _squash_tween: Tween

@onready var health: HealthComponent = $HealthComponent
@onready var melee: MeleeAttack = $MeleeAttack
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _visual: Node2D = $Visual
@onready var _facing_marker: Node2D = $FacingMarker


func _ready() -> void:
	health.died.connect(_on_died)
	_hurtbox.hit_received.connect(_on_hit_received)
	melee.windup_started.connect(_on_attack_windup)
	melee.strike_started.connect(_on_attack_strike)
	melee.finished.connect(_on_attack_finished)
	_update_facing_marker()


func _physics_process(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
	if state == State.DEAD:
		return
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	var staggered := _stagger_left > 0.0
	var input_dir := _read_input(delta)
	match state:
		State.NORMAL:
			if input_dir != Vector2.ZERO and not staggered:
				facing = input_dir.normalized()
			if _dodge_buffer_left > 0.0:
				_try_dodge(input_dir)
			if state == State.NORMAL and _attack_buffer_left > 0.0 and not staggered:
				_try_attack()
		State.ATTACK:
			# Dodge may cancel an attack; that keeps defence responsive.
			if _dodge_buffer_left > 0.0:
				_try_dodge(input_dir)
		State.DODGE:
			_dodge_time_left -= delta
			_spawn_dodge_ghosts(delta)
			if _dodge_time_left <= 0.0:
				state = State.NORMAL
	var move_input := Vector2.ZERO if staggered else input_dir
	velocity = _movement_velocity(move_input) + _knockback + _lunge
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	_lunge = _lunge.move_toward(Vector2.ZERO, attack_lunge_decay * delta)
	move_and_slide()
	_update_facing_marker()


func _process(delta: float) -> void:
	if _hurt_blink_left > 0.0:
		_hurt_blink_left -= delta
		_visual.visible = _hurt_blink_left <= 0.0 or fmod(_hurt_blink_left, 0.12) > 0.06


func is_dead() -> bool:
	return state == State.DEAD


func is_staggered() -> bool:
	return _stagger_left > 0.0


## 1 right after a dodge starts, 0 when the next dodge is available.
func get_dodge_cooldown_ratio() -> float:
	return clampf(_dodge_cooldown_left / dodge_cooldown, 0.0, 1.0)


## Teleports the player (room entry) and clears transient combat state.
func place_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_lunge = Vector2.ZERO
	_stagger_left = 0.0
	_attack_buffer_left = 0.0
	_dodge_buffer_left = 0.0
	if state != State.DEAD:
		melee.cancel()
		_reset_squash()
		state = State.NORMAL


func _read_input(delta: float) -> Vector2:
	_attack_buffer_left = maxf(_attack_buffer_left - delta, 0.0)
	_dodge_buffer_left = maxf(_dodge_buffer_left - delta, 0.0)
	if not controls_enabled:
		return Vector2.ZERO
	if Input.is_action_just_pressed(&"attack"):
		_attack_buffer_left = input_buffer_time
	if Input.is_action_just_pressed(&"dodge"):
		_dodge_buffer_left = input_buffer_time
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func _movement_velocity(input_dir: Vector2) -> Vector2:
	match state:
		State.NORMAL:
			return input_dir * move_speed
		State.ATTACK:
			return input_dir * move_speed * attack_move_multiplier
		State.DODGE:
			return _dodge_direction * dodge_speed
	return Vector2.ZERO


func _try_attack() -> void:
	if melee.start(facing):
		state = State.ATTACK
		_attack_buffer_left = 0.0


func _try_dodge(input_dir: Vector2) -> void:
	if _dodge_cooldown_left > 0.0:
		return
	if state == State.ATTACK:
		melee.cancel()
	_lunge = Vector2.ZERO
	_stagger_left = 0.0
	_dodge_direction = input_dir.normalized() if input_dir != Vector2.ZERO else facing
	facing = _dodge_direction
	state = State.DODGE
	_dodge_time_left = dodge_duration
	_dodge_cooldown_left = dodge_cooldown
	_dodge_buffer_left = 0.0
	_ghost_timer = 0.0
	health.grant_invulnerability(dodge_invulnerability)
	_reset_squash()
	BurstEffect.spawn(get_parent(), global_position, BurstEffect.Style.RING,
			Color(0.6, 0.85, 1.0, 0.8), 14.0, 34.0, 0.25)
	dodge_started.emit()


func _spawn_dodge_ghosts(delta: float) -> void:
	_ghost_timer -= delta
	if _ghost_timer > 0.0:
		return
	_ghost_timer = 0.035
	BurstEffect.spawn(get_parent(), global_position, BurstEffect.Style.DISC,
			Color(0.39, 0.7, 1.0, 0.4), 17.0, 15.0, 0.22)


func _on_attack_windup(duration: float) -> void:
	# Anticipation: gather in slightly before the swing.
	_tween_scale(Vector2(0.9, 0.9), duration)


func _on_attack_strike() -> void:
	_lunge = Vector2.from_angle(melee.rotation) * attack_lunge_speed
	# Release: pop out, then settle.
	_visual.scale = Vector2(1.12, 1.12)
	_tween_scale(Vector2.ONE, 0.14)


func _on_attack_finished() -> void:
	if state == State.ATTACK:
		state = State.NORMAL


func _on_hit_received(hitbox: Hitbox) -> void:
	var direction := hitbox.get_knockback_direction(global_position)
	_flash(Color(3.0, 0.7, 0.7))
	BurstEffect.spawn_spray(get_parent(), global_position - direction * 12.0, direction,
			Color(1.0, 0.45, 0.45, 0.95), 5, 1.4, 34.0, 0.18)
	hurt.emit(direction)
	if state == State.DEAD:
		return
	_knockback = direction * knockback_strength
	_lunge = Vector2.ZERO
	_stagger_left = hurt_stagger_time
	if state == State.ATTACK:
		melee.cancel()
		state = State.NORMAL
	_hurt_blink_left = health.invulnerability_after_hit
	_squash(direction)


func _on_died() -> void:
	state = State.DEAD
	melee.cancel()
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_lunge = Vector2.ZERO
	_hurt_blink_left = 0.0
	_visual.visible = true
	_facing_marker.hide()
	if _squash_tween != null:
		_squash_tween.kill()
	set_deferred(&"collision_layer", 0)
	_hurtbox.set_deferred(&"monitorable", false)
	BurstEffect.spawn(get_parent(), global_position, BurstEffect.Style.RING,
			Color(1.0, 0.3, 0.3, 0.9), 10.0, 70.0, 0.6)
	var tween := create_tween().set_parallel()
	tween.tween_property(_visual, ^"modulate", Color(0.45, 0.45, 0.55, 0.85), 0.5)
	tween.tween_property(_visual, ^"scale", Vector2(1.3, 0.55), 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	died.emit()


## Squashes along the dominant axis of `direction`, then springs back.
func _squash(direction: Vector2) -> void:
	var along := 0.72
	var across := 1.2
	_visual.scale = Vector2(along, across) if absf(direction.x) >= absf(direction.y) else Vector2(across, along)
	_tween_scale(Vector2.ONE, 0.18)


func _tween_scale(target: Vector2, duration: float) -> void:
	if _squash_tween != null:
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.tween_property(_visual, ^"scale", target, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reset_squash() -> void:
	if _squash_tween != null:
		_squash_tween.kill()
	_visual.scale = Vector2.ONE


func _flash(color: Color) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_visual.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, ^"modulate", Color.WHITE, 0.18)


func _update_facing_marker() -> void:
	_facing_marker.rotation = facing.angle()
