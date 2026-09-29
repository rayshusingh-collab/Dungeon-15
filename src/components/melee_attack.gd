class_name MeleeAttack
extends Node2D
## Reusable melee attack: WINDUP -> ACTIVE -> RECOVERY. Owns a child Hitbox
## shaped as a circular sector (reach / arc) and optionally drives an
## AttackArcEffect for visuals. This node's rotation is the attack direction.

signal windup_started(duration: float)
signal strike_started
signal recovery_started(duration: float)
signal finished
signal hit_landed(hurtbox: Hurtbox)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

@export var reach: float = 80.0
@export_range(10.0, 180.0) var arc_degrees: float = 120.0
## Telegraph time before the hitbox turns on (0 = instant).
@export var windup_time: float = 0.0
@export var active_time: float = 0.12
@export var recovery_time: float = 0.08
## Minimum time between attack starts.
@export var cooldown: float = 0.3
@export var effect: AttackArcEffect

var phase: Phase = Phase.IDLE

var _phase_time_left: float = 0.0
var _cooldown_left: float = 0.0

@onready var hitbox: Hitbox = $Hitbox
@onready var _hitbox_shape: CollisionPolygon2D = $Hitbox/CollisionPolygon2D


func _ready() -> void:
	_hitbox_shape.polygon = build_sector(reach, deg_to_rad(arc_degrees), 10)
	hitbox.hit_landed.connect(hit_landed.emit)
	if effect != null:
		effect.configure(reach, deg_to_rad(arc_degrees))


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if phase == Phase.IDLE:
		return
	_phase_time_left -= delta
	if _phase_time_left > 0.0:
		return
	match phase:
		Phase.WINDUP:
			_begin_strike()
		Phase.ACTIVE:
			hitbox.deactivate()
			_enter(Phase.RECOVERY, recovery_time)
			recovery_started.emit(recovery_time)
		Phase.RECOVERY:
			phase = Phase.IDLE
			finished.emit()


func can_start() -> bool:
	return phase == Phase.IDLE and _cooldown_left <= 0.0


func is_busy() -> bool:
	return phase != Phase.IDLE


## Starts an attack toward `direction`. Returns false if busy or cooling down.
func start(direction: Vector2) -> bool:
	if not can_start() or direction == Vector2.ZERO:
		return false
	rotation = direction.angle()
	_cooldown_left = cooldown
	if windup_time > 0.0:
		_enter(Phase.WINDUP, windup_time)
		windup_started.emit(windup_time)
		if effect != null:
			effect.play_windup(windup_time)
	else:
		_begin_strike()
	return true


## Aborts the current attack (e.g. interrupted by a hit or a dodge). The
## cooldown keeps running; `finished` is not emitted.
func cancel() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.IDLE
	hitbox.deactivate()
	if effect != null:
		effect.stop()


## Overrides the remaining cooldown (e.g. a fixed delay after being staggered).
func set_cooldown_remaining(seconds: float) -> void:
	_cooldown_left = maxf(seconds, 0.0)


## 1 right after an attack starts, 0 when another attack is allowed.
func get_cooldown_ratio() -> float:
	return clampf(_cooldown_left / cooldown, 0.0, 1.0) if cooldown > 0.0 else 0.0


static func build_sector(radius: float, arc: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in segments + 1:
		points.append(Vector2.from_angle(-arc / 2.0 + arc * i / segments) * radius)
	return points


func _begin_strike() -> void:
	_enter(Phase.ACTIVE, active_time)
	# With a windup the hitbox was rotated at least one physics step ago, so
	# its overlaps are already current and it may hit on the first active frame.
	hitbox.activate(windup_time <= 0.0)
	strike_started.emit()
	if effect != null:
		effect.play_strike(active_time + recovery_time)


func _enter(new_phase: Phase, duration: float) -> void:
	phase = new_phase
	_phase_time_left = duration
