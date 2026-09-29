class_name GameCamera
extends Camera2D
## Frames the current room so it is fully visible below the HUD strip at any
## aspect ratio (wider screens show extra margin, never crop the room).
## Impact feedback: kick() is a short directional push that eases back (reads
## as physical force); shake() is a decaying random jitter. The randomness is
## cosmetic only and deliberately not part of the seeded run RNG.

## Screen-space margins (base-resolution pixels) kept free around the room.
@export var margin_top: float = 60.0
@export var margin_bottom: float = 8.0
@export var margin_side: float = 8.0
## Global multiplier for kick + shake (a future accessibility/settings hook).
@export var feedback_scale: float = 1.0
## Hard cap on the total offset in pixels, so feedback never gets uncomfortable.
@export var max_offset: float = 14.0

var _frame: Rect2
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_time_left: float = 0.0
var _kick: Vector2 = Vector2.ZERO
var _kick_duration: float = 0.0
var _kick_time_left: float = 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)


func frame_rect(rect: Rect2) -> void:
	_frame = rect
	_refit()


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


func _refit() -> void:
	if _frame.size == Vector2.ZERO:
		return
	var view := get_viewport_rect().size
	var available := view - Vector2(margin_side * 2.0, margin_top + margin_bottom)
	var fit := minf(available.x / _frame.size.x, available.y / _frame.size.y)
	zoom = Vector2(fit, fit)
	# Centre the room in the area below the HUD strip rather than the screen.
	var screen_offset_y := (margin_top + available.y / 2.0) - view.y / 2.0
	global_position = _frame.get_center() - Vector2(0.0, screen_offset_y / fit)
