extends Control

# Малює приціл за налаштуваннями з CrosshairConfig (меню → «Приціл»).
# weapon_switch.gd лише масштабує цей вузол (розкид) і ховає його в оптичному прицілі.

var _seen_version: int = -1


func _ready() -> void:
	CrosshairConfig.ensure_loaded()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_pivot()
	resized.connect(_update_pivot)


# Масштабування від розкиду має йти від центру екрана, а не від кута.
func _update_pivot() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _process(_delta: float) -> void:
	if _seen_version != CrosshairConfig.version:
		_seen_version = CrosshairConfig.version
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = (size * 0.5).round()
	var t: float = CrosshairConfig.thickness
	var g: float = CrosshairConfig.gap
	var l: float = CrosshairConfig.length
	var col: Color = CrosshairConfig.color
	col.a = CrosshairConfig.opacity
	var out_col := Color(0, 0, 0, CrosshairConfig.opacity)

	var rects: Array[Rect2] = [
		Rect2(c.x + g, c.y - t * 0.5, l, t),        # права
		Rect2(c.x - g - l, c.y - t * 0.5, l, t),    # ліва
		Rect2(c.x - t * 0.5, c.y - g - l, t, l),    # верхня
		Rect2(c.x - t * 0.5, c.y + g, t, l),        # нижня
	]
	if CrosshairConfig.dot:
		var d: float = CrosshairConfig.dot_size
		rects.append(Rect2(c.x - d * 0.5, c.y - d * 0.5, d, d))

	if CrosshairConfig.outline:
		for r in rects:
			draw_rect(r.grow(1.0), out_col)
	for r in rects:
		draw_rect(r, col)
