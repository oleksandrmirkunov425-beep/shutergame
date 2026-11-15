extends Node
# autoload/economy.gd — Project Settings -> Autoload, ім'я "Economy".
# Баланс зберігається і рахується ТІЛЬКИ на сервері. Клієнт лише показує число від сервера.
# Сховище: Firebase Realtime Database (якщо задані змінні середовища FIREBASE_URL і FIREBASE_SECRET),
# інакше — локальний файл (для тестів на своєму ПК).

# ---------- Налаштування нагород ----------
const PVP_MAX_REWARD := 30        # перемога 10:0 над гравцем
const BOT_MAX_REWARD := 45        # перемога 10:0 над ботом
const WINS_TO_END := 10           # має збігатися з world.wins_to_end_game
# Матч з ботом іде офлайн, тому сервер не може його перевірити — обмежуємо накрутку:
const BOT_MIN_INTERVAL_SEC := 90  # не частіше ніж раз на 90 с
const BOT_DAILY_CAP := 600        # максимум коїнів за добу з ботів

const DB_PATH := "user://economy_db.json"      # сервер, лише якщо Firebase не налаштований
const TOKEN_PATH := "user://account.cfg"       # клієнт: лише "логін" (токен), не гроші
const FETCH_RETRIES := 3

# ---------- Клієнт: те, що показуємо в меню ----------
var view_coins: int = -1          # -1 = ще не отримали від сервера
var view_last_reward: int = 0     # скільки щойно нараховано (меню покаже "+N")
signal profile_updated

# ---------- Сервер ----------
var _peer_acc: Dictionary = {}    # peer_id -> ключ акаунта (лише ПІСЛЯ завантаження профілю)
var _db: Dictionary = {}          # ключ акаунта -> профіль (кеш у пам'яті)
var _loading: Dictionary = {}     # peer_id -> true, поки профіль вантажиться з Firebase
var _fb_url: String = ""
var _fb_secret: String = ""


func _ready() -> void:
	if not _is_server_build():
		return
	_fb_url = OS.get_environment("FIREBASE_URL").strip_edges().rstrip("/")
	_fb_secret = OS.get_environment("FIREBASE_SECRET").strip_edges()
	if _use_firebase():
		print("[economy] storage: Firebase")
	else:
		print("[economy] storage: local file (Firebase не налаштований)")
		_load_file()
	multiplayer.peer_disconnected.connect(_on_peer_gone)


func _is_server_build() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()


func _use_firebase() -> bool:
	return _fb_url != "" and _fb_secret != ""


# Чим більше раундів програв переможець, тим менша нагорода: 10:0 -> max, 10:5 -> половина, 10:9 -> ~10%.
static func calc_reward(max_reward: int, rounds_lost: int) -> int:
	var lost := clampi(rounds_lost, 0, WINS_TO_END - 1)
	return maxi(1, roundi(max_reward * float(WINS_TO_END - lost) / WINS_TO_END))


static func _default_profile() -> Dictionary:
	return {"coins": 0, "last_bot_unix": 0, "bot_day": "", "bot_today": 0}


# ====================== КЛІЄНТ ======================
func send_hello() -> void:
	hello.rpc_id(1, _get_token())


func _get_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(TOKEN_PATH) == OK:
		var t: String = str(cfg.get_value("account", "token", ""))
		if t.length() == 32:
			return t
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value("account", "token", token)
	cfg.save(TOKEN_PATH)
	return token


@rpc("authority", "reliable")
func sync_profile(coins: int, reward: int) -> void:
	if multiplayer.is_server():
		return
	view_coins = coins
	if reward > 0:
		view_last_reward = reward
	profile_updated.emit()


