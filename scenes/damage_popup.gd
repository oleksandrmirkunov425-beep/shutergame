extends Node3D

@onready var label: Label3D = $Label3D


func set_text(value: String) -> void:
	if label:
		label.text = value


func _ready() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + 1.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(queue_free)
