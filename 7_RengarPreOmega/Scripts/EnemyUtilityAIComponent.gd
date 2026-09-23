extends Node
class_name EnemyUtilityAIComponent

## Прозрачный Utility AI: каждое решение выбирается по наибольшему score.
## Компонент не наносит урон и не создаёт hitbox: он лишь передаёт
## EnemyController намерение движения и рекомендуемое направление атаки.

enum Decision { APPROACH, HOLD, ATTACK, RETREAT }
enum AdaptationProfile { CUSTOM, BALANCED, BERSERKER, DEFENDER }

signal decision_changed(decision: Decision, scores: Dictionary)

@export_group("References")
@export var perception_path: NodePath = NodePath("../EnemyPerceptionComponent")
@export var memory_path: NodePath = NodePath("../EnemyMemoryComponent")

@export_group("Archetype Profile")
@export var adaptation_profile: AdaptationProfile = AdaptationProfile.BALANCED
@export var apply_profile_on_ready := true

@export_group("Decision Timing")
@export_range(0.05, 1.0, 0.01, "suffix:s") var decision_interval := 0.16
@export_range(0.0, 1.0, 0.01) var decision_noise := 0.04

@export_group("Tactics")
@export_range(0.5, 5.0, 0.1, "suffix:m") var preferred_distance := 1.6
@export_range(0.5, 5.0, 0.1, "suffix:m") var attack_distance := 2.25
@export_range(0.5, 5.0, 0.1, "suffix:m") var retreat_distance := 2.7
@export_range(0.0, 1.0, 0.01) var block_penalty := 0.75
@export_range(0.0, 1.0, 0.01) var recent_attack_retreat_weight := 0.72
@export_group("Attack Direction Exploration")
@export_range(0, 10, 1) var minimum_attempts_per_direction := 2
@export_range(0.0, 1.0, 0.01) var repeated_direction_penalty := 0.12
@export var debug_logging := true

var enemy_body: CharacterBody3D
var combat_comp: CombatComponent
var health_comp: HealthComponent
var perception: EnemyPerceptionComponent
var memory: EnemyMemoryComponent

var current_decision: Decision = Decision.APPROACH
var current_scores: Dictionary = {}
var current_recommended_attack_direction := "UP"
var _last_selected_attack_direction := ""
var _exploration_cursor := 0
var _decision_time_left := 0.0

func _ready() -> void:
	enemy_body = get_parent() as CharacterBody3D
	if enemy_body == null:
		push_error("EnemyUtilityAIComponent должен быть дочерним узлом CharacterBody3D")
		return
	combat_comp = enemy_body.get_node_or_null("CombatComponent") as CombatComponent
	health_comp = enemy_body.get_node_or_null("HealthComponent") as HealthComponent
	if apply_profile_on_ready:
		apply_profile_preset(adaptation_profile)
	perception = get_node_or_null(perception_path) as EnemyPerceptionComponent
	memory = get_node_or_null(memory_path) as EnemyMemoryComponent
	if perception == null or memory == null or combat_comp == null:
		push_error("EnemyUtilityAIComponent: не найдены Perception, Memory или CombatComponent")
		return
	perception.player_attack_observed.connect(memory.record_player_attack)
	perception.player_block_observed.connect(memory.record_player_block)
	perception.player_mobility_observed.connect(memory.record_player_mobility)
	combat_comp.attack_started.connect(_on_enemy_attack_started)
	combat_comp.hit_detected.connect(_on_enemy_attack_hit)
	combat_comp.stun_started.connect(_on_enemy_stunned)
	combat_comp.damage_taken.connect(_on_enemy_damaged)
	_refresh_decision(true)

func update(delta: float) -> Decision:
	if not is_operational():
		return current_decision
	_decision_time_left -= delta
	if _decision_time_left <= 0.0:
		_refresh_decision(false)
	return current_decision

func is_operational() -> bool:
	return enemy_body != null and combat_comp != null and perception != null and memory != null and perception.player_body != null

func wants_attack() -> bool:
	return current_decision == Decision.ATTACK

func wants_block() -> bool:
	if perception == null:
		return false
	var recent_attack := perception.get_player_attack_recency(1.2)
	return (current_decision == Decision.HOLD or perception.is_player_attacking()) and recent_attack > 0.10

func get_recommended_block_direction() -> String:
	if perception == null:
		return "UP"
	var incoming := perception.last_player_attack_direction
	if incoming == "LEFT":
		return "RIGHT"
	if incoming == "RIGHT":
		return "LEFT"
	return "UP"

func get_recommended_attack_direction() -> String:
	current_recommended_attack_direction = _choose_attack_direction(true)
	_last_selected_attack_direction = current_recommended_attack_direction
	return current_recommended_attack_direction

