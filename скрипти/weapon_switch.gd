extends Camera3D

@onready var ak47: Node3D = $AK47
@onready var knife: Node3D = $Karanbit
@onready var ak47_anim: AnimationPlayer = $AK47/доставання
@onready var ak47_reload_anim: AnimationPlayer = $AK47/перезарядка
@onready var ak47_inspect_anim: AnimationPlayer = $AK47/осмотр
@onready var knife_anim: AnimationPlayer = $Karanbit/доставання
@onready var knife_attack_anim: AnimationPlayer = $Karanbit/удар
@onready var muzzle: Marker3D = $AK47/MuzzlePoint

var player_body: CharacterBody3D = null

enum Weapon { AK47, KNIFE }
var current_weapon: Weapon = Weapon.KNIFE

@export_category("Shooting Settings")
@export var bullet_scene: PackedScene
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
@export var max_spread_deg: float = 10.0
@export var spread_increase_per_shot: float = 1.2
@export var spread_recovery_speed: float = 5.0
@export var jump_spread_deg: float = 6.0

# Після цієї кількості пострілів у поточній черзі розкид починає рости
# набагато швидше (сильний "розсип" ближче до кінця довгої черги).
@export var shots_before_heavy_spread: int = 5
@export var heavy_spread_increase_per_shot: float = 3.0

@export var move_spread_deg: float = 8.0
@export var move_spread_speed_threshold: float = 3.0

@export_category("Recoil Settings")
@export var recoil_kick_up_deg: float = 1.4
@export var recoil_kick_side_deg: float = 0.6
@export var recoil_recovery_speed: float = 9.0

@export_category("Crosshair Settings")
@export var crosshair: Control
@export var crosshair_recoil_multiplier: float = 900.0
@export var crosshair_spread_multiplier: float = 300.0
@export var crosshair_follow_speed: float = 14.0

@export_category("HUD")
@export var ammo_label: Label

var can_shoot: bool = true
var is_reloading: bool = false
var is_drawing: bool = false
var is_attacking: bool = false
var is_inspecting: bool = false

var ammo_in_mag: int = 0
var reserve_ammo: int = 0

var current_spread_deg: float = 0.0
var recoil_current: Vector2 = Vector2.ZERO

# Лічильник пострілів у поточній черзі. Скидається на 0, щойно розкид
# повністю спадає до нуля (тобто пройшла пауза між чергами) — так наступна
# черга знову починається з точного 1-го пострілу.
var shot_count: int = 0

var crosshair_base_position: Vector2 = Vector2.ZERO
var crosshair_display_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			player_body = node
			break
		node = node.get_parent()

	if not _has_authority():
		set_process(false)
		set_process_unhandled_input(false)
		current = false
		return

	current = true

	if not ammo_label:
		var found = get_tree().get_first_node_in_group("ammo_label")
		if found and found is Label:
			ammo_label = found
		else:
			push_warning("ammo_label не знайдено ні в Інспекторі, ні по групі 'ammo_label'!")

	ammo_in_mag = mag_size
	reserve_ammo = mag_size * (mag_count - 1)

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


func _process(delta: float) -> void:
	if current_spread_deg > 0.0:
		# Зменшуємо розкид так, щоб він повністю обнулився рівно за 1.0 секунду
		# (або можете змінити 1.0 на інший час, наприклад, 0.5 для пів секунди)
		var reset_time: float = 1.0
		current_spread_deg = max(current_spread_deg - (max_spread_deg / reset_time) * delta, 0.0)

		if current_spread_deg <= 0.0:
			shot_count = 0

	if recoil_current.length() > 0.0001:
		var recovery: Vector2 = recoil_current * recoil_recovery_speed * delta
		if recovery.length() > recoil_current.length():
			recovery = recoil_current
		rotation.x -= recovery.x
		rotation.y -= recovery.y
		recoil_current -= recovery

	if full_auto and current_weapon == Weapon.AK47 and Input.is_action_pressed("shoot"):
		if can_shoot and not is_reloading and not is_drawing:
			shoot()

	_update_crosshair(delta)


func _update_crosshair(delta: float) -> void:
	if not crosshair:
		return

	var target_offset: Vector2 = Vector2(
		-recoil_current.y * crosshair_recoil_multiplier,
		-recoil_current.x * crosshair_recoil_multiplier
	)

	crosshair_display_offset = crosshair_display_offset.lerp(target_offset, clamp(crosshair_follow_speed * delta, 0.0, 1.0))
	crosshair.position = crosshair_base_position + crosshair_display_offset

	var spread_scale: float = 1.0 + deg_to_rad(current_spread_deg) * (crosshair_spread_multiplier / 100.0)
	crosshair.scale = Vector2(spread_scale, spread_scale)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weapon_2") and not is_attacking:
		switch_weapon(Weapon.AK47)
	elif event.is_action_pressed("weapon_1") and not is_attacking:
		switch_weapon(Weapon.KNIFE)

	if event.is_action_pressed("shoot"):
		if current_weapon == Weapon.AK47 and can_shoot and not is_reloading and not is_drawing:
			shoot()
		elif current_weapon == Weapon.KNIFE and not is_drawing and not is_attacking:
			knife_attack()

	if event.is_action_pressed("reload") and current_weapon == Weapon.AK47 and not is_reloading and not is_drawing:
		reload()

	if event.is_action_pressed("view"):
		if current_weapon == Weapon.AK47 and not is_drawing and not is_reloading and not is_inspecting:
			inspect_weapon()


