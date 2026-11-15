extends RefCounted
class_name GameSettings

const PATH := "user://game_settings.cfg"
const DEFAULT_SENSITIVITY := 1.0
const DEFAULT_SCOPE_MULTIPLIER := 1.0

static var sensitivity: float = DEFAULT_SENSITIVITY
static var scope_sensitivity_multiplier: float = DEFAULT_SCOPE_MULTIPLIER
static var _loaded := false

static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	sensitivity = clampf(float(config.get_value("mouse", "sensitivity", DEFAULT_SENSITIVITY)), 0.1, 5.0)
	scope_sensitivity_multiplier = clampf(float(config.get_value("mouse", "scope_multiplier", DEFAULT_SCOPE_MULTIPLIER)), 0.1, 3.0)

static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("mouse", "sensitivity", sensitivity)
	config.set_value("mouse", "scope_multiplier", scope_sensitivity_multiplier)
	config.save(PATH)
