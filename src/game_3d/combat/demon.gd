extends CharacterBody3D
const Grid = preload("res://src/game_3d/grid_space.gd")
const V = preload("res://src/game_3d/combat/combat_visuals.gd")
enum State { IDLE, CHASE, WINDUP, ACTIVE, RECOVERY, HIT, DEAD }
const NAMES := ["WATCH","HUNT","WINDUP","ATTACK","RECOVERY","STAGGER","FALLEN"]
var arena: Node3D
var kind := "basic"
var room_id := -1
var home := Vector3.ZERO
var home_area := Rect2i()
var state := State.IDLE
var state_time := 0.0
var health := 4
var max_health := 4
var facing := Vector3.FORWARD
var impulse := Vector3.ZERO
var awake := false
var _fired := false
var _cooldown := 0.0
var _repath := 0.0
var _path: Array[Vector2i] = []
var _index := 0
var _flash := 0.0
var _visual: Node3D
var _skin: StandardMaterial3D
var _base_color: Color
var _telegraph: MeshInstance3D
var _label: Label3D
var shots_fired := 0

func _ready() -> void:
	collision_layer=4
	collision_mask=1|2|4
	max_health=12 if kind=="brute" else 4
	health=max_health
	var scale_factor := 1.35 if kind=="brute" else 1.0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.48*scale_factor
	capsule.height=1.5*scale_factor
	shape.shape=capsule
	shape.position.y=capsule.height/2
	add_child(shape)
	_visual=Node3D.new()
	add_child(_visual)
	_base_color={"basic":Color(0.55,0.13,0.12),"brute":Color(0.42,0.28,0.18),"ranged":Color(0.45,0.18,0.62)}[kind]
	_skin=V.material(_base_color)
	var mesh := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius=capsule.radius
	body.height=capsule.height
	body.radial_segments=12
	body.rings=4
	mesh.mesh=body
	mesh.material_override=_skin
	mesh.position.y=shape.position.y
	_visual.add_child(mesh)
	for x in [-0.3,0.3]:
		var horn := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius=0
		cone.bottom_radius=0.13
		cone.height=0.45
		cone.radial_segments=5
		horn.mesh=cone
		horn.position=Vector3(x*scale_factor,capsule.height+0.12,0)
		horn.material_override=V.material(Color(0.8,0.7,0.53))
		_visual.add_child(horn)
	V.box(_visual,Vector3(0.55,0.09,0.09),Vector3(0,capsule.height*0.8,-capsule.radius),V.material(Color(1,0.65,0.12)))
	if kind=="ranged":
		_telegraph=V.box(_visual,Vector3(0.1,0.025,8),Vector3(0,0.055,-4),V.material(Color(1,0.3,0.1)))
	else:
		_telegraph=V.arc(_visual,3.2 if kind=="brute" else 2.6,70 if kind=="brute" else 60,Color(1,0.48,0.08,0.5))
	_telegraph.hide()
	_label=Label3D.new()
	_label.position.y=capsule.height+0.6
	_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size=40
	_label.pixel_size=0.012
	add_child(_label)

