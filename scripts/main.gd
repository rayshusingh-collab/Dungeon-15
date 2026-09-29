extends Node2D

const ROOM_SIZE := Vector2(1152, 648)
const WALL := 32.0

var player: CharacterBody2D
var joystick_center := Vector2(120, 520)
var joystick_radius := 72.0
var joystick_dir := Vector2.ZERO
var dragging := false
var enemies: Array[CharacterBody2D] = []
var door_open := false
var rng := RandomNumberGenerator.new()
var run_seed: int

func _ready():
    run_seed = int(Time.get_unix_time_from_system())
    rng.seed = run_seed
    build_room()
    spawn_player()
    spawn_enemies(4)
    queue_redraw()

func build_room():
    add_wall(Vector2(ROOM_SIZE.x / 2, WALL / 2), Vector2(ROOM_SIZE.x, WALL))
    add_wall(Vector2(ROOM_SIZE.x / 2, ROOM_SIZE.y - WALL / 2), Vector2(ROOM_SIZE.x, WALL))
    add_wall(Vector2(WALL / 2, ROOM_SIZE.y / 2), Vector2(WALL, ROOM_SIZE.y))
    # right wall split to leave a door gap
    add_wall(Vector2(ROOM_SIZE.x - WALL / 2, 145), Vector2(WALL, 290))
    add_wall(Vector2(ROOM_SIZE.x - WALL / 2, 503), Vector2(WALL, 290))

func add_wall(pos: Vector2, size: Vector2):
    var body := StaticBody2D.new()
    body.position = pos
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    body.add_child(shape)
    add_child(body)

func spawn_player():
    player = CharacterBody2D.new()
    player.position = ROOM_SIZE / 2
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 18
    shape.shape = circle
    player.add_child(shape)
    add_child(player)

func spawn_enemies(count: int):
    for i in count:
        var enemy := CharacterBody2D.new()
        enemy.position = Vector2(rng.randf_range(250, 900), rng.randf_range(100, 550))
        var shape := CollisionShape2D.new()
        var circle := CircleShape2D.new()
        circle.radius = 16
        shape.shape = circle
        enemy.add_child(shape)
        enemy.set_meta("hp", 2)
        enemies.append(enemy)
        add_child(enemy)

func _physics_process(delta):
    if player == null:
        return
    var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var dir := joystick_dir if joystick_dir.length() > 0.05 else keyboard
    player.velocity = dir * 230.0
    player.move_and_slide()

    for enemy in enemies.duplicate():
        if not is_instance_valid(enemy):
            enemies.erase(enemy)
            continue
        var to_player := player.position - enemy.position
        if to_player.length() < 300 and to_player.length() > 45:
            enemy.velocity = to_player.normalized() * 75.0
            enemy.move_and_slide()
        else:
            enemy.velocity = Vector2.ZERO

    if enemies.is_empty():
        door_open = true
    queue_redraw()

func _unhandled_input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        dragging = event.pressed and event.position.distance_to(joystick_center) < 110
        if not event.pressed:
            joystick_dir = Vector2.ZERO
        update_joystick(event.position)
    elif event is InputEventMouseMotion and dragging:
        update_joystick(event.position)
    elif event is InputEventScreenTouch:
        if event.pressed and event.position.distance_to(joystick_center) < 110:
            dragging = true
            update_joystick(event.position)
        elif not event.pressed:
            dragging = false
            joystick_dir = Vector2.ZERO
    elif event is InputEventScreenDrag and dragging:
        update_joystick(event.position)

    if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
        attack()

func update_joystick(pos: Vector2):
    if not dragging:
        return
    var offset := pos - joystick_center
    if offset.length() > joystick_radius:
        offset = offset.normalized() * joystick_radius
    joystick_dir = offset / joystick_radius

func attack():
    if player == null:
        return
    for enemy in enemies.duplicate():
        if is_instance_valid(enemy) and enemy.position.distance_to(player.position) <= 85:
            var hp: int = int(enemy.get_meta("hp")) - 1
            enemy.set_meta("hp", hp)
            if hp <= 0:
                enemies.erase(enemy)
                enemy.queue_free()

func _draw():
    # floor
    draw_rect(Rect2(Vector2.ZERO, ROOM_SIZE), Color("171820"))
    # walls
    var wall_color := Color("5a5368")
    draw_rect(Rect2(0, 0, ROOM_SIZE.x, WALL), wall_color)
    draw_rect(Rect2(0, ROOM_SIZE.y-WALL, ROOM_SIZE.x, WALL), wall_color)
    draw_rect(Rect2(0, 0, WALL, ROOM_SIZE.y), wall_color)
    draw_rect(Rect2(ROOM_SIZE.x-WALL, 0, WALL, 290), wall_color)
    draw_rect(Rect2(ROOM_SIZE.x-WALL, 358, WALL, 290), wall_color)

    # exit door indicator
    draw_rect(Rect2(ROOM_SIZE.x-WALL, 290, WALL, 68), Color("45d483") if door_open else Color("b33b4b"))

    # player
    if player:
        draw_circle(player.position, 18, Color("63b3ff"))
        draw_circle(player.position, 8, Color("d9efff"))

    # enemies
    for enemy in enemies:
        if is_instance_valid(enemy):
            draw_circle(enemy.position, 16, Color("e05252"))
            draw_circle(enemy.position, 6, Color("521919"))

    # joystick
    draw_circle(joystick_center, joystick_radius, Color(0.35, 0.35, 0.4, 0.35))
    draw_circle(joystick_center + joystick_dir * joystick_radius, 30, Color(0.8, 0.8, 0.9, 0.75))

    # attack button
    draw_circle(Vector2(1030, 520), 55, Color(0.7, 0.2, 0.2, 0.65))
