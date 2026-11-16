extends Node

@onready var network_panel: Control = $Networkpanel
@onready var host_button: Button = $Networkpanel/HostButton
@onready var ip_input: LineEdit = $Networkpanel/IPInput
@onready var join_button: Button = $Networkpanel/JoinButton   # тепер працює як "Скасувати"
@onready var status_label: Label = $Networkpanel/StatusLabel

const MAX_CONNECT_ATTEMPTS := 20

const DEFAULT_NICK_PREFIX := "Player"

var nick_input: LineEdit = null
var _ui: Control = null      # нове головне меню (скрипти/menu_ui.gd)
var _shop: Control = null    # новий екран магазину (скрипти/shop_ui.gd)
var _recent_gain: int = 0
var _bg_attempts: int = 0
var _bg_timer: Timer = null

const CROSSHAIR_SCRIPT := preload("res://weapons/crosschair.gd")
const SETTINGS_SCRIPT := preload("res://скрипти/game_settings.gd")
const MENU_UI_SCRIPT := preload("res://скрипти/menu_ui.gd")
const SHOP_UI_SCRIPT := preload("res://скрипти/shop_ui.gd")

var _settings_layer: CanvasLayer = null
var _sensitivity_slider: HSlider = null
var _scope_slider: HSlider = null
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
	_hide_legacy_ui()
	_make_nick_input()
	SETTINGS_SCRIPT.load_settings()
	_make_settings_ui()
	_make_new_ui()
	Network.connection_succeeded.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)

	Economy.profile_updated.connect(_on_profile_updated)
	Economy.shop_message.connect(func(text: String): _shop.set_message(text))
	_bg_timer = Timer.new()
	_bg_timer.one_shot = true
	_bg_timer.timeout.connect(_bg_connect)
	add_child(_bg_timer)
	_on_profile_updated()
	_bg_connect()


# ---------- Нове меню ----------
# Старі кнопки/написи зі сцени ховаємо (мережева панель лишається в сцені, але не показується:
# статус пошуку тепер малює оверлей у menu_ui.gd).
func _hide_legacy_ui() -> void:
	for c in get_children():
		if c is Control:
			(c as Control).hide()


func _make_new_ui() -> void:
	# Усе нове меню живе в CanvasLayer: так воно завжди займає весь екран, навіть якщо корінь сцени
	# Node2D, а в сцені є Camera2D (для Node2D розмір «батька» нульовий, і Control стискався б у точку).
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_ui = MENU_UI_SCRIPT.new()
	layer.add_child(_ui)
	_ui.build(nick_input)
	_ui.play_pressed.connect(_on_button_pressed)
	_ui.bot_pressed.connect(_on_bot_button_pressed)
	_ui.shop_pressed.connect(func(): _shop.open())
	_ui.settings_pressed.connect(func(): _settings_layer.visible = true)
	_ui.quit_pressed.connect(_on_button_3_pressed)
	_ui.cancel_search_pressed.connect(_on_cancel_pressed)

	_shop = SHOP_UI_SCRIPT.new()
	layer.add_child(_shop)
	_shop.build()
	_shop.online_check = func() -> bool: return _online() and Economy.view_coins >= 0


func _set_status(text: String) -> void:
	status_label.text = text
	if _ui:
		_ui.set_status(text)


func _show_search(on: bool) -> void:
	if _ui:
		_ui.show_search(on)


func _on_profile_updated() -> void:
	if Economy.view_last_reward > 0:
		_recent_gain = Economy.view_last_reward
		Economy.view_last_reward = 0
	if _ui:
		_ui.refresh(_recent_gain)
	if _shop:
		_shop.refresh()


func _online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p is WebSocketMultiplayerPeer and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# Фоновий коннект до сервера просто щоб показати баланс і відправити результат матчу з ботом.
func _bg_connect() -> void:
	if _searching or _online():
		return
	if _bg_attempts >= MAX_CONNECT_ATTEMPTS:
		return
	_bg_attempts += 1
	Network.join_game(ip_input.text.strip_edges())


# Нік: не зберігається на диск (живе лише до закриття гри), тож для тесту
# на одному ПК у кожному запущеному вікні можна ввести свій.
func _make_nick_input() -> void:
	nick_input = LineEdit.new()
	nick_input.max_length = 16
	nick_input.placeholder_text = "Введи нік"
	var current: String = str(Engine.get_meta("player_nick", ""))
	if current == "":
		current = "%s%d" % [DEFAULT_NICK_PREFIX, randi_range(100, 999)]
	nick_input.text = current
	_store_nick(current)
	nick_input.text_changed.connect(_store_nick)


func _on_bot_button_pressed() -> void:
	if nick_input:
		_store_nick(nick_input.text)
	Matchmaker.start_bot_match()

func _store_nick(text: String) -> void:
	var n := text.strip_edges()
	Engine.set_meta("player_nick", n if n != "" else "Player")


