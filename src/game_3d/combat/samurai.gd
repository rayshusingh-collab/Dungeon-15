extends "res://src/game_3d/player.gd"
const V = preload("res://src/game_3d/combat/combat_visuals.gd")
enum State { READY, WINDUP, STRIKE, RECOVERY, DODGE, HIT, DEAD }
const STATE_NAMES := ["READY","WINDUP","STRIKE","RECOVERY","DODGE","HIT","DEAD"]
var arena: Node3D
var state := State.READY
var state_time := 0.0
var health := 8
var max_health := 8
var chain := 0
var queued_second := false
var attacks_started := 0
var hits_landed := 0
var dodge_cooldown := 0.0
var hurt_grace := 0.0
var facing := Vector3.FORWARD
var dodge_direction := Vector3.FORWARD
var knockback := Vector3.ZERO
var _hit_ids: Dictionary = {}
var _armor: StandardMaterial3D
var _sword: Node3D
var _arc: MeshInstance3D
var _flash := 0.0

func _ready() -> void:
	collision_mask=1|4
	_armor=V.material(Color(0.12,0.16,0.22))
	$Visual/Capsule.material_override=_armor
	$Visual/FacingMarker.hide()
	V.box(visual,Vector3(0.75,0.2,0.5),Vector3(0,1.43,0),_armor)
	V.box(visual,Vector3(0.55,0.07,0.55),Vector3(0,1.58,0),V.material(Color(0.7,0.48,0.2)))
	_sword=Node3D.new()
	_sword.position.y=0.85
	visual.add_child(_sword)
	V.box(_sword,Vector3(0.07,0.09,1.65),Vector3(0.34,0,-1.05),V.material(Color(0.85,0.92,1)))
	V.box(_sword,Vector3(0.32,0.09,0.1),Vector3(0.34,0,-0.28),V.material(Color(0.75,0.55,0.2)))
	_arc=V.arc(visual,2.65,65,Color(0.85,0.95,1,0.28))
	_arc.hide()

func movement_direction() -> Vector3:
	var axis := _movement_input()
	var direction := Vector3(axis.x,0,axis.y)
	if is_instance_valid(movement_camera):
		var right := movement_camera.global_basis.x
		var forward := -movement_camera.global_basis.z
		right.y=0
		forward.y=0
		direction=right.normalized()*axis.x-forward.normalized()*axis.y
	return direction

func _physics_process(delta: float) -> void:
	var edges: Vector2i=movement_input.edges()
	var direction := movement_direction()
	state_time+=delta
	dodge_cooldown=maxf(0,dodge_cooldown-delta)
	hurt_grace=maxf(0,hurt_grace-delta)
	_flash=maxf(0,_flash-delta)
	if state==State.DEAD:
		velocity=Vector3.ZERO
		visual.rotation.z=lerp_angle(visual.rotation.z,-PI/2,minf(delta*10,1))
		return
	if edges.y and dodge_cooldown<=0 and state!=State.DODGE:
		dodge_direction=direction.normalized() if direction.length_squared()>0.0001 else facing
		facing=dodge_direction
		queued_second=false
		chain=0
		dodge_cooldown=0.6
		_set_state(State.DODGE)
	elif edges.x:
		if state==State.READY:
			_begin_attack(1,direction)
		elif chain==1 and state in [State.WINDUP,State.STRIKE,State.RECOVERY]:
			queued_second=true
	match state:
		State.WINDUP:
			if state_time>=(0.075 if chain==1 else 0.11):
				_set_state(State.STRIKE)
		State.STRIKE:
			_sword_hits()
			if state_time>=(0.12 if chain==1 else 0.14):
				_set_state(State.RECOVERY)
		State.RECOVERY:
			if state_time>=(0.18 if chain==1 else 0.25):
				if queued_second and chain==1:
					_begin_attack(2,direction)
				else:
					chain=0
					_set_state(State.READY)
		State.DODGE:
			if state_time>=0.28:
				_set_state(State.READY)
		State.HIT:
			if state_time>=0.19:
				_set_state(State.READY)
	var motion := direction*move_speed
	if state==State.DODGE:
		motion=dodge_direction*9.5
	elif state in [State.WINDUP,State.STRIKE]:
		motion*=0.65
	elif state==State.RECOVERY:
		motion*=0.8
	elif state==State.HIT:
		motion*=0.35
	if state==State.READY and direction.length_squared()>0.0001:
		facing=direction.normalized()
	visual.look_at(visual.global_position+facing,Vector3.UP)
	velocity.x=motion.x+knockback.x
	velocity.z=motion.z+knockback.z
	velocity.y=0 if is_on_floor() else velocity.y-gravity*delta
	knockback=knockback.move_toward(Vector3.ZERO,18*delta)
	move_and_slide()
	_arc.visible=state in [State.WINDUP,State.STRIKE]
	_sword.rotation.y=-0.9
	if state==State.STRIKE:
		_sword.rotation.y=lerpf(-1.15,1.15,clampf(state_time/0.12,0,1))*(-1 if chain==2 else 1)
	_armor.albedo_color=Color(1,0.3,0.25) if _flash>0 else (Color(0.4,0.65,0.85) if state==State.DODGE else Color(0.12,0.16,0.22))

func _set_state(next: State) -> void:
	state=next
	state_time=0

func _begin_attack(index: int,direction: Vector3) -> void:
	chain=index
	queued_second=false
	attacks_started+=1
	_hit_ids.clear()
	if direction.length_squared()>0.0001:
		facing=direction.normalized()
	_set_state(State.WINDUP)

func _sword_hits() -> void:
	for enemy in arena.enemies:
		if enemy.is_dead() or _hit_ids.has(enemy.get_instance_id()):
			continue
		var offset: Vector3=enemy.global_position-global_position
		offset.y=0
		if offset.length()>2.65 or (offset.length()>0.1 and facing.dot(offset.normalized())<cos(deg_to_rad(65))):
			continue
		if not arena.clear_attack_line(global_position,enemy.global_position):
			continue
		_hit_ids[enemy.get_instance_id()]=true
		enemy.receive_damage(2 if chain==1 else 3,facing*(4.0 if chain==1 else 6.0))
		hits_landed+=1
		arena.contact(enemy.global_position+Vector3.UP*0.8)

func invulnerable() -> bool:
	return state==State.DEAD or hurt_grace>0 or (state==State.DODGE and state_time<0.22)

func receive_damage(amount: int,impulse: Vector3) -> bool:
	if invulnerable() or arena.reached_exit:
		return false
	health=maxi(0,health-amount)
	queued_second=false
	chain=0
	knockback=impulse
	_flash=0.14
	hurt_grace=0.65
	_set_state(State.DEAD if health==0 else State.HIT)
	_arc.hide()
	return true

func reset_combat() -> void:
	health=max_health
	queued_second=false
	chain=0
	knockback=Vector3.ZERO
	_hit_ids.clear()
	velocity=Vector3.ZERO
	hurt_grace=0
	dodge_cooldown=0
	_flash=0
	visual.rotation=Vector3.ZERO
	facing=Vector3.FORWARD
	_arc.hide()
	_set_state(State.READY)
