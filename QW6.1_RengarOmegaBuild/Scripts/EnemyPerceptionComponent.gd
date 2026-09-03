extends Node
class_name EnemyPerceptionComponent

## Наблюдает уже существующие компоненты игрока и выдаёт только факты для AI.
## Не изменяет ввод, здоровье, физику или состояние боя.

signal player_attack_observed(direction: String)
signal player_block_observed(direction: String)
signal player_mobility_observed(action_name: String)

@export var debug_logging := false

var enemy_body: CharacterBody3D
var player_body: CharacterBody3D
var player_combat: CombatComponent
var player_state: StateComponent
var player_input: AttackInputComponent

var last_player_attack_direction := "UP"
var last_player_attack_time := -999.0
var last_player_block_direction := "UP"
var last_player_mobility_time := -999.0
var last_player_mobility_action := ""

func _ready() -> void:
	enemy_body = get_parent() as CharacterBody3D
	call_deferred("_bind_player")

func get_distance_to_player() -> float:
	if enemy_body == null or player_body == null:
		return INF
	return enemy_body.global_position.distance_to(player_body.global_position)

func is_player_attacking() -> bool:
	return player_input != null and player_input.is_attack_in_progress()

func is_player_blocking() -> bool:
	return player_combat != null and player_combat.is_block_active

func is_player_moving_fast() -> bool:
	if player_body == null:
		return false
	return Vector2(player_body.velocity.x, player_body.velocity.z).length() > 4.0

func was_player_recently_mobile(window_seconds: float) -> bool:
	return _now() - last_player_mobility_time <= window_seconds

func get_player_attack_recency(window_seconds: float) -> float:
	var elapsed := _now() - last_player_attack_time
	return clampf(1.0 - elapsed / maxf(window_seconds, 0.01), 0.0, 1.0)

func _bind_player() -> void:
	var candidate := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if candidate == null:
		push_warning("EnemyPerceptionComponent: игрок не найден")
		return
	player_body = candidate
	player_combat = player_body.get_node_or_null("CombatComponent") as CombatComponent
	player_state = player_body.get_node_or_null("StateComponent") as StateComponent
	player_input = player_body.get_node_or_null("AttackInputComponent") as AttackInputComponent
	if player_combat != null:
		player_combat.attack_performed.connect(_on_player_attack_performed)
		player_combat.block_started.connect(_on_player_block_started)
	if player_state != null:
		player_state.action_started.connect(_on_player_action_started)
	_trace("PLAYER_BOUND")

func _on_player_attack_performed(direction: String, _is_leap_attack: bool) -> void:
	last_player_attack_direction = direction
	last_player_attack_time = _now()
	player_attack_observed.emit(direction)
	_trace("PLAYER_ATTACK | dir=" + direction)

func _on_player_block_started(direction: String) -> void:
	last_player_block_direction = direction
	player_block_observed.emit(direction)
	_trace("PLAYER_BLOCK | dir=" + direction)

func _on_player_action_started(_direction: Vector2, action_type: int) -> void:
	last_player_mobility_time = _now()
	last_player_mobility_action = "DODGE" if action_type == StateComponent.ActionType.DODGE else "DASH"
	player_mobility_observed.emit(last_player_mobility_action)
	_trace("PLAYER_MOBILITY | action=" + last_player_mobility_action)

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

func _trace(message: String) -> void:
	if debug_logging:
		print("[EnemyPerception] ", message)
