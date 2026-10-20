extends "res://tools/test_harness.gd"
const Scene = preload("res://src/game_3d/blood_and_steel.tscn")
const Nav = preload("res://src/game_3d/combat/combat_navigation.gd")
const Fixture = preload("res://src/game_3d/hazard_fixture_data.gd")
const Grid = preload("res://src/game_3d/grid_space.gd")
const S = preload("res://src/game_3d/combat/samurai.gd")
const E = preload("res://src/game_3d/combat/demon.gd")
var live: Node3D

func _suite_name() -> String:
	return "M2 BLOOD AND STEEL"

func _get_tests() -> Array[Callable]:
	return [_test_plans,_test_sword_and_dodge,_test_enemy_telegraphs,_test_navigation_and_occlusion,_test_projectiles,_test_death_reset_and_exit,_test_controller,_test_m1_terrain_in_combat]

func _after_each() -> void:
	if is_instance_valid(live):
		for action in live.input_source.combat_actions:
			Input.action_release(action)
		for action in ["move_left","move_right","move_up","move_down"]:
			Input.action_release(action)
		live.queue_free()
		await process_frame
		await process_frame

func _floor(seed_value: int=12345) -> Node3D:
	var scene := Scene.instantiate()
	scene.run_seed=seed_value
	root.add_child(scene)
	live=scene
	return scene

func _fixture() -> Node3D:
	var scene := _floor()
	scene.set_physics_process(false)
	scene.geometry.free()
	scene.rects.clear()
	scene.layout=Fixture.create()
	scene._build_geometry()
	scene.navigation=Nav.new(scene.layout)
	for enemy in scene.enemies:
		enemy.set_physics_process(false)
		enemy.collision_layer=0
		enemy.collision_mask=0
		enemy.hide()
		enemy.home_area=Rect2i(Vector2i.ZERO,scene.layout.size)
	scene.player.movement_camera=null
	scene.player.position=Grid.center(Vector2i(3,5),0.05)
	scene.player.facing=Vector3.RIGHT
	return scene

func _place(enemy: CharacterBody3D,tile: Vector2i,active: bool=false) -> void:
	enemy.home=Grid.center(tile,0.05)
	enemy.reset_enemy()
	enemy.set_physics_process(active)

func _edge(scene: Node3D,index: int) -> void:
	Input.action_press(scene.input_source.combat_actions[index])
	await _frames(2)
	Input.action_release(scene.input_source.combat_actions[index])
	await _frames(2)

func _test_plans() -> bool:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for seed_value in [12345,42,7]:
		var scene := _floor(seed_value)
		await _frames(3)
		var before: String=scene.layout.fingerprint()
		_check(before=={12345:"2994f8107a89ee44",42:"31476b85897e6431",7:"21ae2fd9691ea505"}[seed_value],"seed %d retains M1 layout fingerprint" % seed_value)
		_check(scene.encounters.size()==3 and scene.enemies.size()==5,"three bounded pre-placed patrols, five enemies")
		_check(str(scene.encounters)==str(Nav.new(scene.layout).plan_encounters()),"encounter placement deterministic")
		var safe := true
		for enemy in scene.enemies:
			var tile := Grid.tile_at(enemy.home)
			safe=safe and scene.navigation.clear_spawn(tile) and scene.layout.get_owner_of(tile)==enemy.room_id
			for door in scene.layout.rooms[enemy.room_id].doors:
				safe=safe and Vector2(tile).distance_to(Vector2(door.inside))>=3
		_check(safe,"spawns clear of terrain, solids, entrance approaches and door lanes")
		_check(scene.encounters[0].kinds==["basic"] and scene.encounters[1].kinds==["basic","ranged"] and scene.encounters[2].kinds==["brute","ranged"],"small escalating patrols expose all three demon types")
		_check(not scene.encounters[0].required and not scene.encounters[1].required and scene.encounters[2].required,"two optional patrols and one required; no locked-room geometry")
		_check(scene.layout.fingerprint()==before,"combat planning leaves source data untouched")
		var count := get_node_count()
		await _frames(120)
		_check(get_node_count()==count,"idle floor does not spawn new enemies or FX")
		print("M2_SAMPLE seed=",seed_value," build_ms=",scene.combat_build_msec," nodes=",count," plan=",str(scene.encounters))
		await _after_each()
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_before,"multiple seed scene teardown adds no orphan nodes")
	var all_valid := true
	for seed_value in range(20):
		var result := DungeonGenerator.new().generate(DepthProfile.load_for_depth(1),seed_value,1)
		var nav := Nav.new(result.layout)
		all_valid=all_valid and result.ok and nav.plan_encounters().size()==3
	_check(all_valid,"20 additional deterministic layouts provide three suitable patrol rooms")
	return true

