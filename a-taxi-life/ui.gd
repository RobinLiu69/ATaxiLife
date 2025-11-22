extends CanvasLayer

@onready var car = get_parent()

@onready var accelerator = $Accelerator
@onready var brakes = $Brakes
@onready var shifter: TextureRect = $GearShifterBoard/GearShifter
@onready var speed_text_display: RichTextLabel = $DashBoard/SpeedTextDisplay
@onready var steering_wheel: TextureRect = $SteeringWheel
@onready var direction_light: TextureRect = $SteeringWheel/DirectionLight
@onready var update_timer: Timer = $DashBoard/SpeedTextDisplay/UpdateTimer


@export var direction_textures: Array[String] = [
	"res://UI/向左轉燈.png",
	"res://UI/無轉向燈.png",
	"res://UI/向右轉燈.png"
]

var current_speed: int = 0


func _ready() -> void:
	car.accelerate.connect(_on_car_accelerate)
	car.braking.connect(_on_car_braking)
	car.shift_changed.connect(_on_car_shift)
	car.steering_changed.connect(_on_car_steering)
	car.speed_update.connect(_update_current_speed)
	


func _on_car_accelerate(step_on: bool) -> void:
	accelerator.position.y = 912 if step_on else 902


func _on_car_braking(step_on: bool) -> void:
	brakes.position.y = 912 if step_on else 902

func _on_car_shift(type: int) -> void:
	if type == 2:
		shifter.position.y = -165
	else:
		shifter.position.y = -60 + type * -35


func _update_current_speed(speed: int) -> void:
	current_speed = speed


func _on_car_steering(angle: float) -> void:
	steering_wheel.rotation_degrees = angle * 10

func _process(delta: float) -> void:
	if Input.is_action_pressed("Left_turn"):
		_change_direction_light(0)
	elif Input.is_action_pressed("Right_turn"):
		_change_direction_light(2)
	else:
		_change_direction_light(1)


func _change_direction_light(idx: int) -> void:
	if direction_textures.is_empty():
		return
	direction_light.texture = load(direction_textures[idx])


func _on_update_timer_timeout() -> void:
	speed_text_display.text = str(current_speed)
