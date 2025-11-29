extends Node
class_name GearShifter

@export var DRAG_THRESHOLD: float = 1.0        # 換檔所需的累積拖曳閾值
@export var MOUSE_SENSITIVITY: float = 15000.0 # 滑鼠移動的靈敏度
@export var SHIFT_COOLDOWN_TIME: float = 0.2   # 換檔冷卻時間 (秒)

# --- 內部狀態變數 ---
var is_shifter_active: bool = false         # 是否正在拖曳排檔桿
var shifter_drag_accumulator: float = 0.0   # 累積拖曳量
var is_on_cooldown: bool = false            # 換檔延遲/冷卻中
var cooldown_timer: float = 0.0             # 冷卻計時器
var gear_position: int = -1                 # 當前排檔位置 (2=P, 1=R, 0=N, -1=D, -2=L)

# 信號定義 (假設已在腳本頂部定義)
signal gear_position_changed(new_position: int)

func shift_gear_with_mouse(delta: float, current_car_speed: float) -> void:
	# 僅當操作排檔桿時執行
	if is_shifter_active:
		# 1. 累積滑鼠拖曳量
		if is_on_cooldown:
			cooldown_timer -= delta
			if cooldown_timer <= 0:
				is_on_cooldown = false
			return # 冷卻中，跳過換檔判斷
		var mouse_delta_y: float = Input.get_last_mouse_velocity().y
		shifter_drag_accumulator += mouse_delta_y / MOUSE_SENSITIVITY
		
		# 2. 處理換檔冷卻時間
		
		# 3. 判斷換檔動作
		var shift_up_requested: bool = shifter_drag_accumulator < -DRAG_THRESHOLD
		var shift_down_requested: bool = shifter_drag_accumulator > DRAG_THRESHOLD
		
		var new_position: int = gear_position
		var is_shift_successful: bool = false
		
		if shift_up_requested: # 向上推排檔桿 (R -> N -> P)
			# 向上換檔 (檔位數值 +1，如 N(0) -> R(1))
			if gear_position < 2: # 檔位上限是 P(2)
				new_position = gear_position + 1
				is_shift_successful = true
			
		elif shift_down_requested: # 向下推排檔桿 (P -> R -> N -> D -> L)
			
			# --- P(2) -> R(1) / R(1) -> N(0) / N(0) -> D(-1) ---
			if gear_position > -1: # 從 P, R, N 往下撥 (非 L 檔)
				new_position = gear_position - 1
				is_shift_successful = true
			
			# --- D(-1) -> L(-2) 特殊條件 ---
			elif gear_position == -1:
				 # 原始邏輯的 D -> L 判斷 (假設 L 檔需要靜止才能切入)
				new_position = gear_position - 1
				is_shift_successful = true
			# --- L(-2) 檔位下限 ---
			# 當前在 L 檔時，無法再向下切換，所以不做任何動作
			
		# 4. 執行換檔並重置狀態
		if is_shift_successful:
			if new_position != gear_position:
				gear_position = new_position
				
				# 發送信號通知 CarEngine 腳本
				emit_signal("gear_position_changed", gear_position)
				
				# 重設累積量 (只抵銷一個閾值，保留多餘的拖曳量)
				if shift_up_requested:
					shifter_drag_accumulator += DRAG_THRESHOLD
				elif shift_down_requested:
					shifter_drag_accumulator -= DRAG_THRESHOLD
				
				# 啟動冷卻
				is_on_cooldown = true
				cooldown_timer = SHIFT_COOLDOWN_TIME
				
	else:
		# 如果沒有拖曳，讓累積量慢慢歸零 (防止閒置時誤觸)
		shifter_drag_accumulator = lerp(shifter_drag_accumulator, 0.0, delta * 5.0)
