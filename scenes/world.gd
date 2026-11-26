extends Node3D

@export var player_scene: PackedScene

@export_category("Round Settings")
@export var countdown_seconds: int = 5
@export var round_end_delay: float = 3.0   # скільки секунд після смерті до нового раунду
@export var freeze_seconds: int = 3          # скільки секунд на старті раунду гравці стоять (3-2-1)
@export var round_time_seconds: int = 60     # ліміт часу на раунд; після нього раунд — нічия (0 = без ліміту)
@export var wins_to_end_game: int = 10
@export var game_over_delay: float = 3.0

@export_category("Map Settings")
# true  — карта oasis і її точки спавну (WingmanSpawns) використовуються в УСІХ режимах (1×1, бот, 2×2).
# false — як раніше: 1×1 і бот на desert (DesertSpawns), лише 2×2 на oasis.
@export var oasis_in_all_modes: bool = false

@export_category("Warmup Settings")
@export var warmup_respawn_delay: float = 1.0

enum State { WAITING, COUNTDOWN, PLAYING, ROUND_END, GAME_OVER, FREEZE }

# Команди (значення мають збігатися з Player.Team у player.gd)
const TEAM_CT := 0
const TEAM_T := 1
const BOT_ID := 2
const BOT_AI_SCRIPT := preload("res://scenes/bot_ai.gd")
const BOMB_SYSTEM_SCRIPT := preload("res://scenes/bomb_system.gd")
var bomb: Node = null   # BombSystem — тільки в 2×2 (не з ботом)
var teams: Dictionary = {}  # player_id:int -> TEAM_CT / TEAM_T

var room: Node                 # корінь кімнати (main)
var room_id: int = -1
var game_mode: String = "1v1"
var room_peers: Array = []     # реальні peer_id цієї кімнати (бот не є мережевим peer)
var bot_match: bool = false
var _match_begun: bool = false
var _rewarded: bool = false     # нагорода за матч видається лише раз

var spawn_points: Array[Node3D] = []
var _use_oasis: bool = false   # яка карта активна => з якої групи беремо спавни
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

# Ніки гравців (peer_id -> нік). Заповнює сервер, клієнти отримують разом з рахунком.
var nicks: Dictionary = {}
# Ніки, які клієнт отримав від сервера разом з рахунком (на клієнті `nicks` порожній).
var _known_nicks: Dictionary = {}
var _known_teams: Dictionary = {}   # команди, які сервер надіслав клієнтам
var _scoreboard: Control = null

var _countdown_timer: Timer
var _round_tick_timer: Timer      # щосекунди рахує час до наступного раунду після смерті
var _round_end_left: int = 0
var _freeze_timer: Timer          # відлік 3-2-1 на старті раунду (гравці стоять)
var _freeze_left: int = 0
var _play_timer: Timer           # щосекунди відлічує час раунду (60 с)
var _play_left: int = 0
var _round_end_timer: Timer
var _game_over_timer: Timer


func _setup_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X   # чіткіші текстури під кутом (земля, стіни)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.directional_shadow_atlas_set_size(4096, true)


