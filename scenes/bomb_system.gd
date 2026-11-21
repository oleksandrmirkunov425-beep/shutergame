class_name BombSystem
extends Node
# Бомба для режиму 2×2 (створюється з world.gd як дочірній вузол "BombSystem").
#  • На початку раунду одному з T видається бомба (носій). Клавіша 4 — дістати C4 (модель bomb/c4.glb).
#  • Носій з C4 в руках стоїть на бомбсайті (група "bombsite", див. bombsite.gd) і тримає ЛКМ PLANT_TIME секунд — ставить бомбу.
#  • Таймер бомби BOMB_TIME секунд показується на табло між рахунками (червоним).
#  • CT поруч із бомбою тримає E DEFUSE_TIME секунд — розміновує.
#  • Вибух = раунд виграє T, розмінування = раунд виграє CT.
# Сервер усе рахує і перевіряє; клієнти лише малюють підказку, полоску та модель бомби.

const PLANT_TIME := 3.0
const DEFUSE_TIME := 5.0
const BOMB_TIME := 40
const DEFUSE_RADIUS := 2.2    # по горизонталі, м
const HUD_BOMB := 6           # стан табло "бомба тікає" (див. scoreboard.gd)
const KIND_PLANT := 0
const KIND_DEFUSE := 1
const WEAPON_BOMB := 4          # Weapon.BOMB у weapon_switch.gd
const WEAPON_KNIFE := 1
const BOMB_MODEL_PATH := "res://bomb/c4.glb"
const BOMB_GROUND_SCALE := 1.5   # модель ~24 см, на землі робимо трохи більшою

var world                     # world.gd (без типу, щоб бачити його enum State і константи TEAM_*)
var planted: bool = false
var bomb_pos: Vector3 = Vector3.ZERO

# --- сервер ---
var _bomb_timer: Timer
var _bomb_left: int = 0
var _planter: int = -1
var _carrier: int = -1          # хто несе бомбу (сервер вирішує, клієнти знають через RPC)
var _holders: Dictionary = {}   # peer_id -> {"kind": int, "t": float}
var _active: bool = false       # на клієнтах є що прибирати (модель бомби)

# --- клієнт ---
var _live: bool = false         # раунд іде (PLAYING або бомба тікає)
var _left_client: int = BOMB_TIME
var _sites: Array = []
var _sites_cached: bool = false
var _hold_kind: int = -1        # який E-дію зараз виконуємо локально
var _hold_t: float = 0.0
var _sent_kind: int = -1        # що востаннє повідомили серверу
var _done_sent: bool = false    # вже повідомили серверу, що утримання завершено
var _visual: Node3D = null
var _led: MeshInstance3D = null
var _light: OmniLight3D = null
var _defused_visual: bool = false
var _blink_t: float = 0.0
var _layer: CanvasLayer = null
var _prompt: Label = null
var _bar: ProgressBar = null
var _notice: Label = null
var _notice_tween: Tween = null


func setup(w: Node) -> void:
	world = w
	_bomb_timer = Timer.new()
	_bomb_timer.wait_time = 1.0
	add_child(_bomb_timer)
	_bomb_timer.timeout.connect(_on_bomb_tick)
	call_deferred("_get_sites")   # одразу ховаємо зони (на всіх пірах)
	if not multiplayer.is_server():
		_build_ui()


func _exit_tree() -> void:
	Engine.set_meta("bomb_can_use", false)


# ================= Бомбсайти =================

# Бомбсайт — це вузол Bombsite (група "bombsite") АБО будь-який Node3D у цій кімнаті, чия назва починається
# з "bombplant" / "bombsite" (наприклад CSGBox3D "bombplant" у player.tscn).
# Для такого вузла зона = його розмір (size) по X/Z, по висоті беремо із запасом.
func _get_sites() -> Array:
	if _sites_cached:
		return _sites
	_sites_cached = true
	for n in get_tree().get_nodes_in_group("bombsite"):
		if n is Node3D and world.room.is_ancestor_of(n):
			_sites.append(n)
			(n as Node3D).visible = false   # зона — лише розмітка, у грі її не видно нікому
	for n in world.room.find_children("*", "Node3D", true, false):
		if _sites.has(n):
			continue
		var nm := String(n.name).to_lower()
		if nm.begins_with("bombplant") or nm.begins_with("bombsite"):
			_sites.append(n)
			# Це лише розмітка зони: у грі її не показуємо і колізії в неї немає.
			(n as Node3D).visible = false
			if "use_collision" in n:
				n.set("use_collision", false)
	if _sites.is_empty():
		push_warning("bomb_system: на карті немає бомбсайта (вузол Bombsite або Node3D з назвою bombplant) — бомбу можна ставити будь-де.")
	else:
		print("[bomb] бомбсайтів у кімнаті: %d" % _sites.size())
	return _sites


