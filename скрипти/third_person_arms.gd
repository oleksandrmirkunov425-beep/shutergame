extends Node3D
## Руки МОДЕЛІ гравця (player_model/Arm_L, Arm_R) + зброя в них — те, що бачать ІНШІ гравці.
## Власник бачить свої FPS-руки (head/arms), цей вузол у нього вимкнений.
##
## Куди: character.tscn -> вузол `player` -> додати дочірній Node3D з іменем TPArms
## і причепити цей скрипт (трансформ не важливий).
##
## Як працює: руки не анімуються «кістками» (у player_split.glb скелета немає), а
## повертаються так, щоб дивитись у задану точку відносно погляду гравця (head).
## Анімації (діставання, постріл, перезарядка, осмотр, удар) — це короткі Tween-и
## на змінних off_r / off_l / off_pos / off_rot, які додаються до базової пози зброї.
##
## AK-47 та AWP: їхні FPS-моделі й анімації чужим показує weapon_switch.gd
## weapon_switch.gd (ті самі вузли, що бачить власник), але FPS-руки там сховані. Замість них
## РУКИ МОДЕЛІ (Arm_L / Arm_R — з текстурою своєї команди, прикріплені до плечей) тягнуться до
## тих місць, де в цей момент знаходяться FPS-кисті (head/arms/hand_L, hand_R). Тож руки йдуть
## від тіла, а не висять окремо, і при цьому повторюють анімації AWP.

# Номери = enum Weapon у weapon_switch.gd: AK47=0, KNIFE=1, SNIPER=2, M4=3
const AK47_ID := 0     # АК — FPS-модель та її draw/reload/inspect анімації
const SNIPER_ID := 2   # AWP — FPS-модель та її draw/reload/view анімації
const WEAPON_SCENES := {
	0: preload("res://weapons/AK47.fbx"),
	3: preload("res://m4/m4a1_detailed_v3.glb"),
}
const KNIFE_MESH := preload("res://karanbit.obj")
const BOLISONG_SCENE: PackedScene = preload("res://bolisong_knife/ImageToStl.com_titan_balisong_v4.fbx")
const BUTTERFLY_SCENE: PackedScene = preload("res://butterfly_knife/titan_butterfly.glb")
const M9_SCENE: PackedScene = preload("res://m9_bayonet_knife/m9_bayonet_lowpoly_v4.glb")

# Базові пози. Усе — відносно погляду гравця (вузол head).
#  r / l   : куди дивиться права / ліва рука, Vector2(нахил, поворот) у градусах.
#            нахил: + вгору, − вниз.  поворот: + вліво, − вправо.
#  pos/rot : положення (м) і поворот (градуси) моделі зброї відносно правої кисті.
#  scale   : масштаб моделі зброї.
# ЦІ ЧИСЛА — СТАРТОВІ, їх треба підігнати очима (див. пояснення в чаті).
const POSES := {
	0: {"r": Vector2(-12, 14), "l": Vector2(-6, -20), "pos": Vector3(0, 0, -0.15), "rot": Vector3(0, 0, 0),   "scale": 0.15},
	1: {"r": Vector2(-35, 8),  "l": Vector2(-80, 0),  "pos": Vector3(0, 0, -0.05), "rot": Vector3(0, -90, 0), "scale": 1.0},
	3: {"r": Vector2(-12, 14), "l": Vector2(-6, -20), "pos": Vector3(0, 0, -0.15), "rot": Vector3(0, 90, 0),  "scale": 1.3},
}

# Тимчасові зсуви анімацій (їх крутять Tween-и нижче).
var off_r := Vector2.ZERO
var off_l := Vector2.ZERO
var off_pos := Vector3.ZERO
var off_rot := Vector3.ZERO   # градуси

