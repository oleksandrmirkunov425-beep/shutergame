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
	"m9":        {"name": "M9 Bayonet", "price": 1000},
}
const KNIFE_ORDER := ["bolisong", "karambit", "butterfly", "m9"]
const DEFAULT_KNIFE := "bolisong"

# ---------- Скіни зброї ----------
# id скіна має збігатися з Loadout.AK_SKINS і з weapon_switch.gd (AK_SKIN_TEXTURES).
# "weapon" — для якої зброї скін; "name" — повна назва в магазині; "skin" — коротка назва в меню.
const WEAPON_SKINS := {
	"ak47_samurai": {"weapon": "ak47", "name": "AK-47 | Самурай", "skin": "Самурай", "price": 20},
	"awp_samurai": {"weapon": "awp", "name": "AWP | Самурай", "skin": "Самурай", "price": 20},
	"ak47_cyber_circuit": {"weapon": "ak47", "name": "AK-47 | Кіберсхема", "skin": "Кіберсхема", "price": 20},
	"ak47_arctic_tactical": {"weapon": "ak47", "name": "AK-47 | Арктика", "skin": "Арктика", "price": 20},
	"ak47_crimson_filigree": {"weapon": "ak47", "name": "AK-47 | Багряна філігрань", "skin": "Багряна філігрань", "price": 20},
	# Скіни, що випадають лише з кейсів (case_only): купити за коїни не можна, тільки виграти.
	"ak47_arctic_frost": {"weapon": "ak47", "name": "AK-47 | Арктичний мороз", "skin": "Арктичний мороз", "price": 0, "rarity": "blue", "case_only": true},
	"ak47_desert_warfare": {"weapon": "ak47", "name": "AK-47 | Пустельна війна", "skin": "Пустельна війна", "price": 0, "rarity": "blue", "case_only": true},
	"ak47_hazard_strike": {"weapon": "ak47", "name": "AK-47 | Небезпечний удар", "skin": "Небезпечний удар", "price": 0, "rarity": "blue", "case_only": true},
	"ak47_ocean_wave": {"weapon": "ak47", "name": "AK-47 | Океанська хвиля", "skin": "Океанська хвиля", "price": 0, "rarity": "blue", "case_only": true},
	"ak47_neon_circuit": {"weapon": "ak47", "name": "AK-47 | Неонова схема", "skin": "Неонова схема", "price": 0, "rarity": "purple", "case_only": true},
	"ak47_titanium_ghost": {"weapon": "ak47", "name": "AK-47 | Титановий привид", "skin": "Титановий привид", "price": 0, "rarity": "purple", "case_only": true},
	"ak47_royal_filigree": {"weapon": "ak47", "name": "AK-47 | Королівська філігрань", "skin": "Королівська філігрань", "price": 0, "rarity": "pink", "case_only": true},
	"ak47_void_lightning": {"weapon": "ak47", "name": "AK-47 | Блискавка порожнечі", "skin": "Блискавка порожнечі", "price": 0, "rarity": "pink", "case_only": true},
	"ak47_inferno": {"weapon": "ak47", "name": "AK-47 | Інферно", "skin": "Інферно", "price": 0, "rarity": "red", "case_only": true},
	"ak47_emerald_dragon": {"weapon": "ak47", "name": "AK-47 | Смарагдовий дракон", "skin": "Смарагдовий дракон", "price": 0, "rarity": "red", "case_only": true},
	"awp_amber_carbon": {"weapon": "awp", "name": "AWP | Бурштиновий карбон", "skin": "Бурштиновий карбон", "price": 0, "rarity": "blue", "case_only": true},
	"awp_desert_tactical": {"weapon": "awp", "name": "AWP | Пустельна тактика", "skin": "Пустельна тактика", "price": 0, "rarity": "blue", "case_only": true},
	"awp_emerald_silver": {"weapon": "awp", "name": "AWP | Смарагдове срібло", "skin": "Смарагдове срібло", "price": 0, "rarity": "blue", "case_only": true},
	"awp_frost_splinter": {"weapon": "awp", "name": "AWP | Крижаний уламок", "skin": "Крижаний уламок", "price": 0, "rarity": "purple", "case_only": true},
	"awp_cobalt_chrome": {"weapon": "awp", "name": "AWP | Кобальтовий хром", "skin": "Кобальтовий хром", "price": 0, "rarity": "purple", "case_only": true},
	"awp_obsidian_violet": {"weapon": "awp", "name": "AWP | Обсидіан-фіолет", "skin": "Обсидіан-фіолет", "price": 0, "rarity": "pink", "case_only": true},
	"awp_blood_scales": {"weapon": "awp", "name": "AWP | Кривава луска", "skin": "Кривава луска", "price": 0, "rarity": "red", "case_only": true},
}
const SKIN_ORDER := ["ak47_samurai", "ak47_cyber_circuit", "ak47_arctic_tactical", "ak47_crimson_filigree", "awp_samurai",
		"ak47_arctic_frost", "ak47_desert_warfare", "ak47_hazard_strike", "ak47_ocean_wave", "ak47_neon_circuit", "ak47_titanium_ghost", "ak47_royal_filigree", "ak47_void_lightning", "ak47_inferno", "ak47_emerald_dragon",
		"awp_amber_carbon", "awp_desert_tactical", "awp_emerald_silver", "awp_frost_splinter", "awp_cobalt_chrome", "awp_obsidian_violet", "awp_blood_scales"]
