extends Node
class_name ModelTintComponent

## Визуальный компонент: применяет единый материал к MeshInstance3D внутри
## указанной модели, не меняя коллизии, ИИ, здоровье или боевую логику.

@export var target_path: NodePath = NodePath("../EnemyVisual")
@export var tint_color := Color(0.44, 0.12, 0.72, 1.0)
@export var roughness := 0.72

func _ready() -> void:
	var target := get_node_or_null(target_path)
	if target == null:
		push_warning("ModelTintComponent: не найдена целевая модель")
		return

	var tint_material := StandardMaterial3D.new()
	tint_material.albedo_color = tint_color
	tint_material.roughness = roughness

	var meshes := target.find_children("", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_warning("ModelTintComponent: в модели нет MeshInstance3D")
		return

	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			mesh.material_override = tint_material
