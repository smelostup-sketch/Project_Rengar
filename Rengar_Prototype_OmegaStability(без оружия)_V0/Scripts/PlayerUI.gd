extends CanvasLayer

# === UI ЭЛЕМЕНТЫ ===
var hp_bg: ColorRect
var hp_fill: ColorRect
var gold_stacks: Array[ColorRect] = []
var purple_stack: ColorRect
var ability_icons: Array[ColorRect] = []

# === НАСТРОЙКИ РАЗМЕРОВ ===
var stack_size = Vector2(28, 28)
var ability_size = Vector2(40, 40)
var hp_bar_width = 320.0
var hp_bar_height = 20.0
var gap = 6.0
var padding_bottom = 50.0

func _ready():
	await get_tree().process_frame
	_build_ui()
	_connect_signals()

func _connect_signals():
	var player = get_tree().get_first_node_in_group("player")
	if not player: return
	
	var health = player.get_node_or_null("HealthComponent")
	if health:
		health.hp_changed.connect(_on_hp_changed)
		
	var stacks = player.get_node_or_null("StacksComponent")
	if stacks:
		stacks.stacks_updated.connect(_on_stacks_updated)

func _build_ui():
	var size = get_window().size
	var cx = size.x / 2.0
	var by = size.y - padding_bottom

	# 🔹 НИЖНЯЯ СТРОКА: Способности (4 слота, 4-й = ульта)
	var ab_start_x = cx - (ability_size.x * 4 + gap * 3) / 2.0
	for i in range(4):
		var r = ColorRect.new()
		r.size = ability_size
		r.position = Vector2(ab_start_x + i * (ability_size.x + gap), by)
		r.color = Color(0.15, 0.15, 0.15)
		ability_icons.append(r)
		add_child(r)

	# 🔹 СРЕДНЯЯ СТРОКА: HP Бар
	hp_bg = ColorRect.new()
	hp_bg.size = Vector2(hp_bar_width, hp_bar_height)
	hp_bg.position = Vector2(cx - hp_bar_width / 2.0, by - hp_bar_height - gap)
	hp_bg.color = Color(0.2, 0.2, 0.2)
	add_child(hp_bg)

	hp_fill = ColorRect.new()
	hp_fill.size = Vector2(hp_bar_width, hp_bar_height)
	hp_fill.position = hp_bg.position
	hp_fill.color = Color(0.2, 0.85, 0.2)
	add_child(hp_fill)

	# 🔹 ВЕРХНЯЯ СТРОКА: Стаки (3 золотых + 1 фиолетовый)
	var st_start_x = cx - (stack_size.x * 4 + gap * 3) / 2.0
	var st_y = by - hp_bar_height - gap * 2 - stack_size.y

	for i in range(3):
		var r = ColorRect.new()
		r.size = stack_size
		r.position = Vector2(st_start_x + i * (stack_size.x + gap), st_y)
		r.color = Color(0.15, 0.15, 0.15)
		gold_stacks.append(r)
		add_child(r)

	purple_stack = ColorRect.new()
	purple_stack.size = stack_size
	purple_stack.position = Vector2(st_start_x + 3 * (stack_size.x + gap), st_y)
	purple_stack.color = Color(0.15, 0.15, 0.15)
	add_child(purple_stack)

	# Инициализация дефолтных значений
	_on_hp_changed(100.0, 100.0)
	_on_stacks_updated(0, 0, false)

func _on_hp_changed(current: float, max_hp: float) -> void:
	if hp_fill:
		hp_fill.size.x = hp_bar_width * clamp(current / max_hp, 0.0, 1.0)

func _on_stacks_updated(gold: int, purple: int, ultimate_ready: bool) -> void:
	# Золото
	for i in range(3):
		gold_stacks[i].color = Color(1.0, 0.85, 0.2) if i < gold else Color(0.15, 0.15, 0.15)
	# Фиолет
	purple_stack.color = Color(0.7, 0.3, 1.0) if purple == 1 else Color(0.15, 0.15, 0.15)
	# Ульта (4-я способность)
	if ability_icons.size() > 3:
		ability_icons[3].color = Color(1.0, 0.3, 0.3) if ultimate_ready else Color(0.15, 0.15, 0.15)
