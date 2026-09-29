class_name Enemy
extends CharacterBody2D
## Melee chaser with a small explicit state machine:
##   IDLE   -> player comes within aggro_range              -> CHASE
##   CHASE  -> within attack_range and attack ready         -> ATTACK
##   ATTACK -> windup (coils back, telegraph) -> strike (lunges) -> recovery
##             (dimmed, vulnerable)                          -> CHASE
##   any    -> takes a hit (short stagger, interrupts attack) -> HURT -> CHASE
##   CHASE  -> player dead, or player > leash_range from home -> RETURN
##   RETURN -> reaches home -> IDLE (re-aggros if the player comes back)
## Once engaged it keeps chasing across the room; there is no invisible
## "stop at 300 px" boundary. DEAD slides with the killing blow, plays a death
## effect, then frees itself.

signal died(enemy: Enemy)
signal state_changed(new_state: State)

enum State { IDLE, CHASE, ATTACK, HURT, RETURN, DEAD }

@export_group("Movement")
@export var move_speed: float = 95.0
@export var aggro_range: float = 260.0
## Distance (centre to centre) at which the enemy starts its attack windup.
@export var attack_range: float = 60.0
## Gives up when the player is this far from the enemy's home position.
@export var leash_range: float = 700.0
@export_group("Attack motion")
## Slow backward drift while winding up (coiling before the strike).
@export var windup_pullback_speed: float = 22.0
## Forward burst on the strike frame.
@export var strike_lunge_speed: float = 300.0
@export var strike_lunge_decay: float = 4000.0
@export_group("Hit reaction")
@export var hurt_stun_time: float = 0.25
## After a stagger the next attack comes this long after being hit (replaces
## the remaining attack cooldown, so the enemy neither freezes nor insta-swings).
@export var post_hurt_attack_delay: float = 0.6
@export var knockback_strength: float = 380.0
@export var knockback_decay: float = 2200.0
## Knockback applied by the killing blow (the body slides while fading).
@export var death_knockback_strength: float = 480.0
@export var death_color: Color = Color(0.88, 0.32, 0.32)

## Set by whoever spawns the enemy. With no target it just idles.
var target: Player
var home_position: Vector2
var state: State = State.IDLE
var facing: Vector2 = Vector2.LEFT

var _stun_left: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _lunge: Vector2 = Vector2.ZERO
var _visual_tween: Tween

@onready var health: HealthComponent = $HealthComponent
@onready var melee: MeleeAttack = $MeleeAttack
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _visual: Node2D = $Visual
@onready var _facing_marker: Node2D = $FacingMarker
@onready var _alert_label: Label = $AlertLabel


func _ready() -> void:
	home_position = global_position
	health.died.connect(_on_died)
	_hurtbox.hit_received.connect(_on_hit_received)
	melee.windup_started.connect(_on_windup_started)
	melee.strike_started.connect(_on_strike_started)
	melee.recovery_started.connect(_on_recovery_started)
	melee.finished.connect(_on_attack_finished)
	_facing_marker.rotation = facing.angle()


func _physics_process(delta: float) -> void:
	var desired := Vector2.ZERO
	match state:
		State.IDLE:
			if _can_engage():
				_set_state(State.CHASE)
		State.CHASE:
			desired = _chase()
		State.ATTACK:
			if melee.phase == MeleeAttack.Phase.WINDUP:
				desired = -facing * windup_pullback_speed
		State.HURT:
			_stun_left -= delta
			if _stun_left <= 0.0:
				_set_state(State.CHASE if _target_alive() else State.RETURN)
		State.RETURN:
			desired = _return_home(delta)
	velocity = desired + _knockback + _lunge
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	_lunge = _lunge.move_toward(Vector2.ZERO, strike_lunge_decay * delta)
	if state == State.DEAD and velocity == Vector2.ZERO:
		return
	move_and_slide()


func _chase() -> Vector2:
	if not _target_alive() or target.global_position.distance_to(home_position) > leash_range:
		_set_state(State.RETURN)
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	_face(to_target)
	if to_target.length() <= attack_range:
		# In range: attack if ready, otherwise hold position facing the player.
		if melee.start(facing):
			_set_state(State.ATTACK)
		return Vector2.ZERO
	return to_target.normalized() * move_speed


func _return_home(delta: float) -> Vector2:
	if _can_engage():
		_set_state(State.CHASE)
		return Vector2.ZERO
	var to_home := home_position - global_position
	if to_home.length() <= 4.0:
		_set_state(State.IDLE)
		return Vector2.ZERO
	_face(to_home)
	return to_home.normalized() * minf(move_speed, to_home.length() / delta)


