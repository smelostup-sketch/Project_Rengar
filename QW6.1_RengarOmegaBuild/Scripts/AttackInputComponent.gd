extends Node
class_name AttackInputComponent

## Компонент ввода направленной атаки.
## Он владеет вводом, ожиданием жеста и последовательностью атаки. Урон,
## хитбоксы, физика и анимационные клипы остаются в их профильных компонентах.

signal waiting_for_direction_started
signal direction_locked(direction: String)
signal attack_committed(direction: String)
signal attack_input_cancelled(reason: String)
signal attack_sequence_finished

enum InputState { IDLE, WAITING_DIRECTION, START_DELAY, ATTACKING }

@export_group("Attack Direction Input")
@export_range(0.0, 0.25, 0.01, "suffix:s") var attack_start_delay := 0.05
@export_range(0.1, 10.0, 0.1) var direction_threshold := 0.5
@export var combat_path: NodePath = NodePath("../CombatComponent")
@export var state_path: NodePath = NodePath("../StateComponent")
@export var animation_component_path: NodePath = NodePath("../AnimationComponent")

@export_group("Debug")
@export var debug_logging := true

var owner_body: CharacterBody3D
var combat_comp: CombatComponent
var state_comp: StateComponent
var animation_component: Node
var input_state: InputState = InputState.IDLE
var accumulated_mouse_delta := Vector2.ZERO
var locked_direction := ""
var delay_left := 0.0

func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("AttackInputComponent должен быть дочерним узлом CharacterBody3D")
		return

	combat_comp = get_node_or_null(combat_path) as CombatComponent
	state_comp = get_node_or_null(state_path) as StateComponent
	animation_component = get_node_or_null(animation_component_path)
	if combat_comp == null or state_comp == null:
		push_error("AttackInputComponent: не найдены CombatComponent или StateComponent")
		return

	combat_comp.attack_cancelled.connect(_on_combat_attack_cancelled)
	combat_comp.attack_finished.connect(_on_attack_finished)
	_trace("READY | delay=%.2fs threshold=%.2f" % [attack_start_delay, direction_threshold])

func _physics_process(delta: float) -> void:
	if input_state != InputState.START_DELAY:
		return

	if not _can_continue_attack():
		_cancel_input("state_invalid")
		return

	delay_left -= delta
	if delay_left <= 0.0:
		_commit_attack()

func process_mouse_delta(relative: Vector2) -> void:
	if input_state != InputState.WAITING_DIRECTION:
		return

	accumulated_mouse_delta += relative
	var candidate := _resolve_direction(accumulated_mouse_delta)
	if candidate.is_empty():
		return

	locked_direction = candidate
	input_state = InputState.START_DELAY
	delay_left = attack_start_delay
	direction_locked.emit(locked_direction)
	_trace("DIRECTION_LOCKED | dir=%s delta=%s | start in %.2fs" % [locked_direction, _format_delta(), attack_start_delay])

func press_attack() -> bool:
	if input_state != InputState.IDLE:
		_trace("PRESS_IGNORED | state=%s | reason=active_sequence" % get_state_name())
		return false
	if not _can_begin_attack():
		_trace("PRESS_IGNORED | state=%s | reason=%s" % [get_state_name(), _get_begin_failure_reason()])
		return false

	input_state = InputState.WAITING_DIRECTION
	accumulated_mouse_delta = Vector2.ZERO
	locked_direction = ""
	delay_left = 0.0
	waiting_for_direction_started.emit()
	_trace("PRESS_ACCEPTED | state=WAITING_DIRECTION | waiting for mouse direction")
	return true

func release_attack() -> void:
	# Быстрый клик до выбора направления полностью отменяется. После фиксации
	# направления отпускание больше не отменяет последовательность.
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("released_before_direction")
	elif input_state == InputState.START_DELAY or input_state == InputState.ATTACKING:
		_trace("RELEASE_IGNORED | state=%s | attack continues" % get_state_name())

func request_block() -> bool:
	if not can_start_block():
		_trace("BLOCK_REJECTED | state=%s | reason=invalid_context" % get_state_name())
		return false

	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("block_before_direction")
	elif input_state == InputState.START_DELAY or input_state == InputState.ATTACKING:
		_trace("BLOCK_CANCEL | state=%s" % get_state_name())
		combat_comp.cancel_player_attack("block")
	return true