var _player: CharacterBody3D
var _head: Node3D
var _model: Node3D
var _arm_r: Node3D          # рука з ПРАВОГО боку гравця (тримає зброю)
var _arm_l: Node3D
var _arm_len := 0.55
var _holder: Node3D         # «кисть»: сюди чіпляється зброя
var _weapons := {}
var _knife_skin := "karambit"
var _knife_variant_nodes: Dictionary = {}
var _knife_variant_anim: Dictionary = {}
var _w := 1
var _tween: Tween
var _fps_rig_mode := false      # AK/AWP у руках — руки моделі тягнуться до кистей FPS-ригу
var _fps_hand_r: Node3D
var _fps_hand_l: Node3D
const FPS_ARM_STRETCH_MIN := 0.8   # наскільки рука може вкоротитись/подовжитись, щоб дістати до гвинтівки
const FPS_ARM_STRETCH_MAX := 1.35
# Запасні кути рук (як у POSES), якщо в head/arms не знайдено hand_L / hand_R.
const FPS_FALLBACK_R := Vector2(-22, 10)
const FPS_FALLBACK_L := Vector2(-14, -14)


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	# Свого гравця ми не бачимо збоку — для власника все вимкнено.
	if _player == null or _player.is_multiplayer_authority():
		set_process(false)
		return
	_head = _player.get_node("head")
	_model = _player.get_node_or_null("player_model")
	if _model == null:
		set_process(false)
		return

	# Зброя живе НЕ всередині player_model: player.gd фарбує всі MeshInstance3D моделі
	# скіном і рахує по них хітбокси, зброя їх би зіпсувала.
	_holder = Node3D.new()
	_holder.top_level = true
	add_child(_holder)

	for id in WEAPON_SCENES:
		var n: Node3D = (WEAPON_SCENES[id] as PackedScene).instantiate()
		n.visible = false
		_holder.add_child(n)
		_weapons[id] = n
	var knife := MeshInstance3D.new()
	knife.mesh = KNIFE_MESH
	knife.visible = false
	_holder.add_child(knife)
	_weapons[1] = knife

	# Третя особа: моделі альтернативних ножів теж створюються окремо,
	# щоб інші гравці бачили той самий тип ножа, що й власник.
	_add_knife_variant("bolisong", BOLISONG_SCENE)
	_add_knife_variant("butterfly", BUTTERFLY_SCENE)
	_add_knife_variant("m9", M9_SCENE)

	on_switch(1)   # поки невідомо, що в руках — ніж


func _process(_delta: float) -> void:
	var alive: bool = _model.visible and _player.get("is_dead") != true
	var resolved := _resolve_arms()
	if resolved:
		_set_fps_rig_mode(alive and (_w == SNIPER_ID or _w == AK47_ID))
	if not alive or not resolved or _fps_rig_mode:
		_holder.visible = false
		if alive and resolved and _fps_rig_mode:
			_pose_awp_arms()
		return
	_holder.visible = true

	var pose: Dictionary = POSES[_w]
	var hb := _head.global_basis.orthonormalized()
	var r: Vector2 = pose["r"] + off_r
	var l: Vector2 = pose["l"] + off_l
	_aim_arm(_arm_r, hb, r)
	_aim_arm(_arm_l, hb, l)

	# Кисть = кінець правої руки. Зброя дивиться туди ж, куди погляд (+ нахил руки).
	var hand := _arm_r.global_position + _dir(hb, r) * _arm_len
	var wb := hb * Basis.from_euler(Vector3(deg_to_rad(off_r.x), deg_to_rad(off_r.y), 0.0))
	_holder.global_transform = Transform3D(wb, hand)

	var rot: Vector3 = (pose["rot"] + off_rot) * (PI / 180.0)
	var weapon_basis := Basis.from_euler(rot) * Basis.from_scale(Vector3.ONE * float(pose["scale"]))
	var w: Node3D = _weapons.get(_w)
	if w:
		w.position = pose["pos"] + off_pos
		w.basis = weapon_basis
	for skin in _knife_variant_nodes:
		var variant: Node3D = _knife_variant_nodes[skin]
		variant.position = pose["pos"] + off_pos
		variant.basis = weapon_basis


# ---------------------------------------------------------------- руки
# AWP/AK: руки моделі лишаються видимими й тягнуться до кистей FPS-ригу (див. _pose_awp_arms).
func _set_fps_rig_mode(on: bool) -> void:
	if on == _fps_rig_mode:
		return
	_fps_rig_mode = on


