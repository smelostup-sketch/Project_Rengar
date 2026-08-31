extends CharacterBody3D

@export var speed: float = 6.0
@export var rot_sensitivity: float = 0.005
@export var jump_force: float = 8.0
@export var gravity: float = 20.0
@export var leap_range: float = 12.0
@export var leap_speed: float = 15.0

var hp: float = 100.0
var max_hp: float = 100.0
var is_current_hit_leap: bool = false  # 🔑 Отслеживает тип текущей атаки
var vy: float = 0.0
var is_on_ground: bool = true
var is_stealthed: bool = false
var is_leaping: bool = false
var leap_start: Vector3 = Vector3.ZERO
var leap_end: Vector3 = Vector3.ZERO
var leap_duration: float = 0.0
var leap_elapsed: float = 0.0
var hit_registered: bool = false  # Защита от двойного урона

func _ready() -> void:
	print("✅ Система боя загружена")
	for bush in get_tree().get_nodes_in_group("bush"):
		if bush is Area3D:
			bush.body_entered.connect(_on_bush_entered)
			bush.body_exited.connect(_on_bush_exited)

func _process(delta: float) -> void:
	_handle_gravity(delta)
	if is_leaping: _update_leap(delta)
	else:
		_handle_movement(delta)
		_handle_rotation(delta)

func _handle_gravity(delta: float) -> void:
	vy -= gravity * delta
	position.y += vy * delta
	if position.y <= 0.0: position.y = 0.0; vy = 0.0; is_on_ground = true

func _handle_movement(delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		position += global_transform.basis * dir * speed * delta

func _handle_rotation(delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation.y -= Input.get_last_mouse_velocity().x * rot_sensitivity * delta

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and is_on_ground:
			vy = jump_force; is_on_ground = false; print("🦘 Прыжок")

		if event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
			if is_stealthed and not is_leaping: _start_ambush()
			else: _perform_attack(event.physical_keycode)
			
		if event.physical_keycode == KEY_K:
			take_dmg(40)  # 🔑 ТЕСТ HP (удали после проверки)

func _find_nearest_enemy() -> Node3D:
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		print("⚠️ ПРЫЖОК: Враги не найдены! Проверь группу 'enemy' у узла CharacterBody3D врага.")
		return null
		
	var nearest: Node3D = null
	var min_dist: float = leap_range + 1.0
	for e in enemies:
		if e is Node3D:
			var d = global_position.distance_to(e.global_position)
			if d < min_dist:
				min_dist = d
				nearest = e
				
	print("🎯 ПРЫЖОК: Цель = ", nearest.name, " | Дистанция = ", round(min_dist))
	return nearest

func _start_ambush() -> void:
	var target: Node3D = _find_nearest_enemy()
	if target == null: print("❌ Враг слишком далеко"); return
	is_stealthed = false; is_leaping = true
	leap_start = global_position; leap_end = target.global_position
	leap_elapsed = 0.0; leap_duration = leap_start.distance_to(leap_end) / leap_speed
	print("🐆 Прыжок из засады")

func _update_leap(delta: float) -> void:
	leap_elapsed += delta
	var t: float = clampf(leap_elapsed / leap_duration, 0.0, 1.0)
	var current: Vector3 = leap_start.lerp(leap_end, t)
	current.y += sin(t * PI) * 1.5
	global_position = current
	if t >= 1.0:
		is_leaping = false; position.y = 0.0; vy = 0.0; is_on_ground = true
		is_current_hit_leap = true  # 🔑 Прыжок из засады
		print("💥 Приземление")
		_spawn_hitbox(global_position)
	var ui = get_node_or_null("/root/PlayerUI")
	if ui: ui.set_purple(true)

func _perform_attack(keycode: int) -> void:
	is_current_hit_leap = false  # Обычный удар
	var local_pos: Vector3
	var dir_name: String
	
	match keycode:
		KEY_1:
			local_pos = Vector3(0.0, 1.4, -0.8)
			dir_name = "ВЕРХ-ПЕРЕД"
		KEY_2:
			local_pos = Vector3(-1.1, 0.6, -0.8)
			dir_name = "ЛЕВО-ПЕРЕД"
		KEY_3:
			local_pos = Vector3(1.1, 0.6, -0.8)
			dir_name = "ПРАВО-ПЕРЕД"
		_: return

	print("⚔️ Удар: ", dir_name)
	_spawn_hitbox(local_pos)

func _spawn_hitbox(local_offset: Vector3) -> void:
	hit_registered = false
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # Ловит только слой 2 (враг)
	area.monitoring = true
	area.position = local_offset  # Дочерний узел: позиция локальная!

	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1.8, 1.8, 1.8) # Оптимальный размер зоны
	area.add_child(col)

	add_child(area)  # ✅ ПРИКРЕПЛЯЕМ К ИГРОКУ. Двигается/вращается вместе с ним.

	area.body_entered.connect(_on_hitbox_hit.bind(area), CONNECT_ONE_SHOT)
	await get_tree().physics_frame
	if not is_instance_valid(area): return

	# Проверяем, кто уже попал в зону (если стоишь вплотную)
	for body in area.get_overlapping_bodies():
		_on_hitbox_hit(body, area)

	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(area): area.queue_free()

func _on_hitbox_hit(body: Node, area: Area3D) -> void:
	if hit_registered or not is_instance_valid(area) or not is_instance_valid(body): return
	hit_registered = true
	
	var target: Node = body
	if not target.has_method("take_dmg"): target = target.get_parent()
	if target and target.has_method("take_dmg"):
		target.take_dmg(20.0)
		
		# 🔑 Обновляем UI в зависимости от типа атаки
		var ui = get_tree().root.get_node_or_null("PlayerUI") 
		if not ui: ui = get_tree().root.find_child("PlayerUI", true, false)
		if ui:
			if is_current_hit_leap:
				ui.set_purple(true)  # Фиолетовый за прыжок
			else:
				ui.add_gold_stack()  # Золотой за обычный удар
		is_current_hit_leap = false  # Сброс флага
	
	if is_instance_valid(area): area.queue_free()

func _on_bush_entered(body: Node3D) -> void:
	if body == self: is_stealthed = true; print("🌿 В засаде")
func _on_bush_exited(body: Node3D) -> void:
	if body == self: is_stealthed = false; print("🚶 Вышел из куста")

func take_dmg(amount: float) -> void:
	if hp <= 0.0: return
	hp -= amount
	print("🩸 ПОЛУЧЕН УРОН: ", int(amount), " | HP: ", int(hp))
	
	# Обновляем твой UI-бар
	var ui = get_tree().get_first_node_in_group("player_ui")
	if ui and ui.has_method("set_hp"):
		ui.set_hp(hp, max_hp)
		
	# Вспышка/звук (можно добавить позже, пока только консоль)
	if hp <= 0.0:
		print("💀 ИГРОК УБИТ")
		_death_restart()

func _death_restart() -> void:
	# Небольшая задержка, чтобы консоль успела вывести лог
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()
