class_name BurstEffect
extends Node2D
## Short-lived procedural placeholder effect (ring / disc / shards) that frees
## itself. Spawn it into the world, not as a child of a moving actor.
## Shards can spray in a direction (spread < TAU) for directional impacts.

enum Style { RING, DISC, SHARDS }

var style: Style = Style.RING
var color: Color = Color.WHITE
var radius_from: float = 4.0
var radius_to: float = 32.0
var duration: float = 0.3
var shard_count: int = 8
var direction: Vector2 = Vector2.RIGHT
var spread: float = TAU

var _time: float = 0.0


static func spawn(parent: Node, at: Vector2, fx_style: Style, fx_color: Color,
		from_radius: float, to_radius: float, fx_duration: float) -> BurstEffect:
	var fx := BurstEffect.new()
	fx.style = fx_style
	fx.color = fx_color
	fx.radius_from = from_radius
	fx.radius_to = to_radius
	fx.duration = fx_duration
	parent.add_child(fx)
	fx.global_position = at
	return fx


## Directional shard spray (impact sparks) centred on `spray_direction`.
static func spawn_spray(parent: Node, at: Vector2, spray_direction: Vector2, fx_color: Color,
		count: int, spray_spread: float, to_radius: float, fx_duration: float) -> BurstEffect:
	var fx := spawn(parent, at, Style.SHARDS, fx_color, 4.0, to_radius, fx_duration)
	fx.direction = spray_direction.normalized() if spray_direction != Vector2.ZERO else Vector2.RIGHT
	fx.spread = spray_spread
	fx.shard_count = count
	return fx


func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var p := clampf(_time / duration, 0.0, 1.0)
	var radius := lerpf(radius_from, radius_to, 1.0 - (1.0 - p) * (1.0 - p))
	var c := Color(color, color.a * (1.0 - p))
	match style:
		Style.RING:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, c, maxf(1.0, 4.0 * (1.0 - p)))
		Style.DISC:
			draw_circle(Vector2.ZERO, radius, c)
		Style.SHARDS:
			var base := direction.angle()
			for i in shard_count:
				var angle: float
				if spread >= TAU:
					angle = TAU * i / shard_count + 0.3
				else:
					var t := 0.5 if shard_count == 1 else float(i) / (shard_count - 1)
					angle = base + (t - 0.5) * spread
				# Alternate shard lengths so the spray doesn't look like a fan.
				var length := 1.0 if i % 2 == 0 else 0.7
				var dir := Vector2.from_angle(angle)
				draw_line(dir * radius * 0.5 * length, dir * radius * length, c, 3.0)
