extends Node
# Вибраний ніж і скін зброї. Що вибрано і що куплено — вирішує сервер (Economy); тут лише локальна копія,
# щоб гра знала, що показувати (в т.ч. у матчі проти бота без сервера).

const SAVE_PATH := "user://loadout.cfg"
const KNIVES: Array = ["karambit", "bolisong", "butterfly", "m9"]
const AK_SKINS: Array = ["ak47_samurai"]   # "" = стандартний АК
const AWP_SKINS: Array = ["awp_samurai"]   # "" = стандартна AWP

var knife: String = "bolisong"
var ak_skin: String = ""
var awp_skin: String = ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved: String = cfg.get_value("loadout", "knife", "bolisong")
		if KNIVES.has(saved):
			knife = saved
		var saved_skin: String = cfg.get_value("loadout", "ak_skin", "")
		if AK_SKINS.has(saved_skin):
			ak_skin = saved_skin
		var saved_awp: String = cfg.get_value("loadout", "awp_skin", "")
		if AWP_SKINS.has(saved_awp):
			awp_skin = saved_awp


func set_knife(skin: String) -> void:
	if not KNIVES.has(skin):
		return
	knife = skin
	_save()


func set_ak_skin(skin: String) -> void:
	if skin != "" and not AK_SKINS.has(skin):
		return
	ak_skin = skin
	_save()


func set_awp_skin(skin: String) -> void:
	if skin != "" and not AWP_SKINS.has(skin):
		return
	awp_skin = skin
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("loadout", "knife", knife)
	cfg.set_value("loadout", "ak_skin", ak_skin)
	cfg.set_value("loadout", "awp_skin", awp_skin)
	cfg.save(SAVE_PATH)
