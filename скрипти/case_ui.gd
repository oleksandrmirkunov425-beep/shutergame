extends Control
# скрипти/case_ui.gd — екран кейса: 3D-кейс, вміст із шансами, рулетка як у CS2 і вікно з виграшем.
# Що випаде — вирішує СЕРВЕР (Economy.request_open_case). Тут лише показ: рулетка зупиняється на предметі,
# який прислав сервер (Economy.case_opened). Відкривається з shop_ui.gd (вкладка КЕЙСИ).

const Kit := preload("res://скрипти/ui_kit.gd")

signal closed

const CELL_W := 190.0
const CELL_H := 150.0
const CELL_GAP := 8.0
const STRIP_COUNT := 64     # скільки клітинок у стрічці
const WIN_INDEX := 52       # на якій клітинці зупиняється рулетка
const SPIN_TIME := 7.0      # секунд крутіння

# Чи є звʼязок із сервером. Задає shop_ui.gd (той самий, що й для магазину).
var online_check: Callable = Callable()

var _case_id := ""
var _busy := false          # запит відправлено / рулетка крутиться / показано виграш
var _rolling := false       # рулетка крутиться просто зараз (назад вийти не можна)
var _pending_refund := 0
var _request_token := 0
var _rng := RandomNumberGenerator.new()
var _tween: Tween

var _title: Label
var _coin_label: Label
var _back_btn: Button
var _model_holder: Control
var _roulette: Control
var _view: Control
var _strip: HBoxContainer
var _open_btn: Button
var _msg: Label
var _odds_row: HBoxContainer
var _contents: GridContainer
var _result: Control


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := Kit.Backdrop.new(false)
	bg.glow_center = Vector2(0.5, 0.3)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 40)
	root.add_theme_constant_override("margin_right", 40)
	root.add_theme_constant_override("margin_top", 22)
	root.add_theme_constant_override("margin_bottom", 22)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_stage())

	_open_btn = Button.new()
	_open_btn.custom_minimum_size = Vector2(0, 64)
	_open_btn.pressed.connect(_on_open)
	col.add_child(_open_btn)

	_msg = Kit.label("", 18, Kit.C_GOLD, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_msg.custom_minimum_size = Vector2(0, 24)
	col.add_child(_msg)

	col.add_child(Kit.label("У КЕЙСІ", 20, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_LEFT, 2))
	_odds_row = HBoxContainer.new()
	_odds_row.add_theme_constant_override("separation", 22)
	col.add_child(_odds_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(pad)
	_contents = GridContainer.new()
	_contents.columns = 6
	_contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contents.add_theme_constant_override("h_separation", 10)
	_contents.add_theme_constant_override("v_separation", 10)
	pad.add_child(_contents)

	_result = Control.new()
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	add_child(_result)

	Economy.case_opened.connect(_on_case_opened)
	Economy.shop_message.connect(_on_shop_message)
	Economy.profile_updated.connect(func(): if not _busy: _update_coins())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 60)
	h.add_theme_constant_override("separation", 16)

	_back_btn = Button.new()
	_back_btn.text = "‹  НАЗАД"
	_back_btn.custom_minimum_size = Vector2(170, 52)
	Kit.style_button(_back_btn, "ghost", 22)
	_back_btn.pressed.connect(close)
	h.add_child(_back_btn)

	_title = Kit.label("", 40, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 4)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_title)

	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 10)
	coins.add_child(Kit.CoinIcon.new(28))
	_coin_label = Kit.label("...", 26, Kit.C_GOLD)
	coins.add_child(_coin_label)
	var pill := Kit.pill(coins, 16, 8)
	pill.add_theme_stylebox_override("panel", Kit.box(Color("2b2210"), Kit.C_GOLD, 1, 8))
	pill.custom_minimum_size = Vector2(170, 52)
	h.add_child(pill)
	return h


