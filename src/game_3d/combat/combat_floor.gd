extends "res://src/game_3d/first_dungeon.gd"
## M2 composes combat onto M1; the accepted M1 scene and all source data stay untouched.
const Nav = preload("res://src/game_3d/combat/combat_navigation.gd")
const Demon = preload("res://src/game_3d/combat/demon.gd")
const Projectile = preload("res://src/game_3d/combat/demon_projectile.gd")
const V = preload("res://src/game_3d/combat/combat_visuals.gd")
var navigation: RefCounted
var encounters: Array[Dictionary] = []
var enemies: Array[CharacterBody3D] = []
var room_cleared: Dictionary = {}
var encounter_labels: Dictionary = {}
var projectile_root: Node3D
var required_room := -1
var combat_build_msec := 0.0
var banner := "Follow the halls. Read the telegraphs. Two sword cuts, then dodge."
var banner_time := 5.0
var _restart_pending := false
var _contact_fx: Node3D
var _contact_time := 0.0
var health_bar: ProgressBar
var damage_overlay: ColorRect
var exit_label: Label3D

func _ready() -> void:
	var start := Time.get_ticks_usec()
	super._ready()
	if layout==null:
		return
	player.free()
	player=preload("res://src/prototype_3d/player_3d.tscn").instantiate()
	player.set_script(preload("res://src/game_3d/combat/samurai.gd"))
	player.movement_input=input_source
	player.movement_camera=camera
	player.arena=self
	player.position=Grid.center(layout.player_spawn,0.05)
	add_child(player)
	camera.target=player
	navigation=Nav.new(layout)
	encounters=navigation.plan_encounters()
	if encounters.size()!=3:
		push_error("M2 rejected seed %d: fewer than three suitable safe patrol rooms" % run_seed)
		status.text="M2 CANNOT POPULATE SEED %d SAFELY\nStop this scene and choose another seed. No unsafe spawns were substituted." % run_seed
		player.set_physics_process(false)
		set_physics_process(false)
		return
	required_room=encounters[-1].room
	projectile_root=Node3D.new()
	projectile_root.name="Projectiles"
	add_child(projectile_root)
	for encounter in encounters:
		room_cleared[encounter.room]=false
		for i in encounter.kinds.size():
			var enemy := Demon.new()
			enemy.arena=self
			enemy.kind=encounter.kinds[i]
			enemy.room_id=encounter.room
			enemy.home_area=encounter.bounds
			enemy.home=Grid.center(encounter.tiles[i],0.05)
			enemy.position=enemy.home
			add_child(enemy)
			enemies.append(enemy)
		var label := Label3D.new()
		label.position=Grid.center(encounter.entry,2.8)
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size=40
		label.pixel_size=0.015
		add_child(label)
		encounter_labels[encounter.room]=label
	for child in get_children():
		if child is Label3D and child.text=="EXIT":
			exit_label=child
	_contact_fx=Node3D.new()
	var white := V.material(Color(1,0.9,0.5))
	white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	V.box(_contact_fx,Vector3(0.7,0.06,0.06),Vector3.ZERO,white)
	V.box(_contact_fx,Vector3(0.06,0.7,0.06),Vector3.ZERO,white)
	add_child(_contact_fx)
	_contact_fx.hide()
	health_bar=ProgressBar.new()
	status.position=Vector2(18,42)
	health_bar.position=Vector2(18,18)
	health_bar.size=Vector2(240,16)
	health_bar.max_value=player.max_health
	health_bar.show_percentage=false
	var fill := StyleBoxFlat.new()
	fill.bg_color=Color(0.8,0.12,0.08)
	health_bar.add_theme_stylebox_override("fill",fill)
	var background := StyleBoxFlat.new()
	background.bg_color=Color(0.08,0.035,0.03)
	health_bar.add_theme_stylebox_override("background",background)
	status.get_parent().add_child(health_bar)
	damage_overlay=ColorRect.new()
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	damage_overlay.color=Color(0.8,0.05,0.03,0)
	status.get_parent().add_child(damage_overlay)
	combat_build_msec=(Time.get_ticks_usec()-start)/1000.0
	_update_patrol_labels()
	print("M2 seed=%d build_ms=%.2f rooms=%s enemies=%d fingerprint=%s" % [run_seed,combat_build_msec,str(encounters.map(func(item: Dictionary) -> int: return item.room)),enemies.size(),layout.fingerprint()])

