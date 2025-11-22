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

var dragging := false

var steer_angle: float = 0.0

signal steering_changed(angle: float)
signal shift_changed(type: bool)
signal braking(type: bool)
signal accelerate(type: bool)
signal speed_update(speed: int)

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

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	if gear == -1:
		linear_velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
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
			elif shifting_check_y < -1 and shift_type == 1 and linear_velocity.length() == 0:
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
			if gear_max_speeds[gear] - linear_velocity.length() < 100 and gear < 2:
				gear += 1
			elif linear_velocity.length() - gear_max_speeds[(gear-1)] < -200 and gear > 1:
				gear -= 1
			elif gear > 2:
				gear = 2
		-1:
			if gear_max_speeds[gear] - linear_velocity.length() < 100 and gear < 5:
				gear += 1
			elif linear_velocity.length() - gear_max_speeds[(gear-1)] < -200 and gear > 1:
				gear -= 1
		0:
			gear = 0
		1:
			gear = 6
		2:
			gear = -1
	
	if dragging:
		var mouse_move_x = Input.get_last_mouse_velocity().x
		var sensitivity := 0.00025
		steer_angle = clamp(steer_angle + mouse_move_x * sensitivity,-max_steer_angle,max_steer_angle)
	else:
		steer_angle = move_toward(steer_angle,0.0,return_steer_speed * delta)
	emit_signal("steering_changed", steer_angle)
	left_front_wheel.rotation_degrees = steer_angle + 90
	right_front_wheel.rotation_degrees = steer_angle + 90

	var forward_dir = Vector2.RIGHT.rotated(rotation)


	if Input.is_action_pressed("space"):
		if linear_velocity.length() < gear_max_speeds[gear]:
			var force = forward_dir * engine_force * gear_ratios[gear] * cos(deg_to_rad(steer_angle))
			apply_central_force(force)
		emit_signal("accelerate", true)
	else:
		emit_signal("accelerate", false)
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

func calculate_current_speed():
	var speed = round(linear_velocity.length())/10
	emit_signal("speed_update", speed)
