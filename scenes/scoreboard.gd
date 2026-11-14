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

	var enemy_box := _make_box(COLOR_ENEMY)
	_enemy_score = enemy_box.get_child(0)
	row.add_child(enemy_box)

	_enemy_nick = _make_nick(HORIZONTAL_ALIGNMENT_LEFT, COLOR_ENEMY)
	row.add_child(_enemy_nick)


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
