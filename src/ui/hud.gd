class_name Hud
extends CanvasLayer
## In-game HUD: health, room info, banners, damage flash, fades and the death
## screen. Knows nothing about gameplay nodes; Main pushes state in and
## listens to restart_requested.

signal restart_requested

var _banner_tween: Tween
var _flash_tween: Tween
var _fade_tween: Tween

@onready var _health_display: HealthDisplay = $HealthDisplay
@onready var _room_label: Label = $RoomLabel
@onready var _hint_label: Label = $HintLabel
@onready var _banner: Label = $Banner
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _fade: ColorRect = $Fade
@onready var _death_screen: Control = $DeathScreen
@onready var _death_info: Label = $DeathScreen/Panel/Info
@onready var _restart_button: Button = $DeathScreen/Panel/RestartButton


func _ready() -> void:
	_restart_button.pressed.connect(restart_requested.emit)
	_hint_label.visible = not OS.has_feature("mobile")
	_death_screen.hide()


func set_health(current: int, maximum: int) -> void:
	_health_display.set_health(current, maximum)


func set_room_info(room_number: int, enemies_left: int) -> void:
	if enemies_left > 0:
		_room_label.text = "ROOM %d   |   ENEMIES LEFT: %d" % [room_number, enemies_left]
	else:
		_room_label.text = "ROOM %d   |   CLEARED" % room_number


func show_banner(text: String, color: Color = Color.WHITE, hold: float = 1.3) -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.text = text
	_banner.modulate = Color(color, 0.0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, ^"modulate:a", 1.0, 0.15)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, ^"modulate:a", 0.0, 0.4)


func flash_damage() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_damage_flash.color.a = 0.22
	# UI feedback runs in real time, unaffected by gameplay hit-stop.
	_flash_tween = create_tween().set_ignore_time_scale(true)
	_flash_tween.tween_property(_damage_flash, ^"color:a", 0.0, 0.3)


## Fades the screen to black. Await it to sequence a transition.
func fade_out(duration: float) -> void:
	await _fade_to(1.0, duration)


func fade_in(duration: float) -> void:
	await _fade_to(0.0, duration)


func show_death(room_number: int) -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_death_info.text = "You reached room %d" % room_number
	# Short delay so the player sees what killed them before the overlay.
	var tween := create_tween()
	tween.tween_interval(0.7)
	tween.tween_callback(_reveal_death_screen)


func is_death_screen_visible() -> bool:
	return _death_screen.visible


func _reveal_death_screen() -> void:
	_death_screen.modulate.a = 0.0
	_death_screen.show()
	# Briefly disabled so a mashed attack key does not restart instantly.
	_restart_button.disabled = true
	var tween := create_tween()
	tween.tween_property(_death_screen, ^"modulate:a", 1.0, 0.25)
	tween.tween_interval(0.3)
	tween.tween_callback(_enable_restart)


func _enable_restart() -> void:
	_restart_button.disabled = false
	_restart_button.grab_focus()


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, ^"color:a", alpha, duration)
	await _fade_tween.finished
