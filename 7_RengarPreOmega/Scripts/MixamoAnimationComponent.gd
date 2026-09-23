extends Node
class_name MixamoAnimationComponent

## Визуальный компонент Player.
## Не содержит физику, боевую логику или hitbox-логику.
## Получает сигналы CombatComponent и напрямую управляет AnimationPlayer.
##
## Единый animation contract:
## Idle
## Run
## Jump
## HitReact
## AttackLeft
## AttackRight
## AttackUp

signal attack_animation_finished

@export var visual_model_path: NodePath = NodePath("../VisualModel")

@export_range(0.1, 3.0, 0.05)
var movement_animation_speed: float = 1.0

@export_range(0.1, 3.0, 0.05)
var attack_animation_speed: float = 1.0

var owner_body: CharacterBody3D
var state_comp: StateComponent
var combat_comp: CombatComponent
var animation_player: AnimationPlayer

var current_loop: StringName = &""


func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D

	if owner_body == null:
		push_error(
			"MixamoAnimationComponent должен быть дочерним узлом CharacterBody3D"
		)
		return

	state_comp = owner_body.get_node_or_null("StateComponent") as StateComponent
	combat_comp = owner_body.get_node_or_null("CombatComponent") as CombatComponent

	var visual_model := get_node_or_null(visual_model_path) as Node3D

	if visual_model == null:
		push_error(
			"MixamoAnimationComponent: не найден VisualModel: "
			+ str(visual_model_path)
		)
		return

	animation_player = visual_model.get_node_or_null(
		"AnimationPlayer"
	) as AnimationPlayer

	if animation_player == null:
		for child in visual_model.get_children():
			if child is AnimationPlayer:
				animation_player = child as AnimationPlayer
				break

	if animation_player == null:
		push_error(
			"MixamoAnimationComponent: в VisualModel не найден AnimationPlayer. "
			+ "Проверьте структуру узла "
			+ str(visual_model_path)
		)
		return

	animation_player.animation_finished.connect(_on_animation_finished)

	if combat_comp != null:
		combat_comp.damage_taken.connect(_on_damage_taken)
		combat_comp.attack_cancelled.connect(_on_attack_cancelled)
		combat_comp.attack_performed.connect(_on_attack_performed)

	_set_animation_speed(movement_animation_speed)
	_play_loop(&"Idle")

	print("MixamoAnimationComponent: AnimationPlayer initialized")


func _physics_process(_delta: float) -> void:
	if owner_body == null or animation_player == null:
		return

	# Если сейчас проигрывается одноразовая атака или HitReact,
	# locomotion не должна перезаписать AnimationPlayer.
	if _is_action_animation_playing():
		return

	var horizontal_speed := Vector2(
		owner_body.velocity.x,
		owner_body.velocity.z
	).length()

	if not owner_body.is_on_floor():
		_play_loop(&"Jump")
	elif horizontal_speed > 0.15:
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
			"MixamoAnimationComponent: не найден клип "
			+ String(clip_name)
		)
		return

	current_loop = &""
	_set_animation_speed(attack_animation_speed)
	animation_player.play(clip_name)

	print(
		"MixamoAnimationComponent: PLAY | clip=%s | speed=%.2f"
		% [
			String(clip_name),
			attack_animation_speed
		]
	)


func _on_damage_taken() -> void:
	if not animation_player.has_animation(&"HitReact"):
		push_warning(
			"MixamoAnimationComponent: не найден клип HitReact"
		)
		return

	current_loop = &""
	_set_animation_speed(movement_animation_speed)
	animation_player.play(&"HitReact")


func _on_attack_cancelled(_reason: String) -> void:
	# CombatComponent уже сообщил об interruption.
	# Никаких таймеров здесь нет: просто возвращаем визуал
	# к locomotion.
	current_loop = &""
	_set_animation_speed(movement_animation_speed)
	_play_loop(&"Idle")


func _on_animation_finished(animation_name: StringName) -> void:
	match animation_name:
		&"AttackLeft", &"AttackRight", &"AttackUp":
			_set_animation_speed(movement_animation_speed)
			current_loop = &""
			attack_animation_finished.emit()

			print(
				"MixamoAnimationComponent: ATTACK_ANIMATION_FINISHED | clip=%s"
				% String(animation_name)
			)

		&"HitReact":
			_set_animation_speed(movement_animation_speed)
			current_loop = &""


func _clip_for_direction(direction: String) -> StringName:
	match direction:
		"LEFT":
			return &"AttackLeft"
		"RIGHT":
			return &"AttackRight"
		"UP":
			return &"AttackUp"
		_:
			push_warning(
				"MixamoAnimationComponent: неизвестное направление атаки: "
				+ direction
			)
			return &"AttackRight"


func _play_loop(clip_name: StringName) -> void:
	if animation_player == null:
		return

	if _is_action_animation_playing():
		return

	if current_loop == clip_name:
		return

	if not animation_player.has_animation(clip_name):
		push_warning(
			"MixamoAnimationComponent: не найден цикл "
			+ String(clip_name)
		)
		return

	current_loop = clip_name
	_set_animation_speed(movement_animation_speed)
	animation_player.play(clip_name)


func _is_action_animation_playing() -> bool:
	if animation_player == null:
		return false

	var current := animation_player.current_animation

	return (
		current == &"AttackLeft"
		or current == &"AttackRight"
		or current == &"AttackUp"
		or current == &"HitReact"
	)


func apply_runtime_speeds() -> void:
	_set_animation_speed(movement_animation_speed)


func _set_animation_speed(value: float) -> void:
	if animation_player != null:
		animation_player.speed_scale = maxf(value, 0.01)
