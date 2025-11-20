extends Sprite2D

func _ready():
	var car = get_parent()
	print(car)
	car.steering_changed.connect(_on_car_steering)

func _on_car_steering(angle):
	rotation_degrees = angle +90
