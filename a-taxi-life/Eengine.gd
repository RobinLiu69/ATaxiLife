extends Node
class_name CarEngine

# --- 汽車參數 (已根據 160 km/h 要求調整 Redline) ---
@export var wheel_radius: float = 0.35      # 車輪半徑 (m)
@export var max_torque: float = 250.0       # 引擎最大扭矩 (Nm)
@export var max_power_rpm: float = 3500.0   # 扭矩峰值轉速 (RPM)
@export var redline_rpm: float = 4250.0     # 引擎紅線轉速 (RPM) - 調整至約 160 km/h 頂速
@export var idle_rpm: float = 800.0         # 怠速轉速 (RPM)
@export var final_drive_ratio: float = 3.5  # 最終傳動比

# 檔位傳動比：[R, N, 1, 2, 3, 4, 5, ...]
@export var gear_ratios: Array[float] = [-3.2, 0.0, 2.9, 1.8, 1.3, 1.0, 0.75]
@export var shift_up_rpm: float = 4000.0    # 換檔：升檔轉速 (配合新紅線調整)
@export var shift_down_rpm: float = 2000.0  # 換檔：降檔轉速
@export var brake_strength_const: float = 15.0 # 煞車強度常數 (N / (kg * brake))
@export var creep_torque: float = 30.0      # 蠕行扭矩 (Nm)
@export var clutch_slip_efficiency: float = 0.8 # 離合器滑動時傳遞的扭矩效率
@export var clutch_lock_speed: float = 5.0  # 離合器鎖定速度閾值 (m/s)

# --- 內部狀態變數 ---
var current_rpm: float = 800.0
var current_gear_idx: int = 2        # 預設 1 檔 (索引 2)
var current_gear_mode: String = "D"  # 預設 Drive 模式
var _clutch_engaged: bool = false    

signal current_rpm_update(rpm: int) 

const PI_2 = 2.0 * PI
const LOW_GEAR_SPEED_LIMIT_MS = 20.0 / 3.6 # 20 km/h 轉換為 m/s (~5.56 m/s)

# ----------------------------------------------------------------------------------
# 內建函式：變速箱控制
# ----------------------------------------------------------------------------------

func _handle_auto_shift() -> void:
	# 只有在 D 檔才執行自動換檔
	if current_gear_mode != "D":
		return
	
	var max_forward_gear_idx = gear_ratios.size() - 1 
	
	# 升檔邏輯
	if current_gear_idx >= 2 and current_rpm > shift_up_rpm and current_gear_idx < max_forward_gear_idx:
		current_gear_idx += 1
		
	# 降檔邏輯
	elif current_gear_idx > 2 and current_rpm < shift_down_rpm:
		current_gear_idx -= 1

func shift_to(mode: String) -> void:
	current_gear_mode = mode
	match mode:
		"D": 
			current_gear_idx = 2 # 1 檔 (自動換檔的起點)
		"N":
			current_gear_idx = 1 # 空檔
		"R":
			current_gear_idx = 0 # 倒檔
		"L":
			current_gear_idx = 2 # L 檔鎖定在 1 檔
			
	_clutch_engaged = false 

