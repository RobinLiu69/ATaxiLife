extends Node
class_name SteeringWheel

# --- 配置參數 ---
@export_group("Steering Setup")
@export var STEERING_ANGLE_MAX: float = 30.0 # 最大轉向角 (度)
@export var STEERING_SENSITIVITY: float = 0.001 # 基礎滑鼠靈敏度
@export var RETURN_SPEED: float = 10.0 # 方向盤回正速度 (度/秒)
@export var VELOCITY_SENSITIVITY_SCALAR: float = 10.0 # 速度對靈敏度的影響縮放因子

# --- 狀態變數 ---
var current_steer_angle: float = 0.0 # 當前方向盤轉向角度 (度)
var is_dragging: bool = false        # 是否正在拖曳滑鼠 (操作方向盤)

# --- 接收來自 CarController 的數據 ---
var current_car_speed: float = 0.0   # 由車體腳本傳入的當前速度 (m/s)

# 信號定義 (讓車體知道轉向角度變了)
signal steering_changed(new_angle: float)

func _process(delta: float) -> void:
	# 由於滑鼠輸入是幀率相關，所以放在 _process 處理輸入
	_update_steering_input(delta)

func _update_steering_input(delta: float) -> void:
	
	# 1. 計算靈敏度 (考慮車速影響)
	# 原邏輯：速度越快，分母越大，靈敏度越低 (更難轉動)
	var speed_factor = max(current_car_speed / 5.0, 10.0) * VELOCITY_SENSITIVITY_SCALAR
	var calculated_sensitivity = STEERING_SENSITIVITY / speed_factor
	
	if is_dragging:
		# 2. 滑鼠拖曳輸入 (改變角度)
		var mouse_delta_x: float = Input.get_last_mouse_velocity().x
		
		# 累積轉向角度
		var angle_change = mouse_delta_x * calculated_sensitivity
		current_steer_angle = clamp(current_steer_angle + angle_change, -STEERING_ANGLE_MAX, STEERING_ANGLE_MAX)
		
	else:
		# 3. 自動回正邏輯
		current_steer_angle = move_toward(current_steer_angle, 0.0, RETURN_SPEED * delta)

	emit_signal("steering_changed", current_steer_angle)

# --- 供外部調用：更新車速 ---
func set_car_speed(speed: float):
	current_car_speed = abs(speed)
