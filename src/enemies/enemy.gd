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
## Group pressure (M2.2 play-test polish):
##   - Contact: while chasing or attacking (not staggered, not recovering) its
##     body hurts (ContactDamage). Dimmed/staggered enemies are safe to touch.
##   - Stagger guard: a hit interrupts it once; for stagger_guard_time after
##     that (or until its next attack finishes) hits still damage it but it
##     fights through them, so swinging non-stop is no longer a stun-lock.
##     `windup_armor` (brute) also ignores interrupts during its windup/strike.
##   - Crowd steering: near the target, enemies keep apart and work around an
##     enemy that already holds their side, so groups surround instead of
##     queueing in front of the player's swing.

signal died(enemy: Enemy)
signal state_changed(new_state: State)

enum State { IDLE, CHASE, ATTACK, HURT, RETURN, DEAD }

## Seconds between path re-plans while the target is out of sight.
const REPATH_INTERVAL := 0.3
const WAYPOINT_REACHED := 10.0
## Spark shown when a hit lands but does not interrupt (stagger guard / armor).
const GUARD_SPARK_COLOR := Color(1.0, 0.78, 0.3, 0.95)

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
@export var post_hurt_attack_delay: float = 0.35
@export var knockback_strength: float = 380.0
@export var knockback_decay: float = 2200.0
## Knockback applied by the killing blow (the body slides while fading).
@export var death_knockback_strength: float = 480.0
## After a stagger, further hits don't interrupt for this long (or until the
## enemy's next attack finishes, whichever comes first).
@export var stagger_guard_time: float = 1.5
## Knockback multiplier for hits it fights through.
@export var guarded_knockback_scale: float = 0.15
## Hits never interrupt its windup or strike (heavy attackers).
@export var windup_armor: bool = false
@export_group("Body pressure")
## Push back after its body hit the player, so it doesn't stay glued on.
@export var contact_recoil: float = 140.0
@export_group("Crowd")
## Enemies closer than this push apart.
@export var separation_radius: float = 52.0
@export var separation_weight: float = 0.9
## Within this distance of the target it works around enemies already holding its side.
@export var flank_range: float = 200.0
@export var flank_weight: float = 1.0
## Another enemy within this angle (seen from the target) and closer holds "my side".
@export var flank_angle_degrees: float = 70.0
## While another enemy holds its side it circles no closer than this (just
## outside the player's swing), and closes in once it has its own angle.
@export var flank_hold_distance: float = 115.0
## A circling enemy commits anyway once it is this far (degrees) off the
## direction the player faces: outside the swing, it goes for the opening.
@export var flank_opening_degrees: float = 65.0
## While waiting in range for its next attack it keeps pressing its body in
## (contact pressure) at this weight, plus crowd spreading.
@export var press_in_weight: float = 0.6
## Speed share used while waiting in range for the next attack.
@export var hold_spread_ratio: float = 0.55
@export var death_color: Color = Color(0.88, 0.32, 0.32)

## Living enemies, for crowd steering without per-frame allocation.
static var _active: Array[Enemy] = []

## Set by whoever spawns the enemy. With no target it just idles.
var target: Player
var home_position: Vector2
var state: State = State.IDLE
var facing: Vector2 = Vector2.LEFT

## Optional grid pathfinding (set by the room that spawns the enemy). Without
## it the enemy steers straight at its target (open arenas, tests).
var navigator: DungeonNavigation

var _stun_left: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _lunge: Vector2 = Vector2.ZERO
var _visual_tween: Tween
var _path: PackedVector2Array = PackedVector2Array()
var _repath_left: float = 0.0
var _stagger_guard_left: float = 0.0
var _side_taken: bool = false
## Tie-break side when flanking an enemy exactly in line (set by the spawner).
var flank_sign: float = 1.0

@onready var health: HealthComponent = $HealthComponent
@onready var melee: MeleeAttack = $MeleeAttack
@onready var terrain: TerrainState = $TerrainState
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _visual: Node2D = $Visual
@onready var _facing_marker: Node2D = $FacingMarker
@onready var _alert_label: Label = $AlertLabel
@onready var _contact: ContactDamage = $ContactDamage


