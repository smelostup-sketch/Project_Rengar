extends CanvasLayer

var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
var gold_stacks: Array[ColorRect] = []
var purple_stack: ColorRect = null
var gold_count: int = 0
var stack_timer: float = 0.0  # Таймер неактивности

func _process(delta):
	if gold_count > 0:
		stack_timer += delta
		if stack_timer >= 10.0:
			reset_gold_stacks()

func _ready():
	await get_tree().process_frame
	_build_ui()
	_update_display()

func _build_ui():
	var size = get_window().size
	var cx = size.x / 2
	var by = size.y - 50

	# === HP БАР ===
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(320, 22)
	hp_bar_bg.position = Vector2(cx - 160, by)
	hp_bar_bg.color = Color(0.15, 0.15, 0.15)
	add_child(hp_bar_bg)

	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(320, 22)
	hp_bar_fill.position = hp_bar_bg.position
	hp_bar_fill.color = Color(0.2, 0.85, 0.2)
	add_child(hp_bar_fill)

	# === 3 ЗОЛОТЫХ СТЕКА ===
	var stack_y = by - 42
	var sq = 32
	var gap = 8
	var total_w = sq * 3 + gap * 2
	var start_x = cx - total_w / 2

	for i in range(3):
		var r = ColorRect.new()
		r.size = Vector2(sq, sq)
		r.position = Vector2(start_x + i * (sq + gap), stack_y)
		r.color = Color(0.15, 0.15, 0.15)
		add_child(r)
		gold_stacks.append(r)

	# === 1 ФИОЛЕТОВЫЙ СТЕК ===
	purple_stack = ColorRect.new()
	purple_stack.size = Vector2(sq, sq)
	purple_stack.position = Vector2(start_x + total_w + gap, stack_y)
	purple_stack.color = Color(0.15, 0.15, 0.15)
	add_child(purple_stack)

func add_gold_stack() -> void:
	if gold_count < 3:
		gold_count += 1
		stack_timer = 0.0  # 🔑 Сброс таймера при ударе
		_update_display()

func reset_gold_stacks() -> void:
	gold_count = 0
	stack_timer = 0.0
	_update_display()

func set_purple(active: bool) -> void:
	purple_stack.color = Color(0.7, 0.3, 1.0) if active else Color(0.15, 0.15, 0.15)

func _update_display() -> void:
	for i in range(3):
		gold_stacks[i].color = Color(1.0, 0.85, 0.2) if i < gold_count else Color(0.15, 0.15, 0.15)

func set_hp(current: float, max_hp: float) -> void:
	if hp_bar_fill == null: return # 🔑 Ждём инициализации
	var ratio = clamp(current / max_hp, 0.0, 1.0)
	hp_bar_fill.size.x = 320 * ratio