func _test_sword_and_dodge() -> bool:
	var scene := _fixture()
	var player: CharacterBody3D=scene.player
	var enemy: CharacterBody3D=scene.enemies[0]
	_place(enemy,Vector2i(4,5))
	await _frames(3)
	Input.action_press(scene.input_source.combat_actions[0])
	await _frames(50)
	_check(player.attacks_started==1 and player.state==S.State.READY,"held attack produces exactly one cut then returns ready")
	_check(enemy.health==2 and player.hits_landed==1,"one active swing hits each target once")
	Input.action_release(scene.input_source.combat_actions[0])
	await _frames(3)
	enemy.reset_enemy()
	player.reset_combat()
	player.position=Grid.center(Vector2i(3,5),0.05)
	player.facing=Vector3.RIGHT
	var start_count: int=player.attacks_started
	await _edge(scene,0)
	await _edge(scene,0)
	var second: bool=await _wait_until(func() -> bool: return player.chain==2,45)
	_check(second,"second deliberate press queues the second cut")
	await _edge(scene,0)
	await _frames(45)
	_check(player.attacks_started==start_count+2,"chain is capped at two despite a third press")
	_check(enemy.is_dead() and player.state==S.State.READY,"two cuts defeat a basic demon and recover without lockup")
	player.reset_combat()
	await _edge(scene,1)
	_check(player.state==S.State.DODGE and player.invulnerable(),"dodge enters brief invulnerability")
	_check(not player.receive_damage(3,Vector3.LEFT*5) and player.health==8,"damage ignored in dodge invulnerability")
	await _frames(20)
	_check(player.state==S.State.READY and not player.invulnerable(),"dodge invulnerability expires")
	var start: Vector3=player.position
	_check(player.receive_damage(1,Vector3.RIGHT*5),"vulnerable player takes damage")
	await _frames(4)
	_check(player.health==7 and player.state==S.State.HIT and player.position.x>start.x,"hit state, damage and physical knockback")
	_check(not player.receive_damage(1,Vector3.ZERO),"hurt grace prevents same-frame damage stacking")
	await _frames(45)
	_check(player.state==S.State.READY,"hit recovery returns to controllable state")
	await _edge(scene,0)
	await _edge(scene,1)
	_check(player.state==S.State.DODGE and player.chain==0,"dodge cancels attack cleanly without stale combo")
	return true

