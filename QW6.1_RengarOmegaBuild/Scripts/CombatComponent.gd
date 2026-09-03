extends Node
class_name CombatComponent

# === СИГНАЛЫ ===
signal attack_started(direction: String, is_leap_attack: bool)
signal attack_cancelled(reason: String)
signal attack_finished()
signal attack_performed(direction: String, is_leap_attack: bool)
signal hit_detected(target: Node)
signal block_active_changed(is_active: bool)
signal stun_started(duration: float)

#сигналы анимации
signal damage_taken
signal lock_ended

# === НАСТРОЙКИ АТАКИ ИГРОКА ===
@export var attack_damage: float = 5.0
# Layer 2 — враги; Layer 3 — будущие weapon/world blockers из группы attack_blocker.
@export var player_attack_collision_mask: int = 6
@export var recovery_duration: float = 0.3

# === НАСТРОЙКИ ВРАГА ===
@export var enemy_damage: float = 5.0
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
var active_player_hitboxes: Array[Area3D] = []
var active_enemy_hitboxes: Array[Area3D] = []
var weapon_hitboxes: Array[Area3D] = []
var weapon_hitbox_shapes: Array[CollisionShape3D] = []
var weapon_hitbox_generation: int = 0
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

@export_group("Enemy Block")
@export var enemy_block_enabled := true
@export var enemy_block_duration := 1.0
var enemy_block_active := false
var enemy_block_timer := 0.0
var enemy_block_dir := "UP"

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
var block_success_audio: AudioStreamPlayer3D = null

signal block_started(dir: String)
signal block_ended()
signal block_successful(defender: String, direction: String)

func _ready() -> void:
	var parent = get_parent()
	if not (parent is CharacterBody3D):
		push_error("CombatComponent должен быть дочерним узлом CharacterBody3D")
		return
	
	owner_body = parent as CharacterBody3D
	health_comp = owner_body.get_node_or_null("HealthComponent") as HealthComponent
	state_comp = owner_body.get_node_or_null("StateComponent") as StateComponent
	block_success_audio = owner_body.get_node_or_null("BlockSuccessAudio") as AudioStreamPlayer3D
	is_player = owner_body.is_in_group("player")

	# Оружие создаётся один раз в сцене. LEFT/RIGHT используют свою руку,
	# верхний удар активирует оба заранее размещённых Area3D.
	var attachment_prefix := "Player" if is_player else "Enemy"
	for hand_name in ["Right", "Left"]:
		var attachment_name := attachment_prefix + "WeaponAttachment" if hand_name == "Right" else attachment_prefix + "LeftWeaponAttachment"
		var static_hitbox_path := NodePath(attachment_name + "/Sword/WeaponHitbox")
		var static_hitbox := owner_body.get_node_or_null(static_hitbox_path) as Area3D
		if static_hitbox == null:
			push_warning("CombatComponent: не найден статический WeaponHitbox по пути " + str(static_hitbox_path) + " - возможно, ещё не загружен")
			continue
		var static_shape := static_hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if static_shape == null:
			push_warning("CombatComponent: в статическом WeaponHitbox нет CollisionShape3D")
			continue
		weapon_hitboxes.append(static_hitbox)
		weapon_hitbox_shapes.append(static_shape)
		static_hitbox.set_deferred("monitoring", false)
		static_hitbox.set_deferred("monitorable", false)
		static_shape.set_deferred("disabled", true)
		static_hitbox.body_entered.connect(_on_static_weapon_hitbox_body_entered)
	
	if weapon_hitboxes.is_empty():
		push_error("CombatComponent: не найдено ни одного WeaponHitbox!")

func _physics_process(delta: float) -> void:
	_update_block_timers(delta) # 🔑 ДОЛЖНО БЫТЬ ПЕРВЫМ
	_update_timers(delta)
	if is_player: _update_player(delta)
	else: _update_enemy(delta)

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
	_trace("ATTACK_CONFIRMED | dir=%s | leap=%s | hitbox=AnimationPlayerTrack" % [current_attack_dir, str(is_leap_attack)])
	attack_started.emit(current_attack_dir, is_leap_attack)
	attack_performed.emit(current_attack_dir, is_leap_attack)

	is_recovery = true
	recovery_timer = recovery_duration
	return true

