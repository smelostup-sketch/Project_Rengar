extends Node
class_name HealthComponent

@export var max_hp: float = 100.0
var hp: float = 100.0
var is_dead: bool = false

signal hp_changed(current: float, maximum: float)
signal died

func _ready():
	hp = max_hp

func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if hp <= 0.0 or is_dead: return
	hp = max(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if is_dead: return
	hp = min(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

func get_hp_ratio() -> float:
	return clamp(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