func _test_enemy_telegraphs() -> bool:
	var scene := _fixture()
	var player: CharacterBody3D=scene.player
	player.set_physics_process(false)
	var basic: CharacterBody3D=scene.enemies[0]
	_place(basic,Vector2i(4,5),true)
	await _frames(20)
	_check(basic.state==E.State.WINDUP and player.health==8 and basic._telegraph.visible,"basic visibly anticipates before damaging")
	basic.receive_damage(1,Vector3.RIGHT*3)
	_check(basic.state==E.State.HIT,"basic windup can be stagger-interrupted")
	await _frames(12)
	_check(player.health==8,"interrupted strike causes no delayed ghost damage")
	await _frames(90)
	_check(player.health<8,"basic resumes and executes real melee damage")
	basic.set_physics_process(false)
	basic.collision_layer=0
	basic.collision_mask=0
	basic.hide()
	player.reset_combat()
	player.position=Grid.center(Vector2i(3,5),0.05)
	var brute: CharacterBody3D=scene.enemies[3]
	_place(brute,Vector2i(4,5),true)
	await _frames(40)
	_check(brute.state==E.State.WINDUP and player.health==8,"brute has a slower readable windup")
	brute.receive_damage(2,Vector3.RIGHT*3)
	_check(brute.state==E.State.WINDUP and brute.health==10,"brute's committed strike resists light stagger")
	await _frames(25)
	var recovered: bool=await _wait_until(func() -> bool: return brute.state==E.State.RECOVERY,15)
	_check(player.health==5 and recovered,"brute deals powerful damage then exposes long recovery")
	player.reset_combat()
	player.position=Grid.center(Vector2i(3,5),0.05)
	player.facing=Vector3.LEFT
	brute._start_attack(player.position)
	await _frames(47)
	player.set_physics_process(true)
	await _edge(scene,1)
	await _frames(16)
	_check(player.health==8,"timed dodge avoids the brute strike")
	# Move across the telegraph boundary after aim locks: visible angle must match damage.
	brute.set_physics_process(false)
	brute.collision_layer=0
	brute.collision_mask=0
	player.set_physics_process(false)
	player.reset_combat()
	_place(basic,Vector2i(5,5),true)
	player.position=basic.position+Vector3(sin(deg_to_rad(63)),0,-cos(deg_to_rad(63)))*2
	basic._start_attack(basic.position+Vector3.FORWARD*2)
	await _frames(45)
	_check(player.health==8,"basic strike cannot hit outside its visible 60-degree telegraph")
	basic.set_physics_process(false)
	basic.collision_layer=0
	basic.collision_mask=0
	player.reset_combat()
	_place(brute,Vector2i(4,5),true)
	player.position=brute.position+Vector3(sin(deg_to_rad(68)),0,-cos(deg_to_rad(68)))*2.4
	brute._start_attack(brute.position+Vector3.FORWARD*2)
	await _frames(70)
	_check(player.health==5,"brute strike covers the inside edge of its visible 70-degree telegraph")
	return true

func _test_navigation_and_occlusion() -> bool:
	var scene := _fixture()
	var player: CharacterBody3D=scene.player
	var enemy: CharacterBody3D=scene.enemies[0]
	# A deliberately thin test wall keeps the target in sword range: LOS must reject it.
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(0.18,1,2)
	collider.shape=shape
	collider.position.y=0.5
	wall.position=Vector3(9,0,11)
	wall.add_child(collider)
	scene.add_child(wall)
	player.position=Vector3(8,0.05,11)
	player.facing=Vector3.RIGHT
	_place(enemy,Vector2i(5,5))
	enemy.global_position=Vector3(10,0.05,11)
	await _frames(3)
	_check(not scene.clear_attack_line(player.position,enemy.position),"solid test wall occludes sword targets inside attack range")
	await _edge(scene,0)
	await _frames(30)
	_check(enemy.health==4,"sword cannot damage through solid wall")
	player.set_physics_process(false)
	enemy.set_physics_process(true)
	enemy._start_attack(player.position)
	await _frames(45)
	_check(player.health==8,"telegraphed demon melee also respects solid wall occlusion")
	wall.queue_free()
	await _frames(2)
	player.set_physics_process(false)
	player.position=Grid.center(Vector2i(3,3),0.05)
	_place(enemy,Vector2i(3,1),true)
	var path: Array[Vector2i]=scene.navigation.path(enemy.position,player.position)
	var valid := path.size()>3
	for tile in path:
		valid=valid and scene.navigation.safe_tile(tile)
	_check(valid and not path.has(Vector2i(3,2)),"navigation routes around source obstacle instead of through it")
	await _frames(220)
	_check(enemy.global_position.distance_to(player.position)<3,"demon physically follows obstacle detour into melee range")
	player.reset_combat()
	player.position=Grid.center(Vector2i(13,2),0.05)
	_place(enemy,Vector2i(6,2),true)
	var unsafe := false
	for i in 420:
		await physics_frame
		unsafe=unsafe or not scene.navigation.safe_tile(Grid.tile_at(enemy.position))
	_check(not unsafe and enemy.position.y>-0.1,"AI never crosses inaccessible pit, water or spike terrain")
	_check(enemy.global_position.distance_to(player.position)<3,"AI reaches target by going around pit opening")
	_check(scene.navigation.path(Grid.center(Vector2i(7,2)),player.position).is_empty(),"pit starting tiles are rejected by navigation")
	enemy.position.y=-3.1
	await _frames(2)
	_check(enemy.is_dead(),"externally displaced falling enemy is cleaned up instead of falling forever")
	return true

