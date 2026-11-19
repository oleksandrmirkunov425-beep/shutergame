extends Node
# Підбір матчів 1×1 та 2×2 + ізольовані кімнати.
#
# Один сервер (Render) тримає багато кімнат одночасно. Кожна кімната — це окремий
# екземпляр main.tscn за шляхом /root/Matchmaker/Rooms/<room_id>. Той самий шлях
# створюється і на клієнті, тому RPC та MultiplayerSynchronizer знаходять свої ноди.
# Усі "розсилки" тепер йдуть тільки гравцям своєї кімнати (див. rpc_room / targets).

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

signal search_progress(found: int, total: int, mode: String)

var rooms_root: Node

# --- тільки сервер ---
var _queues: Dictionary = {"1v1": [], "2v2": []}  # окремі черги режимів
var _rooms: Dictionary = {}   # room_id -> {"peers": Array, "loaded": Dictionary, "node": Node, "started": bool}
var _peer_room: Dictionary = {}  # peer_id -> room_id
var _next_room_id: int = 1


func _ready() -> void:
	rooms_root = Node.new()
	rooms_root.name = "Rooms"
	add_child(rooms_root)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# ------------------------------------------------------------------
# Допоміжні функції (працюють і на клієнті, і на сервері)
# ------------------------------------------------------------------

# Корінь кімнати (main), у якій лежить нода.
func room_of(node: Node) -> Node:
	var n := node
	while n:
		if n.has_meta("peer_ids"):
			return n
		n = n.get_parent()
	return get_tree().current_scene


func room_peers(node: Node) -> Array:
	var room := room_of(node)
	if room and room.has_meta("peer_ids"):
		return room.get_meta("peer_ids")
	return []


# Кому слати розсилку: тільки гравцям цієї кімнати (крім мене) + опційно сервер.
func targets(node: Node, include_server: bool = true) -> Array:
	var me := multiplayer.get_unique_id()
	var out: Array = []
	for id in room_peers(node):
		if id != me:
			out.append(id)
	if include_server and me != 1 and not out.has(1):
		out.append(1)
	return out


# Заміна для method.rpc(...): виконує локально (як call_local) і шле тільки в кімнату.
func rpc_room(node: Node, method: StringName, args: Array = [],
		include_server: bool = true, local: bool = true) -> void:
	if local:
		node.callv(method, args)
	for id in targets(node, include_server):
		node.callv("rpc_id", [id, method] + args)



# Запуск локального матчу проти AI без підключення до онлайн-сервера.
func start_bot_match() -> void:
	Network.leave_game()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for child in rooms_root.get_children():
		child.queue_free()
	var old_scene := get_tree().current_scene
	var room: Node = load(GAME_SCENE).instantiate()
	room.name = "bot_room"
	room.set_meta("peer_ids", [1])
	room.set_meta("bot_match", true)
	get_tree().root.add_child(room)
	if old_scene and old_scene != room:
		old_scene.queue_free()
	get_tree().current_scene = room
	room.get_node("MAP/world").call_deferred("begin_match")

# ------------------------------------------------------------------
# КЛІЄНТ: пошук гри
# ------------------------------------------------------------------

func find_match(mode: String = "1v1") -> void:
	request_match.rpc_id(1, mode)


func cancel_search() -> void:
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		cancel_match.rpc_id(1)
	Network.leave_game.call_deferred()


@rpc("authority", "reliable")
func enter_room(room_id: int, peers: Array, mode: String = "1v1") -> void:
	if multiplayer.is_server():
		return
	for c in rooms_root.get_children():
		c.queue_free()

	var room: Node = load(GAME_SCENE).instantiate()
	room.name = str(room_id)
	room.set_meta("peer_ids", peers)
	room.set_meta("game_mode", mode)

	# Меню більше не потрібне (Node2D малювався б поверх 3D).
	var cs := get_tree().current_scene
	if cs:
		cs.queue_free()
	rooms_root.add_child(room)


@rpc("authority", "reliable")
func leave_room() -> void:
	if multiplayer.is_server():
		return
	leave_to_menu()


