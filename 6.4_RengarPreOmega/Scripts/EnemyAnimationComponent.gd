extends Node
class_name EnemyAnimationComponent

## Визуальный компонент врага. Он не содержит ИИ, урон или физику: читает
## уже существующие CombatComponent/CharacterBody3D и управляет только клипами.

@export var visual_model_path: NodePath = NodePath("../EnemyVisual")
@export var run_speed_for_full_animation := 0.15
@export_range(0.1, 3.0, 0.05) var movement_animation_speed: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.0
@export var fallback_attack_duration := 0.72
@export var fallback_hitreact_duration := 0.35

var owner_body: CharacterBody3D
var combat_comp: CombatComponent
var animation_player: AnimationPlayer
var action_time_left := 0.0
var current_loop: StringName = &""

func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("EnemyAnimationComponent должен быть дочерним узлом CharacterBody3D")
		return

	combat_comp = owner_body.get_node_or_null("CombatComponent") as CombatComponent
	var visual_model := get_node_or_null(visual_model_path) as Node3D
	if visual_model != null:
		# Пробуем найти AnimationPlayer разными способами
		animation_player = visual_model.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player == null:
			# Возможно AnimationPlayer является прямым потомком visual_model с другим именем
			for child in visual_model.get_children():
				if child is AnimationPlayer:
					animation_player = child as AnimationPlayer
					break
	if animation_player == null:
		push_error("EnemyAnimationComponent: в EnemyVisual не найден AnimationPlayer. Проверьте структуру узла " + str(visual_model_path))
		return

	if combat_comp != null:
		# AttackPerformed — единственная точка visual swing и Method Track hitbox.
		combat_comp.attack_performed.connect(_on_attack_performed)
		combat_comp.damage_taken.connect(_on_damage_taken)
		combat_comp.stun_started.connect(_on_stun_started)

	_play_loop(&"Idle")

func _physics_process(delta: float) -> void:
	if animation_player == null or owner_body == null:
		return

	if action_time_left > 0.0:
		action_time_left -= delta
		return

	var horizontal_speed := Vector2(owner_body.velocity.x, owner_body.velocity.z).length()
	if horizontal_speed > run_speed_for_full_animation:
		_play_loop(&"Run")
	else:
		_play_loop(&"Idle")

func _on_attack_performed(direction: String, _is_leap_attack: bool) -> void:
	# Клип стартует в одной точке SWING; его Method Track владеют hitbox.
	_play_one_shot(_clip_for_direction(direction), fallback_attack_duration)

func _on_damage_taken() -> void:
	# Обычный полученный урон приоритетнее замаха и всегда прерывает его.
	action_time_left = 0.0
	_play_one_shot(&"HitReact", fallback_hitreact_duration)

func _clip_for_direction(direction: String) -> StringName:
	if direction == "LEFT":
		return &"AttackLeft"
	if direction == "UP":
		return &"AttackUp"
	return &"AttackRight"

func _on_stun_started(duration: float) -> void:
	_play_one_shot(&"HitReact", maxf(duration, fallback_hitreact_duration))

func apply_runtime_speeds() -> void:
	if animation_player != null:
		animation_player.speed_scale = maxf(movement_animation_speed, 0.01)

func _play_loop(clip_name: StringName) -> void:
	if action_time_left > 0.0 or current_loop == clip_name:
		return
	if not animation_player.has_animation(clip_name):
		push_warning("EnemyAnimationComponent: не найден цикл " + String(clip_name))
		return

	current_loop = clip_name
	animation_player.speed_scale = maxf(movement_animation_speed, 0.01)
	animation_player.play(clip_name)

func _play_one_shot(clip_name: StringName, fallback_duration: float) -> void:
	if animation_player == null or not animation_player.has_animation(clip_name):
		push_warning("EnemyAnimationComponent: не найден клип " + String(clip_name))
		return

	var clip := animation_player.get_animation(clip_name)
	var playback_speed := attack_animation_speed if String(clip_name).begins_with("Attack") else movement_animation_speed
	action_time_left = (maxf(clip.length - 0.06, 0.1) / maxf(playback_speed, 0.01)) if clip != null else fallback_duration
	current_loop = &""
	animation_player.speed_scale = maxf(playback_speed, 0.01)
	animation_player.play(clip_name)