func switch_weapon(weapon: Weapon) -> void:
	if current_weapon == weapon or is_attacking:
		return
	_switch_weapon_rpc.rpc(weapon)


@rpc("call_local", "any_peer", "reliable")
func _switch_weapon_rpc(weapon: Weapon) -> void:
	if current_weapon == weapon:
		return

	current_weapon = weapon
	ak47.visible = (weapon == Weapon.AK47)
	knife.visible = (weapon == Weapon.KNIFE)

	ak47.set_process(weapon == Weapon.AK47)
	ak47.set_physics_process(weapon == Weapon.AK47)
	ak47.set_process_unhandled_input(weapon == Weapon.AK47)

	knife.set_process(weapon == Weapon.KNIFE)
	knife.set_physics_process(weapon == Weapon.KNIFE)
	knife.set_process_unhandled_input(weapon == Weapon.KNIFE)

	# Якщо перемикаємо зброю під час осмотру АК47 — перериваємо осмотр
	if is_inspecting and ak47_inspect_anim:
		ak47_inspect_anim.stop()
		is_inspecting = false

	if weapon == Weapon.AK47:
		if knife_anim:
			knife_anim.stop()
		if ak47_anim:
			ak47_anim.stop()
			ak47_anim.play("knife1_Switch")
			if _has_authority():
				is_drawing = true
				var anim_length: float = ak47_anim.current_animation_length
				await get_tree().create_timer(anim_length).timeout
				is_drawing = false
		if _has_authority():
			_update_ammo_hud()
	elif weapon == Weapon.KNIFE:
		if ak47_anim:
			ak47_anim.stop()
		if knife_anim:
			knife_anim.stop()
			knife_anim.play("swichKNIFE")
			if _has_authority():
				is_drawing = true
				var anim_length: float = knife_anim.current_animation_length
				await get_tree().create_timer(anim_length).timeout
				is_drawing = false
		if _has_authority() and ammo_label:
			ammo_label.text = ""


func knife_attack() -> void:
	_knife_attack_rpc.rpc()


@rpc("call_local", "any_peer", "reliable")
func _knife_attack_rpc() -> void:
	if not knife_attack_anim:
		push_warning("knife_attack_anim (AnimationPlayer 'удар') не знайдено!")
		return

	if _has_authority():
		is_attacking = true

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
	_inspect_weapon_rpc.rpc()


@rpc("call_local", "any_peer", "reliable")
func _inspect_weapon_rpc() -> void:
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
	if not bullet_scene:
		push_warning("bullet_scene не встановлено в Інспекторі!")
		return

	# Миттєво перериваємо осмотр зброї, якщо стріляємо під час нього
	if ak47_inspect_anim and ak47_inspect_anim.is_playing():
		ak47_inspect_anim.stop()
		is_inspecting = false

	if ammo_in_mag <= 0:
		if reserve_ammo > 0:
			reload()
		return

	can_shoot = false
	ammo_in_mag -= 1
	_update_ammo_hud()

	var shoot_direction: Vector3 = _get_spread_direction()
	var target_point: Vector3 = _get_aim_point(shoot_direction)

	var spawn_pos: Vector3 = muzzle.global_transform.origin

	var direction: Vector3 = (target_point - spawn_pos).normalized()
	if direction.length() < 0.001:
		direction = shoot_direction

	# Спавнимо кулю на ВСІХ клієнтах через RPC (включно з тим, хто стріляв)
	_spawn_bullet_rpc.rpc(spawn_pos, direction, multiplayer.get_unique_id())

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


@rpc("call_local", "any_peer", "reliable")
func _spawn_bullet_rpc(spawn_pos: Vector3, direction: Vector3, shooter_id: int) -> void:
	var bullet = bullet_scene.instantiate()

	# ВИПРАВЛЕННЯ (Jolt): прибираємо нерівномірний масштаб ДО додавання в сцену,
	# щоб фізичний рушій ніколи не бачив scale (1, 1, 2.567).
	_sanitize_bullet_scale(bullet)

	get_tree().current_scene.add_child(bullet)

	# Чиста орієнтація без масштабу (замість look_at, який успадковує scale).
	var dir: Vector3 = direction.normalized()
	if dir.length() < 0.001:
		dir = -global_transform.basis.z
	# Якщо напрямок майже паралельний до UP — беремо запасну вісь, щоб не було помилки.
	var up_axis: Vector3 = Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.999:
		up_axis = Vector3.RIGHT
	bullet.global_transform = Transform3D(Basis.looking_at(dir, up_axis), spawn_pos)

	bullet.shooter_id = shooter_id
	bullet.shooter_body = player_body
	bullet.launch()


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
	var kick_up: float = deg_to_rad(recoil_kick_up_deg)
	var kick_side: float = deg_to_rad(randf_range(-recoil_kick_side_deg, recoil_kick_side_deg))

	rotation.x += kick_up
	rotation.y += kick_side

	recoil_current += Vector2(kick_up, kick_side)


func reload() -> void:
	if reserve_ammo <= 0 or ammo_in_mag == mag_size:
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
	var take: int = min(needed, reserve_ammo)
	ammo_in_mag += take
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

	if _has_authority():
		_update_ammo_hud()


func _update_ammo_hud() -> void:
	if ammo_label and current_weapon == Weapon.AK47:
		ammo_label.text = "%d / %d" % [ammo_in_mag, reserve_ammo]


func _get_spread_direction() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var total_spread_deg: float = base_spread_deg + current_spread_deg

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
