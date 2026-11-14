extends Node

@onready var network_panel: Control = $Networkpanel
@onready var host_button: Button = $Networkpanel/HostButton
@onready var ip_input: LineEdit = $Networkpanel/IPInput
@onready var join_button: Button = $Networkpanel/JoinButton   # тепер працює як "Скасувати"
@onready var status_label: Label = $Networkpanel/StatusLabel

const MAX_CONNECT_ATTEMPTS := 20

const DEFAULT_NICK_PREFIX := "Player"

var nick_input: LineEdit = null

const CROSSHAIR_SCRIPT := preload("res://weapons/crosschair.gd")

var _crosshair_layer: CanvasLayer = null
var _searching: bool = false
var _attempts: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Network.is_dedicated_server():
		return

	host_button.hide()
	ip_input.visible = OS.is_debug_build()  # поле адреси лише для локальних тестів
	ip_input.placeholder_text = "Адреса сервера (порожньо = онлайн-сервер)"
	join_button.text = "Скасувати"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	join_button.pressed.connect(_on_cancel_pressed)
	_make_nick_input()
	_make_knife_buttons()
	_make_crosshair_ui()
	Network.connection_succeeded.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)


# Нік: не зберігається на диск (живе лише до закриття гри), тож для тесту
# на одному ПК у кожному запущеному вікні можна ввести свій.
func _make_nick_input() -> void:
	var title := Label.new()
	title.text = "Нік:"
	title.position = Vector2(292, 268)
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	nick_input = LineEdit.new()
	nick_input.position = Vector2(370, 262)
	nick_input.size = Vector2(344, 50)
	nick_input.max_length = 16
	nick_input.placeholder_text = "Введи нік"
	nick_input.add_theme_font_size_override("font_size", 26)
	var current: String = str(Engine.get_meta("player_nick", ""))
	if current == "":
		current = "%s%d" % [DEFAULT_NICK_PREFIX, randi_range(100, 999)]
	nick_input.text = current
	_store_nick(current)
	nick_input.text_changed.connect(_store_nick)
	add_child(nick_input)


func _store_nick(text: String) -> void:
	var n := text.strip_edges()
	Engine.set_meta("player_nick", n if n != "" else "Player")


# Вибір ножа: 3 кнопки праворуч від меню.
func _make_knife_buttons() -> void:
	var title := Label.new()
	title.text = "Ніж:"
	title.position = Vector2(1020, 285)
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	var group := ButtonGroup.new()
	var defs: Array = [["karambit", "Керамбіт", 330], ["bolisong", "Метелик", 400], ["butterfly", "Butterfly", 470]]
	for d in defs:
		var skin: String = d[0]
		var b := Button.new()
		b.text = d[1]
		b.toggle_mode = true
		b.button_group = group
		b.position = Vector2(1020, d[2])
		b.size = Vector2(250, 60)
		b.add_theme_font_size_override("font_size", 28)
		b.button_pressed = (Loadout.knife == skin)
		b.pressed.connect(func(): Loadout.set_knife(skin))
		add_child(b)


