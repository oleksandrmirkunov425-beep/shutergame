extends Node

# Tactical local bot controller. Runs only in the offline bot match.
#
# v2 — бот з обмеженим сприйняттям:
#   * поле зору (горизонтальне + вертикальне): бачить лише те, на що дивиться;
#   * повільне "помічання": рівень уваги росте поступово, на периферії ще повільніше;
#   * слух: чує біг/кроки гравця (крізь стіни тихіше) і постріли через hear_noise();
#   * пам'ять: пам'ятає останню позицію та напрямок руху гравця;
#   * стани: PATROL -> ALERT -> COMBAT -> SEARCH -> PATROL;
#   * повертається з обмеженою швидкістю і стріляє, лише коли дивиться на ціль.

enum State { PATROL, ALERT, COMBAT, SEARCH }

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

const PROXIMITY_SENSE := 2.0   # впритул бот "відчуває" гравця навіть поза FOV
const AIM_CONE_DEG := 12.0     # стріляє лише якщо ціль в такому конусі перед ним
const AIM_SETTLE_TIME := 0.6   # скільки секунд "наводиться" після помічання цілі
const ARRIVE_DIST := 1.0

@export_range(0.1, 1.0, 0.05) var accuracy: float = 0.88
@export_range(0.05, 2.0, 0.05) var reaction_time: float = 0.16

@export_group("Зір")
@export_range(60.0, 180.0, 5.0) var fov_degrees: float = 75.0
@export_range(30.0, 120.0, 5.0) var vertical_fov_degrees: float = 70.0
@export_range(20.0, 90.0, 5.0) var center_fov_degrees: float = 35.0
@export_range(0.1, 3.0, 0.05) var spot_time: float = 0.45
@export var turn_speed_deg: float = 320.0

@export_group("Слух")
@export var hear_run_radius: float = 16.0
@export var hear_walk_radius: float = 6.0
@export var loud_speed: float = 4.2
@export var quiet_speed: float = 1.0

@export_group("Пам'ять і пошук")
@export var reacquire_time: float = 1.3
@export var search_time: float = 12.0
@export var alert_timeout: float = 10.0

@export_group("Інше")
@export var health_property: String = "health"
@export var use_navmesh: bool = true
@export var debug_state: bool = false

var body: CharacterBody3D
var target: CharacterBody3D
var state: int = State.PATROL

var _head: Node3D
var _rng := RandomNumberGenerator.new()
var _time := 0.0

# --- сприйняття ---
var _awareness := 0.0
var _can_see := false
var _los_clear := false
var _distance := 999.0
var _target_h_angle := PI
var _vis_fraction := 0.0
var _visible_points: Array[Vector3] = []
var _hear_cd := 0.0

# --- пам'ять ---
var _last_seen_position := Vector3.ZERO
var _last_seen_velocity := Vector3.ZERO
var _lost_time := 0.0

# --- бій ---
var _fire_timer := 0.0
var _decision_timer := 0.0
var _strafe_sign := 1.0
var _preferred_side := 1.0
var _burst_left := 0
var _burst_pause := 0.0
var _aim_settle := 1.0

# --- патруль ---
var _patrol_point := Vector3.ZERO
var _has_patrol_point := false
var _patrol_wait := 0.0

# --- насторога ---
var _investigate_pos := Vector3.ZERO
var _alert_arrived := false
var _alert_timer := 0.0
var _alert_look_time := 0.0

# --- пошук ---
var _search_point := Vector3.ZERO
var _search_stage := 0
var _search_first := true
var _search_time_left := 0.0
var _scan_timer := 0.0

# --- погляд ---
var _desired_yaw := 0.0
var _desired_pitch := 0.0
var _scan_clock := 0.0
var _scan_base_yaw := 0.0

# --- навігація ---
var _path := PackedVector3Array()
var _path_idx := 0
var _path_dest := Vector3.ZERO
var _repath_timer := 0.0

