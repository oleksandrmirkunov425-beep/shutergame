extends CanvasLayer
# Pause menu (ESC). Створюється в player.gd лише для власника ноди.
# Гра НЕ зупиняється (мультиплеєр) — блокується тільки керування гравця.
#
#   open() / close() / toggle()
#   is_open — true, поки меню на екрані

var is_open: bool = false

var _root: Control = null
var _resume_button: Button = null


func _ready() -> void:
	layer = 100
	_build()
	_root.visible = false


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func _on_exit_pressed() -> void:
	is_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Matchmaker.leave_to_menu()


# ---- UI ----------------------------------------------------------------
func _build() -> void:
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.10, 0.12, 0.97)
	panel_style.border_color = Color(0.25, 0.27, 0.32)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 48
	panel_style.content_margin_right = 48
	panel_style.content_margin_top = 36
	panel_style.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	box.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)

	_resume_button = _make_button("Resume", Color(0.20, 0.55, 0.30))
	_resume_button.pressed.connect(close)
	box.add_child(_resume_button)

	var exit_button := _make_button("Exit to Main Menu", Color(0.65, 0.22, 0.22))
	exit_button.pressed.connect(_on_exit_pressed)
	box.add_child(exit_button)


func _make_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.17, 0.20), accent))
	b.add_theme_stylebox_override("hover", _button_style(accent.darkened(0.35), accent))
	b.add_theme_stylebox_override("pressed", _button_style(accent.darkened(0.15), accent))
	b.add_theme_stylebox_override("focus", _button_style(Color(0.16, 0.17, 0.20), accent.lightened(0.3)))
	return b


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb
