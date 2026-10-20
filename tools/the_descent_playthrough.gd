extends "res://tools/blood_and_steel_playthrough.gd"
## Reuses the accepted input bot. Warps between room entrances, never forces kills.
const RunScene = preload("res://src/game_3d/the_descent.tscn")
const Run = preload("res://src/game_3d/descent/run_controller.gd")

func _suite_name() -> String:
	return "M3 LIVE THREE-DEPTH COMBAT"

func _test_fights() -> bool:
	for seed_value in [12345,42,7]:
		var run := RunScene.instantiate()
		run.run_seed=seed_value
		root.add_child(run)
		for d in range(1,4):
			var scene: Node3D=run.floor_node
			scene.player.movement_camera=null # world-axis input driver; real UI tests cover camera mapping.
			var shots_max := 0
			for encounter: Dictionary in scene.encounters:
				scene.player.position=Grid.center(encounter.entry,0.05)
				scene.player.velocity=Vector3.ZERO
				var repath := 0
				var path: Array[Vector2i] = []
				var attack_release := 0
				var frames := 0
				while frames<5400 and not scene.room_cleared[encounter.room] and scene.player.state!=S.State.DEAD:
					frames+=1
					await physics_frame
					Input.action_release(scene.input_source.combat_actions[0])
					Input.action_release(scene.input_source.combat_actions[1])
					attack_release=maxi(0,attack_release-1)
					var target: CharacterBody3D=null
					for enemy in scene.enemies:
						if enemy.room_id!=encounter.room or enemy.is_dead():
							continue
						if target==null or (enemy.kind=="ranged" and target.kind!="ranged"):
							target=enemy
					if target==null:
						break
					var offset: Vector3=target.position-scene.player.position
					offset.y=0
					var distance := offset.length()
					var direction := Vector3.ZERO
					var roll := Vector3.ZERO
					for enemy in scene.enemies:
						if enemy.is_dead() or enemy.room_id!=encounter.room:
							continue
						var windup := 0.95 if enemy.kind=="brute" else 0.5
						if enemy.kind!="ranged" and enemy.state==E.State.WINDUP and windup-enemy.state_time<0.18 and enemy.position.distance_to(scene.player.position)<3.8:
							roll=_safe_roll(scene,(scene.player.position-enemy.position).normalized())
					for shot in scene.projectile_root.get_children():
						if shot.position.distance_to(scene.player.position+Vector3.UP*0.6)<2.4:
							roll=_safe_roll(scene,Vector3(-shot.direction.z,0,shot.direction.x))
					if roll.length()>0.1 and scene.player.dodge_cooldown<=0:
						direction=roll
						Input.action_press(scene.input_source.combat_actions[1])
					elif distance<=2.55 and scene.clear_attack_line(scene.player.position,target.position):
						direction=offset.normalized()*0.4
						if attack_release==0 and (scene.player.state==S.State.READY or (scene.player.chain==1 and not scene.player.queued_second and scene.player.state in [S.State.WINDUP,S.State.STRIKE,S.State.RECOVERY])):
							Input.action_press(scene.input_source.combat_actions[0])
							attack_release=6
					else:
						repath-=1
						if repath<=0:
							path=scene.navigation.path(scene.player.position,target.position)
							if path.size()>1 and path[0]==Grid.tile_at(scene.player.position):
								path.pop_front()
							repath=12
						while not path.is_empty() and Vector2(scene.player.position.x-Grid.center(path[0]).x,scene.player.position.z-Grid.center(path[0]).z).length()<0.2:
							path.pop_front()
						if not path.is_empty():
							direction=Grid.center(path[0])-scene.player.position
							direction.y=0
							direction=direction.normalized()
					_movement(direction)
					shots_max=maxi(shots_max,scene.projectile_root.get_child_count())
					if frames%900==0:
						print("LIVE_PROGRESS seed=",seed_value," room=",encounter.room," hp=",scene.player.health," player=",scene.player.position," target=",target.position," target_hp=",target.health)
				_movement(Vector3.ZERO)
				Input.action_release(scene.input_source.combat_actions[0])
				Input.action_release(scene.input_source.combat_actions[1])
				_check(scene.room_cleared[encounter.room],"seed %d patrol H%02d beaten through actual combat inputs" % [seed_value,encounter.room])
				print("LIVE_RESULT seed=",seed_value," room=",encounter.room," hp=",scene.player.health," frames=",frames," hits=",scene.player.hits_landed," resets=",scene.resets)
				if scene.player.state==S.State.DEAD or frames>=5400:
					break
			await process_frame
			_check(scene.player.health>0 and scene.enemies.all(func(e: CharacterBody3D) -> bool: return e.is_dead()),"all depth %d enemies defeated with carried health" % d)
			if run.phase!=Run.Phase.REWARD:
				_check(false,"required reward reached")
				break
			run.modal_age=1
			_check(run.choose_upgrade(d-1),"live objective awards one upgrade")
			scene.player.position=Grid.center(scene.layout.exit_tile,0.05)
			_check(run.try_exit(),"live combat unlocks descent")
			for wait_frame in 5:
				await process_frame
		_check(run.phase==Run.Phase.VICTORY,"seed %d completes three-depth combat run" % seed_value)
		run.queue_free()
		await process_frame
		await process_frame
	return true
