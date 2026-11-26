extends Control
# скрипти/case_ui.gd — кейс: екран з вмістом/шансами, а після натискання «ВІДКРИТИ» — повноекранна кінематографія:
#   1) кейс відкривається (анімація «Open» з самої моделі: замки, кришка, промінь, іскри);
#   2) рулетка зі скінами на весь екран;
#   3) випадіння предмета з ефектами -> кнопки «ОБРАТИ» / «ЗАБРАТИ» -> повернення в магазин.
# Що випаде — вирішує СЕРВЕР (Economy.request_open_case). Тут лише показ: рулетка зупиняється на предметі від сервера.

const Kit := preload("res://скрипти/ui_kit.gd")

signal closed                       # екран кейса закрився (магазин знову видно)
signal finished(item_id: String)    # кінематографія завершена; item_id — що випало

const CELL_W := 270.0
const CELL_H := 230.0
const CELL_GAP := 10.0
const STRIP_COUNT := 64     # скільки клітинок у стрічці
const WIN_INDEX := 52       # на якій клітинці зупиняється рулетка
const SPIN_TIME := 6.5      # секунд крутіння

# Чи є звʼязок із сервером. Задає shop_ui.gd (той самий, що й для магазину).
var online_check: Callable = Callable()

var _case_id := ""
var _busy := false          # запит відправлено / йде кінематографія
var _cinematic := false     # йде кінематографія (екран кейса недоступний)
var _rolling := false       # рулетка крутиться просто зараз
var _in_reveal := false
var _pending_item := ""
var _pending_refund := 0
var _request_token := 0
var _run_id := 0            # номер «сеансу» кінематографії: старі await-и самі гаснуть, коли він змінюється
var _rng := RandomNumberGenerator.new()
var _tweens: Array = []
var _shake := 0.0
var _last_idx := -1
var _cells: Array = []

# --- екран кейса
var _title: Label
var _coin_label: Label
var _back_btn: Button
var _model_holder: Control
var _open_btn: Button
var _msg: Label
var _odds_row: HBoxContainer
var _contents: GridContainer

# --- кінематографія
var _cine: Control
var _c_bg: ColorRect
var _c_rays: Rays
var _c_stage: CaseStage
var _c_view: Control
var _c_strip: HBoxContainer
var _c_title: Label
var _c_skip: Button
var _c_flash: ColorRect
var _c_reveal: Control
var _sfx: Array = []
var _snd_tick: AudioStreamWAV
var _snd_boom: AudioStreamWAV
var _snd_land: AudioStreamWAV


# ===================================================================== допоміжні класи
# Промені світла + м'яке сяйво за предметом.
class Rays extends Control:
	var color := Color("f2b84b")
	var intensity := 1.0
	var spin := 0.22
	var _a := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_a += delta * spin * (0.5 + intensity)
		if is_visible_in_tree() and modulate.a > 0.01:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var radius := maxf(size.x, size.y) * 0.8
		for i in 9:
			draw_circle(c, radius * (0.06 + i * 0.07), Color(color, 0.035 * intensity))
		var n := 16
		for i in n:
			var a0 := _a + TAU * float(i) / float(n)
			var a1 := a0 + TAU / float(n) * 0.42
			draw_polygon(
				PackedVector2Array([c, c + Vector2.RIGHT.rotated(a0) * radius, c + Vector2.RIGHT.rotated(a1) * radius]),
				PackedColorArray([Color(color, 0.30 * intensity), Color(color, 0.0), Color(color, 0.0)]))


# 3D-сцена кейса на весь екран: сама модель з анімацією «Open» з файлу.
class CaseStage extends SubViewportContainer:
	var cam: Camera3D
	var _ap: AnimationPlayer
	var _vp: SubViewport

	func _init(packed: PackedScene) -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vp = SubViewport.new()
		_vp.transparent_bg = true
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		add_child(_vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.64, 0.72)
		env.ambient_light_energy = 1.0
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-45, 30, 0)
		key.light_energy = 1.4
		_vp.add_child(key)
		cam = Camera3D.new()
		cam.fov = 38.0
		_vp.add_child(cam)
		set_dist(1.95)
		var model := packed.instantiate()
		_vp.add_child(model)
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_ap = aps[0]
			if _ap.has_animation("Open"):
				_ap.play("Open")
				_ap.seek(0.0, true)
				_ap.pause()   # закритий кейс, поки не скажемо відкривати

	func set_dist(z: float) -> void:
		var pos := Vector3(0.0, 0.75, z)
		cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.3, 0) - pos, Vector3.UP), pos)

	func play_open() -> void:
		if _ap != null and _ap.has_animation("Open"):
			_ap.play("Open")


