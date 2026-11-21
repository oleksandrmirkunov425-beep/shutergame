extends Camera3D

@onready var ak47: Node3D = $AK47
@onready var knife: Node3D = $Karanbit
@onready var bolisong: Node3D = get_node_or_null("bolisong") if has_node("bolisong") else get_node_or_null("balisong")
@onready var bolisong_anim: AnimationPlayer = bolisong.get_node_or_null("AnimationPlayer") if bolisong else null
@onready var butterfly: Node3D = get_node_or_null("butterfly")
@onready var butterfly_anim: AnimationPlayer = _get_anim_player(butterfly)
@onready var m9: Node3D = get_node_or_null("m9bayonet")
@onready var m9_anim: AnimationPlayer = m9.get_node_or_null("AnimationPlayer") as AnimationPlayer if m9 else null
@onready var ak47_anim: AnimationPlayer = $AK47/доставання
@onready var ak47_reload_anim: AnimationPlayer = $AK47/перезарядка
@onready var ak47_inspect_anim: AnimationPlayer = $AK47/осмотр
@onready var knife_anim: AnimationPlayer = $Karanbit/доставання
@onready var knife_attack_anim: AnimationPlayer = $Karanbit/удар
@onready var knife_inspect_anim: AnimationPlayer = get_node_or_null("Karanbit/осмотр") as AnimationPlayer
@onready var muzzle: Marker3D = $AK47/MuzzlePoint

var player_body: CharacterBody3D = null

enum Weapon { AK47, KNIFE, SNIPER, M4 }
var current_weapon: Weapon = Weapon.KNIFE

@export_category("Shooting Settings")
@export var ak_damage: float = 25.0   # урон АК за влучання в тулуб (множники частин тіла — у hitbox.gd)
@export var fire_rate: float = 0.1
@export var max_shoot_distance: float = 1000.0
@export var shoot_collision_mask: int = 1
@export var full_auto: bool = true

@export_category("Ammo Settings")
@export var mag_size: int = 30
@export var mag_count: int = 3
@export var reload_time: float = 2.2

# base_spread_deg = 0 — стоячи нерухомо, 1-й постріл черги летить точно
# в приціл. Розкид з'являється тільки з наступних пострілів (накопичення),
# від руху (move_spread_deg) або в стрибку (jump_spread_deg).
@export_category("Spread Settings")
@export var base_spread_deg: float = 0.0
@export var max_spread_deg: float = 2.0
@export var spread_increase_per_shot: float = 0.12
@export var spread_recovery_speed: float = 6.0
@export var jump_spread_deg: float = 6.0

# Після цієї кількості пострілів у поточній черзі розкид росте трохи швидше,
# але кулі все одно тримаються спрей-патерну (як у CS2).
@export var shots_before_heavy_spread: int = 10
@export var heavy_spread_increase_per_shot: float = 0.25

@export var move_spread_deg: float = 4.5
@export var move_spread_speed_threshold: float = 3.0

@export_category("Recoil Settings")
@export var recoil_kick_up_deg: float = 0.85
@export var recoil_kick_side_deg: float = 0.85
@export var recoil_snappiness: float = 22.0
@export var recoil_recovery_speed_deg: float = 14.0
@export var recoil_recovery_delay: float = 0.15

# Фіксований спрей-патерн АК-47 (30 куль): Vector2(вгору_deg, вліво_deg).
# Перші ~9 куль ідуть вгору, далі класична Т-подібна дуга вліво -> вправо -> вліво.
const AK_SPRAY_PATTERN: Array[Vector2] = [
	Vector2(0.45,  0.00), # 1
	Vector2(0.75,  0.05), # 2
	Vector2(1.10, -0.05), # 3
	Vector2(1.35,  0.10), # 4
	Vector2(1.45, -0.15), # 5
	Vector2(1.40,  0.15), # 6
	Vector2(1.25, -0.25), # 7
	Vector2(1.10,  0.35), # 8
	Vector2(0.85,  0.65), # 9
	Vector2(0.55,  0.90), # 10
	Vector2(0.30,  0.80), # 11
	Vector2(0.15,  0.35), # 12
	Vector2(0.10, -0.55), # 13
	Vector2(0.10, -0.95), # 14
	Vector2(0.15, -1.10), # 15
	Vector2(0.15, -0.90), # 16
	Vector2(0.10, -0.45), # 17
	Vector2(0.10,  0.35), # 18
	Vector2(0.15,  0.85), # 19
	Vector2(0.15,  1.05), # 20
	Vector2(0.10,  0.90), # 21
	Vector2(0.10,  0.40), # 22
	Vector2(0.15, -0.50), # 23
	Vector2(0.15, -0.90), # 24
	Vector2(0.10, -0.80), # 25
	Vector2(0.10, -0.35), # 26
	Vector2(0.10,  0.45), # 27
	Vector2(0.10,  0.75), # 28
	Vector2(0.05,  0.50), # 29
	Vector2(0.05, -0.25), # 30
]

@export_category("Crosshair Settings")
@export var crosshair: Control
@export var crosshair_recoil_multiplier: float = 900.0
@export var crosshair_spread_multiplier: float = 300.0
@export var crosshair_follow_speed: float = 14.0

@export_category("HUD")
@export var ammo_label: Label

# Звуки пострілів. Якщо не призначені в інспекторі — вантажаться з res://sounds/.
@export_category("Sounds")
@export var ak_shot_sound: AudioStream
@export var awp_shot_sound: AudioStream
@export var shot_volume_db: float = -3.0
@export var shot_max_distance: float = 150.0
# Базове ім'я без розширення: шукаються .ogg, .mp3, .wav (у такому порядку), тож свої записи
# достатньо покласти у res://sounds/ під іменами ak_shot / awp_shot.
const AK_SHOT_BASE := "res://sounds/ak_shot"
const AWP_SHOT_BASE := "res://sounds/awp_shot"
const SOUND_EXTENSIONS: Array[String] = [".ogg", ".mp3", ".wav"]
var _ak_sounds: Array[AudioStream] = []
var _awp_sounds: Array[AudioStream] = []
var _sounds_loaded_ak: bool = false
var _sounds_loaded_awp: bool = false

# ------------------------------------------------------------------
# СНАЙПЕРКА (AWP). Анімації (draw / reload / view) беруться з AnimationPlayer,
# який лежить у сцені: head/Camera3D/awp/AnimationPlayer. У коді анімацій немає.
# Клавіша 3 — дістати, ПКМ — приціл (кілька разів = наступний рівень зуму), R — перезарядка.
# ------------------------------------------------------------------
@export_category("Sniper (AWP)")
@export var sniper_scene: PackedScene   # необов'язково: інакше вантажиться res://awp/awp.glb
@export var sniper_view_position: Vector3 = Vector3(0.24, -0.40, -0.45)
@export var sniper_view_rotation_deg: Vector3 = Vector3(0.0, 90.0, 0.0)
@export var sniper_view_scale: Vector3 = Vector3.ONE
@export var sniper_muzzle_local: Vector3 = Vector3(0.64, 0.163, 0.0)   # дуло в координатах моделі
@export var sniper_damage: float = 115.0
@export var sniper_bullet_speed: float = 300.0   # швидкість кулі (у АК — 60 з bullet.tscn)
@export var sniper_fire_interval: float = 1.45    # мінімум між пострілами (якщо є анімація пострілу довша — чекаємо її)
@export var sniper_mag_size: int = 5
@export var sniper_reserve_total: int = 15
# Нескінченний запас: перезаряджатись можна безкінечно (обойма витрачається, запас — ні). Вимкніть для звичайних патронів.
@export var infinite_reserve_ammo: bool = true
@export var sniper_reload_time: float = 3.3   # запасне значення: діє, лише якщо в плеєрі немає анімації reload
@export var sniper_unscoped_spread_deg: float = 5.0   # без прицілу летить «куди-небудь»
@export var sniper_recoil_up_deg: float = 2.2
@export var sniper_zoom_fovs: Array[float] = [30.0, 10.0]   # FOV першого та другого рівня зуму

const SNIPER_MODEL_PATHS: Array[String] = ["res://awp/awp.glb", "res://awp/awp_style.glb"]

# ------------------------------------------------------------------
# M4A1 (поки без стрільби: тільки модель в руках, меню, HUD, магазин)
# Береться вузол head/Camera3D/m4 зі сцени (положення з редактора лишається як є).
# Якщо вузла немає — будується з res://m4/m4a1_detailed_v3.glb зі значеннями нижче.
# ------------------------------------------------------------------
@export_category("M4")
@export var m4_scene: PackedScene
@export var m4_view_position: Vector3 = Vector3(0.303, -0.49, -0.55)
@export var m4_view_rotation_deg: Vector3 = Vector3(0.0, 101.4, 0.0)
@export var m4_view_scale: Vector3 = Vector3(1.3, 1.3, 1.3)
@export var m4_mag_size: int = 30
@export var m4_reserve_total: int = 90
@export var m4_damage: float = 30.0 # Урон по тулубу, руках і ногах; голова задається окремо нижче.
@export var m4_head_damage: float = 60.0
@export var m4_fire_rate: float = 0.14 # Повільніше: приблизно 7.1 пострілу/с.
@export var m4_reload_time: float = 2.4
@export var m4_recoil_up_multiplier: float = 0.72
@export var m4_recoil_side_multiplier: float = 0.78
var m4_shot_count: int = 0
const M4_SPRAY_PATTERN: Array[Vector2] = [
	Vector2(0.34, 0.00), Vector2(0.48, 0.03), Vector2(0.62, -0.04),
	Vector2(0.72, 0.06), Vector2(0.78, -0.08), Vector2(0.80, 0.10),
	Vector2(0.76, -0.12), Vector2(0.70, 0.16), Vector2(0.62, 0.22),
	Vector2(0.55, 0.28), Vector2(0.48, 0.24), Vector2(0.42, 0.12),
	Vector2(0.38, -0.16), Vector2(0.36, -0.24), Vector2(0.38, -0.28),
	Vector2(0.40, -0.22), Vector2(0.36, -0.10), Vector2(0.34, 0.10),
	Vector2(0.36, 0.22), Vector2(0.38, 0.26), Vector2(0.34, 0.20),
	Vector2(0.32, 0.08), Vector2(0.34, -0.14), Vector2(0.34, -0.22),
	Vector2(0.32, -0.18), Vector2(0.30, -0.08), Vector2(0.30, 0.10),
	Vector2(0.28, 0.18), Vector2(0.28, 0.12), Vector2(0.26, -0.06)
]
const M4_MODEL_PATHS: Array[String] = ["res://m4/m4a1_detailed_v3.glb"]
var m4_holder: Node3D = null
var m4_anim: AnimationPlayer = null      # AnimationPlayer з вузла m4 (анімація "draw")
var _m4_pose_base: Array = []            # звичайна поза M4 + рук зі сцени (до будь-якої анімації)
const M4_ANIM_DRAW := "draw"
const M4_DRAW_TIME: float = 0.75         # тривалість діставання, с
const M4_DRAW_START_OFFSET := Vector3(0.14, -0.62, 0.18)   # звідки з'являється M4 (простір камери)
const M4_DRAW_START_ROT := Vector3(0.0, 0.22, -0.65)       # нахил стовбуром вниз на старті
const M4_DRAW_ARMS_OFFSET := Vector3(0.0, -0.62, 0.18)     # руки йдуть знизу разом зі зброєю
var m4_muzzle_point: Marker3D = null
var m4_ammo_in_mag: int = 30
var m4_reserve: int = 90

# Назви анімацій у AnimationPlayer снайперки (сцена character.tscn).
const SNIPER_ANIM_DRAW := "draw"
const SNIPER_ANIM_RELOAD := "reload"
const SNIPER_ANIM_VIEW := "view"
var _sniper_inspect_id: int = 0
var _force_redraw: bool = false

var sniper_holder: Node3D = null
var sniper_muzzle: Node3D = null

# Спільний ефект спалаху для всіх видів вогнепальної зброї.
# Покладіть PNG у корінь проєкту: res://muzzle_flash.png.
const MUZZLE_FLASH_TEXTURE_PATH := "res://muzzle_flash.png"
var _ak_muzzle_flash: Sprite3D = null
var _sniper_muzzle_flash: Sprite3D = null
var _ak_muzzle_flash_tween: Tween = null
var _sniper_muzzle_flash_tween: Tween = null
var _m4_muzzle_flash: Sprite3D = null
var _m4_muzzle_flash_tween: Tween = null

var sniper_ammo_in_mag: int = 0
var sniper_reserve: int = 0
var sniper_scope_level: int = 0   # 0 = без прицілу
var _sniper_next_shot_ms: int = 0   # час (мс), раніше за який затвор ще не готовий
var _sniper_reload_id: int = 0
# AnimationPlayer снайперки зі сцени та початкові пози вузлів, які він чіпає (AWP + руки).
var sniper_anim: AnimationPlayer = null
var _sniper_pose_base: Array = []
# Поза «тримаю AWP»: кінцеві кадри анімації draw (AWP + руки). Саме в ній AWP та руки мають стояти,
# коли нічого не відбувається (після огляду F, скасування огляду, респавну). Це і є «idle».
var _sniper_hold_base: Array = []
var _base_fov: float = 75.0
var _base_mouse_sens: float = -1.0
var _scope_layer: CanvasLayer = null
var _crosshair_hidden_by_scope: bool = false
var _arms_hidden_by_sniper: bool = false
var _arms_default_poses: Array = []