func _test_projectiles() -> bool:
	var scene := _fixture()
	var player: CharacterBody3D=scene.player
	player.set_physics_process(false)
	var ranged: CharacterBody3D=scene.enemies[2]
	_place(ranged,Vector2i(6,5),true)
	await _frames(30)
	_check(ranged.state==E.State.WINDUP and ranged._telegraph.visible,"ranged demon visibly aims before firing")
	await _frames(20)
	_check(ranged.shots_fired>0 and scene.projectile_root.get_child_count()>0,"ranged fires visible moving projectiles")
	await _frames(55)
	_check(player.health<8,"projectile physically hits and damages player")
	ranged._set_state(E.State.CHASE)
	ranged._cooldown=5
	player.position=ranged.position+Vector3.LEFT*2
	var before: float=ranged.position.distance_to(player.position)
	await _frames(50)
	_check(ranged.position.distance_to(player.position)>before+0.5,"ranged attempts to maintain distance")
	ranged.set_physics_process(false)
	for shot in scene.projectile_root.get_children():
		shot.queue_free()
	await _frames(2)
	player.reset_combat()
	player.position=Grid.center(Vector2i(3,3),0.05)
	scene.fire_projectile(Grid.center(Vector2i(3,1),0.65),Vector3.BACK)
	await _frames(40)
	_check(player.health==8 and scene.projectile_root.get_child_count()==0,"source solid obstacle absorbs projectile; no damage through wall")
	for i in 100:
		scene.fire_projectile(Grid.center(Vector2i(10,5),0.65),Vector3.RIGHT)
	_check(scene.projectile_root.get_child_count()==12,"projectile count is bounded even under excessive fire requests")
	await _frames(160)
	_check(scene.projectile_root.get_child_count()==0,"projectile lifetime/wall cleanup leaves no accumulated nodes")
	return true

func _test_death_reset_and_exit() -> bool:
	var scene := _floor()
	await _frames(3)
	var player: CharacterBody3D=scene.player
	player.position=Grid.center(scene.layout.exit_tile,0.05)
	await _frames(3)
	_check(not scene.reached_exit,"uncleared required patrol seals exit progress without locking rooms")
	for enemy in scene.enemies:
		if enemy.room_id==scene.required_room:
			enemy.receive_damage(99,Vector3.ZERO)
	await _frames(3)
	_check(scene.reached_exit and scene.status.text.contains("DEPTH 1 CLEARED"),"required patrol defeat opens exit and completes only depth 1")
	_check(not scene.room_cleared[scene.encounters[0].room],"optional patrol need not be cleared to complete floor")
	scene.reset_to_entry()
	await _frames(4)
	_check(player.health==8 and not scene.reached_exit and scene.enemies.all(func(e: CharacterBody3D) -> bool: return not e.is_dead()),"reset restores health, patrols and exit seal")
	player.receive_damage(99,Vector3.ZERO)
	await _frames(3)
	_check(player.state==S.State.DEAD and scene.status.text.contains("YOU DIED"),"death is stable and has explicit restart feedback")
	Input.action_press(scene.input_source.combat_actions[0])
	await _frames(3)
	var attacks: int=player.attacks_started
	var key := InputEventKey.new()
	key.physical_keycode=KEY_R
	key.pressed=true
	scene._unhandled_key_input(key)
	await _frames(5)
	_check(player.state==S.State.READY and player.health==8 and Grid.tile_at(player.position)==scene.layout.player_spawn,"R restarts from death with usable movement state")
	_check(player.attacks_started==attacks,"held attack does not auto-trigger across death/reset")
	Input.action_release(scene.input_source.combat_actions[0])
	await _frames(3)
	var count := get_node_count()
	for i in 10:
		scene.reset_to_entry()
		await _frames(3)
	_check(get_node_count()==count,"ten encounter resets reuse enemies/FX without node growth")
	_check(scene.enemies.size()==5 and scene.projectile_root.get_child_count()==0,"restart leaves bounded enemy count and no projectiles")
	return true