const SKIN_WEAPONS := ["ak47", "awp"]

# ---------- Кейси (як у CS2) ----------
# Рулетку крутить клієнт, а ЩО випаде — вирішує тільки сервер (request_open_case). Скіни case_only купити не можна.
# "model" — 3D-модель кейса (можна свою для кожного кейса). "items" — id скінів/ножів, що можуть випасти.
const CASES := {
	"emerald_dragon": {
		"name": "Emerald Dragon Case", "price": 60, "model": "res://case/cs2_case_emerald_dragon.glb",
		"items": [
			"ak47_arctic_frost", "ak47_desert_warfare", "ak47_hazard_strike", "ak47_ocean_wave",
			"ak47_neon_circuit", "ak47_titanium_ghost", "ak47_royal_filigree", "ak47_void_lightning",
			"ak47_inferno", "ak47_emerald_dragon", "karambit", "butterfly", "m9"],
	},
	"sniper": {
		"name": "Sniper Case", "price": 60, "model": "res://case/cs2_case_emerald_dragon.glb",
		"items": [
			"awp_amber_carbon", "awp_desert_tactical", "awp_emerald_silver", "awp_frost_splinter",
			"awp_cobalt_chrome", "awp_obsidian_violet", "awp_blood_scales", "karambit", "butterfly", "m9"],
	},
}
const CASE_ORDER := ["emerald_dragon", "sniper"]

# Шанси за рідкістю (у %, нормалізуються серед тих рідкостей, що є в кейсі). Усередині рідкості — рівно.
const RARITY_ORDER := ["blue", "purple", "pink", "red", "gold"]
const RARITY_WEIGHTS := {"blue": 68.0, "purple": 20.0, "pink": 8.0, "red": 3.0, "gold": 1.0}
const RARITY_NAMES := {"blue": "АРМІЙСЬКИЙ", "purple": "ОБМЕЖЕНИЙ", "pink": "ЗАСЕКРЕЧЕНИЙ", "red": "ТАЄМНИЙ", "gold": "РІДКІСНИЙ (НІЖ)"}
# Якщо випав предмет, який уже є — повертаємо коїни (ніж: половина ціни).
const DUPLICATE_REFUND := {"blue": 10, "purple": 20, "pink": 40, "red": 90}

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
signal case_opened(case_id: String, item_id: String, refund: int)   # сервер відповів: що випало з кейса

# ---------- Сервер ----------
var _peer_acc: Dictionary = {}    # peer_id -> ключ акаунта (лише ПІСЛЯ завантаження профілю)
var _db: Dictionary = {}          # ключ акаунта -> профіль (кеш у пам'яті)
var _loading: Dictionary = {}     # peer_id -> true, поки профіль вантажиться з Firebase
var _fb_url: String = ""
var _fb_secret: String = ""
var _rng := RandomNumberGenerator.new()   # шанси кейсів (тільки сервер)


func _ready() -> void:
	if not _is_server_build():
		return
	_rng.randomize()
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


