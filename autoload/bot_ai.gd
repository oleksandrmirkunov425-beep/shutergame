extends Node

# Tactical local bot controller. Runs only in the offline bot match.
const BOT_ID := 2
const PLAYER_ID := 1
const WALK_SPEED := 3.8
const RUN_SPEED := 5.2
const GRAVITY := 15.5
const OPTIMAL_MIN := 7.0
const OPTIMAL_MAX := 12.0
const VISION_RANGE := 55.0
const FIRE_INTERVAL := 0.23
const BODY_DAMAGE := 27.0

@export_range(0.1, 1.0, 0.05) var accuracy: float = 0.88
@export_range(0.05, 2.0, 0.05) var reaction_time: float = 0.16

var body: CharacterBody3D
var target: CharacterBody3D
var _fire_timer := 0.0
var _decision_timer := 0.0
var _strafe_sign := 1.0
var _rng := RandomNumberGenerator.new()
var _has_los := false
var _last_seen_position: Vector3 = Vector3.ZERO
var _lost_sight_timer := 0.0
var _burst_left := 0
var _burst_pause := 0.0
var _reposition_timer := 0.0
var _preferred_side := 1.0

func _ready() -> void:
	body = get_parent() as CharacterBody3D
	_rng.randomize()
	_fire_timer = reaction_time
	_decision_timer = _rng.randf_range(1.0, 2.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or bool(body.get("is_dead")):
		return
	if bool(body.get("frozen")):
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		_apply_gravity(delta)
		body.move_and_slide()
		return

	_find_target()
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		body.velocity.x = move_toward(body.velocity.x, 0.0, 10.0 * delta)
		body.velocity.z = move_toward(body.velocity.z, 0.0, 10.0 * delta)
		_apply_gravity(delta)
		body.move_and_slide()
		return

	var to_target := target.global_position - body.global_position
	var flat_to_target := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat_to_target.length()
	if distance > 0.05:
		_face_target(flat_to_target, to_target)
		_has_los = distance <= VISION_RANGE and _has_line_of_sight()
		if _has_los:
			_last_seen_position = target.global_position
			_lost_sight_timer = 0.0
		else:
			_lost_sight_timer += delta
		_move_tactically(flat_to_target.normalized(), distance, delta)
		_fire_timer -= delta
		_burst_pause -= delta
		if _has_los and _fire_timer <= 0.0 and _burst_pause <= 0.0:
			if _burst_left <= 0:
				_burst_left = _rng.randi_range(3, 5)
			_fire_at_target()
			_burst_left -= 1
			_fire_timer = FIRE_INTERVAL + _rng.randf_range(0.0, 0.045)
			if _burst_left <= 0:
				_burst_pause = _rng.randf_range(0.28, 0.55)
		elif not _has_los:
			_fire_timer = maxf(_fire_timer, 0.0)

	_apply_gravity(delta)
	body.move_and_slide()

func _find_target() -> void:
	if is_instance_valid(target) and not bool(target.get("is_dead")):
		return
	var room := Matchmaker.room_of(body)
	if room == null:
		return
	target = room.get_node_or_null("players/1") as CharacterBody3D

func _face_target(flat_dir: Vector3, full_dir: Vector3) -> void:
	var desired_yaw := atan2(-flat_dir.x, -flat_dir.z)
	body.rotation.y = lerp_angle(body.rotation.y, desired_yaw, 7.0 * get_physics_process_delta_time())
	var head := body.get_node_or_null("head") as Node3D
	if head:
		var horizontal := Vector2(full_dir.x, full_dir.z).length()
		var desired_pitch := atan2(full_dir.y - 0.35, maxf(horizontal, 0.01))
		head.rotation.x = lerp_angle(head.rotation.x, clampf(desired_pitch, -0.8, 0.8), 5.0 * get_physics_process_delta_time())

func _move_tactically(direction: Vector3, distance: float, delta: float) -> void:
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_strafe_sign = -_strafe_sign if _rng.randf() < 0.55 else _strafe_sign
		_preferred_side = _strafe_sign
		_decision_timer = _rng.randf_range(0.65, 1.35)

	var desired := Vector3.ZERO
	var side := Vector3(-direction.z, 0.0, direction.x) * _preferred_side
	if _has_los:
		# Не біжить прямо в гравця: тримає дистанцію, стрейфиться і змінює кут атаки.
		if distance > OPTIMAL_MAX:
			desired += direction * 0.48 + side * 0.9
		elif distance < OPTIMAL_MIN:
			desired -= direction * 0.65
			desired += side * 0.75
		else:
			desired += side * 1.0
			if _rng.randf() < 0.12:
				desired -= direction * 0.45
	else:
		# Якщо втратив ціль за укриттям — рухається до останньої відомої позиції.
		var to_last := _last_seen_position - body.global_position
		to_last.y = 0.0
		if _lost_sight_timer < 2.8 and to_last.length() > 1.2:
			desired = to_last.normalized()
		else:
			desired = direction * 0.35 + side * 0.9

	# Simple obstacle steering: if the direct path is blocked, choose the clearer side.
	if desired.length() > 0.01 and _front_blocked(desired.normalized()):
		var obstacle_side := Vector3(-direction.z, 0.0, direction.x)
		var left_clear := not _front_blocked(obstacle_side)
		var right_clear := not _front_blocked(-obstacle_side)
		if left_clear or right_clear:
			desired = obstacle_side * (1.0 if left_clear and (not right_clear or _strafe_sign > 0.0) else -1.0)
		else:
			desired = -direction

	if desired.length() > 0.01:
		desired = desired.normalized()
	var speed := RUN_SPEED if distance > OPTIMAL_MAX else WALK_SPEED
	var accel := 11.0 if body.is_on_floor() else 4.0
	body.velocity.x = move_toward(body.velocity.x, desired.x * speed, accel * delta * speed)
	body.velocity.z = move_toward(body.velocity.z, desired.z * speed, accel * delta * speed)

func _front_blocked(direction: Vector3) -> bool:
	var from := body.global_position + Vector3.UP * 0.9
	var to := from + direction * 1.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _own_rids()
	query.collide_with_areas = false
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _has_line_of_sight() -> bool:
	var head := body.get_node_or_null("head") as Node3D
	var from := head.global_position if head else body.global_position + Vector3.UP * 1.5
	var target_head := target.get_node_or_null("head") as Node3D
	var to := target_head.global_position if target_head else target.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _own_rids()
	query.collide_with_areas = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	# У цієї гри капсула CharacterBody3D може перекривати окремі Area-хітбокси.
	# Сам факт першого зіткнення з цільовим тілом означає чисту видимість.
	if collider == target:
		return true
	if collider is Hitbox:
		return (collider as Hitbox).owner_player == target
	return false

func _fire_at_target() -> void:
	var head := body.get_node_or_null("head") as Node3D
	if head == null:
		return
	var target_head := target.get_node_or_null("head") as Node3D
	var aim_point := target_head.global_position + Vector3(0.0, -0.18, 0.0) if target_head else target.global_position + Vector3.UP * 1.3
	# Невелике випередження рухомої цілі, щоб бот не цілився лише в її минуле місце.
	var target_velocity: Vector3 = target.velocity
	aim_point += Vector3(target_velocity.x, 0.0, target_velocity.z) * 0.12
	var direction := (aim_point - head.global_position).normalized()
	var distance := head.global_position.distance_to(aim_point)
	var distance_penalty := clampf(distance / VISION_RANGE, 0.0, 1.0) * 0.012
	var spread := (1.0 - accuracy) * 0.035 + 0.003 + distance_penalty
	direction = (direction + Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))).normalized()
	var query := PhysicsRayQueryParameters3D.create(head.global_position, head.global_position + direction * VISION_RANGE)
	var excluded := _own_rids()
	query.exclude = excluded
	query.collide_with_areas = true
	var space := body.get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	# Як і в системі куль гравця, капсула персонажа прозора для пострілу:
	# пропускаємо її, щоб дістатися до окремого хітбокса голови/тулуба.
	var guard := 0
	while not hit.is_empty() and not (hit.get("collider") is Hitbox) and guard < 8:
		var obstacle: Object = hit.get("collider")
		if obstacle is CharacterBody3D and (obstacle as Node).has_method("take_damage"):
			excluded.append((obstacle as CollisionObject3D).get_rid())
			query.exclude = excluded
			hit = space.intersect_ray(query)
			guard += 1
		else:
			return
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	# Звук відтворюється в 3D у точці дула, тому гравець чує напрямок і відстань.
	_play_bot_shot_sound(head.global_position + direction * 0.65)
	if collider is Hitbox:
		var box := collider as Hitbox
		if box.owner_player == target and not bool(target.get("is_dead")):
			target.call("take_damage", BODY_DAMAGE * box.damage_multiplier, BOT_ID)

func _play_bot_shot_sound(world_pos: Vector3) -> void:
	var weapon_camera := body.get_node_or_null("head/Camera3D")
	if weapon_camera and weapon_camera.has_method("_play_shot_sound"):
		weapon_camera.call("_play_shot_sound", world_pos, false)

func _own_rids() -> Array[RID]:
	var result: Array[RID] = []
	if body is CollisionObject3D:
		result.append(body.get_rid())
	var boxes := body.get_node_or_null("Hitboxes")
	if boxes:
		for box in boxes.get_children():
			if box is CollisionObject3D:
				result.append(box.get_rid())
	return result

func _apply_gravity(delta: float) -> void:
	if body.is_on_floor():
		if body.velocity.y < 0.0:
			body.velocity.y = -0.1
	else:
		body.velocity.y -= GRAVITY * delta
