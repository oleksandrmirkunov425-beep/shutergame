extends RefCounted
# скрипти/ui_kit.gd — спільні кольори, стилі та віджети для нового меню і магазину.
# Нічого не додає в сцену сам: menu_ui.gd і shop_ui.gd беруть звідси готові шматки.

const C_TEXT := Color("eef0f4")
const C_MUTED := Color("8a92a3")
const C_RED := Color("d6263a")
const C_RED_HI := Color("ff5468")
const C_GOLD := Color("f2b84b")
const C_PURPLE := Color("9566f5")
const C_STEEL := Color("8e98ab")
const C_GREEN := Color("5fd38d")

# Малюнки скінів — це ті самі PNG, що гра накладає на модель (skins/*.png), лише з вирізаним фоном.
# Новий скін: додати рядок сюди (або просто покласти skins/<id>.png — тоді він візьметься без вирізки).
const ART_AK := preload("res://skins/preview/ak47_samurai_cut.png")
const ART_AWP := preload("res://skins/preview/awp_samurai_cut.png")
const ART_M4 := preload("res://m4/m4_silhouette.png")   # силует M4 (вид збоку) для меню
const ART_AK_CYBER := preload("res://skins/preview/ak47_cyber_circuit_cut.png")
const ART_AK_ARCTIC := preload("res://skins/preview/ak47_arctic_tactical_cut.png")
const ART_AK_CRIMSON := preload("res://skins/preview/ak47_crimson_filigree_cut.png")
const SKIN_ART := {
	"ak47_samurai": ART_AK, "awp_samurai": ART_AWP,
	"ak47_cyber_circuit": ART_AK_CYBER, "ak47_arctic_tactical": ART_AK_ARCTIC, "ak47_crimson_filigree": ART_AK_CRIMSON,
}
const MIRROR_SKINS := true   # відзеркалити арт скінів (дуло вправо)
const SKIN_ON_MODEL := []   # для цієї зброї скін малюється на 3D-моделі (порожній масив = завжди плоский арт)
const WEAPON_SHAPE := {"ak47": ART_AK, "awp": ART_AWP, "m4": ART_M4}   # силует стандартної зброї (форма та сама)

# Скільки коштує «рівень» картки: від ціни. Можна задати явно в Economy: "rarity": "gold"/"red"/"purple"/"common".
static func rarity_of(info: Dictionary, price: int) -> String:
	var r: String = str(info.get("rarity", ""))
	if r != "":
		return r
	if price >= 400:
		return "gold"
	if price >= 100:
		return "red"
	if price > 0:
		return "purple"
	return "common"


static func rarity_color(r: String) -> Color:
	match r:
		"gold": return C_GOLD
		"red": return C_RED
		"purple": return C_PURPLE
	return C_STEEL