func _test_controller() -> bool:
	var before := InputMap.get_actions()
	var shared := str(InputMap.action_get_events("attack"),InputMap.action_get_events("dodge"),InputMap.action_get_events("move_left"))
	var scene := _floor()
	var source: Node=scene.input_source
	await _frames(3)
	source.bind_device(42)
	for pair in [[JOY_BUTTON_A,0,S.State.WINDUP],[JOY_BUTTON_B,1,S.State.DODGE]]:
		scene.player.reset_combat()
		var event := InputEventJoypadButton.new()
		event.device=42
		event.button_index=pair[0]
		event.pressed=true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(3)
		_check(scene.player.state==pair[2],"synthetic GP325 logical face button %d triggers combat state" % pair[0])
		event=event.duplicate()
		event.pressed=false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(3)
	for code: int in [KEY_SPACE,KEY_J,KEY_SHIFT,KEY_K]:
		scene.player.reset_combat()
		var key := InputEventKey.new()
		key.physical_keycode=code
		key.pressed=true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		await _frames(2)
		_check(scene.player.state==(S.State.WINDUP if code in [KEY_SPACE,KEY_J] else S.State.DODGE),"physical keyboard combat key %d mapped privately" % code)
		key=key.duplicate()
		key.pressed=false
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		await _frames(2)
	_check(shared==str(InputMap.action_get_events("attack"),InputMap.action_get_events("dodge"),InputMap.action_get_events("move_left")),"M2 preserves all shared combat/movement bindings")
	scene.player.reset_combat()
	var short_key := InputEventKey.new()
	short_key.physical_keycode=KEY_SPACE
	short_key.pressed=true
	Input.parse_input_event(short_key)
	Input.flush_buffered_events()
	short_key=short_key.duplicate()
	short_key.pressed=false
	Input.parse_input_event(short_key)
	Input.flush_buffered_events()
	await _frames(2)
	_check(scene.player.state==S.State.WINDUP,"sub-physics-frame tap is buffered once instead of lost")
	await _frames(35)
	scene.player.reset_combat()
	short_key=short_key.duplicate()
	short_key.pressed=true
	Input.parse_input_event(short_key)
	Input.flush_buffered_events()
	await _frames(2)
	var attack_count: int=scene.player.attacks_started
	short_key=short_key.duplicate()
	short_key.echo=true
	Input.parse_input_event(short_key)
	Input.flush_buffered_events()
	await _frames(35)
	_check(scene.player.attacks_started==attack_count,"keyboard autorepeat cannot queue or repeat a sword chain")
	short_key=short_key.duplicate()
	short_key.pressed=false
	short_key.echo=false
	Input.parse_input_event(short_key)
	Input.flush_buffered_events()
	await _after_each()
	_check(InputMap.get_actions()==before,"M2 private combat and movement actions removed on scene exit")
	return true

func _test_m1_terrain_in_combat() -> bool:
	var scene := _fixture()
	scene.set_physics_process(true)
	var player: CharacterBody3D=scene.player
	player.position=Grid.center(Vector2i(6,5),0.05)
	await _frames(5)
	Input.action_press("move_right")
	await _frames(192)
	Input.action_release("move_right")
	var bridge_supported: bool= player.is_on_floor() and Grid.tile_at(player.position)==Vector2i(14,5) and scene.resets==0
	player.position=Grid.center(Vector2i(8,11),0.05)
	await _frames(5)
	_check(bridge_supported and player.move_speed==2.5 and player.is_on_floor(),"M2 physically crosses the M1 bridge and retains supported half-speed water")
	player.health=3
	player.position=Grid.center(Vector2i(9,2),0.05)
	player.velocity=Vector3.ZERO
	await _frames(65)
	_check(scene.resets==1 and player.health==8 and Grid.tile_at(player.position)==scene.layout.player_spawn,"M2 pit still falls/reset to entry and restores encounter run")
	scene.elapsed=0
	player.position=Grid.center(Vector2i(16,5),0.05)
	await _frames(5)
	_check(scene.resets==1 and Grid.tile_at(player.position)==Vector2i(16,5),"M2 safe spike window retains physical traversal")
	player._set_state(S.State.DODGE)
	scene.elapsed=scene.safe_seconds+0.7
	await _frames(3)
	_check(scene.resets==2 and Grid.tile_at(player.position)==scene.layout.player_spawn,"M1 raised-spike reset is not bypassed by demon-hit invulnerability")
	_check(player.state==S.State.READY and scene.projectile_root.get_child_count()==0 and scene.enemies.all(func(enemy: CharacterBody3D) -> bool: return not enemy.is_dead()),"hazard restart leaves responsive combat state and clean bounded encounters")
	return true
