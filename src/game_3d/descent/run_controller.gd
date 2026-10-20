extends Node3D
## Owns the run; each floor is a disposable instance of the accepted combat floor.
const Floor = preload("res://src/game_3d/descent/descent_floor.gd")
const Pad = preload("res://src/game_3d/combat/combat_input.gd")
const Grid = preload("res://src/game_3d/grid_space.gd")
enum Phase { BUILDING, PLAYING, REWARD, DEAD, VICTORY }
const UPGRADE_NAMES := ["Sharpened Blade", "Reinforced Guard", "Swift Step"]
const UPGRADE_EFFECTS := ["+1 damage on both cuts (maximum +3)", "+2 maximum health and heal 2 (maximum 14 HP)", "-0.08s dodge interval (minimum 0.36s)"]
@export var run_seed: int = 12345
var depth := 1
var phase := Phase.BUILDING
var floor_node: Node3D
var ranks := [0,0,0]
var health := 8
var rewarded: Dictionary = {}
var cleared: Dictionary = {}
var builds: Array[Dictionary] = []
var selected := 0
var panel: PanelContainer
var heading: Label
var buttons: Array[Button] = []
var hud: Label
var modal_age := 0.0
var _pressed: Dictionary = {}
var _axis_held: Dictionary = {}
var _transitioning := false

static func seed_for(seed_value: int, depth_value: int) -> int:
	if depth_value<1 or depth_value>3:
		return -1
	return seed_value if depth_value==1 else StableHash.hash62("DUNGEON15:M3:%d:%d" % [seed_value,depth_value])%2147483647

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			run_seed=int(arg.trim_prefix("--seed="))
	var canvas := CanvasLayer.new()
	canvas.layer=10
	add_child(canvas)
	hud=Label.new()
	hud.position=Vector2(18,18)
	hud.add_theme_constant_override("outline_size",6)
	canvas.add_child(hud)
	panel=PanelContainer.new()
	panel.position=Vector2(170,205)
	panel.custom_minimum_size=Vector2(810,240)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	heading=Label.new()
	heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	for i in 3:
		var button := Button.new()
		button.custom_minimum_size=Vector2(780,48)
		button.pressed.connect(func() -> void: choose_upgrade(i))
		column.add_child(button)
		buttons.append(button)
	panel.hide()
	_build_floor()

func _build_floor() -> void:
	var started := Time.get_ticks_usec()
	phase=Phase.BUILDING
	floor_node=Node3D.new()
	floor_node.set_script(Floor)
	floor_node.depth=depth
	floor_node.depth_seed=seed_for(run_seed,depth)
	var input := Node.new()
	input.name="ControllerInput"
	input.set_script(Pad)
	floor_node.add_child(input)
	add_child(floor_node)
	if floor_node.encounters.size()<3 or floor_node.route.is_empty():
		phase=Phase.DEAD
		_modal("FLOOR COULD NOT BE BUILT SAFELY\nR: restart this run")
		return
	_apply_stats()
	_clear_combat_edges()
	floor_node.status.hide()
	floor_node.health_bar.position=Vector2(18,180)
	builds.append({"depth":depth,"seed":floor_node.depth_seed,"fingerprint":floor_node.layout.fingerprint(),"build_ms":(Time.get_ticks_usec()-started)/1000.0,"enemies":floor_node.enemies.size(),"nodes":get_tree().get_node_count(),"collisions":floor_node.rects.filter(func(r: Dictionary) -> bool: return r.kind!=DungeonLayout.Tile.PIT).size()+floor_node.enemies.size()+1})
	print("M3 floor ",builds[-1])
	phase=Phase.PLAYING
	_transitioning=false
	panel.hide()

func _apply_stats() -> void:
	var samurai: CharacterBody3D=floor_node.player
	samurai.max_health=8+2*ranks[1]
	samurai.health=clampi(health,0,samurai.max_health)
	samurai.sword_bonus=ranks[0]
	samurai.dodge_interval=0.6-0.08*ranks[2]
	floor_node.health_bar.max_value=samurai.max_health

func _clear_combat_edges() -> void:
	floor_node.input_source._pending=[false,false]
	for i in floor_node.input_source.combat_actions.size():
		floor_node.input_source._held[i]=Input.is_action_pressed(floor_node.input_source.combat_actions[i])

