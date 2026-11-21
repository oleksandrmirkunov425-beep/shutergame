extends CharacterBody3D

@export_category("CS2 Movement Settings")
@export var max_speed: float = 5.5   # ≈ АК-47 у CS2 (215 u/s)
@export var walk_speed: float = 2.9   # Shift, ≈ 52% від бігу, як у CS2
@export var crouch_speed: float = 1.9   # присід, ≈ 34% від бігу, як у CS2
@export var jump_velocity: float = 5.6
@export var custom_gravity: float = 15.5
@export var ground_acceleration: float = 5.5
@export var air_acceleration: float = 80.0
@export var air_speed_cap: float = 1.1
@export var friction: float = 5.2
@export var stop_speed: float = 2.0

@export_category("Speed Limits")
@export var max_velocity: float = 13.0

@export_category("Jump & Crouch Settings")
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.08
@export var crouch_head_offset: float = 0.6   # = stand_height - crouch_height
@export var stand_height: float = 2.0          # висота капсули стоячи (перезаписується з капсули в _ready)
@export var crouch_height: float = 1.4         # висота капсули в присіді
@export var crouch_lerp_speed: float = 14.0
@export var reset_speed_on_jump: bool = false
@export var jump_speed_penalty: float = 1.0

@export_category("Camera Settings")
@export var mouse_sensitivity: float = 0.003
@export var max_look_angle: float = 89.0

@export_category("Health Settings")
@export var max_health: float = 100.0
@export var respawn_time: float = 3.0
@export var health_label: Label   # якщо не призначиш - шукаємо по групі "health_label"

@export_category("Death / Ragdoll Collision")
# Біт(и) шару, на якому стоять КОЛАЙДЕРИ ІНШИХ ГРАВЦІВ (не підлоги/стін!).
# Постав таке саме значення, як Layer гравця в інспекторі (Node -> CollisionObject3D -> Collision -> Layer).
# Після смерті цей біт прибирається з layer/mask тіла, щоб воно не штовхало
# й не блокувало інших гравців, але біти підлоги/світу лишаються — тому труп
# все одно падає на землю, а не провалюється під карту.
@export_flags_3d_physics var player_collision_layer: int = 2

var health: float = max_health
var is_dead: bool = false
var frozen: bool = false   # на старті раунду стоїмо 3-2-1 (ставить сервер через _set_frozen)
var last_attacker_id: int = -1

var _original_collision_layer: int
var _original_collision_mask: int

@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_anim: AnimationPlayer = $смерть
@onready var death_sound: AudioStreamPlayer3D = $deathSound
@onready var death_cam: Camera3D = get_node_or_null("deathcamera")

# Вся візуальна частина смерті (анімація + камера) живе в окремому скрипті.
const PlayerDeath := preload("res://скрипти/death.gd")
var _death: RefCounted = null

# Бойовий HUD (червоні краї при уроні, HP як у CS2, картки серії вбивств) — лише для власника.
const CombatHud := preload("res://скрипти/combat_hud.gd")
var _hud: CombatHud = null

# Меню паузи (ESC): Resume / Exit to Main Menu. Створюється лише для власника.
const PauseMenu := preload("res://скрипти/pause_menu.gd")
var _pause_menu: PauseMenu = null

# true, поки відкрите меню паузи — керування персонажем і зброєю вимкнене.
var paused: bool:
	get:
		return _pause_menu != null and _pause_menu.is_open

# ---- Команди (КТ / Т) ----
# Команду визначає сервер (world.gd) і надсилає через _set_team().
enum Team { CT, T }
var team: int = -1   # -1 = ще не отримали від сервера

# Одна модель тіла на обидві команди (голова/тулуб/руки/ноги — окремі вузли). За командою міняється
# лише текстура (скін): player_skin_t.png / player_skin_ct.png, див. _apply_model_skin().
@onready var model: Node3D = get_node_or_null("player_model")
const SKIN_TEX_T := preload("res://playersModels/player_skin_t.png")
const SKIN_TEX_CT := preload("res://playersModels/player_skin_ct.png")
var _skin_mats: Dictionary = {}   # команда -> StandardMaterial3D
# Одні руки на обидві команди: всі анімації прив'язані до цього вузла.
# За командою міняються лише меші та матеріали (скін), див. _apply_arms_skin().
@onready var arms_node: Node3D = get_node_or_null("head/arms")

