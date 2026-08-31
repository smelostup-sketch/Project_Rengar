extends CharacterBody3D

@onready var health_comp: HealthComponent = $HealthComponent
@onready var state_comp: StateComponent = $StateComponent
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var attack_input_comp: AttackInputComponent = $AttackInputComponent
@onready var stacks_comp: StacksComponent = $StacksComponent
@onready var animation_comp: MixamoAnimationComponent = $AnimationComponent

@export_group("Character Speed")
@export_range(0.1, 3.0, 0.05) var character_speed_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.25

func _ready() -> void:
	if state_comp:
		state_comp.movement_speed_multiplier = character_speed_multiplier
	if animation_comp:
		animation_comp.movement_animation_speed = character_speed_multiplier
		animation_comp.attack_animation_speed = attack_animation_speed
		animation_comp.apply_runtime_speeds()
	print("✅ НОВАЯ АРХИТЕКТУРА LOADED")
	if health_comp:
		health_comp.hp_changed.connect(_on_hp_changed)
		health_comp.died.connect(_on_player_died)
	if combat_comp:
		combat_comp.hit_detected.connect(_on_hit_detected)

func _physics_process(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("is_free_look_active") and cam.is_free_look_active():
		rotation.y = lerp_angle(rotation.y, cam.get_view_yaw(), 12.0 * delta)

	# 1. INPUT & STATE (решает ЧТО делать)
	state_comp.process(delta)
	
	# 2. JUMP (задаёт Y импульс до физики)
	state_comp.process_jump_request()
	
	# 3. PHYSICS (применяет X/Z override/движение + ВСЕГДА гравитацию)
	state_comp.apply_physics(delta)
	
	# 4. PHYSICS STEP (разрешает коллизии, обновляет floor state)
	move_and_slide()
	
	# 5. FLOOR CACHE (готовит was_on_floor для СЛЕДУЮЩЕГО кадра)
	state_comp.cache_floor_state()
	
	# 6. POST-PHYSICS (только для раннего сброса прыжка при ударе)
	if state_comp.is_leaping and get_slide_collision_count() > 0:
		state_comp.set_leaping(false)
		velocity *= 0.4

func _input(event: InputEvent) -> void:
	# 1. Движение мыши (идёт всегда, распределяется внутри компонента).
	if event is InputEventMouseMotion:
		attack_input_comp.process_mouse_delta(event.relative)
		combat_comp.process_mouse_delta(event.relative)
		return

	# 2. Клавиатура: пробел — прыжок. Тильда обрабатывается камерой.
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_SPACE and event.pressed:
			state_comp.jump_requested = true
		return

	# 3. Мышь: ЛКМ — атака, ПКМ — блок.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if attack_input_comp.request_block():
					combat_comp.set_block_input_pressed()
			else:
				combat_comp.set_block_input_released()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				attack_input_comp.press_attack()
			else:
				attack_input_comp.release_attack()

# === ДЕЛЕГАТЫ (НЕ УДАЛЯТЬ) ===
func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	stacks_comp.register_combat_event() # 🔑 Получение урона = бой
	if combat_comp: combat_comp.player_take_dmg(amount, attacker_pos)

func is_blocking_active(enemy_attack_dir: String) -> bool:
	return combat_comp.is_blocking_active(enemy_attack_dir)

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

func _on_hp_changed(current: float, max_hp: float) -> void:
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("player_ui")
	if ui and ui.has_method("set_hp"): ui.set_hp(current, max_hp)

func _on_player_died() -> void:
	print("💀 ИГРОК УБИТ")
	set_process(false); set_physics_process(false)
	get_tree().reload_current_scene()

func _on_hit_detected(_target: Node) -> void:
	stacks_comp.register_combat_event() # 🔑 Нанесение урона = бой
	if combat_comp.last_attack_was_in_leap:
		stacks_comp.add_purple()
	else:
		stacks_comp.add_gold()
	combat_comp.last_attack_was_in_leap = false
