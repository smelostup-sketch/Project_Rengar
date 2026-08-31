extends Node3D
class_name MixamoAnimationLibrary

## Модель Y Bot и клипы Mixamo имеют одинаковый риг.
## Скрипт добавляет копии их Animation в AnimationPlayer модели, чтобы один
## Skeleton3D использовался для всех состояний. Этот же загрузчик работает
## и у игрока, и у противника: визуальная модель не дублирует боевую логику.

const ANIMATION_SOURCES := {
	&"Idle": "res://Assets/Mixamo/Idle.fbx",
	&"Run": "res://Assets/Mixamo/Running.fbx",
	&"Jump": "res://Assets/Mixamo/Running Jump.fbx",
	&"HitReact": "res://Assets/Mixamo/Reaction.fbx",
	&"AttackLeft": "res://Assets/Mixamo/AT_LEFT.fbx",
	&"AttackRight": "res://Assets/Mixamo/AT_RIGHT.fbx",
	# Временный отдельный state: пока нет AT_UP.fbx, используется тот же
	# исходный клип. Замена пути позже не потребует менять input/FSM-код.
	&"AttackUp": "res://Assets/Mixamo/AT_RIGHT.fbx",
}

func _ready() -> void:
	var target_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if target_player == null:
		push_error("MixamoAnimationLibrary: у VisualModel не найден AnimationPlayer")
		return

	var library := target_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		target_player.add_animation_library(&"", library)

	for animation_name in ANIMATION_SOURCES:
		_add_clip(target_player, library, animation_name, ANIMATION_SOURCES[animation_name])

	print("MixamoAnimationLibrary: загружены ", target_player.get_animation_list())

func _add_clip(target_player: AnimationPlayer, library: AnimationLibrary, animation_name: StringName, source_path: String) -> void:
	var source_scene := load(source_path) as PackedScene
	if source_scene == null:
		push_error("MixamoAnimationLibrary: не найден FBX " + source_path)
		return

	var source_root := source_scene.instantiate()
	var source_player := source_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if source_player == null:
		push_error("MixamoAnimationLibrary: в " + source_path + " нет AnimationPlayer")
		source_root.queue_free()
		return

	var source_animation := source_player.get_animation(&"mixamo_com")
	if source_animation == null:
		push_error("MixamoAnimationLibrary: в " + source_path + " нет клипа mixamo_com")
		source_root.queue_free()
		return

	var copy := source_animation.duplicate(true) as Animation
	if animation_name == &"Idle" or animation_name == &"Run":
		copy.loop_mode = Animation.LOOP_LINEAR
	else:
		copy.loop_mode = Animation.LOOP_NONE

	if library.has_animation(animation_name):
		library.remove_animation(animation_name)
	library.add_animation(animation_name, copy)
	source_root.queue_free()
