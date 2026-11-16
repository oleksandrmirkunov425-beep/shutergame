extends Control
# скрипти/menu_ui.gd — головне меню: кнопки ліворуч, вітрина зі зброєю по центру,
# нік і баланс угорі праворуч, оверлей пошуку суперника.
# Усе будується кодом (як і решта меню). menu.gd лише створює цей вузол і слухає сигнали.

const Kit := preload("res://скрипти/ui_kit.gd")

signal play_pressed
signal bot_pressed
signal shop_pressed
signal settings_pressed
signal quit_pressed
signal cancel_search_pressed

var _coin_label: Label
var _gain_label: Label
var _stage: Control
var _terrorist: Kit.TerroristStage
var _search_layer: Control
var _search_label: Label
var _showcase_sig := ""   # що зараз у вітрині — щоб не перебудовувати, якщо нічого не змінилось


func build(nick_input: LineEdit) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := Kit.Backdrop.new(true)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_stage()
	_build_left_panel()
	_build_top_right(nick_input)
	_build_search_overlay()
	refresh(0)


# ---------------------------------------------------------------- ліва панель
func _build_left_panel() -> void:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.anchor_right = 0.29
	panel.offset_right = 0
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.045, 0.05, 0.062, 0.94), Color("22252e"), 1, 0))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 56)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	box.add_child(_menu_button("ГРАТИ", "primary", play_pressed))
	box.add_child(_menu_button("ГРАТИ ПРОТИ БОТА", "ghost", bot_pressed))
	box.add_child(_menu_button("МАГАЗИН", "ghost", shop_pressed))
	box.add_child(_menu_button("НАЛАШТУВАННЯ", "ghost", settings_pressed))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var quit := Button.new()
	quit.text = "ВИЙТИ"
	quit.custom_minimum_size = Vector2(150, 46)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Kit.style_button(quit, "dim", 18)
	quit.pressed.connect(func(): quit_pressed.emit())
	box.add_child(quit)


func _menu_button(text: String, kind: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.style_button(b, kind, 28)
	b.pressed.connect(func(): sig.emit())
	return b


# ---------------------------------------------------------------- нік і баланс
func _build_top_right(nick_input: LineEdit) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_left = -440
	row.offset_right = -36
	row.offset_top = 28
	row.offset_bottom = 84
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	# Нік — це той самий LineEdit, що читає menu.gd; просто одягнений у «пігулку».
	nick_input.custom_minimum_size = Vector2(230, 54)
	nick_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nick_input.add_theme_font_override("font", Kit.font(true, 1))
	nick_input.add_theme_font_size_override("font_size", 24)
	nick_input.add_theme_color_override("font_color", Kit.C_TEXT)
	nick_input.add_theme_color_override("caret_color", Kit.C_RED_HI)
	nick_input.add_theme_color_override("font_placeholder_color", Kit.C_MUTED)
	nick_input.add_theme_stylebox_override("normal", Kit.box(Color("15171d"), Color("333743"), 1, 8))
	nick_input.add_theme_stylebox_override("focus", Kit.box(Color("1b1d25"), Kit.C_RED, 1, 8))
	row.add_child(nick_input)

	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 10)
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_child(Kit.CoinIcon.new(28))
	_coin_label = Kit.label("...", 26, Kit.C_GOLD)
	coin_row.add_child(_coin_label)
	_gain_label = Kit.label("", 18, Kit.C_GREEN)
	coin_row.add_child(_gain_label)
	var pill := Kit.pill(coin_row, 16, 8)
	pill.custom_minimum_size = Vector2(120, 54)
	row.add_child(pill)


# ---------------------------------------------------------------- вітрина
# Замість стенда зі зброєю — 3D-терорист із калашем (анімація — у Kit.TerroristStage).
func _build_stage() -> void:
	_stage = Control.new()
	_stage.anchor_left = 0.33
	_stage.anchor_right = 0.97
	_stage.anchor_top = 0.06
	_stage.anchor_bottom = 0.97
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_terrorist = Kit.TerroristStage.new()
	_terrorist.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_terrorist)


# ---------------------------------------------------------------- пошук суперника
func _build_search_overlay() -> void:
	_search_layer = ColorRect.new()
	(_search_layer as ColorRect).color = Color(0, 0, 0, 0.72)
	_search_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_search_layer.visible = false
	add_child(_search_layer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.add_theme_stylebox_override("panel", Kit.box(Color("0f1116"), Kit.C_RED, 1, 10, Color(1.0, 0.2, 0.3, 0.25), 24))
	center.add_child(card)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 30)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)

	var sp := Kit.Spinner.new()
	sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sp)
	v.add_child(Kit.label("ПОШУК СУПЕРНИКА", 28, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 2))
	_search_label = Kit.label("", 18, Kit.C_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_search_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_search_label.custom_minimum_size = Vector2(500, 52)
	v.add_child(_search_label)

	var cancel := Button.new()
	cancel.text = "СКАСУВАТИ"
	cancel.custom_minimum_size = Vector2(220, 52)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Kit.style_button(cancel, "ghost", 22)
	cancel.pressed.connect(func(): cancel_search_pressed.emit())
	v.add_child(cancel)


func show_search(on: bool) -> void:
	_search_layer.visible = on


func set_status(text: String) -> void:
	_search_label.text = text


# ---------------------------------------------------------------- оновлення з Economy / Loadout
func refresh(gain: int = 0) -> void:
	if _coin_label == null:
		return
	_coin_label.text = "..." if Economy.view_coins < 0 else str(Economy.view_coins)
	_gain_label.text = "+%d" % gain if gain > 0 else ""
	_rebuild_showcase()


func _current_skin(weapon: String) -> String:
	if Economy.view_coins >= 0:
		return str(Economy.view_skins.get(weapon, ""))
	return Loadout.ak_skin if weapon == "ak47" else Loadout.awp_skin


func _clear(c: Control) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


func _fill(holder: Control, content: Control) -> void:
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(content)


func _rebuild_showcase() -> void:
	# Терорист тримає справжній АК із вибраним скіном.
	var ak := _current_skin("ak47")
	var sig := "%s" % ak
	if sig == _showcase_sig:
		return
	_showcase_sig = sig
	if _terrorist != null:
		_terrorist.set_ak_skin(ak)