# ====================== СЕРВЕР: вхід ======================
@rpc("any_peer", "reliable")
func hello(token: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _peer_acc.has(peer) or _loading.has(peer):
		return
	if token.length() != 32 or not token.is_valid_hex_number(false):
		return
	var key := token.sha256_text()
	if _db.has(key):
		_bind(peer, key)
	elif _use_firebase():
		_loading[peer] = true
		_fetch_profile(peer, key, FETCH_RETRIES)
	else:
		_db[key] = _default_profile()
		_save_profile(key)
		_bind(peer, key)


func _bind(peer: int, key: String) -> void:
	_peer_acc[peer] = key
	_push(peer, 0)


func _on_peer_gone(peer: int) -> void:
	var key: String = _peer_acc.get(peer, "")
	_peer_acc.erase(peer)
	_loading.erase(peer)
	# З Firebase кеш чистимо, щоб не тримати в пам'яті всіх, хто колись заходив.
	if _use_firebase() and key != "" and not _peer_acc.values().has(key):
		_db.erase(key)


# ====================== СЕРВЕР: нарахування ======================
# Викликається з world.gd на сервері, коли гравець виграв матч до 10 перемог.
func award_pvp_win(winner_peer: int, rounds_lost: int) -> void:
	if not multiplayer.is_server():
		return
	_give(winner_peer, calc_reward(PVP_MAX_REWARD, rounds_lost))


# Клієнт повідомляє про виграш у боті (rounds_lost = скільки раундів програв).
@rpc("any_peer", "reliable")
func report_bot_win(rounds_lost: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or rounds_lost < 0 or rounds_lost >= WINS_TO_END:
		return
	var now := Time.get_unix_time_from_system()
	if now - float(p["last_bot_unix"]) < BOT_MIN_INTERVAL_SEC:
		return
	var day := Time.get_date_string_from_system(true)
	if str(p["bot_day"]) != day:
		p["bot_day"] = day
		p["bot_today"] = 0
	var amount := calc_reward(BOT_MAX_REWARD, rounds_lost)
	if int(p["bot_today"]) + amount > BOT_DAILY_CAP:
		return
	p["bot_today"] = int(p["bot_today"]) + amount
	p["last_bot_unix"] = now
	_give(peer, amount)


func _give(peer: int, amount: int) -> void:
	var p := _profile_of(peer)
	if p.is_empty() or amount <= 0:
		return   # гравець без профілю (офлайн-бот-матч, Firebase ще не віддав дані) нічого не отримує
	p["coins"] = int(p["coins"]) + amount
	_save_profile(_peer_acc[peer])
	_push(peer, amount)


func _profile_of(peer: int) -> Dictionary:
	return _db.get(_peer_acc.get(peer, ""), {})


func _push(peer: int, reward: int) -> void:
	var p := _profile_of(peer)
	if p.is_empty() or peer == 1 or not multiplayer.get_peers().has(peer):
		return
	sync_profile.rpc_id(peer, int(p["coins"]), reward)


# ====================== СХОВИЩЕ ======================
func _save_profile(key: String) -> void:
	if _use_firebase():
		_fb_request("accounts/" + key, HTTPClient.METHOD_PUT, JSON.stringify(_db[key]),
			func(ok: bool, _text: String):
				if not ok:
					push_error("[economy] Firebase: не вдалося зберегти профіль"))
	else:
		_save_file()


# Завантаження профілю з Firebase. Якщо запит не вдався — профіль НЕ створюємо
# (інакше можна було б затерти справжній баланс нулем).
func _fetch_profile(peer: int, key: String, retries_left: int) -> void:
	_fb_request("accounts/" + key, HTTPClient.METHOD_GET, "",
		func(ok: bool, text: String):
			if not _loading.has(peer):
				return   # гравець уже вийшов
			if not ok:
				if retries_left > 0:
					await get_tree().create_timer(2.0).timeout
					_fetch_profile(peer, key, retries_left - 1)
				else:
					_loading.erase(peer)
					push_error("[economy] Firebase: не вдалося завантажити профіль")
				return
			_loading.erase(peer)
			var profile := _default_profile()
			var data = JSON.parse_string(text)
			if data is Dictionary:
				profile.merge(data, true)
			elif not _db.has(key):
				_db[key] = profile
				_save_profile(key)   # новий акаунт
			_db[key] = profile
			_bind(peer, key))


func _fb_request(path: String, method: int, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, resp: PackedByteArray):
			req.queue_free()
			cb.call(result == HTTPRequest.RESULT_SUCCESS and code == 200, resp.get_string_from_utf8()))
	var url := "%s/%s.json?auth=%s" % [_fb_url, path, _fb_secret]
	var err := req.request(url, ["Content-Type: application/json"], method, body)
	if err != OK:
		req.queue_free()
		cb.call(false, "")


# Локальний файл — лише для тестів без Firebase.
func _load_file() -> void:
	if not FileAccess.file_exists(DB_PATH):
		return
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_db = data


func _save_file() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_db))
