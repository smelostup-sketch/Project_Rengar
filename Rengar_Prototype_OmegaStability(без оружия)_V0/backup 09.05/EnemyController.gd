extends CharacterBody3D

@export var max_hp: float = 100.0
@export var chase_speed: float = 3.0
@export var detection_range: float = 8.0
@export var stop_distance: float = 2.5
@export var gravity: float = 20.0

var hp: float = max_hp
var player: Node3D = null
var ai_state: String = "IDLE"
var hp_bar: MeshInstance3D = null  # 🔑 ИСПРАВЛЕНО: тип под 3D

func _ready():
	_create_enemy_hp_bar()

func _physics_process(delta):
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if not player: return

	var dist = global_position.distance_to(player.global_position)
	var is_stealthed = "is_stealthed" in player and player.is_stealthed

	if dist <= detection_range and not is_stealthed:
		ai_state = "CHASE" if dist > stop_distance else "STOPPED"
	else:
		ai_state = "IDLE"

	match ai_state:
		"CHASE":
			var dir = player.global_position - global_position
			dir.y = 0.0
			global_rotation.y = atan2(dir.x, dir.z)
			velocity.x = dir.normalized().x * chase_speed
			velocity.z = dir.normalized().z * chase_speed
		_:
			velocity.x = 0.0
			velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	
	if global_position.y < 0.05:
		global_position.y = 0.05
		velocity.y = 0.0

	_update_enemy_indicator()
	_update_enemy_hp_bar()

# 🔑 3D HP-БАР (вместо 2D ColorRect)
func _create_enemy_hp_bar() -> void:
	hp_bar = MeshInstance3D.new()
	hp_bar.name = "EnemyHPBar"
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.05)  # Ширина, Высота, Глубина
	hp_bar.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.2)
	mat.unshaded = true  # Не зависит от освещения
	hp_bar.material_override = mat
	
	hp_bar.position = Vector3(0, 2.4, 0)
	add_child(hp_bar)

func _update_enemy_hp_bar() -> void:
	if not hp_bar: return
	var ratio = clamp(hp / max_hp, 0.0, 1.0)
	var box = hp_bar.mesh as BoxMesh
	if box: box.size.x = 0.6 * ratio  # Укорачиваем бар по ширине
	
	var cam = get_viewport().get_camera_3d()
	if cam: hp_bar.global_rotation.y = cam.global_rotation.y

func take_dmg(amount: float):
	if hp <= 0.0: return
	hp -= amount
	print("💀 Урон: ", int(amount), " | HP: ", int(hp))
	_play_hit_flash()
	_spawn_damage_label(int(amount))
	_play_impact_sound()
	_spawn_impact_particles()
	_update_enemy_hp_bar()
	if hp <= 0.0:
		print("☠️ Враг убит")
		queue_free()

func _play_hit_flash() -> void:
	var mesh = find_child("MeshInstance3D", true, false)
	if not mesh: return
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0.2, 0.2)
	mesh.set_surface_override_material(0, flash_mat)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(mesh): mesh.set_surface_override_material(0, null)

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
	if cam: lbl.global_rotation.y = cam.global_rotation.y
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
	match ai_state:
		"IDLE": lbl.text = "❓"
		"CHASE": lbl.text = "❗"
		"STOPPED": lbl.text = "👁️"

	var cam = get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y