func _ready() -> void:
	_setup_graphics()
	# world -> MAP -> main (корінь кімнати)
	room = get_node("../..")
	room_id = room.name.to_int()
	room_peers = room.get_meta("peer_ids", [])
	game_mode = str(room.get_meta("game_mode", "1v1"))
	# Страховка: 4 гравці в кімнаті — це завжди 2×2 (спавни з WingmanSpawns),
	# навіть якщо мета "game_mode" чомусь не дійшла. Рішення фіксуємо один раз,
	# щоб воно не змінювалось, коли хтось вийде з матчу.
	if room_peers.size() >= 4:
		game_mode = "2v2"
	_configure_map_and_spawns()
	bot_match = bool(room.get_meta("bot_match", false))
	players_node = room.get_node("players")

	spawn_points = _collect_spawn_points()
	print("[world] room %d: mode=%s, players=%d, spawn group=%s, points=%d" % [room_id, game_mode, room_peers.size(), _get_spawn_root().name if _get_spawn_root() else "—", spawn_points.size()])
	for i in spawn_points.size():
		print("[world] point #%d: %s  pos=%s" % [i, spawn_points[i].name, str(spawn_points[i].global_position)])
	if game_mode == "2v2" and spawn_points.size() < 4:
		push_warning("world.gd: 2v2 mode, but only %d spawn points (4 needed). Check SpawnPoints/WingmanSpawns in player.tscn!" % spawn_points.size())
	if spawn_points.is_empty():
		push_error("world.gd: no spawn points found in SpawnPoints/DesertSpawns or SpawnPoints/WingmanSpawns!")

	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	add_child(_countdown_timer)
	_countdown_timer.timeout.connect(_on_countdown_tick)

	_round_tick_timer = Timer.new()
	_round_tick_timer.wait_time = 1.0
	add_child(_round_tick_timer)
	_round_tick_timer.timeout.connect(_on_round_tick)

	_freeze_timer = Timer.new()
	_freeze_timer.wait_time = 1.0
	add_child(_freeze_timer)
	_freeze_timer.timeout.connect(_on_freeze_tick)

	_play_timer = Timer.new()
	_play_timer.wait_time = 1.0
	add_child(_play_timer)
	_play_timer.timeout.connect(_on_play_tick)

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

	# Бомба: тільки в 2×2 проти людей.
	if game_mode == "2v2" and not bot_match:
		bomb = BOMB_SYSTEM_SCRIPT.new()
		bomb.name = "BombSystem"
		add_child(bomb)
		bomb.call("setup", self)

	# Клієнт: малюємо табло з ніками і надсилаємо серверу свій нік.
	if not multiplayer.is_server() or bot_match:
		_make_scoreboard()
		if not bot_match:
			var my_nick: String = str(Engine.get_meta("player_nick", "Player"))
			_submit_nick.rpc_id(1, my_nick)

	# Клієнт: сцена кімнати готова — повідомляємо сервер. Коли готові обидва,
	# сервер викликає begin_match() (так жоден RPC не губиться до появи нод).
	if not multiplayer.is_server():
		Matchmaker.room_loaded.rpc_id(1, room_id)


# У цій сцені зберігаються обидві карти. Режим кімнати визначає, яка активна.
func _configure_map_and_spawns() -> void:
	var desert := get_node_or_null("../desert_courtyard_textured (1)")
	var oasis := get_node_or_null("../wingman_oasis_large")
	var use_oasis := game_mode == "2v2" or oasis_in_all_modes
	_use_oasis = use_oasis
	_set_map_active(desert, not use_oasis)
	_set_map_active(oasis, use_oasis)
	_hide_collision_meshes(oasis)

	var spawn_root := _get_spawn_root()
	# Якщо в групі вже є 4+ точок (по 2 на команду) — додаткових не треба.
	if use_oasis and spawn_root != null and spawn_root.get_child_count() >= 2 and spawn_root.get_child_count() < 4:
		# Для 2×2 створюємо по дві близькі точки на кожній стороні карти.
		# Перші дві точки вже є у сцені; додаткові розташовуються поруч із ними.
		for source_name in ["SpawnPoints1", "SpawnPoints2"]:
			var source := spawn_root.get_node_or_null(source_name) as Node3D
			if source == null:
				continue
			var extra := Marker3D.new()
			extra.name = source_name + "_TeamMate"
			extra.transform = source.transform
			extra.position.x += 2.5
			spawn_root.add_child(extra)


# Точки спавну лежать у підгрупах: SpawnPoints/DesertSpawns (1×1 і бот)
# та SpawnPoints/WingmanSpawns (2×2). Раніше код брав прямих дітей SpawnPoints,
# тобто самі групи (позиція 0,0,0) — через це гравці з'являлись під картою.
func _get_spawn_root() -> Node3D:
	var group_name := "WingmanSpawns" if _use_oasis else "DesertSpawns"
	return room.get_node_or_null("SpawnPoints/" + group_name) as Node3D


func _collect_spawn_points() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var root := _get_spawn_root()
	if root == null:
		# Запасний варіант: старий плаский формат SpawnPoints/<Marker3D>.
		root = room.get_node_or_null("SpawnPoints") as Node3D
	if root == null:
		return result
	for child in root.get_children():
		if child is Marker3D:
			result.append(child as Node3D)
	return result


