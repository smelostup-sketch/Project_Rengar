extends Node
class_name EnemyAIDebugVisualizer

## Визуализация решений адаптивного AI над головой противника.
## Это debug-интерфейс: он читает снимок Utility AI и ничего не меняет в бою.

@export_group("References")
@export var utility_ai_path: NodePath = NodePath("../EnemyUtilityAIComponent")
@export var label_path: NodePath = NodePath("../UtilityAIThoughtLabel")

@export_group("Display")
@export var enabled := true
@export var height := 3.45
@export var font_size := 16
@export var update_interval := 0.10
@export var show_scores := true
@export var show_memory_preferences := true

var enemy_body: CharacterBody3D
var utility_ai: EnemyUtilityAIComponent
var label: Label3D
var _time_left := 0.0

func _ready() -> void:
	enemy_body = get_parent() as CharacterBody3D
	if enemy_body == null:
		push_error("EnemyAIDebugVisualizer должен быть дочерним узлом CharacterBody3D")
		return
	utility_ai = get_node_or_null(utility_ai_path) as EnemyUtilityAIComponent
	label = get_node_or_null(label_path) as Label3D
	if utility_ai == null or label == null:
		push_error("EnemyAIDebugVisualizer: не найдены EnemyUtilityAIComponent или UtilityAIThoughtLabel")
		return
	label.position.y = height
	label.font_size = font_size
	_refresh_label()

func _process(delta: float) -> void:
	if label == null:
		return
	label.visible = enabled
	if not enabled:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = update_interval
		_refresh_label()
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		label.global_rotation.y = camera.global_rotation.y

func _refresh_label() -> void:
	if utility_ai == null or label == null:
		return
	var snapshot := utility_ai.get_debug_snapshot()
	var scores: Dictionary = snapshot.get("scores", {})
	var title := "AI · " + String(snapshot.get("profile", "UNKNOWN"))
	var decision := "РЕШЕНИЕ: " + String(snapshot.get("decision", "WAIT"))
	var reason := "Почему: " + String(snapshot.get("reason", "ожидание"))
	var lines: Array[String] = [title, decision, reason]
	if show_scores:
		lines.append("Вес: Идти %.2f | Ждать %.2f | Удар %.2f | Отход %.2f" % [
			float(scores.get(EnemyUtilityAIComponent.Decision.APPROACH, 0.0)),
			float(scores.get(EnemyUtilityAIComponent.Decision.HOLD, 0.0)),
			float(scores.get(EnemyUtilityAIComponent.Decision.ATTACK, 0.0)),
			float(scores.get(EnemyUtilityAIComponent.Decision.RETREAT, 0.0)),
		])
	if show_memory_preferences:
		lines.append("Память: атака %s %.0f%% · блок %s %.0f%% · dodge %.0f%%" % [
			String(snapshot.get("dominant_attack", "UP")),
			float(snapshot.get("dominant_attack_share", 0.0)) * 100.0,
			String(snapshot.get("dominant_block", "UP")),
			float(snapshot.get("dominant_block_share", 0.0)) * 100.0,
			float(snapshot.get("dodge_share", 0.0)) * 100.0,
		])
	lines.append("Следующий удар: " + String(snapshot.get("recommended_attack", "UP")))
	label.text = "\n".join(lines)
	label.modulate = _color_for_decision(String(snapshot.get("decision", "")))

func _color_for_decision(decision: String) -> Color:
	if decision == "ATTACK":
		return Color(1.0, 0.42, 0.32)
	if decision == "RETREAT":
		return Color(0.35, 0.86, 1.0)
	if decision == "HOLD":
		return Color(0.74, 0.60, 1.0)
	return Color(1.0, 0.92, 0.35)