const ARMS_SCENE_T := preload("res://playersModels/terrorist_t1_arms.glb")
const ARMS_SCENE_CT := preload("res://playersModels/operative_ct1_arms.glb")
const ARM_PARTS := ["arm_L", "hand_L", "arm_R", "hand_R"]

var _mat_voxel: StandardMaterial3D
var _mat_glow: StandardMaterial3D

var gravity: float = custom_gravity
var jump_streak: int = 0
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _head_base_y: float = 0.607

# ---- Присідання ----
# crouching реплікується через MultiplayerSynchronizer (див. character.tscn),
# тому інші гравці теж бачать присід (колізія, модель, хітбокси).
var crouching: bool = false:
	set(value):
		crouching = value
		if _capsule != null:
			_apply_capsule()
var _capsule: CapsuleShape3D
var _crouch_k: float = 1.0   # поточний візуальний масштаб по висоті (1 = стоїть)
var _model_base: Dictionary = {}   # стояча поза моделей (запам'ятовується на самому початку _ready)


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	# Запам'ятовуємо стоячу позу моделей ДО будь-яких анімацій/скидань.
	if model != null:
		_model_base[model] = model.transform
	# Чужі копії гравця не повинні мати власного HUD: інакше в групах
	# (score_label, health_label...) з'являються чужі лейбли, і Hud оновлює не ті.
	if not is_multiplayer_authority():
		var other_ui := get_node_or_null("CanvasLayer")
		if other_ui:
			remove_child(other_ui)
			other_ui.queue_free()
	_death = PlayerDeath.new(self, death_anim, death_cam)
	Hitbox.build_for(self)   # хітбокси голови/тулуба/рук/ніг (на кожній копії гравця)
	gravity = custom_gravity
	# Ресурс форми спільний для всіх інстансів сцени -> робимо власну копію,
	# інакше всі гравці присідали б одночасно.
	_capsule = collision_shape.shape.duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule
	stand_height = _capsule.height
	_apply_capsule()
	_head_base_y = head.position.y
	health = max_health
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	# Поки команда невідома, обидві моделі сховані (оновиться в _set_team).
	_apply_team_visual()

	if not health_label:
		var found = get_tree().get_first_node_in_group("health_label")
		if found and found is Label:
			health_label = found

	# ВАЖЛИВО: цей блок виконується на КОЖНІЙ локальній копії ноди гравця,
	# на КОЖНОМУ піру — і для власної ноди (authority), і для чужих нод,
	# які цей пір лише спостерігає через реплікацію. Тобто коли клієнт B
	# отримує репліку гравця A від MultiplayerSpawner, у клієнта B теж
	# викликається цей _ready() для ноди гравця A — і саме тут B повідомляє
	# сервер "я вже реально бачу ноду гравця id в себе в дереві".
	#
	# Це потрібно, щоб сервер не слав _set_spawn_transform / _revive /
	# поповнення патронів "наосліп" одразу після спавну — раніше через це
	# траплялись помилки "Node not found", коли пакет ще не встиг дійти
	# і репліка ноди фізично не існувала на клієнті-отримувачі.
	# Синхронізація позиції — лише гравцям цієї кімнати.
	# Бот — локальна офлайн-нода, тому їй не потрібні мережевий synchronizer/RPC ready handshake.
	var world := _get_world()
	var local_bot_match := world != null and bool(world.get("bot_match"))
	if not bool(get_meta("is_bot", false)) and not local_bot_match:
		var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if sync:
			sync.public_visibility = false
			for id in Matchmaker.targets(self):
				sync.set_visibility_for(id, true)
		if world and world.has_method("_on_player_node_ready_rpc"):
			world._on_player_node_ready_rpc.rpc_id(1, name.to_int())

	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		set_physics_process(false)
		camera.current = false
		return

	camera.current = true
	camera.make_current()
	print("[player] local camera current=", camera.current, " player_id=", name, " position=", global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud = CombatHud.new()
	_hud.name = "CombatHud"
	add_child(_hud)
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	if health_label:
		health_label.visible = false   # старий "HP: 100" замінено новим HUD
	_update_health_hud()


func _get_world() -> Node:
	var room := Matchmaker.room_of(self)
	return room.get_node_or_null("MAP/world") if room else null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# ESC працює завжди (навіть коли гравця вбито).
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		return

	if is_dead or paused:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))