# --- застрягання / здоров'я ---
var _stuck_timer := 0.0
var _stuck_pos := Vector3.ZERO
var _wants_move := false
var _last_health := -1.0


func _ready() -> void:
	body = get_parent() as CharacterBody3D
	_rng.randomize()
	add_to_group("bot_ai")
	_decision_timer = _rng.randf_range(1.0, 2.0)
	_patrol_wait = _rng.randf_range(0.5, 1.5)
	if is_instance_valid(body):
		_desired_yaw = body.rotation.y
		_scan_base_yaw = body.rotation.y
		_stuck_pos = body.global_position


func _physics_process(delta: float) -> void:
	if not is_instance_valid(body):
		return
	if bool(body.get("is_dead")):
		_reset_brain()
		return
	_time += delta
	_repath_timer -= delta

	if bool(body.get("frozen")):
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		_apply_gravity(delta)
		body.move_and_slide()
		return

	_find_target()
	_poll_damage()
	if not is_instance_valid(target) or bool(target.get("is_dead")):
		body.velocity.x = move_toward(body.velocity.x, 0.0, 10.0 * delta)
		body.velocity.z = move_toward(body.velocity.z, 0.0, 10.0 * delta)
		_apply_gravity(delta)
		body.move_and_slide()
		return

	_update_perception(delta)
	match state:
		State.PATROL:
			_do_patrol(delta)
		State.ALERT:
			_do_alert(delta)
		State.COMBAT:
			_do_combat(delta)
		State.SEARCH:
			_do_search(delta)

	_apply_look(delta)
	_apply_gravity(delta)
	body.move_and_slide()
	_check_stuck(delta)


func _find_target() -> void:
	if is_instance_valid(target) and not bool(target.get("is_dead")):
		return
	var room := Matchmaker.room_of(body)
	if room == null:
		return
	target = room.get_node_or_null("players/1") as CharacterBody3D


# =============================================================================
#  ПУБЛІЧНІ ХУКИ
# =============================================================================

# Викликай з коду гравця при пострілі:
#   get_tree().call_group("bot_ai", "hear_noise", global_position, 45.0)
func hear_noise(pos: Vector3, loudness: float = 30.0) -> void:
	if not is_instance_valid(body) or bool(body.get("is_dead")):
		return
	var dist := body.global_position.distance_to(pos)
	if dist > loudness:
		return
	_register_noise(pos, 1.0 - dist / maxf(loudness, 0.01))


# Викликається автоматично (якщо в бота є властивість health_property),
# або вручну з take_damage() бота.
func on_damaged() -> void:
	if not is_instance_valid(target):
		return
	_awareness = maxf(_awareness, 0.9)
	# Ухилення: одразу міняємо бік стрейфу.
	_preferred_side = -_preferred_side
	_strafe_sign = _preferred_side
	_decision_timer = _rng.randf_range(0.5, 1.0)
	if state == State.COMBAT and _can_see:
		return
	# Звідки саме стріляли — бот не знає точно, лише приблизний напрямок.
	var dist := body.global_position.distance_to(target.global_position)
	var err := clampf(1.5 + dist * 0.12, 1.5, 8.0)
	_last_seen_position = target.global_position + Vector3(_rng.randf_range(-err, err), 0.0, _rng.randf_range(-err, err))
	_last_seen_velocity = Vector3.ZERO
	if state == State.COMBAT:
		_lost_time = 0.0
	else:
		_enter_search()
	_look_at_point(_last_seen_position + Vector3.UP * 1.3)


# =============================================================================
#  СПРИЙНЯТТЯ
# =============================================================================

