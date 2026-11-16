extends Control
# скрипти/shop_ui.gd — екран магазину: вкладки (Ножі / АК-47 / M4 / AWP), сітка карток, панель деталей справа.
# Товари беруться з Economy (KNIVES, WEAPON_SKINS), куплене/вибране — з Economy.view_*.
# Купівля й вибір — ті самі RPC, що й раніше: Economy.request_buy_* / request_equip_*.

const Kit := preload("res://скрипти/ui_kit.gd")

signal closed

const WEAPON_TITLE := {"ak47": "AK-47", "m4": "M4", "awp": "AWP"}
const TABS := [["knife", "НОЖІ"], ["ak47", "АК-47"], ["m4", "M4"], ["awp", "AWP"]]

# Чи можна зараз купувати/вибирати (є звʼязок із сервером). Задає menu.gd.
var online_check: Callable = Callable()

var _tab := "knife"
var _selected := ""
var _tab_buttons: Dictionary = {}
var _grid: GridContainer
var _cards: Dictionary = {}
var _coin_label: Label
var _detail_preview: Control
var _detail_name: Label
var _detail_info: VBoxContainer
var _detail_btn: Button
var _msg: Label
var _detail_sig := ""


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := Kit.Backdrop.new(false)
	bg.glow_center = Vector2(0.82, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 40)
	root.add_theme_constant_override("margin_right", 40)
	root.add_theme_constant_override("margin_top", 22)
	root.add_theme_constant_override("margin_bottom", 26)
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_tabs())
	col.add_child(_build_body())

	_msg = Kit.label("", 18, Kit.C_GOLD, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_msg.custom_minimum_size = Vector2(0, 26)
	col.add_child(_msg)


# ---------------------------------------------------------------- шапка
func _build_header() -> Control:
	var h := Control.new()
	h.custom_minimum_size = Vector2(0, 72)

	var back := Button.new()
	back.text = "‹  НАЗАД"
	Kit.style_button(back, "ghost", 22)
	back.anchor_top = 0.5
	back.anchor_bottom = 0.5
	back.offset_top = -26
	back.offset_bottom = 26
	back.offset_right = 170
	back.pressed.connect(close)
	h.add_child(back)

	var plate := Kit.TitlePlate.new()
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -230
	plate.offset_right = 230
	plate.offset_top = -22
	plate.offset_bottom = 66
	h.add_child(plate)
	var title := Kit.label("МАГАЗИН", 46, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 4)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(title)

	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 10)
	coins.add_child(Kit.CoinIcon.new(28))
	_coin_label = Kit.label("...", 26, Kit.C_GOLD)
	coins.add_child(_coin_label)
	var pill := Kit.pill(coins, 16, 8)
	pill.add_theme_stylebox_override("panel", Kit.box(Color("2b2210"), Kit.C_GOLD, 1, 8))
	pill.anchor_left = 1.0
	pill.anchor_right = 1.0
	pill.anchor_top = 0.5
	pill.anchor_bottom = 0.5
	pill.offset_left = -130
	pill.offset_right = 0
	pill.offset_top = -27
	pill.offset_bottom = 27
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.add_child(pill)
	return h


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for t in TABS:
		var id: String = t[0]
		var b := Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(150, 42)
		b.pressed.connect(func(): _set_tab(id))
		row.add_child(b)
		_tab_buttons[id] = b
	return row


# ---------------------------------------------------------------- тіло: сітка + деталі
func _build_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 2.3
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)   # місце під свічення карток
	scroll.add_child(pad)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	pad.add_child(_grid)

	body.add_child(_build_detail())
	return body


func _build_detail() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.custom_minimum_size = Vector2(400, 0)
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.055, 0.06, 0.075, 0.95), Color("2c303b"), 1, 10))

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 130)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	v.add_child(holder)
	_detail_preview = holder

	_detail_name = Kit.label("", 26, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_LEFT, 1)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)

	_detail_info = VBoxContainer.new()
	_detail_info.add_theme_constant_override("separation", 8)
	v.add_child(_detail_info)

	_detail_btn = Button.new()
	_detail_btn.custom_minimum_size = Vector2(0, 72)
	_detail_btn.pressed.connect(func(): _act(_selected_item()))
	v.add_child(_detail_btn)
	return panel


# ---------------------------------------------------------------- дані
func _online() -> bool:
	return online_check.is_valid() and bool(online_check.call())


func _current_skin(weapon: String) -> String:
	if weapon == "m4":
		return ""   # скінів для M4 поки немає
	if Economy.view_coins >= 0:
		return str(Economy.view_skins.get(weapon, ""))
	return Loadout.ak_skin if weapon == "ak47" else Loadout.awp_skin


func _current_knife() -> String:
	return Economy.view_equipped if Economy.view_equipped != "" else Loadout.knife


