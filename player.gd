extends CharacterBody3D

@export_category("CS2 Movement Settings")
@export var max_speed: float = 6.5
@export var walk_speed: float = 3.4
@export var crouch_speed: float = 2.8
@export var jump_velocity: float = 5.6
@export var custom_gravity: float = 15.5
@export var ground_acceleration: float = 12.5
@export var air_acceleration: float = 80.0
@export var air_speed_cap: float = 1.1
@export var friction: float = 6.5
@export var stop_speed: float = 2.0

@export_category("Speed Limits")
@export var max_velocity: float = 13.0

@export_category("Jump & Crouch Settings")
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.08
@export var crouch_head_offset: float = 0.38
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
var last_attacker_id: int = -1

var _original_collision_layer: int
var _original_collision_mask: int

@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_anim: AnimationPlayer = $смерть
@onready var death_sound: AudioStreamPlayer3D = $deathSound

# ---- Команди (КТ / Т) ----
# Команду визначає сервер (world.gd) і надсилає через _set_team().
enum Team { CT, T }
var team: int = -1   # -1 = ще не отримали від сервера

@onready var model_ct: Node3D = get_node_or_null("operative_ct1")
@onready var model_t: Node3D = get_node_or_null("terrorist_t1")

var gravity: float = custom_gravity
var jump_streak: int = 0
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _head_base_y: float = 0.607


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	gravity = custom_gravity
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
	var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync:
		sync.public_visibility = false
		for id in Matchmaker.targets(self):
			sync.set_visibility_for(id, true)

	var world := _get_world()
	if world and world.has_method("_on_player_node_ready_rpc"):
		world._on_player_node_ready_rpc.rpc_id(1, name.to_int())

	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		set_physics_process(false)
		camera.current = false
		return

	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_health_hud()


func _get_world() -> Node:
	var room := Matchmaker.room_of(self)
	return room.get_node_or_null("MAP/world") if room else null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_dead:
		_process_death_fall(delta)
		return

	var input_dir := Input.get_vector("a", "d", "w", "s")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var is_crouching := Input.is_key_pressed(KEY_CTRL)
	var is_walking := Input.is_key_pressed(KEY_SHIFT) and not is_crouching

	var target_head_y := _head_base_y - (crouch_head_offset if is_crouching else 0.0)
	head.position.y = lerpf(head.position.y, target_head_y, clampf(crouch_lerp_speed * delta, 0.0, 1.0))

	var target_speed := max_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_walking:
		target_speed = walk_speed

	if Input.is_action_just_pressed("ui_accept"):
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

func take_damage(amount: float, attacker_id: int = -1) -> void:
	if is_dead:
		return
	if is_multiplayer_authority():
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

	last_attacker_id = attacker_id
	health -= amount
	health = max(health, 0.0)
	_update_health_hud()

	if health <= 0.0:
		_die()


func _die() -> void:
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

	if death_anim:
		death_anim.stop()
		death_anim.play("player_Die")

	if is_multiplayer_authority():
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


@rpc("authority", "call_local", "reliable")
func _play_death_sound() -> void:
	if death_sound:
		death_sound.play()


@rpc("any_peer", "call_local", "reliable")
func _revive() -> void:
	if death_anim:
		death_anim.stop()
		death_anim.seek(0.0, true)

	# Повертаємо оригінальні шари зіткнення
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	velocity = Vector3.ZERO
	health = max_health
	is_dead = false
	last_attacker_id = -1

	_update_health_hud()

	# Нагадуємо суперникові, який у мене ніж (на випадок, якщо пакет загубився).
	var weapon_node := get_node_or_null("head/Camera3D")
	if weapon_node and weapon_node.has_method("announce_knife_skin"):
		weapon_node.announce_knife_skin()


# Показує модель за командою. Власник свого гравця не бачить власне тіло
# (вид від першої особи), а чужого бачить у моделі його команди.
func _apply_team_visual() -> void:
	var is_local := is_multiplayer_authority()
	if model_ct:
		model_ct.visible = (team == Team.CT) and not is_local
	if model_t:
		model_t.visible = (team == Team.T) and not is_local


@rpc("any_peer", "call_local", "reliable")
func _set_team(value: int) -> void:
	team = value
	_apply_team_visual()


func _update_health_hud() -> void:
	if health_label and is_multiplayer_authority():
		health_label.text = "HP: %d" % int(health)