func _update_perception(delta: float) -> void:
	var to_target := target.global_position - body.global_position
	_distance = Vector2(to_target.x, to_target.z).length()
	var eye := _eye_position()
	var forward := _facing()

	# Зір: перевіряємо 3 точки тіла цілі — FOV + пряма видимість променем.
	_visible_points.clear()
	_los_clear = false
	if _distance <= VISION_RANGE:
		for p in _target_sample_points():
			if _ray_reaches_target(eye, p):
				_los_clear = true
				if _point_in_fov(eye, forward, p):
					_visible_points.append(p)
	_can_see = not _visible_points.is_empty()
	_vis_fraction = _visible_points.size() / 3.0

	var flat_f := Vector2(forward.x, forward.z)
	var flat_d := Vector2(to_target.x, to_target.z)
	if flat_f.length() > 0.001 and flat_d.length() > 0.001:
		_target_h_angle = absf(flat_f.angle_to(flat_d))
	else:
		_target_h_angle = 0.0

	# Рівень уваги: росте поступово, залежить від відстані, кута і відкритості цілі.
	if _can_see:
		_last_seen_position = target.global_position
		_last_seen_velocity = target.velocity
		if state == State.COMBAT:
			_awareness = 1.0
		else:
			var dist_factor := lerpf(2.2, 0.6, clampf(_distance / VISION_RANGE, 0.0, 1.0))
			var periph := 1.0 if _target_h_angle <= deg_to_rad(center_fov_degrees * 0.5) else 0.5
			var rate := dist_factor * periph * (0.4 + 0.6 * _vis_fraction) / maxf(spot_time, 0.05)
			_awareness = minf(1.0, _awareness + rate * delta)
	elif state != State.COMBAT:
		var decay := 0.12 if (state == State.ALERT or state == State.SEARCH) else 0.35
		_awareness = maxf(0.0, _awareness - decay * delta)

	# Слух: чує лише рух гравця, і лише коли не бачить його.
	_hear_cd -= delta
	if not _can_see and _hear_cd <= 0.0:
		var speed := Vector2(target.velocity.x, target.velocity.z).length()
		var radius := 0.0
		if speed >= loud_speed:
			radius = hear_run_radius
		elif speed >= quiet_speed:
			radius = hear_walk_radius
		if radius > 0.0:
			if not _los_clear:
				radius *= 0.55   # крізь стіни чутно гірше
			if _distance <= radius:
				_hear_cd = 0.45
				_register_noise(target.global_position, 1.0 - _distance / radius)

	# Переходи між станами за баченим.
	if _can_see and state != State.COMBAT:
		if _awareness >= 1.0:
			_enter_combat()
		elif state == State.PATROL and _awareness >= 0.3:
			_enter_alert(_last_seen_position)
		elif state == State.ALERT:
			_investigate_pos = _last_seen_position
			_alert_arrived = false
		elif state == State.SEARCH:
			_search_point = _last_seen_position
			_search_stage = 0
			_search_first = true


func _register_noise(pos: Vector3, strength: float) -> void:
	if state == State.COMBAT and _can_see:
		return
	# Чим тихіше/далі шум, тим менш точно бот визначає його джерело.
	var err := 0.5 + (1.0 - strength) * 3.5
	var p := pos + Vector3(_rng.randf_range(-err, err), 0.0, _rng.randf_range(-err, err))
	_awareness = maxf(_awareness, 0.35 + 0.4 * strength)
	match state:
		State.COMBAT:
			_last_seen_position = p
			_last_seen_velocity = Vector3.ZERO
			_lost_time = minf(_lost_time, reacquire_time * 0.5)
		State.SEARCH:
			_search_point = p
			_search_stage = 0
			_search_first = true
			_search_time_left = maxf(_search_time_left, 6.0)
		_:
			_enter_alert(p)


func _target_sample_points() -> Array[Vector3]:
	var pos := target.global_position
	var target_head := target.get_node_or_null("head") as Node3D
	var upper := target_head.global_position + Vector3(0.0, -0.18, 0.0) if target_head else pos + Vector3.UP * 1.3
	var pts: Array[Vector3] = []
	pts.append(upper)
	pts.append(pos + Vector3.UP * 0.9)
	pts.append(pos + Vector3.UP * 0.35)
	return pts


