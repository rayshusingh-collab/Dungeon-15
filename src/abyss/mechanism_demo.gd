extends "res://src/abyss/streaming_demo.gd"


func _ready() -> void:
	super._ready()
	$Instructions/Label.text = "The Shifting Abyss / ancient mechanism\nFind the gold mechanism beside the disconnected east bridge\nE / south face button: interact | F4: verify south button\nCross to the Wayfinder chamber, then leave and return"
	$MechanismInput.interacted.connect($Streamer.activate)


func _process(delta: float) -> void:
	super._process(delta)
	$Instructions/Mechanism.text = $Streamer.prompt() + "\n" + $MechanismInput.mapping_status