func _build_stage() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 270)
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.045, 0.05, 0.065, 0.95), Color("2c303b"), 1, 10))

	var stage := Control.new()
	stage.clip_contents = true
	panel.add_child(stage)

	_model_holder = Control.new()
	_model_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_model_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_model_holder)

	_roulette = Control.new()
	_roulette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roulette.visible = false
	stage.add_child(_roulette)

	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.clip_contents = true
	_roulette.add_child(_view)

	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", int(CELL_GAP))
	_view.add_child(_strip)

	_view.add_child(_fade(true))
	_view.add_child(_fade(false))

	# Золота риска по центру — на чому зупиниться рулетка.
	var marker := ColorRect.new()
	marker.color = Kit.C_GOLD
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.anchor_left = 0.5
	marker.anchor_right = 0.5
	marker.anchor_top = 0.0
	marker.anchor_bottom = 1.0
	marker.offset_left = -2
	marker.offset_right = 2
	_view.add_child(marker)
	return panel


func _fade(left: bool) -> TextureRect:
	var dark := Color(0.04, 0.045, 0.06, 0.95)
	var clear := Color(dark, 0.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([dark, clear]) if left else PackedColorArray([clear, dark])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 128
	gt.height = 4
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_top = 0.0
	tr.anchor_bottom = 1.0
	if left:
		tr.anchor_left = 0.0
		tr.anchor_right = 0.0
		tr.offset_right = 150
	else:
		tr.anchor_left = 1.0
		tr.anchor_right = 1.0
		tr.offset_left = -150
	return tr


# ---------------------------------------------------------------- показ
func open(case_id: String) -> void:
	if not Economy.CASES.has(case_id):
		return
	_case_id = case_id
	_busy = false
	_rolling = false
	_msg.text = ""
	_result.visible = false
	var info: Dictionary = Economy.CASES[case_id]
	_title.text = str(info["name"]).to_upper()
	_show_model()
	_build_odds()
	_build_contents()
	_update_coins()
	_update_button()
	visible = true


func close() -> void:
	if _rolling:
		return
	visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _result.visible:
			_close_result(false)
		else:
			close()
		get_viewport().set_input_as_handled()


func _online() -> bool:
	return online_check.is_valid() and bool(online_check.call())


func _update_coins() -> void:
	_coin_label.text = "..." if Economy.view_coins < 0 else str(Economy.view_coins)


func _update_button() -> void:
	var info: Dictionary = Economy.CASES.get(_case_id, {})
	var price := int(info.get("price", 0))
	_open_btn.text = "ВІДКРИТИ КЕЙС — %d" % price
	_open_btn.disabled = _busy or not _online()
	Kit.style_button(_open_btn, "primary", 30)
	_back_btn.disabled = _rolling
	if not _busy:
		_update_coins()
		if not _online():
			_msg.text = "Немає звʼязку з сервером — відкрити кейс поки не можна."
		elif _msg.text.begins_with("Немає звʼязку"):
			_msg.text = ""


func _show_model() -> void:
	_roulette.visible = false
	_model_holder.visible = true
	for c in _model_holder.get_children():
		_model_holder.remove_child(c)
		c.queue_free()
	var info: Dictionary = Economy.CASES[_case_id]
	var path := str(info.get("model", ""))
	var packed: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed != null:
		var pv := Kit.ModelPreview.new(packed)
		pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_model_holder.add_child(pv)
	else:
		var l := Kit.label(str(info["name"]).to_upper(), 36, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER, 3)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_model_holder.add_child(l)


# ---------------------------------------------------------------- вміст і шанси
func _build_odds() -> void:
	for c in _odds_row.get_children():
		_odds_row.remove_child(c)
		c.queue_free()
	var odds := Economy.case_odds(_case_id)
	for i in range(Economy.RARITY_ORDER.size() - 1, -1, -1):
		var r: String = Economy.RARITY_ORDER[i]
		if not odds.has(r):
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		var sq := ColorRect.new()
		sq.color = Kit.rarity_color(r)
		sq.custom_minimum_size = Vector2(14, 14)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sq)
		item.add_child(Kit.label("%s  %s%%" % [Economy.RARITY_NAMES[r], ("%.1f" % float(odds[r])).trim_suffix(".0")], 16, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_LEFT, 1))
		_odds_row.add_child(item)