# ===================================================================== побудова екрана кейса
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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 290)
	panel.add_theme_stylebox_override("panel", Kit.box(Color(0.045, 0.05, 0.065, 0.95), Color("2c303b"), 1, 10))
	_model_holder = Control.new()
	_model_holder.clip_contents = true
	_model_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_model_holder)
	col.add_child(panel)

	_open_btn = Button.new()
	_open_btn.custom_minimum_size = Vector2(0, 64)
	_open_btn.pressed.connect(_on_open)
	col.add_child(_open_btn)

	_msg = Kit.label("", 18, Kit.C_GOLD, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_msg.custom_minimum_size = Vector2(0, 24)
	col.add_child(_msg)

	col.add_child(Kit.label("IN THE CASE", 20, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_LEFT, 2))
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

	# Шар кінематографії лежить поверх усього.
	_cine = Control.new()
	_cine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cine.mouse_filter = Control.MOUSE_FILTER_STOP
	_cine.visible = false
	add_child(_cine)

	_make_sounds()
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)

	Economy.case_opened.connect(_on_case_opened)
	Economy.shop_message.connect(_on_shop_message)
	Economy.profile_updated.connect(func(): if not _busy: _update_coins())


func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 60)
	h.add_theme_constant_override("separation", 16)

	_back_btn = Button.new()
	_back_btn.text = "‹  BACK"
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


# ===================================================================== показ екрана кейса
func open(case_id: String) -> void:
	if not Economy.CASES.has(case_id):
		return
	_case_id = case_id
	_busy = false
	_cinematic = false
	_rolling = false
	_msg.text = ""
	_cine.visible = false
	var info: Dictionary = Economy.CASES[case_id]
	_title.text = str(info["name"]).to_upper()
	_show_model()
	_build_odds()
	_build_contents()
	_update_coins()
	_update_button()
	visible = true


func close() -> void:
	if _cinematic:
		return
	visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _cinematic:
		if _in_reveal:
			_finish(false)
		else:
			_skip()
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
	_open_btn.text = "OPEN CASE — %d" % price
	_open_btn.disabled = _busy or not _online()
	Kit.style_button(_open_btn, "primary", 30)
	_back_btn.disabled = _cinematic
	if not _busy:
		_update_coins()
		if not _online():
			_msg.text = "No connection to the server — the case can't be opened right now."
		elif _msg.text.begins_with("No connection"):
			_msg.text = ""


func _show_model() -> void:
	for c in _model_holder.get_children():
		_model_holder.remove_child(c)
		c.queue_free()
	var info: Dictionary = Economy.CASES[_case_id]
	var packed := _load_case_model(info)
	if packed != null:
		var pv := Kit.ModelPreview.new(packed)
		pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_model_holder.add_child(pv)
	else:
		var l := Kit.label(str(info["name"]).to_upper(), 36, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER, 3)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_model_holder.add_child(l)


