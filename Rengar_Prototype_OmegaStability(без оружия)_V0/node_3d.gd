extends Node3D

@export var speed := 5.0

func _process(delta):
	var dir := Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	
	# normalized() делает скорость одинаковой по диагонали
	# delta обеспечивает плавность на любом FPS
	position += dir.normalized() * speed * delta
