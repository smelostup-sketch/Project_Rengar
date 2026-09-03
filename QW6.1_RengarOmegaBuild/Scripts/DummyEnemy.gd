extends CharacterBody3D
class_name DummyEnemy

## Второй противник-манекен: не атакует, очень хорошо блокирует атаки игрока.
## Противник игнорирует манекена. Манекен желтого цвета и не передвигается.

@export var block_chance: float = 0.95 # 95% шанс заблокировать атаку
@export var block_direction: String = "UP"

var health_comp: HealthComponent = null
var combat_comp: CombatComponent = null

func _ready() -> void:
	health_comp = $HealthComponent as HealthComponent
	combat_comp = $CombatComponent as CombatComponent
	
	# Устанавливаем желтый цвет модели
	_set_model_color(Color(1.0, 1.0, 0.0, 1.0))
	
	# Добавляем в группу dummy_enemy для игнорирования ИИ врагов
	add_to_group("dummy_enemy")
	
	if health_comp:
		health_comp.hp_changed.connect(_on_hp_changed)
	
	print("✅ MANEKEN DUMMY LOADED | Yellow Blocker")

func _physics_process(_delta: float) -> void:
	# Манекен НЕ двигается вообще
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * _delta
	move_and_slide()

func _set_model_color(color: Color) -> void:
	var enemy_visual := get_node_or_null("DummyVisual") as Node3D
	if enemy_visual == null:
		return
	
	var meshes := enemy_visual.find_children("", "MeshInstance3D", true, false)
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat

func is_blocking_active(player_attack_direction: String) -> bool:
	# Манекен ОЧЕНЬ ХОРОШО блокирует - почти всегда активен блок
	if combat_comp == null:
		return false
	
	# Всегда активируем блок в направлении атаки
	var block_dir = _get_opposite_direction(player_attack_direction)
	return _directions_are_blocked(block_dir, player_attack_direction)

func _get_opposite_direction(attack_dir: String) -> String:
	match attack_dir:
		"UP": return "UP"
		"LEFT": return "RIGHT"
		"RIGHT": return "LEFT"
		_: return "UP"

func _directions_are_blocked(defense_direction: String, attack_direction: String) -> bool:
	return (defense_direction == "UP" and attack_direction == "UP") or \
		   (defense_direction == "LEFT" and attack_direction == "RIGHT") or \
		   (defense_direction == "RIGHT" and attack_direction == "LEFT") or \
		   (defense_direction == "DOWN" and attack_direction == "DOWN")

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	# Манекен получает урон, но с высоким шансом блокирует
	if combat_comp != null and randf() < block_chance:
		# Успешный блок
		notify_successful_block(_get_opposite_direction(combat_comp.current_attack_dir if combat_comp.has_variable("current_attack_dir") else "UP"))
		return
	
	if health_comp:
		health_comp.take_dmg(amount, attacker_pos)

func _on_hp_changed(current: float, max_hp: float) -> void:
	if current <= 0:
		print("🟡 МАНЕКЕН УНИЧТОЖЕН")
		queue_free()