# ESC: закрити меню паузи -> або закрити меню зброї -> або відкрити меню паузи.
func _handle_escape() -> void:
	if _pause_menu == null:
		return
	if _pause_menu.is_open:
		_pause_menu.close()
		return
	if bool(camera.get("_weapon_menu_open")):
		camera.call("_close_weapon_menu")
		return
	_pause_menu.open()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_dead:
		_process_death_fall(delta)
		return

	if frozen:
		# Стоїмо на місці (можна лише крутити камеру), гравітація працює.
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= gravity * delta
		move_and_slide()
		return

	var input_dir := Vector2.ZERO if paused else Input.get_vector("a", "d", "w", "s")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var is_crouching := _update_crouch(Input.is_key_pressed(KEY_CTRL) and not paused)
	var is_walking := Input.is_key_pressed(KEY_SHIFT) and not is_crouching and not paused

	var target_head_y := _head_base_y - (crouch_head_offset if is_crouching else 0.0)
	head.position.y = lerpf(head.position.y, target_head_y, clampf(crouch_lerp_speed * delta, 0.0, 1.0))

	var target_speed := max_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_walking:
		target_speed = walk_speed

	if Input.is_action_just_pressed("ui_accept") and not paused:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	var on_floor := is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
		if velocity.y < 0.0:
			velocity.y = -0.1
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		jump_streak += 1
		velocity.y = jump_velocity

		if jump_streak > 1:
			var horizontal = Vector2(velocity.x, velocity.z)
			horizontal *= jump_speed_penalty
			velocity.x = horizontal.x
			velocity.z = horizontal.y

		if reset_speed_on_jump:
			var horizontal2 = Vector2(velocity.x, velocity.z)
			if horizontal2.length() > max_speed:
				horizontal2 = horizontal2.normalized() * max_speed
				velocity.x = horizontal2.x
				velocity.z = horizontal2.y

	if on_floor:
		if velocity.y <= 0.0:
			jump_streak = 0
		apply_friction(delta)
		accelerate(wish_dir, target_speed, ground_acceleration, delta, false)
	else:
		velocity.y -= gravity * delta
		accelerate(wish_dir, target_speed, air_acceleration, delta, true)

	clamp_max_velocity()
	move_and_slide()


# ---- Присідання ----

# Повертає true, якщо гравець зараз у присіді. Встати можна лише коли над головою є місце.
func _update_crouch(want_crouch: bool) -> bool:
	if want_crouch and not crouching:
		crouching = true
	elif not want_crouch and crouching:
		var diff := stand_height - crouch_height
		if not test_move(global_transform, Vector3.UP * diff):
			crouching = false
	return crouching


# Міняє висоту капсули; ноги лишаються на землі (капсулу зсуваємо вниз).
func _apply_capsule() -> void:
	_capsule.height = crouch_height if crouching else stand_height
	collision_shape.position.y = -(stand_height - _capsule.height) * 0.5


# Плавно підганяє модель і хітбокси під присід (працює на кожній копії гравця).
func _process(delta: float) -> void:
	if is_dead:
		return
	var target := (crouch_height / stand_height) if crouching else 1.0
	if is_equal_approx(_crouch_k, target):
		return
	_crouch_k = lerpf(_crouch_k, target, clampf(crouch_lerp_speed * delta, 0.0, 1.0))
	if absf(_crouch_k - target) < 0.002:
		_crouch_k = target
	_apply_crouch_visuals(_crouch_k)


# Стискає по висоті моделі команд і хітбокси відносно ніг.
func _apply_crouch_visuals(k: float) -> void:
	var feet_y := -stand_height * 0.5
	if model != null:
		var base: Transform3D = _model_base.get(model, model.transform)
		var squash := Transform3D(Basis.from_scale(Vector3(1.0, k, 1.0)), Vector3(0.0, feet_y * (1.0 - k), 0.0))
		model.transform = squash * base
	Hitbox.set_crouch(self, k, feet_y)


# Фізика "трупа": падає під гравітацією, гальмується тертям по горизонталі
# і зупиняється, щойно торкається підлоги/землі (шари світу лишились в mask).
func _process_death_fall(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	var speed = Vector2(velocity.x, velocity.z).length()
	if speed > 0.0:
		var drop = friction * delta
		var new_speed = max(speed - drop, 0.0)
		var scale_factor = new_speed / speed
		velocity.x *= scale_factor
		velocity.z *= scale_factor

	move_and_slide()


func apply_friction(delta: float) -> void:
	var speed = Vector2(velocity.x, velocity.z).length()
	if speed < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var control = speed if speed > stop_speed else stop_speed
	var drop = control * friction * delta
	var new_speed = max(speed - drop, 0.0)

	var scale_factor = new_speed / speed
	velocity.x *= scale_factor
	velocity.z *= scale_factor


func accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float, is_air: bool) -> void:
	if wish_dir == Vector3.ZERO:
		return

	var capped_wish_speed = wish_speed
	if is_air:
		capped_wish_speed = min(wish_speed, air_speed_cap)

	var current_speed = Vector2(velocity.x, velocity.z).dot(Vector2(wish_dir.x, wish_dir.z))
	var add_speed = capped_wish_speed - current_speed
	if add_speed <= 0:
		return

	var accel_speed = accel * capped_wish_speed * delta
	accel_speed = min(accel_speed, add_speed)

	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z


