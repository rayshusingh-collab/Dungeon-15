class_name Hud
extends CanvasLayer
## In-game HUD: health, depth + seed, status line, banners, damage flash,
## fades, debug map, seed panel, death and depth-complete screens.
## Knows nothing about gameplay nodes; Main pushes state in and listens to
## the request signals. Runs while the tree is paused (seed panel).

signal retry_requested
signal new_seed_requested
signal next_depth_requested
signal play_seed_requested(seed_value: int)
signal seed_panel_toggled(open: bool)
## Debug builds: the TAC button asks Main to toggle the tactical overlay.
signal tactical_overlay_requested

var _banner_tween: Tween
var _flash_tween: Tween
var _fade_tween: Tween
var _run_seed: int = 0
var _depth: int = 1
var _debug_event_tween: Tween

@onready var map: DungeonMap = $Map
@onready var seed_panel: SeedPanel = $SeedPanel
@onready var _health_display: HealthDisplay = $HealthDisplay
@onready var _run_label: Label = $RunLabel
@onready var _status_label: Label = $StatusLabel
@onready var _hint_label: Label = $HintLabel
@onready var _debug_event_label: Label = $DebugEventLabel
@onready var _banner: Label = $Banner
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _fade: ColorRect = $Fade
@onready var _death_screen: Control = $DeathScreen
@onready var _death_info: Label = $DeathScreen/Panel/Info
@onready var _retry_button: Button = $DeathScreen/Panel/Buttons/RetryButton
@onready var _complete_screen: Control = $CompleteScreen
@onready var _complete_title: Label = $CompleteScreen/Panel/Title
@onready var _complete_info: Label = $CompleteScreen/Panel/Info
@onready var _next_button: Button = $CompleteScreen/Panel/Buttons/NextButton
@onready var _replay_button: Button = $CompleteScreen/Panel/Buttons/ReplayButton


func _ready() -> void:
	$TopButtons/MapButton.pressed.connect(toggle_map.bind(DungeonMap.Mode.EXPLORATION))
	$TopButtons/DebugMapButton.pressed.connect(toggle_map.bind(DungeonMap.Mode.DEBUG_FULL))
	# The full map and the tactical overlay are development tools: debug builds only.
	$TopButtons/DebugMapButton.visible = OS.is_debug_build()
	$TopButtons/TacticsButton.visible = OS.is_debug_build()
	$TopButtons/TacticsButton.pressed.connect(tactical_overlay_requested.emit)
	_debug_event_label.modulate.a = 0.0
	$TopButtons/SeedButton.pressed.connect(open_seed_panel)
	_retry_button.pressed.connect(retry_requested.emit)
	$DeathScreen/Panel/Buttons/NewSeedButton.pressed.connect(new_seed_requested.emit)
	_next_button.pressed.connect(next_depth_requested.emit)
	_replay_button.pressed.connect(retry_requested.emit)
	$CompleteScreen/Panel/Buttons/NewSeedButton.pressed.connect(new_seed_requested.emit)
	seed_panel.play_seed_requested.connect(play_seed_requested.emit)
	seed_panel.replay_requested.connect(retry_requested.emit)
	seed_panel.new_seed_requested.connect(new_seed_requested.emit)
	seed_panel.closed.connect(seed_panel_toggled.emit.bind(false))
	_hint_label.visible = not OS.has_feature("mobile")
	_death_screen.hide()
	_complete_screen.hide()
	seed_panel.hide()
	map.hide()


func set_health(current: int, maximum: int) -> void:
	_health_display.set_health(current, maximum)


func set_run_info(depth: int, depth_name: String, run_seed: int) -> void:
	_depth = depth
	_run_seed = run_seed
	_run_label.text = "%s   |   SEED %d" % [depth_name.to_upper(), run_seed]


func get_run_text() -> String:
	return _run_label.text


func set_status(text: String, color: Color = Color(0.85, 0.85, 0.92)) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(&"font_color", color)


func get_status() -> String:
	return _status_label.text


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


## Opens the map in `map_mode`, or closes it if it is already open in that mode.
func toggle_map(map_mode: DungeonMap.Mode = DungeonMap.Mode.EXPLORATION) -> void:
	if map.visible and map.mode == map_mode:
		map.hide()
		return
	map.set_mode(map_mode)
	map.show()
	map.queue_redraw()


## Short development-only line for proof events (tension sockets).
func show_debug_event(text: String) -> void:
	if _debug_event_tween != null:
		_debug_event_tween.kill()
	_debug_event_label.text = text
	_debug_event_label.modulate.a = 1.0
	_debug_event_tween = create_tween()
	_debug_event_tween.tween_interval(2.5)
	_debug_event_tween.tween_property(_debug_event_label, ^"modulate:a", 0.0, 0.6)


func get_debug_event_text() -> String:
	return _debug_event_label.text


func is_map_visible() -> bool:
	return map.visible


func open_seed_panel() -> void:
	seed_panel.open(_run_seed, _depth)
	seed_panel_toggled.emit(true)


func is_seed_panel_open() -> bool:
	return seed_panel.visible


func show_death(stats_text: String) -> void:
	_hide_banner()
	_death_info.text = stats_text
	# Short delay so the player sees what killed them before the overlay.
	var tween := create_tween()
	tween.tween_interval(0.7)
	tween.tween_callback(_reveal.bind(_death_screen, _retry_button))


func is_death_screen_visible() -> bool:
	return _death_screen.visible


func show_depth_complete(title: String, stats_text: String, has_next_depth: bool) -> void:
	_hide_banner()
	_complete_title.text = title
	_complete_info.text = stats_text
	_next_button.visible = has_next_depth
	_reveal(_complete_screen, _next_button if has_next_depth else _replay_button)


func show_generation_failure(message: String) -> void:
	_hide_banner()
	_complete_title.text = "GENERATION FAILED"
	_complete_info.text = message
	_next_button.visible = false
	_replay_button.visible = false
	_reveal(_complete_screen, $CompleteScreen/Panel/Buttons/NewSeedButton)


func is_complete_screen_visible() -> bool:
	return _complete_screen.visible


func press_button(path: String) -> void:
	(get_node(path) as Button).pressed.emit()


func _reveal(screen: Control, focus_button: Button) -> void:
	screen.modulate.a = 0.0
	screen.show()
	# Briefly disabled so a mashed attack key does not trigger a button.
	for button in screen.find_children("*", "Button", true, false):
		(button as Button).disabled = true
	var tween := create_tween()
	tween.tween_property(screen, ^"modulate:a", 1.0, 0.25)
	tween.tween_interval(0.3)
	tween.tween_callback(_enable_buttons.bind(screen, focus_button))


func _enable_buttons(screen: Control, focus_button: Button) -> void:
	for button in screen.find_children("*", "Button", true, false):
		(button as Button).disabled = false
	focus_button.grab_focus()


func _hide_banner() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 0.0


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, ^"color:a", alpha, duration)
	await _fade_tween.finished
