extends CharacterBody3D

@export var chase_speed: float = 3.0
@export var detection_range: float = 8.0
@export var stop_distance: float = 1.5
@export var gravity: float = 20.0

@export_group("Adaptive Utility AI")
@export var utility_ai_enabled := true
@export var retreat_speed_multiplier := 0.65

@export_group("Character Speed")
@export_range(0.1, 3.0, 0.05) var character_speed_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.0

@onready var health_comp: HealthComponent = $HealthComponent
@onready var state_comp: StateComponent = $StateComponent
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var utility_ai: EnemyUtilityAIComponent = $EnemyUtilityAIComponent
@onready var animation_comp: EnemyAnimationComponent = $AnimationComponent

var player: Node3D = null
var telegraph_label: Label3D = null
var hp_bar: MeshInstance3D = null

func _ready() -> void:
	if state_comp:
		state_comp.movement_speed_multiplier = character_speed_multiplier
	if animation_comp:
		animation_comp.movement_animation_speed = character_speed_multiplier
		animation_comp.attack_animation_speed = attack_animation_speed
		animation_comp.apply_runtime_speeds()
	_create_enemy_hp_bar()
	_create_telegraph_label()
	if health_comp:
		health_comp.hp_changed.connect(_on_hp_changed)
		health_comp.died.connect(_on_enemy_died)

func _physics_process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player): return

	# 1️⃣ ГРАВИТАЦИЯ (Применяем ВСЕГДА до move_and_slide, чтобы враг не парил в стане/откате)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# 2️⃣ ПРИОРИТЕТНЫЕ СОСТОЯНИЯ (Стан, Откат)
	if combat_comp.stun_timer > 0.0:
		velocity.x = 0.0; velocity.z = 0.0 # Гасим только горизонталь
		move_and_slide()
		_update_enemy_indicator()
		_update_enemy_hp_bar()
		return
	elif combat_comp.ai_state == "STUNNED":
		combat_comp.ai_state = "IDLE"

	if combat_comp.attack_delay_timer > 0.0:
		move_and_slide()
		_update_enemy_indicator()
		_update_enemy_hp_bar()
		return

	if combat_comp.enemy_block_active:
		if not utility_ai_enabled or utility_ai == null or not utility_ai.wants_block():
			combat_comp.deactivate_enemy_block()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_update_enemy_indicator()
			_update_enemy_hp_bar()
			_update_telegraph_visibility()
			return

	# 3️⃣ ЛОГИКА ИИ + СТЕЛС. Utility AI выбирает только намерение; урон,
	# windup, swing, стан и физика остаются в существующих компонентах.
	var dist = global_position.distance_to(player.global_position)
	var player_is_stealthed = false
	if player.has_node("StateComponent"):
		player_is_stealthed = player.get_node("StateComponent").is_stealthed
	var utility_is_active := utility_ai_enabled and utility_ai != null and utility_ai.is_operational()
	
	if combat_comp.ai_state not in ["WINDUP", "ATTACK", "SWING", "STUNNED"]:
		if dist > detection_range or player_is_stealthed:
			combat_comp.ai_state = "IDLE"
		elif utility_is_active:
			match utility_ai.update(delta):
				EnemyUtilityAIComponent.Decision.APPROACH:
					combat_comp.ai_state = "CHASE"
				EnemyUtilityAIComponent.Decision.HOLD, EnemyUtilityAIComponent.Decision.ATTACK:
					combat_comp.ai_state = "STOPPED"
				EnemyUtilityAIComponent.Decision.RETREAT:
					combat_comp.ai_state = "RETREAT"
		else:
			# Без нового компонента сохраняется прежнее поведение прототипа.
			combat_comp.ai_state = "CHASE" if dist > stop_distance else "STOPPED"
	
	# Поворот к игроку
	if combat_comp.ai_state not in ["ATTACK", "SWING"] and is_instance_valid(player):
		var dir = player.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			global_rotation.y = lerp_angle(global_rotation.y, atan2(dir.x, dir.z), 0.35)
	
	# 4️⃣ ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ (не трогаем Y!)
	if combat_comp.ai_state == "CHASE":
		var chase_dir = (player.global_position - global_position).normalized()
		chase_dir.y = 0.0
		velocity.x = chase_dir.x * chase_speed * character_speed_multiplier
		velocity.z = chase_dir.z * chase_speed * character_speed_multiplier
		combat_comp.can_attack = true
	elif combat_comp.ai_state == "RETREAT":
		var retreat_dir := utility_ai.get_retreat_direction() if utility_is_active else Vector3.ZERO
		velocity.x = retreat_dir.x * chase_speed * retreat_speed_multiplier * character_speed_multiplier
		velocity.z = retreat_dir.z * chase_speed * retreat_speed_multiplier * character_speed_multiplier
	elif combat_comp.ai_state == "STOPPED":
		velocity.x = 0.0
		velocity.z = 0.0
		if utility_is_active and utility_ai.wants_block():
			combat_comp.activate_enemy_block(utility_ai.get_recommended_block_direction())
		elif combat_comp.can_attack and dist <= 3.0:
			var player_leaping = player.has_node("StateComponent") and player.get_node("StateComponent").is_leaping
			if not player_leaping and (not utility_is_active or utility_ai.wants_attack()):
				var attack_direction := utility_ai.get_recommended_attack_direction() if utility_is_active else ""
				combat_comp.enemy_start_attack(attack_direction)
				combat_comp.can_attack = false
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# 5️⃣ ФИЗИКА GODOT
	move_and_slide()

	_update_enemy_indicator()
	_update_enemy_hp_bar()
	_update_telegraph_visibility()

