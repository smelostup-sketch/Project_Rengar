extends Node
class_name CombatComponent

# === СИГНАЛЫ ===
signal attack_started(direction: String, is_leap_attack: bool)
signal attack_cancelled(reason: String)
signal attack_performed(direction: String, is_leap_attack: bool)
signal hit_detected(target: Node)
signal block_active_changed(is_active: bool)
signal stun_started(duration: float)

#сигналы анимации
signal damage_taken
signal lock_ended

# === НАСТРОЙКИ АТАКИ ИГРОКА ===
@export var attack_damage: float = 5.0
@export var hitbox_size: float = 1.8
# Layer 2 — враги; Layer 3 — будущие weapon/world blockers из группы attack_blocker.
@export var player_attack_collision_mask: int = 6
@export var hitbox_lifetime: float = 0.2
@export var recovery_duration: float = 0.3

# === НАСТРОЙКИ ВРАГА ===
@export var enemy_damage: float = 5.0
@export var enemy_hitbox_size: float = 2.5
@export var windup_duration: float = 1.0
@export var attack_delay_duration: float = 0.25
@export var knockback_force: float = 4.0

# проверка от гпт
var dmg_id := 0
# проверка от гпт
# === СОСТОЯНИЕ ИГРОКА ===
var hit_registered: bool = false
var active_player_hitbox: Area3D = null
var active_enemy_hitbox: Area3D = null
var last_attack_was_in_leap: bool = false
@export var debug_logging := true

var is_recovery: bool = false
var recovery_timer: float = 0.0
var is_input_locked: bool = false
var lock_timer: float = 0.0

# === СОСТОЯНИЕ ВРАГА ===
var ai_state: String = "IDLE"
var attack_dir: String = ""
var windup_timer: float = 0.0
var stun_timer: float = 0.0
var swing_timer: float = 0.0
var can_attack: bool = true
var attack_delay_timer: float = 0.0

# === ССЫЛКИ ===
var health_comp: HealthComponent = null
var state_comp: StateComponent = null
var owner_body: CharacterBody3D = null
var is_player: bool = false

var current_attack_dir: String = "UP"

@export_group("Block Settings")
@export var block_activation_time: float = 0.2      # Время удержания + движения мыши до активации
@export var block_active_duration: float = 0.5      # Длительность блока (синхронизируется с будущей анимацией)
@export var min_mouse_delta_block: float = 0.5      # Минимальный сдвиг мыши для активации

var is_block_input_held: bool = false
var block_activation_timer: float = 0.0
var block_active_timer: float = 0.0
var is_block_active: bool = false
var block_dir: String = "UP"
var block_mouse_acc: Vector2 = Vector2.ZERO
var block_activated_this_hold: bool = false # 🔑 Флаг фиксации: 1 нажатие = 1 блок

signal block_started(dir: String)
signal block_ended()

func _ready() -> void:
	var parent = get_parent()
	if not (parent is CharacterBody3D):
		push_error("CombatComponent должен быть дочерним узлом CharacterBody3D")
		return
	
	owner_body = parent as CharacterBody3D
	health_comp = owner_body.get_node_or_null("HealthComponent") as HealthComponent
	state_comp = owner_body.get_node_or_null("StateComponent") as StateComponent
	is_player = owner_body.is_in_group("player")

func _physics_process(delta: float) -> void:
	_update_block_timers(delta) # 🔑 ДОЛЖНО БЫТЬ ПЕРВЫМ
	_update_timers(delta)
	if is_player: _update_player(delta)
	else: _update_enemy(delta)

# === ДИАГНОСТИКА: ВИЗУАЛИЗАЦИЯ ХИТБОКСОВ ===
func _create_visual_hitbox(area: Area3D, size: Vector3, color: Color) -> void:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	area.add_child(mesh)

func _update_timers(delta: float) -> void:
	if is_recovery:
		recovery_timer -= delta
		if recovery_timer <= 0.0:
			is_recovery = false
	if is_input_locked:
		lock_timer -= delta
		if lock_timer <= 0.0:
			is_input_locked = false
			lock_ended.emit() # ✅ ДОБАВЛЕНО: теперь анимации узнают, что блок ввода снят
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0 and ai_state == "STUNNED":
			ai_state = "IDLE"
	if attack_delay_timer > 0.0:
		attack_delay_timer -= delta