# ---------------------------------------------------------------- стилі
static func font(bold: bool = true, spacing: int = 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.55 if bold else 0.0
	f.spacing_glyph = spacing
	return f


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 6,
		glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	if glow_size > 0:
		s.shadow_color = glow
		s.shadow_size = glow_size
	return s


static func label(text: String, size: int, color: Color = C_TEXT, bold: bool = true,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, spacing: int = 1) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font(bold, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# kind: primary | ghost | gold | red | purple | dim | tab_on | tab_off
static func style_button(b: Button, kind: String, font_size: int = 22) -> void:
	var bg := Color("1a1c23")
	var border := Color("3b3f4a")
	var fg := C_TEXT
	var glow := Color(0, 0, 0, 0)
	match kind:
		"primary":
			bg = Color("c7243a"); border = Color("ff6a7c"); glow = Color(C_RED, 0.55)
		"gold":
			bg = Color("2b2210"); border = C_GOLD; fg = C_GOLD
		"red":
			bg = Color("2d0d14"); border = C_RED; fg = Color("ff8c99")
		"purple":
			bg = Color("1f1638"); border = C_PURPLE; fg = Color("c9adff")
		"dim":
			bg = Color("16181e"); border = Color("30343e"); fg = C_MUTED
		"tab_on":
			bg = Color("2a2d37"); border = Color("c4cad8"); fg = C_TEXT
		"tab_off":
			bg = Color("15171d"); border = Color("30343e"); fg = C_MUTED
	b.add_theme_stylebox_override("normal", box(bg, border, 1, 6, glow, 12 if glow.a > 0.0 else 0))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.14), border.lightened(0.25), 1, 6, glow, 16 if glow.a > 0.0 else 0))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.2), border, 1, 6))
	b.add_theme_stylebox_override("disabled", box(bg.darkened(0.15), border.darkened(0.45), 1, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font(true, 1))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func pill(inner: Control, pad_h: int = 14, pad_v: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color("15171d"), Color("333743"), 1, 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", pad_h)
	m.add_theme_constant_override("margin_right", pad_h)
	m.add_theme_constant_override("margin_top", pad_v)
	m.add_theme_constant_override("margin_bottom", pad_v)
	p.add_child(m)
	m.add_child(inner)
	return p


# ---------------------------------------------------------------- віджети
class CoinIcon extends Control:
	func _init(px: int = 24) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color("a8741a"))
		draw_circle(c, r * 0.88, Color("f2b84b"))
		draw_arc(c, r * 0.66, 0.0, TAU, 32, Color("b9801e"), maxf(1.0, r * 0.12), true)
		var f: Font = ThemeDB.fallback_font
		var fs := int(r * 1.15)
		var ts := f.get_string_size("C", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - ts.x / 2.0, c.y + ts.y * 0.28), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("8a5a10"))


class Star extends Control:
	var color := Color.WHITE

	func _init(px: int = 18, col: Color = Color.WHITE) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = col

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var k := r * 0.28
		var pts := PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(k, -k), c + Vector2(r, 0), c + Vector2(k, k),
			c + Vector2(0, r), c + Vector2(-k, k), c + Vector2(-r, 0), c + Vector2(-k, -k)])
		draw_colored_polygon(pts, color)


class Spinner extends Control:
	var angle := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			angle += delta * 5.0
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 5.0
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 5.0, true)
		draw_arc(c, r, angle, angle + PI * 1.1, 32, Color("ff4a5f"), 5.0, true)


# Запасний значок ножа (метелик) — малюється, якщо в проєкті не знайшлося його 3D-моделі.
class BladeIcon extends Control:
	var tint := Color("8e98ab")

	func _init(col: Color = Color("8e98ab")) -> void:
		tint = col
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := minf(size.x / 3.0, size.y / 0.5)   # одиниця: довжина ножа = 3
		if s <= 0.0:
			return
		var o := Vector2((size.x - s * 3.0) / 2.0, size.y / 2.0)
		var pt := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
		# клинок (клиповий вістря + черевце)
		draw_colored_polygon(PackedVector2Array([
			pt.call(0.0, 0.05), pt.call(0.22, -0.10), pt.call(0.7, -0.15), pt.call(1.5, -0.15),
			pt.call(1.5, 0.08), pt.call(0.8, 0.12), pt.call(0.35, 0.11)]), tint)
		draw_line(pt.call(0.1, 0.03), pt.call(1.45, -0.02), tint.darkened(0.35), maxf(1.0, s * 0.015), true)
		# дві рукояті з проміжком
		draw_rect(Rect2(pt.call(1.5, -0.15), Vector2(1.4, 0.13) * s), tint.darkened(0.3))
		draw_rect(Rect2(pt.call(1.5, 0.0), Vector2(1.4, 0.13) * s), tint.darkened(0.45))
		draw_circle(pt.call(1.55, -0.01), s * 0.07, tint.lightened(0.2))
		draw_circle(pt.call(2.85, -0.01), s * 0.035, tint.darkened(0.6))


