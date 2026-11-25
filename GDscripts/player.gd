extends CharacterBody2D

const ANIM_IDLE = "idle"
const ANIM_WALK = "walk"
const ANIM_RUN = "run"
const ANIM_CROUCH_WALK = "crouch_walk"
const ANIM_JUMP = "jump"
const ANIM_FALL = "fall"
const ANIM_CLIMB = "climb"

@export var walk_speed: float = 300.0
@export var run_speed: float = 600.0
@export var crouch_speed_scale: float = 0.5
@export var ladder_horizontal_scale: float = 0.5

@export var jump_force: float = -800.0
@export var crouch_jump_scale: float = 0.5
@export var gravity: float = 1800.0

@export var accel: float = 2500.0
@export var decel: float = 3500.0

@export var coyote_time: float = 0.08
@export var jump_buffer: float = 0.06
@export var land_lock_time: float = 0.03
@export var crouch_freeze_frame: int = 1

@export var crouch_shape: RectangleShape2D
var _stand_shape: Shape2D
var _stand_pos: Vector2
var _crouch_shape: Shape2D
var _crouch_pos: Vector2

enum State {IDLE, WALK, RUN, CROUCH_WALK, JUMP, FALL, CLIMB}

var current_state: State = State.IDLE
var is_crouch: bool = false
var is_on_ladder: bool = false
var last_dir: int = 1

var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0
var land_lock_timer: float = 0.0
var jump_anim_finished: bool = false
var fall_anim_finished: bool = false
var climb_moving: bool = false
var _crouch_prev: bool = false
var _jump_was_run: bool = false

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var ladder_detector: Area2D = $LadderDetector

var _ladder_bodies: int = 0

func _ready() -> void:
	_stand_shape = collision_shape.shape
	_stand_pos = collision_shape.position
	_build_crouch_shape()
	ladder_detector.body_entered.connect(_on_ladder_body_entered)
	ladder_detector.body_exited.connect(_on_ladder_body_exited)

# 从站立形状自动派生上半砍掉、底部贴地的矮矩形；外部拖入 crouch_shape 时优先用外部资源
func _build_crouch_shape() -> void:
	var r := _stand_shape.get_rect()
	var h := r.size.y * 0.5
	var rect := RectangleShape2D.new()
	rect.size = Vector2(r.size.x, h)
	_crouch_shape = rect
	var bottom := r.position.y + r.size.y
	_crouch_pos = Vector2(_stand_pos.x, bottom - h * 0.5)

func _physics_process(delta: float) -> void:
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	if coyote_timer > 0:
		coyote_timer -= delta
	if land_lock_timer > 0:
		land_lock_timer -= delta

	var input_x: float = Input.get_axis("move_left", "move_right")
	var input_y: float = Input.get_axis("move_up", "move_down")
	var run_press: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	var jump_press: bool = Input.is_action_just_pressed("jump")
	var crouch_down: bool = Input.is_physical_key_pressed(KEY_C)
	var crouch_tap: bool = crouch_down and not _crouch_prev
	_crouch_prev = crouch_down

	if crouch_tap:
		is_crouch = !is_crouch
		refresh_crouch_collision()

	if jump_press:
		jump_buffer_timer = jump_buffer

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	state_update(input_x, input_y, run_press)
	apply_movement(input_x, input_y, run_press)
	move_and_slide()

	sprite.flip_h = last_dir < 0
	animate_state()

func refresh_crouch_collision() -> void:
	if is_crouch:
		collision_shape.shape = crouch_shape if crouch_shape else _crouch_shape
		collision_shape.position = _crouch_pos
	else:
		collision_shape.shape = _stand_shape
		collision_shape.position = _stand_pos

func state_update(input_x: float, input_y: float, run_press: bool) -> void:
	if is_crouch:
		current_state = State.CROUCH_WALK
		return

	if is_on_ladder:
		if is_on_floor():
			current_state = State.IDLE
			return
		if input_y != 0:
			current_state = State.CLIMB
			climb_moving = true
		elif current_state == State.CLIMB:
			climb_moving = false
		return

	match current_state:
		State.JUMP:
			if velocity.y > 0:
				current_state = State.FALL
		State.FALL:
			if is_on_floor():
				current_state = State.IDLE
				land_lock_timer = land_lock_time
				_jump_was_run = false
		State.IDLE, State.WALK, State.RUN, State.CROUCH_WALK:
			if not is_on_floor():
				if velocity.y < 0:
					current_state = State.JUMP
				else:
					current_state = State.FALL
			else:
				if input_x != 0:
					current_state = State.RUN if run_press else State.WALK
				else:
					current_state = State.IDLE
		State.CLIMB:
			if not is_on_ladder:
				if is_on_floor():
					current_state = State.IDLE
					_jump_was_run = false
				else:
					current_state = State.JUMP if velocity.y < 0 else State.FALL