# Основна зброя (слот 1): що саме обрано в меню на E. Ніж — слот 3.
var primary_weapon: Weapon = Weapon.AK47
var _weapon_menu_layer: CanvasLayer = null
# Зброя в руках малюється окремим шаром ПОВЕРХ екрана (не проходить крізь стіни).
const VIEWMODEL_LAYER: int = 1 << 19   # візуальний шар №20 (у сцені він вільний)
var _vm_viewport: SubViewport = null
var _vm_camera: Camera3D = null
var _weapon_menu_open: bool = false
var _weapon_menu_buttons: Dictionary = {}

var can_shoot: bool = true
var is_reloading: bool = false
var is_drawing: bool = false
var is_attacking: bool = false
var is_inspecting: bool = false

# Який ніж вибрано: "karambit", "bolisong", "butterfly" або "m9" (синхронізується між гравцями)
var knife_skin: String = "karambit"
var _bolisong_base_rot: Vector3 = Vector3.ZERO
var _butterfly_base_rot: Vector3 = Vector3.ZERO
var _butterfly_base_pos: Vector3 = Vector3.ZERO
var _m9_base_rot: Vector3 = Vector3.ZERO
var _m9_pose_base: Array = []
var _m9_action_id: int = 0
# Лічильник осмотрів: старий таймер не має права зупиняти новий осмотр.
var _butterfly_inspect_id: int = 0
# Лічильник перемикань зброї: таймер старого перемикання не має права чіпати новий стан.
var _switch_id: int = 0
# Осмотр керамбіта: лічильник (старий таймер не чіпає новий осмотр) і базові значення вузлів.
var _knife_inspect_id: int = 0
var _knife_inspect_base: Array = []
# Початкові (до будь-якої анімації) position/rotation/scale/visible вузлів bolisong і butterfly
# (рука, ніж...). Без їх відновлення після stop() рука могла лишитись у позі,
# з якої Draw уже не виводить її на екран.
var _bolisong_pose_base: Array = []
var _butterfly_pose_base: Array = []

var ammo_in_mag: int = 0
var reserve_ammo: int = 0

var current_spread_deg: float = 0.0
var recoil_target: Vector2 = Vector2.ZERO
var recoil_current: Vector2 = Vector2.ZERO

# Лічильник пострілів у поточній черзі. Скидається на 0, щойно розкид
# повністю спадає до нуля (тобто пройшла пауза між чергами) — так наступна
# черга знову починається з точного 1-го пострілу.
var shot_count: int = 0
var _time_since_last_shot: float = 999.0

var crosshair_base_position: Vector2 = Vector2.ZERO
var crosshair_display_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_base_fov = fov
	# Перед кожним кадром примусово лишаємо видимою тільки зброю з рук (на всіх клієнтах).
	RenderingServer.frame_pre_draw.connect(_enforce_held_only)
	_ensure_input_action("slot_primary", KEY_1)
	_ensure_input_action("slot_knife", KEY_3)
	_ensure_input_action("weapon_menu", KEY_E)
	_ensure_input_action("scope", KEY_NONE, MOUSE_BUTTON_RIGHT)
	_setup_sniper()
	_setup_m4()
	_capture_knife_inspect_base()
	_bolisong_pose_base = _capture_pose_base(bolisong_anim)
	_butterfly_pose_base = _capture_pose_base(butterfly_anim)
	_m9_pose_base = _capture_pose_base(m9_anim)
	if m9:
		_m9_base_rot = m9.rotation
		_setup_m9_idle()
	if bolisong:
		_bolisong_base_rot = bolisong.rotation
	if butterfly:
		_butterfly_base_rot = butterfly.rotation
		_butterfly_base_pos = butterfly.position
		_setup_butterfly_idle()
	_apply_visibility()

	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			player_body = node
			break
		node = node.get_parent()

	_capture_arms_default_poses()

	if not _has_authority():
		set_process(false)
		set_process_unhandled_input(false)
		current = false
		return

	current = true

	# Мій вибраний ніж із меню; розсилаємо суперникові трохи згодом і на початку кожного раунду.
	knife_skin = Loadout.knife
	_apply_weapon_skin(ak47, Loadout.ak_skin)
	_apply_weapon_skin(sniper_holder, Loadout.awp_skin)
	_apply_visibility()
	get_tree().create_timer(1.0).timeout.connect(announce_knife_skin)

	if not ammo_label:
		var found = get_tree().get_first_node_in_group("ammo_label")
		if found and found is Label:
			ammo_label = found
		else:
			push_warning("ammo_label не знайдено ні в Інспекторі, ні по групі 'ammo_label'!")

	ammo_in_mag = mag_size
	reserve_ammo = mag_size * (mag_count - 1)
	sniper_ammo_in_mag = sniper_mag_size
	sniper_reserve = sniper_reserve_total
	m4_ammo_in_mag = m4_mag_size
	m4_reserve = m4_reserve_total
	_setup_scope_ui()
	_setup_weapon_menu()
	_setup_viewmodel_overlay()

	current_weapon = Weapon.AK47
	_update_ammo_hud()

	switch_weapon(Weapon.KNIFE)

	if player_body == null:
		push_warning("Не знайдено CharacterBody3D серед предків — розкид у стрибку/русі не працюватиме!")

	if crosshair:
		crosshair_base_position = crosshair.position
	else:
		push_warning("crosshair не призначено в інспекторі — приціл не буде рухатись!")


func _has_authority() -> bool:
	return player_body != null and player_body.is_multiplayer_authority()


# На старті раунду (3-2-1) стрільба заблокована.
func _is_frozen() -> bool:
	return player_body != null and "frozen" in player_body and player_body.frozen


func _is_paused() -> bool:
	return player_body != null and "paused" in player_body and player_body.paused


func _is_player_dead() -> bool:
	return player_body != null and "is_dead" in player_body and player_body.is_dead


func _process(delta: float) -> void:
	_time_since_last_shot += delta

	# Старт раунду (3-2-1) або смерть — приціл AWP знімається й нового не вмикається.
	if sniper_scope_level > 0 and (_is_frozen() or _is_player_dead()):
		_set_scope(0)

	# Після паузи у стрільбі рівномірно повертаємо цільову віддачу до 0
	if _time_since_last_shot >= recoil_recovery_delay:
		if current_spread_deg > 0.0:
			current_spread_deg = max(current_spread_deg - spread_recovery_speed * delta, 0.0)
			if current_spread_deg <= 0.0:
				shot_count = 0

		var step_rad: float = deg_to_rad(recoil_recovery_speed_deg) * delta
		recoil_target = recoil_target.move_toward(Vector2.ZERO, step_rad)
		if recoil_target == Vector2.ZERO and current_spread_deg <= 0.0:
			shot_count = 0
			m4_shot_count = 0

	# Плавно наздоганяємо recoil_target (без різких ривків ні вгору, ні вниз)
	var prev_recoil: Vector2 = recoil_current
	recoil_current = recoil_current.lerp(recoil_target, clamp(recoil_snappiness * delta, 0.0, 1.0))
	var delta_recoil: Vector2 = recoil_current - prev_recoil
	rotation.x += delta_recoil.x
	rotation.y += delta_recoil.y

	# ESC (player.gd повертає захоплення миші) закриває меню зброї.
	if _weapon_menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_close_weapon_menu(false)

	if full_auto and (current_weapon == Weapon.AK47 or current_weapon == Weapon.M4) and not _weapon_menu_open and not _is_frozen() and not _is_player_dead() and not _is_paused() and Input.is_action_pressed("shoot"):
		if can_shoot and not is_reloading and not is_drawing:
			if current_weapon == Weapon.M4:
				m4_shoot()
			else:
				shoot()

	_update_crosshair(delta)
	_sync_viewmodel_camera()


func _update_crosshair(_delta: float) -> void:
	if not crosshair:
		return

	# Приціл завжди залишається по центру екрана (куди дивиться камера),
	# змінюється лише його розмір залежно від розкиду.
	crosshair.position = crosshair_base_position
	var spread_scale: float = 1.0 + deg_to_rad(current_spread_deg) * (crosshair_spread_multiplier / 100.0)
	crosshair.scale = Vector2(spread_scale, spread_scale)


func _unhandled_input(event: InputEvent) -> void:
	# Меню паузи відкрите — ігрові дії вимкнені.
	if _is_paused():
		return
	# E — меню вибору основної зброї (АК-47 / M4 / AWP). Поки воно відкрите, ігрові дії вимкнені.
	if event.is_action_pressed("weapon_menu"):
		if _weapon_menu_open:
			_close_weapon_menu()
		else:
			_open_weapon_menu()
		return
	if _weapon_menu_open:
		return

	# 1 — основна зброя (обрана в меню), 3 — ніж.
	if event.is_action_pressed("slot_primary") and not is_attacking:
		switch_weapon(primary_weapon)
	elif event.is_action_pressed("slot_knife") and not is_attacking:
		switch_weapon(Weapon.KNIFE)

	# На старті раунду та після смерті стріляти / бити ножем / перезаряджатись не можна.
	if _is_player_dead() and (event.is_action_pressed("shoot") or event.is_action_pressed("reload")):
		return
	if event.is_action_pressed("shoot") and _is_frozen():
		return

	if event.is_action_pressed("shoot"):
		if (current_weapon == Weapon.AK47 or current_weapon == Weapon.M4) and can_shoot and not is_reloading and not is_drawing:
			if current_weapon == Weapon.M4:
				m4_shoot()
			else:
				shoot()
		elif current_weapon == Weapon.KNIFE and not is_drawing and not is_attacking:
			knife_attack()
		elif current_weapon == Weapon.SNIPER:
			sniper_shoot()

	if event.is_action_pressed("scope") and current_weapon == Weapon.SNIPER and not is_drawing and not is_reloading and not _is_frozen() and not _is_player_dead():
		_sniper_cancel_inspect()
		_cycle_scope()

	if event.is_action_pressed("reload"):
		if current_weapon == Weapon.AK47 and not is_reloading and not is_drawing:
			reload()
		elif current_weapon == Weapon.M4 and not is_reloading and not is_drawing:
			m4_reload()
		elif current_weapon == Weapon.SNIPER:
			sniper_reload()

	if event.is_action_pressed("view"):
		if current_weapon == Weapon.AK47 and not is_drawing and not is_reloading and not is_inspecting:
			inspect_weapon()
		elif current_weapon == Weapon.KNIFE and not is_drawing and not is_attacking and not is_inspecting:
			inspect_weapon()
		elif current_weapon == Weapon.SNIPER and not is_drawing and not is_reloading and not is_inspecting and sniper_scope_level == 0:
			inspect_weapon()


func switch_weapon(weapon: Weapon) -> void:
	if current_weapon == weapon or is_attacking:
		return
	Matchmaker.rpc_room(self, "_switch_weapon_rpc", [weapon], false)