# Вікно налаштувань (вкладки "Миша" і "Приціл"); відкривається кнопкою НАЛАШТУВАННЯ в меню.
func _make_settings_ui() -> void:
	CrosshairConfig.ensure_loaded()

	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 10
	_settings_layer.visible = false
	add_child(_settings_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Налаштування"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	# Вкладки: Миша | Приціл
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tabs)

	var tab_group := ButtonGroup.new()
	var mouse_tab := Button.new()
	mouse_tab.text = "Миша"
	mouse_tab.toggle_mode = true
	mouse_tab.button_group = tab_group
	mouse_tab.button_pressed = true
	mouse_tab.custom_minimum_size = Vector2(180, 40)
	tabs.add_child(mouse_tab)

	var crosshair_tab := Button.new()
	crosshair_tab.text = "Приціл"
	crosshair_tab.toggle_mode = true
	crosshair_tab.button_group = tab_group
	crosshair_tab.custom_minimum_size = Vector2(180, 40)
	tabs.add_child(crosshair_tab)

	# --- Вкладка 1: Миша ---
	var mouse_page := VBoxContainer.new()
	mouse_page.add_theme_constant_override("separation", 14)
	vbox.add_child(mouse_page)

	_sensitivity_slider = _add_mouse_slider_row(mouse_page, "Чутливість миші", 0.1, 5.0, 0.05, SETTINGS_SCRIPT.sensitivity)
	_scope_slider = _add_mouse_slider_row(mouse_page, "Множник у прицілі", 0.1, 3.0, 0.05, SETTINGS_SCRIPT.scope_sensitivity_multiplier)

	var note := Label.new()
	note.text = "Множник прицілу додатково застосовується під час зуму снайперської гвинтівки."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_page.add_child(note)

	# --- Вкладка 2: Приціл ---
	var crosshair_page := VBoxContainer.new()
	crosshair_page.add_theme_constant_override("separation", 12)
	crosshair_page.visible = false
	vbox.add_child(crosshair_page)

	# Прев'ю на тлі, схожому на гру.
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.42, 0.5)
	bg.custom_minimum_size = Vector2(0, 140)
	crosshair_page.add_child(bg)
	var preview := Control.new()
	preview.set_script(CROSSHAIR_SCRIPT)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(preview)

	var sliders: Array = []   # [слайдер, геттер] — щоб оновити після "Скинути"
	sliders.append([_add_slider_row(crosshair_page, "Довжина", 1.0, 30.0, 1.0, CrosshairConfig.length, func(v): CrosshairConfig.length = v), func(): return CrosshairConfig.length])
	sliders.append([_add_slider_row(crosshair_page, "Товщина", 1.0, 8.0, 1.0, CrosshairConfig.thickness, func(v): CrosshairConfig.thickness = v), func(): return CrosshairConfig.thickness])
	sliders.append([_add_slider_row(crosshair_page, "Проміжок", 0.0, 25.0, 1.0, CrosshairConfig.gap, func(v): CrosshairConfig.gap = v), func(): return CrosshairConfig.gap])
	sliders.append([_add_slider_row(crosshair_page, "Розмір крапки", 1.0, 10.0, 1.0, CrosshairConfig.dot_size, func(v): CrosshairConfig.dot_size = v), func(): return CrosshairConfig.dot_size])
	sliders.append([_add_slider_row(crosshair_page, "Прозорість", 0.1, 1.0, 0.05, CrosshairConfig.opacity, func(v): CrosshairConfig.opacity = v), func(): return CrosshairConfig.opacity])

	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 24)
	crosshair_page.add_child(checks)
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
	crosshair_page.add_child(color_row)
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

	mouse_tab.pressed.connect(func():
		mouse_page.visible = true
		crosshair_page.visible = false)
	crosshair_tab.pressed.connect(func():
		mouse_page.visible = false
		crosshair_page.visible = true)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var reset_btn := Button.new()
	reset_btn.text = "Скинути"
	reset_btn.custom_minimum_size = Vector2(140, 44)
	reset_btn.pressed.connect(func():
		_sensitivity_slider.value = SETTINGS_SCRIPT.DEFAULT_SENSITIVITY
		_scope_slider.value = SETTINGS_SCRIPT.DEFAULT_SCOPE_MULTIPLIER
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
		SETTINGS_SCRIPT.sensitivity = _sensitivity_slider.value
		SETTINGS_SCRIPT.scope_sensitivity_multiplier = _scope_slider.value
		SETTINGS_SCRIPT.save_settings()
		CrosshairConfig.save_config()
		_settings_layer.visible = false)
	buttons.add_child(done_btn)


func _add_mouse_slider_row(parent: Control, title: String, min_v: float, max_v: float, step_v: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.text = "%.2f×" % slider.value
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float): value_label.text = "%.2f×" % v)
	return slider


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
	_show_search(true)
	if _online():
		_set_status("Пошук суперника...")
		Matchmaker.find_match()
		return
	_connect()


func _connect() -> void:
	_attempts += 1
	_set_status("Підключення до сервера... (безкоштовний сервер може прокидатись до хвилини)")
	Network.join_game(ip_input.text.strip_edges())


func _on_connected() -> void:
	_bg_attempts = 0
	Economy.send_hello()
	if Engine.has_meta("pending_bot_win"):
		Economy.report_bot_win.rpc_id(1, int(Engine.get_meta("pending_bot_win")))
		Engine.remove_meta("pending_bot_win")
	if not _searching:
		return
	_set_status("Пошук суперника...")
	Matchmaker.find_match()


func _on_connection_failed() -> void:
	if not _searching:
		_bg_timer.start(5.0)   # сервер міг спати — пробуємо ще
		return
	if _attempts >= MAX_CONNECT_ATTEMPTS:
		_searching = false
		_set_status("Не вдалося підключитись до сервера. Спробуй ще раз.")
		return
	_set_status("Сервер прокидається... спроба %d/%d" % [_attempts + 1, MAX_CONNECT_ATTEMPTS])
	await get_tree().create_timer(2.0).timeout
	if _searching:
		_connect()


func _on_cancel_pressed() -> void:
	_searching = false
	Matchmaker.cancel_search()
	_show_search(false)
	_bg_attempts = 0
	_bg_timer.start(1.0)   # cancel_search розриває зв'язок — відновлюємо його для балансу


func _on_button_3_pressed() -> void:
	get_tree().quit()
