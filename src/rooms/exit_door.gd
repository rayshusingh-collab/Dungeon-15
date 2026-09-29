class_name ExitDoor
extends Node2D
## Room exit. Locked: a solid Blocker fills the doorway. Unlocked: the Blocker
## is disabled and walking into the doorway emits player_entered. The
## Threshold body behind the doorway is always solid, so the player can never
## leave the room bounds, even before the transition fires.

signal player_entered

@export var size: Vector2 = Vector2(32, 68)
@export var locked_color: Color = Color("b33b4b")
@export var open_color: Color = Color("45d483")

var locked: bool = true

var _pulse: float = 0.0

@onready var _blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D
@onready var _trigger: Area2D = $Trigger
@onready var _label: Label = $Label


func _ready() -> void:
	_trigger.body_entered.connect(_on_trigger_body_entered)
	_apply_state()


func set_locked(value: bool) -> void:
	locked = value
	if is_node_ready():
		_apply_state()


func _apply_state() -> void:
	_blocker_shape.set_deferred(&"disabled", not locked)
	_trigger.set_deferred(&"monitoring", not locked)
	_label.text = "LOCKED" if locked else "EXIT"
	_label.add_theme_color_override(&"font_color", locked_color.lightened(0.35) if locked else open_color)
	set_process(not locked)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _on_trigger_body_entered(body: Node2D) -> void:
	if not locked and body is Player:
		player_entered.emit()


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	if locked:
		draw_rect(rect, locked_color)
		for i in 3:
			var y := rect.position.y + size.y * (i + 1) / 4.0
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0, 0, 0, 0.45), 4.0)
		draw_rect(rect, Color(1, 1, 1, 0.55), false, 2.0)
	else:
		var glow := 0.55 + 0.45 * sin(_pulse * 5.0)
		draw_rect(rect, Color(open_color, 0.3 + 0.45 * glow))
		# Chevrons pointing out of the room (+X).
		for x: float in [-6.0, 5.0]:
			draw_polyline(PackedVector2Array([Vector2(x - 5, -11), Vector2(x + 4, 0), Vector2(x - 5, 11)]),
					Color(1, 1, 1, 0.5 + 0.5 * glow), 3.0)