@rpc("call_local", "any_peer", "reliable")
func _switch_weapon_rpc(weapon: Weapon) -> void:
	# _force_redraw: той самий виклик, але без «зброя вже в руках» — щоб заново зіграти draw.
	if current_weapon == weapon and not _force_redraw:
		return
	_force_redraw = false

	_switch_id += 1
	var my_switch: int = _switch_id
	if _has_authority():
		is_drawing = false   # нове перемикання скасовує попереднє діставання

	var prev_weapon: Weapon = current_weapon
	current_weapon = weapon
	if prev_weapon == Weapon.SNIPER:
		# Зникає приціл, скасовується перезарядка та поза снайперки.
		_sniper_reload_id += 1
		if _has_authority() and is_reloading:
			is_reloading = false
		_sniper_reset_pose()
	_set_scope(0)
	_apply_visibility()
	_knife_inspect_cancel()

	if prev_weapon == Weapon.M4 and weapon != Weapon.M4:
		# Зупиняємо draw і повертаємо M4 та руки в звичайну позу, щоб не «залипли» посеред анімації.
		_m4_reset_pose()
		_restore_arms_default_poses()
	if prev_weapon == Weapon.M4 and _has_authority():
		is_reloading = false

	ak47.set_process(weapon == Weapon.AK47)
	ak47.set_physics_process(weapon == Weapon.AK47)
	ak47.set_process_unhandled_input(weapon == Weapon.AK47)

	knife.set_process(weapon == Weapon.KNIFE)
	knife.set_physics_process(weapon == Weapon.KNIFE)
	knife.set_process_unhandled_input(weapon == Weapon.KNIFE)

	# Якщо перемикаємо зброю під час осмотру АК47 — перериваємо осмотр
	if is_inspecting:
		if ak47_inspect_anim:
			ak47_inspect_anim.stop()
		if bolisong_anim:
			bolisong_anim.stop()
		_butterfly_cancel()
		_m9_stop()
		is_inspecting = false

	if weapon == Weapon.AK47:
		if knife_anim:
			knife_anim.stop()
		if knife_attack_anim:
			knife_attack_anim.stop()
		if bolisong_anim:
			bolisong_anim.stop()
			_restore_pose_base(_bolisong_pose_base)
		_butterfly_cancel()
		_restore_pose_base(_butterfly_pose_base)
		_m9_stop()
		if ak47_anim:
			ak47_anim.stop()
			ak47_anim.play("knife1_Switch")
			var anim_length: float = ak47_anim.current_animation_length / maxf(absf(ak47_anim.speed_scale), 0.01)
			if _has_authority():
				is_drawing = true
			await get_tree().create_timer(anim_length).timeout
			# Поки чекали, зброю перемкнули знову — це перемикання застаріло.
			if my_switch != _switch_id:
				return
			if _has_authority():
				is_drawing = false
		if _has_authority():
			_update_ammo_hud()
	elif weapon == Weapon.KNIFE:
		if ak47_anim:
			ak47_anim.stop()
		var draw_player: AnimationPlayer = knife_anim
		var draw_name: String = "swichKNIFE"
		if _use_bolisong():
			draw_player = bolisong_anim
			draw_name = _find_anim(bolisong_anim, ["draw", "switch", "equip", "deploy"])
		elif _use_butterfly():
			# Діставання butterfly — анімація "Draw"
			_butterfly_cancel()
			draw_player = butterfly_anim
			draw_name = "Draw" if butterfly_anim.has_animation("Draw") else _find_anim(butterfly_anim, ["draw", "switch", "equip", "deploy"])
		elif _use_m9():
			# Діставання M9: анімація "draw" (рука й ніж піднімаються), далі — "idle"
			_m9_stop()
			draw_player = m9_anim
			draw_name = _find_anim(m9_anim, ["draw", "switch", "equip", "deploy"])
		if draw_player and draw_name != "" and draw_player.has_animation(draw_name):
			draw_player.stop()
			# Скидаємо руку/ніж у початкову позу, щоб Draw стартував так само, як і вперше.
			if draw_player == bolisong_anim:
				_restore_pose_base(_bolisong_pose_base)
			elif draw_player == butterfly_anim:
				_restore_pose_base(_butterfly_pose_base)
			elif draw_player == m9_anim:
				_restore_pose_base(_m9_pose_base)
			draw_player.play(draw_name)
			draw_player.seek(0.0, true)
			var draw_length: float = draw_player.current_animation_length / maxf(absf(draw_player.speed_scale), 0.01)
			if _has_authority():
				is_drawing = true
			await get_tree().create_timer(draw_length).timeout
			# Поки чекали, зброю перемкнули знову — це перемикання застаріло.
			if my_switch != _switch_id:
				return
			if _has_authority():
				is_drawing = false
			if draw_player == butterfly_anim:
				# Idle вмикаємо щойно закінчився Draw — на всіх клієнтах, не лише в authority.
				_butterfly_play_idle()
			elif draw_player == m9_anim:
				_m9_play_idle()
		if _has_authority() and ammo_label:
			ammo_label.text = ""
	elif weapon == Weapon.SNIPER:
		if ak47_anim:
			ak47_anim.stop()
		if ak47_reload_anim:
			ak47_reload_anim.stop()
		if knife_anim:
			knife_anim.stop()
		if knife_attack_anim:
			knife_attack_anim.stop()
		_restore_arms_default_poses()
		if bolisong_anim:
			bolisong_anim.stop()
			_restore_pose_base(_bolisong_pose_base)
		_butterfly_cancel()
		_restore_pose_base(_butterfly_pose_base)
		_m9_stop()
		var draw_length: float = _sniper_play(SNIPER_ANIM_DRAW)
		if _has_authority():
			is_drawing = true
		await get_tree().create_timer(draw_length).timeout
		if my_switch != _switch_id:
			return
		if _has_authority():
			is_drawing = false
			_update_ammo_hud()
	elif weapon == Weapon.M4:
		if ak47_anim:
			ak47_anim.stop()
		if ak47_reload_anim:
			ak47_reload_anim.stop()
		if knife_anim:
			knife_anim.stop()
		if knife_attack_anim:
			knife_attack_anim.stop()
		_restore_arms_default_poses()
		if bolisong_anim:
			bolisong_anim.stop()
			_restore_pose_base(_bolisong_pose_base)
		_butterfly_cancel()
		_restore_pose_base(_butterfly_pose_base)
		_m9_stop()
		if _has_authority():
			_update_ammo_hud()
		# Діставання M4: анімація "draw" (зброя й руки піднімаються знизу в позу «тримаю»).
		var m4_draw_length: float = _m4_play_draw()
		if _has_authority() and m4_draw_length > 0.0:
			is_drawing = true
		await get_tree().create_timer(m4_draw_length).timeout
		# Поки чекали, зброю перемкнули знову — це перемикання застаріло.
		if my_switch != _switch_id:
			return
		if _has_authority():
			is_drawing = false
			_update_ammo_hud()


func knife_attack() -> void:
	if _is_player_dead():
		return
	Matchmaker.rpc_room(self, "_knife_attack_rpc", [], false)


@rpc("call_local", "any_peer", "reliable")
func _knife_attack_rpc() -> void:
	_knife_inspect_cancel()
	if _use_bolisong():
		_bolisong_attack()
		return
	if _use_butterfly():
		_butterfly_attack()
		return
	if _use_m9():
		_m9_attack()
		return

	if not knife_attack_anim:
		push_warning("knife_attack_anim (AnimationPlayer 'удар') не знайдено!")
		return

	if _has_authority():
		is_attacking = true
		is_inspecting = false

	knife_attack_anim.stop()

	var attack_anim_name: String = ""
	for anim_name in knife_attack_anim.get_animation_list():
		if anim_name != "RESET":
			attack_anim_name = anim_name
			break

	if attack_anim_name != "":
		knife_attack_anim.play(attack_anim_name)
	else:
		push_warning("У AnimationPlayer 'удар' немає жодної анімації окрім RESET!")
		if _has_authority():
			is_attacking = false
		return

	if _has_authority():
		var anim_length: float = knife_attack_anim.current_animation_length
		await get_tree().create_timer(anim_length).timeout
		is_attacking = false


# ------------------------------------------------------------------
# ОСМОТР ЗБРОЇ (АК47) — виклик по кнопці "view" (F)
# ------------------------------------------------------------------
func inspect_weapon() -> void:
	Matchmaker.rpc_room(self, "_inspect_weapon_rpc", [], false)


@rpc("call_local", "any_peer", "reliable")
func _inspect_weapon_rpc() -> void:
	if current_weapon == Weapon.SNIPER:
		_sniper_inspect()
		return
	if current_weapon == Weapon.KNIFE and _use_bolisong():
		_bolisong_inspect()
		return
	if current_weapon == Weapon.KNIFE and _use_butterfly():
		_butterfly_inspect()
		return
	if current_weapon == Weapon.KNIFE and _use_m9():
		_m9_inspect()
		return
	if current_weapon == Weapon.KNIFE:
		_knife_inspect()
		return

	if not ak47_inspect_anim:
		push_warning("ak47_inspect_anim (AnimationPlayer 'осмотр') не знайдено!")
		return

	var inspect_anim_name: String = ""
	for anim_name in ak47_inspect_anim.get_animation_list():
		if anim_name != "RESET":
			inspect_anim_name = anim_name
			break

	if inspect_anim_name == "":
		push_warning("У AnimationPlayer 'осмотр' немає жодної анімації окрім RESET!")
		return

	ak47_inspect_anim.stop()
	ak47_inspect_anim.play(inspect_anim_name)

	if _has_authority():
		is_inspecting = true
		var anim_length: float = ak47_inspect_anim.current_animation_length
		await get_tree().create_timer(anim_length).timeout
		# Якщо постріл вже перервав осмотр раніше — is_inspecting вже false,
		# нічого страшного, просто ще раз виставимо false.
		is_inspecting = false


func shoot() -> void:
	if _is_player_dead():
		return
	# Миттєво перериваємо осмотр зброї, якщо стріляємо під час нього
	if ak47_inspect_anim and ak47_inspect_anim.is_playing():
		ak47_inspect_anim.stop()
		is_inspecting = false

	if ammo_in_mag <= 0:
		if reserve_ammo > 0 or infinite_reserve_ammo:
			reload()
		return

	can_shoot = false
	ammo_in_mag -= 1
	_update_ammo_hud()

	# Куля вилітає з камери (приціл) прямо по напрямку погляду, а не з дула —
	# тож навіть якщо зброя за стіною, куля йде в те, на що дивиться приціл.
	var direction: Vector3 = _get_spread_direction()
	var spawn_pos: Vector3 = global_transform.origin

	# У локальному матчі RPC-одержувачів немає: обробляємо постріл тут же.
	var room := Matchmaker.room_of(self)
	if room and bool(room.get_meta("bot_match", false)):
		_spawn_bullet_rpc(spawn_pos, direction, multiplayer.get_unique_id())
	else:
		# Онлайн: розсилаємо постріл іншим гравцям кімнати.
		Matchmaker.rpc_room(self, "_spawn_bullet_rpc", [spawn_pos, direction, multiplayer.get_unique_id(), -1.0, -1.0], false)

	_apply_recoil()

	# Перші shots_before_heavy_spread пострілів черги — звичайний приріст.
	# Далі (6-й патрон і більше) — набагато сильніший приріст розкиду.
	var increment: float = spread_increase_per_shot
	if shot_count >= shots_before_heavy_spread:
		increment = heavy_spread_increase_per_shot

	current_spread_deg = min(current_spread_deg + increment, max_spread_deg)
	shot_count += 1

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true


func m4_shoot() -> void:
	if _is_player_dead() or current_weapon != Weapon.M4 or not can_shoot:
		return
	if m4_ammo_in_mag <= 0:
		if m4_reserve > 0:
			m4_reload()
		return

	can_shoot = false
	m4_ammo_in_mag -= 1
	_update_ammo_hud()
	var direction: Vector3 = _get_spread_direction()
	var spawn_pos: Vector3 = global_transform.origin
	var room := Matchmaker.room_of(self)
	if room and bool(room.get_meta("bot_match", false)):
		_spawn_bullet_rpc(spawn_pos, direction, multiplayer.get_unique_id(), m4_damage, -1.0)
	else:
		Matchmaker.rpc_room(self, "_spawn_bullet_rpc", [spawn_pos, direction, multiplayer.get_unique_id(), m4_damage, -1.0], false)

	_apply_recoil()
	var increment: float = spread_increase_per_shot * 0.82
	if shot_count >= shots_before_heavy_spread:
		increment = heavy_spread_increase_per_shot * 0.72
	current_spread_deg = minf(current_spread_deg + increment, max_spread_deg * 0.85)
	shot_count += 1
	m4_shot_count += 1
	await get_tree().create_timer(m4_fire_rate).timeout
	can_shoot = true


func m4_reload() -> void:
	if is_reloading or m4_ammo_in_mag >= m4_mag_size or m4_reserve <= 0:
		return
	is_reloading = true
	can_shoot = false
	await get_tree().create_timer(m4_reload_time).timeout
	if not is_inside_tree():
		return
	var needed: int = m4_mag_size - m4_ammo_in_mag
	var take: int = min(needed, m4_reserve)
	m4_ammo_in_mag += take
	m4_reserve -= take
	current_spread_deg = 0.0
	shot_count = 0
	m4_shot_count = 0
	_update_ammo_hud()
	is_reloading = false
	can_shoot = true


@rpc("call_local", "any_peer", "reliable")
func _spawn_bullet_rpc(spawn_pos: Vector3, direction: Vector3, shooter_id: int, damage_override: float = -1.0, speed_override: float = -1.0) -> void:
	# Хітскан: постріл — миттєвий промінь, без об'єкта кулі.
	var is_sniper: bool = speed_override > 0.0
	var is_m4: bool = damage_override > 0.0 and is_equal_approx(damage_override, m4_damage)
	var damage: float = damage_override if damage_override > 0.0 else ak_damage
	_fire_hitscan(spawn_pos, direction, shooter_id, damage)

	# Трейсер кулі: короткий слід у напрямку пострілу.
	_spawn_bullet_tracer(spawn_pos, direction, is_sniper, is_m4)

	# Кожна зброя має власну точку спалаху: M4 не використовує маркер АК.
	if is_m4:
		_play_m4_muzzle_flash()
	else:
		_play_weapon_muzzle_flash(is_sniper)

	# Поки окремий запис M4 не призначений, використовується стандартний звук пострілу.
	_play_shot_sound(spawn_pos, is_sniper)


func _find_m4_muzzle_world_position() -> Vector3:
	# Фіксована точка на кінці ствола M4A1 з моделі m4a1_detailed_v3.glb.
	if is_instance_valid(m4_muzzle_point):
		return m4_muzzle_point.global_position
	return global_position + (-global_transform.basis.z.normalized() * 0.5)


func _get_or_create_m4_muzzle_flash() -> Sprite3D:
	if is_instance_valid(_m4_muzzle_flash):
		return _m4_muzzle_flash

	if not ResourceLoader.exists(MUZZLE_FLASH_TEXTURE_PATH):
		push_warning("Не знайдено текстуру спалаху M4: %s" % MUZZLE_FLASH_TEXTURE_PATH)
		return null

	var texture := load(MUZZLE_FLASH_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("Не вдалося завантажити текстуру спалаху M4: %s" % MUZZLE_FLASH_TEXTURE_PATH)
		return null

	var flash := Sprite3D.new()
	flash.name = "M4_MuzzleFlash"
	flash.texture = texture
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.shaded = false
	flash.no_depth_test = true
	flash.pixel_size = 0.001
	flash.modulate = Color(1.0, 1.0, 1.0, 0.0)
	flash.scale = Vector3.ONE * 0.0533333
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.layers = VIEWMODEL_LAYER
	flash.visible = false

	# Спрайт закріплений на точці дула: не шукає позицію заново під час пострілу.
	if is_instance_valid(m4_muzzle_point):
		m4_muzzle_point.add_child(flash)
	else:
		add_child(flash)
	_m4_muzzle_flash = flash
	return flash


func _play_m4_muzzle_flash() -> void:
	if not _has_authority() or not is_instance_valid(m4_holder):
		return
	var flash := _get_or_create_m4_muzzle_flash()
	if flash == null:
		return

	flash.position = Vector3.ZERO
	flash.rotation = Vector3.ZERO

	if _m4_muzzle_flash_tween and _m4_muzzle_flash_tween.is_running():
		_m4_muzzle_flash_tween.kill()

	flash.visible = true
	flash.modulate = Color.WHITE
	flash.scale = Vector3.ONE * 0.0533333

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "scale", Vector3.ONE * 0.0733333, 0.075)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.075)
	tween.tween_callback(func():
		if is_instance_valid(flash):
			flash.visible = false
	)
	_m4_muzzle_flash_tween = tween

