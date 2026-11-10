extends Node
# Підбір суперника 1х1 + кімнати.
#
# Один сервер (Render) тримає багато кімнат одночасно. Кожна кімната — це окремий
# екземпляр main.tscn за шляхом /root/Matchmaker/Rooms/<room_id>. Той самий шлях
# створюється і на клієнті, тому RPC та MultiplayerSynchronizer знаходять свої ноди.
# Усі "розсилки" тепер йдуть тільки гравцям своєї кімнати (див. rpc_room / targets).

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var rooms_root: Node

# --- тільки сервер ---
var _queue: Array = []        # peer_id-и, що чекають суперника
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


# ------------------------------------------------------------------
# КЛІЄНТ: пошук гри
# ------------------------------------------------------------------

func find_match() -> void:
	request_match.rpc_id(1)


func cancel_search() -> void:
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		cancel_match.rpc_id(1)
	Network.leave_game.call_deferred()


@rpc("authority", "reliable")
func enter_room(room_id: int, peers: Array) -> void:
	if multiplayer.is_server():
		return
	for c in rooms_root.get_children():
		c.queue_free()

	var room: Node = load(GAME_SCENE).instantiate()
	room.name = str(room_id)
	room.set_meta("peer_ids", peers)

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
	Network.leave_game.call_deferred()
	get_tree().change_scene_to_file(MENU_SCENE)


# ------------------------------------------------------------------
# СЕРВЕР: черга і кімнати
# ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func request_match() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id) or _queue.has(id):
		return
	_queue.append(id)
	print("[matchmaker] ", id, " у черзі. Черга: ", _queue.size())
	_try_pair()


@rpc("any_peer", "reliable")
func cancel_match() -> void:
	if not multiplayer.is_server():
		return
	_queue.erase(multiplayer.get_remote_sender_id())


func _try_pair() -> void:
	while _queue.size() >= 2:
		var a: int = _queue.pop_front()
		var b: int = _queue.pop_front()
		_create_room([a, b])


func _create_room(peers: Array) -> void:
	var room_id := _next_room_id
	_next_room_id += 1
	print("[matchmaker] кімната ", room_id, ": ", peers)

	var room: Node = load(GAME_SCENE).instantiate()
	room.name = str(room_id)
	room.set_meta("peer_ids", peers)  # той самий масив, що й у _rooms — оновлюється при виході гравця

	_rooms[room_id] = {"peers": peers, "loaded": {}, "node": room, "started": false}
	for p in peers:
		_peer_room[p] = room_id
	rooms_root.add_child(room)

	for p in peers:
		enter_room.rpc_id(p, room_id, peers)


# Клієнт каже: "сцена кімнати в мене завантажена". Коли обидва готові — старт.
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
	_queue.erase(id)
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
