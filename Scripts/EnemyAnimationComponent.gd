extends Node
class_name EnemyAnimationComponent

## Визуальный компонент врага.
## Не содержит ИИ, урон или физику.
## Читает CombatComponent и управляет только AnimationPlayer.

signal attack_animation_finished

@export var visual_model_path: NodePath = NodePath("../EnemyVisual")

@export_group("Movement Animation")
@export var run_speed_for_full_animation: float = 0.15
@export_range(0.1, 3.0, 0.05)
var movement_animation_speed: float = 1.0

@export_group("Attack Animation")
@export_range(0.1, 3.0, 0.05)
var attack_animation_speed: float = 1.0

var owner_body: CharacterBody3D
var combat_comp: CombatComponent
var animation_player: AnimationPlayer

var current_loop: StringName = &""


func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D

	if owner_body == null:
		push_error(
			"EnemyAnimationComponent должен быть дочерним узлом CharacterBody3D"
		)
		return

	combat_comp = owner_body.get_node_or_null(
		"CombatComponent"
	) as CombatComponent

	var visual_model := get_node_or_null(
		visual_model_path
	) as Node3D

	if visual_model != null:
		# Основной ожидаемый путь:
		# EnemyVisual/AnimationPlayer
		animation_player = visual_model.get_node_or_null(
			"AnimationPlayer"
		) as AnimationPlayer

		# Fallback: ищем AnimationPlayer среди прямых детей.
		if animation_player == null:
			for child in visual_model.get_children():
				if child is AnimationPlayer:
					animation_player = child as AnimationPlayer
					break

	if animation_player == null:
		push_error(
			"EnemyAnimationComponent: в EnemyVisual не найден AnimationPlayer. "
			+ "Проверьте структуру узла "
			+ str(visual_model_path)
		)
		return

	# AnimationPlayer — единственный источник истины
	# о фактическом завершении animation clip.
	animation_player.animation_finished.connect(
		_on_animation_finished
	)

	if combat_comp != null:
		# AttackPerformed — точка запуска визуального swing.
		# Method Tracks самого AnimationPlayer управляют hitbox.
		combat_comp.attack_performed.connect(
			_on_attack_performed
		)

		combat_comp.damage_taken.connect(
			_on_damage_taken
		)

		combat_comp.stun_started.connect(
			_on_stun_started
		)

	apply_runtime_speeds()
	_play_loop(&"Idle")


func _physics_process(_delta: float) -> void:
	if animation_player == null or owner_body == null:
		return

	# Пока проигрывается attack / HitReact,
	# locomotion не имеет права перезаписывать animation.
	if _is_action_animation_playing():
		return

	var horizontal_speed := Vector2(
		owner_body.velocity.x,
		owner_body.velocity.z
	).length()

	if horizontal_speed > run_speed_for_full_animation:
		_play_loop(&"Run")
	else:
		_play_loop(&"Idle")


func _on_attack_performed(
	direction: String,
	_is_leap_attack: bool
) -> void:
	var clip_name := _clip_for_direction(direction)

	if not animation_player.has_animation(clip_name):
		push_warning(
			"EnemyAnimationComponent: не найден attack clip "
			+ String(clip_name)
		)
		return

	current_loop = &""

	animation_player.speed_scale = maxf(
		attack_animation_speed,
		0.01
	)

	animation_player.play(clip_name)


func _on_damage_taken() -> void:
	# Полученный урон визуально прерывает текущую атаку.
	current_loop = &""

	if not animation_player.has_animation(&"HitReact"):
		push_warning(
			"EnemyAnimationComponent: не найден клип HitReact"
		)
		return

	animation_player.speed_scale = maxf(
		movement_animation_speed,
		0.01
	)

	animation_player.play(&"HitReact")


func _on_stun_started(duration: float) -> void:
	# duration здесь больше не используется как таймер.
	# Фактическое окончание визуальной реакции определяется
	# AnimationPlayer.animation_finished.
	_play_one_shot(&"HitReact", movement_animation_speed)


func _on_animation_finished(animation_name: StringName) -> void:
	# Только attack clips завершают attack sequence.
	if (
		animation_name == &"AttackLeft"
		or animation_name == &"AttackRight"
		or animation_name == &"AttackUp"
	):
		animation_player.speed_scale = maxf(
			movement_animation_speed,
			0.01
		)

		current_loop = &""

		print(
			"EnemyAnimationComponent: ATTACK_ANIMATION_FINISHED | clip=",
			String(animation_name)
		)

		attack_animation_finished.emit()

	elif animation_name == &"HitReact":
		animation_player.speed_scale = maxf(
			movement_animation_speed,
			0.01
		)

		current_loop = &""


func _clip_for_direction(direction: String) -> StringName:
	if direction == "LEFT":
		return &"AttackLeft"

	if direction == "UP":
		return &"AttackUp"

	return &"AttackRight"


func apply_runtime_speeds() -> void:
	if animation_player == null:
		return

	animation_player.speed_scale = maxf(
		movement_animation_speed,
		0.01
	)


func _play_loop(clip_name: StringName) -> void:
	if animation_player == null:
		return

	if _is_action_animation_playing():
		return

	if current_loop == clip_name:
		return

	if not animation_player.has_animation(clip_name):
		push_warning(
			"EnemyAnimationComponent: не найден loop clip "
			+ String(clip_name)
		)
		return

	current_loop = clip_name

	animation_player.speed_scale = maxf(
		movement_animation_speed,
		0.01
	)

	animation_player.play(clip_name)


func _play_one_shot(
	clip_name: StringName,
	playback_speed: float
) -> void:
	if animation_player == null:
		return

	if not animation_player.has_animation(clip_name):
		push_warning(
			"EnemyAnimationComponent: не найден клип "
			+ String(clip_name)
		)
		return

	current_loop = &""

	animation_player.speed_scale = maxf(
		playback_speed,
		0.01
	)

	animation_player.play(clip_name)


func _is_action_animation_playing() -> bool:
	if animation_player == null:
		return false

	var current_animation := animation_player.current_animation

	return (
		current_animation == &"AttackLeft"
		or current_animation == &"AttackRight"
		or current_animation == &"AttackUp"
		or current_animation == &"HitReact"
	)
