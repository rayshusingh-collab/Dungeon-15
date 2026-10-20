extends "res://src/game_3d/combat/combat_floor.gd"
var depth := 1
var depth_seed := 12345

func _create_layout() -> DungeonLayout:
	run_seed=depth_seed
	var result := DungeonGenerator.new().generate(DepthProfile.load_for_depth(depth),depth_seed,depth)
	if not result.ok:
		push_error("Descent generation failed: " + str(result.failure_log))
		return null
	return result.layout

func _plan_encounters() -> Array[Dictionary]:
	return navigation.plan_encounters(depth,true)

func _ready() -> void:
	super._ready()
	for enemy in enemies:
		enemy.max_health+=depth-1
		enemy.health=enemy.max_health

func reset_to_entry() -> void:
	# Pits and raised spikes remain fatal, without silently healing the run.
	if is_instance_valid(player) and player.state!=player.State.DEAD:
		player.hurt_grace=0
		player._set_state(player.State.READY)
		player.receive_damage(player.max_health,Vector3.ZERO)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_H:
		survey_visible=not survey_visible

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Contact only prompts; explicit interaction completes a floor.
	reached_exit=false
