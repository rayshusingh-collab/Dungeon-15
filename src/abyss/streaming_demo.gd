extends Node3D

var _elapsed: float = 0


func _ready() -> void:
	$Instructions/Label.text = "The Shifting Abyss / streaming test\nWASD / arrows / left stick / D-pad | F3: controller diagnostics\nExplore the guarded links; return to revisit reconstructed chunks\nOrange gates wait for collision; R retries failed loads"


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0
		$Instructions/Streaming.text = $Streamer.diagnostic_text()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		$Streamer.retry_failed()
