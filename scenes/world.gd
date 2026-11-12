extends Node3D

@export var player_scene: PackedScene

@export_category("Round Settings")
@export var countdown_seconds: int = 5
@export var round_end_delay: float = 5.0
@export var wins_to_end_game: int = 10
@export var game_over_delay: float = 3.0

@export_category("Warmup Settings")
@export var warmup_respawn_delay: float = 1.0

enum State { WAITING, COUNTDOWN, PLAYING, ROUND_END, GAME_OVER }

# Команди (значення мають збігатися з Player.Team у player.gd)
const TEAM_CT := 0
const TEAM_T := 1
var teams: Dictionary = {}  # player_id:int -> TEAM_CT / TEAM_T

var room: Node                 # корінь кімнати (main)
var room_id: int = -1
var room_peers: Array = []     # peer_id гравців ЦІЄЇ кімнати
var _match_begun: bool = false

var spawn_points: Array[Node3D] = []
var players_node: Node
var state: int = State.WAITING
var countdown_value: int = 0
var scores: Dictionary = {}
var alive_players: Dictionary = {}

# Для кожного player_id: множина peer_id, які вже підтвердили, що нода
# ЦЬОГО гравця реально існує в ЇХНЬОМУ (peer_id) дереві сцени.
var _ready_peers: Dictionary = {}  # player_id:int -> {peer_id:int -> true}

# Останній відомий transform спавну кожного гравця — використовується і
# для респауну, і для "наздоганяння" пізніх пірів актуальним станом.
var _last_spawn_transform: Dictionary = {}  # player_id:int -> Transform3D

var _countdown_timer: Timer
var _round_end_timer: Timer
var _game_over_timer: Timer


func _ready() -> void:
	# world -> MAP -> main (корінь кімнати)
	room = get_node("../..")
	room_id = room.name.to_int()
	room_peers = room.get_meta("peer_ids", [])
	players_node = room.get_node("players")

	for child in room.get_node("SpawnPoints").get_children():
		spawn_points.append(child)

	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	add_child(_countdown_timer)
	_countdown_timer.timeout.connect(_on_countdown_tick)

	_round_end_timer = Timer.new()
	_round_end_timer.wait_time = round_end_delay
	_round_end_timer.one_shot = true
	add_child(_round_end_timer)
	_round_end_timer.timeout.connect(_on_round_end_timeout)

	_game_over_timer = Timer.new()
	_game_over_timer.wait_time = game_over_delay
	_game_over_timer.one_shot = true
	add_child(_game_over_timer)
	_game_over_timer.timeout.connect(_on_game_over_timeout)

	# Клієнт: сцена кімнати готова — повідомляємо сервер. Коли готові обидва,
	# сервер викликає begin_match() (так жоден RPC не губиться до появи нод).
	if not multiplayer.is_server():
		Matchmaker.room_loaded.rpc_id(1, room_id)


# Тільки сервер: обидва гравці завантажили кімнату.
func begin_match() -> void:
	if not multiplayer.is_server():
		return
	_match_begun = true
	_assign_teams()
	state = State.WAITING
	_hud(State.WAITING, 0)
	for id in room_peers.duplicate():
		_on_player_connected(id)
	_check_start_conditions()


# Тільки сервер: випадково ділимо гравців кімнати на КТ і Т.
func _assign_teams() -> void:
	teams.clear()
	var ids := room_peers.duplicate()
	ids.shuffle()
	for i in ids.size():
		teams[ids[i]] = TEAM_CT if i % 2 == 0 else TEAM_T


# ---- розсилки тільки гравцям цієї кімнати ----
func _hud(new_state: int, value: int) -> void:
	for id in room_peers:
		_sync_hud_state.rpc_id(id, new_state, value)


func _scores_sync() -> void:
	for id in room_peers:
		_sync_scores.rpc_id(id, scores)


