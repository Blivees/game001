extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_force: float = -800.0
@export var gravity: float = 1800.0

func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 左右移动（A / D）
	velocity.x = Input.get_axis("move_left", "move_right") * speed

	# 跳跃（空格，需站在地面）
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	move_and_slide()