func _ready() -> void:
	home_position = global_position
	health.died.connect(_on_died)
	_hurtbox.hit_received.connect(_on_hit_received)
	melee.windup_started.connect(_on_windup_started)
	melee.strike_started.connect(_on_strike_started)
	melee.recovery_started.connect(_on_recovery_started)
	melee.finished.connect(_on_attack_finished)
	_contact.hit_landed.connect(_on_contact_landed)
	_facing_marker.rotation = facing.angle()
	_active.append(self)


func _exit_tree() -> void:
	_active.erase(self)


## Its body hurts on contact right now (readable: bright and active).
func is_body_dangerous() -> bool:
	return state == State.CHASE or (state == State.ATTACK and melee.phase != MeleeAttack.Phase.RECOVERY)


func is_stagger_guarded() -> bool:
	return _stagger_guard_left > 0.0


## Starts chasing the target immediately (ambush spawns). Pass INF as the leash
## for enemies that must never give up (locked encounters).
func engage(leash: float = leash_range) -> void:
	leash_range = leash
	if state == State.IDLE or state == State.RETURN:
		_set_state(State.CHASE)


func _physics_process(delta: float) -> void:
	_stagger_guard_left = maxf(_stagger_guard_left - delta, 0.0)
	var dangerous := is_body_dangerous()
	if _contact.armed != dangerous:
		_contact.armed = dangerous
	var desired := Vector2.ZERO
	match state:
		State.IDLE:
			if _can_engage():
				_set_state(State.CHASE)
		State.CHASE:
			desired = _chase(delta)
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


func _chase(delta: float) -> Vector2:
	if not _target_alive() or target.global_position.distance_to(home_position) > leash_range:
		_set_state(State.RETURN)
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var visible := navigator == null or navigator.line_of_sight(global_position, target.global_position)
	if visible:
		_face(to_target)
	var speed := move_speed * terrain.speed_scale()
	var distance := to_target.length()
	if distance <= attack_range and visible:
		# In range with a clear line: attack if ready. Otherwise keep the body
		# pressure on (press in, spread out) while the next attack comes up.
		if melee.start(facing):
			_set_state(State.ATTACK)
			return Vector2.ZERO
		var press := to_target / distance * press_in_weight if distance > 0.001 else Vector2.ZERO
		return (press + crowd_steer(to_target)) * speed * hold_spread_ratio
	var velocity_to := _steer_toward(target.global_position, speed, delta)
	if not visible:
		_face(velocity_to)
		return velocity_to
	var crowd := crowd_steer(to_target)
	if _side_taken and distance <= flank_range and not _behind_target_guard():
		# Another enemy holds this side: circle at the edge of the target's reach
		# (never closer) until this enemy has its own angle, then close in.
		var hold := -to_target / distance * clampf((flank_hold_distance - distance) / 40.0, 0.0, 1.0) \
				if distance > 0.001 else Vector2.ZERO
		var orbit := crowd + hold
		return orbit.normalized() * speed if orbit != Vector2.ZERO else velocity_to
	var steered := velocity_to.normalized() + crowd
	return steered.normalized() * speed if steered != Vector2.ZERO else velocity_to


## True when this enemy is outside the target's swing arc (the player faces
## another way): a flanker that sees this commits instead of circling.
func _behind_target_guard() -> bool:
	var from_target := global_position - target.global_position
	if from_target == Vector2.ZERO:
		return true
	return target.facing.dot(from_target.normalized()) < cos(deg_to_rad(flank_opening_degrees))


