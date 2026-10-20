extends "res://tools/test_harness.gd"
const Scene = preload("res://src/game_3d/the_descent.tscn")
const Run = preload("res://src/game_3d/descent/run_controller.gd")
const Grid = preload("res://src/game_3d/grid_space.gd")
var live: Node3D

func _suite_name() -> String:
	return "M3 THE DESCENT"

func _get_tests() -> Array[Callable]:
	return [_progression,_upgrades,_death_and_cleanup,_input]

func _after_each() -> void:
	if is_instance_valid(live):
		live.queue_free()
		await _ticks(2)

func _start(seed_value: int=12345) -> Node3D:
	live=Scene.instantiate()
	live.run_seed=seed_value
	root.add_child(live)
	return live

func _clear_required(run: Node3D) -> void:
	for enemy in run.floor_node.enemies:
		if enemy.room_id==run.floor_node.required_room:
			enemy.receive_damage(999,Vector3.ZERO)
	await _ticks(2)
	run.modal_age=1

func _progression() -> bool:
	_check(Run.seed_for(42,0)==-1 and Run.seed_for(42,4)==-1,"invalid depths rejected")
	for seed_value in [12345,42,7]:
		var run := _start(seed_value)
		var fingerprints: Array[String] = []
		for depth_value in range(1,4):
			await _ticks(2)
			var f: Node3D=run.floor_node
			_check(run.depth==depth_value and run.phase==Run.Phase.PLAYING,"seed %d depth %d playable" % [seed_value,depth_value])
			var result := DungeonGenerator.new().generate(DepthProfile.load_for_depth(depth_value),Run.seed_for(seed_value,depth_value),depth_value)
			_check(result.ok and result.layout.fingerprint()==f.layout.fingerprint(),"floor matches unchanged deterministic generator")
			fingerprints.append(f.layout.fingerprint())
			_check(not f.route.is_empty(),"supported entrance-exit route")
			_check(f.enemies.size()>=5 and f.enemies.size()<=10,"bounded preplaced composition")
			var safe := true
			for e in f.enemies:
				safe=safe and f.navigation.clear_spawn(Grid.tile_at(e.home)) and e.health==e.max_health
				var encounter: Dictionary=f.encounters.filter(func(item: Dictionary) -> bool: return item.room==e.room_id)[0]
				var access: Array[Vector2i]=f.navigation.path(Grid.center(encounter.entry),e.home)
				safe=safe and not access.is_empty() and access.all(func(tile: Vector2i) -> bool: return encounter.bounds.grow(1).has_point(tile))
			_check(safe,"all actors occupy dry clear patches at full scaled HP")
			f.player.position=Grid.center(f.layout.exit_tile,0.05)
			_check(not run.try_exit(),"sealed exit rejects interaction")
			await _clear_required(run)
			_check(run.phase==Run.Phase.REWARD and f.process_mode==Node.PROCESS_MODE_DISABLED,"objective pauses combat for reward")
			_check(not run.try_exit(),"reward must be selected before exit")
			_check(run.choose_upgrade(depth_value-1),"one reward accepted")
			_check(not run.choose_upgrade(depth_value-1),"duplicate reward rejected")
			f.player.position=Grid.center(f.layout.player_spawn,0.05)
			_check(not run.try_exit(),"remote transition rejected")
			f.player.position=Grid.center(f.layout.exit_tile,0.05)
			var old: WeakRef=weakref(f)
			_check(run.try_exit() and not run.try_exit(),"exactly one exit activation")
			if depth_value<3:
				await _ticks(4)
				_check(old.get_ref()==null,"previous floor and subscriptions freed")
				_check(run.ranks[0]==1 and run.health>0,"run stats carry to next floor")
		_check(run.phase==Run.Phase.VICTORY and run.depth==3 and run.rewarded.size()==3,"three-depth slice victory only")
		run.restart_run()
		await _ticks(4)
		_check(run.depth==1 and run.ranks==[0,0,0] and run.rewarded.is_empty() and run.health==8,"victory restart clears run")
		_check(run.floor_node.layout.fingerprint()==fingerprints[0],"same run seed reproduces depth one")
		await _after_each()
	return true