# Для карти Oasis (2×2): ставить кожну точку спавну на реальну підлогу карти.
# Промінь б'ється тільки в колізію карти, тому гравець завжди з'являється НА oasis,
# а не в повітрі/під землею. Усе, що знайдено (або не знайдено), пишеться в консоль.
func _snap_oasis_spawns_to_ground() -> void:
	if not _use_oasis:
		return
	var oasis := get_node_or_null("../wingman_oasis_large") as Node3D
	if oasis == null:
		push_error("world.gd: node wingman_oasis_large not found — oasis spawns can't be attached to the map!")
		return
	var space := get_world_3d().direct_space_state
	var mask := 0xFFFFFFFF & ~2   # усі шари, крім шару гравців
	for sp in spawn_points:
		var pos := sp.global_position
		var hit_y := NAN
		# 1) спершу шукаємо підлогу трохи нижче/вище маркера (щоб не влучити в дах),
		# 2) якщо не знайшли — стріляємо зверху вниз з великої висоти.
		for start_up in [3.0, 80.0]:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * start_up, pos + Vector3.DOWN * 400.0, mask)
			var r := space.intersect_ray(q)
			if not r.is_empty():
				hit_y = (r["position"] as Vector3).y
				break
		if is_nan(hit_y):
			push_warning("world.gd: there is NO oasis collision under spawn point '%s' (%s) — players will fall through here. Check that the glb has collision and that the point is above the map." % [sp.name, str(pos)])
			continue
		# Початок гравця — центр капсули, тому піднімаємо на пів-висоти + запас.
		sp.global_position = Vector3(pos.x, hit_y + 1.2, pos.z)
		print("[world] oasis spawn %s: y %.2f -> %.2f" % [sp.name, pos.y, sp.global_position.y])


var _map_fix_info: String = ""

# У glb колізійні меші (*_collision-col) не мають матеріалу і Godot малює їх білими
# поверх справжньої геометрії. Ховаємо лише картинку — колізія (StaticBody3D) лишається.
func _hide_collision_meshes(map_node: Node) -> void:
	if map_node == null:
		return
	var hidden := 0
	for node in map_node.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var has_material := false
		for i in mi.mesh.get_surface_count():
			if mi.get_active_material(i) != null:
				has_material = true
				break
		if String(mi.name).to_lower().contains("collision") or not has_material:
			mi.visible = false
			hidden += 1
	_map_fix_info = "hidden collision meshes: %d" % hidden
	print("[map-fix] ", _map_fix_info)


