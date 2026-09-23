extends Node3D
class_name CombatDebugVisualizer

## Встроенная 3D-отладка боя. Показывает в игровом окне:
## - красный луч и оси активного хитбокса игрока;
## - синий луч и оси активного хитбокса противника;
## - жёлтый луч накопленного движения мыши;
## - текстовое состояние новой input-FSM.

@export_group("Debug Visuals")
@export var enabled := true
@export var toggle_key := KEY_F3
@export var player_path: NodePath = NodePath("../PLayerCharacterBody3D")
@export var enemy_path: NodePath = NodePath("../EnemyCharacterBody3D")
@export_range(0.5, 8.0, 0.1) var max_mouse_ray_length := 3.0

var player_body: CharacterBody3D
var enemy_body: CharacterBody3D
var player_combat: CombatComponent
var enemy_combat: CombatComponent
var attack_input: AttackInputComponent
var line_mesh := ImmediateMesh.new()
var mesh_instance := MeshInstance3D.new()
var ray_material := StandardMaterial3D.new()
var state_label := Label3D.new()

func _ready() -> void:
	player_body = get_node_or_null(player_path) as CharacterBody3D
	enemy_body = get_node_or_null(enemy_path) as CharacterBody3D
	if player_body != null:
		player_combat = player_body.get_node_or_null("CombatComponent") as CombatComponent
		attack_input = player_body.get_node_or_null("AttackInputComponent") as AttackInputComponent
	if enemy_body != null:
		enemy_combat = enemy_body.get_node_or_null("CombatComponent") as CombatComponent

	ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_material.vertex_color_use_as_albedo = true
	ray_material.no_depth_test = true
	mesh_instance.mesh = line_mesh
	mesh_instance.material_override = ray_material
	add_child(mesh_instance)

	state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	state_label.pixel_size = 0.004
	state_label.font_size = 40
	state_label.outline_size = 6
	state_label.modulate = Color(1.0, 0.92, 0.3, 1.0)
	state_label.no_depth_test = true
	add_child(state_label)
	_update_visibility()
	print("[CombatDebug] READY | F3 toggles debug rays")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == toggle_key:
		enabled = not enabled
		_update_visibility()
		print("[CombatDebug] VISUALS ", "ON" if enabled else "OFF")
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not enabled:
		return
	_render_debug_lines()
	_update_label()

func _update_visibility() -> void:
	mesh_instance.visible = enabled
	state_label.visible = enabled
	if not enabled:
		line_mesh.clear_surfaces()

func _render_debug_lines() -> void:
	line_mesh.clear_surfaces()
	var player_candidate = player_combat.get_debug_active_hitbox() if player_combat != null else null
	var enemy_candidate = enemy_combat.get_debug_active_hitbox() if enemy_combat != null else null
	var has_player_hitbox := is_instance_valid(player_candidate) and player_candidate.is_inside_tree()
	var has_enemy_hitbox := is_instance_valid(enemy_candidate) and enemy_candidate.is_inside_tree()

	var has_mouse_ray := attack_input != null and (attack_input.is_waiting_for_direction() or attack_input.is_attack_in_progress()) and attack_input.get_debug_mouse_delta().length() >= 0.001
	if not has_player_hitbox and not has_enemy_hitbox and not has_mouse_ray:
		return

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Считываем snapshot в том же кадре после is_instance_valid. В нижний
	# renderer передаются Vector3/Basis, а не Node, поэтому queue_free() не
	# может оставить освобождённый Area3D в типизированном аргументе.
	if has_player_hitbox:
		_draw_hitbox_rays(player_candidate.global_position, player_candidate.global_transform.basis, Color(1.0, 0.15, 0.15, 1.0))
	if has_enemy_hitbox:
		_draw_hitbox_rays(enemy_candidate.global_position, enemy_candidate.global_transform.basis, Color(0.15, 0.55, 1.0, 1.0))
	_draw_mouse_direction_ray()
	line_mesh.surface_end()

func _draw_hitbox_rays(origin: Vector3, basis: Basis, color: Color) -> void:
	var forward := -basis.z.normalized()
	var right := basis.x.normalized()
	var up := basis.y.normalized()

	# Центральный боевой луч и две короткие перпендикулярные оси помогают
	# видеть позицию и ориентацию Area3D непосредственно в игровом окне.
	_add_line(origin, origin + forward * 2.0, color)
	_add_line(origin - right * 0.35, origin + right * 0.35, color.darkened(0.2))
	_add_line(origin - up * 0.35, origin + up * 0.35, color.darkened(0.2))
	_add_arrow_head(origin + forward * 2.0, forward, color)

func _draw_mouse_direction_ray() -> void:
	if player_body == null or not player_body.is_inside_tree() or attack_input == null:
		return
	if not attack_input.is_waiting_for_direction() and not attack_input.is_attack_in_progress():
		return

	var delta := attack_input.get_debug_mouse_delta()
	if delta.length() < 0.001:
		return
	var local_direction := Vector3(delta.x, 0.0, delta.y).normalized()
	var world_direction := player_body.global_transform.basis * local_direction
	world_direction.y = 0.0
	if world_direction.length() < 0.001:
		return
	world_direction = world_direction.normalized()
	var ray_length := clampf(delta.length() / maxf(attack_input.direction_threshold, 0.01), 0.25, max_mouse_ray_length)
	var origin := player_body.global_position + Vector3.UP * 2.25
	var color := Color(1.0, 0.9, 0.2, 1.0)
	_add_line(origin, origin + world_direction * ray_length, color)
	_add_arrow_head(origin + world_direction * ray_length, world_direction, color)

func _add_arrow_head(tip: Vector3, direction: Vector3, color: Color) -> void:
	var side := direction.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	var back := -direction.normalized() * 0.20
	_add_line(tip, tip + back + side * 0.11, color)
	_add_line(tip, tip + back - side * 0.11, color)

func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	line_mesh.surface_set_color(color)
	line_mesh.surface_add_vertex(from)
	line_mesh.surface_set_color(color)
	line_mesh.surface_add_vertex(to)

func _update_label() -> void:
	if player_body == null or not player_body.is_inside_tree() or attack_input == null:
		return
	state_label.global_position = player_body.global_position + Vector3.UP * 3.1
	var delta := attack_input.get_debug_mouse_delta()
	state_label.text = "DEBUG INPUT\n%s | dir: %s\nmouse: (%.1f, %.1f)" % [
		attack_input.get_state_name(),
		attack_input.get_debug_direction() if not attack_input.get_debug_direction().is_empty() else "—",
		delta.x,
		delta.y,
	]