func _items(tab: String) -> Array:
	var out: Array = []
	if tab == "knife":
		for id in Economy.KNIFE_ORDER:
			var info: Dictionary = Economy.KNIVES[id]
			var price := int(info["price"])
			out.append({
				"key": "knife:" + id, "kind": "knife", "id": id, "weapon": "knife", "model": id, "skin": "",
				"line1": str(info["name"]).to_upper(), "line2": "", "full": str(info["name"]).to_upper(),
				"price": price, "owned": price == 0 or Economy.view_owned.has(id),
				"equipped": _current_knife() == id, "rarity": Kit.rarity_of(info, price)})
		return out
	var title: String = WEAPON_TITLE[tab]
	var cur := _current_skin(tab)
	out.append({
		"key": tab + ":", "kind": "default", "id": "", "weapon": tab, "model": tab, "skin": "",
		"line1": title, "line2": "СТАНДАРТНИЙ", "full": "%s | СТАНДАРТНИЙ" % title,
		"price": 0, "owned": true, "equipped": cur == "", "rarity": "common"})
	for sid in Economy.SKIN_ORDER:
		var info: Dictionary = Economy.WEAPON_SKINS[sid]
		if str(info["weapon"]) != tab:
			continue
		var price := int(info["price"])
		out.append({
			"key": tab + ":" + sid, "kind": "skin", "id": sid, "weapon": tab, "model": tab, "skin": sid,
			"line1": title, "line2": str(info["skin"]).to_upper(), "full": str(info["name"]).to_upper(),
			"price": price, "owned": Economy.view_owned.has(sid), "equipped": cur == sid,
			"rarity": Kit.rarity_of(info, price)})
	return out


func _selected_item() -> Dictionary:
	for it in _items(_tab):
		if it["key"] == _selected:
			return it
	return {}


# ---------------------------------------------------------------- дії
func _act(it: Dictionary) -> void:
	if it.is_empty() or not _online():
		return
	match str(it["kind"]):
		"knife":
			if it["owned"]:
				Economy.request_equip_knife.rpc_id(1, it["id"])
			else:
				Economy.request_buy_knife.rpc_id(1, it["id"])
		"default":
			if str(it["weapon"]) == "m4":
				return   # у M4 лише стандартний вигляд, на сервер нічого слати не треба
			Economy.request_equip_skin.rpc_id(1, it["weapon"], "")
		"skin":
			if it["owned"]:
				Economy.request_equip_skin.rpc_id(1, it["weapon"], "" if it["equipped"] else it["id"])
			else:
				Economy.request_buy_skin.rpc_id(1, it["id"])


# Текст і вигляд головної кнопки дії для предмета.
func _action_for(it: Dictionary) -> Array:   # [текст, вид, вимкнена?]
	if it["kind"] == "knife" or it["kind"] == "default":
		if it["equipped"]:
			return ["ОБРАНО", "dim", true]
		return ["ОБРАТИ", "primary", false] if it["owned"] else ["КУПИТИ — %d" % it["price"], "primary", false]
	if it["equipped"]:
		return ["ЗНЯТИ СКІН", "ghost", false]
	return ["ОБРАТИ", "primary", false] if it["owned"] else ["КУПИТИ — %d" % it["price"], "primary", false]


# ---------------------------------------------------------------- показ
func open() -> void:
	_msg.text = ""
	_detail_sig = ""
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func set_message(text: String) -> void:
	if _msg != null:
		_msg.text = text


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _set_tab(id: String) -> void:
	_tab = id
	_selected = ""
	_detail_sig = ""
	refresh()


func refresh() -> void:
	if _grid == null or not visible:
		return
	_coin_label.text = "..." if Economy.view_coins < 0 else str(Economy.view_coins)
	for id in _tab_buttons:
		Kit.style_button(_tab_buttons[id], "tab_on" if id == _tab else "tab_off", 20)

	var items := _items(_tab)
	if _selected == "" or not items.any(func(i): return i["key"] == _selected):
		# Перший вибір: те, що зараз обрано, інакше перший товар.
		_selected = str(items[0]["key"])
		for it in items:
			if it["equipped"]:
				_selected = str(it["key"])

	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	for it in items:
		var card := _make_card(it)
		_grid.add_child(card)
		_cards[it["key"]] = card
	_refresh_detail()