func clamp_max_velocity() -> void:
	var horizontal = Vector2(velocity.x, velocity.z)
	if horizontal.length() > max_velocity:
		horizontal = horizontal.normalized() * max_velocity
		velocity.x = horizontal.x
		velocity.z = horizontal.y


# ---- Здоров'я / урон / смерть / респаун (керується world.gd через раунди) ----

# true, якщо attacker_id — тіммейт цього гравця (по своїх урону немає).
func is_friendly_fire(attacker_id: int) -> bool:
	var world := _get_world()
	if world == null or not world.has_method("are_teammates"):
		return false
	return world.are_teammates(name.to_int(), attacker_id)


func take_damage(amount: float, attacker_id: int = -1) -> void:
	if is_dead:
		return
	if is_friendly_fire(attacker_id):
		return
	if bool(get_meta("is_bot", false)):
		_apply_damage(amount, attacker_id)
	elif is_multiplayer_authority():
		_apply_damage(amount, attacker_id)
	else:
		_apply_damage_rpc.rpc_id(get_multiplayer_authority(), amount, attacker_id)


@rpc("any_peer", "reliable")
func _apply_damage_rpc(amount: float, attacker_id: int) -> void:
	if is_multiplayer_authority():
		_apply_damage(amount, attacker_id)


@rpc("any_peer", "call_local", "reliable")
func _set_spawn_transform(t: Transform3D) -> void:
	global_transform = t
	velocity = Vector3.ZERO


func _apply_damage(amount: float, attacker_id: int = -1) -> void:
	if is_dead:
		return
	if is_friendly_fire(attacker_id):
		return

	last_attacker_id = attacker_id
	health -= amount
	health = max(health, 0.0)
	_update_health_hud()
	if _hud:
		_hud.on_damage(amount)

	if health <= 0.0:
		_die()


func _die() -> void:
	if _hud:
		_hud.on_death()   # скидає серію вбивств, червоні краї
	Matchmaker.rpc_room(self, "_set_dead_state", [true])
	Matchmaker.rpc_room(self, "_play_death_sound")

	# Прибираємо зіткнення саме з іншими гравцями (щоб труп їх не штовхав
	# і не блокував), але лишаємо решту шарів (світ/підлога/стіни) —
	# завдяки цьому тіло падає під гравітацією і лягає на землю, а не
	# провалюється крізь карту.
	collision_layer &= ~player_collision_layer
	collision_mask &= ~player_collision_layer

	if is_multiplayer_authority() and health_label:
		health_label.text = "Ви загинули..."

	if is_multiplayer_authority() or bool(get_meta("is_bot", false)):
		var world := _get_world()
		if world:
			if multiplayer.is_server():
				world.report_death(name.to_int(), last_attacker_id)
			elif world.has_method("_report_death_rpc"):
				world._report_death_rpc.rpc_id(1, name.to_int(), last_attacker_id)
	# Респаун більше НЕ відбувається тут — ним керує world.gd
	# на початку наступного раунду (через _revive + _set_spawn_transform).


@rpc("authority", "call_local", "reliable")
func _set_dead_state(value: bool) -> void:
	is_dead = value
	if value:
		# Перед анімацією смерті повертаємо стоячу позу моделі/хітбоксів.
		crouching = false
		_crouch_k = 1.0
		_apply_crouch_visuals(1.0)
	Hitbox.set_enabled(self, not value)   # труп не ловить кулі (на всіх клієнтах)
	if value and _death:
		_death.play()   # анімація смерті + камера (на всіх клієнтах)


@rpc("authority", "call_local", "reliable")
func _play_death_sound() -> void:
	if death_sound:
		death_sound.play()


@rpc("any_peer", "call_local", "reliable")
func _set_frozen(value: bool) -> void:
	frozen = value


