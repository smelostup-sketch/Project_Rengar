extends Node
class_name AnimationComponent

## Этот компонент управляет уже созданным AnimationTree.
## В сцене Player он автоматически ищет дочерний узел PlayerAnimTree,
## поэтому ссылка больше не теряется при сохранении/копировании сцены.
@export var anim_tree: AnimationTree

var root_playback: AnimationNodeStateMachinePlayback
var attack_playback: AnimationNodeStateMachinePlayback
var block_playback: AnimationNodeStateMachinePlayback

var state_comp: StateComponent
var combat_comp: CombatComponent
var owner_body: CharacterBody3D

# === HIT REACT ===
var in_hitreact := false
var hitreact_timer := 0.0
const HITREACT_DURATION := 0.35
const HIT_COOLDOWN := 0.25
var last_hit_time := -999.0

# === STATE CACHE ===
var current_root_state := ""

func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("AnimationComponent должен быть дочерним узлом CharacterBody3D")
		return

	# Устраняет исходную ошибку: AnimationTree не был назначен в Inspector.
	if anim_tree == null:
		anim_tree = owner_body.get_node_or_null("PlayerAnimTree") as AnimationTree
	if anim_tree == null:
		push_error("Не найден AnimationTree. Добавьте дочерний узел PlayerAnimTree или назначьте поле anim_tree.")
		return

	state_comp = owner_body.get_node_or_null("StateComponent") as StateComponent
	combat_comp = owner_body.get_node_or_null("CombatComponent") as CombatComponent

	anim_tree.active = true
	root_playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	attack_playback = anim_tree.get("parameters/Attack/playback") as AnimationNodeStateMachinePlayback
	block_playback = anim_tree.get("parameters/Block/playback") as AnimationNodeStateMachinePlayback

	if root_playback == null:
		push_error("Не найден parameters/playback. Корень PlayerAnimTree должен быть AnimationNodeStateMachine.")
		return

	# travel() не запускает неактивную StateMachine. Явный start делает
	# запуск детерминированным даже если в редакторе не задан Start Node.
	root_playback.start(&"Motion", true)
	current_root_state = "Motion"

	if attack_playback == null:
		push_warning("Не найден parameters/Attack/playback. Проверьте вложенный StateMachine Attack.")
	if block_playback == null:
		push_warning("Не найден parameters/Block/playback. Проверьте вложенный StateMachine Block.")

	_connect_signals()
	print("AnimationTree: Motion started")

func _connect_signals() -> void:
	if state_comp != null:
		state_comp.action_started.connect(_on_action_start)
		state_comp.action_ended.connect(_on_action_end)

	if combat_comp != null:
		combat_comp.attack_performed.connect(_on_attack)
		combat_comp.block_started.connect(_on_block_start)
		combat_comp.block_ended.connect(_on_block_end)
		combat_comp.damage_taken.connect(_on_damage)
		combat_comp.lock_ended.connect(_on_lock_end)

func _physics_process(delta: float) -> void:
	if owner_body == null or anim_tree == null:
		return

	if in_hitreact:
		hitreact_timer -= delta
		if hitreact_timer <= 0.0:
			in_hitreact = false
			_safe_root_travel("Motion")
		return

	# В текущем BlendSpace2D Forward расположен в (0, 1), поэтому
	# -local_velocity.z соответствует существующему расположению клипов.
	var local_velocity := owner_body.global_transform.basis.inverse() * owner_body.velocity
	var blend := Vector2(local_velocity.x, -local_velocity.z)
	if blend.length() > 1.0:
		blend = blend.normalized()
	anim_tree.set("parameters/Motion/blend_position", blend)

func _safe_root_travel(state_name: String) -> void:
	if root_playback == null:
		return
	if current_root_state == state_name:
		return
	current_root_state = state_name
	root_playback.travel(StringName(state_name))

func _restart_attack(state_name: String) -> void:
	if attack_playback == null:
		return
	# start(..., true) гарантирует повторный запуск той же атаки с кадра 0.
	attack_playback.start(StringName(state_name), true)

func _restart_block(state_name: String) -> void:
	if block_playback == null:
		return
	block_playback.start(StringName(state_name), true)

func _on_damage() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_hit_time < HIT_COOLDOWN or in_hitreact:
		return
	last_hit_time = now
	in_hitreact = true
	hitreact_timer = HITREACT_DURATION
	_safe_root_travel("HitReact")

func _on_action_start(dir: Vector2, action_type: StateComponent.ActionType) -> void:
	if in_hitreact:
		return
	var state_name := "Dodge" if action_type == StateComponent.ActionType.DODGE else "Dash"
	anim_tree.set("parameters/%s/blend_position" % state_name, dir)
	_safe_root_travel(state_name)

func _on_action_end() -> void:
	if not in_hitreact and (current_root_state == "Dash" or current_root_state == "Dodge"):
		_safe_root_travel("Motion")

func _on_attack(direction: String, _is_leap: bool) -> void:
	if in_hitreact:
		return
	_safe_root_travel("Attack")
	_restart_attack("Atk_" + direction)

func _on_block_start(direction: String) -> void:
	if in_hitreact:
		return
	_safe_root_travel("Block")
	_restart_block("Block_" + direction)

func _on_block_end() -> void:
	if not in_hitreact and current_root_state == "Block":
		_safe_root_travel("Motion")

func _on_lock_end() -> void:
	if not in_hitreact:
		_safe_root_travel("Motion")