func _collect_m4_meshes(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_collect_m4_meshes(child, result)


func _spawn_bullet_tracer(spawn_pos: Vector3, direction: Vector3, is_sniper: bool, is_m4: bool = false) -> void:
	var dir: Vector3 = direction.normalized()
	if dir.length() < 0.001:
		dir = -global_transform.basis.z

	var end_pos: Vector3 = _get_tracer_end_point(spawn_pos, dir)
	var start_pos: Vector3 = spawn_pos + dir * 0.55
	var muzzle_node: Node3D = sniper_muzzle if is_sniper else muzzle
	if is_m4 and _has_authority():
		# Візуальний трасер M4 починається з переднього кінця її моделі,
		# а не з маркера MuzzlePoint автомата AK-47.
		start_pos = _find_m4_muzzle_world_position()
	elif _has_authority() and sniper_scope_level == 0 and is_instance_valid(muzzle_node):
		start_pos = muzzle_node.global_position

	var dist: float = start_pos.distance_to(end_pos)
	if dist < 0.15:
		return

	var parent_node: Node = Matchmaker.room_of(self)
	if parent_node == null:
		parent_node = get_tree().current_scene
	if parent_node == null:
		return

	var streak_len: float = minf(dist, 7.5 if is_sniper else 4.5)
	var thickness: float = 0.02 if is_sniper else 0.012
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, streak_len)
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.90, 0.60, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.80, 0.40)
	mat.emission_energy_multiplier = 2.2
	tracer.material_override = mat

	parent_node.add_child(tracer)
	var travel_dir: Vector3 = (end_pos - start_pos).normalized()
	var fly_from: Vector3 = start_pos + travel_dir * (streak_len * 0.5)
	var fly_to: Vector3 = end_pos - travel_dir * (streak_len * 0.5)
	tracer.global_position = fly_from
	var up_vec: Vector3 = Vector3.RIGHT if absf(travel_dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	tracer.look_at(end_pos, up_vec)

	var speed: float = 420.0 if is_sniper else 260.0
	var fly_time: float = clampf(dist / speed, 0.025, 0.14)
	var tw := tracer.create_tween()
	tw.set_parallel(true)
	tw.tween_property(tracer, "global_position", fly_to, fly_time)
	tw.tween_property(mat, "albedo_color:a", 0.0, fly_time).set_delay(fly_time * 0.4)
	tw.chain().tween_callback(tracer.queue_free)


func _get_tracer_end_point(from: Vector3, dir: Vector3) -> Vector3:
	var max_dist: float = maxf(max_shoot_distance, 1000.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var ex: Array[RID] = _hitscan_exclude()
	query.exclude = ex

	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)
	var guard: int = 0
	while result and not (result.get("collider") is Hitbox) \
			and result.get("collider") is CharacterBody3D \
			and (result.get("collider") as Node).has_method("take_damage") and guard < 8:
		ex.append((result.get("collider") as CollisionObject3D).get_rid())
		query.exclude = ex
		result = space_state.intersect_ray(query)
		guard += 1

	if result:
		return result.get("position")
	return from + dir * max_dist


# Повертає/створює Sprite3D зі спалахом на кінці ствола.
func _get_or_create_muzzle_flash(is_sniper: bool) -> Sprite3D:
	var muzzle_node: Node3D = sniper_muzzle if is_sniper else muzzle
	if muzzle_node == null:
		return null

	var flash: Sprite3D = _sniper_muzzle_flash if is_sniper else _ak_muzzle_flash
	if is_instance_valid(flash):
		return flash

	if not ResourceLoader.exists(MUZZLE_FLASH_TEXTURE_PATH):
		push_warning("Не знайдено текстуру спалаху: %s" % MUZZLE_FLASH_TEXTURE_PATH)
		return null

	var texture := load(MUZZLE_FLASH_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("Не вдалося завантажити текстуру спалаху: %s" % MUZZLE_FLASH_TEXTURE_PATH)
		return null

	flash = Sprite3D.new()
	flash.name = "MuzzleFlash"
	flash.texture = texture
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.shaded = false
	flash.no_depth_test = true
	flash.pixel_size = 0.001
	flash.modulate = Color(1.0, 1.0, 1.0, 0.0)
	flash.scale = Vector3.ONE * (0.55 if is_sniper else 0.42)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.layers = VIEWMODEL_LAYER
	flash.visible = false
	muzzle_node.add_child(flash)

	if is_sniper:
		_sniper_muzzle_flash = flash
	else:
		_ak_muzzle_flash = flash
	return flash


# Викликається з _spawn_bullet_rpc, тому ефект бачать і стрілець, і решта гравців.
func _play_weapon_muzzle_flash(is_sniper: bool) -> void:
	var flash := _get_or_create_muzzle_flash(is_sniper)
	if flash == null:
		return

	var old_tween: Tween = _sniper_muzzle_flash_tween if is_sniper else _ak_muzzle_flash_tween
	if old_tween and old_tween.is_running():
		old_tween.kill()

	flash.visible = true
	flash.modulate.a = 1.0
	flash.scale = Vector3.ONE * (0.55 if is_sniper else 0.42)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "scale", flash.scale * 1.35, 0.075)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.075)
	tween.tween_callback(func(): flash.visible = false)

	if is_sniper:
		_sniper_muzzle_flash_tween = tween
	else:
		_ak_muzzle_flash_tween = tween


# Збирає всі варіанти звуку: base.ogg/.mp3/.wav та base_1 ... base_9.
func _load_sound_variants(base: String) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	var names: Array[String] = [base]
	for i in range(1, 10):
		names.append("%s_%d" % [base, i])
	for n in names:
		for ext in SOUND_EXTENSIONS:
			if ResourceLoader.exists(n + ext):
				var st := load(n + ext) as AudioStream
				if st:
					result.append(st)
				break
	return result


# Звук пострілу: AudioStreamPlayer3D у кімнаті, сам видаляється після програвання.
# Кожного разу береться випадковий варіант запису + невелика зміна висоти.
func _play_shot_sound(pos: Vector3, is_sniper: bool) -> void:
	var stream: AudioStream = awp_shot_sound if is_sniper else ak_shot_sound   # ручне призначення з інспектора
	if stream == null:
		if is_sniper:
			if not _sounds_loaded_awp:
				_awp_sounds = _load_sound_variants(AWP_SHOT_BASE)
				_sounds_loaded_awp = true
			if not _awp_sounds.is_empty():
				stream = _awp_sounds[randi() % _awp_sounds.size()]
		else:
			if not _sounds_loaded_ak:
				_ak_sounds = _load_sound_variants(AK_SHOT_BASE)
				_sounds_loaded_ak = true
			if not _ak_sounds.is_empty():
				stream = _ak_sounds[randi() % _ak_sounds.size()]
	if stream == null:
		return
	var room: Node = Matchmaker.room_of(self)
	if room == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = shot_volume_db + randf_range(-1.0, 0.5)
	p.unit_size = 12.0
	p.max_distance = shot_max_distance
	p.pitch_scale = randf_range(0.97, 1.03)
	room.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------
# ХІТСКАН: миттєвий промінь замість кулі. Влучання лише по хітбоксах моделі (hitbox.gd).
# ------------------------------------------------------------------
func _hitscan_exclude() -> Array[RID]:
	var ex: Array[RID] = []
	if player_body != null:
		ex.append(player_body.get_rid())
		var boxes := player_body.get_node_or_null("Hitboxes")
		if boxes:
			for hb in boxes.get_children():
				if hb is CollisionObject3D:
					ex.append((hb as CollisionObject3D).get_rid())
	return ex


func _fire_hitscan(from: Vector3, direction: Vector3, shooter_id: int, damage: float) -> void:
	# Урон рахує лише той, хто стріляв; на решті клієнтів промінь не потрібен.
	if multiplayer.get_unique_id() != shooter_id:
		return
	var dir: Vector3 = direction.normalized()
	if dir.length() < 0.001:
		dir = -global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * maxf(max_shoot_distance, 1000.0))
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var ex: Array[RID] = _hitscan_exclude()
	query.exclude = ex

	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	# Капсула руху гравця для променя "прозора": б'ємо лише по хітбоксах моделі.
	var guard: int = 0
	while result and not (result.get("collider") is Hitbox) \
			and result.get("collider") is CharacterBody3D \
			and (result.get("collider") as Node).has_method("take_damage") and guard < 8:
		ex.append((result.get("collider") as CollisionObject3D).get_rid())
		query.exclude = ex
		result = space_state.intersect_ray(query)
		guard += 1

	if not result or not (result.get("collider") is Hitbox):
		return   # стіна/підлога/промах — урону немає

	var hb := result.get("collider") as Hitbox
	var target: Node = hb.owner_player
	if target == null or not target.has_method("take_damage"):
		return
	if "is_dead" in target and target.is_dead:
		return

	var final_damage: float
	if current_weapon == Weapon.M4:
		# M4: 60 у голову та 30 у будь-яку іншу частину тіла.
		# Не множимо на старі коефіцієнти Hitbox, щоб значення були точними.
		final_damage = m4_head_damage if hb.part_name.to_lower() == "head" else m4_damage
	else:
		final_damage = damage * hb.damage_multiplier
	target.take_damage(final_damage, shooter_id)
	_spawn_damage_popup(target, final_damage, hb.part_name == "head")
	_watch_for_kill(target, hb.part_name == "head", current_weapon)


# Урон показується біля прицілу (зліва або справа, випадково), а не над противником.
var _dmg_layer: CanvasLayer = null


func _spawn_damage_popup(_target: Node, amount: float, is_headshot: bool = false) -> void:
	_get_hud_layer()

	var label := Label.new()
	label.text = "-%d" % int(amount)
	label.add_theme_font_size_override("font_size", 34 if is_headshot else 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if is_headshot else Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 40)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_layer.add_child(label)

	# Центр екрана = приціл. Випадково ліворуч або праворуч + невеликий розкид.
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var offset := Vector2(side * randf_range(45.0, 95.0), randf_range(-45.0, 5.0))
	label.position = center + offset - label.custom_minimum_size * 0.5

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func _get_hud_layer() -> CanvasLayer:
	if _dmg_layer == null:
		_dmg_layer = CanvasLayer.new()
		_dmg_layer.layer = 5   # над зброєю та прицілом, під меню
		add_child(_dmg_layer)
	return _dmg_layer


# ------------------------------------------------------------------
# ВБИВСТВО: червоний хрестик на прицілі + картка знизу (як у CS2).
# Смерть цілі приходить від її власника по мережі, тому після влучання коротко
# чекаємо, чи ціль стала мертвою (is_dead), і тільки тоді показуємо ефект.
# ------------------------------------------------------------------
var _kill_watch_token: int = 0


func _watch_for_kill(target: Node, headshot: bool, weapon: int) -> void:
	_kill_watch_token += 1
	var token: int = _kill_watch_token
	var deadline: int = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if token != _kill_watch_token or not is_instance_valid(target):
			return
		if "is_dead" in target and target.is_dead:
			_kill_watch_token += 1   # одне вбивство — один ефект
			_spawn_kill_marker()
			# Картка серії вбивств підряд (HUD локального гравця).
			var chud := get_tree().get_first_node_in_group("combat_hud")
			if chud and chud.has_method("add_kill"):
				chud.call("add_kill", headshot)
			# Кіл-таб справа зверху бачать обидва гравці.
			Matchmaker.rpc_room(self, "_killfeed_rpc", [multiplayer.get_unique_id(), target.name.to_int(), _weapon_display_name(weapon), headshot], false)
			return


# ------------------------------------------------------------------
# КІЛ-ТАБ (справа зверху, як у CS2): хто кого вбив і з чого. Показується обом гравцям.
# Один спільний контейнер на всі копії скрипта, тож записи не накладаються.
# ------------------------------------------------------------------
const KILLFEED_MAX: int = 5
const KILLFEED_SHOW_TIME: float = 5.0
static var _killfeed_box: VBoxContainer = null


@rpc("call_local", "any_peer", "reliable")
func _killfeed_rpc(killer_id: int, victim_id: int, weapon_name: String, headshot: bool) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_add_killfeed_entry(_nick_of(killer_id), weapon_name, headshot, _nick_of(victim_id),
		killer_id == my_id, victim_id == my_id)


# Нік гравця з world.gd (id -> нік); якщо світ ще не готовий — "Player".
func _nick_of(id: int) -> String:
	var room := Matchmaker.room_of(self)
	var world := room.get_node_or_null("MAP/world") if room else null
	if world and world.has_method("get_nick"):
		return str(world.call("get_nick", id))
	return "Player"


func _get_killfeed_box() -> VBoxContainer:
	if is_instance_valid(_killfeed_box):
		return _killfeed_box
	var layer := CanvasLayer.new()
	layer.layer = 6
	get_tree().root.add_child(layer)

	# Контейнер на весь екран з відступами від краю: записи завжди притиснуті до ПРАВОГО ВЕРХНЬОГО кута.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_END     # праворуч
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN     # зверху
	margin.add_child(box)
	_killfeed_box = box
	return box