# ====================== КЕЙСИ: спільні функції (клієнт і сервер) ======================
# Єдиний опис предмета кейса (скін або ніж): назва, рідкість, що показувати в превʼю.
static func item_info(id: String) -> Dictionary:
	if KNIVES.has(id):
		var k: Dictionary = KNIVES[id]
		return {"id": id, "kind": "knife", "name": str(k["name"]), "weapon": "knife", "model": id, "skin": "",
			"rarity": "gold", "price": int(k["price"])}
	if WEAPON_SKINS.has(id):
		var sk: Dictionary = WEAPON_SKINS[id]
		return {"id": id, "kind": "skin", "name": str(sk["name"]), "weapon": str(sk["weapon"]), "model": str(sk["weapon"]),
			"skin": id, "rarity": str(sk.get("rarity", "purple")), "price": int(sk["price"])}
	return {}


# Випадковий предмет кейса з урахуванням шансів. Сервер викликає з серверним rng; клієнт — лише для «масовки» в рулетці.
static func roll_case(case_id: String, rng: RandomNumberGenerator) -> String:
	if not CASES.has(case_id):
		return ""
	var by_rarity: Dictionary = {}
	for id in CASES[case_id]["items"]:
		var r := str(item_info(str(id)).get("rarity", ""))
		if r == "":
			continue
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(str(id))
	var total := 0.0
	for r in by_rarity:
		total += float(RARITY_WEIGHTS.get(r, 0.0))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var pick := ""
	for r in RARITY_ORDER:
		if not by_rarity.has(r):
			continue
		roll -= float(RARITY_WEIGHTS.get(r, 0.0))
		pick = r
		if roll < 0.0:
			break
	var pool: Array = by_rarity[pick]
	return str(pool[rng.randi() % pool.size()])


# Шанс (у %) кожної рідкості в цьому кейсі — для показу гравцю.
static func case_odds(case_id: String) -> Dictionary:
	var present: Dictionary = {}
	for id in CASES[case_id]["items"]:
		present[str(item_info(str(id)).get("rarity", ""))] = true
	var total := 0.0
	for r in present:
		total += float(RARITY_WEIGHTS.get(r, 0.0))
	var out: Dictionary = {}
	for r in RARITY_ORDER:
		if present.has(r) and total > 0.0:
			out[r] = float(RARITY_WEIGHTS[r]) / total * 100.0
	return out


static func duplicate_refund(id: String) -> int:
	var info := item_info(id)
	if info.is_empty():
		return 0
	if str(info["kind"]) == "knife":
		return maxi(1, roundi(float(info["price"]) / 2.0))
	return int(DUPLICATE_REFUND.get(str(info["rarity"]), 10))

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
func case_result(case_id: String, item_id: String, refund: int) -> void:
	if multiplayer.is_server():
		return
	case_opened.emit(case_id, item_id, refund)


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
	if bool(WEAPON_SKINS[skin_id].get("case_only", false)):
		_reply(peer, "Цей скін випадає лише з кейсів.")   # інакше ціна 0 = безкоштовно для всіх
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


# Відкриття кейса: сервер перевіряє баланс, списує ціну, САМ вибирає предмет і видає його.
# Клієнт отримує лише результат (case_result) і крутить рулетку, яка зупиняється на цьому предметі.
@rpc("any_peer", "reliable")
func request_open_case(case_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := _profile_of(peer)
	if p.is_empty() or not CASES.has(case_id):
		return
	var price: int = CASES[case_id]["price"]
	if int(p["coins"]) < price:
		_reply(peer, "Не вистачає коїнів: потрібно %d." % price)
		return
	var item := roll_case(case_id, _rng)
	if item == "":
		return
	p["coins"] = int(p["coins"]) - price      # спочатку списуємо
	var refund := 0
	if p["owned"].has(item):
		refund = duplicate_refund(item)       # дублікат -> частина вартості назад
		p["coins"] = int(p["coins"]) + refund
	else:
		p["owned"][item] = true               # не вибираємо автоматично: гравець сам обере в результаті
	_save_profile(_peer_acc[peer])
	_push(peer, 0)
	if peer != 1 and multiplayer.get_peers().has(peer):
		case_result.rpc_id(peer, case_id, item, refund)


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