func cancel_player_attack(reason: String) -> void:
	# Легальная отмена: contact, валидный блок или валидный dash.
	# Обнуляется только боевой активный объект; velocity не изменяется.
	is_recovery = false
	recovery_timer = 0.0
	# Safety shutdown for an interrupted clip; normal enable/disable comes only
	# from AnimationPlayer Call Method Track.
	animation_disable_weapon_hitbox()
	_trace("ATTACK_CANCELLED | reason=" + reason)
	attack_cancelled.emit(reason)

# === СТАТИЧЕСКИЙ HITBOX МЕЧА ===
# Эти public method вызываются Method Track в AttackLeft/Right/Up.
# Area3D создан один раз в сцене как дочерний узел BoneAttachment3D меча.
func animation_enable_weapon_hitbox() -> void:
	if weapon_hitboxes.size() < 2:
		_trace("WEAPON_HITBOX_ENABLE_REJECTED | reason=missing_static_area")
		return
	weapon_hitbox_generation += 1
	var activation_generation := weapon_hitbox_generation
	hit_registered = false
	active_player_hitboxes.clear()
	active_enemy_hitboxes.clear()
	var selected_hitboxes := _get_hitboxes_for_attack(get_debug_direction())
	for index in weapon_hitboxes.size():
		var should_enable := weapon_hitboxes[index] in selected_hitboxes
		weapon_hitboxes[index].set_deferred("monitoring", should_enable)
		weapon_hitboxes[index].set_deferred("monitorable", should_enable)
		weapon_hitbox_shapes[index].set_deferred("disabled", not should_enable)
		if should_enable:
			if is_player:
				active_player_hitboxes.append(weapon_hitboxes[index])
			else:
				active_enemy_hitboxes.append(weapon_hitboxes[index])
	if is_player:
		active_player_hitbox = active_player_hitboxes[0] if not active_player_hitboxes.is_empty() else null
	else:
		active_enemy_hitbox = active_enemy_hitboxes[0] if not active_enemy_hitboxes.is_empty() else null
	_trace("WEAPON_HITBOX_ENABLED | owner=" + owner_body.name + " | dir=" + get_debug_direction() + " | count=" + str(selected_hitboxes.size()))
	_scan_static_weapon_hitboxes_after_activation(activation_generation)

func animation_disable_weapon_hitbox() -> void:
	if weapon_hitboxes.is_empty():
		return
	weapon_hitbox_generation += 1
	for index in weapon_hitboxes.size():
		weapon_hitboxes[index].set_deferred("monitoring", false)
		weapon_hitboxes[index].set_deferred("monitorable", false)
		weapon_hitbox_shapes[index].set_deferred("disabled", true)
	active_player_hitboxes.clear()
	active_enemy_hitboxes.clear()
	active_player_hitbox = null
	active_enemy_hitbox = null
	_trace("WEAPON_HITBOX_DISABLED | owner=" + owner_body.name)

func _get_hitboxes_for_attack(direction: String) -> Array[Area3D]:
	if direction == "UP":
		return weapon_hitboxes.duplicate()
	if direction == "LEFT" and weapon_hitboxes.size() > 1:
		return [weapon_hitboxes[1]]
	return [weapon_hitboxes[0]]

func _scan_static_weapon_hitboxes_after_activation(activation_generation: int) -> void:
	await get_tree().physics_frame
	if activation_generation != weapon_hitbox_generation:
		return
	_scan_static_weapon_hitboxes()

func _scan_static_weapon_hitboxes() -> void:
	var hitboxes := active_player_hitboxes if is_player else active_enemy_hitboxes
	for hitbox in hitboxes:
		if not is_instance_valid(hitbox) or not hitbox.monitoring:
			continue
		for body in hitbox.get_overlapping_bodies():
			_on_static_weapon_hitbox_body_entered(body)
			if hit_registered:
				return