func _add_killfeed_entry(killer: String, weapon_name: String, headshot: bool, victim: String, killer_is_me: bool = false, victim_is_me: bool = false) -> void:
	var box := _get_killfeed_box()
	# Лишаємо не більше KILLFEED_MAX записів: найстаріший зникає.
	while box.get_child_count() >= KILLFEED_MAX:
		var oldest := box.get_child(0)
		box.remove_child(oldest)
		oldest.queue_free()

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	sb.border_color = Color(0.92, 0.16, 0.16)   # у 1х1 кожне вбивство стосується тебе
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(_kill_label(killer, 20, Color(1.0, 0.85, 0.3) if killer_is_me else Color.WHITE))
	# Замість слів — іконки: постріл (куля) або ніж, і голова при хедшоті.
	row.add_child(_make_kill_icon(KillIcon.Kind.KNIFE if weapon_name == "Ніж" else KillIcon.Kind.BULLET))
	if headshot:
		row.add_child(_make_kill_icon(KillIcon.Kind.HEAD))
	row.add_child(_kill_label(victim, 20, Color(1.0, 0.85, 0.3) if victim_is_me else Color(1.0, 0.45, 0.45)))

	box.add_child(panel)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(KILLFEED_SHOW_TIME)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


# Кіл-таб: "<нік> left the game" (викликається з world.gd, коли суперник вийшов).
func show_left_message(nick: String) -> void:
	var box := _get_killfeed_box()
	while box.get_child_count() >= KILLFEED_MAX:
		var oldest := box.get_child(0)
		box.remove_child(oldest)
		oldest.queue_free()

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	sb.border_color = Color(0.6, 0.6, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(_kill_label(nick, 20, Color(1.0, 0.45, 0.45)))
	row.add_child(_kill_label("left the game", 18, Color(0.8, 0.82, 0.88)))

	box.add_child(panel)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(KILLFEED_SHOW_TIME)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


func _weapon_display_name(weapon: int) -> String:
	match weapon:
		Weapon.AK47:
			return "AK-47"
		Weapon.SNIPER:
			return "AWP"
		Weapon.M4:
			return "M4"
	return "Ніж"


# Червоний хрестик по центру екрана: «вистрибує» і тане.
func _spawn_kill_marker() -> void:
	var layer := _get_hud_layer()
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size = Vector2(90, 90)
	m.pivot_offset = Vector2(45, 45)
	m.position = get_viewport().get_visible_rect().size * 0.5 - Vector2(45, 45)
	m.draw.connect(func():
		var c := Vector2(45, 45)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = (d as Vector2).normalized()
			m.draw_line(c + dir * 11.0, c + dir * 29.0, Color(0, 0, 0, 0.9), 8.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = (d as Vector2).normalized()
			m.draw_line(c + dir * 12.0, c + dir * 28.0, Color(1.0, 0.12, 0.12), 4.0))
	layer.add_child(m)

	m.scale = Vector2(1.9, 1.9)
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(m, "modulate:a", 0.0, 0.3)
	tw.tween_callback(m.queue_free)



# Власні PNG (необов'язково): якщо покласти файли в res://textures/kill_hud/ —
# вони замінять намальовані іконки: icon_shot.png, icon_knife.png, icon_headshot.png.
const KILL_ICON_DIR := "res://textures/kill_hud/"
const KILL_ICON_FILES: Array[String] = ["icon_shot.png", "icon_knife.png", "icon_headshot.png"]
const KILL_ICON_HEIGHT: float = 24.0


func _make_kill_icon(kind: int) -> Control:
	var path: String = KILL_ICON_DIR + KILL_ICON_FILES[kind]
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.custom_minimum_size = Vector2(KILL_ICON_HEIGHT * tex.get_width() / maxf(tex.get_height(), 1.0), KILL_ICON_HEIGHT)
			tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return tr
	var icon := KillIcon.new(kind)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


# Іконки кіл-табу, намальовані кодом (без зовнішніх файлів).
class KillIcon extends Control:
	enum Kind { BULLET, KNIFE, HEAD }
	var kind: int = Kind.BULLET

	func _init(k: int = Kind.BULLET) -> void:
		kind = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(28, 28) if k == Kind.HEAD else Vector2(32, 18)

	func _shape(points: PackedVector2Array, fill: Color) -> void:
		draw_colored_polygon(points, fill)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(0, 0, 0, 0.9), 1.5)

	func _draw() -> void:
		match kind:
			Kind.BULLET:
				# Куля, летить праворуч: гільза + загострений носик.
				_shape(PackedVector2Array([Vector2(2, 4), Vector2(18, 4), Vector2(18, 14), Vector2(2, 14)]), Color(0.86, 0.66, 0.26))
				_shape(PackedVector2Array([Vector2(18, 4), Vector2(24, 5), Vector2(30, 9), Vector2(24, 13), Vector2(18, 14)]), Color(0.92, 0.93, 0.97))
				draw_line(Vector2(4.5, 4.5), Vector2(4.5, 13.5), Color(0.45, 0.32, 0.1), 2.0)
			Kind.KNIFE:
				# Ніж лезом праворуч: руків'я, гарда, лезо.
				_shape(PackedVector2Array([Vector2(1, 6), Vector2(9, 6), Vector2(9, 12), Vector2(1, 12)]), Color(0.38, 0.26, 0.16))
				_shape(PackedVector2Array([Vector2(9, 4), Vector2(11, 4), Vector2(11, 14), Vector2(9, 14)]), Color(0.86, 0.66, 0.26))
				_shape(PackedVector2Array([Vector2(11, 5), Vector2(25, 5), Vector2(31, 11), Vector2(11, 12)]), Color(0.88, 0.9, 0.95))
			Kind.HEAD:
				# Голова з плечима та червоним прицілом (хедшот).
				_shape(PackedVector2Array([Vector2(3, 27), Vector2(4, 21), Vector2(9, 17), Vector2(19, 17), Vector2(24, 21), Vector2(25, 27)]), Color(0.78, 0.8, 0.86))
				draw_circle(Vector2(14, 11), 7.0, Color(0.92, 0.93, 0.97))
				draw_arc(Vector2(14, 11), 7.0, 0.0, TAU, 24, Color(0, 0, 0, 0.9), 1.5)
				var red := Color(1.0, 0.2, 0.2)
				draw_arc(Vector2(14, 11), 10.0, 0.0, TAU, 32, red, 2.0)
				draw_line(Vector2(14, -1), Vector2(14, 4), red, 2.0)
				draw_line(Vector2(0, 11), Vector2(5, 11), red, 2.0)
				draw_line(Vector2(23, 11), Vector2(28, 11), red, 2.0)


func _kill_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


# Скидає масштаб кореневого вузла кулі та всіх CollisionShape3D всередині на (1, 1, 1).
# Візуальні меші НЕ чіпаємо — якщо хочеш витягнутий трасер, масштабуй MeshInstance3D
# прямо в bullet.tscn, і він збережеться.
func _sanitize_bullet_scale(root: Node) -> void:
	if root is Node3D:
		(root as Node3D).scale = Vector3.ONE
	_reset_collision_scales(root)


func _reset_collision_scales(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			(child as Node3D).scale = Vector3.ONE
		_reset_collision_scales(child)


func _apply_recoil() -> void:
	_time_since_last_shot = 0.0
	var step: Vector2
	var up_scale: float = 1.0
	var side_scale: float = 1.0
	if current_weapon == Weapon.M4:
		var idx_m4: int = clampi(m4_shot_count, 0, M4_SPRAY_PATTERN.size() - 1)
		step = M4_SPRAY_PATTERN[idx_m4]
		up_scale = m4_recoil_up_multiplier
		side_scale = m4_recoil_side_multiplier
	else:
		var idx: int = clampi(shot_count, 0, AK_SPRAY_PATTERN.size() - 1)
		step = AK_SPRAY_PATTERN[idx]

	var kick_up: float = deg_to_rad(step.x * recoil_kick_up_deg * up_scale)
	var kick_side: float = deg_to_rad(step.y * recoil_kick_side_deg * side_scale)
	recoil_target += Vector2(kick_up, kick_side)


func reload() -> void:
	if (reserve_ammo <= 0 and not infinite_reserve_ammo) or ammo_in_mag == mag_size:
		return

	# Переривати осмотр і при перезарядці, щоб анімації не накладались
	if is_inspecting and ak47_inspect_anim:
		ak47_inspect_anim.stop()
		is_inspecting = false

	is_reloading = true
	can_shoot = false

	if ak47_reload_anim:
		var reload_anim_name: String = ""
		for anim_name in ak47_reload_anim.get_animation_list():
			if anim_name != "RESET":
				reload_anim_name = anim_name
				break
		if reload_anim_name != "":
			ak47_reload_anim.stop()
			ak47_reload_anim.play(reload_anim_name)

	await get_tree().create_timer(reload_time).timeout

	var needed: int = mag_size - ammo_in_mag
	var take: int = needed if infinite_reserve_ammo else min(needed, reserve_ammo)
	ammo_in_mag += take
	if not infinite_reserve_ammo:
		reserve_ammo -= take

	# Перезарядка дає "чистий" магазин — без розкиду, накопиченого
	# з попередньої черги/магазину.
	current_spread_deg = 0.0
	shot_count = 0

	_update_ammo_hud()

	is_reloading = false
	can_shoot = true


# Повне поповнення магазину й запасних патронів. Викликається сервером
# (world.gd) при кожному спавні/респауні гравця — і в розминці, і на
# початку кожного нового раунду справжнього матчу.
@rpc("any_peer", "call_local", "reliable")
func _reset_ammo_rpc() -> void:
	ammo_in_mag = mag_size
	reserve_ammo = mag_size * (mag_count - 1)
	is_reloading = false
	can_shoot = true
	shot_count = 0
	current_spread_deg = 0.0
	sniper_ammo_in_mag = sniper_mag_size
	sniper_reserve = sniper_reserve_total
	m4_ammo_in_mag = m4_mag_size
	m4_reserve = m4_reserve_total
	m4_shot_count = 0
	_sniper_reload_id += 1
	_sniper_next_shot_ms = 0
	if current_weapon == Weapon.SNIPER:
		_sniper_hold_pose()
	else:
		_sniper_reset_pose()
	if _has_authority() and current_weapon == Weapon.SNIPER:
		is_inspecting = false
	_set_scope(0)
	if _weapon_menu_open:
		_close_weapon_menu()

	if _has_authority():
		_update_ammo_hud()

	# Новий раунд / респавн: зброя «видається» заново — одразу граємо анімацію draw.
	_replay_draw()


# Повторно програє доставання зброї, що вже в руках (на старті кожного раунду).
func _replay_draw() -> void:
	_force_redraw = true
	_switch_weapon_rpc(current_weapon)
	_force_redraw = false


func _update_ammo_hud() -> void:
	if not ammo_label:
		return
	if current_weapon == Weapon.AK47:
		ammo_label.text = "%d / %d" % [ammo_in_mag, reserve_ammo]
	elif current_weapon == Weapon.SNIPER:
		ammo_label.text = "%d / %d" % [sniper_ammo_in_mag, sniper_reserve]
	elif current_weapon == Weapon.M4:
		ammo_label.text = "%d / %d" % [m4_ammo_in_mag, m4_reserve]


func _get_spread_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var total_spread_deg: float = base_spread_deg + current_spread_deg
	if current_weapon == Weapon.SNIPER:
		# Снайперка: без розкиду з прицілом, без прицілу — велика кучність; накопичення як у АК немає.
		total_spread_deg = 0.0 if sniper_scope_level > 0 else sniper_unscoped_spread_deg

	if player_body != null:
		if not player_body.is_on_floor():
			total_spread_deg += jump_spread_deg
		else:
			var horizontal_velocity: Vector3 = Vector3(player_body.velocity.x, 0.0, player_body.velocity.z)
			var speed_ratio: float = clamp(horizontal_velocity.length() / move_spread_speed_threshold, 0.0, 1.0)
			total_spread_deg += move_spread_deg * speed_ratio

	if total_spread_deg <= 0.0:
		return forward

	var spread_rad: float = deg_to_rad(total_spread_deg)

	var angle: float = randf_range(0.0, TAU)
	var radius: float = sqrt(randf()) * spread_rad

	var right: Vector3 = global_transform.basis.x
	var up: Vector3 = global_transform.basis.y

	var offset: Vector3 = (right * cos(angle) + up * sin(angle)) * radius

	return (forward + offset).normalized()


func _get_aim_point(direction: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var from: Vector3 = global_transform.origin
	var to: Vector3 = from + direction * max_shoot_distance

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = shoot_collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result:
		return result.position
	return to


# ------------------------------------------------------------------
# СКІНИ НА ЗБРОЮ (АК-47, AWP)
# Модель не має UV-розгортки, тому малюнок скіна (вид збоку) накладається шейдером
# проєкцією збоку: позиція на малюнку береться з розмірів моделі, а не з UV.
# Скін бачить лише власник (АК від першої особи) — тож по мережі його синхронізувати не треба.
# ------------------------------------------------------------------
const AK_SKIN_SHADER := preload("res://skins/skin_side_projection.gdshader")
const AK_SKIN_TEXTURES := {
	"ak47_samurai": preload("res://skins/ak47_samurai.png"),
	"awp_samurai": preload("res://skins/awp_samurai.png"),
}
var _ak_default_overrides: Dictionary = {}   # MeshInstance3D -> стандартний material_override (щоб скін можна було зняти)


func _apply_weapon_skin(root: Node3D, skin_id: String) -> void:
	if root == null:
		return
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	for mi in meshes:
		if not _ak_default_overrides.has(mi):
			_ak_default_overrides[mi] = (mi as MeshInstance3D).material_override
	if not AK_SKIN_TEXTURES.has(skin_id):   # "" або невідомий id -> стандартний вигляд
		for mi in meshes:
			(mi as MeshInstance3D).material_override = _ak_default_overrides[mi]
		return

	# Спільна «коробка» всіх деталей АК (в локальних координатах мешів).
	var box: AABB = (meshes[0] as MeshInstance3D).get_aabb()
	for i in range(1, meshes.size()):
		box = box.merge((meshes[i] as MeshInstance3D).get_aabb())

	# Осі моделі: найдовша — уздовж ствола, найкоротша — вшир, середня — вгору.
	var long_i := 0
	var wide_i := 0
	for i in 3:
		if box.size[i] > box.size[long_i]:
			long_i = i
		if box.size[i] < box.size[wide_i]:
			wide_i = i
	var up_i := 3 - long_i - wide_i

	var u_axis := Vector3.ZERO
	u_axis[long_i] = -1.0 if long_i == 2 else 1.0   # «вперед» у Godot = -Z, в FBX-координатах моделі = +Y
	var v_axis := Vector3.ZERO
	v_axis[up_i] = -1.0                             # на малюнку «вниз» = більше v
	var side_axis := Vector3.ZERO
	side_axis[wide_i] = 1.0

	var mat := ShaderMaterial.new()
	mat.shader = AK_SKIN_SHADER
	mat.set_shader_parameter("skin_texture", AK_SKIN_TEXTURES[skin_id])
	mat.set_shader_parameter("u_axis", u_axis)
	mat.set_shader_parameter("v_axis", v_axis)
	mat.set_shader_parameter("side_axis", side_axis)
	mat.set_shader_parameter("u_range", _axis_range(box, u_axis))
	mat.set_shader_parameter("v_range", _axis_range(box, v_axis))
	for mi in meshes:
		(mi as MeshInstance3D).material_override = mat


# (мінімум, розмір) значень dot(p, axis) по всій «коробці».
func _axis_range(box: AABB, axis: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in 8:
		var d := axis.dot(box.get_endpoint(i))
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, maxf(hi - lo, 0.0001))


# ------------------------------------------------------------------
# ВИБІР НОЖА: керамбіт / bolisong
# ------------------------------------------------------------------
func _use_bolisong() -> bool:
	return knife_skin == "bolisong" and bolisong != null and bolisong_anim != null


func _use_butterfly() -> bool:
	return knife_skin == "butterfly" and butterfly != null and butterfly_anim != null


func _use_m9() -> bool:
	return knife_skin == "m9" and m9 != null and m9_anim != null


func _apply_visibility() -> void:
	# Моделі від першої особи (АК, ножі, AWP, руки) бачить тільки їхній власник.
	# У чужого клієнта копія цього гравця має їх повністю сховані, інакше вони «висять у повітрі» біля нього.
	if not _has_authority():
		for item in [ak47, knife, bolisong, butterfly, m9, sniper_holder, m4_holder]:
			if item:
				item.visible = false
		if player_body != null:
			var remote_arms := player_body.get_node_or_null("head/arms") as Node3D
			if remote_arms:
				remote_arms.visible = false
		return
	var is_ak: bool = (current_weapon == Weapon.AK47)
	var is_kn: bool = (current_weapon == Weapon.KNIFE)
	var is_sn: bool = (current_weapon == Weapon.SNIPER)
	var is_m4: bool = (current_weapon == Weapon.M4)
	var bf: bool = knife_skin == "bolisong" and bolisong != null
	var bt: bool = knife_skin == "butterfly" and butterfly != null
	var m9v: bool = knife_skin == "m9" and m9 != null
	ak47.visible = is_ak
	knife.visible = is_kn and not bf and not bt and not m9v
	if bolisong:
		bolisong.visible = is_kn and bf
	if butterfly:
		butterfly.visible = is_kn and bt
	if m9:
		m9.visible = is_kn and m9v
	# Модель снайперки ховаємо, поки дивимось крізь приціл.
	if sniper_holder:
		sniper_holder.visible = is_sn and sniper_scope_level == 0
	if m4_holder:
		m4_holder.visible = is_m4
	_update_arms_visibility(is_sn)


# Гарантія: іншим гравцям (і мені) видно ТІЛЬКИ предмет, що зараз у руках.
# Викликається перед кожним малюванням кадру — вже після всіх анімацій і таймерів, тож
# жодна анімація/tween/запізнілий RPC не залишить показаним зайвий предмет.
func _enforce_held_only() -> void:
	if not is_inside_tree():
		return
	_apply_visibility()
	# Спалахи пострілу теж належать лише до зброї в руках.
	if is_instance_valid(_ak_muzzle_flash) and current_weapon != Weapon.AK47:
		_ak_muzzle_flash.visible = false
	if is_instance_valid(_sniper_muzzle_flash) and current_weapon != Weapon.SNIPER:
		_sniper_muzzle_flash.visible = false
	if is_instance_valid(_m4_muzzle_flash) and current_weapon != Weapon.M4:
		_m4_muzzle_flash.visible = false


# Руки завжди видимі для всіх видів зброї (ховаються лише під час зуму в приціл снайперки).
func _update_arms_visibility(is_sniper: bool) -> void:
	if player_body == null:
		return
	var arms := player_body.get_node_or_null("head/arms") as Node3D
	if arms == null:
		return

	if is_sniper and sniper_scope_level > 0:
		arms.visible = false
		_arms_hidden_by_sniper = true
	else:
		arms.visible = true
		_set_arms_descendants_visible(arms)
		_arms_hidden_by_sniper = false


func _capture_arms_default_poses() -> void:
	_arms_default_poses.clear()
	if player_body == null:
		return
	var arms := player_body.get_node_or_null("head/arms") as Node3D
	if arms == null:
		return
	for part_name in ["arm_L", "arm_R", "hand_L", "hand_R"]:
		var n := arms.find_child(part_name, true, false) as Node3D
		if n:
			_arms_default_poses.append([n, n.position, n.rotation])


func _restore_arms_default_poses() -> void:
	for entry in _arms_default_poses:
		var n: Node3D = entry[0]
		if is_instance_valid(n):
			n.position = entry[1]
			n.rotation = entry[2]


func _set_arms_descendants_visible(node: Node) -> void:
	# Відновлюємо видимість усіх 3D-вузлів усередині моделі рук.
	# Викликається перед малюванням кадру через _enforce_held_only().
	for child in node.get_children():
		if child is Node3D:
			(child as Node3D).visible = true
		_set_arms_descendants_visible(child)


# AnimationPlayer всередині імпортованої моделі (glb/fbx).
func _get_anim_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var ap := root.get_node_or_null("AnimationPlayer")
	if ap == null:
		ap = root.find_child("AnimationPlayer", true, false)
	return ap as AnimationPlayer


# Шукає анімацію, в назві якої є одне зі слів (без урахування регістру).
func _find_anim(player: AnimationPlayer, keywords: Array) -> String:
	if not player:
		return ""
	for anim_name in player.get_animation_list():
		if anim_name == "RESET":
			continue
		var low: String = String(anim_name).to_lower()
		for k in keywords:
			if low.contains(k):
				return anim_name
	return ""


func announce_knife_skin() -> void:
	if _has_authority():
		Matchmaker.rpc_room(self, "_set_knife_skin_rpc", [knife_skin], false)


@rpc("any_peer", "call_local", "reliable")
func _set_knife_skin_rpc(skin: String) -> void:
	if skin != "karambit" and skin != "bolisong" and skin != "butterfly" and skin != "m9":
		return
	knife_skin = skin
	_apply_visibility()


# F на bolisong: Inspect_Rollover
func _bolisong_inspect() -> void:
	var anim_name: String = "Inspect_Rollover"
	if not bolisong_anim.has_animation(anim_name):
		anim_name = _find_anim(bolisong_anim, ["inspect"])
	if anim_name == "":
		push_warning("У bolisong/AnimationPlayer немає анімації Inspect_Rollover!")
		return

	bolisong_anim.stop()
	bolisong_anim.play(anim_name)

	if _has_authority():
		is_inspecting = true
		await get_tree().create_timer(bolisong_anim.current_animation_length).timeout
		is_inspecting = false


# Удар bolisong: своя анімація (attack/stab/slash...), інакше — короткий помах.
func _bolisong_attack() -> void:
	if _has_authority():
		is_attacking = true
		is_inspecting = false

	var duration: float = 0.3
	var anim_name: String = _find_anim(bolisong_anim, ["attack", "stab", "slash", "swing", "hit"])
	if anim_name != "":
		bolisong_anim.stop()
		bolisong_anim.play(anim_name)
		duration = bolisong_anim.current_animation_length
	else:
		bolisong_anim.stop()
		bolisong.rotation = _bolisong_base_rot
		var t := create_tween()
		t.tween_property(bolisong, "rotation:x", _bolisong_base_rot.x + deg_to_rad(-40.0), 0.1)
		t.tween_property(bolisong, "rotation:x", _bolisong_base_rot.x, 0.2)

	if _has_authority():
		await get_tree().create_timer(duration).timeout
		is_attacking = false


# ------------------------------------------------------------------
# BUTTERFLY: Draw (діставання) + Inspect_Valorant (осмотр як у Valorant)
# ------------------------------------------------------------------
func _setup_butterfly_idle() -> void:
	if butterfly_anim and butterfly_anim.has_animation("Idle"):
		butterfly_anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR


func _butterfly_play_idle() -> void:
	if butterfly_anim and _use_butterfly() and current_weapon == Weapon.KNIFE and butterfly_anim.has_animation("Idle"):
		# 0.15 с blend — щоб перехід в Idle не був різким.
		butterfly_anim.play("Idle", 0.15)


# Зупиняє будь-яку анімацію butterfly і повертає ніж у базове положення.
# Inspect_Valorant має власні треки .:position/.:rotation, а в Idle їх немає —
# без цього після переривання ніж назавжди залишався б зсунутим.
func _butterfly_cancel() -> void:
	_butterfly_inspect_id += 1
	if butterfly_anim:
		butterfly_anim.stop()
	if butterfly:
		butterfly.position = _butterfly_base_pos
		butterfly.rotation = _butterfly_base_rot


# F на butterfly: Inspect_Valorant
func _butterfly_inspect() -> void:
	var anim_name: String = "Inspect_Valorant"
	if not butterfly_anim.has_animation(anim_name):
		anim_name = _find_anim(butterfly_anim, ["valorant", "inspect"])
	if anim_name == "":
		push_warning("У butterfly/AnimationPlayer немає анімації Inspect_Valorant!")
		return

	_butterfly_cancel()
	var my_id: int = _butterfly_inspect_id
	butterfly_anim.play(anim_name)

	if _has_authority():
		is_inspecting = true

	# Чекаємо на ВСІХ клієнтах (не лише в authority), щоб після осмотру скрізь
	# вмикався Idle. Враховуємо speed_scale плеєра.
	var duration: float = butterfly_anim.get_animation(anim_name).length / maxf(absf(butterfly_anim.speed_scale), 0.01)
	await get_tree().create_timer(duration).timeout

	# Осмотр перервали (удар / зміна зброї / новий осмотр) — таймер застарів.
	if my_id != _butterfly_inspect_id:
		return
	if _has_authority():
		is_inspecting = false
	_butterfly_play_idle()


# Удар butterfly: власної анімації удару в моделі немає — короткий помах.
func _butterfly_attack() -> void:
	if _has_authority():
		is_attacking = true
		is_inspecting = false

	_butterfly_cancel()
	if butterfly_anim.has_animation("Idle"):
		butterfly_anim.play("Idle")
	var t := create_tween()
	t.tween_property(butterfly, "rotation:x", _butterfly_base_rot.x + deg_to_rad(-40.0), 0.1)
	t.tween_property(butterfly, "rotation:x", _butterfly_base_rot.x, 0.2)

	if _has_authority():
		await get_tree().create_timer(0.3).timeout
		is_attacking = false


# ------------------------------------------------------------------
# КЕРАМБІТ: осмотр (F) — AnimationPlayer "осмотр" на вузлі Karanbit
# ------------------------------------------------------------------
# Запам'ятовуємо початкові position/rotation усіх вузлів, які чіпає осмотр
# (Karanbit, arm_R...), щоб після переривання вернути їх на місце.
func _capture_knife_inspect_base() -> void:
	_knife_inspect_base.clear()
	if not knife_inspect_anim:
		return
	var root: Node = knife_inspect_anim.get_node_or_null(knife_inspect_anim.root_node)
	if root == null:
		return
	var seen := {}
	for anim_name in knife_inspect_anim.get_animation_list():
		if anim_name == "RESET":
			continue
		var anim: Animation = knife_inspect_anim.get_animation(anim_name)
		for i in anim.get_track_count():
			var p: NodePath = anim.track_get_path(i)
			var prop: String = p.get_concatenated_subnames()
			if prop == "":
				continue
			var node: Node = root.get_node_or_null(NodePath(p.get_concatenated_names()))
			if node == null:
				continue
			var key: String = str(node.get_instance_id()) + ":" + prop
			if seen.has(key):
				continue
			seen[key] = true
			_knife_inspect_base.append([node, prop, node.get(prop)])


# Запам'ятовує початкові значення всіх вузлів/властивостей, які чіпають анімації плеєра.
func _capture_pose_base(player: AnimationPlayer) -> Array:
	var result: Array = []
	if player == null:
		return result
	var root: Node = player.get_node_or_null(player.root_node)
	if root == null:
		return result
	var seen := {}
	for anim_name in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		for i in anim.get_track_count():
			var p: NodePath = anim.track_get_path(i)
			var prop: String = p.get_concatenated_subnames()
			if prop == "":
				continue
			var names: String = p.get_concatenated_names()
			var node: Node = root if names == "" or names == "." else root.get_node_or_null(NodePath(names))
			if node == null:
				continue
			var key: String = str(node.get_instance_id()) + ":" + prop
			if seen.has(key):
				continue
			seen[key] = true
			result.append([node, prop, node.get_indexed(NodePath(prop))])
	return result


func _restore_pose_base(base: Array) -> void:
	for entry in base:
		var node: Node = entry[0]
		if is_instance_valid(node):
			node.set_indexed(NodePath(entry[1]), entry[2])


func _knife_inspect_restore() -> void:
	for entry in _knife_inspect_base:
		var node: Node = entry[0]
		if is_instance_valid(node):
			node.set(entry[1], entry[2])


# Зупиняє осмотр керамбіта і повертає ніж та руку в базове положення.
func _knife_inspect_cancel() -> void:
	_knife_inspect_id += 1
	if knife_inspect_anim and knife_inspect_anim.is_playing():
		knife_inspect_anim.stop()
		_knife_inspect_restore()


func _knife_inspect() -> void:
	if not knife_inspect_anim:
		push_warning("knife_inspect_anim (AnimationPlayer 'осмотр' у Karanbit) не знайдено!")
		return

	var anim_name: String = ""
	for n in knife_inspect_anim.get_animation_list():
		if n != "RESET":
			anim_name = n
			break
	if anim_name == "":
		push_warning("У Karanbit/осмотр немає жодної анімації окрім RESET!")
		return

	_knife_inspect_cancel()
	var my_id: int = _knife_inspect_id
	knife_inspect_anim.play(anim_name)

	if _has_authority():
		is_inspecting = true

	# Чекаємо на ВСІХ клієнтах, щоб скрізь після осмотру ніж став на місце.
	var duration: float = knife_inspect_anim.get_animation(anim_name).length / maxf(absf(knife_inspect_anim.speed_scale), 0.01)
	await get_tree().create_timer(duration).timeout

	# Осмотр перервали (удар / зміна зброї / новий осмотр) — таймер застарів.
	if my_id != _knife_inspect_id:
		return
	_knife_inspect_restore()
	if _has_authority():
		is_inspecting = false


# ------------------------------------------------------------------
# СНАЙПЕРКА (AWP)
# ------------------------------------------------------------------
func _ensure_input_action(action: String, key: Key = KEY_NONE, mouse: MouseButton = MOUSE_BUTTON_NONE) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	if key != KEY_NONE:
		var ek := InputEventKey.new()
		ek.physical_keycode = key
		InputMap.action_add_event(action, ek)
	if mouse != MOUSE_BUTTON_NONE:
		var em := InputEventMouseButton.new()
		em.button_index = mouse
		InputMap.action_add_event(action, em)


func _setup_m4() -> void:
	# 1) Вузол зі сцени (head/Camera3D/m4) — береться як є, з положенням, яке ви виставили в редакторі.
	for n in ["m4", "M4", "m4a1", "M4A1"]:
		m4_holder = get_node_or_null(n) as Node3D
		if m4_holder != null:
			break
	if m4_holder == null:
		# 2) Вузла немає — будуємо з моделі.
		var packed: PackedScene = m4_scene
		if packed == null:
			for path in M4_MODEL_PATHS:
				if ResourceLoader.exists(path):
					packed = load(path) as PackedScene
					break
		if packed == null:
			push_warning("Модель M4A1 не знайдена (шукав вузол 'm4' у камері та %s) — M4 вимкнено." % str(M4_MODEL_PATHS))
			return
		var model := packed.instantiate() as Node3D
		if model == null:
			push_warning("Модель M4A1 не вдалось завантажити як Node3D.")
			return
		m4_holder = Node3D.new()
		m4_holder.name = "m4"
		add_child(m4_holder)
		m4_holder.add_child(model)
		m4_holder.position = m4_view_position
		m4_holder.rotation_degrees = m4_view_rotation_deg
		m4_holder.scale = m4_view_scale
	# Точне кріплення спалаху для цієї моделі: ствол уздовж локальної осі +X.
	# Кінець ствола моделі знаходиться біля X=0.49, Y=0.28, Z=0.
	m4_muzzle_point = m4_holder.get_node_or_null("MuzzlePoint") as Marker3D
	if m4_muzzle_point == null:
		m4_muzzle_point = Marker3D.new()
		m4_muzzle_point.name = "MuzzlePoint"
		m4_holder.add_child(m4_muzzle_point)
	m4_muzzle_point.position = Vector3(0.515, 0.28, 0.0)
	_sniper_disable_shadows(m4_holder)   # просто вимикає тіні у всіх мешах вузла
	m4_holder.visible = false
	m4_anim = _get_anim_player(m4_holder)
	_m4_pose_base = _capture_pose_base(m4_anim)
	_m4_build_draw_animation()


# Запускає draw M4 з першого кадру. Повертає тривалість (с) або 0, якщо анімації немає.
func _m4_play_draw() -> float:
	_m4_reset_pose()
	if m4_anim == null or not m4_anim.has_animation(M4_ANIM_DRAW):
		return 0.0
	m4_anim.play(M4_ANIM_DRAW)
	m4_anim.seek(0.0, true)   # одразу застосувати стартовий кадр — без миготіння кінцевою позою
	return m4_anim.current_animation_length / maxf(absf(m4_anim.speed_scale), 0.01)


# Зупиняє анімацію й повертає M4 та руки в позу зі сцени.
func _m4_reset_pose() -> void:
	if m4_anim:
		m4_anim.stop()
	_restore_pose_base(_m4_pose_base)


# У сцені "draw" для M4 має лише один ключ (кінцева поза). Тут з нього робиться справжня анімація:
# кінцева поза (з вашого ключа) лишається цільовою, а на старті M4 і руки знизу.
# Якщо ви самі намалюєте в редакторі draw із кількома ключами — код її не чіпає.
func _m4_build_draw_animation() -> void:
	if m4_anim == null or not m4_anim.has_animation(M4_ANIM_DRAW):
		return
	var anim: Animation = m4_anim.get_animation(M4_ANIM_DRAW)
	for i in anim.get_track_count():
		if anim.track_get_key_count(i) > 1:
			return
	var root: Node = m4_anim.get_node_or_null(m4_anim.root_node)
	if root == null:
		return
	var cam_basis: Basis = global_transform.basis
	var t_end: float = M4_DRAW_TIME
	var t_land: float = M4_DRAW_TIME * 0.62
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_VALUE or anim.track_get_key_count(i) == 0:
			continue
		var p: NodePath = anim.track_get_path(i)
		var prop: String = p.get_concatenated_subnames()
		var names: String = p.get_concatenated_names()
		var node: Node = root if names == "" or names == "." else root.get_node_or_null(NodePath(names))
		if node == null or (prop != "position" and prop != "rotation"):
			continue
		var final_v: Vector3 = anim.track_get_key_value(i, anim.track_get_key_count(i) - 1)
		var start_v: Vector3 = final_v
		var land_v: Vector3 = final_v
		if node == m4_holder:
			if prop == "position":
				start_v = final_v + M4_DRAW_START_OFFSET
				land_v = final_v + Vector3(0.0, 0.018, 0.0)   # легкий «підскок» перед фіксацією
			else:
				start_v = final_v + M4_DRAW_START_ROT
				land_v = final_v + Vector3(0.0, 0.0, 0.05)
		elif prop == "position" and node is Node3D and node.get_parent() is Node3D:
			# Руки: «вниз» переводимо з простору камери в локальний простір батька руки.
			var par := node.get_parent() as Node3D
			start_v = final_v + par.global_transform.basis.inverse() * (cam_basis * M4_DRAW_ARMS_OFFSET)
		while anim.track_get_key_count(i) > 0:
			anim.track_remove_key(i, 0)
		anim.track_insert_key(i, 0.0, start_v, 0.4)      # швидкий старт, плавне гальмування
		anim.track_insert_key(i, t_land, land_v, 0.6)
		anim.track_insert_key(i, t_end, final_v, 1.0)
	anim.length = t_end
	anim.loop_mode = Animation.LOOP_NONE


func _setup_sniper() -> void:
	# 1) Вузол снайперки, уже доданий у сцену (у вас: head/Camera3D/awp) — беремо його як є,
	#    його положення в сцені стає «базовим».
	for n in ["awp", "AWP", "Awp"]:
		sniper_holder = get_node_or_null(n) as Node3D
		if sniper_holder != null:
			break

	if sniper_holder != null:
		sniper_muzzle = sniper_holder.get_node_or_null("MuzzlePoint") as Node3D
		if sniper_muzzle == null:
			var mm := Marker3D.new()
			mm.name = "MuzzlePoint"
			mm.position = sniper_muzzle_local
			sniper_holder.add_child(mm)
			sniper_muzzle = mm
	else:
		# 2) Вузла немає — будуємо з моделі (sniper_scene або файл у res://awp/).
		var packed: PackedScene = sniper_scene
		if packed == null:
			for path in SNIPER_MODEL_PATHS:
				if ResourceLoader.exists(path):
					packed = load(path) as PackedScene
					break
		if packed == null:
			push_warning("Модель снайперки не знайдена (шукав вузол 'awp' у камері та %s) — слот 3 вимкнено." % str(SNIPER_MODEL_PATHS))
			return
		var model := packed.instantiate() as Node3D
		if model == null:
			push_warning("Модель снайперки не вдалось завантажити як Node3D.")
			return
		sniper_holder = Node3D.new()
		sniper_holder.name = "AWP"
		add_child(sniper_holder)
		sniper_holder.add_child(model)
		sniper_holder.position = sniper_view_position
		sniper_holder.rotation_degrees = sniper_view_rotation_deg
		sniper_holder.scale = sniper_view_scale
		var m := Marker3D.new()
		m.name = "MuzzlePoint"
		m.position = sniper_muzzle_local
		sniper_holder.add_child(m)
		sniper_muzzle = m

	_sniper_disable_shadows(sniper_holder)
	sniper_anim = _find_sniper_anim_player(sniper_holder)
	if sniper_anim == null:
		push_warning("AnimationPlayer снайперки не знайдено (очікую head/Camera3D/awp/AnimationPlayer) — AWP буде без анімацій.")
	_sniper_pose_base = _capture_pose_base(sniper_anim)
	_sniper_hold_base = _capture_sniper_hold_pose()
	sniper_holder.visible = false


func _sniper_disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_sniper_disable_shadows(c)


func sniper_shoot() -> void:
	if _is_player_dead():
		return
	if sniper_holder == null or Time.get_ticks_msec() < _sniper_next_shot_ms or is_reloading or is_drawing:
		return
	if sniper_ammo_in_mag <= 0:
		if sniper_reserve > 0 or infinite_reserve_ammo:
			sniper_reload()
		return

	_sniper_cancel_inspect()
	_sniper_next_shot_ms = Time.get_ticks_msec() + int(sniper_fire_interval * 1000.0)
	sniper_ammo_in_mag -= 1
	_update_ammo_hud()
	var my_switch: int = _switch_id

	# Напрямок рахуємо ДО зняття прицілу (розкид залежить від нього).
	# Як і в АК: куля стартує з камери й летить точно в приціл.
	var direction: Vector3 = _get_spread_direction()
	var spawn_pos: Vector3 = global_transform.origin

	Matchmaker.rpc_room(self, "_spawn_bullet_rpc", [spawn_pos, direction, multiplayer.get_unique_id(), sniper_damage, sniper_bullet_speed], false)

	# Одна сильна віддача вгору (+ трохи вбік); відновлюється існуючою логікою recoil_target.
	_time_since_last_shot = 0.0
	recoil_target += Vector2(deg_to_rad(sniper_recoil_up_deg), deg_to_rad(randf_range(-0.3, 0.3)))

	# Після пострілу приціл знімається (як в CS). Анімація пострілу — лише якщо ви додали її
	# в AnimationPlayer (назва містить shoot / fire / bolt); якщо ні — нічого не граємо.
	_set_scope(0)
	var shot_length: float = _sniper_play(_find_anim(sniper_anim, ["shoot", "fire", "bolt"]))

	# Цикл між пострілами = довша з двох величин: sniper_fire_interval або анімація пострілу.
	var cycle: float = maxf(sniper_fire_interval, shot_length)
	_sniper_next_shot_ms = Time.get_ticks_msec() + int(cycle * 1000.0)

	await get_tree().create_timer(cycle).timeout
	if my_switch != _switch_id:
		return
	if sniper_ammo_in_mag <= 0 and (sniper_reserve > 0 or infinite_reserve_ammo) and current_weapon == Weapon.SNIPER and not is_reloading:
		sniper_reload()


func sniper_reload() -> void:
	if sniper_holder == null or is_reloading or is_drawing:
		return
	if (sniper_reserve <= 0 and not infinite_reserve_ammo) or sniper_ammo_in_mag >= sniper_mag_size:
		return
	_set_scope(0)
	_sniper_cancel_inspect()
	is_reloading = true
	_sniper_reload_id += 1
	var my_reload: int = _sniper_reload_id
	# Перезарядка триває рівно стільки, скільки йде анімація reload (з урахуванням speed_scale).
	var reload_length: float = _sniper_play(SNIPER_ANIM_RELOAD)
	if reload_length <= 0.0:
		reload_length = sniper_reload_time   # анімації немає — запасний час

	await get_tree().create_timer(reload_length).timeout
	if my_reload != _sniper_reload_id:
		return   # перемкнули зброю / респаун — перезарядку скасовано

	var needed_s: int = sniper_mag_size - sniper_ammo_in_mag
	var take: int = needed_s if infinite_reserve_ammo else mini(needed_s, sniper_reserve)
	sniper_ammo_in_mag += take
	if not infinite_reserve_ammo:
		sniper_reserve -= take
	is_reloading = false
	_update_ammo_hud()


# ---- приціл -------------------------------------------------------
func _cycle_scope() -> void:
	var next: int = sniper_scope_level + 1
	if next > sniper_zoom_fovs.size():
		next = 0
	_set_scope(next)


func _set_scope(level: int) -> void:
	if level == sniper_scope_level and fov == (_base_fov if level == 0 else sniper_zoom_fovs[level - 1]):
		return
	sniper_scope_level = level
	_apply_visibility()
	if not _has_authority():
		return
	fov = _base_fov if level == 0 else sniper_zoom_fovs[level - 1]

	# Чутливість миші падає пропорційно зуму.
	if player_body != null and "mouse_sensitivity" in player_body:
		if _base_mouse_sens < 0.0:
			_base_mouse_sens = player_body.mouse_sensitivity
		var ratio: float = 1.0
		if level > 0:
			ratio = tan(deg_to_rad(fov) * 0.5) / tan(deg_to_rad(_base_fov) * 0.5)
		player_body.mouse_sensitivity = _base_mouse_sens * ratio

	if _scope_layer:
		_scope_layer.visible = level > 0
	if crosshair:
		if level > 0 and crosshair.visible:
			crosshair.visible = false
			_crosshair_hidden_by_scope = true
		elif level == 0 and _crosshair_hidden_by_scope:
			crosshair.visible = true
			_crosshair_hidden_by_scope = false


# Накладка снайперського прицілу: чорне поле з колом і тонким перехрестям.
func _setup_scope_ui() -> void:
	if _scope_layer != null:
		return
	_scope_layer = CanvasLayer.new()
	_scope_layer.layer = 5
	_scope_layer.visible = false
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_scope.bind(overlay))
	overlay.resized.connect(overlay.queue_redraw)
	_scope_layer.add_child(overlay)
	add_child(_scope_layer)


func _draw_scope(overlay: Control) -> void:
	var size_v: Vector2 = overlay.size
	var center: Vector2 = size_v * 0.5
	var radius: float = size_v.y * 0.46
	var outer: float = size_v.length()
	var width: float = outer - radius
	overlay.draw_arc(center, radius + width * 0.5, 0.0, TAU, 160, Color.BLACK, width)
	overlay.draw_arc(center, radius, 0.0, TAU, 160, Color(0, 0, 0, 0.9), 3.0)
	overlay.draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), Color(0, 0, 0, 0.9), 1.5)
	overlay.draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), Color(0, 0, 0, 0.9), 1.5)
	overlay.draw_circle(center, 2.0, Color(1, 0.1, 0.1, 0.9))