func _on_hp_changed(_current: float, _max_hp: float) -> void:
	_update_enemy_hp_bar()

func _on_enemy_died() -> void:
	print("☠️ СМЕРТЬ ВРАГА")
	queue_free()

func is_blocking_active(player_attack_direction: String) -> bool:
	return combat_comp != null and combat_comp.is_blocking_active(player_attack_direction)

# 🔑 ДЕЛЕГАТ УРОНА С ВИЗУАЛЬНЫМИ ЭФФЕКТАМИ
func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if health_comp and health_comp.is_dead:
		return
	if combat_comp and combat_comp.attack_delay_timer > 0.05:
		return
	_play_hit_flash()
	_spawn_damage_label(int(amount))
	_play_impact_sound()
	_spawn_impact_particles()
	if health_comp:
		health_comp.take_dmg(amount, attacker_pos)
	if combat_comp:
		combat_comp.enemy_on_take_dmg(amount, attacker_pos)

func _create_enemy_hp_bar() -> void:
	hp_bar = MeshInstance3D.new()
	hp_bar.name = "EnemyHPBar"
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.05)
	hp_bar.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar.material_override = mat
	hp_bar.position = Vector3(0, 2.4, 0)
	add_child(hp_bar)

func _update_enemy_hp_bar() -> void:
	if not hp_bar or not health_comp:
		return
	var ratio = health_comp.get_hp_ratio()
	var box = hp_bar.mesh as BoxMesh
	if box:
		box.size.x = 0.6 * ratio
	var cam = get_viewport().get_camera_3d()
	if cam:
		hp_bar.global_rotation.y = cam.global_rotation.y

func _create_telegraph_label() -> void:
	telegraph_label = Label3D.new()
	telegraph_label.name = "TelegraphLabel"
	telegraph_label.font_size = 40
	telegraph_label.outline_size = 3
	telegraph_label.no_depth_test = true
	telegraph_label.position = Vector3(0, 2.8, 0)
	telegraph_label.visible = false
	add_child(telegraph_label)

