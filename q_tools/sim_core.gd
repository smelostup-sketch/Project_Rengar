extends SceneTree
## Детерминированные проверки единого боевого ядра (Q_2).
## Враг и игрок идут через один perform_directional_attack; проверяются:
## гард recovery, спам-устойчивость, окно хитбокса, отмена уроном, lock,
## темп recovery игрока (0.15) и врага (2.0).

var log_f: FileAccess
var frame := 0
var t0 := 0
var enemy: CharacterBody3D
var player: CharacterBody3D
var ecc: Node
var pcc: Node
var passed := 0
var failed := 0
var d := {}


func check(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + name)
	else:
		failed += 1
		log_f.store_line("FAIL " + name)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		log_f = FileAccess.open("res://q_tools/sim_core_out.txt", FileAccess.WRITE)
		var scn := load("res://Основная_сцена.tscn") as PackedScene
		var inst := scn.instantiate()
		root.add_child(inst)
		enemy = inst.get_node("EnemyCharacterBody3D")
		player = inst.get_node("PLayerCharacterBody3D")
		ecc = enemy.get_node("CombatComponent")
		pcc = player.get_node("CombatComponent")
		# Изоляция ядра: автономное поведение контроллера врага выключено.
		enemy.set_physics_process(false)
		t0 = Time.get_ticks_msec()
		return false
	var t := (Time.get_ticks_msec() - t0) / 1000.0
	var hb_r := enemy.get_node("EnemyWeaponAttachment/Sword/WeaponHitbox") as Area3D
	if not d.has("a1") and t >= 0.2:
		d["a1"] = true
		check("enemy perform accepted from idle", ecc.perform_directional_attack("RIGHT", false) == true)
	if not d.has("a2") and t >= 0.25:
		d["a2"] = true
		check("repeat during recovery rejected", ecc.perform_directional_attack("LEFT", false) == false)
	if t >= 0.3 and t < 1.9:
		if not d.has("spam_acc"):
			d["spam_acc"] = 0
		if ecc.perform_directional_attack("UP", false):
			d["spam_acc"] = int(d["spam_acc"]) + 1
	if not d.has("spam_end") and t >= 1.9:
		d["spam_end"] = true
		check("spam 0.3..1.9s: 0 accepted", int(d.get("spam_acc", 0)) == 0)
	if not d.has("win") and hb_r.monitoring:
		d["win"] = t
	if d.has("win") and not d.has("win_end") and not hb_r.monitoring and t > float(d["win"]) + 0.05:
		d["win_end"] = t
		var rel0: float = float(d["win"]) - 0.2
		var rel1: float = t - 0.2
		check("enemy hitbox window ~0.38..1.92s (got %.2f..%.2f)" % [rel0, rel1],
			rel0 > 0.30 and rel0 < 0.50 and rel1 > 1.70 and rel1 < 2.10)
	if not d.has("a3") and t >= 2.3:
		d["a3"] = true
		check("enemy can attack again after recovery 2.0", ecc.perform_directional_attack("UP", false) == true)
	if not d.has("dmg") and t >= 2.8:
		d["dmg"] = true
		ecc.enemy_on_take_dmg(5.0, player.global_position)
		check("damage cancels attack (single path)", ecc.is_recovery == false)
		check("damage locks input", ecc.is_input_locked == true)
	if not d.has("dmg2") and t >= 2.9:
		d["dmg2"] = true
		check("perform right after damage rejected", ecc.perform_directional_attack("LEFT", false) == false)
	if not d.has("dmg3") and t >= 3.3:
		d["dmg3"] = true
		check("perform accepted after lock ends", ecc.perform_directional_attack("LEFT", false) == true)
	if not d.has("p1") and t >= 3.8:
		d["p1"] = true
		check("player perform accepted", pcc.perform_directional_attack("LEFT", false) == true)
	if not d.has("p2") and t >= 3.85:
		d["p2"] = true
		check("player repeat rejected", pcc.perform_directional_attack("LEFT", false) == false)
	if not d.has("p3") and t >= 4.0:
		d["p3"] = true
		check("player re-attack after 0.15s recovery", pcc.perform_directional_attack("RIGHT", false) == true)
	if frame == 900:
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	return false