func _point_in_fov(eye: Vector3, forward: Vector3, p: Vector3) -> bool:
	var d := p - eye
	var flat_d := Vector2(d.x, d.z)
	if flat_d.length() < PROXIMITY_SENSE:
		return true
	var flat_f := Vector2(forward.x, forward.z)
	if flat_f.length() < 0.001 or flat_d.length() < 0.001:
		return true
	if absf(flat_f.angle_to(flat_d)) > deg_to_rad(fov_degrees * 0.5):
		return false
	var pitch_f := atan2(forward.y, flat_f.length())
	var pitch_d := atan2(d.y, flat_d.length())
	return absf(pitch_d - pitch_f) <= deg_to_rad(vertical_fov_degrees * 0.5)


func _ray_reaches_target(from: Vector3, to: Vector3) -> bool:
	var dir := (to - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, to + dir * 0.4)
	query.exclude = _own_rids()
	query.collide_with_areas = true
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	# Капсула CharacterBody3D може перекривати окремі Area-хітбокси:
	# перше зіткнення з тілом цілі означає чисту видимість.
	if collider == target:
		return true
	if collider is Hitbox:
		return (collider as Hitbox).owner_player == target
	return false


# =============================================================================
#  СТАНИ
# =============================================================================

func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	if debug_state:
		print("[Bot] ", State.keys()[state], " -> ", State.keys()[new_state])
	state = new_state


func _reset_brain() -> void:
	state = State.PATROL
	_awareness = 0.0
	_can_see = false
	_lost_time = 0.0
	_has_patrol_point = false
	_burst_left = 0
	_last_health = -1.0


func _enter_patrol() -> void:
	_set_state(State.PATROL)
	_has_patrol_point = false
	_patrol_wait = _rng.randf_range(0.3, 1.0)
	_scan_base_yaw = body.rotation.y
	_scan_clock = 0.0


func _enter_alert(pos: Vector3) -> void:
	_set_state(State.ALERT)
	_investigate_pos = pos
	_alert_arrived = false
	_alert_timer = alert_timeout
	_alert_look_time = _rng.randf_range(2.5, 4.0)
	_scan_clock = 0.0


func _enter_combat() -> void:
	_set_state(State.COMBAT)
	_awareness = 1.0
	_fire_timer = reaction_time + _rng.randf_range(0.0, 0.1)
	_aim_settle = 1.0
	_burst_left = 0
	_lost_time = 0.0
	_decision_timer = 0.0


func _enter_search() -> void:
	_set_state(State.SEARCH)
	_search_time_left = search_time
	_search_point = _predict_position()
	_search_stage = 0
	_search_first = true


func _predict_position() -> Vector3:
	var flat_vel := Vector3(_last_seen_velocity.x, 0.0, _last_seen_velocity.z)
	var reach := flat_vel.length() * 0.6
	if reach > 0.2:
		var from := _last_seen_position + Vector3.UP * 0.9
		if _free_distance(from, flat_vel.normalized(), reach) >= reach:
			return _last_seen_position + flat_vel * 0.6
	return _last_seen_position


func _do_patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		_apply_move(Vector3.ZERO, WALK_SPEED, delta)
		_scan_clock += delta
		_desired_yaw = _scan_base_yaw + sin(_scan_clock * 1.6) * 1.1
		_desired_pitch = 0.0
		return
	if not _has_patrol_point:
		_pick_patrol_point()
	var arrived := _move_to(_patrol_point, WALK_SPEED * 0.85, delta)
	_look_along_movement(0.5)
	if arrived:
		_has_patrol_point = false
		_patrol_wait = _rng.randf_range(1.2, 2.8)
		_scan_base_yaw = body.rotation.y
		_scan_clock = 0.0