func _can_engage() -> bool:
	return _target_alive() \
		and global_position.distance_to(target.global_position) <= aggro_range \
		and target.global_position.distance_to(home_position) <= leash_range


func _target_alive() -> bool:
	return is_instance_valid(target) and not target.is_dead()


func _face(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		facing = direction.normalized()
		_facing_marker.rotation = facing.angle()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old_state := state
	state = new_state
	if new_state == State.CHASE and (old_state == State.IDLE or old_state == State.RETURN):
		_show_alert()
	state_changed.emit(new_state)


func _on_windup_started(duration: float) -> void:
	# Coil: swell and heat up toward the strike.
	_animate_visual(Color(1.9, 1.3, 0.5), Vector2(1.15, 1.15), duration)


func _on_strike_started() -> void:
	_lunge = facing * strike_lunge_speed
	_visual.modulate = Color(2.5, 2.2, 1.8)
	_visual.scale = Vector2(0.88, 0.88)
	_animate_visual(Color.WHITE, Vector2.ONE, 0.08)


func _on_recovery_started(duration: float) -> void:
	# Spent: dim while recovering, which is the player's opening.
	_animate_visual(Color(0.6, 0.6, 0.72), Vector2.ONE, minf(0.1, duration))


func _on_attack_finished() -> void:
	_animate_visual(Color.WHITE, Vector2.ONE, 0.1)
	if state == State.ATTACK:
		_set_state(State.CHASE)


func _on_hit_received(hitbox: Hitbox) -> void:
	var direction := hitbox.get_knockback_direction(global_position)
	var contact := global_position - direction * 14.0
	if state == State.DEAD:
		# Killing blow: bigger spray, and the body slides with the hit.
		_knockback = direction * death_knockback_strength
		BurstEffect.spawn_spray(get_parent(), contact, direction, Color(1, 1, 1, 0.95), 7, 1.6, 54.0, 0.24)
		return
	BurstEffect.spawn_spray(get_parent(), contact, direction, Color(1, 1, 1, 0.95), 5, 1.3, 38.0, 0.16)
	BurstEffect.spawn(get_parent(), contact, BurstEffect.Style.RING, Color(1, 1, 1, 0.8), 4.0, 20.0, 0.12)
	_knockback = direction * knockback_strength
	_lunge = Vector2.ZERO
	melee.cancel()
	melee.set_cooldown_remaining(post_hurt_attack_delay)
	_visual.modulate = Color(4, 4, 4)
	_visual.scale = Vector2(0.7, 1.22) if absf(direction.x) >= absf(direction.y) else Vector2(1.22, 0.7)
	_animate_visual(Color.WHITE, Vector2.ONE, 0.18)
	_stun_left = hurt_stun_time
	_set_state(State.HURT)


func _on_died() -> void:
	_set_state(State.DEAD)
	melee.cancel()
	remove_from_group(&"enemies")
	_lunge = Vector2.ZERO
	# Keep sliding against walls only; stop blocking the player and enemies.
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 1)
	_hurtbox.set_deferred(&"monitorable", false)
	_alert_label.hide()
	_facing_marker.hide()
	died.emit(self)
	BurstEffect.spawn(get_parent(), global_position, BurstEffect.Style.RING,
			death_color, 12.0, 56.0, 0.4)
	if _visual_tween != null:
		_visual_tween.kill()
	_visual.modulate = Color(4, 4, 4)
	_visual.scale = Vector2.ONE
	var tween := create_tween().set_parallel()
	tween.tween_property(_visual, ^"scale", Vector2(1.5, 1.5), 0.35)
	tween.tween_property(_visual, ^"modulate", Color(1, 1, 1, 0), 0.35).set_delay(0.05)
	tween.chain().tween_callback(queue_free)


func _show_alert() -> void:
	_alert_label.show()
	_alert_label.scale = Vector2(0.4, 0.4)
	var tween := _alert_label.create_tween()
	tween.tween_property(_alert_label, ^"scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_callback(_alert_label.hide)


func _animate_visual(color: Color, scale_to: Vector2, duration: float) -> void:
	if _visual_tween != null:
		_visual_tween.kill()
	_visual_tween = create_tween().set_parallel()
	_visual_tween.tween_property(_visual, ^"modulate", color, duration)
	_visual_tween.tween_property(_visual, ^"scale", scale_to, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
