extends Node2D

@onready var car: RigidBody2D = $".."



func _physics_process(delta: float) -> void:
	if car.linear_velocity.length() > 800:
		position.x = move_toward(position.x, car.linear_velocity.length() / 6, 30 * delta)
	else:
		position.x = move_toward(position.x, 0, 30 * delta)
