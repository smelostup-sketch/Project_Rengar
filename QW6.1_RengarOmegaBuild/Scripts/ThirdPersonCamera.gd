extends Camera3D

## Камера следует за CharacterBody3D в _process(), то есть после физического
## move_and_slide(). Это убирает один физический кадр отставания при dash/dodge.

@export var target: NodePath
@export var distance := 4.0
@export var min_dist := 2.5
@export var max_dist := 10.0
@export var zoom_speed := 0.5
@export var mouse_sens := 0.004
@export var pitch_limit := 80.0
@export var target_height := 1.5
@export var free_look_key := KEY_QUOTELEFT

var yaw := 0.0
var free_look_active := false
var pitch := deg_to_rad(-20.0)
var player_ref: Node3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player_ref = get_node_or_null(target) as Node3D
	if player_ref == null:
		push_error("ThirdPersonCamera: не назначен target PlayerCharacterBody3D")
		return

	var offset := global_position - player_ref.global_position
	if offset.length_squared() > 0.001:
		yaw = atan2(offset.x, offset.z)
		pitch = -asin(clampf(offset.y / offset.length(), -1.0, 1.0))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.keycode == free_look_key or event.physical_keycode == free_look_key) and not event.echo:
		free_look_active = event.pressed
		return
	
	# Камера ВСЕГДА управляется мышью (и в обычном режиме, и в режиме свободного обзора)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sens
		pitch += event.relative.y * mouse_sens
		pitch = clampf(pitch, deg_to_rad(-pitch_limit), deg_to_rad(pitch_limit))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = maxf(min_dist, distance - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = minf(max_dist, distance + zoom_speed)

func is_free_look_active() -> bool:
	return free_look_active

func get_view_yaw() -> float:
	return yaw

func _process(_delta: float) -> void:
	if player_ref == null:
		return

	# В обычном режиме (free_look_active = false) игрок плавно поворачивается к направлению камеры
	# При активном свободном обзоре (тильда нажата) игрок НЕ поворачивается автоматически
	# Направление камеры (yaw) обновляется в _input() ВСЕГДА при движении мыши
	if not free_look_active:
		# Игрок следует за камерой
		player_ref.rotation.y = lerp_angle(player_ref.rotation.y, yaw, 12.0 * _delta)
	
	var look_target := player_ref.global_position + Vector3.UP * target_height
	var camera_direction := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	).normalized()

	global_position = look_target + camera_direction * distance
	look_at(look_target, Vector3.UP)
