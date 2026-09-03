extends CharacterBody3D

@export_group("Dummy Enemy Settings")
@export var block_chance := 0.95  # 95% шанс заблокировать атаку
@export var dummy_color := Color(1.0, 1.0, 0.0, 1.0)  # Желтый цвет

@onready var health_comp: HealthComponent = $HealthComponent
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var state_comp: StateComponent = $StateComponent
@onready var animation_comp: EnemyAnimationComponent = $AnimationComponent
@onready var model_tint: ModelTintComponent = $ModelTintComponent

var player: Node3D = null

func _ready() -> void:
	# Устанавливаем желтый цвет модели
	if model_tint:
		model_tint.set_tint(dummy_color)
	
	# Применяем цвет к HP бару если есть
	_create_dummy_hp_bar()
	
	# Манекен не должен иметь гравитации и движения
	velocity = Vector3.ZERO
	
	print("🛡️ Манекен-тренировочный создан (желтый, блок 95%)")

func _physics_process(delta: float) -> void:
	# Манекен никогда не двигается
	velocity = Vector3.ZERO
	move_and_slide()
	
	# Обновляем индикатор состояния
	_update_dummy_indicator()

func _create_dummy_hp_bar() -> void:
	var hp_bar = MeshInstance3D.new()
	hp_bar.name = "DummyHPBar"
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.05)
	hp_bar.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0)  # Желтый HP бар
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar.material_override = mat
	hp_bar.position = Vector3(0, 2.4, 0)
	add_child(hp_bar)

func _update_dummy_indicator() -> void:
	if not has_node("StateLabel"):
		var lbl = Label3D.new()
		lbl.name = "StateLabel"
		lbl.font_size = 32
		lbl.outline_size = 2
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 2.6, 0)
		lbl.modulate = Color(1.0, 1.0, 0.0, 1.0)  # Желтый текст
		add_child(lbl)
	
	var lbl = get_node("StateLabel")
	if lbl:
		if combat_comp and combat_comp.enemy_block_active:
			lbl.text = "🛡️"
		else:
			lbl.text = "🎯"  # Манекен готов к тренировке
		
		# Поворот к камере
		var cam = get_viewport().get_camera_3d()
		if cam:
			lbl.global_rotation.y = cam.global_rotation.y

func is_blocking_active(player_attack_direction: String) -> bool:
	# Манекен блокирует с высоким шансом
	if combat_comp == null:
		return false
	
	# 95% шанс блока
	if randf() < block_chance:
		combat_comp.activate_enemy_block(_get_random_block_direction())
		return combat_comp.is_blocking_active(player_attack_direction)
	
	return false

func _get_random_block_direction() -> String:
	var directions = ["LEFT", "RIGHT", "UP"]
	return directions[randi() % directions.size()]

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	# Манекен получает урон только если не заблокировал
	if is_blocking_active(""):
		notify_successful_block("")
		print("🛡️ Манекен заблокировал атаку!")
		return
	
	if health_comp and not health_comp.is_dead:
		_spawn_damage_label(int(amount))
		health_comp.take_dmg(amount, attacker_pos)
		print("💥 Манекен получил урон: ", amount)

func _spawn_damage_label(val: int) -> void:
	var lbl = Label3D.new()
	lbl.text = str(val)
	lbl.font_size = 28
	lbl.outline_size = 3
	lbl.modulate = Color(1.0, 0.3, 0.3)
	lbl.no_depth_test = true
	get_tree().root.add_child(lbl)
	lbl.global_position = global_position + Vector3(0, 1.0, 0)
	var cam = get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y
	var tw = create_tween()
	tw.parallel().tween_property(lbl, "position:y", 2.8, 0.6).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.finished.connect(lbl.queue_free)