# Руки моделі беруть позицію з кистей FPS-ригу: плече лишається на місці, рука повертається
# й трохи розтягується так, щоб кінець руки опинився біля гвинтівки.
func _pose_awp_arms() -> void:
	if _fps_hand_r == null or not is_instance_valid(_fps_hand_r):
		_fps_hand_r = _find_fps_hand("r")
	if _fps_hand_l == null or not is_instance_valid(_fps_hand_l):
		_fps_hand_l = _find_fps_hand("l")
	var hb := _head.global_basis.orthonormalized()
	_reach_arm(_arm_r, _fps_hand_r, hb, FPS_FALLBACK_R)
	_reach_arm(_arm_l, _fps_hand_l, hb, FPS_FALLBACK_L)


func _reach_arm(arm: Node3D, target: Node3D, hb: Basis, fallback: Vector2) -> void:
	var dir: Vector3
	var stretch := 1.0
	if target != null and is_instance_valid(target):
		var to_t := target.global_position - arm.global_position
		var dist := to_t.length()
		if dist > 0.01:
			dir = to_t / dist
			stretch = clampf(dist / _arm_len, FPS_ARM_STRETCH_MIN, FPS_ARM_STRETCH_MAX)
		else:
			dir = _dir(hb, fallback)
	else:
		dir = _dir(hb, fallback)
	var tb := (arm.get_parent() as Node3D).global_basis.orthonormalized()
	var q := Quaternion((-tb.y).normalized(), dir.normalized())
	arm.global_basis = (Basis(q) * tb).scaled_local(Vector3(1.0, stretch, 1.0))


# Шукає кисть FPS-ригу: head/arms/…/hand_R або hand_L (будь-який регістр, також "hand.R" тощо).
func _find_fps_hand(side: String) -> Node3D:
	var arms := _head.get_node_or_null("arms")
	if arms == null:
		return null
	var found: Node3D = null
	for n in arms.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower().replace(".", "_").replace(" ", "_")
		if nm == "hand_" + side or nm == "hand" + side:
			return n as Node3D
		if found == null and nm.begins_with("hand") and nm.ends_with(side):
			found = n as Node3D
	if found == null:
		for n in arms.find_children("*", "Node3D", true, false):
			var nm2 := String(n.name).to_lower().replace(".", "_")
			if nm2 == "arm_" + side:
				return n as Node3D
	return found


# Створює модель альтернативного ножа та знаходить її AnimationPlayer.
func _add_knife_variant(skin: String, packed: PackedScene) -> void:
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return
	instance.name = "Remote_" + skin
	instance.visible = false
	_holder.add_child(instance)
	_knife_variant_nodes[skin] = instance
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		_knife_variant_anim[skin] = players[0] as AnimationPlayer


func set_knife_skin(skin: String) -> void:
	if skin != "karambit" and skin != "bolisong" and skin != "butterfly" and skin != "m9":
		return
	_knife_skin = skin
	_update_knife_visibility()


func _update_knife_visibility() -> void:
	var karambit: Node3D = _weapons.get(1)
	if karambit:
		karambit.visible = (_w == 1 and _knife_skin == "karambit")
	for skin in _knife_variant_nodes:
		(_knife_variant_nodes[skin] as Node3D).visible = (_w == 1 and skin == _knife_skin)


func _play_knife_animation(keywords: Array[String]) -> void:
	var ap: AnimationPlayer = _knife_variant_anim.get(_knife_skin)
	if ap == null:
		return
	for anim_name in ap.get_animation_list():
		if anim_name == "RESET":
			continue
		var lower := String(anim_name).to_lower()
		for keyword in keywords:
			if lower.contains(keyword):
				ap.stop()
				ap.play(anim_name)
				return


# Для weapon_switch.gd: вузол моделі зброї в руках (щоб накласти скін).
func get_weapon_node(id: int) -> Node3D:
	return _weapons.get(id)


func _resolve_arms() -> bool:
	if _arm_r != null:
		return true
	var a := _model.find_child("Arm_L", true, false) as Node3D
	var b := _model.find_child("Arm_R", true, false) as Node3D
	if a == null or b == null:
		return false
	# Модель розвернута на 180°, тому за назвою L/R сторону не вгадати — беремо за позицією.
	if _head.to_local(a.global_position).x > _head.to_local(b.global_position).x:
		_arm_r = a
		_arm_l = b
	else:
		_arm_r = b
		_arm_l = a
	var mi := _arm_r as MeshInstance3D
	if mi and mi.mesh:
		var bb := mi.mesh.get_aabb()
		_arm_len = clampf(maxf(absf(bb.position.y), absf(bb.end.y)) * _arm_r.global_basis.get_scale().y, 0.3, 0.9)
	return true