func _do_alert(delta: float) -> void:
	_alert_timer -= delta
	if _alert_timer <= 0.0:
		_enter_patrol()
		return
	if not _alert_arrived:
		_alert_arrived = _move_to(_investigate_pos, WALK_SPEED, delta)
		_look_at_point(_investigate_pos + Vector3.UP * 1.3)
		_scan_base_yaw = _desired_yaw
		_scan_clock = 0.0
	else:
		_apply_move(Vector3.ZERO, WALK_SPEED, delta)
		_scan_clock += delta
		_desired_yaw = _scan_base_yaw + sin(_scan_clock * 1.8) * 1.3
		_desired_pitch = 0.0
		_alert_look_time -= delta
		if _alert_look_time <= 0.0:
			_enter_patrol()


func _do_search(delta: float) -> void:
	_search_time_left -= delta
	if _search_time_left <= 0.0:
		_enter_patrol()
		return
	if _search_stage == 0:
		var speed := RUN_SPEED if _search_first else WALK_SPEED
		var arrived := _move_to(_search_point, speed, delta)
		if _search_first:
			_look_at_point(_search_point + Vector3.UP * 1.3)
		else:
			_look_along_movement(0.7)
		if arrived:
			_search_stage = 1
			_search_first = false
			_scan_timer = _rng.randf_range(1.8, 3.0)
			_scan_base_yaw = body.rotation.y
			_scan_clock = 0.0
	else:
		_apply_move(Vector3.ZERO, WALK_SPEED, delta)
		_scan_clock += delta
		_desired_yaw = _scan_base_yaw + sin(_scan_clock * 2.0) * 1.5
		_desired_pitch = 0.0
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_pick_search_point()
			_search_stage = 0


func _do_combat(delta: float) -> void:
	if _can_see:
		_lost_time = 0.0
		_look_at_point(_aim_point())
		var flat := target.global_position - body.global_position
		flat.y = 0.0
		_move_tactically(flat.normalized(), _distance, delta)
		_update_firing(delta)
	else:
		# Втратив ціль (за укриттям або поза зором): біжить туди, де її бачив востаннє.
		_lost_time += delta
		_burst_left = 0
		_fire_timer = maxf(_fire_timer, 0.1)
		if _lost_time > reacquire_time:
			_enter_search()
			return
		var chase := _predict_position()
		_look_at_point(chase + Vector3.UP * 1.3)
		_move_to(chase, RUN_SPEED, delta)


# =============================================================================
#  РУХ
# =============================================================================

func _move_tactically(direction: Vector3, distance: float, delta: float) -> void:
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_strafe_sign = -_strafe_sign if _rng.randf() < 0.55 else _strafe_sign
		_preferred_side = _strafe_sign
		_decision_timer = _rng.randf_range(0.65, 1.35)

	var desired := Vector3.ZERO
	var side := Vector3(-direction.z, 0.0, direction.x) * _preferred_side
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

	desired = _avoid_obstacles(desired)
	var speed := RUN_SPEED if distance > OPTIMAL_MAX else WALK_SPEED
	_apply_move(desired, speed, delta)


# Іде до точки (через navmesh, якщо він є, інакше напряму). true = дійшов.
func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	var to := point - body.global_position
	to.y = 0.0
	if to.length() < ARRIVE_DIST:
		_apply_move(Vector3.ZERO, speed, delta)
		return true
	var dir := _avoid_obstacles(_path_direction(point))
	_apply_move(dir, speed, delta)
	return false


func _path_direction(dest: Vector3) -> Vector3:
	if use_navmesh:
		if _repath_timer <= 0.0 or dest.distance_to(_path_dest) > 1.0:
			_repath_timer = 0.5
			_path_dest = dest
			_path_idx = 1
			_path = PackedVector3Array()
			var map := body.get_world_3d().navigation_map
			if NavigationServer3D.map_get_regions(map).size() > 0:
				_path = NavigationServer3D.map_get_path(map, body.global_position, dest, true)
		while _path_idx < _path.size():
			var to_point := _path[_path_idx] - body.global_position
			to_point.y = 0.0
			if to_point.length() > 0.7:
				return to_point.normalized()
			_path_idx += 1
	var flat := dest - body.global_position
	flat.y = 0.0
	return flat.normalized()