func _on_static_weapon_hitbox_body_entered(body: Node3D) -> void:
	if is_player:
		_on_player_weapon_hitbox_body_entered(body)
	else:
		_on_enemy_weapon_hitbox_body_entered(body)

func _on_player_weapon_hitbox_body_entered(body: Node) -> void:
	if hit_registered or not is_instance_valid(body):
		return
	if body == owner_body or body.is_in_group("player"):
		return
	if body.has_method("is_blocking_active") and body.is_blocking_active(current_attack_dir):
		hit_registered = true
		_trace("HITBOX_CONTACT | kind=block")
		if body.has_method("notify_successful_block"):
			body.notify_successful_block(current_attack_dir)
		cancel_player_attack("blocked")
		return
	if body.is_in_group("attack_blocker"):
		hit_registered = true
		_trace("HITBOX_CONTACT | kind=world_or_weapon | node=" + body.name)
		cancel_player_attack("world_or_weapon")
		return
	if not body.has_method("take_dmg") and body.get_parent() and body.get_parent().has_method("take_dmg"):
		body = body.get_parent()
	if not body.has_method("take_dmg"):
		return
	hit_registered = true
	_trace("HITBOX_CONTACT | kind=target | node=" + body.name)
	body.take_dmg(attack_damage, owner_body.global_position)
	hit_detected.emit(body)
	cancel_player_attack("hit_confirm")

func _on_enemy_weapon_hitbox_body_entered(body: Node) -> void:
	if hit_registered or not is_instance_valid(body):
		return
	if body == owner_body or body.is_in_group("enemy"):
		return
	# Враги игнорируют манекенов (dummy_enemy) - не атакуют их
	if body.is_in_group("dummy_enemy"):
		return
	if body.has_method("is_blocking_active") and body.is_blocking_active(attack_dir):
		hit_registered = true
		if body.has_method("notify_successful_block"):
			body.notify_successful_block(attack_dir)
		enemy_on_block()
		_trace("HITBOX_CONTACT | kind=block")
		return
	if body.has_method("take_dmg"):
		hit_registered = true
		body.take_dmg(enemy_damage, owner_body.global_position)
		hit_detected.emit(body)

func get_debug_active_hitbox() -> Area3D:
	return active_player_hitbox if is_player else active_enemy_hitbox

func get_debug_active_hitboxes() -> Array[Area3D]:
	return active_player_hitboxes.duplicate() if is_player else active_enemy_hitboxes.duplicate()

func get_debug_direction() -> String:
	return current_attack_dir if is_player else attack_dir

func process_mouse_delta(motion: Vector2) -> void:
	# Накопление блока остаётся здесь; направленная атака обрабатывается
	# независимым AttackInputComponent.
	if is_block_input_held and not is_block_active:
		block_mouse_acc += motion

func notify_successful_block(direction: String) -> void:
	if block_success_audio != null and is_instance_valid(block_success_audio):
		block_success_audio.play()
	block_successful.emit("PLAYER" if is_player else "ENEMY", direction)
	_trace("BLOCK_SUCCESS | defender=%s | dir=%s" % ["PLAYER" if is_player else "ENEMY", direction])

func is_blocking_active(enemy_attack_dir: String) -> bool:
	if is_player:
		if not is_block_active: return false
		return _directions_are_blocked(block_dir, enemy_attack_dir)
	if not enemy_block_active: return false
	return _directions_are_blocked(enemy_block_dir, enemy_attack_dir)

func activate_enemy_block(block_direction: String = "UP") -> bool:
	if is_player or not enemy_block_enabled or owner_body == null:
		return false
	if ai_state in ["WINDUP", "SWING", "STUNNED"]:
		return false
	enemy_block_dir = block_direction if block_direction in ["UP", "LEFT", "RIGHT"] else "UP"
	enemy_block_active = true
	enemy_block_timer = enemy_block_duration
	_trace("ENEMY_BLOCK_ACTIVATED | dir=" + enemy_block_dir)
	return true