# ---- анімації з AnimationPlayer у сцені ------------------------------
# Шукає AnimationPlayer всередині AWP (у вас: head/Camera3D/awp/AnimationPlayer).
func _find_sniper_anim_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var fallback: AnimationPlayer = null
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap.has_animation(SNIPER_ANIM_DRAW) or ap.has_animation(SNIPER_ANIM_RELOAD):
			return ap
		if fallback == null:
			fallback = ap
	return fallback


# Запускає анімацію з початкової пози. Повертає тривалість (с) або 0, якщо такої анімації немає.
func _sniper_play(anim_name: String) -> float:
	if sniper_anim == null or anim_name == "" or not sniper_anim.has_animation(anim_name):
		return 0.0
	_sniper_reset_pose()
	sniper_anim.play(anim_name)
	sniper_anim.seek(0.0, true)
	return sniper_anim.current_animation_length / maxf(absf(sniper_anim.speed_scale), 0.01)


# Зупиняє анімацію й повертає AWP та руки у початкове положення.
func _sniper_reset_pose() -> void:
	_sniper_inspect_id += 1   # будь-яке скидання робить застарілим таймер осмотру
	if sniper_anim:
		sniper_anim.stop()
	_restore_pose_base(_sniper_pose_base)


# Запам'ятовує останній кадр анімації draw для кожного треку (позиція/поворот AWP і рук) — це поза idle.
func _capture_sniper_hold_pose() -> Array:
	var result: Array = []
	if sniper_anim == null or not sniper_anim.has_animation(SNIPER_ANIM_DRAW):
		return result
	var anim: Animation = sniper_anim.get_animation(SNIPER_ANIM_DRAW)
	var root: Node = sniper_anim.get_node_or_null(sniper_anim.root_node)
	if root == null:
		return result
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		var key_count: int = anim.track_get_key_count(i)
		if key_count == 0:
			continue
		var p: NodePath = anim.track_get_path(i)
		var prop: String = p.get_concatenated_subnames()
		if prop == "":
			continue
		var names: String = p.get_concatenated_names()
		var node: Node = root if names == "" or names == "." else root.get_node_or_null(NodePath(names))
		if node == null:
			continue
		result.append([node, prop, anim.track_get_key_value(i, key_count - 1)])
	return result


