# attach to TextureRect
extends TextureRect

@export var textures: Array = ["res://UI/向左轉燈.png", "res://UI/無轉向燈.png", "res://UI/向右轉燈.png"]  # 在編輯器把圖片拖進來


func _ready() -> void:
	pass

# 用 action（推薦）
func _process(delta: float) -> void:
	if Input.is_action_pressed("Left_turn"):
		_change_texture(0)
	elif Input.is_action_pressed("Right_turn"):
		_change_texture(2)
	else:
		_change_texture(1)

func _change_texture(delta_idx: int) -> void:
	if textures.size() == 0:
		return
	texture = load(textures[delta_idx])
