class_name RoomMarker
extends Area2D
## Placeholder content socket that gives a room a reason to exist. Touching it
## "collects" it; Main decides what that means:
##   reward  optional reward (placeholder payload, Milestone 3)
##   lore    story inscription
##   secret  faint future-secret sign
##   heal    recovery shrine: restores health (resource-pressure hook). Not
##           consumed while the player is at full health.
##   cache   high-value reward behind a visible risk (placeholder payload)
##   power   future power-up socket guarded by an optional challenge fight

signal collected(marker: RoomMarker)

var kind: StringName = &"reward"
var is_collected: bool = false


func setup(center: Vector2, marker_kind: StringName) -> void:
	position = center
	kind = marker_kind
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	var node := CollisionShape2D.new()
	node.shape = shape
	add_child(node)
	body_entered.connect(_on_body_entered)


## Makes the marker collectable again (e.g. a shrine touched at full health).
func restore() -> void:
	is_collected = false
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if is_collected or not body is Player:
		return
	is_collected = true
	queue_redraw()
	collected.emit(self)


func _draw() -> void:
	var dim := 0.35 if is_collected else 1.0
	var font := ThemeDB.fallback_font
	match kind:
		&"reward":
			var gold := Color(0.95, 0.75, 0.25, dim)
			draw_rect(Rect2(-16, -10, 32, 22), gold.darkened(0.3))
			draw_rect(Rect2(-16, -14 if not is_collected else -22, 32, 7), gold)
			draw_rect(Rect2(-3, -4, 6, 6), Color(0.2, 0.15, 0.05, dim))
			_label(font, "REWARD" if not is_collected else "EMPTY", gold)
		&"cache":
			var bright := Color(1.0, 0.55, 0.2, dim)
			draw_rect(Rect2(-18, -12, 36, 26), bright.darkened(0.35))
			draw_rect(Rect2(-18, -16 if not is_collected else -24, 36, 8), bright)
			draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color(1, 0.6, 0.2, 0.5 * dim), 2.0)
			_label(font, "CACHE" if not is_collected else "EMPTY", bright)
		&"power":
			var violet := Color(0.75, 0.5, 1.0, dim)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -18), Vector2(14, 0), Vector2(0, 18), Vector2(-14, 0)]), violet)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)]),
					Color(1, 1, 1, 0.8 * dim))
			_label(font, "POWER" if not is_collected else "TAKEN", violet)
		&"heal":
			var green := Color(0.4, 0.95, 0.55, dim)
			draw_circle(Vector2.ZERO, 18.0, Color(0.1, 0.25, 0.14, dim))
			draw_rect(Rect2(-4, -12, 8, 24), green)
			draw_rect(Rect2(-12, -4, 24, 8), green)
			_label(font, "SHRINE" if not is_collected else "USED", green)
		&"lore":
			var stone := Color(0.7, 0.72, 0.8, dim)
			draw_rect(Rect2(-12, -18, 24, 32), stone.darkened(0.4))
			for i in 4:
				draw_line(Vector2(-7, -11 + i * 6), Vector2(7, -11 + i * 6), stone, 2.0)
			_label(font, "LORE", stone)
		&"secret":
			var hint := Color(0.6, 0.55, 0.75, 0.35 * dim)
			draw_line(Vector2(-14, -12), Vector2(-2, 0), hint, 2.0)
			draw_line(Vector2(-2, 0), Vector2(-8, 12), hint, 2.0)
			draw_line(Vector2(-2, 0), Vector2(12, 4), hint, 2.0)


func _label(font: Font, text: String, color: Color) -> void:
	draw_string_outline(font, Vector2(-50, 32), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, 4, Color.BLACK)
	draw_string(font, Vector2(-50, 32), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, color)
