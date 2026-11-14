extends RefCounted
class_name CrosshairConfig

# Налаштування прицілу. Зберігаються у файл user://crosshair.cfg і діють і в меню, і в грі.
# `version` збільшується при кожній зміні — приціл за ним розуміє, що треба перемалюватись.

const PATH := "user://crosshair.cfg"

static var length: float = 8.0       # довжина кожної риски
static var thickness: float = 2.0    # товщина
static var gap: float = 4.0          # проміжок від центру
static var dot: bool = false         # крапка в центрі
static var dot_size: float = 3.0
static var outline: bool = true      # чорний контур
static var opacity: float = 1.0
static var color: Color = Color(0.1, 1.0, 0.1)
static var version: int = 0

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_config()


static func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	length = float(cf.get_value("crosshair", "length", length))
	thickness = float(cf.get_value("crosshair", "thickness", thickness))
	gap = float(cf.get_value("crosshair", "gap", gap))
	dot = bool(cf.get_value("crosshair", "dot", dot))
	dot_size = float(cf.get_value("crosshair", "dot_size", dot_size))
	outline = bool(cf.get_value("crosshair", "outline", outline))
	opacity = float(cf.get_value("crosshair", "opacity", opacity))
	color = cf.get_value("crosshair", "color", color)
	version += 1


static func save_config() -> void:
	var cf := ConfigFile.new()
	cf.set_value("crosshair", "length", length)
	cf.set_value("crosshair", "thickness", thickness)
	cf.set_value("crosshair", "gap", gap)
	cf.set_value("crosshair", "dot", dot)
	cf.set_value("crosshair", "dot_size", dot_size)
	cf.set_value("crosshair", "outline", outline)
	cf.set_value("crosshair", "opacity", opacity)
	cf.set_value("crosshair", "color", color)
	cf.save(PATH)


static func reset_defaults() -> void:
	length = 8.0
	thickness = 2.0
	gap = 4.0
	dot = false
	dot_size = 3.0
	outline = true
	opacity = 1.0
	color = Color(0.1, 1.0, 0.1)
	version += 1