func request_dash_cancel() -> void:
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("dash_before_direction")
	elif input_state == InputState.START_DELAY or input_state == InputState.ATTACKING:
		_trace("DASH_CANCEL | state=%s" % get_state_name())
		combat_comp.cancel_player_attack("dash")

func cancel_pending_direction_for_dodge() -> void:
	# Dodge не прерывает начатую атаку. До фиксации направления атаки ещё нет,
	# поэтому только незавершённое ожидание может быть закрыто dodge-вводом.
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("dodge_before_direction")

func blocks_dodge_start() -> bool:
	return input_state == InputState.START_DELAY or input_state == InputState.ATTACKING

func can_start_block() -> bool:
	if combat_comp == null or state_comp == null or owner_body == null:
		return false
	if not owner_body.is_on_floor() or state_comp.is_leaping:
		return false
	if state_comp.is_dashing or state_comp.is_dodging:
		return false
	if state_comp.is_climbing or state_comp.is_swimming:
		return false
	return true

func is_waiting_for_direction() -> bool:
	return input_state == InputState.WAITING_DIRECTION

func is_attack_in_progress() -> bool:
	return input_state == InputState.START_DELAY or input_state == InputState.ATTACKING

func get_state_name() -> String:
	return InputState.keys()[input_state]

func get_debug_mouse_delta() -> Vector2:
	return accumulated_mouse_delta

func get_debug_direction() -> String:
	return locked_direction

func _can_begin_attack() -> bool:
	# Атака разрешена на земле, в движении и в воздухе. Отказ происходит сразу
	# на нажатии ЛКМ, а не после ожидания направления, что исключает ложное
	# зависание последовательности при спаме во время recovery/lock/block.
	if state_comp == null or combat_comp == null:
		return false
	return not state_comp.is_dodging and not combat_comp.is_input_locked and not combat_comp.is_block_active and not combat_comp.is_recovery

func _get_begin_failure_reason() -> String:
	if state_comp == null or combat_comp == null:
		return "component_missing"
	if state_comp.is_dodging:
		return "dodge_active"
	if combat_comp.is_input_locked:
		return "input_locked"
	if combat_comp.is_block_active:
		return "block_active"
	if combat_comp.is_recovery:
		return "recovery_active"
	return "unknown"

func _can_continue_attack() -> bool:
	# Dodge не должен принудительно отменять уже подтверждённую атаку.
	return state_comp != null

func _resolve_direction(delta: Vector2) -> String:
	# Утверждённые направления: Right, Left и Up. Нижний жест не содержит
	# скрытого fallback и продолжает ожидание до валидного движения.
	if delta.y < -direction_threshold and absf(delta.y) > absf(delta.x):
		return "UP"
	if absf(delta.x) >= direction_threshold:
		# v6: горизонтальный жест инвертирован относительно прежней схемы.
		return "RIGHT" if delta.x < 0.0 else "LEFT"

	return ""

func _commit_attack() -> void:
	if input_state != InputState.START_DELAY or combat_comp == null:
		return
	_trace("ATTACK_START_ATTEMPT | dir=%s | leap=%s" % [locked_direction, str(state_comp.is_leaping)])
	if not combat_comp.perform_directional_attack(locked_direction, state_comp.is_leaping):
		_cancel_input("combat_rejected")
		return

	input_state = InputState.ATTACKING
	attack_committed.emit(locked_direction)
	_trace("ATTACK_STARTED | dir=%s | state=ATTACKING" % locked_direction)

func _cancel_input(reason: String) -> void:
	if input_state == InputState.IDLE:
		return
	var previous_state := get_state_name()
	input_state = InputState.IDLE
	accumulated_mouse_delta = Vector2.ZERO
	locked_direction = ""
	delay_left = 0.0
	attack_input_cancelled.emit(reason)
	_trace("ATTACK_FINISHED | from=%s | reason=%s" % [previous_state, reason])

func _on_combat_attack_cancelled(reason: String) -> void:
	_cancel_input(reason)

func _on_attack_finished() -> void:
	if input_state == InputState.ATTACKING:
		input_state = InputState.IDLE
		attack_sequence_finished.emit()
		_trace("ATTACK_FINISHED | from=ATTACKING | reason=animation_complete")

func _format_delta() -> String:
	return "(%.1f, %.1f)" % [accumulated_mouse_delta.x, accumulated_mouse_delta.y]

func _trace(message: String) -> void:
	if debug_logging:
		print("[AttackInput] ", message)