func get_debug_snapshot() -> Dictionary:
	var dominant_attack := _dominant_memory_direction("player_attacks")
	var dominant_block := _dominant_memory_direction("player_blocks")
	return {
		"profile": get_profile_name(),
		"decision": get_decision_name(),
		"reason": get_decision_reason(),
		"scores": current_scores.duplicate(),
		"distance": perception.get_distance_to_player() if perception != null else INF,
		"recommended_attack": current_recommended_attack_direction,
		"dominant_attack": dominant_attack,
		"dominant_attack_share": memory.get_player_attack_share(dominant_attack) if memory != null else 0.0,
		"dominant_block": dominant_block,
		"dominant_block_share": memory.get_player_block_share(dominant_block) if memory != null else 0.0,
		"dodge_share": memory.get_player_mobility_share("DODGE") if memory != null else 0.0,
	}

func get_decision_reason() -> String:
	if perception == null or memory == null:
		return "ожидание данных восприятия"
	var distance := perception.get_distance_to_player()
	match current_decision:
		Decision.APPROACH:
			return "дистанция %.1f м выше комфортной %.1f м" % [distance, preferred_distance]
		Decision.HOLD:
			return "цель в зоне; блок/риск делает атаку невыгодной"
		Decision.ATTACK:
			return "дистанция %.1f м в зоне удара; выбран %s" % [distance, current_recommended_attack_direction]
		Decision.RETREAT:
			return "недавняя атака игрока или низкое здоровье"
	return "нет причины"

func get_profile_name() -> String:
	return AdaptationProfile.keys()[adaptation_profile]

func apply_profile_preset(profile: AdaptationProfile) -> void:
	adaptation_profile = profile
	if profile == AdaptationProfile.CUSTOM:
		return
	if profile == AdaptationProfile.BALANCED:
		decision_interval = 0.16
		decision_noise = 0.04
		preferred_distance = 1.6
		attack_distance = 2.25
		retreat_distance = 2.7
		block_penalty = 0.75
		recent_attack_retreat_weight = 0.72
	elif profile == AdaptationProfile.BERSERKER:
		decision_interval = 0.10
		decision_noise = 0.07
		preferred_distance = 1.15
		attack_distance = 2.8
		retreat_distance = 2.2
		block_penalty = 0.38
		recent_attack_retreat_weight = 0.30
	elif profile == AdaptationProfile.DEFENDER:
		decision_interval = 0.22
		decision_noise = 0.02
		preferred_distance = 2.15
		attack_distance = 2.0
		retreat_distance = 3.6
		block_penalty = 0.95
		recent_attack_retreat_weight = 0.92

func get_retreat_direction() -> Vector3:
	if perception == null or perception.player_body == null or enemy_body == null:
		return Vector3.ZERO
	var direction := enemy_body.global_position - perception.player_body.global_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO

func get_decision_name() -> String:
	return Decision.keys()[current_decision]

func _refresh_decision(force: bool) -> void:
	_decision_time_left = decision_interval
	current_scores = _calculate_scores()
	current_recommended_attack_direction = _choose_attack_direction(false)
	var next_decision := _best_decision(current_scores)
	if force or next_decision != current_decision:
		current_decision = next_decision
		decision_changed.emit(current_decision, current_scores.duplicate())
		_trace("DECISION | %s | scores=%s" % [get_decision_name(), _format_scores(current_scores)])
	else:
		current_decision = next_decision

func _calculate_scores() -> Dictionary:
	var distance := perception.get_distance_to_player()
	var distance_to_attack := clampf(1.0 - distance / maxf(attack_distance, 0.01), 0.0, 1.0)
	var near_preferred := clampf(1.0 - absf(distance - preferred_distance) / maxf(preferred_distance, 0.01), 0.0, 1.0)
	var recent_player_attack := perception.get_player_attack_recency(0.8)
	var player_attacking_now := 1.0 if perception.is_player_attacking() else 0.0
	var block_pressure := maxf(recent_player_attack, player_attacking_now)
	var player_mobile := 1.0 if perception.was_player_recently_mobile(0.65) or perception.is_player_moving_fast() else 0.0
	var player_blocking := 1.0 if perception.is_player_blocking() else 0.0
	var learned_blocking := maxf(memory.get_player_block_share("UP"), maxf(memory.get_player_block_share("LEFT"), memory.get_player_block_share("RIGHT")))
	var learned_attack_success := _average_attack_success()
	var low_health := 0.0
	if health_comp != null and health_comp.max_hp > 0.0:
		low_health = clampf(1.0 - health_comp.hp / health_comp.max_hp, 0.0, 1.0)
	return {
		Decision.APPROACH: clampf((distance - preferred_distance) / maxf(preferred_distance, 0.01), 0.0, 1.0) + (1.0 - player_mobile) * 0.16,
		Decision.HOLD: near_preferred * 0.28 + player_blocking * 0.32 + block_pressure * 1.30,
		Decision.ATTACK: distance_to_attack * 0.92 + near_preferred * 0.24 + learned_attack_success * 0.24 - player_blocking * block_penalty - learned_blocking * 0.18 - player_mobile * 0.18,
		Decision.RETREAT: recent_player_attack * recent_attack_retreat_weight + player_mobile * memory.get_player_mobility_share("DODGE") * 0.22 + low_health * 0.36,
	}