func _on_player_connected(id: int) -> void:
	scores[id] = 0
	alive_players[id] = true

	# ВАЖЛИВО: MultiplayerSpawner НЕ реплікує вже заспавнені ноди пізнім
	# (late-join) пірам — це підтверджена поведінка Godot. Тому перед
	# спавном НОВОГО гравця вручну "наздоганяємо" його копіями ВСІХ уже
	# існуючих живих гравців — надсилаємо RPC САМЕ цьому новому піру.
	for existing_id in _last_spawn_transform.keys():
		if existing_id == id:
			continue
		if players_node.get_node_or_null(str(existing_id)):
			_rpc_spawn_player.rpc_id(id, existing_id, _last_spawn_transform[existing_id])

	var spawn_index: int = room_peers.find(id)
	_spawn_or_respawn_player(id, max(spawn_index, 0))


# Викликається з Matchmaker, коли гравець вийшов (id вже прибраний з room_peers).
func on_peer_left(id: int) -> void:
	_rpc_despawn_player(id)
	for p in room_peers:
		_rpc_despawn_player.rpc_id(p, id)
	scores.erase(id)
	alive_players.erase(id)
	_ready_peers.erase(id)
	_last_spawn_transform.erase(id)
	teams.erase(id)

	if state == State.GAME_OVER:
		return
	_countdown_timer.stop()
	_round_end_timer.stop()
	if _match_begun and room_peers.size() == 1:
		_end_game(room_peers[0])  # суперник вийшов — технічна перемога
	else:
		Matchmaker.close_room(room_id)


func _check_start_conditions() -> void:
	if state == State.WAITING and room_peers.size() >= 2:
		_start_countdown()


func _start_countdown() -> void:
	state = State.COUNTDOWN
	countdown_value = countdown_seconds
	_hud(State.COUNTDOWN, countdown_value)
	_countdown_timer.start()


func _on_countdown_tick() -> void:
	countdown_value -= 1
	if countdown_value <= 0:
		_countdown_timer.stop()
		_begin_round()
	else:
		_hud(State.COUNTDOWN, countdown_value)


func _begin_round() -> void:
	state = State.PLAYING
	_hud(State.PLAYING, 0)
	_scores_sync()

	var ids := room_peers.duplicate()
	for i in ids.size():
		_spawn_or_respawn_player(ids[i], i)
		alive_players[ids[i]] = true


func _spawn_or_respawn_player(id: int, spawn_index: int) -> void:
	var spawn_point: Node3D = spawn_points[spawn_index % spawn_points.size()]
	var existing := players_node.get_node_or_null(str(id))

	_last_spawn_transform[id] = spawn_point.global_transform

	if existing:
		existing.global_transform = spawn_point.global_transform
		_broadcast_transform_to_ready_peers(id, existing, spawn_point.global_transform)
		_broadcast_revive_to_ready_peers(id, existing)
		_refill_ammo_for_owner(id, existing)
	else:
		var player := player_scene.instantiate()
		player.name = str(id)
		player.set_multiplayer_authority(id)
		player.global_transform = spawn_point.global_transform
		_ready_peers[id] = {}
		players_node.add_child(player, true)

		# Замість автоматичної реплікації MultiplayerSpawner (яка НЕ
		# бекфілить пізніх пірів) — явно розсилаємо всім УЖЕ підключеним
		# пірам команду створити свою локальну копію. "call_local" —
		# сервер теж отримає виклик, але вище він уже створив собі
		# справжню ноду, тож нижче для нього просто нічого не станеться.
		for p in room_peers:
			_rpc_spawn_player.rpc_id(p, id, spawn_point.global_transform)


# Створює локальну копію ноди гравця на клієнті. Викликається:
#  1) broadcast-ом (.rpc) при живому спавні нового гравця
#  2) targeted rpc_id-ом конкретному піру, щоб "наздогнати" його вже
#     існуючими гравцями при підключенні (_on_player_connected)
@rpc("call_local", "reliable")
func _rpc_spawn_player(id: int, t: Transform3D) -> void:
	if multiplayer.is_server():
		return  # сервер уже має справжню ноду, створену напряму

	if players_node.get_node_or_null(str(id)):
		return  # вже існує (дублікат виклику) — нічого не робимо

	var player := player_scene.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	player.global_transform = t
	players_node.add_child(player)