# Фон: темний градієнт, віньєтка, діагональна «карбонова» штриховка, червоні неонові смуги.
class Backdrop extends Control:
	var neon := true
	var glow_center := Vector2(0.66, 0.42)

	func _init(with_neon: bool = true) -> void:
		neon = with_neon
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := size
		var top := Color("0d0e12")
		var bot := Color("07080a")
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([top, top, bot, bot]))
		# м'яка червона пляма світла
		var gc := Vector2(s.x * glow_center.x, s.y * glow_center.y)
		for i in 14:
			var t := float(i) / 13.0
			draw_circle(gc, lerpf(s.y * 0.75, s.y * 0.06, t), Color(0.55, 0.07, 0.12, 0.018))
		# карбонова штриховка
		var step := 7.0
		var x := -s.y
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x + s.y, s.y), Color(1, 1, 1, 0.014), 1.0)
			x += step
		if neon:
			_glow(Vector2(s.x * 1.0, s.y * 0.12), Vector2(s.x * 0.82, s.y * 0.2), 4.0)
			_glow(Vector2(0.0, s.y * 0.13), Vector2(s.x * 0.04, s.y * 0.11), 4.0)
			_glow(Vector2(s.x * 0.97, s.y * 0.9), Vector2(s.x * 0.8, s.y * 0.97), 3.0)
		# віньєтка по краях
		var edge := Color(0, 0, 0, 0.55)
		var clear := Color(0, 0, 0, 0)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.22, 0), Vector2(s.x * 0.22, s.y), Vector2(0, s.y)]),
			PackedColorArray([edge, clear, clear, edge]))
		draw_polygon(PackedVector2Array([Vector2(s.x * 0.78, 0), Vector2(s.x, 0), s, Vector2(s.x * 0.78, s.y)]),
			PackedColorArray([clear, edge, edge, clear]))

	func _glow(a: Vector2, b: Vector2, w: float) -> void:
		draw_line(a, b, Color(1.0, 0.16, 0.24, 0.06), w * 7.0, true)
		draw_line(a, b, Color(1.0, 0.16, 0.24, 0.16), w * 3.0, true)
		draw_line(a, b, Color(1.0, 0.45, 0.5, 0.95), w * 0.8, true)


# Плашка заголовка (трапеція з червоним краєм).
class TitlePlate extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cut := h * 0.42
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - cut, h), Vector2(cut, h)])
		draw_polygon(pts, PackedColorArray([Color("2a0f15"), Color("2a0f15"), Color("12090c"), Color("12090c")]))
		draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(cut, h), Vector2(w - cut, h), Vector2(w, 0)]),
			Color("e33a4e"), 2.0, true)