func _load_case_model(info: Dictionary) -> PackedScene:
	var path := str(info.get("model", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


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
	ids.sort_custom(func(a, b):
		return Economy.RARITY_ORDER.find(str(Economy.item_info(str(a))["rarity"])) > Economy.RARITY_ORDER.find(str(Economy.item_info(str(b))["rarity"])))
	for id in ids:
		_contents.add_child(_make_mini(str(id)))


func _item_short_name(info: Dictionary) -> String:
	if str(info["kind"]) == "skin":
		return str(Economy.WEAPON_SKINS[str(info["id"])]["skin"])
	return str(info["name"])


func _weapon_title(info: Dictionary) -> String:
	match str(info["weapon"]):
		"ak47": return "AK-47"
		"awp": return "AWP"
	return "KNIFE"


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


func _preview_holder(info: Dictionary, min_h: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, min_h)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var steel: Color = Kit.C_GOLD if str(info["kind"]) == "knife" else Color("a3acbf")
	var pv := Kit.make_thumb(str(info["model"]), str(info["skin"]), steel)   # AWP: знімок 3D-моделі; інше — плоский арт
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pv)
	return holder


# ===================================================================== відкриття: запит до сервера
func _on_open() -> void:
	if _busy or _case_id == "":
		return
	if not _online():
		_update_button()
		return
	var info: Dictionary = Economy.CASES[_case_id]
	var price := int(info["price"])
	if Economy.view_coins < price:
		_msg.text = "Not enough coins: %d needed." % price
		return
	_busy = true
	_msg.text = ""
	_update_button()
	_request_token += 1
	var token := _request_token
	Economy.request_open_case.rpc_id(1, _case_id)
	get_tree().create_timer(8.0).timeout.connect(func():
		if _busy and not _cinematic and token == _request_token:
			_busy = false
			_msg.text = "The server didn't respond. Try again."
			_update_button())


func _on_shop_message(text: String) -> void:
	# Сервер відмовив (напр. не вистачило коїнів) — кінематографію не запускаємо.
	if visible and _busy and not _cinematic:
		_busy = false
		_msg.text = text
		_update_button()


func _on_case_opened(case_id: String, item_id: String, refund: int) -> void:
	if not visible or not _busy or _cinematic or case_id != _case_id:
		return
	_start_cinematic(item_id, refund)


# ===================================================================== КІНЕМАТОГРАФІЯ
func _start_cinematic(item_id: String, refund: int) -> void:
	_cinematic = true
	_in_reveal = false
	_rolling = false
	_pending_item = item_id
	_pending_refund = refund
	_shake = 0.0
	_run_id += 1
	_back_btn.disabled = true
	_build_cine()
	_cine.visible = true
	_phase_open(_run_id)


# Чекаємо sec секунд; false — якщо за цей час кінематографію пропустили/скасували.
func _wait(sec: float, id: int) -> bool:
	await get_tree().create_timer(sec).timeout
	return id == _run_id


func _tween() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


func _kill_tweens() -> void:
	for t in _tweens:
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	_tweens.clear()


func _build_cine() -> void:
	for c in _cine.get_children():
		_cine.remove_child(c)
		c.queue_free()
	_cells.clear()
	_kill_tweens()
	var S := _cine.size
	if S.x < 10.0:
		S = get_viewport_rect().size

	_c_bg = ColorRect.new()
	_c_bg.color = Color(0.015, 0.017, 0.024, 0.0)
	_c_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cine.add_child(_c_bg)

	_c_rays = Rays.new()
	_c_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c_rays.modulate.a = 0.0
	_cine.add_child(_c_rays)

	# 3D-кейс
	var packed := _load_case_model(Economy.CASES[_case_id])
	if packed != null:
		_c_stage = CaseStage.new(packed)
		_c_stage.size = S
		_c_stage.position = Vector2.ZERO
		_c_stage.pivot_offset = S / 2.0
		_c_stage.modulate.a = 0.0
		_cine.add_child(_c_stage)
	else:
		_c_stage = null

	# Рулетка: смуга на всю ширину, стрічка всередині
	_c_view = Control.new()
	_c_view.clip_contents = true
	_c_view.size = Vector2(S.x, CELL_H + 80.0)
	_c_view.position = Vector2(0, S.y * 0.5 - _c_view.size.y / 2.0)
	_c_view.modulate.a = 0.0
	_c_view.visible = false
	_cine.add_child(_c_view)

	var band := ColorRect.new()
	band.color = Color(0.0, 0.0, 0.0, 0.55)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c_view.add_child(band)

	_c_strip = HBoxContainer.new()
	_c_strip.add_theme_constant_override("separation", int(CELL_GAP))
	_c_view.add_child(_c_strip)
	_rng.randomize()
	for i in STRIP_COUNT:
		var id := _pending_item if i == WIN_INDEX else Economy.roll_case(_case_id, _rng)
		var cell := _make_cell(id)
		_c_strip.add_child(cell)
		_cells.append(cell)
	_c_strip.position = Vector2(0.0, (_c_view.size.y - CELL_H) / 2.0)

	_c_view.add_child(_fade(true, S))
	_c_view.add_child(_fade(false, S))
	var line := ColorRect.new()
	line.color = Kit.C_GOLD
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.size = Vector2(4, _c_view.size.y)
	line.position = Vector2(S.x / 2.0 - 2.0, 0)
	_c_view.add_child(line)
	for flip in [false, true]:
		var tri := Polygon2D.new()
		tri.color = Kit.C_GOLD
		var y0 := 0.0 if not flip else _c_view.size.y
		var dy := 20.0 if not flip else -20.0
		tri.polygon = PackedVector2Array([Vector2(S.x / 2.0 - 16.0, y0), Vector2(S.x / 2.0 + 16.0, y0), Vector2(S.x / 2.0, y0 + dy)])
		_c_view.add_child(tri)

	_c_title = Kit.label(str(Economy.CASES[_case_id]["name"]).to_upper(), 40, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 6)
	_c_title.size = Vector2(S.x, 60)
	_c_title.position = Vector2(0, S.y * 0.5 - _c_view.size.y / 2.0 - 90.0)
	_c_title.modulate.a = 0.0
	_cine.add_child(_c_title)

	# Шар виграшу (наповнюється пізніше)
	_c_reveal = Control.new()
	_c_reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cine.add_child(_c_reveal)

	_c_flash = ColorRect.new()
	_c_flash.color = Color(1, 1, 1, 0.0)
	_c_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_c_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cine.add_child(_c_flash)

	_c_skip = Button.new()
	_c_skip.text = "SKIP  ›"
	_c_skip.size = Vector2(230, 50)
	_c_skip.position = Vector2(S.x - 230.0 - 36.0, S.y - 50.0 - 30.0)
	Kit.style_button(_c_skip, "ghost", 18)
	_c_skip.modulate.a = 0.0
	_c_skip.pressed.connect(_skip)
	_cine.add_child(_c_skip)


func _fade(left: bool, S: Vector2) -> TextureRect:
	var dark := Color(0.0, 0.0, 0.0, 0.92)
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
	var w := S.x * 0.16
	tr.size = Vector2(w, _c_view.size.y)
	tr.position = Vector2(0, 0) if left else Vector2(S.x - w, 0)
	return tr


func _make_cell(id: String) -> Control:
	var info := Economy.item_info(id)
	var rc := Kit.rarity_color(str(info["rarity"]))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CELL_W, CELL_H)
	card.pivot_offset = Vector2(CELL_W, CELL_H) / 2.0
	card.add_theme_stylebox_override("panel", Kit.box(
		Color(rc.r * 0.16 + 0.04, rc.g * 0.16 + 0.04, rc.b * 0.16 + 0.05, 1.0), rc.darkened(0.1), 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var mm := MarginContainer.new()
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mm.add_theme_constant_override("margin_left", 10)
	mm.add_theme_constant_override("margin_right", 10)
	mm.add_theme_constant_override("margin_top", 14)
	mm.add_child(_preview_holder(info, 110))
	v.add_child(mm)
	var n := Kit.label(_item_short_name(info).to_upper(), 19, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 0)
	n.clip_text = true
	v.add_child(n)
	var bar := ColorRect.new()
	bar.color = rc
	bar.custom_minimum_size = Vector2(0, 7)
	v.add_child(bar)
	return card


# ---------------------------------------------------------------- фаза 1: кейс відкривається
func _phase_open(id: int) -> void:
	var S := _cine.size
	if S.x < 10.0:
		S = get_viewport_rect().size
	_c_skip.modulate.a = 0.0
	var t0 := _tween()
	t0.set_parallel(true)
	t0.tween_property(_c_bg, "color:a", 1.0, 0.45)
	t0.tween_property(_c_rays, "modulate:a", 0.55, 1.0)
	t0.tween_property(_c_skip, "modulate:a", 1.0, 0.6).set_delay(0.8)
	if _c_stage != null:
		_c_stage.scale = Vector2(0.6, 0.6)
		t0.tween_property(_c_stage, "modulate:a", 1.0, 0.7)
		t0.tween_property(_c_stage, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var tc := _tween()
		tc.tween_method(func(z: float): _c_stage.set_dist(z), 2.9, 1.95, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Передчуття: легка тряска
	var ts := _tween()
	ts.tween_property(self, "_shake", 0.45, 0.9).set_delay(0.2)
	if not await _wait(1.15, id):
		return

	# Відкриваємо: замки, кришка, промінь, іскри (анімація з моделі, 3 с)
	if _c_stage != null:
		_c_stage.play_open()
	_play(_snd_boom, -6.0)
	var to := _tween()
	to.set_parallel(true)
	to.tween_property(self, "_shake", 0.0, 0.5)
	to.tween_property(_c_rays, "intensity", 1.9, 2.6)
	to.tween_property(_c_rays, "modulate:a", 1.0, 2.0)
	if not await _wait(1.0, id):
		return
	var tp := _tween()
	tp.tween_property(self, "_shake", 0.7, 0.18)
	tp.tween_property(self, "_shake", 0.0, 0.6)
	if not await _wait(1.25, id):
		return
	# Ривок камери в промінь світла
	if _c_stage != null:
		var td := _tween()
		td.tween_method(func(z: float): _c_stage.set_dist(z), 1.95, 1.0, 0.75).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if not await _wait(0.7, id):
		return
	var tf := _tween()
	tf.tween_property(_c_flash, "color:a", 1.0, 0.12)
	if not await _wait(0.14, id):
		return

	# Спалах -> перемикаємось на рулетку
	if _c_stage != null:
		_c_stage.visible = false
	_c_rays.intensity = 0.8
	_c_rays.modulate.a = 0.28
	_c_view.visible = true
	var tg := _tween()
	tg.set_parallel(true)
	tg.tween_property(_c_flash, "color:a", 0.0, 0.55)
	tg.tween_property(_c_view, "modulate:a", 1.0, 0.5)
	tg.tween_property(_c_title, "modulate:a", 1.0, 0.5)
	if not await _wait(0.8, id):
		return
	_phase_spin(id)


# ---------------------------------------------------------------- фаза 2: рулетка
func _phase_spin(id: int) -> void:
	var S := _cine.size
	if S.x < 10.0:
		S = get_viewport_rect().size
	_rolling = true
	_last_idx = -1
	var view_w := S.x
	var target := WIN_INDEX * (CELL_W + CELL_GAP) + CELL_W / 2.0 + _rng.randf_range(-CELL_W * 0.36, CELL_W * 0.36)
	var end_x := view_w / 2.0 - target
	_c_strip.position.x = 0.0
	var tw := _tween()
	tw.tween_property(_c_strip, "position:x", end_x, SPIN_TIME).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if not await _wait(SPIN_TIME + 0.1, id):
		return
	_rolling = false

	# Зупинилась: підсвічуємо виграшну клітинку, решту притемнюємо
	var info := Economy.item_info(_pending_item)
	var rc := Kit.rarity_color(str(info["rarity"]))
	_play(_snd_land, -4.0)
	var tl := _tween()
	tl.set_parallel(true)
	for i in _cells.size():
		var cell: Control = _cells[i]
		if i == WIN_INDEX:
			cell.modulate = Color.WHITE
			tl.tween_property(cell, "scale", Vector2(1.12, 1.12), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tl.tween_property(cell, "modulate", Color(1, 1, 1, 0.22), 0.45)
	_c_flash.color = Color(rc, 0.0)
	tl.tween_property(_c_flash, "color:a", 0.35, 0.12)
	var tl2 := _tween()
	tl2.tween_interval(0.12)
	tl2.tween_property(_c_flash, "color:a", 0.0, 0.5)
	_burst(Vector2(S.x / 2.0, S.y / 2.0), rc, 70)
	_c_rays.color = rc
	_c_rays.intensity = 1.4
	var tr := _tween()
	tr.tween_property(_c_rays, "modulate:a", 0.6, 0.5)
	if not await _wait(1.5, id):
		return
	_phase_reveal(id)


# ---------------------------------------------------------------- фаза 3: випадіння
func _phase_reveal(id: int) -> void:
	_in_reveal = true
	_rolling = false
	var S := _cine.size
	if S.x < 10.0:
		S = get_viewport_rect().size
	var info := Economy.item_info(_pending_item)
	var rc := Kit.rarity_color(str(info["rarity"]))
	for c in _c_reveal.get_children():
		_c_reveal.remove_child(c)
		c.queue_free()
	if _c_stage != null:
		_c_stage.visible = false
	_c_bg.color.a = 1.0

	var t0 := _tween()
	t0.set_parallel(true)
	t0.tween_property(_c_view, "modulate:a", 0.0, 0.35)
	t0.tween_property(_c_title, "modulate:a", 0.0, 0.35)
	t0.tween_property(_c_skip, "modulate:a", 0.0, 0.2)
	_c_rays.color = rc
	_c_rays.intensity = 2.0
	t0.tween_property(_c_rays, "modulate:a", 1.0, 0.6)

	# Предмет великим планом
	var w := S.x * 0.56
	var h := S.y * 0.40
	var holder := Control.new()
	holder.size = Vector2(w, h)
	holder.position = Vector2((S.x - w) / 2.0, S.y * 0.16)
	holder.pivot_offset = Vector2(w, h) / 2.0
	holder.scale = Vector2(0.25, 0.25)
	holder.modulate.a = 0.0
	holder.clip_contents = false
	_c_reveal.add_child(holder)
	var pv := Kit.make_preview(str(info["model"]), str(info["skin"]), Color("a3acbf"), true, true)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pv)
	t0.tween_property(holder, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t0.tween_property(holder, "modulate:a", 1.0, 0.4)

	var y := S.y * 0.58
	var l1 := Kit.label("YOU GOT", 26, Kit.C_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER, 5)
	l1.size = Vector2(S.x, 36)
	l1.position = Vector2(0, y)
	var l2 := Kit.label(str(Economy.RARITY_NAMES[str(info["rarity"])]), 34, rc, true, HORIZONTAL_ALIGNMENT_CENTER, 6)
	l2.size = Vector2(S.x, 46)
	l2.position = Vector2(0, y + 40)
	var l3 := Kit.label(str(info["name"]).to_upper(), 58, Kit.C_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 3)
	l3.size = Vector2(S.x, 76)
	l3.position = Vector2(0, y + 92)
	var sub_text := "Added to your items"
	var sub_color := Kit.C_GREEN
	if _pending_refund > 0:
		sub_text = "You already own this item — +%d coins refunded" % _pending_refund
		sub_color = Kit.C_GOLD
	var l4 := Kit.label(sub_text, 26, sub_color, false, HORIZONTAL_ALIGNMENT_CENTER, 0)
	l4.size = Vector2(S.x, 36)
	l4.position = Vector2(0, y + 176)
	var k := 0
	for l in [l1, l2, l3, l4]:
		l.modulate.a = 0.0
		_c_reveal.add_child(l)
		t0.tween_property(l, "modulate:a", 1.0, 0.45).set_delay(0.35 + 0.12 * k)
		k += 1

	# Кнопки
	var bw := 300.0
	var gap := 24.0
	var by := S.y - 120.0
	var equip := Button.new()
	equip.text = "EQUIP"
	equip.size = Vector2(bw, 64)
	equip.position = Vector2(S.x / 2.0 - bw - gap / 2.0, by)
	Kit.style_button(equip, "gold", 26)
	equip.disabled = not _online()
	equip.modulate.a = 0.0
	equip.pressed.connect(func(): _finish(true))
	_c_reveal.add_child(equip)
	var take := Button.new()
	take.text = "KEEP"
	take.size = Vector2(bw, 64)
	take.position = Vector2(S.x / 2.0 + gap / 2.0, by)
	Kit.style_button(take, "primary", 26)
	take.modulate.a = 0.0
	take.pressed.connect(func(): _finish(false))
	_c_reveal.add_child(take)
	t0.tween_property(equip, "modulate:a", 1.0, 0.4).set_delay(1.2)
	t0.tween_property(take, "modulate:a", 1.0, 0.4).set_delay(1.2)

	_play(_snd_land, -2.0)
	_burst(Vector2(S.x / 2.0, S.y * 0.36), rc, 90)
	var tf := _tween()
	_c_flash.color = Color(rc, 0.0)
	tf.tween_property(_c_flash, "color:a", 0.5, 0.1)
	tf.tween_property(_c_flash, "color:a", 0.0, 0.6)


# ---------------------------------------------------------------- пропуск і завершення
func _skip() -> void:
	if not _cinematic or _in_reveal:
		return
	_run_id += 1          # усі await-и попередніх фаз гаснуть
	_kill_tweens()
	_rolling = false
	_shake = 0.0
	if _c_stage != null:
		_c_stage.visible = false
	_c_flash.color.a = 0.0
	_phase_reveal(_run_id)


func _finish(equip: bool) -> void:
	if not _cinematic:
		return
	var item := _pending_item
	if equip and _online():
		var info := Economy.item_info(item)
		if not info.is_empty():
			if str(info["kind"]) == "knife":
				Economy.request_equip_knife.rpc_id(1, item)
			else:
				Economy.request_equip_skin.rpc_id(1, str(info["weapon"]), item)
	_run_id += 1
	_kill_tweens()
	var t := _tween()
	t.tween_property(_c_bg, "color:a", 1.0, 0.01)
	t.parallel().tween_property(_c_reveal, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(_c_rays, "modulate:a", 0.0, 0.3)
	t.tween_interval(0.05)
	t.tween_callback(func():
		_cinematic = false
		_in_reveal = false
		_busy = false
		_cine.visible = false
		_update_coins()
		visible = false
		finished.emit(item)
		closed.emit())


# ---------------------------------------------------------------- ефекти
func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.4
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 820.0
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 10.0
	p.color = color.lightened(0.25)
	_cine.add_child(p)
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


func _process(_delta: float) -> void:
	if not _cinematic:
		return
	if _c_stage != null and _c_stage.visible:
		if _shake > 0.001:
			_c_stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 16.0
			_c_stage.rotation = randf_range(-1.0, 1.0) * _shake * 0.012
		else:
			_c_stage.position = Vector2.ZERO
			_c_stage.rotation = 0.0
	if _rolling and _c_view != null:
		var idx := int(floor((_c_view.size.x * 0.5 - _c_strip.position.x) / (CELL_W + CELL_GAP)))
		if idx != _last_idx:
			if _last_idx >= 0 and _last_idx < _cells.size():
				(_cells[_last_idx] as Control).modulate = Color.WHITE
			_last_idx = idx
			if idx >= 0 and idx < _cells.size():
				(_cells[idx] as Control).modulate = Color(1.35, 1.35, 1.35)
			_play(_snd_tick, -14.0)


# ---------------------------------------------------------------- звуки (генеруємо самі, без файлів)
func _play(stream: AudioStream, vol_db: float) -> void:
	for p in _sfx:
		var pl := p as AudioStreamPlayer
		if not pl.playing:
			pl.stream = stream
			pl.volume_db = vol_db
			pl.play()
			return
	var first := _sfx[0] as AudioStreamPlayer
	first.stream = stream
	first.volume_db = vol_db
	first.play()


func _make_wav(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	w.data = bytes
	return w


func _make_sounds() -> void:
	var rate := 22050
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# тік рулетки
	var n := int(rate * 0.05)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 95.0)
		s[i] = (sin(TAU * 1500.0 * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.25) * env
	_snd_tick = _make_wav(s, rate)
	# глухий удар при відкритті
	n = int(rate * 0.7)
	s = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var f := 60.0 + 90.0 * exp(-t * 8.0)
		s[i] = (sin(TAU * f * t) * 0.9 + rng.randf_range(-1.0, 1.0) * 0.15 * exp(-t * 12.0)) * exp(-t * 5.0)
	_snd_boom = _make_wav(s, rate)
	# дзвінкий акорд при зупинці/випадінні
	n = int(rate * 1.1)
	s = PackedFloat32Array()
	s.resize(n)
	var notes := [660.0, 880.0, 1100.0, 1320.0]
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for k in notes.size():
			var tk := t - 0.07 * k
			if tk > 0.0:
				v += sin(TAU * float(notes[k]) * tk) * exp(-tk * 4.5) * 0.25
		s[i] = v
	_snd_land = _make_wav(s, rate)