# IDLE: зупиняє анімацію й ставить AWP та руки в позу «тримаю гвинтівку» (а не в стандартну позу сцени).
func _sniper_hold_pose() -> void:
	_sniper_inspect_id += 1   # як і при повному скиданні: старий таймер осмотру стає недійсним
	if sniper_anim:
		sniper_anim.stop()
	if _sniper_hold_base.is_empty():
		_restore_pose_base(_sniper_pose_base)   # запасний варіант: у плеєрі немає draw
	else:
		_restore_pose_base(_sniper_hold_base)


# Осмотр (клавіша F): анімація "view".
func _sniper_inspect() -> void:
	if sniper_anim == null or not sniper_anim.has_animation(SNIPER_ANIM_VIEW):
		push_warning("У AnimationPlayer снайперки немає анімації \"%s\"." % SNIPER_ANIM_VIEW)
		return
	var duration: float = _sniper_play(SNIPER_ANIM_VIEW)
	var my_id: int = _sniper_inspect_id
	if _has_authority():
		is_inspecting = true

	await get_tree().create_timer(duration).timeout
	# Осмотр перервали (постріл / перезарядка / приціл / зміна зброї) — таймер застарів.
	if my_id != _sniper_inspect_id:
		return
	_sniper_hold_pose()   # раніше тут було _sniper_reset_pose() -> руки стрибали в позу АК/ножа
	if _has_authority():
		is_inspecting = false