func _process(delta: float) -> void:
	modal_age+=delta
	if not is_instance_valid(floor_node) or phase==Phase.BUILDING:
		return
	if not is_instance_valid(floor_node.player):
		hud.text="FLOOR BUILD FAILED SAFELY / R: retry run"
		return
	if phase==Phase.PLAYING:
		health=floor_node.player.health
		cleared[depth]=floor_node.room_cleared.duplicate()
		if health<=0:
			phase=Phase.DEAD
			_modal("YOU DIED / DEPTH %d\nR or south / Enter: new run at Depth 1" % depth)
		elif floor_node.room_cleared.get(floor_node.required_room,false) and not rewarded.has(depth):
			phase=Phase.REWARD
			selected=0
			_modal("REQUIRED PATROL CLEARED / CHOOSE ONE UPGRADE\nArrows / WASD / stick / D-pad: select | Enter / south / click: choose")
			_update_choices()
	var unlocked: bool=rewarded.has(depth)
	var near_exit: bool=Grid.tile_at(floor_node.player.position)==floor_node.layout.exit_tile
	var objective_text := "EXIT READY - reach the green marker" if unlocked else "Required objective: defeat patrol H%02d (amber doorway sign)" % floor_node.required_room
	var controls_text := "E / Enter / south: descend" if near_exit and unlocked else "Move: WASD/arrows/pad | Attack: Space/J/south | Dodge: Shift/K/east | R: new run | H: diagnostics"
	if phase in [Phase.DEAD,Phase.VICTORY]:
		objective_text="VERTICAL-SLICE VICTORY" if phase==Phase.VICTORY else "YOU DIED"
		controls_text="R / Enter / south: new run at Depth 1"
	hud.text="THE DESCENT / VERTICAL SLICE / DEPTH %d OF 3\nRun %d / Floor %d / HP %d/%d\nBlade %d | Guard %d | Step %d | Depths completed %d/3\n%s\n%s" % [depth,run_seed,floor_node.depth_seed,health,floor_node.player.max_health,ranks[0],ranks[1],ranks[2],depth if phase==Phase.VICTORY else depth-1,objective_text,controls_text]
	if floor_node.survey_visible:
		hud.text+="\nPad %d | %s | deadzone %.2f | %s" % [floor_node.input_source.device_id,str(floor_node.input_source.stick_vector()),floor_node.input_source.deadzone,floor_node.input_source.last_button_event]
	elif phase in [Phase.PLAYING,Phase.REWARD]:
		var target: Vector3=Grid.center(floor_node.layout.exit_tile)
		var target_name := "Exit"
		if not unlocked:
			for encounter in floor_node.encounters:
				if not floor_node.room_cleared.get(encounter.room,false):
					target=Grid.center(encounter.entry)
					target_name="Patrol H%02d" % encounter.room
					break
		var offset: Vector3=target-floor_node.player.position
		var right: float=offset.dot(floor_node.camera.global_basis.x)
		var down: float=offset.dot(floor_node.camera.global_basis.z)
		var bearing := ("right" if right>0 else "left") if absf(right)>absf(down) else ("down-screen" if down>0 else "up-screen")
		hud.text+="\n%s: %s / %.0fm direct bearing (follow doorways) | %s" % [target_name,bearing,Vector2(offset.x,offset.z).length(),floor_node.player.STATE_NAMES[floor_node.player.state]]

func _modal(text: String) -> void:
	modal_age=0
	_axis_held.clear()
	floor_node.process_mode=Node.PROCESS_MODE_DISABLED
	heading.text=text
	panel.show()
	for button in buttons:
		button.visible=phase==Phase.REWARD
	if phase==Phase.DEAD and is_instance_valid(floor_node.player):
		floor_node.player.visual.rotation.z=-PI/2
		if is_instance_valid(floor_node.damage_overlay):
			floor_node.damage_overlay.color.a=0.13

func _update_choices() -> void:
	for i in buttons.size():
		buttons[i].text=("> " if selected==i else "")+UPGRADE_NAMES[i]+" / "+UPGRADE_EFFECTS[i]+" / rank %d" % ranks[i]
	buttons[selected].grab_focus()