func _build_contents() -> void:
	for c in _contents.get_children():
		_contents.remove_child(c)
		c.queue_free()
	var ids: Array = (Economy.CASES[_case_id]["items"] as Array).duplicate()
	# Рідкісні — першими.
	ids.sort_custom(func(a, b):
		return Economy.RARITY_ORDER.find(str(Economy.item_info(str(a))["rarity"])) > Economy.RARITY_ORDER.find(str(Economy.item_info(str(b))["rarity"])))
	for id in ids:
		_contents.add_child(_make_mini(str(id)))


func _item_short_name(info: Dictionary) -> String:
	if str(info["kind"]) == "skin":
		return str(Economy.WEAPON_SKINS[str(info["id"])]["skin"])
	return str(info["name"])


func _make_mini(id: String) -> Control:
	var info := Economy.item_info(id)
	var rc := Kit.rarity_color(str(info["rarity"]))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Kit.box(
		Color(rc.r * 0.14 + 0.04, rc.g * 0.14 + 0.04, rc.b * 0.14 + 0.05, 0.95), rc, 1, 6))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	v.add_child(_preview_holder(info, 64))
	var n := Kit.label(("%s\n%s" % [_weapon_title(info), _item_short_name(info)]).to_upper(), 13, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 0)
	n.clip_text = true
	v.add_child(n)
	return card


func _weapon_title(info: Dictionary) -> String:
	match str(info["weapon"]):
		"ak47": return "AK-47"
		"awp": return "AWP"
	return "НІЖ"


func _preview_holder(info: Dictionary, min_h: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, min_h)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var steel: Color = Kit.C_GOLD if str(info["kind"]) == "knife" else Color("a3acbf")
	var pv := Kit.make_preview(str(info["model"]), str(info["skin"]), steel, false)   # плоский арт: без десятків 3D-в'юпортів
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pv)
	return holder


# ---------------------------------------------------------------- відкриття й рулетка
func _on_open() -> void:
	if _busy or _case_id == "":
		return
	if not _online():
		_update_button()
		return
	var info: Dictionary = Economy.CASES[_case_id]
	var price := int(info["price"])
	if Economy.view_coins < price:
		_msg.text = "Не вистачає коїнів: потрібно %d." % price
		return
	_busy = true
	_msg.text = ""
	_update_button()
	_request_token += 1
	var token := _request_token
	Economy.request_open_case.rpc_id(1, _case_id)
	get_tree().create_timer(8.0).timeout.connect(func():
		if _busy and not _rolling and token == _request_token:
			_busy = false
			_msg.text = "Сервер не відповів. Спробуй ще раз."
			_update_button())


func _on_shop_message(text: String) -> void:
	# Сервер відмовив (напр. не вистачило коїнів) — рулетку не крутимо.
	if visible and _busy and not _rolling:
		_busy = false
		_msg.text = text
		_update_button()


func _on_case_opened(case_id: String, item_id: String, refund: int) -> void:
	if not visible or not _busy or _rolling or case_id != _case_id:
		return
	_start_roll(item_id, refund)


func _start_roll(item_id: String, refund: int) -> void:
	_rolling = true
	_pending_refund = refund
	_back_btn.disabled = true
	_model_holder.visible = false
	_roulette.visible = true
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	_rng.randomize()
	for i in STRIP_COUNT:
		var id := item_id if i == WIN_INDEX else Economy.roll_case(_case_id, _rng)
		_strip.add_child(_make_cell(id))
	await get_tree().process_frame
	await get_tree().process_frame   # дати контейнерам порахувати розміри
	var view_w := _view.size.x
	_strip.position = Vector2(0.0, (_view.size.y - CELL_H) / 2.0)
	# Зупиняємось на випадковому місці всередині виграшної клітинки — як у CS2.
	var target := WIN_INDEX * (CELL_W + CELL_GAP) + CELL_W / 2.0 + _rng.randf_range(-CELL_W * 0.38, CELL_W * 0.38)
	var end_x := view_w / 2.0 - target
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_strip, "position:x", end_x, SPIN_TIME).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func(): _on_roll_done(item_id))