func _set_map_active(map_node: Node, active: bool) -> void:
	if map_node == null:
		return
	map_node.visible = active
	map_node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# Прихована 3D-карта все ще може блокувати гравців фізичними колізіями.
	var stack: Array[Node] = [map_node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is CollisionObject3D:
			var body := current as CollisionObject3D
			if active:
				if body.has_meta("saved_collision_layer"):
					body.collision_layer = int(body.get_meta("saved_collision_layer"))
					body.collision_mask = int(body.get_meta("saved_collision_mask"))
			else:
				if not body.has_meta("saved_collision_layer"):
					body.set_meta("saved_collision_layer", body.collision_layer)
					body.set_meta("saved_collision_mask", body.collision_mask)
				body.collision_layer = 0
				body.collision_mask = 0
		for child in current.get_children():
			stack.append(child)


# Тільки сервер: обидва гравці завантажили кімнату.
func begin_match() -> void:
	if not multiplayer.is_server():
		return
	_match_begun = true
	_snap_oasis_spawns_to_ground()   # на цей момент фізика карти вже точно готова
	_assign_teams()
	if bot_match:
		nicks[1] = str(Engine.get_meta("player_nick", "Player"))
	state = State.WAITING
	_hud(State.WAITING, 0)
	for id in room_peers.duplicate():
		_on_player_connected(id)
	if bot_match:
		_spawn_bot()
	_scores_sync()   # щоб табло з ніками з'явилось ще до старту раунду
	_check_start_conditions()


# Локальний бот живе тільки на серверній/офлайн-копії. Його тіло та хітбокси — ті самі, що в гравця.
func _spawn_bot() -> void:
	if players_node.get_node_or_null(str(BOT_ID)):
		return
	var spawn_index := _bot_spawn_index()
	var bot := player_scene.instantiate() as CharacterBody3D
	bot.name = str(BOT_ID)
	bot.set_multiplayer_authority(BOT_ID)
	bot.set_meta("is_bot", true)
	bot.global_transform = spawn_points[spawn_index].global_transform
	players_node.add_child(bot, true)
	bot.call("_set_team", int(teams.get(BOT_ID, TEAM_T)))
	bot.set_meta("bot_nick", "BOT | TACTICAL")
	var ai := Node.new()
	ai.name = "BotAI"
	ai.set_script(BOT_AI_SCRIPT)
	bot.add_child(ai)
	scores[BOT_ID] = 0
	alive_players[BOT_ID] = true
	nicks[BOT_ID] = "BOT | TACTICAL"
	bot.set("frozen", true)

# Тільки сервер: випадково ділимо гравців кімнати на КТ і Т.
func _assign_teams() -> void:
	teams.clear()
	if bot_match:
		# У локальному матчі команди сталі: гравець — CT, бот — T.
		teams[1] = TEAM_CT
		teams[BOT_ID] = TEAM_T
		return
	var ids := room_peers.duplicate()
	ids.shuffle()
	if game_mode == "2v2":
		for i in ids.size():
			teams[ids[i]] = TEAM_CT if i < 2 else TEAM_T
	else:
		for i in ids.size():
			teams[ids[i]] = TEAM_CT if i % 2 == 0 else TEAM_T


# ---- розсилки тільки гравцям цієї кімнати ----
func _hud(new_state: int, value: int) -> void:
	if bot_match:
		_sync_hud_state(new_state, value)
		return
	for id in room_peers:
		_sync_hud_state.rpc_id(id, new_state, value)


func _scores_sync() -> void:
	if bot_match:
		_sync_scores(scores)
		_sync_scoreboard(scores, nicks, teams)
		return
	for id in room_peers:
		_sync_scores.rpc_id(id, scores)
		_sync_scoreboard.rpc_id(id, scores, nicks, teams)


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

	var spawn_index: int = _spawn_index_for(id)
	_spawn_or_respawn_player(id, spawn_index)


# Викликається з Matchmaker, коли гравець вийшов (id вже прибраний з room_peers).
func on_peer_left(id: int) -> void:
	_rpc_despawn_player(id)
	for p in room_peers:
		_rpc_despawn_player.rpc_id(p, id)
		_rpc_player_left.rpc_id(p, str(nicks.get(id, "Player")))   # кіл-таб: "<нік> left the game"
	scores.erase(id)
	nicks.erase(id)
	alive_players.erase(id)
	_ready_peers.erase(id)
	_last_spawn_transform.erase(id)
	teams.erase(id)

	if state == State.GAME_OVER:
		return
	_countdown_timer.stop()
	_round_end_timer.stop()
	_round_tick_timer.stop()
	_freeze_timer.stop()
	_play_timer.stop()
	if bomb:
		bomb.call("reset")
	if _match_begun and room_peers.size() == 1:
		_end_game(room_peers[0])  # суперник вийшов — технічна перемога
	else:
		Matchmaker.close_room(room_id)


func _check_start_conditions() -> void:
	if state == State.WAITING and (room_peers.size() >= 2 or bot_match and room_peers.size() >= 1):
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
	_round_tick_timer.stop()
	_play_timer.stop()
	if bomb:
		bomb.call("reset")
	_scores_sync()

	# Всіх гравців ставимо на спавни...
	var ids := room_peers.duplicate()
	if bot_match:
		ids.append(BOT_ID)
	for i in ids.size():
		var spawn_index := _bot_spawn_index() if bot_match and ids[i] == BOT_ID else _spawn_index_for(ids[i])
		_spawn_or_respawn_player(ids[i], spawn_index)
		alive_players[ids[i]] = true

	# ...і на кілька секунд "заморожуємо": можна дивитись, але не рухатись і не стріляти.
	_start_freeze()


func _start_freeze() -> void:
	if bomb:
		bomb.call("assign_carrier")
	state = State.FREEZE
	_freeze_left = freeze_seconds
	_set_frozen_all(true)
	_hud(State.FREEZE, _freeze_left)
	_freeze_timer.start()


func _on_freeze_tick() -> void:
	if state != State.FREEZE:
		_freeze_timer.stop()
		return
	_freeze_left -= 1
	if _freeze_left > 0:
		_hud(State.FREEZE, _freeze_left)
		return
	_freeze_timer.stop()
	_set_frozen_all(false)
	state = State.PLAYING
	_play_left = round_time_seconds
	_hud(State.PLAYING, _play_left)
	if round_time_seconds > 0:
		_play_timer.start()


# Тільки сервер: щосекунди зменшує час раунду; на нулі — нічия.
func _on_play_tick() -> void:
	if state != State.PLAYING:
		_play_timer.stop()
		return
	_play_left -= 1
	if _play_left > 0:
		_hud(State.PLAYING, _play_left)
	else:
		_play_timer.stop()
		_on_round_time_up()


# Час раунду вийшов: очко нікому не дається, починається наступний раунд.
func _on_round_time_up() -> void:
	if bomb:
		# 2×2: T не встигли поставити бомбу — раунд виграє CT.
		var scorer := -1
		for id in alive_players.keys():
			if alive_players[id] and int(teams.get(id, -1)) == TEAM_CT and scores.has(id):
				scorer = id
				break
		if scorer == -1:
			for id in scores.keys():
				if int(teams.get(id, -1)) == TEAM_CT:
					scorer = id
					break
		_finish_round(scorer)
		return
	_start_round_end()


# Бомба поставлена: ліміт часу раунду більше не діє, далі тікає таймер бомби.
func on_bomb_planted() -> void:
	_play_timer.stop()


# Вибух (виграє T) або розмінування (виграє CT).
func on_bomb_result(winning_team: int, preferred_id: int) -> void:
	if state != State.PLAYING:
		return
	var scorer := preferred_id
	if not scores.has(scorer) or int(teams.get(scorer, -1)) != winning_team:
		scorer = -1
		for id in scores.keys():
			if int(teams.get(id, -1)) == winning_team:
				scorer = id
				break
	_finish_round(scorer)


# Очко переможцю раунду (scorer = -1 — нікому), перевірка кінця гри, пауза до нового раунду.
func _finish_round(scorer: int) -> void:
	if scorer != -1:
		scores[scorer] += 1
	_scores_sync()
	if scorer != -1:
		var winning_score := int(scores.get(scorer, 0))
		if game_mode == "2v2":
			winning_score = _team_score(int(teams.get(scorer, TEAM_CT)))
		if winning_score >= wins_to_end_game:
			_end_game(scorer)
			return
	_start_round_end()


func _start_round_end() -> void:
	_play_timer.stop()
	if bomb:
		bomb.call("halt")
	state = State.ROUND_END
	_round_end_left = int(round_end_delay)
	_hud(State.ROUND_END, _round_end_left)   # значення = секунди до наступного раунду
	_round_end_timer.start()
	_round_tick_timer.start()


# Тільки сервер: кажемо власнику кожного гравця, що він (не) може рухатись.
func _set_frozen_all(value: bool) -> void:
	if bot_match:
		var bot := players_node.get_node_or_null(str(BOT_ID))
		if bot:
			bot.set("frozen", value)
		var local_player := players_node.get_node_or_null("1")
		if local_player:
			local_player.set("frozen", value)
		return
	for id in room_peers:
		var player := players_node.get_node_or_null(str(id))
		if is_instance_valid(player) and _ready_peers.get(id, {}).has(id):
			player.rpc_id(id, "_set_frozen", value)


# Індекс спавну бота: на oasis — протилежний куток карти (WingmanSpawns3), на desert — друга точка.
func _bot_spawn_index() -> int:
	if _use_oasis:
		return 2 if spawn_points.size() > 2 else (1 if spawn_points.size() > 1 else 0)
	return 1 if spawn_points.size() > 1 else 0


func _spawn_index_for(id: int) -> int:
	if game_mode != "2v2":
		var slot: int = max(room_peers.find(id), 0)
		# На oasis у 1×1 гравці стають у протилежні кутки (точки 1 і 3), а не поруч.
		return slot * 2 if _use_oasis else slot
	var team := int(teams.get(id, TEAM_CT))
	var teammates: Array = []
	for peer_id in room_peers:
		if int(teams.get(peer_id, TEAM_CT)) == team:
			teammates.append(peer_id)
	var teammate_slot := teammates.find(id)
	return (0 if team == TEAM_CT else 2) + max(teammate_slot, 0)


func _spawn_or_respawn_player(id: int, spawn_index: int) -> void:
	var spawn_point: Node3D = spawn_points[spawn_index % spawn_points.size()]
	print("[spawn] room %d mode=%s oasis=%s id=%d team=%s index=%d -> %s pos=%s" % [room_id, game_mode, str(_use_oasis), id, str(teams.get(id, "-")), spawn_index, spawn_point.name, str(spawn_point.global_position)])
	if bot_match and id == BOT_ID:
		var bot_existing := players_node.get_node_or_null(str(BOT_ID))
		if bot_existing:
			bot_existing.global_transform = spawn_point.global_transform
			bot_existing.call("_revive")
			bot_existing.set("frozen", true)
		return
	var existing := players_node.get_node_or_null(str(id))

	_last_spawn_transform[id] = spawn_point.global_transform

	if existing:
		existing.global_transform = spawn_point.global_transform
		if bot_match:
			# Offline-матч не проходить мережевий ready-handshake, тому
			# команду локальному гравцю призначаємо безпосередньо тут.
			if teams.has(id):
				existing.call("_set_team", int(teams[id]))
			existing.call("_set_spawn_transform", spawn_point.global_transform)
			existing.call("_revive")
		else:
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
		if bot_match and teams.has(id):
			player.call("_set_team", int(teams[id]))

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

	print("[client spawn] mode=%s oasis=%s id=%d pos=%s" % [game_mode, str(_use_oasis), id, str(t.origin)])
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
	if bot_match:
		var local_weapon := player.get_node_or_null("head/Camera3D")
		if local_weapon and local_weapon.has_method("_reset_ammo_rpc"):
			local_weapon.call("_reset_ammo_rpc")
		return
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


# true, якщо обидва гравці в одній команді (для блокування урону по своїх).
# На сервері / у грі з ботом беремо teams, на клієнті — те, що надіслав сервер.
func are_teammates(a: int, b: int) -> bool:
	if a == b or a == -1 or b == -1:
		return false
	var t: Dictionary = teams if not teams.is_empty() else _known_teams
	if not t.has(a) or not t.has(b):
		return false
	return int(t[a]) == int(t[b])


func report_death(victim_id: int, attacker_id: int) -> void:
	if not alive_players.get(victim_id, false):
		return

	alive_players[victim_id] = false
	if bomb:
		bomb.call("on_player_died", victim_id)

	if state == State.WAITING or state == State.COUNTDOWN:
		_schedule_warmup_respawn(victim_id)
		return

	if state != State.PLAYING:
		return

	# Раунд триває, поки в команді загиблого лишається хоч один живий гравець.
	var victim_team := int(teams.get(victim_id, -1))
	# Бомба вже стоїть: навіть якщо всі T загинули, раунд триває до вибуху чи розмінування.
	if bomb and bool(bomb.get("planted")) and victim_team == TEAM_T:
		return
	if victim_team != -1:
		for id in alive_players.keys():
			if alive_players[id] and int(teams.get(id, -2)) == victim_team:
				return

	# Уся команда загинула: очко отримує той, хто добив останнього.
	var scorer := attacker_id
	if scorer == -1 or scorer == victim_id or not scores.has(scorer) \
			or int(teams.get(scorer, -1)) == victim_team:
		scorer = -1
		for id in alive_players.keys():
			if alive_players[id] and teams.has(id) and int(teams[id]) != victim_team and scores.has(id):
				scorer = id
				break
	_finish_round(scorer)


func _schedule_warmup_respawn(victim_id: int) -> void:
	await get_tree().create_timer(warmup_respawn_delay).timeout

	if state != State.WAITING and state != State.COUNTDOWN:
		return
	if not room_peers.has(victim_id) and not (bot_match and victim_id == BOT_ID):
		return

	var spawn_index: int = _spawn_index_for(victim_id)
	if bot_match and victim_id == BOT_ID:
		spawn_index = _bot_spawn_index()
	_spawn_or_respawn_player(victim_id, spawn_index)
	alive_players[victim_id] = true


func _on_round_tick() -> void:
	if state != State.ROUND_END:
		_round_tick_timer.stop()
		return
	_round_end_left -= 1
	if _round_end_left > 0:
		_hud(State.ROUND_END, _round_end_left)
	else:
		_round_tick_timer.stop()


func _on_round_end_timeout() -> void:
	if state != State.GAME_OVER:
		_begin_round()


func _end_game(winner_id: int) -> void:
	_round_tick_timer.stop()
	_play_timer.stop()
	if bomb:
		bomb.call("halt")
	_freeze_timer.stop()
	state = State.GAME_OVER
	_reward_winner(winner_id)
	_hud(State.GAME_OVER, winner_id)
	_game_over_timer.start()


# Нагорода коїнами. Рахується за рахунком: чим більше раундів програв переможець, тим менше.
# Технічна перемога (суперник вийшов, рахунок < wins_to_end_game) нагороди не дає.
func _reward_winner(winner_id: int) -> void:
	if _rewarded:
		return
	_rewarded = true
	var winner_score := int(scores.get(winner_id, 0))
	if game_mode == "2v2":
		winner_score = _team_score(int(teams.get(winner_id, TEAM_CT)))
	if winner_score < wins_to_end_game:
		return
	if bot_match:
		# Офлайн-матч: сервера тут немає. Результат лишаємо в пам'яті, меню відправить його
		# на сервер після повернення (див. menu.gd / Economy.report_bot_win).
		if winner_id == 1:
			Engine.set_meta("pending_bot_win", int(scores.get(BOT_ID, 0)))
		return
	if multiplayer.is_server():
		var loser_score := 0
		if game_mode == "2v2":
			var losing_team := TEAM_T if int(teams.get(winner_id, TEAM_CT)) == TEAM_CT else TEAM_CT
			loser_score = _team_score(losing_team)
		else:
			for id in scores.keys():
				if id != winner_id:
					loser_score = max(loser_score, int(scores[id]))
		Economy.award_pvp_win(winner_id, loser_score)


func _on_game_over_timeout() -> void:
	if bot_match:
		Matchmaker.leave_to_menu()
	else:
		Matchmaker.close_room(room_id)


@rpc("call_local", "reliable")
func _sync_hud_state(new_state: int, value: int) -> void:
	Hud.set_state(new_state, value)
	if bomb:
		bomb.call("on_hud_state", new_state, value)
	if _scoreboard:
		_scoreboard.call("set_state", new_state, value)


@rpc("call_local", "reliable")
func _sync_scores(new_scores: Dictionary) -> void:
	Hud.set_scores(new_scores)


# ---------- Ніки та табло ----------
@rpc("any_peer", "reliable")
func _submit_nick(nick: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not room_peers.has(id):
		return
	nick = nick.strip_edges().substr(0, 16)
	nicks[id] = nick if nick != "" else "Player"


@rpc("call_local", "reliable")
func _sync_scoreboard(new_scores: Dictionary, new_nicks: Dictionary, new_teams: Dictionary) -> void:
	_known_nicks = new_nicks.duplicate()
	_known_teams = new_teams.duplicate()
	if _scoreboard == null:
		return
	var my_id := multiplayer.get_unique_id()
	if game_mode == "2v2":
		var my_team := int(new_teams.get(my_id, TEAM_CT))
		var enemy_team := TEAM_T if my_team == TEAM_CT else TEAM_CT
		var my_ids: Array = []
		var enemy_ids: Array = []
		var my_total := 0
		var enemy_total := 0
		for id in new_scores.keys():
			if int(new_teams.get(id, TEAM_CT)) == my_team:
				my_ids.append(id)
				my_total += int(new_scores[id])
			else:
				enemy_ids.append(id)
				enemy_total += int(new_scores[id])
		var my_names := PackedStringArray()
		var enemy_names := PackedStringArray()
		for id in my_ids:
			my_names.append(str(new_nicks.get(id, "Player")))
		for id in enemy_ids:
			enemy_names.append(str(new_nicks.get(id, "Player")))
		_scoreboard.call("update_board", " + ".join(my_names), my_total,
			" + ".join(enemy_names), enemy_total)
	else:
		var enemy_id := -1
		for id in new_scores.keys():
			if id != my_id:
				enemy_id = id
		_scoreboard.call("update_board",
			str(new_nicks.get(my_id, "Player")), int(new_scores.get(my_id, 0)),
			str(new_nicks.get(enemy_id, "Player")), int(new_scores.get(enemy_id, 0)))


func _team_score(team_id: int) -> int:
	var total := 0
	for id in scores.keys():
		if int(teams.get(id, TEAM_CT)) == team_id:
			total += int(scores[id])
	return total



# Нік гравця за id (для кіл-табу). Працює і на сервері, і на клієнті, і в грі з ботом.
func get_nick(id: int) -> String:
	var n: String = str(_known_nicks.get(id, nicks.get(id, "")))
	return n if n != "" else "Player"


func _make_scoreboard() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_scoreboard = Scoreboard.new()
	layer.add_child(_scoreboard)


# Кіл-таб: суперник вийшов з гри.
@rpc("call_local", "reliable")
func _rpc_player_left(nick: String) -> void:
	var my_weapon := players_node.get_node_or_null("%d/head/Camera3D" % multiplayer.get_unique_id())
	if my_weapon and my_weapon.has_method("show_left_message"):
		my_weapon.show_left_message(nick)