func _best_decision(scores: Dictionary) -> Decision:
	var best: Decision = Decision.APPROACH
	var best_score := -INF
	for candidate in [Decision.APPROACH, Decision.HOLD, Decision.ATTACK, Decision.RETREAT]:
		var score := float(scores.get(candidate, -INF))
		# Сохраняет решение при практически равных score и убирает дрожание.
		if candidate == current_decision:
			score += 0.05
		if score > best_score:
			best_score = score
			best = candidate
	return best

func _choose_attack_direction(use_noise: bool) -> String:
	# Сначала гарантируем, что ни одно направление не будет навсегда вытеснено
	# первым удачным результатом. Выбираем одно из наименее проверенных направлений.
	var least_attempts := INF
	var least_tried: Array[String] = []
	for direction in EnemyMemoryComponent.DIRECTIONS:
		var attempts := memory.get_attack_attempts(direction)
		if attempts < minimum_attempts_per_direction:
			if attempts < least_attempts:
				least_attempts = attempts
				least_tried.clear()
				least_tried.append(direction)
			elif is_equal_approx(attempts, least_attempts):
				least_tried.append(direction)
	if not least_tried.is_empty():
		var exploration_direction := least_tried[_exploration_cursor % least_tried.size()]
		_exploration_cursor += 1
		return exploration_direction

	var best_directions: Array[String] = []
	var best_score := -INF
	for direction in EnemyMemoryComponent.DIRECTIONS:
		var expected_success := memory.get_attack_success(direction)
		var observed_block_share := memory.get_player_block_share(_block_direction_for_enemy_attack(direction))
		var score := 0.45 + expected_success * 0.35 - observed_block_share * block_penalty - memory.get_attack_block_rate(direction) * 0.45
		if direction == _last_selected_attack_direction:
			score -= repeated_direction_penalty
		if use_noise:
			score += randf_range(-decision_noise, decision_noise)
		if score > best_score + 0.001:
			best_score = score
			best_directions.clear()
			best_directions.append(direction)
		elif absf(score - best_score) <= 0.001:
			best_directions.append(direction)
	if best_directions.is_empty():
		return "UP"
	return best_directions[randi() % best_directions.size()]

func _dominant_memory_direction(bucket: String) -> String:
	var best_direction := "UP"
	var best_share := -1.0
	for direction in EnemyMemoryComponent.DIRECTIONS:
		var share := memory.get_player_attack_share(direction) if bucket == "player_attacks" else memory.get_player_block_share(direction)
		if share > best_share:
			best_share = share
			best_direction = direction
	return best_direction

func _average_attack_success() -> float:
	var total := 0.0
	for direction in EnemyMemoryComponent.DIRECTIONS:
		total += memory.get_attack_success(direction)
	return total / float(EnemyMemoryComponent.DIRECTIONS.size())

func _block_direction_for_enemy_attack(enemy_attack_direction: String) -> String:
	if enemy_attack_direction == "LEFT":
		return "RIGHT"
	if enemy_attack_direction == "RIGHT":
		return "LEFT"
	return "UP"

func _on_enemy_attack_started(direction: String, _is_leap_attack: bool) -> void:
	memory.record_enemy_attack_started(direction)

func _on_enemy_attack_hit(_target: Node) -> void:
	memory.record_enemy_attack_hit(combat_comp.attack_dir)

func _on_enemy_stunned(_duration: float) -> void:
	memory.record_enemy_attack_blocked(combat_comp.attack_dir)

func _on_enemy_damaged() -> void:
	memory.record_enemy_damaged()

func _format_scores(scores: Dictionary) -> String:
	return "A=%.2f H=%.2f X=%.2f R=%.2f" % [
		float(scores.get(Decision.APPROACH, 0.0)),
		float(scores.get(Decision.HOLD, 0.0)),
		float(scores.get(Decision.ATTACK, 0.0)),
		float(scores.get(Decision.RETREAT, 0.0)),
	]

func _trace(message: String) -> void:
	if debug_logging:
		print("[EnemyUtilityAI] ", message)
