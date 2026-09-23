extends SceneTree
## Сим врага: перезапуски атак и реакция на урон во время атаки.
## Лог: res://q_tools/sim_enemy_out.txt (события + состояние каждые 20 итераций).

var frame := 0
var enemy: CharacterBody3D = null
var player: CharacterBody3D = null
var log_f: FileAccess = null
var t0 := 0
var n_started := 0
var n_performed := 0
var last_performed_ms := -99999
var restarts := 0
var last_clip := ""


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_enemy_out.txt", FileAccess.WRITE)


func _on_started(dir: String, _leap: bool) -> void:
	n_started += 1
	log_f.store_line("EVT t=%.2f attack_started dir=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dir])


func _on_performed(dir: String, _leap: bool) -> void:
	n_performed += 1
	var now := Time.get_ticks_msec()
	if now - last_performed_ms < 1000:
		restarts += 1
		log_f.store_line("EVT t=%.2f RESTART (<1s after prev perform) dir=%s" % [(now - t0) / 1000.0, dir])
	last_performed_ms = now
	log_f.store_line("EVT t=%.2f attack_performed dir=%s" % [(now - t0) / 1000.0, dir])


func _setup() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if enemy == null or player == null:
		log_f.store_line("SIMENEMY FAIL nodes")
		log_f.close()
		quit(1)
	player.global_position = enemy.global_position + Vector3(0.0, -2.0, 0.0)
	var bush := inst.get_node_or_null("Bush")
	if bush != null:
		bush.global_position = Vector3(100.0, 0.0, 100.0)
	var cc := enemy.get_node("CombatComponent")
	cc.attack_started.connect(_on_started)
	cc.attack_performed.connect(_on_performed)
	t0 = Time.get_ticks_msec()


var pin_pos := Vector3.ZERO


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
	if frame == 2:
		# open-ground teleport: враг из спавна в арке -> на открытое место к игроку
		enemy.global_position = player.global_position + Vector3(0.0, 2.0, 0.0)
		pin_pos = player.global_position
	if frame < 2:
		return false
	var cc := enemy.get_node("CombatComponent")
	var vp := enemy.get_node("EnemyVisual/AnimationPlayer") as AnimationPlayer
	if frame == 500:
		if enemy.has_method("take_dmg"):
			enemy.take_dmg(5.0, player.global_position)
			log_f.store_line("EVT t=%.2f DAMAGE_TO_ENEMY (mid-attack? state=%s)" % [(Time.get_ticks_msec() - t0) / 1000.0, str(cc.get("ai_state"))])
	if frame > 2:
		player.global_position = pin_pos
		player.velocity = Vector3.ZERO
	if frame % 20 == 0 and frame <= 1500:
		var clip := str(vp.current_animation)
		if clip.begins_with("Attack") and last_clip.begins_with("Attack") and clip != last_clip:
			log_f.store_line("EVT t=%.2f CLIP_REPLACED %s -> %s pos=%.2f" % [(Time.get_ticks_msec() - t0) / 1000.0, last_clip, clip, vp.current_animation_position])
		last_clip = clip
		var util := enemy.get_node("EnemyUtilityAIComponent")
		var stc := player.get_node("StateComponent")
		log_f.store_line("ST t=%.2f state=%-8s can_atk=%d clip=%-11s pos=%.2f dist=%.2f stealth=%d dec=%s op=%d" % [
			(Time.get_ticks_msec() - t0) / 1000.0, str(cc.get("ai_state")),
			1 if cc.get("can_attack") else 0, clip, vp.current_animation_position,
			enemy.global_position.distance_to(player.global_position),
			1 if stc.get("is_stealthed") else 0, str(util.get_decision_name()),
			1 if util.is_operational() else 0])
	if frame == 1500:
		log_f.store_line("SUMMARY started=%d performed=%d restarts_lt1s=%d" % [n_started, n_performed, restarts])
		log_f.close()
		quit(0)
		return true
	return false
