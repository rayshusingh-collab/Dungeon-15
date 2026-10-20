extends "res://src/game_3d/first_dungeon.gd"
## F6-only validation scene; numeric shortcuts never exist in the campaign scene.
func _create_layout() -> DungeonLayout:
	fixture_mode = true
	run_seed = 1101
	return preload("res://src/game_3d/hazard_fixture_data.gd").create()

func _ready() -> void:
	super._ready()
	_marker(Vector2i(9,3),"OPEN PIT",Color(0.85,0.85,0.95),false)
	_marker(Vector2i(10,6),"BRIDGE",Color(0.9,0.7,0.4),false)
	_marker(Vector2i(10,11),"WATER / SLOW",Color(0.3,0.9,1),false)
	_marker(Vector2i(16,5),"TIMED SPIKES",Color(1,0.55,0.2),false)

func _unhandled_key_input(event: InputEvent) -> void:
	super._unhandled_key_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		var destinations := {KEY_1:Vector2i(6,5),KEY_2:Vector2i(6,11),KEY_3:Vector2i(14,5)}
		if destinations.has(event.physical_keycode):
			player.position = Grid.center(destinations[event.physical_keycode],0.05)
			player.velocity = Vector3.ZERO
