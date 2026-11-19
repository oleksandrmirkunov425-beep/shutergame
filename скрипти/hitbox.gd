extends StaticBody3D
class_name Hitbox

# Хітбокс частини тіла. Куля (bullet.gd) б'є ТІЛЬКИ по цих вузлах, а не по капсулі руху гравця.
# Форма кожного хітбокса підганяється під реальні вершини моделі (fit_to_model).

# Окремий шар фізики (№10) — тільки для хітбоксів.
const HITBOX_LAYER: int = 1 << 9

@export var part_name: String = "body"
@export var damage_multiplier: float = 1.0
var owner_player: CharacterBody3D = null

# Запасні значення (поки модель невідома або не вдалось прочитати меш).
# Формат: [назва, множник, центр відносно гравця, розмір]
const PARTS: Array = [
	["head",  4.0,  Vector3(0.0,    0.725, 0.0), Vector3(0.45, 0.45, 0.45)],
	["body",  1.0,  Vector3(0.0,    0.20,  0.0), Vector3(0.50, 0.60, 0.40)],
	["arm_l", 0.8,  Vector3(-0.365, 0.20,  0.0), Vector3(0.23, 0.60, 0.40)],
	["arm_r", 0.8,  Vector3(0.365,  0.20,  0.0), Vector3(0.23, 0.60, 0.40)],
	["leg_l", 0.75, Vector3(-0.125, -0.475, 0.0), Vector3(0.25, 0.75, 0.40)],
	["leg_r", 0.75, Vector3(0.125,  -0.475, 0.0), Vector3(0.25, 0.75, 0.40)],
]

# Пропорції моделі (за висотою): ноги — нижні 41.7 %, голова — верхні 25 %,
# руки — все, що по боках від тулуба між ногами і головою.
const LEGS_TOP_RATIO: float = 0.4167
const HEAD_BOTTOM_RATIO: float = 0.75
const ARM_X_RATIO: float = 0.52   # |x| більше цієї частки від найширшої точки — рука


func _ready() -> void:
	# Працює і для хітбоксів, доданих вручну в редакторі: шар, маска і власник підставляються самі.
	collision_layer = HITBOX_LAYER
	collision_mask = 0
	if owner_player == null:
		var n: Node = get_parent()
		while n != null and not (n is CharacterBody3D):
			n = n.get_parent()
		owner_player = n as CharacterBody3D


# Викликається один раз з player.gd (_ready) на КОЖНІЙ копії гравця.
static func build_for(player: CharacterBody3D) -> void:
	if player.has_node("Hitboxes"):
		return
	var root := Node3D.new()
	root.name = "Hitboxes"
	player.add_child(root)
	for p in PARTS:
		var hb := Hitbox.new()
		hb.name = p[0]
		hb.part_name = p[0]
		hb.damage_multiplier = p[1]
		hb.owner_player = player
		hb.collision_layer = HITBOX_LAYER
		hb.collision_mask = 0
		hb.position = p[2]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = p[3]
		cs.shape = box
		hb.add_child(cs)
		root.add_child(hb)