@rpc("call_local", "reliable")
func _rpc_despawn_player(id: int) -> void:
	var node := players_node.get_node_or_null(str(id))
	if node:
		node.queue_free()


# Викликається КОЖНОЮ локальною копією ноди гравця на КОЖНОМУ піру —
# тобто і власником своєї ноди, і будь-ким, хто спостерігає чужого
# гравця, щойно репліка цієї ноди реально з'явилась в його дереві.
@rpc("any_peer", "call_local", "reliable")
func _on_player_node_ready_rpc(id: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1

	if not room_peers.has(peer_id):
		return

	if not _ready_peers.has(id):
		_ready_peers[id] = {}
	_ready_peers[id][peer_id] = true

	var player := players_node.get_node_or_null(str(id))
	if not is_instance_valid(player):
		return

	if teams.has(id):
		player.rpc_id(peer_id, "_set_team", teams[id])
	if _last_spawn_transform.has(id):
		player.rpc_id(peer_id, "_set_spawn_transform", _last_spawn_transform[id])
	if alive_players.get(id, true):
		player.rpc_id(peer_id, "_revive")

	if peer_id == id:
		_refill_ammo_for_owner(id, player)


func _broadcast_transform_to_ready_peers(player_id: int, player: Node, t: Transform3D) -> void:
	var ready_set: Dictionary = _ready_peers.get(player_id, {})
	for peer_id in room_peers:
		if ready_set.has(peer_id):
			player.rpc_id(peer_id, "_set_spawn_transform", t)


func _broadcast_revive_to_ready_peers(player_id: int, player: Node) -> void:
	var ready_set: Dictionary = _ready_peers.get(player_id, {})
	for peer_id in room_peers:
		if ready_set.has(peer_id):
			player.rpc_id(peer_id, "_revive")


func _refill_ammo_for_owner(player_id: int, player: Node) -> void:
	var ready_set: Dictionary = _ready_peers.get(player_id, {})
	if not ready_set.has(player_id):
		return

	var weapon := player.get_node_or_null("head/Camera3D")
	if weapon and weapon.has_method("_reset_ammo_rpc"):
		weapon._reset_ammo_rpc.rpc_id(player_id)


@rpc("any_peer", "call_local", "reliable")
func _report_death_rpc(victim_id: int, attacker_id: int) -> void:
	if multiplayer.is_server():
		report_death(victim_id, attacker_id)


func report_death(victim_id: int, attacker_id: int) -> void:
	if not alive_players.get(victim_id, false):
		return

	alive_players[victim_id] = false

	if state == State.WAITING or state == State.COUNTDOWN:
		_schedule_warmup_respawn(victim_id)
		return

	if state != State.PLAYING:
		return

	if attacker_id != -1 and attacker_id != victim_id and scores.has(attacker_id):
		scores[attacker_id] += 1

	_scores_sync()

	if attacker_id != -1 and scores.get(attacker_id, 0) >= wins_to_end_game:
		_end_game(attacker_id)
		return

	state = State.ROUND_END
	_hud(State.ROUND_END, 0)
	_round_end_timer.start()


func _schedule_warmup_respawn(victim_id: int) -> void:
	await get_tree().create_timer(warmup_respawn_delay).timeout

	if state != State.WAITING and state != State.COUNTDOWN:
		return
	if not room_peers.has(victim_id):
		return

	var spawn_index: int = room_peers.find(victim_id)
	_spawn_or_respawn_player(victim_id, max(spawn_index, 0))
	alive_players[victim_id] = true


func _on_round_end_timeout() -> void:
	if state != State.GAME_OVER:
		_begin_round()


func _end_game(winner_id: int) -> void:
	state = State.GAME_OVER
	_hud(State.GAME_OVER, winner_id)
	_game_over_timer.start()


func _on_game_over_timeout() -> void:
	Matchmaker.close_room(room_id)


@rpc("call_local", "reliable")
func _sync_hud_state(new_state: int, value: int) -> void:
	Hud.set_state(new_state, value)


@rpc("call_local", "reliable")
func _sync_scores(new_scores: Dictionary) -> void:
	Hud.set_scores(new_scores)