@rpc("any_peer", "call_local", "reliable")
func _revive() -> void:
	if _death:
		_death.reset()

	Hitbox.set_enabled(self, true)
	crouching = false
	_crouch_k = 1.0
	_apply_crouch_visuals(1.0)
	# Повертаємо оригінальні шари зіткнення
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	velocity = Vector3.ZERO
	health = max_health
	is_dead = false
	if _hud:
		_hud.on_revive()
	last_attacker_id = -1

	_apply_team_visual()
	_update_health_hud()

	# Нагадуємо суперникові, який у мене ніж (на випадок, якщо пакет загубився).
	var weapon_node := get_node_or_null("head/Camera3D")
	if weapon_node and weapon_node.has_method("announce_knife_skin"):
		weapon_node.announce_knife_skin()


# Показує модель за командою. Власник свого гравця не бачить власне тіло
# (вид від першої особи), а чужого бачить у моделі його команди.
func _apply_team_visual() -> void:
	var is_local := is_multiplayer_authority()
	# Хітбокси підганяємо під модель команди (форма береться з вершин меша).
	if team == Team.CT or team == Team.T:
		_apply_model_skin()
		_apply_crouch_visuals(1.0)   # хітбокси підганяємо під модель у стоячій позі
		# Маска команди: у моделі є грані обох команд, хітбокс беремо тільки по гранях своєї.
		Hitbox.fit_to_model(self, model, 1 if team == Team.CT else 0)
		_apply_crouch_visuals(_crouch_k)
	if model:
		model.visible = (team == Team.CT or team == Team.T) and not is_local
	if arms_node:
		arms_node.visible = is_local and (team == Team.T or team == Team.CT)
		if arms_node.visible:
			_apply_arms_skin()


# Одна модель — два скіни. Текстура команди: колір граней своєї команди; грані, яких у команди
# немає (шолом CT, пов'язка T...), на її текстурі прозорі й відкидаються (alpha scissor).
func _apply_model_skin() -> void:
	if model == null:
		return
	var mat: StandardMaterial3D = _skin_mats.get(team)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_texture = SKIN_TEX_CT if team == Team.CT else SKIN_TEX_T
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.roughness = 0.85
		_skin_mats[team] = mat
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_surface_override_material(0, mat)


# Підміняє меші/матеріали рук під команду. Вузол "arms" та його
# arm_L/hand_L/arm_R/hand_R лишаються тими самими -> анімації спільні.
func _apply_arms_skin() -> void:
	if _mat_voxel == null:
		_mat_voxel = StandardMaterial3D.new()
		_mat_voxel.vertex_color_use_as_albedo = true
		_mat_voxel.roughness = 0.85
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.vertex_color_use_as_albedo = true
		_mat_glow.roughness = 0.2
		_mat_glow.emission_enabled = true
		_mat_glow.emission = Color(0.25, 0.55, 0.85)
		_mat_glow.emission_energy_multiplier = 1.4

	var src: Node = (ARMS_SCENE_CT if team == Team.CT else ARMS_SCENE_T).instantiate()
	# Імпортовані GLB можуть мати дублікати arm_L/arm_R у скелеті та візуальному меші.
	# Беремо перший вузол саме з MeshInstance3D і не затираємо вже робочий меш, якщо
	# у конкретному командному GLB частина назв відрізняється.
	for part in ARM_PARTS:
		var from := _find_mesh_part(src, part)
		var to := _find_mesh_part(arms_node, part)
		if to == null:
			continue
		if from != null and from.mesh != null:
			to.mesh = from.mesh
		if to.mesh != null:
			to.visible = true
			for i in to.mesh.get_surface_count():
				to.set_surface_override_material(i, _mat_glow if i == 1 else _mat_voxel)
	src.free()
	# У деяких імпортованих варіантах root/група лівої руки має власний visible=false.
	for side_name in ["arm_L", "arm_R", "hand_L", "hand_R"]:
		var side := arms_node.find_child(side_name, true, false)
		if side:
			side.visible = true

func _find_mesh_part(root: Node, part_name: String) -> MeshInstance3D:
	if root == null:
		return null
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_front()
		if current.name == part_name and current is MeshInstance3D:
			return current as MeshInstance3D
		for child in current.get_children():
			pending.append(child)
	return null


@rpc("any_peer", "call_local", "reliable")
func _set_team(value: int) -> void:
	team = value
	_apply_team_visual()


func _update_health_hud() -> void:
	if health_label and is_multiplayer_authority():
		health_label.text = "HP: %d" % int(health)
	if _hud and is_multiplayer_authority():
		_hud.set_health(health, max_health)