func clear_attack_line(from: Vector3,to: Vector3) -> bool:
	# Cast below the one-metre wall tops; no pixel navigation receives world metres.
	var a := Vector3(from.x,0.65,from.z)
	var b := Vector3(to.x,0.65,to.z)
	var ray := PhysicsRayQueryParameters3D.create(a,b,1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func fire_projectile(at: Vector3,direction: Vector3) -> void:
	if projectile_root.get_child_count()>=12:
		return
	var shot := Projectile.new()
	shot.arena=self
	shot.direction=direction
	shot.position=at
	projectile_root.add_child(shot)

func contact(at: Vector3) -> void:
	_contact_fx.global_position=at
	_contact_time=0.12
	_contact_fx.show()

func enemy_down(_enemy: CharacterBody3D) -> void:
	for encounter in encounters:
		var alive := 0
		for enemy in enemies:
			alive+=int(enemy.room_id==encounter.room and not enemy.is_dead())
		if alive==0 and not room_cleared[encounter.room]:
			room_cleared[encounter.room]=true
			banner="HALL %02d CLEARED%s" % [encounter.room," - EXIT OPEN" if encounter.required else " - OPTIONAL PATROL DEFEATED"]
			banner_time=4
	_update_patrol_labels()

func _update_patrol_labels() -> void:
	for encounter in encounters:
		var label: Label3D=encounter_labels[encounter.room]
		var count := 0
		for enemy in enemies:
			count+=int(enemy.room_id==encounter.room and not enemy.is_dead())
		label.text="HALL %02d / %s\n%s" % [encounter.room,"REQUIRED PATROL" if encounter.required else "OPTIONAL PATROL","CLEARED" if count==0 else "%d DEMON%s" % [count,"S" if count!=1 else ""]]
		label.modulate=Color(0.4,1,0.6) if count==0 else Color(1,0.6,0.25)
	if is_instance_valid(exit_label):
		var open: bool=room_cleared.get(required_room,false)
		exit_label.text="EXIT / OPEN" if open else "EXIT / SEALED"
		exit_label.modulate=Color(0.4,1,0.5) if open else Color(1,0.55,0.15)

func reset_to_entry() -> void:
	if _restart_pending or player==null or not is_instance_valid(projectile_root):
		return
	super.reset_to_entry()
	_restart_pending=true
	_restore.call_deferred()

func _restore() -> void:
	for shot in projectile_root.get_children():
		shot.queue_free()
	for enemy in enemies:
		enemy.reset_enemy()
	for id in room_cleared:
		room_cleared[id]=false
	player.reset_combat()
	reached_exit=false
	elapsed=0
	banner="Steel drawn. All three patrols restored."
	banner_time=3
	_contact_time=0
	_contact_fx.hide()
	_update_patrol_labels()
	_restart_pending=false

func _physics_process(delta: float) -> void:
	if navigation==null or encounters.is_empty():
		return
	if player.state!=player.State.DEAD:
		super._physics_process(delta)
	if not room_cleared.get(required_room,false):
		reached_exit=false
	banner_time=maxf(0,banner_time-delta)
	_contact_time=maxf(0,_contact_time-delta)
	_contact_fx.visible=_contact_time>0
	_contact_fx.scale=Vector3.ONE*(1+(0.12-_contact_time)*4)
	health_bar.value=player.health
	damage_overlay.color.a=0.13 if player._flash>0 else 0
	var patrol_text := ""
	for encounter in encounters:
		var count := 0
		for enemy in enemies:
			count+=int(enemy.room_id==encounter.room and not enemy.is_dead())
		patrol_text+="H%02d:%s%s  " % [encounter.room,"CLEAR" if count==0 else str(count),"*" if encounter.required else ""]
	status.text="BLOOD AND STEEL / Depth 1 of 15 / Seed %d\nHP %d/%d | %s | Dodge %s\nWASD / arrows / stick / D-pad | Space/J/south: sword | Shift/K/east: dodge\nR: restart floor | H: diagnostics | Patrols %s\n%s\n%s" % [run_seed,player.health,player.max_health,player.STATE_NAMES[player.state],"READY" if player.dodge_cooldown<=0 else "RECOVERING",patrol_text,"EXIT OPEN" if room_cleared.get(required_room,false) else "* DEFEAT THE PATROL IN HALL %02d TO OPEN THE EXIT" % required_room,banner if banner_time>0 else "Read amber telegraphs; dodge the strike, punish recovery."]
	if survey_visible:
		status.text+="\nPad %s | %s | deadzone %.2f | device %d\n%s" % [str(input_source.stick_vector()),input_source.last_button_event,input_source.deadzone,input_source.device_id,input_source.last_event]
	if player.state==player.State.DEAD:
		status.text+="\nYOU DIED - R TO DRAW STEEL AGAIN"
	elif reached_exit:
		status.text+="\nDEPTH 1 CLEARED - R TO FIGHT AGAIN"