func apply_movement(input_x: float, input_y: float, run_press: bool) -> void:
	var target_h_speed: float = 0.0
	if input_x != 0:
		last_dir = sign(input_x)

	match current_state:
		State.CROUCH_WALK:
			target_h_speed = input_x * walk_speed * crouch_speed_scale
			velocity.y += gravity * get_physics_process_delta_time()
			if jump_buffer_timer > 0 and coyote_timer > 0 and land_lock_timer <= 0:
				velocity.y = jump_force * crouch_jump_scale
				jump_buffer_timer = 0.0
				current_state = State.JUMP
				jump_anim_finished = false

		State.CLIMB:
			jump_buffer_timer = 0.0
			target_h_speed = input_x * walk_speed * ladder_horizontal_scale
			velocity.y = input_y * walk_speed * ladder_horizontal_scale

		State.JUMP, State.FALL:
			var air_speed: float = run_speed if _jump_was_run else walk_speed
			target_h_speed = input_x * air_speed * (crouch_speed_scale if is_crouch else 1.0)
			velocity.y += gravity * get_physics_process_delta_time()

		State.IDLE, State.WALK, State.RUN:
			if jump_buffer_timer > 0 and coyote_timer > 0 and land_lock_timer <= 0:
				var was_run := current_state == State.RUN
				velocity.y = jump_force
				jump_buffer_timer = 0.0
				current_state = State.JUMP
				jump_anim_finished = false
				_jump_was_run = was_run
			target_h_speed = input_x * (run_speed if current_state == State.RUN else walk_speed)

	var delta: float = get_physics_process_delta_time()
	if target_h_speed != 0:
		velocity.x = move_toward(velocity.x, target_h_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)

func animate_state() -> void:
	match current_state:
		State.IDLE:
			anim_player.play(ANIM_IDLE)
		State.WALK:
			anim_player.play(ANIM_WALK)
		State.RUN:
			anim_player.play(ANIM_RUN)
		State.CROUCH_WALK:
			if abs(velocity.x) > 1:
				anim_player.play(ANIM_CROUCH_WALK)
			else:
				anim_player.play(ANIM_CROUCH_WALK)
				anim_player.seek(_frame_key_time(ANIM_CROUCH_WALK, crouch_freeze_frame), true)
				anim_player.pause()

		State.JUMP:
			if not jump_anim_finished:
				anim_player.play(ANIM_JUMP)
				if anim_player.current_animation_position >= anim_player.get_animation(ANIM_JUMP).length:
					jump_anim_finished = true
			else:
				anim_player.pause()
		State.FALL:
			if not fall_anim_finished:
				anim_player.play(ANIM_FALL)
				if anim_player.current_animation_position >= anim_player.get_animation(ANIM_FALL).length:
					fall_anim_finished = true
			else:
				anim_player.pause()
		State.CLIMB:
			if climb_moving:
				anim_player.play(ANIM_CLIMB)
			else:
				anim_player.pause()

# 取动画 frame 轨道第 key_idx 个关键帧的时间；找不到返回 0
func _frame_key_time(anim_name: String, key_idx: int) -> float:
	var anim := anim_player.get_animation(anim_name)
	if anim == null:
		return 0.0
	for i in anim.get_track_count():
		if str(anim.track_get_path(i)).ends_with(":frame"):
			if key_idx < anim.track_get_key_count(i):
				return anim.track_get_key_time(i, key_idx)
			break
	return 0.0

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_JUMP:
		jump_anim_finished = true
	if anim_name == ANIM_FALL:
		fall_anim_finished = true

func _on_ladder_body_entered(_body: Node) -> void:
	_ladder_bodies += 1
	is_on_ladder = true

func _on_ladder_body_exited(_body: Node) -> void:
	_ladder_bodies = maxi(0, _ladder_bodies - 1)
	is_on_ladder = _ladder_bodies > 0