func deactivate_enemy_block() -> void:
	if not enemy_block_active:
		return
	enemy_block_active = false
	enemy_block_timer = 0.0
	_trace("ENEMY_BLOCK_ENDED")

func _directions_are_blocked(defense_direction: String, attack_direction: String) -> bool:
	return (defense_direction == "UP" and attack_direction == "UP") or \
		   (defense_direction == "LEFT" and attack_direction == "RIGHT") or \
		   (defense_direction == "RIGHT" and attack_direction == "LEFT") or \
		   (defense_direction == "DOWN" and attack_direction == "DOWN")

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
	if attacker_pos != Vector3.ZERO and is_instance_valid(owner_body) and owner_body.is_inside_tree():
		var dir: Vector3 = (owner_body.global_position - attacker_pos).normalized()
		owner_body.velocity += dir * 3.0
	is_input_locked = true
	lock_timer = 0.1
	print("🔒 ВВОД ЗАЛОКИРОВАН НА 0.1С | ОТКАТ")

# === ВРАГ: АТАКА ===
func enemy_start_attack(recommended_direction: String = "") -> void:
	var dirs: Array = ["UP", "LEFT", "RIGHT"]
	attack_dir = recommended_direction if recommended_direction in dirs else dirs[randi_range(0, 2)]
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
	# Включение и выключение статического Area3D выполняют только Method Track
	# фактически проигрываемого Attack*-клипа.
	_finish_enemy_attack_after_existing_duration()

func _finish_enemy_attack_after_existing_duration() -> void:
	# Сохраняет прежнюю AI-длину SWING и не управляет monitoring Area3D.
	await get_tree().create_timer(0.15).timeout
	can_attack = true
	ai_state = "IDLE"

func enemy_on_block() -> void:
	_trace("ENEMY_ATTACK_CONTACT | kind=block | dir=" + attack_dir)
	animation_disable_weapon_hitbox()
	apply_stun(0.5)
	can_attack = true
	ai_state = "IDLE"

func enemy_on_take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	# Проверка на прерывание атаки только если враг не в состоянии атаки (WINDUP/SWING)
	# Это предотвращает ложное прерывание атаки при получении урона во время WINDUP или SWING
	if ai_state not in ["WINDUP", "SWING"] and attack_delay_timer > 0.05:
		return
	
	# Если враг уже в процессе атаки (WINDUP или SWING), не прерываем её получением урона
	# Атака будет завершена нормально, а откат начнётся после завершения
	if ai_state in ["WINDUP", "SWING"]:
		_trace("ENEMY_DAMAGE_DURING_ATTACK | ignoring delay timer")
		# Не устанавливаем attack_delay_timer, чтобы не прерывать атаку
	else:
		attack_delay_timer = attack_delay_duration
	
	# Полученный урон прерывает visual attack; статический Area3D должен
	# выключиться, даже если clip не дошёл до своего disable Method Track.
	animation_disable_weapon_hitbox()
	# Успешный блок уже испускал stun_started; обычный урон ранее не
	# отправлял анимационного сигнала. Добавляем только визуальную реакцию.
	damage_taken.emit()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null and is_instance_valid(player) and is_instance_valid(owner_body) and owner_body.is_inside_tree() and player.is_inside_tree():
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
	if not is_player and enemy_block_active:
		enemy_block_timer -= delta
		if enemy_block_timer <= 0.0:
			deactivate_enemy_block()
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
		# ПКМ без отдельного жеста использует защиту UP; движение мыши
		# по-прежнему позволяет выбрать LEFT/RIGHT/UP.
		if block_activation_timer >= block_activation_time:
			_finalize_block()
	elif block_activation_timer > 0.0:
		block_activation_timer = 0.0

func _trace(message: String) -> void:
	if debug_logging:
		print("[Combat] ", message)