## Steering offset that keeps enemies apart and, near the target, sends an
## enemy around another one that already holds its side (sets `_side_taken`),
## so groups surround the player instead of stacking in front of one swing.
## Loops over the living-enemy registry; no allocation.
func crowd_steer(to_target: Vector2) -> Vector2:
	var push := Vector2.ZERO
	_side_taken = false
	var from_target := -to_target
	var my_distance := to_target.length()
	var flanking := my_distance <= flank_range and my_distance > 0.001
	var cos_limit := cos(deg_to_rad(flank_angle_degrees))
	for other in _active:
		if other == self or other.state == State.DEAD:
			continue
		var offset := global_position - other.global_position
		var d := offset.length()
		if d < separation_radius and d > 0.001:
			push += offset / d * (1.0 - d / separation_radius) * separation_weight
		if not flanking:
			continue
		var other_from := other.global_position - target.global_position
		var other_distance := other_from.length()
		if other_distance > 0.001 and other_distance < my_distance + 8.0 \
				and from_target.dot(other_from) > cos_limit * my_distance * other_distance:
			# Rotate away from it around the target (tie: this enemy's flank side).
			var side := signf(from_target.cross(other_from))
			if side == 0.0:
				side = flank_sign
			push += from_target.orthogonal() / my_distance * side * flank_weight
			_side_taken = true
	return push


func _return_home(delta: float) -> Vector2:
	if _can_engage():
		_set_state(State.CHASE)
		return Vector2.ZERO
	var to_home := home_position - global_position
	if to_home.length() <= 4.0:
		_set_state(State.IDLE)
		return Vector2.ZERO
	var move := _steer_toward(home_position, minf(move_speed * terrain.speed_scale(), to_home.length() / delta), delta)
	_face(move)
	return move


## Velocity toward `point`: straight when the way is clear (or without a
## navigator), otherwise along a grid path around walls, pits and pillars.
func _steer_toward(point: Vector2, speed: float, delta: float) -> Vector2:
	if navigator == null or navigator.line_of_sight(global_position, point):
		_path = PackedVector2Array()
		return (point - global_position).normalized() * speed
	_repath_left -= delta
	if _path.is_empty() or _repath_left <= 0.0:
		_path = navigator.path(global_position, point)
		_repath_left = REPATH_INTERVAL
	# Drop reached waypoints and shortcut to later ones in plain view.
	while _path.size() > 1 and (global_position.distance_to(_path[0]) < WAYPOINT_REACHED
			or navigator.line_of_sight(global_position, _path[1])):
		_path.remove_at(0)
	if _path.is_empty():
		return (point - global_position).normalized() * speed
	return (_path[0] - global_position).normalized() * speed


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
	# One interrupt per attack cycle: after a full attack it can be staggered again.
	_stagger_guard_left = 0.0
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
	var armored := windup_armor and (melee.phase == MeleeAttack.Phase.WINDUP or melee.phase == MeleeAttack.Phase.ACTIVE)
	if _stagger_guard_left > 0.0 or armored:
		# Fights through it: takes the damage and a short shove, keeps its attack.
		# A gold spark (instead of the white stagger ring) says "not interrupted".
		_knockback = direction * knockback_strength * hitbox.knockback_scale * guarded_knockback_scale
		BurstEffect.spawn(get_parent(), contact, BurstEffect.Style.RING, GUARD_SPARK_COLOR, 6.0, 26.0, 0.16)
		if not melee.is_busy():
			_visual.modulate = Color(2.2, 1.9, 1.2)
			_animate_visual(Color.WHITE, Vector2.ONE, 0.14)
		return
	BurstEffect.spawn(get_parent(), contact, BurstEffect.Style.RING, Color(1, 1, 1, 0.8), 4.0, 20.0, 0.12)
	_stagger_guard_left = stagger_guard_time
	_knockback = direction * knockback_strength * hitbox.knockback_scale
	_lunge = Vector2.ZERO
	melee.cancel()
	melee.set_cooldown_remaining(post_hurt_attack_delay)
	_visual.modulate = Color(4, 4, 4)
	_visual.scale = Vector2(0.7, 1.22) if absf(direction.x) >= absf(direction.y) else Vector2(1.22, 0.7)
	_animate_visual(Color.WHITE, Vector2.ONE, 0.18)
	_stun_left = hurt_stun_time
	_set_state(State.HURT)


## Its body just hit the player: bounce off so it doesn't stay glued on.
func _on_contact_landed(hurtbox: Hurtbox) -> void:
	var away := global_position - hurtbox.global_position
	if away != Vector2.ZERO:
		_knockback = away.normalized() * contact_recoil


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
