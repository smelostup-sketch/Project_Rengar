extends Node
class_name StateComponent

signal state_changed(state_name: String, value: bool)

# === ДВИЖЕНИЕ ===
@export var speed: float = 6.0
@export var acceleration: float = 10.0
@export var deceleration: float = 15.0
var combat_comp: CombatComponent = null
var attack_input_comp: AttackInputComponent = null

# === ФИЗИКА И ПРЫЖКИ ===
@export var gravity: float = 20.0
@export var jump_force: float = 8.0
@export var leap_range: float = 12.0
@export var invert_forward_input: bool = false
const FACING_THRESHOLD: float = 0.98

# === НАСТРОЙКИ ПРЫЖКА (В ИНСПЕКТОРЕ) ===
@export var leap_time_to_target: float = 0.45   # Секунды полёта до цели (постоянное время)
@export var min_leap_speed: float = 6.0         # Мин. скорость (короткие дистанции)
@export var max_leap_speed: float = 8.0         # Макс. скорость (длинные дистанции, баланс)
@export var leap_max_range: float = 10.0        # Макс. дистанция срабатывания засады

@export var jump_floor_tolerance: float = 2.5   # Допуск "почти на земле". Убирает 1-кадровые отмены прыжка
@export var landing_damping: float = 10.0       # Сила гашения вертикальной скорости при приземлении. Больше = резче, меньше = мягче

var is_stealthed: bool = false
var is_leaping: bool = false
# Точки расширения для будущих систем. Пока прототип не запускает эти режимы,
# но AttackInputComponent уже учитывает их в правилах допустимости блока.
var is_climbing: bool = false
var is_swimming: bool = false
var leap_intended_dir: Vector3 = Vector3.ZERO
var jump_requested: bool = false

var owner_body: CharacterBody3D = null
var my_instance_id: int = 0
var was_on_floor: bool = false

# === УКЛОНЕНИЯ И РЫВКИ ===
enum ActionType { NONE, DODGE, DASH }

@export_group("Dodge & Dash Settings")
@export var dodge_speed: float = 12.0
@export var dodge_duration: float = 0.2
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.15
@export var double_tap_window: float = 0.25

var is_dodging: bool = false
var is_dashing: bool = false
var action_timer: float = 0.0
var action_dir: Vector2 = Vector2.ZERO
var action_velocity_xz: Vector2 = Vector2.ZERO # 🔑 ТОЛЬКО X/Z. Y НИКОГДА НЕ ТРОГАЕМ

@export var action_exit_deceleration: float = 36.0
var _is_action_recovering: bool = false # Короткое плавное торможение после dodge/dash.

# Фрейм-буфер
var _prev_w: bool = false; var _prev_a: bool = false
var _prev_s: bool = false; var _prev_d: bool = false
var _prev_q: bool = false; var _prev_e: bool = false
var _last_tap_time: float = 0.0
var _last_tap_key: int = -1

signal action_started(dir: Vector2, type: ActionType)
signal action_ended

