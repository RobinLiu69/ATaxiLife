extends RigidBody2D

# 確保已連結引擎和排檔桿節點
@onready var engine: CarEngine = $CarEngine
@onready var shifter: GearShifter = $GearShifter
@onready var steering_wheel: SteeringWheel = $SteeringWheel # 假設也已連結
@onready var left_front_wheel: Sprite2D = $LeftFrontWheel
@onready var right_front_wheel: Sprite2D = $RightFrontWheel

# --- 常數/參數 ---
@export var wheelbase: float = 2.5 # 軸距

# 內部狀態
var throttle_input: float = 0.0
var brake_input: float = 0.0
# ... (其他 CarController 變數，如 steering_angle)

signal steering_changed(angle: float)
signal gear_changed(gear_position: int)
signal speed_update(speed: int)
signal rpm_update(engine_rpm: int)

func _ready():
	# 設置排檔桿信號監聽
	shifter.gear_position_changed.connect(_on_gear_position_changed)
	steering_wheel.steering_changed.connect(_steering_wheel_changed)
	engine.current_rpm_update.connect(_rpm_update)
	# 初始化
	gravity_scale = 0 
	linear_damp = 0.0 
	
	# 初始檔位
	_on_gear_position_changed.call(shifter.gear_position)
	
func _steering_wheel_changed(angle: float) -> void:
	right_front_wheel.rotation_degrees = 90 + angle
	left_front_wheel.rotation_degrees = 90 + angle
	emit_signal("steering_changed", angle)

func _input(event: InputEvent):
	# 1. 處理油門/煞車輸入 (鍵盤)
	throttle_input = Input.get_action_strength("accelerate") * 0.5
	brake_input = Input.get_action_strength("brake")
	
	# 2. 處理排檔桿輸入 (滑鼠)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: # 假設右鍵開始操作排檔桿
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			shifter.is_shifter_active = event.pressed
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			steering_wheel.is_dragging = event.pressed
		if not steering_wheel.is_dragging and not shifter.is_shifter_active:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	# 1. 計算當前車速 (縱向速度)
	var speed = (linear_velocity.dot(transform.x)/10)
	var absolute_speed = abs(speed)
	var car_mass = mass
	
	# 2. 更新排檔桿狀態 (執行換檔邏輯)
	shifter.shift_gear_with_mouse(delta, absolute_speed)
	
	# 3. 更新方向盤狀態 (計算轉向角度)
	steering_wheel.set_car_speed(speed)
	steering_wheel._update_steering_input(delta) # 假設在 _process 裡更新輸入，但物理處理在 _physics_process
	
	# 4. 引擎動力與阻力計算 (傳入輸入和速度)
	
	
	# 5. 應用縱向驅動力
	var drive_force_vector = transform.x * engine.calculate_physics(delta, speed, throttle_input, brake_input, car_mass)
	apply_central_force(drive_force_vector)

	# 6. 應用轉向 (角速度)
	_apply_steering_physics(delta, speed)

	# 7. 應用側向摩擦力 (抓地力)
	_apply_lateral_friction(delta)
	
	emit_signal("speed_update", absolute_speed)
# --- 信號處理函式 ---

# 接收 GearShifter 的信號，並更新 CarEngine 的檔位
func _on_gear_position_changed(new_position: int):
	var gear_mode_str: String
	emit_signal("gear_changed", new_position)
	
	match new_position:
		2: gear_mode_str = "P"
		1: gear_mode_str = "R"
		0: gear_mode_str = "N"
		-1: gear_mode_str = "D"
		-2: gear_mode_str = "L"
		_:
			push_error("Invalid gear position received: ", new_position)
			return

	engine.shift_to(gear_mode_str)
	print("Gear shifted to: ", gear_mode_str)
	
	
func _rpm_update(rpm: int) -> void:
	emit_signal("rpm_update", rpm)

func _apply_steering_physics(delta: float, forward_velocity: float) -> void:
	var steer_angle_rad = deg_to_rad(steering_wheel.current_steer_angle)
	
	if abs(forward_velocity) > 0.1:
		# 設置角速度: 速度 * tan(轉向角) / 軸距
		angular_velocity = (forward_velocity * tan(steer_angle_rad) / wheelbase)
	else:
		# 靜止時慢慢停止旋轉
		angular_velocity = move_toward(angular_velocity, 0.0, 5.0 * delta)

func _apply_lateral_friction(delta: float):
	# 側向摩擦力邏輯 (確保車子不會無限側滑)
	var right_vector = transform.y 
	var lateral_velocity = linear_velocity.dot(right_vector)
	
	var grip = 0.8 # 簡化，實際應隨速度變化
	
	var friction_impulse = -lateral_velocity * mass * grip
	
	# 施加側向力
	apply_central_force(right_vector * friction_impulse / delta)
