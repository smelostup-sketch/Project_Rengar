extends SceneTree
## Замер лого-спама: 60 отклонённых намерений подряд от провайдера.
var frame := 0
var enemy: CharacterBody3D
var done := false

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		var scn := load("res://Основная_сцена.tscn") as PackedScene
		var inst := scn.instantiate()
		root.add_child(inst)
		enemy = inst.get_node("EnemyCharacterBody3D")
		return false
	if frame == 30 and not done:
		done = true
		var cc := enemy.get_node("CombatComponent")
		cc.perform_directional_attack("RIGHT", false)  # принято -> recovery
		for i in 60:
			cc.perform_directional_attack("LEFT", false)  # все отклонены
	if frame == 60:
		print("SPAMTEST DONE")
		quit(0)
		return true
	return false