func process(delta: float) -> void:
	# 1. Тик активного действия
	if is_dodging or is_dashing:
		action_timer -= delta
		if action_timer <= 0.0:
				is_dodging = false
				is_dashing = false
				# Не обнуляем скорость за один кадр: это и было источником рывка.
				_is_action_recovering = true
				action_ended.emit()
		return # Ввод игнорируется до завершения

	# 2. Edge Detection
	var w = Input.is_key_pressed(KEY_W)
	var a = Input.is_key_pressed(KEY_A)
	var s = Input.is_key_pressed(KEY_S)
	var d = Input.is_key_pressed(KEY_D)

	var just_w = w and not _prev_w
	var just_a = a and not _prev_a
	var just_s = s and not _prev_s
	var just_d = d and not _prev_d
	var just_q = Input.is_key_pressed(KEY_Q) and not _prev_q
	var just_e = Input.is_key_pressed(KEY_E) and not _prev_e

	_prev_w = w; _prev_a = a; _prev_s = s; _prev_d = d
	_prev_q = Input.is_key_pressed(KEY_Q); _prev_e = Input.is_key_pressed(KEY_E)

	# 3. Блокировка старта
	if not _can_start_action(): return

	# 4. ДИСКРЕТНАЯ МАТРИЦА (0 хардкода координат)
	# sign() превращает зажатие в (-1, 0, 1). Получаем ровно 8 клеток вокруг центра
	var raw_x: float = 0.0; var raw_y: float = 0.0
	if w: raw_y -= 1.0
	if s: raw_y += 1.0
	if a: raw_x -= 1.0
	if d: raw_x += 1.0

	var grid_dir = Vector2.ZERO
	if raw_x != 0.0 or raw_y != 0.0:
		grid_dir = Vector2(sign(raw_x), sign(raw_y)).normalized()
	else:
		grid_dir = Vector2(0.0, -1.0) # Fallback: вперёд

	# 5. Dodge (Q/E как модификаторы направления к WASD)
	if just_q or just_e:
		# Считываем базу (WASD)
		var base_wasd = Vector2.ZERO
		if Input.is_key_pressed(KEY_W): base_wasd.y -= 1.0
		if Input.is_key_pressed(KEY_S): base_wasd.y += 1.0
		if Input.is_key_pressed(KEY_A): base_wasd.x -= 1.0
		if Input.is_key_pressed(KEY_D): base_wasd.x += 1.0

		# Если WASD не нажат, нажатие Q/E игнорируется.
		if base_wasd != Vector2.ZERO:
			if not _can_start_mobility_action("DODGE"):
				return
			# Во время START_DELAY или ATTACKING dodge не запускается и не
			# отменяет текущую атаку.
			if attack_input_comp and attack_input_comp.blocks_dodge_start():
				print("[State] DODGE_REJECTED | reason=attack_active | attack_state=", attack_input_comp.get_state_name())
				return
			if attack_input_comp:
				attack_input_comp.cancel_pending_direction_for_dodge()
			var dodge_input = base_wasd

			# Q и E выступают как модификаторы по оси X.
			if Input.is_key_pressed(KEY_Q): dodge_input.x -= 1.0
			if Input.is_key_pressed(KEY_E): dodge_input.x += 1.0
			dodge_input = dodge_input.normalized()
			print("[State] DODGE_STARTED | input=", dodge_input)
			_start_action(dodge_input, ActionType.DODGE)
			return

	# 6. Dash (Double Tap)
	var current_key = -1
	if just_w: current_key = KEY_W
	elif just_a: current_key = KEY_A
	elif just_s: current_key = KEY_S
	elif just_d: current_key = KEY_D

	if current_key != -1:
		var now = Time.get_ticks_msec() * 0.001
		if current_key == _last_tap_key and (now - _last_tap_time) < double_tap_window:
			# Dash всегда один из четырёх направлений double-tap, даже если
			# в этот момент зажата другая кнопка WASD.
			var dash_dir: Vector2
			match current_key:
				KEY_W: dash_dir = Vector2(0.0, -1.0)
				KEY_A: dash_dir = Vector2(-1.0, 0.0)
				KEY_S: dash_dir = Vector2(0.0, 1.0)
				KEY_D: dash_dir = Vector2(1.0, 0.0)
				_: dash_dir = Vector2(0.0, -1.0)
			if not _can_start_mobility_action("DASH"):
				_last_tap_time = 0.0
				_last_tap_key = -1
				return
			# Dash — разрешённый cancel атаки. Он отменяет атаку только если
			# сам dash проходит все контекстные проверки.
			if attack_input_comp:
				attack_input_comp.request_dash_cancel()
			print("[State] DASH_STARTED | input=", dash_dir)
			_start_action(dash_dir, ActionType.DASH)
			_last_tap_time = 0.0
			_last_tap_key = -1
			return
		_last_tap_time = now
		_last_tap_key = current_key

func _can_start_action() -> bool:
	# Block сохраняет прежний запрет на движение-действие. Recovery атаки больше
	# не блокирует dash: сам dash является утверждённой отменой атаки.
	if combat_comp and combat_comp.is_block_active:
		return false
	return true

func _can_start_mobility_action(action_name: String) -> bool:
	# Взаимная блокировка: действие нельзя начать, пока активен второй тип.
	if is_dodging or is_dashing:
		print("[State] %s_REJECTED | reason=mobility_action_active" % action_name)
		return false
	# Обычный прыжок и падение определяются через is_on_floor(); боевой прыжок
	# дополнительно маркируется is_leaping. В обоих случаях action запрещён.
	if owner_body == null or is_leaping or not owner_body.is_on_floor():
		print("[State] %s_REJECTED | reason=airborne" % action_name)
		return false
	return true