func choose_upgrade(index: int) -> bool:
	if phase!=Phase.REWARD or modal_age<0.25 or index<0 or index>2 or rewarded.has(depth):
		return false
	ranks[index]=mini(3,ranks[index]+1)
	if index==1:
		health=mini(health+2,8+2*ranks[1])
	rewarded[depth]=index
	_apply_stats()
	phase=Phase.PLAYING
	panel.hide()
	_clear_combat_edges()
	floor_node.process_mode=Node.PROCESS_MODE_INHERIT
	floor_node.banner="UPGRADE CHOSEN - EXIT READY / E, Enter or south at the marker"
	floor_node.banner_time=5
	return true

func try_exit() -> bool:
	if depth<1 or depth>3 or phase!=Phase.PLAYING or _transitioning or not rewarded.has(depth) or not floor_node.room_cleared.get(floor_node.required_room,false) or floor_node.player.health<=0 or Grid.tile_at(floor_node.player.position)!=floor_node.layout.exit_tile:
		return false
	_transitioning=true
	cleared[depth]=floor_node.room_cleared.duplicate()
	health=floor_node.player.health
	if depth==3:
		phase=Phase.VICTORY
		_modal("VERTICAL-SLICE VICTORY / THREE DEPTHS CLEARED\nDepths 4-15 are outside this slice.\nR or south / Enter: new run")
	else:
		phase=Phase.BUILDING
		floor_node.process_mode=Node.PROCESS_MODE_DISABLED
		_replace_floor.call_deferred(depth+1,false)
	return true

func restart_run() -> void:
	if phase==Phase.BUILDING:
		return
	phase=Phase.BUILDING
	floor_node.process_mode=Node.PROCESS_MODE_DISABLED
	_replace_floor.call_deferred(1,true)

func _replace_floor(next_depth: int, fresh: bool) -> void:
	if next_depth<1 or next_depth>3:
		return
	floor_node.queue_free()
	await get_tree().process_frame
	if fresh:
		ranks=[0,0,0]
		health=8
		rewarded.clear()
		cleared.clear()
		builds.clear()
	depth=next_depth
	_build_floor()

func _input(event: InputEvent) -> void:
	var code := -1
	var down := false
	if event is InputEventKey:
		if event.echo:
			if phase==Phase.REWARD:
				get_viewport().set_input_as_handled()
			return
		code=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		down=event.pressed
	elif event is InputEventJoypadButton:
		if not is_instance_valid(floor_node) or event.device!=floor_node.input_source.device_id:
			return
		code=100000+event.button_index
		down=event.pressed
	elif event is InputEventJoypadMotion and phase==Phase.REWARD:
		if event.device!=floor_node.input_source.device_id or event.axis not in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
			return
		if absf(event.axis_value)<0.3:
			_axis_held[event.axis]=false
		elif absf(event.axis_value)>0.6 and not _axis_held.get(event.axis,false):
			_axis_held[event.axis]=true
			selected=posmod(selected+(1 if event.axis_value>0 else -1),3)
			_update_choices()
		get_viewport().set_input_as_handled()
		return
	else:
		return
	var was_down: bool=_pressed.get(code,false)
	_pressed[code]=down
	if not down or was_down:
		return
	if code==KEY_R:
		restart_run()
		get_viewport().set_input_as_handled()
		return
	var confirm: bool=code in [KEY_ENTER,KEY_KP_ENTER,100000+JOY_BUTTON_A]
	if phase==Phase.REWARD:
		if code in [KEY_UP,KEY_W,KEY_LEFT,KEY_A,100000+JOY_BUTTON_DPAD_UP,100000+JOY_BUTTON_DPAD_LEFT]:
			selected=posmod(selected-1,3)
		elif code in [KEY_DOWN,KEY_S,KEY_RIGHT,KEY_D,100000+JOY_BUTTON_DPAD_DOWN,100000+JOY_BUTTON_DPAD_RIGHT]:
			selected=posmod(selected+1,3)
		elif confirm:
			choose_upgrade(selected)
		_update_choices()
		get_viewport().set_input_as_handled()
	elif phase in [Phase.DEAD,Phase.VICTORY] and confirm and modal_age>=0.25:
		restart_run()
		get_viewport().set_input_as_handled()
	elif phase==Phase.PLAYING and (confirm or code==KEY_E) and try_exit():
		get_viewport().set_input_as_handled()