func _sniper_cancel_inspect() -> void:
	if sniper_anim and sniper_anim.is_playing() and sniper_anim.current_animation == SNIPER_ANIM_VIEW:
		_sniper_hold_pose()
	if _has_authority() and current_weapon == Weapon.SNIPER:
		is_inspecting = false


# ------------------------------------------------------------------
# МЕНЮ ВИБОРУ ОСНОВНОЇ ЗБРОЇ (клавіша E)
# ------------------------------------------------------------------
func _setup_weapon_menu() -> void:
	if _weapon_menu_layer != null:
		return
	_weapon_menu_layer = CanvasLayer.new()
	_weapon_menu_layer.layer = 10
	_weapon_menu_layer.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_weapon_menu_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Основна зброя (слот 1)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)

	for entry in [[Weapon.AK47, "AK-47"], [Weapon.M4, "M4"], [Weapon.SNIPER, "AWP"]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 90)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_on_weapon_menu_choice.bind(entry[0]))
		row.add_child(b)
		_weapon_menu_buttons[entry[0]] = [b, entry[1]]

	var hint := Label.new()
	hint.text = "E — закрити   |   1 — основна, 3 — ніж"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	add_child(_weapon_menu_layer)
	_refresh_weapon_menu()


func _refresh_weapon_menu() -> void:
	for w in _weapon_menu_buttons:
		var b: Button = _weapon_menu_buttons[w][0]
		var label: String = _weapon_menu_buttons[w][1]
		var picked: bool = (w == primary_weapon)
		b.text = ("✓ " if picked else "") + label
		if w == Weapon.SNIPER and sniper_holder == null:
			b.disabled = true
			b.text = label + " (немає моделі)"
		if w == Weapon.M4 and m4_holder == null:
			b.disabled = true
			b.text = label + " (немає моделі)"


func _open_weapon_menu() -> void:
	if _weapon_menu_layer == null or _weapon_menu_open:
		return
	_weapon_menu_open = true
	_set_scope(0)
	_refresh_weapon_menu()
	_weapon_menu_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_weapon_menu(recapture_mouse: bool = true) -> void:
	if not _weapon_menu_open:
		return
	_weapon_menu_open = false
	if _weapon_menu_layer:
		_weapon_menu_layer.visible = false
	if recapture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_weapon_menu_choice(weapon: Weapon) -> void:
	primary_weapon = weapon
	_close_weapon_menu()
	# Одразу беремо обрану зброю в руки (якщо вона ще не в руках).
	if not is_attacking:
		switch_weapon(primary_weapon)


# ------------------------------------------------------------------
# ЗБРОЯ ЗАВЖДИ ПОВЕРХ ЕКРАНА
# Моделі в руках (АК, ножі, AWP, руки) переносяться на окремий шар, який основна камера
# не малює. Їх малює друга камера в прозорому SubViewport, а результат кладеться
# поверх екрана — тож стіни/предмети ніколи не перекривають зброю.
# ------------------------------------------------------------------
func _set_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for c in node.get_children():
		_set_render_layer(c, layer)


func _setup_viewmodel_overlay() -> void:
	if _vm_viewport != null:
		return

	for root in [ak47, knife, bolisong, butterfly, m9, sniper_holder, m4_holder]:
		if root:
			_set_render_layer(root, VIEWMODEL_LAYER)
	if player_body != null:
		var arms := player_body.get_node_or_null("head/arms")
		if arms:
			_set_render_layer(arms, VIEWMODEL_LAYER)
	cull_mask &= ~VIEWMODEL_LAYER   # основна камера більше не малює зброю

	_vm_viewport = SubViewport.new()
	_vm_viewport.transparent_bg = true
	_vm_viewport.msaa_3d = get_viewport().msaa_3d
	_vm_viewport.handle_input_locally = false
	_vm_viewport.gui_disable_input = true
	_vm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vm_viewport.size = Vector2i(get_viewport().get_visible_rect().size)

	_vm_camera = Camera3D.new()
	_vm_camera.cull_mask = VIEWMODEL_LAYER
	_vm_camera.fov = _base_fov
	_vm_camera.keep_aspect = keep_aspect
	_vm_camera.near = 0.02
	_vm_camera.far = 20.0
	_vm_camera.environment = _make_viewmodel_environment()
	_vm_viewport.add_child(_vm_camera)

	var layer := CanvasLayer.new()
	layer.layer = 0   # під HUD (приціл, HP, рахунок), над 3D-сценою
	var tex := TextureRect.new()
	tex.texture = _vm_viewport.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(tex)
	layer.add_child(_vm_viewport)
	add_child(layer)
	_vm_camera.current = true

	get_viewport().size_changed.connect(_on_viewport_resized)


# Те саме освітлення, що й у світі, але з прозорим фоном (без неба й туману).
func _make_viewmodel_environment() -> Environment:
	var src: Environment = get_world_3d().environment
	var env: Environment
	if src != null:
		env = src.duplicate() as Environment
		if src.background_mode == Environment.BG_SKY:
			if src.ambient_light_source == Environment.AMBIENT_SOURCE_BG:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			if src.reflected_light_source == Environment.REFLECTION_SOURCE_BG:
				env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	else:
		env = Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.65)
		env.ambient_light_energy = 1.0
	env.background_mode = Environment.BG_CLEAR_COLOR
	return env


func _on_viewport_resized() -> void:
	if _vm_viewport:
		_vm_viewport.size = Vector2i(get_viewport().get_visible_rect().size)


# Камера зброї повторює позу основної камери (разом з віддачею).
func _sync_viewmodel_camera() -> void:
	if _vm_camera == null:
		return
	var gt: Transform3D = global_transform
	_vm_camera.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)


# ------------------------------------------------------------------
# M9 BAYONET: draw (діставання) + idle + view (осмотр, F) + короткий помах при ударі
# ------------------------------------------------------------------
func _setup_m9_idle() -> void:
	if m9_anim and m9_anim.has_animation("idle"):
		m9_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR


func _m9_play_idle() -> void:
	if m9_anim and _use_m9() and current_weapon == Weapon.KNIFE and m9_anim.has_animation("idle"):
		m9_anim.play("idle", 0.15)


# Зупиняє анімації M9 і повертає ніж та руки в базову позу.
func _m9_stop() -> void:
	_m9_action_id += 1
	if m9_anim:
		m9_anim.stop()
		_restore_pose_base(_m9_pose_base)
	if m9:
		m9.rotation = _m9_base_rot


func _m9_inspect() -> void:
	var anim_name: String = _find_anim(m9_anim, ["view", "inspect"])
	if anim_name == "":
		push_warning("У m9bayonet/AnimationPlayer немає анімації view!")
		return
	_m9_stop()
	var my_id: int = _m9_action_id
	m9_anim.play(anim_name)
	if _has_authority():
		is_inspecting = true
	var duration: float = m9_anim.get_animation(anim_name).length / maxf(absf(m9_anim.speed_scale), 0.01)
	await get_tree().create_timer(duration).timeout
	if my_id != _m9_action_id:
		return
	if _has_authority():
		is_inspecting = false
	_m9_play_idle()


# Окремої анімації удару в моделі немає — короткий помах.
func _m9_attack() -> void:
	if _has_authority():
		is_attacking = true
		is_inspecting = false
	_m9_action_id += 1
	var my_id: int = _m9_action_id
	# idle тримає rotation ножа, тому на час помаху його зупиняємо (поза лишається як є)
	if m9_anim:
		m9_anim.stop()
	var base_x: float = m9.rotation.x
	var t := create_tween()
	t.tween_property(m9, "rotation:x", base_x + deg_to_rad(-40.0), 0.1)
	t.tween_property(m9, "rotation:x", base_x, 0.2)
	await get_tree().create_timer(0.3).timeout
	if my_id != _m9_action_id:
		return
	if _has_authority():
		is_attacking = false
	_m9_play_idle()
