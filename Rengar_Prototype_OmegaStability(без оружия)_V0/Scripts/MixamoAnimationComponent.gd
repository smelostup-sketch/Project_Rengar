extends Node
class_name MixamoAnimationComponent

## Минимальная визуальная FSM для Mixamo-клипов.
## Дерево хранится в сцене: Motion (Idle/Run), Jump, HitReact и два удара.
## Физика, столкновения и боевые хитбоксы остаются в существующих компонентах.

signal attack_animation_finished

@export var anim_tree: AnimationTree
@export var run_speed_for_full_blend := 6.0
@export var attack_recovery_fallback := 0.72

var owner_body: CharacterBody3D
var state_comp: StateComponent
var combat_comp: CombatComponent
var root_playback: AnimationNodeStateMachinePlayback
var hitreact_time_left := 0.0
var attack_time_left := 0.0

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
	root_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if root_playback == null:
		push_error("В PlayerAnimTree не найден корневой StateMachine")
		return

	root_playback.start(&"Motion", true)
	if combat_comp != null:
		combat_comp.damage_taken.connect(_on_damage_taken)
		combat_comp.attack_cancelled.connect(_on_attack_cancelled)
		combat_comp.attack_performed.connect(_on_attack_performed)
	if state_comp != null:
		state_comp.state_changed.connect(_on_state_changed)

	print("Mixamo AnimationTree: Motion started")

func _physics_process(delta: float) -> void:
	if owner_body == null or anim_tree == null or root_playback == null:
		return

	if hitreact_time_left > 0.0:
		hitreact_time_left -= delta
		if hitreact_time_left <= 0.0:
			root_playback.travel(&"Motion")
		return

	if attack_time_left > 0.0:
		attack_time_left -= delta
		if attack_time_left <= 0.0:
			root_playback.travel(&"Motion")
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

func _on_state_changed(state_name: String, value: bool) -> void:
	if state_name == "leap" and value and root_playback != null:
		root_playback.travel(&"Jump")

func _on_damage_taken() -> void:
	if root_playback == null:
		return
	attack_time_left = 0.0
	hitreact_time_left = 0.35
	root_playback.start(&"HitReact", true)

func _on_attack_started(direction: String, _is_leap_attack: bool) -> void:
	if root_playback == null or hitreact_time_left > 0.0:
		return
	# Сигнал приходит только после фиксации направления и attack_start_delay.
	# В этот момент CombatComponent одновременно запускает хитбокс; вводом
	# отдельно владеет AttackInputComponent.
	_play_attack(_clip_for_direction(direction), true)

func _on_attack_cancelled(_reason: String) -> void:
	if hitreact_time_left <= 0.0:
		attack_time_left = 0.0
		root_playback.travel(&"Motion")

func _on_attack_performed(direction: String, _is_leap_attack: bool) -> void:
	if root_playback == null or hitreact_time_left > 0.0:
		return
	# Единственный визуальный one-shot запускается в подтверждённой точке
	# после фиксации направления и attack_start_delay.
	_play_attack(_clip_for_direction(direction), true)

func _clip_for_direction(direction: String) -> StringName:
	if direction == "LEFT":
		return &"AttackLeft"
	if direction == "UP":
		# Отдельный state уже существует; до поставки AT_UP.fbx он использует
		# временную копию доступного правого клипа в MixamoAnimationLibrary.
		return &"AttackUp"
	return &"AttackRight"

func _play_attack(clip_name: StringName, restart_same_clip: bool) -> void:
	var visual_player := owner_body.get_node_or_null("VisualModel/AnimationPlayer") as AnimationPlayer
	if visual_player == null or not visual_player.has_animation(clip_name):
		push_warning("Не найден боевой клип " + String(clip_name))
		return

	var clip := visual_player.get_animation(clip_name)
	attack_time_left = maxf(clip.length - 0.06, 0.1) if clip != null else attack_recovery_fallback
	# One-shot стартует непосредственно из подтверждённого ввода. Это не
	# создаёт второй боевой таймер: длина клипа остаётся источником возврата.
	if restart_same_clip:
		root_playback.start(clip_name, true)
	elif root_playback.get_current_node() != clip_name:
		root_playback.travel(clip_name, true)
