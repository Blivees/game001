extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_force: float = -550.0
@export var gravity: float = 1800.0

func _physics_process(delta: float) -> void:
	# 左右移动
	var input_dir: float = Input.get_axis("move_left", "move_right")
	velocity.x = input_dir * speed

	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		# 在地上才能跳
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_force

	move_and_slide()
