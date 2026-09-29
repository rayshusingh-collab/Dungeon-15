class_name HealthBar
extends Node2D
## Small placeholder world-space health bar that tracks a HealthComponent.

@export var health: HealthComponent
@export var width: float = 36.0
@export var height: float = 6.0
@export var fill_color: Color = Color(0.95, 0.3, 0.3)
@export var back_color: Color = Color(0, 0, 0, 0.7)
## Hide until the first point of damage (keeps the screen uncluttered).
@export var hide_when_full: bool = true


func _ready() -> void:
	if health != null:
		health.health_changed.connect(_on_health_changed)
	_refresh()


func _on_health_changed(_current: int, _maximum: int) -> void:
	_refresh()


func _refresh() -> void:
	visible = health != null and not health.is_dead() \
		and not (hide_when_full and health.current >= health.max_health)
	queue_redraw()


func _draw() -> void:
	if health == null or health.max_health <= 0:
		return
	var rect := Rect2(Vector2(-width / 2.0, -height / 2.0), Vector2(width, height))
	draw_rect(rect.grow(1.0), back_color)
	var ratio := float(health.current) / health.max_health
	draw_rect(Rect2(rect.position, Vector2(width * ratio, height)), fill_color)
	# Segment ticks so individual hit points are countable.
	for i in range(1, health.max_health):
		var x := rect.position.x + width * i / health.max_health
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), back_color, 1.0)
