extends Area3D

@export var speed: float = 60.0
@export var damage: float = 25.0
@export var lifetime: float = 3.0

var shooter_id: int = -1
var shooter_body: Node = null      # тіло того, хто вистрілив — ігноруємо його
var velocity_dir: Vector3 = Vector3.ZERO

var _prev_position: Vector3 = Vector3.ZERO
var _time_alive: float = 0.0
var _hit: bool = false
const MAX_RANGE: float = 1000.0
var _exclude_cache: Array[RID] = []
var _exclude_ready: bool = false

const DAMAGE_POPUP_SCENE := preload("res://scenes/damage_popup.tscn")


func _ready() -> void:
	# Area3D більше не потрібна для влучання, лишаємо тільки для сумісності/вигляду.
	monitoring = false

	_prev_position = global_transform.origin


# Хітскан: куля — це миттєвий промінь від камери, а не об'єкт, що летить.
# Влучання визначається в момент пострілу, тож швидкість кулі не має значення.
func launch() -> void:
	var dir: Vector3 = -global_transform.basis.z
	if dir.length() < 0.001:
		queue_free()
		return
	dir = dir.normalized()
	var from: Vector3 = global_transform.origin
	var to: Vector3 = from + dir * MAX_RANGE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var ex: Array[RID] = _get_exclude().duplicate()
	query.exclude = ex

	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	# Капсула руху гравця для променя "прозора": б'ємо лише по хітбоксах, що повторюють модель.
	var guard: int = 0
	while result and not (result.get("collider") is Hitbox) and _is_player_body(result.get("collider")) and guard < 8:
		ex.append((result.get("collider") as CollisionObject3D).get_rid())
		query.exclude = ex
		result = space_state.intersect_ray(query)
		guard += 1

	if result:
		_on_hit(result)
	else:
		queue_free()


# Сам стрілець (його тіло і всі його хітбокси) для променя "прозорий".
func _get_exclude() -> Array[RID]:
	if _exclude_ready:
		return _exclude_cache
	_exclude_ready = true
	if shooter_body and shooter_body is CollisionObject3D:
		_exclude_cache.append((shooter_body as CollisionObject3D).get_rid())
		var boxes := shooter_body.get_node_or_null("Hitboxes")
		if boxes:
			for hb in boxes.get_children():
				if hb is CollisionObject3D:
					_exclude_cache.append((hb as CollisionObject3D).get_rid())
	return _exclude_cache


func _is_player_body(body: Object) -> bool:
	return body is CharacterBody3D and (body as Node).has_method("take_damage")


func _on_hit(result: Dictionary) -> void:
	_hit = true

	var body: Node = result.get("collider")
	var target: Node = null
	var multiplier: float = 1.0

	# Урон тільки через хітбокс (голова / тулуб / рука / нога). Стіни й підлога урону не дають.
	if body is Hitbox:
		target = (body as Hitbox).owner_player
		multiplier = (body as Hitbox).damage_multiplier

	if multiplayer.get_unique_id() == shooter_id:
		if target and target.has_method("take_damage"):
			# Не наносимо урон і не показуємо попап, якщо ціль вже мертва
			if not ("is_dead" in target and target.is_dead):
				var final_damage: float = damage * multiplier
				target.take_damage(final_damage, shooter_id)
				_spawn_damage_popup(target, final_damage)

	if is_instance_valid(self):
		queue_free()


func _spawn_damage_popup(target: Node, amount: float) -> void:
	if not target is Node3D:
		return

	var popup := DAMAGE_POPUP_SCENE.instantiate()
	Matchmaker.room_of(self).add_child(popup)

	var target_3d := target as Node3D
	popup.global_position = target_3d.global_position + Vector3(0, 1.8, 0)
	popup.set_text("-%d" % int(amount))