func _update_player(_delta: float) -> void:
	pass

func _update_enemy(_delta: float) -> void:
	if ai_state == "WINDUP":
		windup_timer -= _delta
		if windup_timer <= 0.0:
			enemy_perform_attack()

# === ИГРОК: ПОДТВЕРЖДЁННАЯ НАПРАВЛЕННАЯ АТАКА ===
# Вызывается только AttackInputComponent после выбора направления и задержки.
# Он сохраняет владение вводом, а этот компонент сохраняет владение уроном
# и хитбоксом. Это разделение не допускает дублирования боевой механики.
func perform_directional_attack(direction: String, is_leap_attack: bool = false) -> bool:
	if not is_player or is_input_locked or is_block_active or is_recovery:
		_trace("ATTACK_REJECTED | reason=locked_or_recovery")
		return false
	if direction != "RIGHT" and direction != "LEFT" and direction != "UP":
		_trace("ATTACK_REJECTED | reason=invalid_direction | dir=" + direction)
		return false

	current_attack_dir = direction
	last_attack_was_in_leap = is_leap_attack
	var local_pos := _attack_local_position(direction)
	_trace("ATTACK_CONFIRMED | dir=%s | leap=%s" % [current_attack_dir, str(is_leap_attack)])
	attack_started.emit(current_attack_dir, is_leap_attack)
	attack_performed.emit(current_attack_dir, is_leap_attack)
	_spawn_player_hitbox(local_pos)

	is_recovery = true
	recovery_timer = recovery_duration
	return true

func cancel_player_attack(reason: String) -> void:
	# Легальная отмена: contact, валидный блок или валидный dash.
	# Обнуляется только боевой активный объект; velocity не изменяется.
	is_recovery = false
	recovery_timer = 0.0
	_clear_active_player_hitbox()
	_trace("ATTACK_CANCELLED | reason=" + reason)
	attack_cancelled.emit(reason)

func _attack_local_position(direction: String) -> Vector3:
	match direction:
		"UP": return Vector3(0.0, 1.4, -0.8)
		"LEFT": return Vector3(-1.1, 0.6, -0.8)
		"RIGHT": return Vector3(1.1, 0.6, -0.8)
	return Vector3.ZERO

func _spawn_player_hitbox(pos: Vector3) -> void:
	hit_registered = false
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = player_attack_collision_mask
	area.monitoring = true
	area.position = pos
	owner_body.add_child(area)
	active_player_hitbox = area
	_trace("PLAYER_HITBOX_SPAWNED | dir=%s | local_pos=%s" % [current_attack_dir, str(pos)])
	
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(hitbox_size, hitbox_size, hitbox_size)
	area.add_child(col)
	
	# 🔑 ВИЗУАЛИЗАЦИЯ
	_create_visual_hitbox(area, col.shape.size, Color(1, 0.2, 0.2, 0.3)) # Красный, 30% прозрачности
	
	area.body_entered.connect(_on_player_hitbox_hit.bind(area), CONNECT_ONE_SHOT)
	
	await get_tree().physics_frame
	if not is_instance_valid(area): return
	for body in area.get_overlapping_bodies():
		_on_player_hitbox_hit(body, area)
	
	await get_tree().create_timer(hitbox_lifetime).timeout
	if is_instance_valid(area): area.queue_free()