func _physics_process(delta: float) -> void:
	state_time+=delta
	_flash=maxf(0,_flash-delta)
	_cooldown=maxf(0,_cooldown-delta)
	_repath-=delta
	if global_position.y<-3 and not is_dead():
		receive_damage(max_health,Vector3.ZERO)
	if is_dead():
		_visual.rotation.z=lerp_angle(_visual.rotation.z,PI/2,minf(delta*8,1))
		if state_time>0.45:
			hide()
		return
	if arena.player.state==arena.player.State.DEAD or arena.reached_exit:
		_telegraph.hide()
		velocity=Vector3.ZERO
		return
	var target: Vector3=arena.player.global_position
	var in_area := home_area.grow(1).has_point(Grid.tile_at(target))
	if in_area and global_position.distance_to(target)<22:
		awake=true
	var direction := Vector3.ZERO
	var distance := global_position.distance_to(target)
	if not awake or not in_area:
		if global_position.distance_to(home)>0.2:
			direction=_navigate(home)
		if state!=State.IDLE:
			_set_state(State.IDLE)
	else:
		match state:
			State.IDLE:
				_set_state(State.CHASE)
			State.CHASE:
				if kind=="ranged":
					if distance<4.5:
						direction=_navigate(_retreat_target(target))
					elif distance>8 or not arena.clear_attack_line(global_position,target):
						direction=_navigate(target)
					if distance>=4.5 and distance<=11 and _cooldown<=0 and arena.clear_attack_line(global_position,target):
						_start_attack(target)
				else:
					if distance<(2.8 if kind=="brute" else 2.2) and _cooldown<=0 and arena.clear_attack_line(global_position,target):
						_start_attack(target)
					else:
						direction=_navigate(target)
			State.WINDUP:
				if state_time>=(0.95 if kind=="brute" else (0.65 if kind=="ranged" else 0.5)):
					_set_state(State.ACTIVE)
			State.ACTIVE:
				if not _fired:
					_fired=true
					if kind=="ranged":
						if arena.clear_attack_line(global_position,global_position+facing*0.8):
							arena.fire_projectile(global_position+Vector3.UP*0.65+facing*0.7,facing)
							shots_fired+=1
					else:
						var delta_target := target-global_position
						delta_target.y=0
						var edge := cos(deg_to_rad(70.0 if kind=="brute" else 60.0))
						if delta_target.length()<(3.2 if kind=="brute" else 2.6) and facing.dot(delta_target.normalized())>=edge and arena.clear_attack_line(global_position,target):
							arena.player.receive_damage(3 if kind=="brute" else 1,facing*(7 if kind=="brute" else 4))
				if state_time>=0.13:
					_set_state(State.RECOVERY)
			State.RECOVERY:
				if state_time>=(0.9 if kind=="brute" else 0.55):
					_cooldown=0.4
					_set_state(State.CHASE)
			State.HIT:
				if state_time>=0.24:
					_set_state(State.CHASE)
	var speed := 1.8 if kind=="brute" else (2.5 if kind=="ranged" else 3.2)
	var motion := direction*speed+impulse
	impulse=impulse.move_toward(Vector3.ZERO,18*delta)
	var next := global_position+motion*delta
	if not home_area.grow(1).has_point(Grid.tile_at(next)) or not arena.navigation.safe_step(global_position,next,0.5 if kind=="brute" else 0.43):
		motion=Vector3.ZERO
	velocity.x=motion.x
	velocity.z=motion.z
	velocity.y=0 if is_on_floor() else velocity.y-20*delta
	move_and_slide()
	if direction.length_squared()>0.01 and state not in [State.WINDUP,State.ACTIVE]:
		facing=direction.normalized()
	_visual.look_at(_visual.global_position+facing,Vector3.UP)
	_telegraph.visible=state in [State.WINDUP,State.ACTIVE]
	_skin.albedo_color=Color.WHITE if _flash>0 else (Color(0.95,0.48,0.12) if state==State.WINDUP else _base_color)
	_label.text="%s %d/%d\n%s" % [kind.to_upper(),health,max_health,NAMES[state]]

func _navigate(target: Vector3) -> Vector3:
	if _repath<=0:
		_path=arena.navigation.path(global_position,target)
		_index=1 if _path.size()>1 else 0
		_repath=0.3
	while _index<_path.size():
		var goal := Grid.center(_path[_index])
		var offset := goal-global_position
		offset.y=0
		if offset.length()>0.15:
			var dir := offset.normalized()
			if not arena.navigation.safe_step(global_position,global_position+dir*0.15):
				var align := Grid.center(Grid.tile_at(global_position))-global_position
				align.y=0
				return align.normalized() if align.length()>0.1 else Vector3.ZERO
			return dir
		_index+=1
	return Vector3.ZERO

func _retreat_target(target: Vector3) -> Vector3:
	var best := global_position
	var score := global_position.distance_to(target)
	for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var tile := Grid.tile_at(global_position)+step*2
		var point := Grid.center(tile)
		if home_area.has_point(tile) and arena.navigation.clear_spawn(tile) and point.distance_to(target)>score and not arena.navigation.path(global_position,point).is_empty():
			best=point
			score=point.distance_to(target)
	return best

func _start_attack(target: Vector3) -> void:
	facing=(target-global_position)
	facing.y=0
	facing=facing.normalized()
	_fired=false
	_set_state(State.WINDUP)

func _set_state(next: State) -> void:
	state=next
	state_time=0

func receive_damage(amount: int,push: Vector3) -> void:
	if is_dead():
		return
	health=maxi(0,health-amount)
	_flash=0.1
	awake=true
	impulse=push*(0.35 if kind=="brute" else 1.0)
	if health==0:
		_set_state(State.DEAD)
		_telegraph.hide()
		_label.text="FALLEN"
		set_deferred("collision_layer",0)
		set_deferred("collision_mask",0)
		arena.enemy_down(self)
	elif kind!="brute" or state not in [State.WINDUP,State.ACTIVE]:
		_set_state(State.HIT)

func is_dead() -> bool:
	return state==State.DEAD

func reset_enemy() -> void:
	show()
	collision_layer=4
	collision_mask=1|2|4
	global_position=home
	velocity=Vector3.ZERO
	impulse=Vector3.ZERO
	health=max_health
	awake=false
	_fired=false
	facing=Vector3.FORWARD
	_flash=0
	_repath=0
	_cooldown=0
	_path.clear()
	_visual.rotation=Vector3.ZERO
	_telegraph.hide()
	_set_state(State.IDLE)