# 3D-превʼю моделі з гри (SubViewport). Підбирає масштаб і поворот сам, повільно гойдає модель.
class ModelPreview extends SubViewportContainer:
	var _packed: PackedScene
	var _skin: Texture2D   # якщо задано — накладається на модель як albedo (так само, як скін у грі)
	var _vp: SubViewport
	var _cam: Camera3D
	var _pivot: Node3D
	var _extent := Vector2(1, 1)   # (довжина, висота) моделі після повороту, у її одиницях
	var _t := 0.0
	var _ok := false

	func _init(packed: PackedScene, skin: Texture2D = null) -> void:
		_packed = packed
		_skin = skin
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.transparent_bg = true
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		add_child(_vp)

		var env := Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.78, 0.8, 0.88)
		env.ambient_light_energy = 0.7
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)

		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-40, 35, 0)
		key.light_energy = 1.2
		_vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-15, -140, 0)
		rim.light_color = Color(1.0, 0.35, 0.42)
		rim.light_energy = 0.9
		_vp.add_child(rim)

		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		var orient := Node3D.new()
		_pivot.add_child(orient)
		var model := _packed.instantiate() as Node3D
		if model == null:
			return
		orient.add_child(model)
		if _skin != null:
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = _skin
			sm.roughness = 0.55
			sm.metallic = 0.15
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = sm

		# Габарити по всіх видимих мешах (у координатах моделі).
		var box := AABB()
		var first := true
		var inv := model.global_transform.affine_inverse()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var b: AABB = (inv * m.global_transform) * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			return
		# Найдовша вісь -> горизонталь екрана.
		var long_i := 0
		for i in 3:
			if box.size[i] > box.size[long_i]:
				long_i = i
		match long_i:
			1: orient.basis = Basis(Vector3(0, 0, 1), PI / 2.0)
			2: orient.basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		var center := box.get_center()
		model.position = -center
		var sz := box.size
		var longest := maxf(sz[long_i], 0.0001)
		var others: Array[float] = []
		for i in 3:
			if i != long_i:
				others.append(sz[i])
		_extent = Vector2(longest, maxf(others[0], others[1]))

		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		var rad := box.size.length() * 0.5
		_cam.position = Vector3(0, 0, rad * 3.0)
		_cam.near = rad * 0.05
		_cam.far = rad * 8.0
		_vp.add_child(_cam)
		_ok = true
		resized.connect(_fit)
		_fit()

	func _fit() -> void:
		if not _ok or size.y <= 1.0:
			return
		var aspect := size.x / size.y
		# Ортогональна камера: size = висота кадру. Вмістити і довжину, і висоту (+ запас на гойдання).
		_cam.size = maxf(_extent.x * 1.18 / aspect, _extent.y * 2.4)

	func _process(delta: float) -> void:
		if not _ok:
			return
		_t += delta
		_pivot.rotation = Vector3(-0.18, sin(_t * 0.9) * 0.55, 0.0)