# Клієнт повертається в меню (кінець гри / втрата зв'язку).
func leave_to_menu() -> void:
	for c in rooms_root.get_children():
		c.queue_free()
	var current := get_tree().current_scene
	if current and bool(current.get_meta("bot_match", false)):
		current.queue_free()
	Network.leave_game.call_deferred()
	get_tree().change_scene_to_file(MENU_SCENE)


# ------------------------------------------------------------------
# СЕРВЕР: черга і кімнати
# ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_match(mode: String = "1v1") -> void:
	if not multiplayer.is_server():
		return
	if mode != "2v2":
		mode = "1v1"
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		return
	for queue_mode in _queues.keys():
		_queues[queue_mode].erase(id)
	var queue: Array = _queues[mode]
	if queue.has(id):
		return
	queue.append(id)
	_queues[mode] = queue
	print("[matchmaker] ", id, " у черзі ", mode, ". Черга: ", queue.size())
	_try_pair(mode)
	_notify_queue(mode)


@rpc("any_peer", "reliable")
func cancel_match() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for mode in _queues.keys():
		if _queues[mode].has(id):
			_queues[mode].erase(id)
			_notify_queue(str(mode))


# Сервер повідомляє кожному гравцю в черзі поточний прогрес пошуку.
func _notify_queue(mode: String) -> void:
	if not multiplayer.is_server() or not _queues.has(mode):
		return
	var needed := 4 if mode == "2v2" else 2
	var found: int = _queues[mode].size()
	for peer_id in _queues[mode]:
		update_search_progress.rpc_id(int(peer_id), found, needed, mode)


@rpc("authority", "reliable")
func update_search_progress(found: int, total: int, mode: String) -> void:
	if multiplayer.is_server():
		return
	search_progress.emit(found, total, mode)


func _try_pair(mode: String) -> void:
	var needed := 4 if mode == "2v2" else 2
	var queue: Array = _queues[mode]
	while queue.size() >= needed:
		var peers: Array = []
		for i in needed:
			peers.append(queue.pop_front())
		_create_room(peers, mode)
	_queues[mode] = queue


func _create_room(peers: Array, mode: String = "1v1") -> void:
	var room_id := _next_room_id
	_next_room_id += 1
	print("[matchmaker] кімната ", room_id, ": ", peers)

	var room: Node = load(GAME_SCENE).instantiate()
	room.name = str(room_id)
	room.set_meta("peer_ids", peers)  # той самий масив, що й у _rooms — оновлюється при виході гравця
	room.set_meta("game_mode", mode)

	_rooms[room_id] = {"peers": peers, "loaded": {}, "node": room, "started": false}
	for p in peers:
		_peer_room[p] = room_id
	rooms_root.add_child(room)

	for p in peers:
		enter_room.rpc_id(p, room_id, peers, mode)


# Клієнти повідомляють про завантаження; матч стартує, коли готові всі учасники кімнати.
@rpc("any_peer", "reliable")
func room_loaded(room_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _rooms.get(room_id, {})
	if r.is_empty() or not r["peers"].has(id):
		return
	r["loaded"][id] = true
	if not r["started"] and r["loaded"].size() >= r["peers"].size():
		r["started"] = true
		var world: Node = r["node"].get_node("MAP/world")
		world.begin_match()


func close_room(room_id: int) -> void:
	if not multiplayer.is_server():
		return
	var r: Dictionary = _rooms.get(room_id, {})
	if r.is_empty():
		return
	_rooms.erase(room_id)
	for p in r["peers"]:
		_peer_room.erase(p)
		if multiplayer.get_peers().has(p):
			leave_room.rpc_id(p)
	r["node"].queue_free()
	print("[matchmaker] кімнату ", room_id, " закрито")


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	for mode in _queues.keys():
		if _queues[mode].has(id):
			_queues[mode].erase(id)
			_notify_queue(str(mode))
	if not _peer_room.has(id):
		return
	var room_id: int = _peer_room[id]
	_peer_room.erase(id)
	var r: Dictionary = _rooms.get(room_id, {})
	if r.is_empty():
		return
	r["peers"].erase(id)
	r["loaded"].erase(id)
	r["node"].get_node("MAP/world").on_peer_left(id)
