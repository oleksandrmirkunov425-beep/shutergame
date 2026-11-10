extends Node  # або що там у тебе зверху, не міняй цей рядок

@onready var network_panel: Control = $Networkpanel
@onready var host_button: Button = $Networkpanel/HostButton
@onready var ip_input: LineEdit = $Networkpanel/IPInput
@onready var join_button: Button = $Networkpanel/JoinButton
@onready var status_label: Label = $Networkpanel/StatusLabel

# ВАЖЛИВО: переконайся, що це дійсно твоя головна ігрова сцена (та, де
# лежать world/players/MultiplayerSpawner) — судячи з логів помилок типу
# "main/players/1/...", коренева нода називається "main", тобто це,
# найімовірніше, main.tscn, а не player.tscn.
const GAME_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	# Гравець міг зайти сюди прямо з гри, де курсор захоплений
	# (Input.mouse_mode — глобальна настройка рушія, вона НЕ скидається
	# сама при зміні сцени). Без цього рядка курсор лишається
	# невидимим/захопленим і в меню.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Браузер не може слухати порт — "створити гру" тільки в desktop-версії.
	if OS.has_feature("web"):
		host_button.hide()
	ip_input.placeholder_text = "Адреса сервера (порожньо = онлайн-сервер)"

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	Network.server_started.connect(_on_server_started)
	Network.connection_failed.connect(_on_connection_failed)
	# connection_succeeded більше НЕ використовується для зміни сцени —
	# сцена клієнта тепер вантажиться ДО підключення (див. _on_join_pressed).


func _on_button_pressed() -> void:
	# Кнопка "play" тепер відкриває панель хост/приєднатись замість одразу гри
	network_panel.visible = true
	status_label.text = ""


func _on_host_pressed() -> void:
	status_label.text = "Створення гри..."
	var ip := Network.host_game()
	if ip == "":
		status_label.text = "Помилка створення сервера!"


func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	# Порожнє поле = публічний сервер на Render (див. Network.PUBLIC_SERVER_URL)
	status_label.text = "Підключення..."

	# ВАЖЛИВО: тут ми НЕ підключаємось мережею одразу. Спочатку запам'ятовуємо
	# IP і переходимо на ігрову сцену — щоб вузол "players" (ціль для
	# MultiplayerSpawner) вже реально існував у дереві клієнта. Тільки
	# ПІСЛЯ того, як ігрова сцена завантажиться і скаже "я готова"
	# (world.gd сам викличе Network.finalize_pending_join()), почнеться
	# справжнє ENet-підключення. Без цього порядку сервер міг "дослати"
	# клієнту вже існуючого хоста ДО того, як цільовий вузол з'явився —
	# і такий пакет губився назавжди (Node not found), тому клієнт ніколи
	# не бачив хоста.
	Network.request_join(ip)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_server_started(external_ip: String) -> void:
	status_label.text = "Сервер запущено! Твоя IP: %s" % external_ip
	DisplayServer.clipboard_set(external_ip)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_connection_failed() -> void:
	status_label.text = "Не вдалося підключитись. Перевір IP."


func _on_button_3_pressed() -> void:
	get_tree().quit()