func _avoid_obstacles(desired: Vector3) -> Vector3:
	if desired.length() < 0.01:
		return Vector3.ZERO
	var dir := desired.normalized()
	if not _front_blocked(dir):
		return dir
	for angle in [0.6, 1.2, 1.9]:
		var a: float = angle
		var left := dir.rotated(Vector3.UP, a)
		var right := dir.rotated(Vector3.UP, -a)
		var first := left if _strafe_sign > 0.0 else right
		var second := right if _strafe_sign > 0.0 else left
		if not _front_blocked(first):
			return first
		if not _front_blocked(second):
			return second
	return -dir


func _apply_move(desired: Vector3, speed: float, delta: float) -> void:
	var dir := Vector3.ZERO
	if desired.length() > 0.01:
		dir = desired.normalized()
		_wants_move = true
	var accel := 11.0 if body.is_on_floor() else 4.0
	body.velocity.x = move_toward(body.velocity.x, dir.x * speed, accel * delta * speed)
	body.velocity.z = move_toward(body.velocity.z, dir.z * speed, accel * delta * speed)


func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < 0.8:
		return
	var moved := Vector2(body.global_position.x - _stuck_pos.x, body.global_position.z - _stuck_pos.z).length()
	var wanted := _wants_move
	_stuck_pos = body.global_position
	_stuck_timer = 0.0
	_wants_move = false
	if not wanted or moved > 0.25:
		return
	_strafe_sign = -_strafe_sign
	_preferred_side = _strafe_sign
	_path = PackedVector3Array()
	_repath_timer = 0.0
	match state:
		State.PATROL:
			_has_patrol_point = false
		State.ALERT:
			_alert_arrived = true
		State.SEARCH:
			_search_stage = 1
			_scan_timer = 1.0
			_scan_base_yaw = body.rotation.y
			_scan_clock = 0.0


func _pick_patrol_point() -> void:
	_has_patrol_point = true
	# Якщо на сцені є вузли в групі "bot_waypoints" — ходить між ними.
	var waypoints := get_tree().get_nodes_in_group("bot_waypoints")
	if not waypoints.is_empty():
		for _i in 8:
			var wp := waypoints[_rng.randi() % waypoints.size()] as Node3D
			if wp and wp.global_position.distance_to(body.global_position) > 4.0:
				_patrol_point = wp.global_position
				return
	# Інакше — блукає: обирає напрямок, де найбільше вільного місця.
	var from := body.global_position + Vector3.UP * 0.9
	var best_dir := Vector3.FORWARD
	var best_free := 0.0
	var best_score := -1.0
	for _i in 10:
		var angle := _rng.randf() * TAU
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var free := _free_distance(from, dir, 14.0)
		var score := free * _rng.randf_range(0.6, 1.0)
		if score > best_score:
			best_score = score
			best_free = free
			best_dir = dir
	_patrol_point = body.global_position + best_dir * maxf(best_free * 0.85, 2.0)


func _pick_search_point() -> void:
	var origin := _last_seen_position
	var from := origin + Vector3.UP * 0.9
	for _i in 8:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(3.0, 8.0)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		if _free_distance(from, dir, dist) >= dist:
			_search_point = origin + dir * dist
			return
	_search_point = origin


# =============================================================================
#  ПОГЛЯД
# =============================================================================

func _head_node() -> Node3D:
	if not is_instance_valid(_head):
		_head = body.get_node_or_null("head") as Node3D
	return _head


func _eye_position() -> Vector3:
	var head := _head_node()
	return head.global_position if head else body.global_position + Vector3.UP * 1.5


func _facing() -> Vector3:
	var node: Node3D = _head_node()
	if node == null:
		node = body
	return -node.global_transform.basis.z.normalized()


func _look_at_point(point: Vector3) -> void:
	var d := point - _eye_position()
	var flat_len := Vector2(d.x, d.z).length()
	if flat_len > 0.05:
		_desired_yaw = atan2(-d.x, -d.z)
	_desired_pitch = atan2(d.y, maxf(flat_len, 0.01))


