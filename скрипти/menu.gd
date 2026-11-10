extends Node

@onready var network_panel: Control = $Networkpanel
@onready var host_button: Button = $Networkpanel/HostButton
@onready var ip_input: LineEdit = $Networkpanel/IPInput
@onready var join_button: Button = $Networkpanel/JoinButton   # тепер працює як "Скасувати"
@onready var status_label: Label = $Networkpanel/StatusLabel

const MAX_CONNECT_ATTEMPTS := 20

var _searching: bool = false
var _attempts: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Network.is_dedicated_server():
		return

	host_button.hide()
	ip_input.visible = OS.is_debug_build()  # поле адреси лише для локальних тестів
	ip_input.placeholder_text = "Адреса сервера (порожньо = онлайн-сервер)"
	join_button.text = "Скасувати"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	join_button.pressed.connect(_on_cancel_pressed)
	Network.connection_succeeded.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)


# Кнопка "play": підключаємось до сервера і стаємо в чергу на матч 1х1.
func _on_button_pressed() -> void:
	if _searching:
		return
	_searching = true
	_attempts = 0
	network_panel.visible = true
	_connect()


func _connect() -> void:
	_attempts += 1
	status_label.text = "Підключення до сервера... (безкоштовний сервер може прокидатись до хвилини)"
	Network.join_game(ip_input.text.strip_edges())


func _on_connected() -> void:
	if not _searching:
		return
	status_label.text = "Пошук суперника..."
	Matchmaker.find_match()


func _on_connection_failed() -> void:
	if not _searching:
		return
	if _attempts >= MAX_CONNECT_ATTEMPTS:
		_searching = false
		status_label.text = "Не вдалося підключитись до сервера. Спробуй ще раз."
		return
	status_label.text = "Сервер прокидається... спроба %d/%d" % [_attempts + 1, MAX_CONNECT_ATTEMPTS]
	await get_tree().create_timer(2.0).timeout
	if _searching:
		_connect()


func _on_cancel_pressed() -> void:
	_searching = false
	Matchmaker.cancel_search()
	network_panel.visible = false


func _on_button_3_pressed() -> void:
	get_tree().quit()
