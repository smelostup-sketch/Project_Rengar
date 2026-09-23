extends CharacterBody3D

@export var max_hp: float = 100.0
var hp: float = max_hp

func take_dmg(amount: float) -> void:
	if hp <= 0.0: return
	hp -= amount
	print("💀 Урон: ", int(amount), " | HP: ", int(hp), " / ", int(max_hp))
	_play_hit_flash()
	_spawn_damage_label(int(amount))
	_play_impact_sound()
	_spawn_impact_particles()
	if hp <= 0.0:
		print("☠️ Враг убит")
		queue_free()

func _play_hit_flash() -> void:
	var mesh = get_node_or_null("VisualCube")
	if not mesh: mesh = find_child("MeshInstance3D")
	if not mesh: return

	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0.2, 0.2)
	mesh.set_surface_override_material(0, flash_mat)

	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(mesh):
		mesh.set_surface_override_material(0, null)

func _spawn_damage_label(val: int) -> void:
	var lbl = Label3D.new()
	lbl.text = str(val)
	lbl.font_size = 28
	lbl.outline_size = 3
	lbl.modulate = Color(1, 0.3, 0.3)
	lbl.position = Vector3(0, 1.0, 0)
	lbl.no_depth_test = true
	add_child(lbl)
	
	var cam = get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y
		
	var tw = create_tween()
	tw.parallel().tween_property(lbl, "position:y", 2.8, 0.6).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.finished.connect(lbl.queue_free)

# 🔊 НОВЫЙ ЗВУК (процедурный шум)
func _play_impact_sound() -> void:
	var player = AudioStreamPlayer.new()
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 44100
	player.stream = stream
	add_child(player)
	player.play()
	
	await get_tree().process_frame  # Даем движку инициализировать поток
	var playback = player.get_stream_playback()
	if playback:
		var buffer: PackedVector2Array = []
		for i in range(2205):  # ~50мс звука
			var t = float(i) / 2205.0
			var vol = (1.0 - t) * 0.4  # Затухание
			var sample = randf_range(-vol, vol)
			buffer.append(Vector2(sample, sample))
		playback.push_buffer(buffer)
		
	await get_tree().create_timer(0.1).timeout
	player.queue_free()

# 📦 НОВЫЕ ЧАСТИЦЫ (мелкие красные кубики)
func _spawn_impact_particles() -> void:
	for i in range(5):
		var particle = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.15, 0.15, 0.15)
		particle.mesh = mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.2, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 🔑 Включаем альфа-канал
		particle.material_override = mat
		
		particle.position = Vector3(
			randf_range(-0.5, 0.5),
			randf_range(0.8, 1.5),
			randf_range(-0.5, 0.5)
		)
		add_child(particle)
		
		var velocity = Vector3(
			randf_range(-3, 3),
			randf_range(2, 5),
			randf_range(-3, 3)
		)
		
		var tween = create_tween()
		tween.tween_property(particle, "position", particle.position + velocity * 0.4, 0.4).set_trans(Tween.TRANS_EXPO)
		# 🔑 Меняем альфу через материал, а не через modulate
		tween.parallel().tween_property(particle, "material_override:albedo_color", Color(1, 0.2, 0.2, 0.0), 0.4)
		tween.finished.connect(particle.queue_free)