# Діагностика для повідомлення про відмову: найближчі зони та де в них стоїть гравець.
func _describe_sites(pos: Vector3) -> String:
	var rows: Array = []
	for st in _get_sites():
		var c: Vector3 = (st as Node3D).global_position
		var sz: String = str((st.get("size") as Vector3).snapped(Vector3.ONE * 0.1)) if "size" in st else "-"
		rows.append([Vector2(pos.x - c.x, pos.z - c.z).length(), "%s центр=%s розмір=%s" % [st.name, str(c.snapped(Vector3.ONE * 0.1)), sz]])
	rows.sort_custom(func(x, y): return x[0] < y[0])
	var out := "зон: %d, ваша позиція %s" % [rows.size(), str(pos.snapped(Vector3.ONE * 0.1))]
	for i in mini(rows.size(), 3):
		out += " | " + str(rows[i][1])
	return out


func _site_contains(s: Node3D, pos: Vector3) -> bool:
	if s.has_method("contains_point"):
		return s.contains_point(pos)
	if not ("size" in s):
		return false
	var sz: Vector3 = s.get("size")
	var l: Vector3 = s.global_transform.affine_inverse() * pos
	# По висоті — із запасом: початок гравця ~1 м над підлогою, а зона може бути тонкою плитою.
	return absf(l.x) <= sz.x * 0.5 and absf(l.z) <= sz.z * 0.5 and absf(l.y) <= sz.y * 0.5 + 3.0


# "" — поза зоною; інакше назва бомбсайта ("?" — сайтів на карті немає, дозволено будь-де).
func _site_at(pos: Vector3) -> String:
	var sites := _get_sites()
	if sites.is_empty():
		return "?"
	for s in sites:
		if _site_contains(s, pos):
			return str(s.get("site_name")) if "site_name" in s else String(s.name)
	return ""


func _near_bomb(pos: Vector3) -> bool:
	var d := Vector2(pos.x - bomb_pos.x, pos.z - bomb_pos.z).length()
	return d <= DEFUSE_RADIUS and absf(pos.y - bomb_pos.y) <= 3.0


# ================= Клієнт: ввід, підказки =================

func _local_player() -> Node:
	return world.players_node.get_node_or_null(str(multiplayer.get_unique_id()))


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	_client_process(delta)


func _client_process(delta: float) -> void:
	_update_visual(delta)
	var me := _local_player()
	var cam: Node = me.get_node_or_null("head/Camera3D") if me != null else null
	var my_id := multiplayer.get_unique_id()
	var weapon := int(cam.get("current_weapon")) if cam != null else -1

	# Носій може діставати C4 клавішею 4 (дозвіл читає weapon_switch.gd).
	if cam != null:
		cam.set("bomb_carrier", _carrier == my_id and not planted)
		# Бомби більше немає (поставлена / ми не носій / ми мертві) — прибираємо з рук.
		if weapon == WEAPON_BOMB and (_carrier != my_id or planted or bool(me.get("is_dead"))):
			if not bool(cam.get("is_attacking")):
				cam.call("switch_weapon", WEAPON_KNIFE)

	var kind := -1
	var hint := ""
	if me != null and _live and not bool(me.get("is_dead")) and not bool(me.get("frozen")) and not bool(me.get("paused")):
		var team := int(me.get("team"))
		var pos: Vector3 = (me as Node3D).global_position
		if team == world.TEAM_T and not planted and _carrier == my_id and weapon == WEAPON_BOMB:
			if _site_at(pos) != "":
				kind = KIND_PLANT
			else:
				hint = "Бомбу можна поставити тільки на бомбсайті"
		elif team == world.TEAM_CT and planted and not _defused_visual and _near_bomb(pos):
			kind = KIND_DEFUSE

	# Поки E "зайнято" розмінуванням, меню зброї на E не відкривається (див. weapon_switch.gd).
	Engine.set_meta("bomb_can_use", kind == KIND_DEFUSE)

	var holding := false
	if kind == KIND_PLANT:
		holding = Input.is_action_pressed("shoot")
	elif kind == KIND_DEFUSE:
		holding = Input.is_key_pressed(KEY_E)
	if holding:
		if kind != _hold_kind:
			_hold_kind = kind
			_hold_t = 0.0
		_hold_t += delta
		if _sent_kind != kind:
			_sent_kind = kind
			_hold.rpc_id(1, kind, true)
		var total := PLANT_TIME if kind == KIND_PLANT else DEFUSE_TIME
		if _hold_t >= total and not _done_sent:
			_done_sent = true
			_hold_done.rpc_id(1, kind, (me as Node3D).global_position)
	else:
		_hold_kind = -1
		_hold_t = 0.0
		_done_sent = false
		if _sent_kind != -1:
			_sent_kind = -1
			_hold.rpc_id(1, 0, false)

	_update_prompt(kind, holding, hint)