func _make_card(it: Dictionary) -> Control:
	var rc := Kit.rarity_color(it["rarity"])
	var selected: bool = it["key"] == _selected
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 250)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", Kit.box(
		Color(rc.r * 0.14 + 0.04, rc.g * 0.14 + 0.04, rc.b * 0.14 + 0.05, 0.95),
		rc.lightened(0.25) if selected else rc, 2 if selected else 1, 8,
		Color(rc, 0.35 if selected else 0.12), 12 if selected else 6))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_selected = str(it["key"])
			refresh())

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 100)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(holder)
	var pv := Kit.make_preview(it["model"], it["skin"], Color("8e98ab"), true)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pv)
	var star := Kit.Star.new(18, rc)
	star.anchor_left = 1.0
	star.anchor_right = 1.0
	star.offset_left = -18
	star.offset_top = 0
	star.offset_bottom = 18
	holder.add_child(star)

	var names := Kit.label(str(it["line1"]) + ("\n" + str(it["line2"]) if it["line2"] != "" else ""), 22, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_LEFT, 1)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(names)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(price_row)
	if it["price"] > 0 and not it["owned"]:
		var ci := Kit.CoinIcon.new(22)
		price_row.add_child(ci)
		var enough: bool = Economy.view_coins >= int(it["price"])
		price_row.add_child(Kit.label(str(it["price"]), 24, Kit.C_GOLD if enough else Kit.C_RED_HI))
	else:
		price_row.add_child(Kit.label("Є У ТЕБЕ" if it["price"] > 0 else "БЕЗКОШТОВНО", 16, Kit.C_MUTED, true))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	v.add_child(btns)
	var state_b := Button.new()
	state_b.text = "ОБРАНО"
	state_b.disabled = true
	state_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_b.custom_minimum_size = Vector2(0, 38)
	Kit.style_button(state_b, "gold" if it["equipped"] else "dim", 15)
	if it["equipped"]:
		state_b.add_theme_color_override("font_disabled_color", Kit.C_GOLD)
		state_b.add_theme_stylebox_override("disabled", Kit.box(Color("2b2210"), Kit.C_GOLD, 1, 6))
	btns.add_child(state_b)

	var act := _action_for(it)
	var buy_b := Button.new()
	buy_b.text = "КУПИТИ" if not it["owned"] else ("ЗНЯТИ" if (it["equipped"] and it["kind"] == "skin") else "ОБРАТИ")
	buy_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_b.custom_minimum_size = Vector2(0, 38)
	buy_b.disabled = bool(act[2]) or not _online()
	var kind: String = it["rarity"] if it["rarity"] != "common" else "ghost"
	Kit.style_button(buy_b, kind, 15)
	buy_b.pressed.connect(func():
		_selected = str(it["key"])
		_act(it)
		refresh())
	btns.add_child(buy_b)
	return card


func _refresh_detail() -> void:
	var it := _selected_item()
	if it.is_empty():
		return
	var sig := "%s|%s|%s|%s" % [it["key"], it["owned"], it["equipped"], _online()]
	var rc := Kit.rarity_color(it["rarity"])

	if _detail_preview.get_child_count() == 0 or _detail_sig.split("|")[0] != it["key"]:
		for c in _detail_preview.get_children():
			_detail_preview.remove_child(c)
			c.queue_free()
		var pv := Kit.make_preview(it["model"], it["skin"], Color("a3acbf"), true, true)   # у деталях скін крутиться в 3D
		pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_detail_preview.add_child(pv)
	_detail_sig = sig

	_detail_name.text = str(it["full"])

	for c in _detail_info.get_children():
		_detail_info.remove_child(c)
		c.queue_free()
	var status := "ОБРАНО" if it["equipped"] else ("КУПЛЕНО" if it["owned"] else "НЕ КУПЛЕНО")
	_detail_info.add_child(_info_row("СТАТУС", status, Kit.C_GOLD if it["equipped"] else Kit.C_TEXT))
	var kind_name := "НІЖ" if it["kind"] == "knife" else ("СКІН" if it["kind"] == "skin" else "БАЗОВИЙ ВИГЛЯД")
	_detail_info.add_child(_info_row("ТИП", kind_name, Kit.C_TEXT))
	var price_text := "—" if it["owned"] or it["price"] == 0 else "%d" % it["price"]
	_detail_info.add_child(_info_row("ЦІНА", price_text, Kit.C_GOLD if price_text != "—" else Kit.C_MUTED))
	var bar := ColorRect.new()
	bar.color = rc
	bar.custom_minimum_size = Vector2(0, 3)
	_detail_info.add_child(bar)

	var act := _action_for(it)
	_detail_btn.text = act[0]
	_detail_btn.disabled = bool(act[2]) or not _online()
	Kit.style_button(_detail_btn, act[1], 32)
	if not _online():
		_msg.text = "Немає звʼязку з сервером — купувати й вибирати поки не можна."
	elif _msg.text.begins_with("Немає звʼязку"):
		_msg.text = ""


func _info_row(k: String, v: String, vcol: Color) -> Control:
	var r := HBoxContainer.new()
	var kl := Kit.label(k, 15, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_LEFT, 1)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(kl)
	r.add_child(Kit.label(v, 18, vcol, true, HORIZONTAL_ALIGNMENT_RIGHT, 1))
	return r