# Налаштування прицілу: кнопка під вибором ножа відкриває вікно з повзунками й прев'ю.
func _make_crosshair_ui() -> void:
	CrosshairConfig.ensure_loaded()

	var open_btn := Button.new()
	open_btn.text = "Приціл"
	open_btn.position = Vector2(1020, 560)
	open_btn.size = Vector2(250, 60)
	open_btn.add_theme_font_size_override("font_size", 28)
	open_btn.pressed.connect(func(): _crosshair_layer.visible = true)
	add_child(open_btn)

	_crosshair_layer = CanvasLayer.new()
	_crosshair_layer.layer = 10
	_crosshair_layer.visible = false
	add_child(_crosshair_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Налаштування прицілу"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	# Прев'ю на тлі, схожому на гру.
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.42, 0.5)
	bg.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(bg)
	var preview := Control.new()
	preview.set_script(CROSSHAIR_SCRIPT)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(preview)

	var sliders: Array = []   # [слайдер, геттер] — щоб оновити після "Скинути"
	sliders.append([_add_slider_row(vbox, "Довжина", 1.0, 30.0, 1.0, CrosshairConfig.length, func(v): CrosshairConfig.length = v), func(): return CrosshairConfig.length])
	sliders.append([_add_slider_row(vbox, "Товщина", 1.0, 8.0, 1.0, CrosshairConfig.thickness, func(v): CrosshairConfig.thickness = v), func(): return CrosshairConfig.thickness])
	sliders.append([_add_slider_row(vbox, "Проміжок", 0.0, 25.0, 1.0, CrosshairConfig.gap, func(v): CrosshairConfig.gap = v), func(): return CrosshairConfig.gap])
	sliders.append([_add_slider_row(vbox, "Розмір крапки", 1.0, 10.0, 1.0, CrosshairConfig.dot_size, func(v): CrosshairConfig.dot_size = v), func(): return CrosshairConfig.dot_size])
	sliders.append([_add_slider_row(vbox, "Прозорість", 0.1, 1.0, 0.05, CrosshairConfig.opacity, func(v): CrosshairConfig.opacity = v), func(): return CrosshairConfig.opacity])

	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 24)
	vbox.add_child(checks)
	var dot_check := CheckBox.new()
	dot_check.text = "Крапка в центрі"
	dot_check.button_pressed = CrosshairConfig.dot
	dot_check.toggled.connect(func(on: bool): CrosshairConfig.dot = on; CrosshairConfig.version += 1)
	checks.add_child(dot_check)
	var outline_check := CheckBox.new()
	outline_check.text = "Контур"
	outline_check.button_pressed = CrosshairConfig.outline
	outline_check.toggled.connect(func(on: bool): CrosshairConfig.outline = on; CrosshairConfig.version += 1)
	checks.add_child(outline_check)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 12)
	vbox.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "Колір"
	color_label.custom_minimum_size = Vector2(160, 0)
	color_row.add_child(color_label)
	var picker := ColorPickerButton.new()
	picker.color = CrosshairConfig.color
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(120, 32)
	picker.color_changed.connect(func(c: Color): CrosshairConfig.color = c; CrosshairConfig.version += 1)
	color_row.add_child(picker)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var reset_btn := Button.new()
	reset_btn.text = "Скинути"
	reset_btn.custom_minimum_size = Vector2(140, 44)
	reset_btn.pressed.connect(func():
		CrosshairConfig.reset_defaults()
		for pair in sliders:
			(pair[0] as HSlider).set_value_no_signal(float(pair[1].call()))
			(pair[0] as HSlider).value_changed.emit((pair[0] as HSlider).value)
		dot_check.set_pressed_no_signal(CrosshairConfig.dot)
		outline_check.set_pressed_no_signal(CrosshairConfig.outline)
		picker.color = CrosshairConfig.color)
	buttons.add_child(reset_btn)
	var done_btn := Button.new()
	done_btn.text = "Готово"
	done_btn.custom_minimum_size = Vector2(140, 44)
	done_btn.pressed.connect(func():
		CrosshairConfig.save_config()
		_crosshair_layer.visible = false)
	buttons.add_child(done_btn)


func _add_slider_row(parent: Control, title: String, min_v: float, max_v: float, step_v: float, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = value
	slider.custom_minimum_size = Vector2(280, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.text = "%.2f" % slider.value if step_v < 1.0 else "%d" % int(slider.value)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		value_label.text = "%.2f" % v if step_v < 1.0 else "%d" % int(v)
		on_change.call(v)
		CrosshairConfig.version += 1)
	return slider


# Кнопка "play": підключаємось до сервера і стаємо в чергу на матч 1х1.
func _on_button_pressed() -> void:
	if _searching:
		return
	if nick_input:
		_store_nick(nick_input.text)
	_searching = true
	_attempts = 0
	network_panel.visible = true
	_connect()


func _connect() -> void:
	_attempts += 1
	status_label.text = "Підключення до сервера... (безкоштовний сервер може прокидатись до хвилини)"
	Network.join_game(ip_input.text.strip_edges())


func _on_connected() -> void:
	if not _searching:
		return
	status_label.text = "Пошук суперника..."
	Matchmaker.find_match()


func _on_connection_failed() -> void:
	if not _searching:
		return
	if _attempts >= MAX_CONNECT_ATTEMPTS:
		_searching = false
		status_label.text = "Не вдалося підключитись до сервера. Спробуй ще раз."
		return
	status_label.text = "Сервер прокидається... спроба %d/%d" % [_attempts + 1, MAX_CONNECT_ATTEMPTS]
	await get_tree().create_timer(2.0).timeout
	if _searching:
		_connect()


func _on_cancel_pressed() -> void:
	_searching = false
	Matchmaker.cancel_search()
	network_panel.visible = false


func _on_button_3_pressed() -> void:
	get_tree().quit()