func _on_player_hitbox_hit(body: Node, area: Area3D) -> void:
	if hit_registered or not is_instance_valid(body):
		return
	if body == owner_body or body.is_in_group("player"):
		return

	# Будущий блок и парирование перехватывают удар до нанесения урона.
	if body.has_method("is_blocking_active") and body.is_blocking_active(current_attack_dir):
		hit_registered = true
		_trace("HITBOX_CONTACT | kind=block")
		cancel_player_attack("blocked")
		return

	# Объекты окружения и оружие противника добавляются в группу attack_blocker.
	if body.is_in_group("attack_blocker"):
		hit_registered = true
		_trace("HITBOX_CONTACT | kind=world_or_weapon | node=" + body.name)
		cancel_player_attack("world_or_weapon")
		return

	# Цель может быть коллайдером-дочерним узлом дамажащего тела.
	if not body.has_method("take_dmg") and body.get_parent() and body.get_parent().has_method("take_dmg"):
		body = body.get_parent()
	if not body.has_method("take_dmg"):
		return

	hit_registered = true
	_trace("HITBOX_CONTACT | kind=target | node=" + body.name)
	body.take_dmg(attack_damage, owner_body.global_position)
	hit_detected.emit(body)
	cancel_player_attack("hit_confirm")

func _clear_active_player_hitbox() -> void:
	if is_instance_valid(active_player_hitbox):
		active_player_hitbox.queue_free()
	active_player_hitbox = null

func get_debug_active_hitbox() -> Area3D:
	return active_player_hitbox if is_player else active_enemy_hitbox

func get_debug_direction() -> String:
	return current_attack_dir if is_player else attack_dir

func process_mouse_delta(motion: Vector2) -> void:
	# Накопление блока остаётся здесь; направленная атака обрабатывается
	# независимым AttackInputComponent.
	if is_block_input_held and not is_block_active:
		block_mouse_acc += motion

func is_blocking_active(enemy_attack_dir: String) -> bool:
	if not is_block_active: return false
	return (block_dir == "UP" and enemy_attack_dir == "UP") or \
		   (block_dir == "LEFT" and enemy_attack_dir == "RIGHT") or \
		   (block_dir == "RIGHT" and enemy_attack_dir == "LEFT") or \
		   (block_dir == "DOWN" and enemy_attack_dir == "DOWN")

# === ИГРОК: ПОЛУЧЕНИЕ УРОНА ===
func player_take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	dmg_id += 1
	_trace("PLAYER_DAMAGE | id=%d | amount=%.1f" % [dmg_id, amount])
	# HitReact и блокировка ввода не должны оставлять AttackInputComponent
	# навсегда в ATTACKING; это устраняет срыв следующих нажатий ЛКМ.
	cancel_player_attack("damage_interrupt")
	if health_comp:
		health_comp.take_dmg(amount, attacker_pos)
	damage_taken.emit()
	if attacker_pos != Vector3.ZERO and owner_body:
		var dir: Vector3 = (owner_body.global_position - attacker_pos).normalized()
		owner_body.velocity += dir * 3.0
	is_input_locked = true
	lock_timer = 0.1
	print("🔒 ВВОД ЗАЛОКИРОВАН НА 0.1С | ОТКАТ")

# === ВРАГ: АТАКА ===
func enemy_start_attack() -> void:
	var dirs: Array = ["UP", "LEFT", "RIGHT"]
	attack_dir = dirs[randi_range(0, 2)]
	ai_state = "WINDUP"
	windup_timer = windup_duration
	# Визуальная телеграфия запускается вместе с существующим WINDUP.
	# Сам хитбокс остаётся в enemy_perform_attack() и не переносится.
	attack_started.emit(attack_dir, false)

func enemy_perform_attack() -> void:
	ai_state = "SWING"
	swing_timer = 0.3
	# Визуальная точка начала взмаха; хитбокс вызывается в той же строке,
	# что и раньше, поэтому тайминг и механика удара не меняются.
	attack_performed.emit(attack_dir, false)
	_enemy_spawn_hitbox()

