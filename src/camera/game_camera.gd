class_name GameCamera
extends Camera2D
## Follows a target through a dungeon larger than the screen, with smoothing
## and limits at the dungeon bounds (so the void outside is rarely shown).
## Impact feedback: kick() is a short directional push that eases back (reads
## as physical force); shake() is a decaying random jitter. The randomness is
## cosmetic only and deliberately not part of the seeded run RNG.

@export var follow_zoom: float = 1.0
@export var smoothing_speed: float = 7.0
## Global multiplier for kick + shake (a future accessibility/settings hook).
@export var feedback_scale: float = 1.0
## Hard cap on the total offset in pixels, so feedback never gets uncomfortable.
@export var max_offset: float = 14.0

var target: Node2D

var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_time_left: float = 0.0
var _kick: Vector2 = Vector2.ZERO
var _kick_duration: float = 0.0
var _kick_time_left: float = 0.0


func _ready() -> void:
	zoom = Vector2(follow_zoom, follow_zoom)
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed


func follow(new_target: Node2D) -> void:
	target = new_target


## Limits the view to `rect` (pixels). Larger views are centred by Camera2D.
func set_bounds(rect: Rect2) -> void:
	limit_left = floori(rect.position.x)
	limit_top = floori(rect.position.y)
	limit_right = ceili(rect.end.x)
	limit_bottom = ceili(rect.end.y)


## Jumps to the target without smoothing (depth start, teleports).
func snap() -> void:
	if target != null:
		global_position = target.global_position
	reset_smoothing()


## Adds a decaying random offset. Stronger shakes override weaker ones.
func shake(strength: float, duration: float) -> void:
	if strength < _shake_strength * (_shake_time_left / maxf(_shake_duration, 0.001)):
		return
	_shake_strength = strength
	_shake_duration = duration
	_shake_time_left = duration


## Pushes the view `strength` pixels along `direction`, easing back over `duration`.
func kick(direction: Vector2, strength: float, duration: float = 0.14) -> void:
	if direction == Vector2.ZERO:
		return
	_kick = direction.normalized() * strength
	_kick_duration = duration
	_kick_time_left = duration


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position
	var total := Vector2.ZERO
	if _shake_time_left > 0.0:
		_shake_time_left = maxf(_shake_time_left - delta, 0.0)
		var k := _shake_time_left / _shake_duration
		total += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * k * k
	if _kick_time_left > 0.0:
		_kick_time_left = maxf(_kick_time_left - delta, 0.0)
		var k := _kick_time_left / _kick_duration
		total += _kick * k * k
	offset = (total * feedback_scale).limit_length(max_offset)
