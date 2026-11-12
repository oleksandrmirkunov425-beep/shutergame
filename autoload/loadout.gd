extends Node
# Вибір ножа (зберігається між запусками гри).

const SAVE_PATH := "user://loadout.cfg"
const KNIVES: Array = ["karambit", "butterfly"]

var knife: String = "karambit"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved: String = cfg.get_value("loadout", "knife", "karambit")
		if KNIVES.has(saved):
			knife = saved


func set_knife(skin: String) -> void:
	if not KNIVES.has(skin):
		return
	knife = skin
	var cfg := ConfigFile.new()
	cfg.set_value("loadout", "knife", knife)
	cfg.save(SAVE_PATH)