# Підганяє КОЖЕН хітбокс (голова, тулуб, ліва/права рука, ліва/права нога) під вершини моделі.
# Викликати, коли відома модель гравця (після вибору команди).
# team_mask: -1 = усі грані; 0 = тільки грані команди T; 1 = тільки грані CT.
# Модель має грані обох команд; маска лежить у UV2 (x = видима для T, y = видима для CT).
static func fit_to_model(player: Node3D, model: Node3D, team_mask: int = -1) -> void:
	if player == null or model == null:
		return
	var root := player.get_node_or_null("Hitboxes")
	if root == null:
		return

	# Усі вершини моделі в координатах гравця.
	var to_player: Transform3D = player.global_transform.affine_inverse()
	var verts: PackedVector3Array = PackedVector3Array()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var xf: Transform3D = to_player * m.global_transform
		_collect_team_verts(m.mesh, xf, team_mask, verts)
	if verts.is_empty():
		return

	var min_y: float = INF
	var max_y: float = -INF
	var max_abs_x: float = 0.0
	for v in verts:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
		max_abs_x = maxf(max_abs_x, absf(v.x))
	var height: float = max_y - min_y
	if height < 0.1:
		return
	var legs_top: float = min_y + height * LEGS_TOP_RATIO
	var head_bottom: float = min_y + height * HEAD_BOTTOM_RATIO
	var arm_x: float = max_abs_x * ARM_X_RATIO

	# Межі (мін/макс) кожної частини.
	var mins: Dictionary = {}
	var maxs: Dictionary = {}
	for v in verts:
		var part: String
		if v.y >= head_bottom:
			part = "head"
		elif v.y < legs_top:
			part = "leg_l" if v.x < 0.0 else "leg_r"
		elif absf(v.x) > arm_x:
			part = "arm_l" if v.x < 0.0 else "arm_r"
		else:
			part = "body"
		if not mins.has(part):
			mins[part] = v
			maxs[part] = v
		else:
			mins[part] = Vector3(minf(mins[part].x, v.x), minf(mins[part].y, v.y), minf(mins[part].z, v.z))
			maxs[part] = Vector3(maxf(maxs[part].x, v.x), maxf(maxs[part].y, v.y), maxf(maxs[part].z, v.z))

	for part in mins.keys():
		var hb := root.get_node_or_null(NodePath(part)) as Node3D
		if hb == null:
			continue
		var size: Vector3 = (maxs[part] - mins[part]) + Vector3(0.02, 0.02, 0.02)
		size = size.max(Vector3(0.05, 0.05, 0.05))
		hb.position = (mins[part] + maxs[part]) * 0.5
		hb.remove_meta("base_pos")    # нова "стояча" база для set_crouch
		hb.remove_meta("base_size")
		for c in hb.get_children():
			if c is CollisionShape3D:
				var box := BoxShape3D.new()
				box.size = size
				(c as CollisionShape3D).shape = box
				break


# Додає вершини граней меша, видимих для команди (за маскою в UV2). Без маски — усі грані.
static func _collect_team_verts(mesh: Mesh, xf: Transform3D, team_mask: int, out: PackedVector3Array) -> void:
	if team_mask < 0:
		for v in mesh.get_faces():
			out.append(xf * v)
		return
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV2] != null:
			uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var idx: PackedInt32Array = PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		var tri_count: int = (idx.size() if idx.size() > 0 else vs.size()) / 3
		for t in tri_count:
			var i0: int = idx[t * 3] if idx.size() > 0 else t * 3
			if uv2.size() > i0:
				var flag: float = uv2[i0].x if team_mask == 0 else uv2[i0].y
				if flag < 0.5:
					continue
			for k in 3:
				var vi: int = idx[t * 3 + k] if idx.size() > 0 else t * 3 + k
				out.append(xf * vs[vi])


# Вмикає/вимикає всі хітбокси гравця (наприклад, на час смерті).
static func set_enabled(player: Node, enabled: bool) -> void:
	var root := player.get_node_or_null("Hitboxes")
	if root == null:
		return
	for hb in root.get_children():
		if hb is CollisionObject3D:
			(hb as CollisionObject3D).collision_layer = HITBOX_LAYER if enabled else 0


# Стискає всі хітбокси по висоті (k = 1 стоїть, k < 1 присів) відносно рівня ніг feet_y
# (координати відносно гравця). Базові позиція/розмір запам'ятовуються при першому виклику
# (і скидаються в fit_to_model).
static func set_crouch(player: Node, k: float, feet_y: float) -> void:
	var root := player.get_node_or_null("Hitboxes")
	if root == null:
		return
	for hb in root.get_children():
		var n3 := hb as Node3D
		if n3 == null:
			continue
		var box: BoxShape3D = null
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				box = (c as CollisionShape3D).shape as BoxShape3D
				break
		if not hb.has_meta("base_pos"):
			hb.set_meta("base_pos", n3.position)
			if box:
				hb.set_meta("base_size", box.size)
		var bp: Vector3 = hb.get_meta("base_pos")
		n3.position = Vector3(bp.x, feet_y + (bp.y - feet_y) * k, bp.z)
		if box and hb.has_meta("base_size"):
			var bs: Vector3 = hb.get_meta("base_size")
			box.size = Vector3(bs.x, bs.y * k, bs.z)