func _look_along_movement(glance: float) -> void:
	var v := Vector2(body.velocity.x, body.velocity.z)
	if v.length() > 0.5:
		_desired_yaw = atan2(-v.x, -v.y) + sin(_time * 0.9) * glance
	_desired_pitch = 0.0


func _apply_look(delta: float) -> void:
	var mult := 0.4
	if state == State.COMBAT:
		mult = 1.0
	elif state != State.PATROL:
		mult = 0.7
	var max_step := deg_to_rad(turn_speed_deg) * mult * delta
	var diff := wrapf(_desired_yaw - body.rotation.y, -PI, PI)
	body.rotation.y += clampf(diff, -max_step, max_step)
	var head := _head_node()
	if head:
		head.rotation.x = move_toward(head.rotation.x, clampf(_desired_pitch, -0.8, 0.8), 6.0 * delta)


# =============================================================================
#  СТРІЛЬБА
# =============================================================================

func _aim_point() -> Vector3:
	if not _visible_points.is_empty():
		return _visible_points[0]
	return target.global_position + Vector3.UP * 1.3


func _aim_error() -> float:
	var dir := (_aim_point() - _eye_position()).normalized()
	return acos(clampf(_facing().dot(dir), -1.0, 1.0))


func _update_firing(delta: float) -> void:
	_aim_settle = move_toward(_aim_settle, 0.0, delta / AIM_SETTLE_TIME)
	_fire_timer -= delta
	_burst_pause -= delta
	if _fire_timer > 0.0 or _burst_pause > 0.0:
		return
	# Стріляє лише коли реально дивиться на ціль (бот повертається не миттєво).
	if _aim_error() > deg_to_rad(AIM_CONE_DEG):
		return
	if _burst_left <= 0:
		_burst_left = _rng.randi_range(3, 5)
	_fire_at_target()
	_burst_left -= 1
	_fire_timer = FIRE_INTERVAL + _rng.randf_range(0.0, 0.045)
	if _burst_left <= 0:
		_burst_pause = _rng.randf_range(0.28, 0.55)


func _fire_at_target() -> void:
	var head := _head_node()
	if head == null:
		return
	var aim_point := _aim_point()
	# Невелике випередження рухомої цілі, щоб бот не цілився лише в її минуле місце.
	var target_velocity: Vector3 = target.velocity
	aim_point += Vector3(target_velocity.x, 0.0, target_velocity.z) * 0.12
	var direction := (aim_point - head.global_position).normalized()
	var distance := head.global_position.distance_to(aim_point)
	var distance_penalty := clampf(distance / VISION_RANGE, 0.0, 1.0) * 0.012
	var move_penalty := clampf(Vector2(target_velocity.x, target_velocity.z).length() / RUN_SPEED, 0.0, 1.0) * 0.006
	# _aim_settle: одразу після помічання цілі бот цілиться гірше, потім "наводиться".
	var spread := (1.0 - accuracy) * 0.035 + 0.003 + distance_penalty + move_penalty + _aim_settle * 0.03
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


# =============================================================================
#  УТИЛІТИ
# =============================================================================

func _poll_damage() -> void:
	if health_property.is_empty():
		return
	var value: Variant = body.get(health_property)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return
	var hp := float(value)
	if _last_health >= 0.0 and hp < _last_health - 0.01:
		on_damaged()
	_last_health = hp


func _front_blocked(direction: Vector3) -> bool:
	var from := body.global_position + Vector3.UP * 0.9
	var to := from + direction * 1.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _own_rids()
	query.collide_with_areas = false
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# Скільки вільного місця від точки в напрямку (до max_dist).
func _free_distance(from: Vector3, dir: Vector3, max_dist: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
	query.exclude = _own_rids()
	query.collide_with_areas = false
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return max_dist
	var hit_pos: Vector3 = hit["position"]
	return from.distance_to(hit_pos)


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