# Вітрина головного меню: воксельний терорист із калашем і простою «idle»-анімацією (все кодом, без ассетів).
# Модель — playersModels/terrorist_t1.glb (один меш без скелета, кольори з вершин — як у грі).
class TerroristStage extends SubViewportContainer:
	const MODEL_PATH := "res://playersModels/terrorist_t1.glb"
	const MODEL_PATH_ALT := "res://playersModels/terrorist_t1 (2).glb"
	const AK_PATH := "res://weapons/AK47.fbx"                 # справжня модель АК з гри
	const AK_DEFAULT_TEX := "res://всяка фігня/ak-47.jpg"     # текстура АК за замовчуванням (як у character.tscn)
	const AK_LENGTH := 0.92                                   # довжина АК у руках, метри
	# Авто-орієнтація може помилитись у моделі: якщо дуло дивиться назад / АК догори дриґом — поставити true.
	const AK_FLIP_MUZZLE := false
	const AK_FLIP_UP := true
	var _vp: SubViewport
	var _pivot: Node3D
	var _body: Node3D
	var _rifle: Node3D
	var _wood_mat: StandardMaterial3D
	var _ak_mat: StandardMaterial3D   # матеріал справжнього АК (текстура/скін)
	var _ak_nodes: Array[MeshInstance3D] = []
	var _ring_mat: StandardMaterial3D
	var _ak_skin := ""   # id скіна АК; запамʼятовуємо, бо set_ak_skin може бути викликаний до _ready
	var _t := 0.0

	func _init() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.transparent_bg = true
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		add_child(_vp)

		var env := Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.78)
		env.ambient_light_energy = 0.75
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)

		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-35, 30, 0)
		key.light_energy = 1.25
		_vp.add_child(key)
		var rim := DirectionalLight3D.new()   # червоний контровий — як неон у меню
		rim.rotation_degrees = Vector3(-20, -150, 0)
		rim.light_color = Color(1.0, 0.3, 0.4)
		rim.light_energy = 1.4
		_vp.add_child(rim)

		var cam := Camera3D.new()
		cam.fov = 28.0
		cam.position = Vector3(0, 1.05, 5.3)
		cam.rotation_degrees = Vector3(-2.0, 0, 0)
		_vp.add_child(cam)

		# Невеликий постамент із червоним неоновим кантом.
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.8
		cm.bottom_radius = 0.85
		cm.height = 0.08
		disc.mesh = cm
		disc.position = Vector3(0, -0.04, 0)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color("15171d")
		dm.roughness = 0.5
		dm.metallic = 0.6
		disc.material_override = dm
		_vp.add_child(disc)
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.86
		rm.bottom_radius = 0.86
		rm.height = 0.02
		ring.mesh = rm
		ring.position = Vector3(0, -0.06, 0)
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = Color(1.0, 0.2, 0.3)
		_ring_mat.emission_enabled = true
		_ring_mat.emission = Color(1.0, 0.2, 0.3)
		_ring_mat.emission_energy_multiplier = 2.0
		ring.material_override = _ring_mat
		_vp.add_child(ring)

		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		_body = Node3D.new()
		_pivot.add_child(_body)

		var packed: PackedScene = null
		if ResourceLoader.exists(MODEL_PATH):
			packed = load(MODEL_PATH) as PackedScene
		if packed == null and ResourceLoader.exists(MODEL_PATH_ALT):
			packed = load(MODEL_PATH_ALT) as PackedScene   # та сама модель, дубль-файл
		if packed != null:
			var model := packed.instantiate() as Node3D
			if model != null:
				_body.add_child(model)
				# Той самий матеріал, що й у грі (character.tscn): колір беремо з вершин.
				var vm := StandardMaterial3D.new()
				vm.vertex_color_use_as_albedo = true
				vm.roughness = 0.85
				for mi in model.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = vm

		_rifle = _build_real_rifle()
		if _rifle == null:
			_rifle = _build_rifle()   # запасний воксельний АК, якщо моделі нема в проєкті
		_rifle.position = Vector3(0.05, 1.0, 0.31)
		_rifle.rotation = Vector3(0.0, -0.3, 0.12)
		# _build_real_rifle() уже додає root до _body; fallback-модель ще не має батька.
		if _rifle.get_parent() == null:
			_body.add_child(_rifle)
		set_ak_skin(_ak_skin)
		_pivot.rotation.y = -0.35

	# Воксельний АК із боксів (дуло в бік +X), під стиль моделі терориста.
	func _build_rifle() -> Node3D:
		var root := Node3D.new()
		var steel := _mat(Color("2a2d33"), 0.4)
		_wood_mat = _mat(Color("7a4a24"), 0.8)
		_box(root, Vector3(0.30, 0.07, 0.05), Vector3(0.0, 0.0, 0.0), steel)        # ствольна коробка
		_box(root, Vector3(0.34, 0.022, 0.022), Vector3(0.30, 0.0, 0.0), steel)     # ствол
		_box(root, Vector3(0.22, 0.026, 0.026), Vector3(0.24, 0.034, 0.0), steel)   # газова трубка
		_box(root, Vector3(0.04, 0.034, 0.034), Vector3(0.49, 0.0, 0.0), steel)     # дулове гальмо
		_box(root, Vector3(0.015, 0.05, 0.015), Vector3(0.44, 0.03, 0.0), steel)    # мушка
		_box(root, Vector3(0.18, 0.05, 0.052), Vector3(0.19, -0.004, 0.0), _wood_mat)   # цівка
		_box(root, Vector3(0.24, 0.075, 0.042), Vector3(-0.27, -0.012, 0.0), _wood_mat) # приклад
		_box(root, Vector3(0.05, 0.10, 0.04), Vector3(-0.07, -0.08, 0.0), _wood_mat, -0.25)  # руків'я
		_box(root, Vector3(0.05, 0.15, 0.036), Vector3(0.06, -0.105, 0.0), steel, 0.28)      # магазин
		return root

	static func _mat(c: Color, rough: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		return m

	static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_z: float = 0.0) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = pos
		mi.rotation.z = rot_z
		mi.material_override = mat
		parent.add_child(mi)

	# Скін АК: ті самі вузли, що й у грі (Cube_003, Cube), отримують текстуру скіна, інакше — стандартну ak-47.jpg.
	func set_ak_skin(skin_id: String) -> void:
		_ak_skin = skin_id
		if _ak_mat != null:
			var path := "res://skins/%s.png" % skin_id if skin_id != "" else AK_DEFAULT_TEX
			if not ResourceLoader.exists(path):
				path = AK_DEFAULT_TEX
			var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
			for n in _ak_nodes:
				n.material_override = _ak_mat if tex != null else null   # нема текстури — лишаємо рідні матеріали моделі
			if tex != null:
				_ak_mat.albedo_texture = tex
		elif _wood_mat != null:
			_wood_mat.albedo_color = Color("b3202f") if skin_id != "" else Color("7a4a24")

	# Справжній АК із проєкту: сам вирівнюємо (довга вісь -> X, дуло -> +X, магазин -> вниз) і масштабуємо до AK_LENGTH.
	func _build_real_rifle() -> Node3D:
		if not ResourceLoader.exists(AK_PATH):
			return null
		var packed := load(AK_PATH) as PackedScene
		if packed == null:
			return null
		var model := packed.instantiate() as Node3D
		if model == null:
			return null
		var root := Node3D.new()
		var holder := Node3D.new()
		root.add_child(holder)
		holder.add_child(model)
		_body.add_child(root)   # у дерево, щоб працювали global_transform

		# Вершини всіх мешів у координатах моделі.
		var pts := PackedVector3Array()
		var inv := model.global_transform.affine_inverse()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var xf: Transform3D = inv * m.global_transform
			for si in m.mesh.get_surface_count():
				var arrays := m.mesh.surface_get_arrays(si)
				if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					pts.append(xf * v)
		if pts.size() < 8:
			root.queue_free()
			return null
		var lo: Vector3 = pts[0]
		var hi: Vector3 = pts[0]
		var mean := Vector3.ZERO
		for v in pts:
			lo = lo.min(v)
			hi = hi.max(v)
			mean += v
		mean /= float(pts.size())
		var ext := hi - lo
		# Осі за довжиною: найдовша = ствол, друга = висота (магазин/приціл), третя = товщина.
		var idx := [0, 1, 2]
		idx.sort_custom(func(p: int, q: int): return ext[p] > ext[q])
		var li: int = idx[0]
		var hi_i: int = idx[1]
		var wi: int = idx[2]
		# Дуло — той кінець, де переріз тонший (на кінці приклада товщий).
		var span := ext[li]
		var end_lo_min := 1e20
		var end_lo_max := -1e20
		var end_hi_min := 1e20
		var end_hi_max := -1e20
		for v in pts:
			var t: float = (v[li] - lo[li]) / maxf(span, 0.0001)
			if t < 0.12:
				end_lo_min = minf(end_lo_min, v[hi_i])
				end_lo_max = maxf(end_lo_max, v[hi_i])
			elif t > 0.88:
				end_hi_min = minf(end_hi_min, v[hi_i])
				end_hi_max = maxf(end_hi_max, v[hi_i])
		var muzzle_at_max := (end_hi_max - end_hi_min) < (end_lo_max - end_lo_min)
		if AK_FLIP_MUZZLE:
			muzzle_at_max = not muzzle_at_max
		# «Низ»: магазин і руків'я тягнуть масу вниз -> центр мас лежить нижче середини габариту.
		var mid_h := (lo[hi_i] + hi[hi_i]) * 0.5
		var min_is_bottom := mean[hi_i] < mid_h
		if AK_FLIP_UP:
			min_is_bottom = not min_is_bottom
		var cols := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		cols[li] = Vector3(1 if muzzle_at_max else -1, 0, 0)
		cols[hi_i] = Vector3(0, 1 if min_is_bottom else -1, 0)
		cols[wi] = Vector3(0, 0, 1)
		var bs := Basis(cols[0], cols[1], cols[2])
		if bs.determinant() < 0.0:
			cols[wi] = Vector3(0, 0, -1)
			bs = Basis(cols[0], cols[1], cols[2])
		var k := AK_LENGTH / maxf(span, 0.0001)
		var center := (lo + hi) * 0.5
		holder.transform = Transform3D(bs.scaled(Vector3(k, k, k)), -(bs * center) * k)

		# Текстура — як у грі: Cube_003 і Cube мають матеріал із текстурою, решта — рідні матеріали моделі.
		_ak_mat = StandardMaterial3D.new()
		_ak_mat.roughness = 0.6
		for nm in ["Cube_003", "Cube"]:
			var n := model.find_child(nm, true, false) as MeshInstance3D
			if n != null:
				_ak_nodes.append(n)
		return root

	# Проста idle-анімація: дихання, легке погойдування, повільний поворот, АК «живе» разом із тілом.
	func _process(delta: float) -> void:
		if _pivot == null or not is_visible_in_tree():
			return
		_t += delta
		_pivot.rotation.y = -0.35 + sin(_t * 0.55) * 0.22
		_body.position.y = sin(_t * 1.8) * 0.012
		_body.scale = Vector3(1.0, 1.0 + sin(_t * 1.8 + 0.4) * 0.006, 1.0)
		_body.rotation.z = sin(_t * 0.9) * 0.012
		if _rifle != null:
			_rifle.rotation.z = 0.12 + sin(_t * 1.8 + 0.9) * 0.02
			_rifle.position.y = 1.0 + sin(_t * 1.8 + 0.6) * 0.008
		if _ring_mat != null:
			_ring_mat.emission_energy_multiplier = 2.0 + sin(_t * 2.2) * 0.5


