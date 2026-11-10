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

const DAMAGE_POPUP_SCENE := preload("res://scenes/damage_popup.tscn")


func _ready() -> void:
	# Area3D більше не потрібна для влучання, лишаємо тільки для сумісності/вигляду.
	monitoring = false

	_prev_position = global_transform.origin


func launch() -> void:
	velocity_dir = -global_transform.basis.z * speed
	_prev_position = global_transform.origin


func _physics_process(delta: float) -> void:
	if _hit:
		return

	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()
		return

	var new_position: Vector3 = global_transform.origin + velocity_dir * delta

	# Перевіряємо весь відрізок шляху кулі за цей кадр, а не тільки кінцеву точку.
	# Це прибирає і "проскакування" по краях, і випадки коли постріл в упор
	# не встигає зафіксуватись при звичайному Area3D-перекритті.
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_prev_position, new_position)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var exclude: Array[RID] = []
	if shooter_body and shooter_body is CollisionObject3D:
		exclude.append((shooter_body as CollisionObject3D).get_rid())
	query.exclude = exclude

	var result := space_state.intersect_ray(query)

	if result:
		_on_hit(result)
	else:
		global_transform.origin = new_position
		_prev_position = new_position


func _on_hit(result: Dictionary) -> void:
	_hit = true

	var body: Node = result.get("collider")

	if multiplayer.get_unique_id() == shooter_id:
		if body and body.has_method("take_damage"):
			# Не наносимо урон і не показуємо попап, якщо ціль вже мертва
			if not ("is_dead" in body and body.is_dead):
				body.take_damage(damage, shooter_id)
				_spawn_damage_popup(body, damage)

	if is_instance_valid(self):
		queue_free()


func _spawn_damage_popup(target: Node, amount: float) -> void:
	if not target is Node3D:
		return

	var popup := DAMAGE_POPUP_SCENE.instantiate()
	get_tree().current_scene.add_child(popup)

	var target_3d := target as Node3D
	popup.global_position = target_3d.global_position + Vector3(0, 1.8, 0)
	popup.set_text("-%d" % int(amount))
