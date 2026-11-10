extends Control

@export var line_length: float = 8.0
@export var thickness: float = 2.0
@export var gap: float = 4.0
@export var color: Color = Color(0, 1, 0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center = get_viewport_rect().size / 2

	# Верхня лінія
	draw_line(center + Vector2(0, -gap - line_length), center + Vector2(0, -gap), color, thickness)
	# Нижня лінія
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), color, thickness)
	# Ліва лінія
	draw_line(center + Vector2(-gap - line_length, 0), center + Vector2(-gap, 0), color, thickness)
	# Права лінія
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), color, thickness)