# Плаский арт скіна, що крутиться в 3D: кілька шарів дають товщину, зворотний бік — дзеркало (зброя «дивиться» в інший бік).
class SpinCard extends SubViewportContainer:
	var _tex: Texture2D
	var _mirror := true
	var _vp: SubViewport
	var _cam: Camera3D
	var _pivot: Node3D
	var _aspect := 1.0
	var _t := 0.0

	func _init(tex: Texture2D, mirror: bool = true) -> void:
		_tex = tex
		_mirror = mirror
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.transparent_bg = true
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		add_child(_vp)
		_aspect = float(_tex.get_width()) / maxf(float(_tex.get_height()), 1.0)

		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		var layers := 9
		var depth := 0.05
		for i in layers:
			var f := float(i) / float(layers - 1)           # 0 = задній шар, 1 = передній
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(_aspect, 1.0)
			mi.mesh = qm
			mi.position.z = lerpf(-depth, depth, f)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.albedo_texture = _tex
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var edge := 1.0 if (i == 0 or i == layers - 1) else 0.35   # проміжні шари темніші — виглядає як торець
			m.albedo_color = Color(edge, edge, edge, 1.0)
			if _mirror:
				m.uv1_scale = Vector3(-1, 1, 1)
				m.uv1_offset = Vector3(1, 0, 0)
			mi.material_override = m
			_pivot.add_child(mi)

		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.position = Vector3(0, 0, 4.0)
		_cam.near = 0.1
		_cam.far = 10.0
		_vp.add_child(_cam)
		resized.connect(_fit)
		_fit()

	func _fit() -> void:
		if _cam == null or size.y <= 1.0:
			return
		var ca := size.x / size.y
		_cam.size = maxf(_aspect * 1.08 / ca, 1.25)

	func _process(delta: float) -> void:
		if _pivot == null or not is_visible_in_tree():
			return
		_t += delta
		_pivot.rotation = Vector3(-0.12, _t * 0.9, 0.0)


