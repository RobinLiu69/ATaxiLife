extends RigidBody2D

# ---- 車輛參數 ----
@export var max_speed: float = 2000.0        # 像素/秒
@export var engine_force: float = 200.0     # 前進最大推力
@export var brake_force: float = 200.0      # 倒退 / 煞車
@export var max_steer_angle: float = 180.0    # 最大轉角（度）
@export var steer_speed: float = 400.0       # 轉向速度（度/秒）
@export var return_steer_speed: float = 120.0       # 轉回速度（度/秒）
@export var drift_factor: float = 0.95       # 側向漂移阻尼

# ---- 檔位系統 ----
@export var gear_ratios := [0.0, 0.5, 0.75, 1.0]   # 加速度倍率
@export var gear_max_speeds := [0, 400, 800, 1200] # 每檔最大速度
var gear: int = 1
var shifting: bool = false
var shift_cooldown: float = 0.25
var shift_timer: float = 0.0

var mouse_start_x := 0.0
var dragging := false

var steer_angle: float = 0.0

signal steering_changed(angle)

func _ready() -> void:
	gravity_scale = 0.0
func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				mouse_start_x = event.position.x
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				dragging = false
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
func _physics_process(delta: float) -> void:
	# ---- 檔位切換 ----
	gear = 1
	#if not shifting:
		#if Input.is_action_just_pressed("gear_up") and gear < gear_ratios.size() - 1:
			#gear += 1
			#shifting = true
			#shift_timer = shift_cooldown
		#elif Input.is_action_just_pressed("gear_down") and gear > 1:
			#gear -= 1
			#shifting = true
			#shift_timer = shift_cooldown
	#else:
		#shift_timer -= delta
		#if shift_timer <= 0:
			#shifting = false

	# ---- 轉向控制 ----
	if dragging:
		var mouse_move_x = Input.get_last_mouse_velocity().x
		var sensitivity := 0.00025
		steer_angle = clamp(steer_angle + mouse_move_x * sensitivity,-max_steer_angle,max_steer_angle)
	else:
		# ⭐ 逐漸回正：利用 move_toward
		steer_angle = move_toward(steer_angle,0.0,return_steer_speed * delta)

	# ---- 計算車頭方向 ----
	var forward_dir = Vector2.RIGHT.rotated(rotation)

	# ---- 計算當前速度方向 ----
	var local_velocity = transform.basis_xform_inv(linear_velocity)

	# ---- 推進力 ----
	if Input.is_action_pressed("W"):
		var force = forward_dir * engine_force * gear_ratios[gear]
		apply_central_force(force)
	elif Input.is_action_pressed("S"):
		var force = -forward_dir * brake_force
		apply_central_force(force)

	# ---- 轉向影響 ----
	if abs(local_velocity.x) > 0.1:
		rotation += deg_to_rad(steer_angle) * local_velocity.x / max_speed * delta
		emit_signal("steering_changed", steer_angle)	

	# ---- 側向漂移阻尼 ----
	var lateral_velocity = transform.basis_xform_inv(linear_velocity).y
	var lateral_force = -lateral_velocity * drift_factor * mass
	apply_central_force(Vector2(-sin(rotation), cos(rotation)) * lateral_force)

	# ---- 限制最高速度 ----
	if linear_velocity.length() > gear_max_speeds[gear]:
		linear_velocity = linear_velocity.normalized() * gear_max_speeds[gear]
