extends Node
# Вибраний ніж. Що вибрано і що куплено — вирішує сервер (Economy); тут лише локальна копія,
# щоб гра знала, який ніж показувати (в т.ч. у матчі проти бота без сервера).

const SAVE_PATH := "user://loadout.cfg"
const KNIVES: Array = ["karambit", "bolisong", "butterfly"]

var knife: String = "bolisong"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved: String = cfg.get_value("loadout", "knife", "bolisong")
		if KNIVES.has(saved):
			knife = saved


func set_knife(skin: String) -> void:
	if not KNIVES.has(skin):
		return
	knife = skin
	var cfg := ConfigFile.new()
	cfg.set_value("loadout", "knife", knife)
	cfg.save(SAVE_PATH)
