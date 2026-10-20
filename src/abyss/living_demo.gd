extends "res://src/abyss/streaming_demo.gd"


func _ready() -> void:
	super._ready()
	$Instructions/Label.text = "The Shifting Abyss / the living castle\nWASD / arrows / left stick / D-pad | F3: controller diagnostics\nThe unseen Castle Master controls the east bridge\nWhen warned, follow SOUTH (0,1) > (1,1) > Wayfinder (1,0)"


func _process(delta: float) -> void:
	super._process(delta)
	if $Streamer.director != null:
		var data: Dictionary = $Streamer.state()
		$Instructions/Director.text = $Streamer.message + "\nRoute: %s | active events %d/1 | ambient structures 12" % [
			data.stable, 0 if data.active.is_empty() else 1]
