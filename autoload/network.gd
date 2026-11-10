extends Node

const DEFAULT_PORT: int = 7777   # для локальних тестів; на Render порт приходить зі змінної PORT
const MAX_CONNECTIONS: int = 64

# Адреса твого сервісу на Render. Перевір точну адресу на сторінці сервісу в Render
# (зверху, біля назви) і встав її сюди. Порожнє поле адреси в меню = ця адреса.
const PUBLIC_SERVER_URL: String = "wss://shutergame.onrender.com"

var connected_peers: Dictionary = {}  # peer_id -> true (тільки на сервері)

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


# Режим сервера на Render: без вікна, одразу слухаємо порт. Кімнати створює Matchmaker.
func _start_dedicated() -> void:
	await get_tree().process_frame
	if host_game() == "":
		push_error("Dedicated server не запустився")
		get_tree().quit(1)
		return
	# Меню на сервері не потрібне.
	var cs := get_tree().current_scene
	if cs:
		cs.queue_free()


func host_game() -> String:
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

	var ip := _get_local_ip_fallback()
	server_started.emit(ip)
	return ip


func join_game(address: String) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	# Безкоштовний Render "прокидається" до ~50 с — даємо рукостисканню більше часу.
	peer.handshake_timeout = 10.0
	var url := _make_url(address)
	var error := peer.create_client(url)
	if error != OK:
		push_error("Не вдалося підключитись до %s: %s" % [url, error])
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	print("[network] join_game: connecting to ", url)


# "" -> PUBLIC_SERVER_URL; "ws://..." / "wss://..." -> як є;
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
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Повністю скидаємо стан мультиплеєра рушія, щоб при повторному вході
	# не лишалися старі ID і синхронізатори.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = null
	connected_peers.clear()


func _get_local_ip_fallback() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("26."):
			return ip
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		if connected_peers.size() >= MAX_CONNECTIONS:
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
		connected_peers[id] = true
	print("[network] peer connected: ", id)


func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	print("[network] peer disconnected: ", id)


func _on_connected_ok() -> void:
	print("[network] connected, my_id=", multiplayer.get_unique_id())
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	print("[network] connection failed")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[network] server disconnected")
	multiplayer.multiplayer_peer = null
	connected_peers.clear()
	Matchmaker.leave_to_menu()