func _dir(hb: Basis, a: Vector2) -> Vector3:
	return hb * Basis.from_euler(Vector3(deg_to_rad(a.x), deg_to_rad(a.y), 0.0)) * Vector3.FORWARD


# Повертає руку (плече лишається на місці) так, щоб вона дивилась у напрямку a.
func _aim_arm(arm: Node3D, hb: Basis, a: Vector2) -> void:
	var tb := (arm.get_parent() as Node3D).global_basis.orthonormalized()
	var q := Quaternion((-tb.y).normalized(), _dir(hb, a).normalized())
	arm.global_basis = Basis(q) * tb


# ---------------------------------------------------------------- події
# Їх викликає weapon_switch.gd (див. helper _tp там).
func on_switch(weapon: int) -> void:
	_w = weapon
	for id in _weapons:
		(_weapons[id] as Node3D).visible = (id == weapon and (id != 1 or _knife_skin == "karambit"))
	_update_knife_visibility()
	if weapon == 1:
		_play_knife_animation(["draw", "switch", "equip", "deploy"])
	# Діставання: руки й зброя піднімаються знизу.
	off_r = Vector2(-70, 0)
	off_l = Vector2(-60, 0)
	off_pos = Vector3(0, -0.15, 0)
	off_rot = Vector3.ZERO
	var t := _new_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "off_r", Vector2.ZERO, 0.4)
	t.tween_property(self, "off_l", Vector2.ZERO, 0.4)
	t.tween_property(self, "off_pos", Vector3.ZERO, 0.4)


func on_fire() -> void:
	if _w == 1 or _w == SNIPER_ID or _w == AK47_ID:
		return
	off_r = Vector2(5, 0)
	off_l = Vector2(4, 0)
	off_pos = Vector3(0, 0, 0.04)
	var t := _new_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "off_r", Vector2.ZERO, 0.12)
	t.tween_property(self, "off_l", Vector2.ZERO, 0.12)
	t.tween_property(self, "off_pos", Vector3.ZERO, 0.12)


func on_reload(duration: float = 2.0) -> void:
	if _w == SNIPER_ID or _w == AK47_ID:
		return   # AWP/AK: reload грає AnimationPlayer FPS-вузлів (weapon_switch.gd)
	var d := maxf(duration, 0.9)
	var t := _new_tween().set_trans(Tween.TRANS_SINE)
	# ліва рука відходить від цівки до магазину, зброя трохи нахиляється
	t.tween_property(self, "off_l", Vector2(-55, -25), 0.25)
	t.parallel().tween_property(self, "off_rot", Vector3(-10, 0, 18), 0.25)
	t.tween_interval(d - 0.6)
	# вставила магазин (поштовх) і повернулась
	t.tween_property(self, "off_l", Vector2(10, -5), 0.15)
	t.tween_property(self, "off_l", Vector2.ZERO, 0.2)
	t.parallel().tween_property(self, "off_rot", Vector3.ZERO, 0.2)


func on_inspect() -> void:
	if _w == SNIPER_ID or _w == AK47_ID:
		return   # AWP/AK: осмотр грає AnimationPlayer FPS-вузлів
	if _w == 1:
		_play_knife_animation(["inspect", "view", "rollover", "flourish"])
	var t := _new_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "off_rot", Vector3(0, -60, 35), 0.5)
	t.parallel().tween_property(self, "off_l", Vector2(-30, 10), 0.5)
	t.tween_interval(1.0)
	t.tween_property(self, "off_rot", Vector3(25, 60, -35), 0.8)
	t.tween_property(self, "off_rot", Vector3.ZERO, 0.5)
	t.parallel().tween_property(self, "off_l", Vector2.ZERO, 0.5)


func on_knife_attack() -> void:
	_play_knife_animation(["attack", "stab", "slash", "swing", "hit"])
	var t := _new_tween().set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "off_r", Vector2(30, -20), 0.08)    # замах
	t.tween_property(self, "off_r", Vector2(-45, 25), 0.10)    # удар
	t.tween_property(self, "off_r", Vector2.ZERO, 0.25)        # назад


func _new_tween() -> Tween:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	return _tween