func _make_cell(id: String) -> Control:
	var info := Economy.item_info(id)
	var rc := Kit.rarity_color(str(info["rarity"]))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CELL_W, CELL_H)
	card.add_theme_stylebox_override("panel", Kit.box(
		Color(rc.r * 0.16 + 0.04, rc.g * 0.16 + 0.04, rc.b * 0.16 + 0.05, 1.0), rc.darkened(0.15), 1, 6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var mm := MarginContainer.new()
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top"]:
		mm.add_theme_constant_override("margin_" + side, 8)
	mm.add_theme_constant_override("margin_top", 10)
	mm.add_child(_preview_holder(info, 80))
	v.add_child(mm)
	var n := Kit.label(_item_short_name(info).to_upper(), 14, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 0)
	n.clip_text = true
	v.add_child(n)
	var bar := ColorRect.new()
	bar.color = rc
	bar.custom_minimum_size = Vector2(0, 5)
	v.add_child(bar)
	return card


func _on_roll_done(item_id: String) -> void:
	_rolling = false
	_back_btn.disabled = false
	_update_coins()
	_show_result(item_id)


# ---------------------------------------------------------------- вікно виграшу
func _show_result(item_id: String) -> void:
	for c in _result.get_children():
		_result.remove_child(c)
		c.queue_free()
	var info := Economy.item_info(item_id)
	var rc := Kit.rarity_color(str(info["rarity"]))

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 560)
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.055, 0.06, 0.075, 0.98), rc, 2, 12, Color(rc, 0.4), 22))
	center.add_child(panel)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	v.add_child(Kit.label("ТОБІ ВИПАЛО", 20, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER, 3))
	v.add_child(Kit.label(str(Economy.RARITY_NAMES[str(info["rarity"])]), 24, rc, true, HORIZONTAL_ALIGNMENT_CENTER, 3))

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 230)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	var steel: Color = Color("a3acbf")
	var pv := Kit.make_preview(str(info["model"]), str(info["skin"]), steel, true, true)   # тут можна 3D: лише один
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pv)
	v.add_child(holder)

	var nm := Kit.label(str(info["name"]).to_upper(), 30, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 2)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)

	if _pending_refund > 0:
		var dup := Kit.label("Цей предмет у тебе вже є — повернено +%d коїнів" % _pending_refund, 20, Kit.C_GOLD, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
		dup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dup)
	else:
		v.add_child(Kit.label("Додано до твоїх предметів", 20, Kit.C_GREEN, false, HORIZONTAL_ALIGNMENT_CENTER, 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var info_case: Dictionary = Economy.CASES[_case_id]
	var again := Button.new()
	again.text = "ВІДКРИТИ ЩЕ — %d" % int(info_case["price"])
	again.custom_minimum_size = Vector2(0, 56)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.style_button(again, "ghost", 20)
	again.disabled = Economy.view_coins < int(info_case["price"]) or not _online()
	again.pressed.connect(func(): _close_result(true))
	row.add_child(again)
	var equip := Button.new()
	equip.text = "ОБРАТИ"
	equip.custom_minimum_size = Vector2(0, 56)
	equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.style_button(equip, "gold", 20)
	equip.disabled = not _online()
	equip.pressed.connect(func():
		_equip(info)
		_close_result(false))
	row.add_child(equip)
	var ok := Button.new()
	ok.text = "ЗАКРИТИ"
	ok.custom_minimum_size = Vector2(0, 56)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.style_button(ok, "primary", 20)
	ok.pressed.connect(func(): _close_result(false))
	row.add_child(ok)

	_result.visible = true


func _equip(info: Dictionary) -> void:
	if not _online():
		return
	if str(info["kind"]) == "knife":
		Economy.request_equip_knife.rpc_id(1, str(info["id"]))
	else:
		Economy.request_equip_skin.rpc_id(1, str(info["weapon"]), str(info["id"]))
	_msg.text = "Обрано: %s" % str(info["name"])


func _close_result(open_again: bool) -> void:
	_result.visible = false
	_busy = false
	_show_model()
	_update_button()
	if open_again:
		_on_open()
