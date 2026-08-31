extends Node
class_name StacksComponent

signal stacks_updated(gold: int, purple: int, ultimate_ready: bool)
signal combat_state_changed(in_combat: bool)

@export var max_gold: int = 3
@export var combat_decay_time: float = 10.0

var gold_count: int = 0
var has_purple: bool = false
var combat_timer: float = 0.0
var is_in_combat: bool = false

func _physics_process(delta: float) -> void:
	if is_in_combat:
		combat_timer += delta
		if combat_timer >= combat_decay_time:
			is_in_combat = false
			_reset_gold_stacks()
			combat_state_changed.emit(false)

# 🔑 Вызывается при нанесении ИЛИ получении урона
func register_combat_event() -> void:
	is_in_combat = true
	combat_timer = 0.0

func add_gold() -> void:
	if gold_count < max_gold:
		gold_count += 1
		register_combat_event()
		_notify_ui()

func add_purple() -> void:
	if not has_purple:
		has_purple = true
		register_combat_event()
		_notify_ui()

func _reset_gold_stacks() -> void:
	if gold_count > 0:
		gold_count = 0
		_notify_ui()

func is_ultimate_ready() -> bool:
	return gold_count >= max_gold and has_purple

func consume_ultimate() -> bool:
	if is_ultimate_ready():
		gold_count = 0
		has_purple = false
		_notify_ui()
		print("🔥 УЛЬТА АКТИВИРОВАНА")
		return true
	return false

func _notify_ui() -> void:
	stacks_updated.emit(gold_count, 1 if has_purple else 0, is_ultimate_ready())