func _start_action(dir: Vector2, type: ActionType) -> void:
	var action_name := "DODGE" if type == ActionType.DODGE else "DASH"
	if not _can_start_mobility_action(action_name):
		return
	_is_action_recovering = false
	if type == ActionType.DODGE:
		# 🔒 ИЗОЛИРОВАННЫЙ ПУТЬ ДОДЖА (Дэш не затронут)
		is_dodging = true
		is_dashing = false
		action_timer = dodge_duration

		# Камера-относительный вектор: 8 направлений, чёткая нормализация
		var world_dir = owner_body.global_transform.basis * Vector3(dir.x, 0.0, dir.y)
		world_dir.y = 0.0
		if world_dir.length() > 0.001: world_dir = world_dir.normalized()

		action_velocity_xz = Vector2(world_dir.x, world_dir.z) * dodge_speed
		action_started.emit(dir, type)
		return

	# =================================================================
	# 🔒 ДЭШ: ОСТАВЛЯЕМ КАК БЫЛО (НИКАКИХ ПРАВОК)
	# =================================================================
	is_dashing = true
	is_dodging = false
	action_timer = dash_duration

	var global_dir = owner_body.global_transform.basis * Vector3(dir.x, 0.0, dir.y)
	global_dir.y = 0.0
	if global_dir.length() > 0.001: global_dir = global_dir.normalized()

	var spd = dash_speed
	action_velocity_xz = Vector2(global_dir.x, global_dir.z) * spd
	action_started.emit(dir, type)
	
func _ready() -> void:
	var parent = get_parent()
	if not (parent is CharacterBody3D):
		push_error("StateComponent должен быть потомком CharacterBody3D")
		return
	_last_tap_time = -999.0
	_last_tap_key = -1
	
	owner_body = parent as CharacterBody3D
	my_instance_id = owner_body.get_instance_id()
	combat_comp = owner_body.get_node_or_null("CombatComponent")
	attack_input_comp = owner_body.get_node_or_null("AttackInputComponent") as AttackInputComponent
	_connect_bush_signals()
	was_on_floor = owner_body.is_on_floor() # 🔑 Инициализация кэша (убирает холодный старт)

func _connect_bush_signals() -> void:
	for bush in owner_body.get_tree().get_nodes_in_group("bush"):
		if bush is Area3D:
			# Защита от дублей при перезагрузке
			if bush.body_entered.is_connected(_on_bush_entered):
				bush.body_entered.disconnect(_on_bush_entered)
			if bush.body_exited.is_connected(_on_bush_exited):
				bush.body_exited.disconnect(_on_bush_exited)
			
			bush.body_entered.connect(_on_bush_entered)
			bush.body_exited.connect(_on_bush_exited)

func _on_bush_entered(body: Node3D) -> void:
	# Сравниваем по instance_id — это надёжнее чем ==
	print("🔍 Bush enter: body_id=", body.get_instance_id(), " my_id=", my_instance_id)
	if body.get_instance_id() == my_instance_id:
		set_stealthed(true)

func _on_bush_exited(body: Node3D) -> void:
	if body.get_instance_id() == my_instance_id:
		set_stealthed(false)

func set_stealthed(value: bool) -> void:
	if is_stealthed != value:
		is_stealthed = value
		state_changed.emit("stealth", value)
		print("🌿 Стелс: ", "ВКЛ" if value else "ВЫКЛ")

func set_leaping(value: bool) -> void:
	if is_leaping != value:
		is_leaping = value
		if value:
			# При прыжке выходим из стелса
			set_stealthed(false)
		state_changed.emit("leap", value)

# === ГЕТТЕРЫ ДЛЯ ДРУГИХ СКРИПТОВ ===
func get_is_stealthed() -> bool:
	return is_stealthed

func get_is_leaping() -> bool:
	return is_leaping

func get_leap_direction() -> Vector3:
	return leap_intended_dir.normalized()

func reset_jump_request() -> void:
	jump_requested = false

