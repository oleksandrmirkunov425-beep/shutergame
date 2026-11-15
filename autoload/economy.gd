extends Node
# autoload/economy.gd — Project Settings -> Autoload, ім'я "Economy".
# Баланс, куплені ножі й вибраний ніж зберігаються і перевіряються ТІЛЬКИ на сервері.
# Клієнт лише показує те, що прислав сервер, і просить дії (купити / вибрати).
# Сховище: Firebase Realtime Database (змінні середовища FIREBASE_URL і FIREBASE_SECRET),
# інакше — локальний файл (для тестів на своєму ПК).

# ---------- Налаштування нагород ----------
const PVP_MAX_REWARD := 30        # перемога 10:0 над гравцем
const BOT_MAX_REWARD := 45        # перемога 10:0 над ботом
const WINS_TO_END := 10           # має збігатися з world.wins_to_end_game
# Матч з ботом іде офлайн, тому сервер не може його перевірити — обмежуємо накрутку:
const BOT_MIN_INTERVAL_SEC := 90  # не частіше ніж раз на 90 с
const BOT_DAILY_CAP := 600        # максимум коїнів за добу з ботів

# ---------- Магазин ножів ----------
# id ножа має збігатися з Loadout.KNIVES і weapon_switch.gd. Ціна 0 = безкоштовний (є в усіх).
const KNIVES := {
	"bolisong":  {"name": "Метелик",   "price": 0},
	"karambit":  {"name": "Керамбіт",  "price": 300},
	"butterfly": {"name": "Butterfly", "price": 500},
}
const KNIFE_ORDER := ["bolisong", "karambit", "butterfly"]
const DEFAULT_KNIFE := "bolisong"

# ---------- Скіни зброї ----------
# id скіна має збігатися з Loadout.AK_SKINS і з weapon_switch.gd (AK_SKIN_TEXTURES).
# "weapon" — для якої зброї скін; "name" — повна назва в магазині; "skin" — коротка назва в меню.
const WEAPON_SKINS := {
	"ak47_samurai": {"weapon": "ak47", "name": "AK-47 | Самурай", "skin": "Самурай", "price": 20},
	"awp_samurai": {"weapon": "awp", "name": "AWP | Самурай", "skin": "Самурай", "price": 20},
}
const SKIN_ORDER := ["ak47_samurai", "awp_samurai"]
const SKIN_WEAPONS := ["ak47", "awp"]

const DB_PATH := "user://economy_db.json"      # сервер, лише якщо Firebase не налаштований
const TOKEN_PATH := "user://account.cfg"       # клієнт: лише "логін" (токен), не гроші
const FETCH_RETRIES := 3

# ---------- Клієнт: те, що показуємо в меню ----------
var view_coins: int = -1          # -1 = ще не отримали від сервера
var view_last_reward: int = 0     # скільки щойно нараховано (меню покаже "+N")
var view_owned: Array = []        # куплені ножі
var view_equipped: String = ""    # вибраний ніж
var view_skins: Dictionary = {}   # зброя -> вибраний скін ("" = стандартний), напр. {"ak47": "ak47_samurai"}
signal profile_updated
signal shop_message(text: String)

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
	return {
		"coins": 0,
		"owned": {DEFAULT_KNIFE: true},
		"equipped": DEFAULT_KNIFE,
		"skins": {},
		"last_bot_unix": 0, "bot_day": "", "bot_today": 0,
	}


# Гарантуємо, що в профілі є безкоштовний ніж і вибраний ніж справді куплений.
static func _normalize(p: Dictionary) -> void:
	if not (p.get("owned") is Dictionary):
		p["owned"] = {}
	p["owned"][DEFAULT_KNIFE] = true
	var eq := str(p.get("equipped", DEFAULT_KNIFE))
	if not KNIVES.has(eq) or not p["owned"].has(eq):
		p["equipped"] = DEFAULT_KNIFE
	# Вибраний скін зброї має бути справді куплений і належати саме цій зброї.
	if not (p.get("skins") is Dictionary):
		p["skins"] = {}
	var skins: Dictionary = p["skins"]
	for weapon in skins.keys():
		var sid := str(skins[weapon])
		if sid != "" and (not WEAPON_SKINS.has(sid) or WEAPON_SKINS[sid]["weapon"] != weapon or not p["owned"].has(sid)):
			skins[weapon] = ""


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
func sync_profile(coins: int, reward: int, owned: Array, equipped: String, skins: Dictionary) -> void:
	if multiplayer.is_server():
		return
	view_coins = coins
	view_owned = owned
	view_equipped = equipped
	view_skins = skins
	Loadout.set_ak_skin(str(skins.get("ak47", "")))   # саме ці скіни гра покаже на зброї у матчі
	Loadout.set_awp_skin(str(skins.get("awp", "")))
	if reward > 0:
		view_last_reward = reward
	if KNIVES.has(equipped):
		Loadout.set_knife(equipped)   # саме цей ніж гра візьме в матчі
	profile_updated.emit()


