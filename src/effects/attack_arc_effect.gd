class_name AttackArcEffect
extends Node2D
## Placeholder visuals for a MeleeAttack, drawn in the attack's local space
## (+X = attack direction). Purely cosmetic: gameplay never reads this node.
## Windup, SECTOR style (enemy telegraph): the danger sector outline plus a fill
##   that grows until the strike.
## Windup, DRAWBACK style (player anticipation): the blade cocks back past the
##   start of the arc, with a faint outline of the reach.
## Strike: with sweep = true, the blade crosses the arc in sweep_time (timed to
##   the hitbox's first active frames, so the blade and the damage coincide),
##   leaving a trail that fades through recovery. With sweep = false, the whole
##   sector flashes.

enum Mode { NONE, WINDUP, STRIKE }
enum WindupStyle { SECTOR, DRAWBACK }

@export var windup_style: WindupStyle = WindupStyle.SECTOR
@export var sweep: bool = true
## Time for the blade to cross the whole arc.
@export var sweep_time: float = 0.05
## Alternate the sweep direction on every swing (reads as a combo).
@export var alternate_sweep: bool = true
@export var strike_color: Color = Color(1, 1, 1, 0.9)
@export var windup_color: Color = Color(1, 0.3, 0.2, 0.45)
## Inner radius of the slash trail, as a fraction of reach.
@export var inner_ratio: float = 0.4
## Opacity of the faint reach outline shown during a DRAWBACK windup.
@export var guide_alpha: float = 0.14
## If > 0, the strike visual lasts this long instead of active + recovery, so
## a danger flash doesn't linger after the damage window has closed.
@export var strike_visual_time: float = 0.0

var _reach: float = 60.0
var _arc: float = PI / 2.0
var _mode: Mode = Mode.NONE
var _time: float = 0.0
var _duration: float = 0.0
## +1 sweeps from -arc/2 to +arc/2, -1 the other way.
var _sign: float = 1.0
var _next_sign: float = 1.0
var _sign_locked: bool = false


func configure(reach: float, arc: float) -> void:
	_reach = reach
	_arc = arc


func play_windup(duration: float) -> void:
	_sign = _next_sign
	_sign_locked = true
	_start(Mode.WINDUP, duration)


func play_strike(duration: float) -> void:
	if not _sign_locked:
		_sign = _next_sign
	_sign_locked = false
	_next_sign = -_sign if alternate_sweep else _sign
	_start(Mode.STRIKE, strike_visual_time if strike_visual_time > 0.0 else duration)


func stop() -> void:
	_mode = Mode.NONE
	_sign_locked = false
	queue_redraw()


func _start(mode: Mode, duration: float) -> void:
	_mode = mode
	_duration = maxf(duration, 0.01)
	_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _mode == Mode.NONE:
		return
	_time += delta
	if _time >= _duration:
		_mode = Mode.NONE
	queue_redraw()


func _draw() -> void:
	match _mode:
		Mode.WINDUP:
			if windup_style == WindupStyle.SECTOR:
				_draw_telegraph()
			else:
				_draw_drawback()
		Mode.STRIKE:
			if sweep:
				_draw_sweep()
			else:
				var p := clampf(_time / _duration, 0.0, 1.0)
				_draw_sector(0.0, _reach, -_arc / 2.0, _arc / 2.0, Color(strike_color, strike_color.a * (1.0 - p)))


func _draw_telegraph() -> void:
	var half := _arc / 2.0
	var p := clampf(_time / _duration, 0.0, 1.0)
	_draw_sector(0.0, _reach * p, -half, half, Color(windup_color, windup_color.a * (0.3 + 0.7 * p)))
	var edge := Color(windup_color, minf(1.0, windup_color.a + 0.4))
	draw_arc(Vector2.ZERO, _reach, -half, half, 24, edge, 3.0)
	draw_line(Vector2.ZERO, Vector2.from_angle(-half) * _reach, edge, 3.0)
	draw_line(Vector2.ZERO, Vector2.from_angle(half) * _reach, edge, 3.0)


func _draw_drawback() -> void:
	var half := _arc / 2.0
	var p := clampf(_time / _duration, 0.0, 1.0)
	draw_arc(Vector2.ZERO, _reach, -half, half, 24, Color(strike_color, guide_alpha), 2.0)
	# Blade cocks back beyond the start of the arc.
	var angle := -half * _sign - 0.35 * _sign * ease(p, 0.5)
	var blade := Vector2.from_angle(angle)
	draw_line(blade * _reach * 0.3, blade * _reach * 0.9, Color(strike_color, strike_color.a * (0.35 + 0.55 * p)), 4.0)


func _draw_sweep() -> void:
	var half := _arc / 2.0
	var swing := clampf(_time / maxf(sweep_time, 0.001), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - swing, 3.0)
	var start_angle := -half * _sign
	var lead := start_angle + _sign * _arc * eased
	var fade := 1.0
	if _time > sweep_time:
		fade = 1.0 - clampf((_time - sweep_time) / maxf(_duration - sweep_time, 0.001), 0.0, 1.0)
	var color := Color(strike_color, strike_color.a * fade)
	_draw_sector(_reach * inner_ratio, _reach, minf(start_angle, lead), maxf(start_angle, lead), Color(color, color.a * 0.5))
	var blade := Vector2.from_angle(lead)
	draw_line(blade * _reach * 0.3, blade * _reach * 1.05, color, 5.0 if swing < 1.0 else 3.0)


func _draw_sector(inner: float, outer: float, from_angle: float, to_angle: float, color: Color) -> void:
	if outer - inner < 1.0 or to_angle - from_angle < 0.02:
		return
	var segments := maxi(3, int((to_angle - from_angle) / 0.12))
	var points := PackedVector2Array()
	for i in segments + 1:
		points.append(Vector2.from_angle(lerpf(from_angle, to_angle, float(i) / segments)) * outer)
	if inner <= 0.0:
		points.append(Vector2.ZERO)
	else:
		for i in range(segments, -1, -1):
			points.append(Vector2.from_angle(lerpf(from_angle, to_angle, float(i) / segments)) * inner)
	draw_colored_polygon(points, color)