func _upgrades() -> bool:
	for upgrade in 3:
		var run := _start()
		for rank in 3:
			run.depth=rank+1
			run.phase=Run.Phase.REWARD
			run.modal_age=0
			_check(not run.choose_upgrade(upgrade),"opening-frame selection blocked")
			run.modal_age=1
			_check(run.choose_upgrade(upgrade),"rank %d upgrade %d accepted" % [rank+1,upgrade])
		var p: CharacterBody3D=run.floor_node.player
		_check(p.sword_bonus==(3 if upgrade==0 else 0),"blade capped at +3")
		_check(p.max_health==(14 if upgrade==1 else 8),"guard capped at 14 HP")
		_check(is_equal_approx(p.dodge_interval,0.36 if upgrade==2 else 0.6),"step capped at 0.36 seconds")
		_check(not run.choose_upgrade(-1) and not run.choose_upgrade(3),"invalid choices rejected")
		if upgrade==0:
			var enemy: CharacterBody3D=run.floor_node.enemies[0]
			p.position=enemy.position+Vector3(0,0,1.5)
			p.facing=Vector3.FORWARD
			p.chain=1
			p._hit_ids.clear()
			p._sword_hits()
			_check(enemy.is_dead(),"upgraded first cut deals five damage through real sword query")
		elif upgrade==1:
			p.receive_damage(3,Vector3.ZERO)
			_check(p.health==11,"guard adds usable health, not just HUD capacity")
		else:
			Input.action_press(run.floor_node.input_source.combat_actions[1])
			await _ticks(1)
			Input.action_release(run.floor_node.input_source.combat_actions[1])
			_check(p.dodge_cooldown<=0.36 and p.dodge_cooldown>0,"upgraded dodge uses shortened interval")
		await _after_each()
	return true

func _death_and_cleanup() -> bool:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var run := _start()
	await _ticks(2)
	var baseline := get_node_count()
	var actions := InputMap.get_actions().size()
	var connections := Input.joy_connection_changed.get_connections().size()
	for cycle in 5:
		var f: Node3D=run.floor_node
		f.fire_projectile(f.player.position+Vector3.UP,Vector3.RIGHT)
		var old: WeakRef=weakref(f)
		f.reset_to_entry()
		await _ticks(2)
		_check(run.phase==Run.Phase.DEAD and f.player.health==0,"fatal terrain waits for restart confirmation")
		run.restart_run()
		run.restart_run()
		await _ticks(4)
		_check(old.get_ref()==null and run.depth==1 and run.health==8,"death replaces whole floor once")
		_check(get_node_count()==baseline,"no node growth across run reset")
		_check(InputMap.get_actions().size()==actions and Input.joy_connection_changed.get_connections().size()==connections,"private bindings and event subscriptions bounded")
	await _after_each()
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_before,"whole-run teardown leaves no orphan nodes")
	return true

func _key(code: int, down: bool=true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.pressed=down
	root.push_input(event,true)

func _button(button: int, down: bool=true) -> void:
	var event := InputEventJoypadButton.new()
	event.device=42
	event.button_index=button
	event.pressed=down
	root.push_input(event,true)

func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device=42
	event.axis=axis
	event.axis_value=value
	root.push_input(event,true)

func _input() -> bool:
	var run := _start()
	run.floor_node.input_source.bind_device(42)
	await _clear_required(run)
	_key(KEY_DOWN)
	_key(KEY_DOWN,false)
	_check(run.selected==1,"keyboard navigates reward")
	var echo := InputEventKey.new()
	echo.physical_keycode=KEY_DOWN
	echo.pressed=true
	echo.echo=true
	root.push_input(echo,true)
	_check(run.selected==1,"keyboard echo cannot move reward focus")
	_button(JOY_BUTTON_DPAD_DOWN)
	_button(JOY_BUTTON_DPAD_DOWN,false)
	_check(run.selected==2,"controller D-pad navigates reward")
	_axis(JOY_AXIS_LEFT_Y,0.8)
	_check(run.selected==0,"left stick navigates reward")
	_axis(JOY_AXIS_LEFT_Y,0.9)
	_check(run.selected==0,"held stick cannot repeatedly advance choice")
	_axis(JOY_AXIS_LEFT_Y,0)
	_axis(JOY_AXIS_LEFT_X,-0.8)
	_axis(JOY_AXIS_LEFT_X,0)
	_check(run.selected==2,"horizontal stick also navigates reward")
	_button(JOY_BUTTON_A)
	_check(run.ranks==[0,0,1],"south button confirms reward")
	_check(run.phase==Run.Phase.PLAYING,"reward resumes combat")
	_button(JOY_BUTTON_A,false)
	run.floor_node.player.position=Grid.center(run.floor_node.layout.exit_tile,0.05)
	_key(KEY_E)
	_key(KEY_E,false)
	await _ticks(4)
	_check(run.depth==2,"keyboard explicit exit interaction transitions")
	_key(KEY_R)
	_key(KEY_R,false)
	await _ticks(4)
	_check(run.depth==1 and run.ranks==[0,0,0],"R restarts complete run")
	return true

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