# ----------------------------------------------------------------------------------
# 核心計算函式
# ----------------------------------------------------------------------------------
func calculate_physics(dt: float, signed_speed: float, throttle: float, brake: float, mass_of_car: float) -> float:
	
	var v_ms = signed_speed
	var abs_v_ms = abs(v_ms)
	var throttle_clamped = clampf(throttle, 0.0, 1.0)
	var brake_clamped = clampf(brake, 0.0, 1.0)
	
	# --- 1. 計算總傳動比 ---
	var gamma_gear: float = 0.0
	if current_gear_idx >= 0 and current_gear_idx < gear_ratios.size():
		gamma_gear = gear_ratios[current_gear_idx]
		
	var gamma: float = final_drive_ratio * gamma_gear
	var abs_gamma: float = abs(gamma)
	
	# --- 2. 決定 RPM 和離合器狀態 (R/L 檔速度限制邏輯新增) ---

	var wheel_rpm_sync: float = 0.0
	if abs_gamma > 0.001:
		wheel_rpm_sync = (abs_v_ms * abs_gamma * 60.0) / PI_2 / wheel_radius
	
	# **【新增 R/L 檔速度限制邏輯】**
	if (current_gear_mode == "L" or current_gear_mode == "R") and abs_v_ms > LOW_GEAR_SPEED_LIMIT_MS:
		# 如果 R 或 L 檔超速 (> 20 km/h)，限制同步 RPM，從而限制驅動力
		var limited_rpm_sync: float = (LOW_GEAR_SPEED_LIMIT_MS * abs_gamma * 60.0) / PI_2 / wheel_radius
		wheel_rpm_sync = minf(wheel_rpm_sync, limited_rpm_sync)
		
	var engine_target_rpm = lerpf(idle_rpm, redline_rpm, throttle_clamped)

	if abs_gamma < 0.001: # 空檔 (N)
		current_rpm = lerp(current_rpm, engine_target_rpm, dt * 5.0) 
		_clutch_engaged = false
	elif abs_v_ms < clutch_lock_speed or brake_clamped > 0.01:
		# 低速或踩煞車：變矩器滑動/離合器分離，RPM 由油門決定
		current_rpm = lerp(current_rpm, engine_target_rpm, dt * 3.0)
		_clutch_engaged = false
	else:
		# 正常行駛：離合器鎖定 (硬連接)，RPM 由車速決定
		current_rpm = maxf(wheel_rpm_sync, idle_rpm)
		_clutch_engaged = true
		
	current_rpm = minf(current_rpm, redline_rpm) # **【整體最大速度 160 km/h 限制的關鍵】**

	_handle_auto_shift()

	# --- 3. 引擎扭矩 $T_{engine}$ 計算 ---
	var T_max_at_RPM: float = 0.0
	var T_output: float = 0.0
	var F_drive: float = 0.0

	if abs_gamma > 0.001:
		
		# a. 扭矩曲線擬合
		var torque_range = max_power_rpm - idle_rpm
		var rpm_since_idle = current_rpm - idle_rpm
		var torque_factor: float
		
		if rpm_since_idle <= 0.0:
			torque_factor = 0.0
		elif rpm_since_idle <= torque_range:
			torque_factor = sin( (rpm_since_idle / torque_range) * PI / 2.0 )
		else:
			var decay_range = redline_rpm - max_power_rpm
			var decay_factor = (current_rpm - max_power_rpm) / decay_range
			decay_factor = clampf(decay_factor, 0.0, 1.0)
			torque_factor = lerpf(1.0, 0.75, decay_factor) 
		
		T_max_at_RPM = max_torque * clampf(torque_factor, 0.0, 1.0)
		
		# b. 實際引擎扭矩
		var T_engine = T_max_at_RPM * throttle_clamped
		
		# c. 車輪輸出扭矩 (離合器/變矩器邏輯)
		if _clutch_engaged:
			T_output = T_engine
		else:
			if current_gear_mode == "D" and abs_v_ms < 1.0 and throttle_clamped == 0.0 and brake_clamped == 0.0:
				T_output = creep_torque
			elif throttle_clamped > 0.0:
				T_output = T_engine * clutch_slip_efficiency
			else:
				T_output = 0.0

		# d. 驅動力 $F_{drive}$ 
		F_drive = (T_output * abs_gamma) / wheel_radius
		
		# e. 判斷驅動力方向
		if gamma_gear < 0.0: 
			F_drive = -abs(F_drive)
		elif v_ms < -0.1 and gamma_gear > 0.0:
			F_drive = -abs(F_drive) 
		
	else:
		F_drive = 0.0

	# --- 4. 煞車力 $F_{brake}$ ---
	var F_brake: float = 0.0
	
	if brake_clamped > 0.0: 
		var F_brake_magnitude = brake_clamped * brake_strength_const * mass_of_car
		
		if abs_v_ms < 0.1:
			var max_static_brake = abs(F_drive) + 1.0 
			F_brake_magnitude = minf(F_brake_magnitude, max_static_brake)
			
			if abs(F_drive) > 0.0:
				F_brake = -sign(F_drive) * F_brake_magnitude
			else:
				F_brake = 0.0
		else:
			F_brake = -sign(v_ms) * F_brake_magnitude
		
	# --- 5. 總牽引力回傳 ---
	var F_traction = F_drive + F_brake
	
	emit_signal("current_rpm_update", int(current_rpm))
	
	return F_traction