func _update_prompt(kind: int, holding: bool, hint: String = "") -> void:
	if _prompt == null:
		return
	if kind == -1:
		_prompt.visible = hint != ""
		_prompt.text = hint
		_bar.visible = false
		return
	var total := PLANT_TIME if kind == KIND_PLANT else DEFUSE_TIME
	_prompt.text = ("Тримай [ЛКМ] — ПОСТАВИТИ БОМБУ" if kind == KIND_PLANT else "Тримай [E] — РОЗМІНУВАТИ")
	_prompt.visible = true
	_bar.visible = holding
	_bar.max_value = total
	_bar.value = minf(_hold_t, total)


# ================= Сервер: перевірка і відлік =================

@rpc("any_peer", "reliable")
func _hold(kind: int, active: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not world.room_peers.has(id):
		return
	if active and (kind == KIND_PLANT or kind == KIND_DEFUSE):
		_holders[id] = {"kind": kind, "start": Time.get_ticks_msec()}
	else:
		_holders.erase(id)


# Клієнт відтримав E / ЛКМ потрібний час. Час перевіряємо приблизно, решту — повністю.
# Позицію беремо від клієнта (позиція гравця на сервері може відставати від справжньої).
@rpc("any_peer", "reliable")
func _hold_done(kind: int, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not world.room_peers.has(id):
		return
	var h = _holders.get(id)
	var total := PLANT_TIME if kind == KIND_PLANT else DEFUSE_TIME
	if h == null or int(h["kind"]) != kind:
		_deny(id, "сервер не бачить початку дії")
		return
	if float(Time.get_ticks_msec() - int(h["start"])) / 1000.0 < total * 0.7:
		_deny(id, "занадто швидко")
		return
	var why := _check(id, kind, pos)
	if why != "":
		_deny(id, why)
		return
	_holders.erase(id)
	if kind == KIND_PLANT:
		_plant(id, pos)
	else:
		_defuse(id)


func _deny(id: int, why: String) -> void:
	print("[bomb] відмова гравцю %d: %s" % [id, why])
	_on_hold_fail.rpc_id(id, why)


# "" — усе гаразд, інакше причина відмови.
func _check(id: int, kind: int, pos: Vector3) -> String:
	if world.state != world.State.PLAYING:
		return "раунд не триває"
	if not world.alive_players.get(id, false):
		return "гравець мертвий"
	var team := int(world.teams.get(id, -1))
	if kind == KIND_PLANT:
		if team != world.TEAM_T:
			return "не команда T"
		if id != _carrier:
			return "бомба не в цього гравця"
		if planted:
			return "бомба вже поставлена"
		if _site_at(pos) == "":
			return "поза бомбсайтом. " + _describe_sites(pos)
		return ""
	if team != world.TEAM_CT:
		return "не команда CT"
	if not planted:
		return "бомби немає"
	if not _near_bomb(pos):
		return "далеко від бомби"
	return ""


func _plant(id: int, p: Vector3) -> void:
	# Ставимо бомбу на підлогу під гравцем.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	# Промінь не повинен влучити в тіло/хітбокси гравців — інакше бомба зависає в повітрі на висоті тіла.
	var exclude: Array[RID] = []
	for pl in world.players_node.get_children():
		for co in pl.find_children("*", "CollisionObject3D", true, false):
			exclude.append((co as CollisionObject3D).get_rid())
		if pl is CollisionObject3D:
			exclude.append((pl as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 6.0, 0xFFFFFFFF)
	q.exclude = exclude
	var r := space.intersect_ray(q)
	# Запасний варіант: початок гравця лежить на 1.2 м над підлогою (див. спавни у world.gd).
	bomb_pos = (r["position"] as Vector3) if not r.is_empty() else (p + Vector3.DOWN * 1.2)
	planted = true
	_planter = id
	_active = true
	_set_carrier(-1)
	_holders.clear()
	_bomb_left = BOMB_TIME
	var site := _site_at(p)
	world.on_bomb_planted()
	_broadcast_planted(bomb_pos, site, id)
	world._hud(HUD_BOMB, _bomb_left)
	_bomb_timer.start()


func _defuse(id: int) -> void:
	_bomb_timer.stop()
	_holders.clear()
	_broadcast_defused()
	world.on_bomb_result(world.TEAM_CT, id)


func _on_bomb_tick() -> void:
	if not planted or world.state != world.State.PLAYING:
		_bomb_timer.stop()
		return
	_bomb_left -= 1
	if _bomb_left > 0:
		world._hud(HUD_BOMB, _bomb_left)
		return
	_bomb_timer.stop()
	_holders.clear()
	_broadcast_exploded(bomb_pos)
	world.on_bomb_result(world.TEAM_T, _planter)


# ---- Носій бомби ----
# Початок раунду (після спавну): випадковий живий T отримує бомбу.
func assign_carrier() -> void:
	var cands: Array = []
	for id in world.room_peers:
		if int(world.teams.get(id, -1)) == world.TEAM_T and world.alive_players.get(id, false):
			cands.append(id)
	_set_carrier(cands.pick_random() if not cands.is_empty() else -1)


# Носій загинув — бомбу підхоплює живий напарник (якщо є).
func on_player_died(id: int) -> void:
	if id != _carrier or planted:
		return
	var cands: Array = []
	for pid in world.room_peers:
		if pid != id and int(world.teams.get(pid, -1)) == world.TEAM_T and world.alive_players.get(pid, false):
			cands.append(pid)
	_set_carrier(cands.pick_random() if not cands.is_empty() else -1)


func _set_carrier(id: int) -> void:
	_carrier = id
	_broadcast_carrier()


func _broadcast_carrier() -> void:
	for pid in _peers():
		_on_carrier.rpc_id(pid, _carrier)


@rpc("call_local", "reliable")
func _on_hold_fail(why: String) -> void:
	_show_notice("Сервер: " + why, Color(1.0, 0.4, 0.3))


@rpc("call_local", "reliable")
func _on_carrier(id: int) -> void:
	var was := _carrier
	_carrier = id
	if id == multiplayer.get_unique_id() and was != id:
		_show_notice("У ВАС БОМБА — натисніть [4]", Color(1.0, 0.85, 0.3))


# Раунд закінчився (смерть команди / кінець гри): бомба більше не тікає, модель лишається до нового раунду.
func halt() -> void:
	_bomb_timer.stop()
	_holders.clear()


# Новий раунд / кінець матчу: прибираємо бомбу.
func reset() -> void:
	_bomb_timer.stop()
	_holders.clear()
	planted = false
	_planter = -1
	_carrier = -1
	if _active:
		_active = false
		_broadcast_clear()
	_broadcast_carrier()


func _peers() -> Array:
	return world.room_peers


func _broadcast_planted(pos: Vector3, site: String, planter: int) -> void:
	for id in _peers():
		_on_planted.rpc_id(id, pos, site, planter)


func _broadcast_defused() -> void:
	for id in _peers():
		_on_defused.rpc_id(id)


func _broadcast_exploded(pos: Vector3) -> void:
	for id in _peers():
		_on_exploded.rpc_id(id, pos)


func _broadcast_clear() -> void:
	for id in _peers():
		_on_clear.rpc_id(id)


# ================= Клієнт: події від сервера =================

# Режим табло: сервер каже, іде раунд чи ні (див. world.gd::_sync_hud_state).
func on_hud_state(state: int, value: int) -> void:
	_live = (state == world.State.PLAYING or state == HUD_BOMB)
	if state == HUD_BOMB:
		_left_client = value
	if state == world.State.FREEZE or state == world.State.COUNTDOWN or state == world.State.WAITING:
		_hold_t = 0.0


@rpc("call_local", "reliable")
func _on_planted(pos: Vector3, site: String, _planter_id: int) -> void:
	planted = true
	bomb_pos = pos
	_defused_visual = false
	_left_client = BOMB_TIME
	_make_visual(pos)
	var where := "" if site == "?" or site == "" else " (%s)" % site
	_show_notice("БОМБУ ВСТАНОВЛЕНО" + where, Color(1.0, 0.35, 0.25))


@rpc("call_local", "reliable")
func _on_defused() -> void:
	_defused_visual = true
	if _led:
		_led.visible = true
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(0.2, 1.0, 0.3)
		gm.emission_enabled = true
		gm.emission = Color(0.2, 1.0, 0.3)
		_led.material_override = gm
	if _light:
		_light.light_color = Color(0.2, 1.0, 0.3)
		_light.visible = true
	_show_notice("БОМБУ РОЗМІНОВАНО", Color(0.4, 0.8, 1.0))


@rpc("call_local", "reliable")
func _on_exploded(pos: Vector3) -> void:
	_clear_visual()
	_explosion_fx(pos)
	_show_notice("БОМБА ВИБУХНУЛА", Color(1.0, 0.6, 0.15))


@rpc("call_local", "reliable")
func _on_clear() -> void:
	planted = false
	_defused_visual = false
	_clear_visual()


# ================= Візуал =================

func _make_visual(pos: Vector3) -> void:
	_clear_visual()
	_visual = Node3D.new()
	world.add_child(_visual)
	_visual.global_position = pos

	var model: Node3D = null
	if ResourceLoader.exists(BOMB_MODEL_PATH):
		var packed := load(BOMB_MODEL_PATH) as PackedScene
		if packed:
			model = packed.instantiate() as Node3D
	if model != null:
		model.scale = Vector3.ONE * BOMB_GROUND_SCALE
		_visual.add_child(model)
		_led = model.find_child("c4_led", true, false) as MeshInstance3D
	else:
		# Запасний варіант, якщо моделі немає: проста коробка.
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.18, 0.30)
		body.mesh = box
		body.position.y = 0.09
		_visual.add_child(body)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.omni_range = 4.0
	_light.light_energy = 1.6
	_light.position = Vector3(0.1, 0.25, 0.0)
	_visual.add_child(_light)


func _clear_visual() -> void:
	if is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null
	_led = null
	_light = null


# Червоний діод блимає дедалі частіше, чим менше лишилось часу.
func _update_visual(delta: float) -> void:
	if _visual == null or _defused_visual:
		return
	_blink_t += delta
	var k := clampf(float(_left_client) / float(BOMB_TIME), 0.0, 1.0)
	var period := lerpf(0.15, 1.0, k)
	var on := fmod(_blink_t, period) < period * 0.4
	if _led:
		_led.visible = on
	if _light:
		_light.visible = on


func _explosion_fx(pos: Vector3) -> void:
	var fx := Node3D.new()
	world.add_child(fx)
	fx.global_position = pos + Vector3.UP * 0.3

	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	ball.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.05)
	ball.material_override = m
	ball.scale = Vector3.ONE * 0.3
	fx.add_child(ball)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.omni_range = 18.0
	light.light_energy = 8.0
	fx.add_child(light)

	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * 7.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.tween_property(light, "light_energy", 0.0, 0.8)
	tw.chain().tween_callback(fx.queue_free)


# ================= UI (тільки клієнт) =================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 18
	add_child(_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -170.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 28)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.visible = false
	box.add_child(_prompt)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 16)
	_bar.show_percentage = false
	_bar.visible = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.85, 0.3)
	_bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.85)
	_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_bar)

	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.offset_top = 100.0
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 36)
	_notice.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice.add_theme_constant_override("outline_size", 10)
	_notice.modulate.a = 0.0
	root.add_child(_notice)


func _show_notice(text: String, color: Color) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	_notice.modulate.a = 1.0
	if _notice_tween:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(2.5)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.5)