func _enemy_spawn_hitbox() -> void:
	var local_offset: Vector3
	if attack_dir == "UP": local_offset = Vector3(0.0, 1.2, 0.5)
	elif attack_dir == "LEFT": local_offset = Vector3(-1.0, 0.8, 0.5)
	elif attack_dir == "RIGHT": local_offset = Vector3(1.0, 0.8, 0.5)
	else: return

	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	owner_body.add_child(area)
	area.position = local_offset
	active_enemy_hitbox = area
	_trace("ENEMY_HITBOX_SPAWNED | dir=%s | local_pos=%s" % [attack_dir, str(local_offset)])

	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(enemy_hitbox_size, enemy_hitbox_size, enemy_hitbox_size)
	area.add_child(col)

	_create_visual_hitbox(area, col.shape.size, Color(0.2, 0.4, 1, 0.3))

	await get_tree().physics_frame
	if not is_instance_valid(area): return

	for body in area.get_overlapping_bodies():
		if not is_instance_valid(body): continue
		if body.has_method("is_blocking_active") and body.is_blocking_active(attack_dir):
			enemy_on_block()
			break # 🔑 ИЗМЕНИЛИ return НА break
		elif body.has_method("take_dmg"):
			body.take_dmg(enemy_damage, owner_body.global_position)
			break # 🔑 Аналогично для урона

	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(area): area.queue_free()
	if active_enemy_hitbox == area:
		active_enemy_hitbox = null

	can_attack = true
	ai_state = "IDLE"

func enemy_on_block() -> void:
	_trace("ENEMY_ATTACK_CONTACT | kind=block | dir=" + attack_dir)
	apply_stun(0.5)
	can_attack = true
	ai_state = "IDLE"

func enemy_on_take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if attack_delay_timer > 0.05:
		return
	attack_delay_timer = attack_delay_duration
	# Успешный блок уже испускал stun_started; обычный урон ранее не
	# отправлял анимационного сигнала. Добавляем только визуальную реакцию.
	damage_taken.emit()
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		var knock_dir: Vector3 = (owner_body.global_position - player.global_position).normalized()
		owner_body.velocity = knock_dir * knockback_force
		_trace("ENEMY_DAMAGE_REACTION | knockback=" + str(knock_dir))

func apply_stun(duration: float) -> void:
	stun_timer = duration
	ai_state = "STUNNED"
	stun_started.emit(duration)
	_trace("ENEMY_STUN | duration=%.2fs" % duration)
	
func _finalize_block() -> void:
	var x = block_mouse_acc.x
	var y = block_mouse_acc.y
	if abs(y) > abs(x) and abs(y) > min_mouse_delta_block:
		block_dir = "UP" if y < 0 else "DOWN"
	elif abs(x) > min_mouse_delta_block:
		block_dir = "LEFT" if x < 0 else "RIGHT"
	else:
		block_dir = "UP"
		
	is_block_active = true
	block_active_timer = 0.0
	block_activated_this_hold = true # 🔑 Блокируем повторную активацию до отпускания
	block_mouse_acc = Vector2.ZERO   # 🔑 Очищаем накопленную дельту
	block_started.emit(block_dir)
	block_active_changed.emit(true)
	_trace("BLOCK_ACTIVATED | dir=" + block_dir)

func set_block_input_pressed() -> void:
	_trace("BLOCK_INPUT_PRESSED")
	is_block_input_held = true
	block_activated_this_hold = false # 🔑 Разрешаем новую активацию
	block_activation_timer = 0.0
	block_mouse_acc = Vector2.ZERO

func set_block_input_released() -> void:
	_trace("BLOCK_INPUT_RELEASED")
	is_block_input_held = false
	block_activation_timer = 0.0
	block_mouse_acc = Vector2.ZERO
	if not is_block_active:
		block_active_changed.emit(false)
		
func _update_block_timers(delta: float) -> void:
	if is_block_active:
		block_active_timer += delta
		if block_active_timer >= block_active_duration:
			is_block_active = false
			block_active_timer = 0.0
			block_ended.emit()
			block_active_changed.emit(false)
			_trace("BLOCK_FINISHED | reason=duration")
		return

	# Активация возможна только один раз на удержание кнопки блока.
	if is_block_input_held and not block_activated_this_hold:
		block_activation_timer += delta
		if block_activation_timer >= block_activation_time and block_mouse_acc.length() >= min_mouse_delta_block:
			_finalize_block()
	elif block_activation_timer > 0.0:
		block_activation_timer = 0.0

func _trace(message: String) -> void:
	if debug_logging:
		print("[Combat] ", message)
