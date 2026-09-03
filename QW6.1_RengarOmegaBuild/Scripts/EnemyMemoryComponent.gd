extends Node
class_name EnemyMemoryComponent

## Небольшая персистентная память одного архетипа врага.
## Хранит только агрегированные игровые события, без записи ввода игрока
## покадрово. Файл располагается в user:// и не входит в проектную сборку.

signal memory_changed

const DIRECTIONS: Array[String] = ["UP", "LEFT", "RIGHT"]
const FORMAT_VERSION := 1

@export_group("Persistence")
@export var profile_id := "rengar_default_enemy"
@export var persistence_enabled := true
@export var debug_logging := false

var _memory: Dictionary = {}

func _ready() -> void:
	_load_memory()
	_increment("meta", "encounters", 1.0)
	_save_memory()

func record_player_attack(direction: String) -> void:
	if not _is_direction(direction):
		return
	_increment("player_attacks", direction, 1.0)
	_commit("player_attack:" + direction)

func record_player_block(block_direction: String) -> void:
	if not _is_direction(block_direction):
		return
	_increment("player_blocks", block_direction, 1.0)
	_commit("player_block:" + block_direction)

func record_player_mobility(action_name: String) -> void:
	if action_name != "DASH" and action_name != "DODGE":
		return
	_increment("player_mobility", action_name, 1.0)
	_commit("player_mobility:" + action_name)

func record_enemy_attack_started(direction: String) -> void:
	if not _is_direction(direction):
		return
	_increment("enemy_attempts", direction, 1.0)
	_commit("enemy_attack_started:" + direction)

func record_enemy_attack_hit(direction: String) -> void:
	if not _is_direction(direction):
		return
	_increment("enemy_hits", direction, 1.0)
	_commit("enemy_attack_hit:" + direction)

func record_enemy_attack_blocked(direction: String) -> void:
	if not _is_direction(direction):
		return
	_increment("enemy_blocks", direction, 1.0)
	_commit("enemy_attack_blocked:" + direction)

func record_enemy_damaged() -> void:
	_increment("meta", "damage_taken", 1.0)
	_commit("enemy_damaged")

func get_player_attack_share(direction: String) -> float:
	return _share("player_attacks", direction)

func get_player_block_share(block_direction: String) -> float:
	return _share("player_blocks", block_direction)

func get_player_mobility_share(action_name: String) -> float:
	return _share("player_mobility", action_name)

func get_attack_attempts(direction: String) -> float:
	if not _is_direction(direction):
		return 0.0
	return _value("enemy_attempts", direction)

func get_attack_success(direction: String) -> float:
	if not _is_direction(direction):
		return 0.5
	var attempts := _value("enemy_attempts", direction)
	if attempts <= 0.0:
		return 0.5
	return clampf(_value("enemy_hits", direction) / attempts, 0.0, 1.0)

func get_attack_block_rate(direction: String) -> float:
	if not _is_direction(direction):
		return 0.0
	var attempts := _value("enemy_attempts", direction)
	if attempts <= 0.0:
		return 0.0
	return clampf(_value("enemy_blocks", direction) / attempts, 0.0, 1.0)

func get_encounter_count() -> int:
	return int(_value("meta", "encounters"))

func get_memory_snapshot() -> Dictionary:
	return _memory.duplicate(true)

func reset_memory() -> void:
	_memory = _new_memory()
	_save_memory()
	memory_changed.emit()
	_trace("MEMORY_RESET")

func _load_memory() -> void:
	_memory = _new_memory()
	if not persistence_enabled:
		return
	var path := _memory_path()
	if not FileAccess.file_exists(path):
		_trace("MEMORY_NEW | path=" + path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("EnemyMemoryComponent: не удалось прочитать " + path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and int(parsed.get("format_version", 0)) == FORMAT_VERSION:
		_memory = parsed
		_ensure_memory_shape()
		_trace("MEMORY_LOADED | encounters=" + str(get_encounter_count()))
	else:
		push_warning("EnemyMemoryComponent: память имеет неверный формат; создан новый профиль")

func _save_memory() -> void:
	if not persistence_enabled:
		return
	_memory["format_version"] = FORMAT_VERSION
	var file := FileAccess.open(_memory_path(), FileAccess.WRITE)
	if file == null:
		push_warning("EnemyMemoryComponent: не удалось сохранить профиль")
		return
	file.store_string(JSON.stringify(_memory, "\t"))

func _commit(event_name: String) -> void:
	_save_memory()
	memory_changed.emit()
	_trace("MEMORY_EVENT | " + event_name)

func _new_memory() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"meta": {"encounters": 0.0, "damage_taken": 0.0},
		"player_attacks": _direction_bucket(),
		"player_blocks": _direction_bucket(),
		"player_mobility": {"DASH": 0.0, "DODGE": 0.0},
		"enemy_attempts": _direction_bucket(),
		"enemy_hits": _direction_bucket(),
		"enemy_blocks": _direction_bucket(),
	}

func _ensure_memory_shape() -> void:
	var defaults := _new_memory()
	for key in defaults:
		if not _memory.has(key) or not (_memory[key] is Dictionary):
			_memory[key] = defaults[key]
	for key in ["player_attacks", "player_blocks", "enemy_attempts", "enemy_hits", "enemy_blocks"]:
		for direction in DIRECTIONS:
			if not _memory[key].has(direction):
				_memory[key][direction] = 0.0
	for action_name in ["DASH", "DODGE"]:
		if not _memory["player_mobility"].has(action_name):
			_memory["player_mobility"][action_name] = 0.0

func _direction_bucket() -> Dictionary:
	return {"UP": 0.0, "LEFT": 0.0, "RIGHT": 0.0}

func _increment(bucket: String, key: String, amount: float) -> void:
	var table: Dictionary = _memory.get(bucket, {})
	table[key] = float(table.get(key, 0.0)) + amount
	_memory[bucket] = table

func _value(bucket: String, key: String) -> float:
	var table: Dictionary = _memory.get(bucket, {})
	return float(table.get(key, 0.0))

func _share(bucket: String, key: String) -> float:
	var table: Dictionary = _memory.get(bucket, {})
	var total := 0.0
	for value in table.values():
		total += float(value)
	return _value(bucket, key) / total if total > 0.0 else 0.0

func _is_direction(direction: String) -> bool:
	return direction in DIRECTIONS

func _memory_path() -> String:
	return "user://enemy_utility_memory_" + profile_id.validate_filename() + ".json"

func _trace(message: String) -> void:
	if debug_logging:
		print("[EnemyMemory] ", message)
