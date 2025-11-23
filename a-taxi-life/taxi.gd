extends RigidBody2D
@onready var left_front_wheel: Sprite2D = $LeftFrontWheel
@onready var right_front_wheel: Sprite2D = $RightFrontWheel


@export var max_speed: float = 1600.0
@export var break_power: float = 300.0
@export var engine_force: float = 200.0
@export var max_steer_angle: float = 45.0
@export var steer_speed: float = 400.0
@export var return_steer_speed: float = 120.0
@export var drift_factor: float = 5

@export_group("scale")
@export var gear_ratios := [0.0, 0.5, 0.75, 0.88, 0.95, 1.0, -0.3]
@export var gear_max_speeds := [0, 100, 200, 400, 800, 1600, 200]
var gear: int = 1
var shifting: bool = false
var shifting_check_y:float = 0.0
var shifting_delay: bool = false
var shift_type: int = 0
var shift_cooldown: float = 0.25
var shift_timer: float = 0.0

var creeping: bool = false
var dragging: bool = false

var displayed_rpm: int = 0
var rpm: int = 800

var base_idle_rpm: float = 800
var redline_rpm: float = 7000 
var rpm_acceleration: float = 1000
var rpm_deceleration: float = 600

var previous_gear: int = 1

var steer_angle: float = 0.0

signal steering_changed(angle: float)
signal shift_changed(type: bool)
signal braking(type: bool)
signal accelerate(type: bool)
signal speed_update(speed: int)
signal rpm_update(rpm: int)

func _ready() -> void:
	gravity_scale = 0.0
	
func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				dragging = false
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				shifting = true
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				shifting = false
				shifting_check_y = 0.0
	if not dragging and not shifting:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if Input.is_action_pressed("B") and linear_velocity.length() > 1e-2 and linear_velocity.length() < 3:
		linear_velocity = Vector2.ZERO
	
	if creeping:
		linear_velocity = linear_velocity.clampf(-40, 40)
	
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	if gear == -1:
		linear_velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	var current_linear_velocity = linear_velocity.length()
	if shifting:
		var mouse_move_y = Input.get_last_mouse_velocity().y
		shifting_check_y += mouse_move_y/15000
		if not shifting_delay:
			if shifting_check_y > 1 and shift_type > -2:
				shift_type -= 1
				emit_signal("shift_changed", shift_type)
				shifting_check_y -= 1
				shifting_delay = true
				shift_timer = shift_cooldown
			elif shifting_check_y < -1 and shift_type < 1:
				shift_type += 1
				emit_signal("shift_changed", shift_type)
				shifting_check_y += 1
				shifting_delay = true
				shift_timer = shift_cooldown
			elif shifting_check_y < -1 and shift_type == 1 and current_linear_velocity == 0:
				shift_type += 1
				emit_signal("shift_changed", shift_type)
				shifting_check_y += 1
				shifting_delay = true
				shift_timer = shift_cooldown
		else:
			shift_timer -= delta
			if shift_timer <= 0:
				shifting_delay = false
	match shift_type:
		-2:
			if gear_max_speeds[gear] - current_linear_velocity < 100 and gear < 2:
				gear += 1
				emit_signal("gear_changed", gear)
			elif current_linear_velocity - gear_max_speeds[(gear-1)] < -100 and gear > 1:
				gear -= 1
				emit_signal("gear_changed", gear)
			elif gear > 2:
				gear = 2
		-1:
			if gear_max_speeds[gear] - current_linear_velocity < 100 and gear < 5:
				gear += 1
				emit_signal("gear_changed", gear)
			elif current_linear_velocity - gear_max_speeds[(gear-1)] < -100 and gear > 1:
				gear -= 1
				emit_signal("gear_changed", gear)
		0:
			gear = 0
		1:
			gear = 6
		2:
			gear = -1
	
	if dragging:
		var mouse_move_x = Input.get_last_mouse_velocity().x
		var sensitivity: float = 0.00025 / max(current_linear_velocity/5, 10) * 10
		steer_angle = clamp(steer_angle + mouse_move_x * sensitivity,-max_steer_angle,max_steer_angle)
	else:
		steer_angle = move_toward(steer_angle, 0.0, return_steer_speed * delta)
	emit_signal("steering_changed", steer_angle)
	left_front_wheel.rotation_degrees = steer_angle + 90
	right_front_wheel.rotation_degrees = steer_angle + 90

	var forward_dir = Vector2.RIGHT.rotated(rotation)


	if Input.is_action_pressed("space"):
		creeping = false
		if linear_velocity.length() < gear_max_speeds[gear]:
			var force = forward_dir * engine_force * gear_ratios[gear] * cos(deg_to_rad(steer_angle))
			apply_central_force(force)
		emit_signal("accelerate", true)
	else:
		if shift_type == -1 and creeping:
			var force = forward_dir * engine_force * 0.05 * cos(deg_to_rad(steer_angle))
			apply_central_force(force)
		elif shift_type == -1 and not creeping and current_linear_velocity <= 30:
			creeping = true
		elif creeping:
			creeping = false
			
		emit_signal("accelerate", false)
		
	$TestingTextLabel.text = str(gear)
	
	if Input.is_action_pressed("B"):
		if linear_velocity.length() > 1e-2:
			var force = -linear_velocity.normalized() * break_power
			apply_central_force(force)
		emit_signal("braking", true)
	else:
		emit_signal("braking", false)
		
	if steer_angle:
		rotation += deg_to_rad(steer_angle) * delta * linear_velocity.length() / 100
		#var force = -linear_velocity * 500 * (1 - cos(deg_to_rad(rotation)))
		#apply_central_force(force)
	
	
	var lateral_velocity = transform.basis_xform_inv(linear_velocity).y
	var lateral_force = -lateral_velocity * drift_factor
	apply_central_force(Vector2(-sin(rotation), cos(rotation)) * lateral_force)

	
	calculate_current_speed()
	update_rpm_continuous(delta)

func calculate_current_speed():
	var speed = round(linear_velocity.length())/10
	emit_signal("speed_update", speed)

func update_rpm_continuous(delta: float):
	var speed = linear_velocity.length()

	displayed_rpm = move_toward(displayed_rpm, rpm, 1000 * delta)

	if gear == 0 or gear == -1:
		rpm -= rpm_deceleration * delta
		rpm = max(rpm, base_idle_rpm)
		emit_signal("rpm_update", displayed_rpm)
		return

	var max_speed_gear = gear_max_speeds[gear]
	var speed_ratio = clamp(speed / max_speed_gear, 0.0, 1.0)

	if gear < previous_gear and gear > 0:
		var gear_ratio = gear_ratios[previous_gear] / gear_ratios[gear]
		rpm *= gear_ratio  
	elif gear > previous_gear:
		rpm *= 0.7

	if Input.is_action_pressed("space") and not creeping and linear_velocity.length() < gear_max_speeds[gear]:
		rpm += rpm_acceleration * delta
	else:
		if creeping:
			rpm += rpm_acceleration * 0.1 * delta
		rpm -= rpm_deceleration * delta
		rpm = max(rpm, base_idle_rpm)

	rpm = clamp(rpm, base_idle_rpm, redline_rpm)

	previous_gear = gear
	



	emit_signal("rpm_update", displayed_rpm)