# ---------------------------------------------------------------- пошук моделей у проєкті
# Моделі зброї/ножів не лежать у патчі зі скінами, а живуть у проєкті (.glb/.tscn). Щоб не вгадувати шляхи,
# один раз скануємо res:// і шукаємо файл за ключовими словами в назві. Свої шляхи можна вписати в MODEL_OVERRIDE.
const MODEL_OVERRIDE := {
	# "bolisong": "res://models/bolisong.glb",
}
const MODEL_KEYWORDS := {
	"ak47": ["ak47", "ak_47", "ak-47"],
	"awp": ["awp"],
	"m4": ["m4a1"],
	"bolisong": ["bolisong", "balisong"],
	"karambit": ["karambit", "karanbit"],
	"butterfly": ["butterfly"],
	"m9": ["m9_bayonet", "m9bayonet"],
}
static var _scan_done := false
static var _found: Array = []
static var _model_cache: Dictionary = {}


static func _scan(dir: String, depth: int = 0) -> void:
	if depth > 6:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with(".") and n != "addons":
				_scan(dir.path_join(n), depth + 1)
		else:
			var f := n
			if f.ends_with(".import"):
				f = f.trim_suffix(".import")
			elif f.ends_with(".remap"):
				f = f.trim_suffix(".remap")
			if f.get_extension().to_lower() in ["glb", "gltf", "fbx", "scn", "tscn"]:
				var p := dir.path_join(f)
				if not _found.has(p):
					_found.append(p)
		n = d.get_next()
	d.list_dir_end()


