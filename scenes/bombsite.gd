@tool
class_name Bombsite
extends Node3D
# Бомбсайт для режиму 2×2. Постав кілька таких вузлів (наприклад A і B) на карті oasis:
# в player.tscn (main) або на самій карті. Це прямокутна зона size (м) з центром у позиції вузла;
# T може ставити бомбу тільки коли стоїть всередині.
# Зону можна крутити/масштабувати як звичайний Node3D. Висоту (size.y) роби із запасом —
# початок гравця лежить приблизно за 1 м над підлогою.

@export var site_name: String = "A"
@export var size: Vector3 = Vector3(12.0, 6.0, 12.0)
@export var show_marker: bool = true   # напівпрозорий маркер на підлозі зони + літера


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("bombsite")
	if show_marker:
		_make_marker()
	if not Engine.is_editor_hint():
		visible = false   # у грі зона невидима для всіх


func contains_point(p: Vector3) -> bool:
	var l: Vector3 = global_transform.affine_inverse() * p
	var h: Vector3 = size * 0.5
	return absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z


func _make_marker() -> void:
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.04, size.z)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0.0, -size.y * 0.5 + 0.03, 0.0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.1, 0.22)
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	var label := Label3D.new()
	label.text = site_name
	label.font_size = 220
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color(1.0, 0.6, 0.15, 0.9)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = Vector3(0.0, -size.y * 0.5 + 2.2, 0.0)
	add_child(label)