@rpc("authority", "reliable")
func shop_reply(text: String) -> void:
	if multiplayer.is_server():
		return
	shop_message.emit(text)


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
	_normalize(_db[key])
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


# ====================== СЕРВЕР: магазин ======================
# Ціну, наявність грошей і чи вже куплено — усе перевіряє сервер. Клієнт тільки каже, який ніж хоче.
@rpc("any_peer", "reliable")
func request_buy_knife(knife_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or not KNIVES.has(knife_id):
		return
	if p["owned"].has(knife_id):
		_reply(peer, "Цей ніж у тебе вже є.")
		return
	var price: int = KNIVES[knife_id]["price"]
	if int(p["coins"]) < price:
		_reply(peer, "Не вистачає коїнів: потрібно %d." % price)
		return
	p["coins"] = int(p["coins"]) - price      # спочатку списуємо
	p["owned"][knife_id] = true
	p["equipped"] = knife_id                  # куплений ніж одразу вибираємо
	_save_profile(_peer_acc[peer])
	_push(peer, 0)
	_reply(peer, "Куплено: %s!" % KNIVES[knife_id]["name"])


@rpc("any_peer", "reliable")
func request_equip_knife(knife_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or not KNIVES.has(knife_id) or not p["owned"].has(knife_id):
		return   # вибрати можна тільки куплене
	p["equipped"] = knife_id
	_save_profile(_peer_acc[peer])
	_push(peer, 0)


# Скіни зброї: так само, усе перевіряє сервер (ціна, баланс, чи вже куплено, чи скін для цієї зброї).
@rpc("any_peer", "reliable")
func request_buy_skin(skin_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or not WEAPON_SKINS.has(skin_id):
		return
	if p["owned"].has(skin_id):
		_reply(peer, "Цей скін у тебе вже є.")
		return
	var price: int = WEAPON_SKINS[skin_id]["price"]
	if int(p["coins"]) < price:
		_reply(peer, "Не вистачає коїнів: потрібно %d." % price)
		return
	p["coins"] = int(p["coins"]) - price                      # спочатку списуємо
	p["owned"][skin_id] = true
	p["skins"][WEAPON_SKINS[skin_id]["weapon"]] = skin_id     # куплений скін одразу вибираємо
	_save_profile(_peer_acc[peer])
	_push(peer, 0)
	_reply(peer, "Куплено: %s!" % WEAPON_SKINS[skin_id]["name"])


# skin_id = "" — зняти скін (повернути стандартний вигляд зброї).
@rpc("any_peer", "reliable")
func request_equip_skin(weapon: String, skin_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or not SKIN_WEAPONS.has(weapon):
		return
	if skin_id != "":
		if not WEAPON_SKINS.has(skin_id) or WEAPON_SKINS[skin_id]["weapon"] != weapon or not p["owned"].has(skin_id):
			return   # вибрати можна тільки куплене і лише для своєї зброї
	p["skins"][weapon] = skin_id
	_save_profile(_peer_acc[peer])
	_push(peer, 0)


func _reply(peer: int, text: String) -> void:
	if peer != 1 and multiplayer.get_peers().has(peer):
		shop_reply.rpc_id(peer, text)


func _profile_of(peer: int) -> Dictionary:
	return _db.get(_peer_acc.get(peer, ""), {})


func _push(peer: int, reward: int) -> void:
	var p := _profile_of(peer)
	if p.is_empty() or peer == 1 or not multiplayer.get_peers().has(peer):
		return
	sync_profile.rpc_id(peer, int(p["coins"]), reward, p["owned"].keys(), str(p["equipped"]), p["skins"])


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
			_db[key] = profile
			if not (data is Dictionary):
				_save_profile(key)   # новий акаунт
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