func apply_physics(delta: float) -> void:
	if owner_body == null:
		return

	# Точная постоянная скорость только внутри активного dash/dodge.
	if is_dodging or is_dashing:
		owner_body.velocity.x = action_velocity_xz.x
		owner_body.velocity.z = action_velocity_xz.y
		apply_gravity(delta)
		return

	if is_leaping or (combat_comp and combat_comp.is_input_locked):
		apply_gravity(delta)
		return

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0

	var horizontal_rate := action_exit_deceleration if _is_action_recovering else acceleration
	var desired_horizontal_speed := 0.0
	if input_dir == Vector3.ZERO:
		var braking_rate := action_exit_deceleration if _is_action_recovering else deceleration
		owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, braking_rate * delta)
		owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, braking_rate * delta)
	else:
		input_dir = input_dir.normalized()
		var target_dir := owner_body.global_transform.basis * input_dir
		target_dir.y = 0.0
		target_dir = target_dir.normalized()
		var target_vel := target_dir * speed
		desired_horizontal_speed = speed
		owner_body.velocity.x = move_toward(owner_body.velocity.x, target_vel.x, horizontal_rate * delta)
		owner_body.velocity.z = move_toward(owner_body.velocity.z, target_vel.z, horizontal_rate * delta)

	# После выхода из действия восстанавливаем стандартные acceleration/deceleration,
	# когда скорость уже близка к обычной целевой скорости.
	if _is_action_recovering:
		var current_horizontal_speed := Vector2(owner_body.velocity.x, owner_body.velocity.z).length()
		if absf(current_horizontal_speed - desired_horizontal_speed) <= 0.10:
			_is_action_recovering = false

	apply_gravity(delta)

func apply_gravity(delta: float) -> void:
	if owner_body == null: return

	if not owner_body.is_on_floor():
		owner_body.velocity.y -= gravity * delta
	else:
		if owner_body.velocity.y < 0.0:
			owner_body.velocity.y = move_toward(owner_body.velocity.y, 0.0, landing_damping * delta)

	# 🔑 завершение leap ТОЛЬКО по факту "почти остановки"
	if is_leaping and owner_body.is_on_floor() and abs(owner_body.velocity.y) < 1.0:
		set_leaping(false)
		_check_bush_overlap()

func process_jump_request() -> void:
	if not jump_requested or is_leaping or owner_body == null:
		return

	if not was_on_floor and owner_body.is_on_floor() == false:
		jump_requested = false
		return

	var target_enemy = _find_nearest_enemy()
	var can_leap = false

	if is_stealthed and target_enemy:
		var forward = -owner_body.global_transform.basis.z.normalized()
		if invert_forward_input:
			forward = -forward

		var dir_to_enemy = (target_enemy.global_position - owner_body.global_position).normalized()

		if forward.dot(dir_to_enemy) > FACING_THRESHOLD:
			can_leap = true

	if can_leap and target_enemy.global_position.distance_to(owner_body.global_position) <= leap_max_range:
		_start_ambush(target_enemy)
	else:
		owner_body.velocity.y = jump_force

	jump_requested = false

# 🔑 Новый метод: вызывается ПОСЛЕ move_and_slide() в Player3D
func cache_floor_state() -> void:
	was_on_floor = owner_body.is_on_floor()

func _find_nearest_enemy() -> Node3D:
	var enemies = owner_body.get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var min_dist: float = leap_range + 1.0
	for e in enemies:
		var d = owner_body.global_position.distance_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest = e as Node3D
	return nearest

func _start_ambush(target: Node3D) -> void:
	set_stealthed(false)
	set_leaping(true)

	var dir = (target.global_position - owner_body.global_position)
	dir.y = 0.0

	leap_intended_dir = dir.normalized()

	var dist = dir.length()
	var target_speed = dist / leap_time_to_target
	target_speed = clamp(target_speed, min_leap_speed, max_leap_speed)

	owner_body.velocity.x = leap_intended_dir.x * target_speed
	owner_body.velocity.z = leap_intended_dir.z * target_speed
	owner_body.velocity.y = jump_force

func _check_bush_overlap() -> void:
	for bush in owner_body.get_tree().get_nodes_in_group("bush"):
		if bush is Area3D and bush.overlaps_body(owner_body):
			set_stealthed(true)
			return