func _show_telegraph() -> void:
	if not telegraph_label or combat_comp.attack_dir == "":
		return
	if combat_comp.attack_dir == "UP":
		telegraph_label.text = "↑"
	elif combat_comp.attack_dir == "LEFT":
		telegraph_label.text = "←"
	elif combat_comp.attack_dir == "RIGHT":
		telegraph_label.text = "→"
	telegraph_label.visible = true
	var cam = get_viewport().get_camera_3d()
	if cam:
		telegraph_label.global_rotation.y = cam.global_rotation.y

func _hide_telegraph() -> void:
	if telegraph_label:
		telegraph_label.visible = false

func _update_telegraph_visibility() -> void:
	if combat_comp.ai_state == "WINDUP":
		_show_telegraph()
	else:
		_hide_telegraph()
	if telegraph_label and telegraph_label.visible:
		var cam = get_viewport().get_camera_3d()
		if cam:
			telegraph_label.global_rotation.y = cam.global_rotation.y

func _update_enemy_indicator() -> void:
	if not has_node("StateLabel"):
		var lbl = Label3D.new()
		lbl.name = "StateLabel"
		lbl.font_size = 32
		lbl.outline_size = 2
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 2.6, 0)
		add_child(lbl)
	var lbl = get_node("StateLabel")
	if combat_comp.enemy_block_active:
		lbl.text = "🛡️"
	elif combat_comp.stun_timer > 0.0:
		lbl.text = "💫"
	elif combat_comp.ai_state == "WINDUP":
		lbl.text = "⚡"
	else:
		if combat_comp.ai_state == "IDLE":
			lbl.text = "❓"
		elif combat_comp.ai_state == "CHASE":
			lbl.text = "❗"
		elif combat_comp.ai_state == "STOPPED":
			lbl.text = "🛑"
	var cam = get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y

func _play_hit_flash() -> void:
	var enemy_visual := get_node_or_null("EnemyVisual")
	if enemy_visual == null:
		return

	var meshes := enemy_visual.find_children("", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return

	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0.2, 0.2)

	var original_materials: Array[Material] = []
	var valid_meshes: Array[MeshInstance3D] = []
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		valid_meshes.append(mesh)
		original_materials.append(mesh.material_override)
		mesh.material_override = flash_mat

	await get_tree().create_timer(0.15).timeout
	for index in valid_meshes.size():
		var mesh := valid_meshes[index]
		if is_instance_valid(mesh):
			mesh.material_override = original_materials[index]

func _spawn_damage_label(val: int) -> void:
	var lbl = Label3D.new()
	lbl.text = str(val)
	lbl.font_size = 28
	lbl.outline_size = 3
	lbl.modulate = Color(1, 0.3, 0.3)
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

func _play_impact_sound() -> void:
	var audio_player = AudioStreamPlayer.new()
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 44100
	audio_player.stream = stream
	add_child(audio_player)
	audio_player.play()
	await get_tree().process_frame
	var playback = audio_player.get_stream_playback()
	if playback:
		var buffer: PackedVector2Array = []
		for i in range(2205):
			var t = float(i) / 2205.0
			var vol = (1.0 - t) * 0.4
			buffer.append(Vector2(randf_range(-vol, vol), randf_range(-vol, vol)))
		playback.push_buffer(buffer)
	await get_tree().create_timer(0.1).timeout
	audio_player.queue_free()

func _spawn_impact_particles() -> void:
	for i in range(5):
		var p = MeshInstance3D.new()
		p.mesh = BoxMesh.new()
		p.mesh.size = Vector3(0.15, 0.15, 0.15)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.2, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p.material_override = mat
		get_tree().root.add_child(p)
		p.global_position = global_position + Vector3(randf_range(-0.5,0.5), randf_range(0.8,1.5), randf_range(-0.5,0.5))
		var vel = Vector3(randf_range(-3,3), randf_range(2,5), randf_range(-3,3))
		var tw = create_tween()
		tw.tween_property(p, "position", p.position + vel * 0.4, 0.4).set_trans(Tween.TRANS_EXPO)
		tw.parallel().tween_property(p, "material_override:albedo_color", Color(1,0.2,0.2,0.0), 0.4)
		tw.finished.connect(p.queue_free)