static func find_model(key: String) -> PackedScene:
	if _model_cache.has(key):
		return _model_cache[key]
	var result: PackedScene = null
	var path := str(MODEL_OVERRIDE.get(key, ""))
	if path == "":
		if not _scan_done:
			_scan_done = true
			_scan("res://")
		var best := ""
		var best_rank := 1 << 30
		for p in _found:
			var base: String = String(p).get_file().get_basename().to_lower()
			var hit := false
			for kw in MODEL_KEYWORDS.get(key, []):
				if base.contains(kw):
					hit = true
			if not hit:
				continue
			var ext := String(p).get_extension().to_lower()
			var rank := (0 if ext == "glb" else 1 if ext == "gltf" else 2 if ext == "fbx" else 3) * 1000 + base.length()
			if rank < best_rank:
				best_rank = rank
				best = p
		path = best
	if path != "" and ResourceLoader.exists(path):
		result = load(path) as PackedScene
	_model_cache[key] = result
	return result


# ---------------------------------------------------------------- превʼю предмета
# skin_id != "" -> реальний малюнок скіна з гри; інакше 3D-модель з проєкту; якщо моделі немає — силует.
# model_key: "ak47" / "awp" / id ножа ("bolisong", "karambit", "butterfly", "m9").
static func make_preview(model_key: String, skin_id: String, steel: Color = Color("8e98ab"), allow_3d: bool = true, spin: bool = false) -> Control:
	# AWP зі скіном: показуємо справжню 3D-модель гри зі скіном на ній, а не плоский арт у стилі CS2.
	# Вимкнути/додати інші зброї: SKIN_ON_MODEL.
	if skin_id != "" and allow_3d and SKIN_ON_MODEL.has(model_key):
		var sp := "res://skins/%s.png" % skin_id
		var packed3d := find_model(model_key)
		if packed3d != null and ResourceLoader.exists(sp):
			return ModelPreview.new(packed3d, load(sp) as Texture2D)
	if skin_id != "":
		var art: Texture2D = SKIN_ART.get(skin_id)
		if art == null:
			var p := "res://skins/%s.png" % skin_id
			if ResourceLoader.exists(p):
				art = load(p) as Texture2D
		if art != null:
			if spin:
				return SpinCard.new(art, MIRROR_SKINS)
			var flat := _tex(art)
			flat.flip_h = MIRROR_SKINS
			return flat
	if allow_3d:
		var packed := find_model(model_key)
		if packed != null:
			return ModelPreview.new(packed)
	if WEAPON_SHAPE.has(model_key):
		return silhouette(WEAPON_SHAPE[model_key], steel)
	return BladeIcon.new(steel)


static func _tex(t: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func silhouette(t: Texture2D, color: Color) -> TextureRect:
	var r := _tex(t)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() { COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	r.material = mat
	return r
