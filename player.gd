extends CharacterBody2D

var speed = 200.0

@onready var mobile_controls = get_node("../MobileControls")

func _physics_process(_delta):
	var direction = mobile_controls.joystick_direction

	velocity = direction * speed
	move_and_slide()
