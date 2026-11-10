extends Node

const DEFAULT_PORT: int = 7777   # для локальних тестів; на Render порт приходить зі змінної PORT
const MAX_PLAYERS: int = 8

# Адреса твого сервісу на Render (після деплою встав свою). Якщо гравець
# залишає поле адреси порожнім — підключаємось саме сюди.
const PUBLIC_SERVER_URL: String = "wss://YOUR-APP.onrender.com"

var players: Dictionary = {}  # peer_id -> {"name": String}

# IP, на яку клієнт хоче підключитись, але ще НЕ підключений мережею —
# зберігається тут, поки клієнт довантажує ігрову сцену.
var _pending_ip: String = ""

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal server_started(external_ip: String)


func is_dedicated_server() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if is_dedicated_server():
		_start_dedicated.call_deferred()


# Режим сервера на Render: без вікна, без гравця-хоста — одразу слухаємо
# порт і вантажимо ігрову сцену (world.gd сам підніме серверну логіку).
func _start_dedicated() -> void:
	await get_tree().process_frame
	if host_game() == "":
		push_error("Dedicated server не запустився")
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func host_game() -> String:
	print("[network] host_game() called")
	var port := DEFAULT_PORT
	if OS.has_environment("PORT"):
		port = OS.get_environment("PORT").to_int()

	# WebSocket замість ENet: Render (як і браузер) не пропускає UDP.
	# TLS на Render термінується самим Render, тому тут звичайний ws://.
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		push_error("Не вдалося створити сервер: %s" % error)
		return ""

	multiplayer.multiplayer_peer = peer
	print("[network] listening on port ", port)

	# На dedicated-сервері гравця-хоста немає — в players лише клієнти.
	if not is_dedicated_server():
		players[1] = {"name": "Host"}

	var ip := _get_local_ip_fallback()
	server_started.emit(ip)
	return ip


func request_join(ip: String) -> void:
	print("[network] request_join(", ip, ") — saved as pending")
	_pending_ip = ip


func has_pending_join() -> bool:
	return _pending_ip != ""


func finalize_pending_join() -> void:
	if _pending_ip == "":
		return
	var ip := _pending_ip
	_pending_ip = ""
	print("[network] finalize_pending_join -> join_game(", ip, ")")
	join_game(ip)


func join_game(address: String) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := _make_url(address)
	var error := peer.create_client(url)
	if error != OK:
		push_error("Не вдалося підключитись до %s: %s" % [url, error])
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	print("[network] join_game: connecting to ", url)


# "" -> PUBLIC_SERVER_URL; "ws://..."/"wss://..." -> як є;
# локальна адреса -> ws://адреса:7777; інакше -> wss://адреса
func _make_url(address: String) -> String:
	address = address.strip_edges()
	if address == "":
		return PUBLIC_SERVER_URL
	if address.contains("://"):
		return address
	if address.begins_with("localhost") or address.begins_with("127.") \
			or address.begins_with("192.168.") or address.begins_with("10.") \
			or address.begins_with("26."):
		return "ws://%s%s" % [address, "" if address.contains(":") else ":%d" % DEFAULT_PORT]
	return "wss://" + address


func leave_game() -> void:
	print("[network] leave_game() called. players before clear=", players)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# ВИПРАВЛЕННЯ: Повністю скидаємо стан мультиплеєра рушія,
	# щоб при повторному вході не залишалися старі ID і синхронізатори.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = null

	players.clear()
	_pending_ip = ""
	print("[network] leave_game() done. peer=", multiplayer.multiplayer_peer)


func disconnect_after_delay(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	leave_game()


func _get_local_ip_fallback() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("26."):
			return ip
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	print("[network] _on_peer_connected id=", id, " my_unique_id=", multiplayer.get_unique_id(), " is_server=", multiplayer.is_server())
	players[id] = {"name": "Player%d" % id}
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[network] _on_peer_disconnected id=", id)
	players.erase(id)
	player_disconnected.emit(id)


func _on_connected_ok() -> void:
	print("[network] _on_connected_ok (connected_to_server signal) my_id=", multiplayer.get_unique_id())
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	print("[network] _on_connected_fail")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/menu.tscn":
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_server_disconnected() -> void:
	print("[network] _on_server_disconnected")
	multiplayer.multiplayer_peer = null
	players.clear()
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/menu.tscn":
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
