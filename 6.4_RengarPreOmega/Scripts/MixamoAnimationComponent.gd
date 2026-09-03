extends Node
class_name MixamoAnimationComponent

## Минимальная визуальная FSM для Mixamo-клипов.
## Дерево хранится в сцене: Motion (Idle/Run), Jump, HitReact и два удара.
## Физика, столкновения и боевые хитбоксы остаются в существующих компонентах.

signal attack_animation_finished

@export var anim_tree: AnimationTree
@export var run_speed_for_full_blend := 6.0
@export_range(0.1, 3.0, 0.05) var movement_animation_speed: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.0
@export var attack_recovery_fallback := 0.72

var owner_body: CharacterBody3D
var state_comp: StateComponent
var combat_comp: CombatComponent
var root_playback: AnimationNodeStateMachinePlayback
var hitreact_time_left := 0.0
var attack_time_left := 0.0
var current_root_state := ""  # 🔑 ДОБАВИТЬ ПЕРЕМЕННУЮ

func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("MixamoAnimationComponent должен быть дочерним узлом CharacterBody3D")
		return

	if anim_tree == null:
		anim_tree = owner_body.get_node_or_null("PlayerAnimTree") as AnimationTree
	if anim_tree == null:
		push_error("Не найден PlayerAnimTree")
		return

	state_comp = owner_body.get_node_or_null("StateComponent") as StateComponent
	combat_comp = owner_body.get_node_or_null("CombatComponent") as CombatComponent
	anim_tree.active = true
	_set_visual_animation_speed(movement_animation_speed)
	root_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if root_playback == null:
		push_error("В PlayerAnimTree не найден корневой StateMachine")
		return

	root_playback.start(&"Motion", true)
	current_root_state = "Motion"  # 🔑 ИНИЦИАЛИЗИРОВАТЬ ПЕРЕМЕННУЮ
	if combat_comp != null:
		combat_comp.damage_taken.connect(_on_damage_taken)
		combat_comp.attack_cancelled.connect(_on_attack_cancelled)
		combat_comp.attack_performed.connect(_on_attack_performed)
		combat_comp.attack_finished.connect(_on_attack_finished)  # 🔑 ДОБАВИТЬ ПОДПИСКУ

	print("Mixamo AnimationTree: Motion started")

func _physics_process(delta: float) -> void:
	if owner_body == null or anim_tree == null or root_playback == null:
		return

	if hitreact_time_left > 0.0:
		hitreact_time_left -= delta
		if hitreact_time_left <= 0.0:
			_safe_root_travel("Motion")
			_set_visual_animation_speed(movement_animation_speed)
		return

	if attack_time_left > 0.0:
		attack_time_left -= delta
		if attack_time_left <= 0.0:
			_safe_root_travel("Motion")
			_set_visual_animation_speed(movement_animation_speed)
			attack_animation_finished.emit()
		return

	var horizontal_speed := Vector2(owner_body.velocity.x, owner_body.velocity.z).length()
	var blend_amount: float = clampf(horizontal_speed / maxf(run_speed_for_full_blend, 0.01), 0.0, 1.0)
	anim_tree.set("parameters/Motion/blend_position", blend_amount)

	var current_state: StringName = root_playback.get_current_node()
	if not owner_body.is_on_floor():
		if current_state != &"Jump":
			root_playback.travel(&"Jump")
	elif current_state == &"Jump":
		root_playback.travel(&"Motion")

func _safe_root_travel(state_name: String) -> void:  # 🔑 ДОБАВИТЬ МЕТОД
	if root_playback == null:
		return
	if current_root_state == state_name:
		return
	current_root_state = state_name
	root_playback.travel(StringName(state_name))

func _on_damage_taken() -> void:
	if root_playback == null:
		return
	attack_time_left = 0.0
	hitreact_time_left = 0.35
	root_playback.start(&"HitReact", true)
	current_root_state = "HitReact"  # 🔑 ДОБАВИТЬ ОБНОВЛЕНИЕ

func _on_attack_performed(direction: String, _is_leap_attack: bool) -> void:
	if root_playback == null or hitreact_time_left > 0.0:
		return
	var visual_player := owner_body.get_node_or_null("VisualModel/AnimationPlayer") as AnimationPlayer
	if visual_player == null or not visual_player.has_animation("Attack" + direction):
		push_warning("Не найден боевой клип Attack" + direction)
		return

	var clip := visual_player.get_animation("Attack" + direction)
	# 🔑 ИСПРАВИТЬ: используем процент вместо жесткого вычитания
	var clip_duration_ratio := 0.95
	attack_time_left = (clip.length * clip_duration_ratio / maxf(attack_animation_speed, 0.01)) if clip != null else attack_recovery_fallback
	_set_visual_animation_speed(attack_animation_speed)
	_safe_root_travel("Motion")  # 🔑 ИСПРАВИТЬ ПУТЬ
	print("[Mixamo] ATTACK_STARTED | clip=Attack%s | duration=%.3fs | scaled=%.3fs" % [direction, clip.length, attack_time_left])

func _on_attack_cancelled(_reason: String) -> void:
	if hitreact_time_left <= 0.0:
		attack_time_left = 0.0
		_set_visual_animation_speed(movement_animation_speed)
		_safe_root_travel("Motion")

func _on_attack_finished() -> void:  # 🔑 ДОБАВИТЬ НОВЫЙ МЕТОД
	# Синхронизирует завершение атаки
	attack_time_left = 0.0
	if current_root_state == "Attack":
		_safe_root_travel("Motion")
		_set_visual_animation_speed(movement_animation_speed)
	print("[Mixamo] ATTACK_ANIMATION_FINISHED")

func apply_runtime_speeds() -> void:
	_set_visual_animation_speed(movement_animation_speed)

func _set_visual_animation_speed(value: float) -> void:
	var visual_player := owner_body.get_node_or_null("VisualModel/AnimationPlayer") as AnimationPlayer
	if visual_player != null:
		visual_player.speed_scale = maxf(value, 0.01)
