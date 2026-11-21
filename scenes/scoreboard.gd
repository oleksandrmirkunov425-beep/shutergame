class_name Scoreboard
extends Control
# Табло зверху по центру:  [мій нік] [рахунок] [рахунок] [нік суперника]
# Квадратики з рахунком завжди рівно по центру між двома нікам.

const NICK_WIDTH := 320.0
const BOX_SIZE := 64.0

const COLOR_ME := Color(0.45, 0.85, 1.0)
const COLOR_ENEMY := Color(1.0, 0.45, 0.3)

var _font: SystemFont
var _my_nick: Label
var _enemy_nick: Label
var _my_score: Label
var _enemy_score: Label
var _timer_label: Label
var _big_label: Label      # великі цифри 3-2-1 по центру екрана
var _big_tween: Tween

const COLOR_TIMER := Color(1.0, 0.85, 0.3)
const COLOR_LOW := Color(1.0, 0.3, 0.25)   # останні 10 секунд раунду


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "Segoe UI", "DejaVu Sans"])
	_font.font_weight = 700

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.offset_top = 14.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	_my_nick = _make_nick(HORIZONTAL_ALIGNMENT_RIGHT, COLOR_ME)
	row.add_child(_my_nick)

	var my_box := _make_box(COLOR_ME)
	_my_score = my_box.get_child(0)
	row.add_child(my_box)

	# Таймер по центру між двома рахунками (розминка / відлік перед раундом).
	var timer_box := _make_box(Color(0.75, 0.75, 0.8))
	_timer_label = timer_box.get_child(0)
	_timer_label.text = "..."
	row.add_child(timer_box)

	var enemy_box := _make_box(COLOR_ENEMY)
	_enemy_score = enemy_box.get_child(0)
	row.add_child(enemy_box)

	_enemy_nick = _make_nick(HORIZONTAL_ALIGNMENT_LEFT, COLOR_ENEMY)
	row.add_child(_enemy_nick)

	_make_big_countdown()


func _make_nick(align: int, color: Color) -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(NICK_WIDTH, BOX_SIZE)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text = "..."
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _make_box(border: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.85)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)

	var l := Label.new()
	l.text = "0"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", border.darkened(0.6))
	l.add_theme_constant_override("outline_size", 8)
	box.add_child(l)
	return box


func update_board(my_nick: String, my_score: int, enemy_nick: String, enemy_score: int) -> void:
	_my_nick.text = my_nick
	_enemy_nick.text = enemy_nick
	_my_score.text = str(my_score)
	_enemy_score.text = str(enemy_score)


# Великі цифри відліку по центру екрана (3 - 2 - 1 перед стартом раунду).
func _make_big_countdown() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_big_label = Label.new()
	_big_label.custom_minimum_size = Vector2(300, 240)
	_big_label.pivot_offset = Vector2(150, 120)
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_label.add_theme_font_override("font", _font)
	_big_label.add_theme_font_size_override("font_size", 190)
	_big_label.add_theme_color_override("font_color", COLOR_TIMER)
	_big_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_big_label.add_theme_constant_override("outline_size", 24)
	_big_label.modulate.a = 0.0
	center.add_child(_big_label)


func _show_big(n: int) -> void:
	_big_label.text = str(n)
	_big_label.scale = Vector2(1.7, 1.7)
	_big_label.modulate.a = 1.0
	if _big_tween:
		_big_tween.kill()
	_big_tween = create_tween()
	_big_tween.tween_property(_big_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_big_tween.tween_interval(0.5)
	_big_tween.tween_property(_big_label, "modulate:a", 0.0, 0.2)


func _hide_big() -> void:
	if _big_tween:
		_big_tween.kill()
	_big_label.modulate.a = 0.0


# Стан гри з сервера: 0 очікування, 1 відлік розминки, 2 раунд іде,
# 3 пауза після смерті (value = секунди до нового раунду),
# 4 кінець гри, 5 "заморозка" на старті раунду (3-2-1 великими цифрами).
func set_state(state: int, value: int) -> void:
	match state:
		0:
			_set_timer("...", Color.WHITE)
			_hide_big()
		1, 3:
			_set_timer(str(value), COLOR_TIMER)
			_hide_big()
		5:
			_set_timer(str(value), COLOR_TIMER)
			if value >= 1:
				_show_big(value)
		2:
			# Раунд іде: value = секунди, що лишились (0 = без ліміту).
			if value > 0:
				_set_timer(str(value), COLOR_LOW if value <= 10 else Color.WHITE)
			else:
				_set_timer("VS", Color.WHITE)
			_hide_big()
		6:
			# Бомба тікає: value = секунди до вибуху.
			_set_timer(str(value), COLOR_LOW)
			_hide_big()
		_:
			_set_timer("VS", Color.WHITE)
			_hide_big()


func _set_timer(text: String, color: Color) -> void:
	_timer_label.text = text
	_timer_label.add_theme_color_override("font_color", color)
