extends CanvasLayer
# Бойовий HUD локального гравця (створюється в player.gd лише для власника ноди):
#   1) червоне затемнення по краях екрана при отриманні урону (+ пульсація при малому HP);
#   2) HP у стилі CS2 (хрестик, велике число, смужка);
#   3) картки серії вбивств у стилі CS2: віялом ("як у колоді"), з променем світла,
#      який плавно зникає за 1 секунду після кіла, іскрами та емблемою.
#
# Виклики ззовні:
#   set_health(hp, max_hp)  - оновити HP
#   on_damage(amount)       - гравець отримав урон
#   on_death() / on_revive()
#   add_kill(headshot)      - гравець вбив суперника (викликає weapon_switch.gd)
#   reset_streak()          - скинути серію вбивств

const LOW_HP: float = 30.0
const MAX_CARDS: int = 12
const BAR_W: float = 214.0
const BEAM_FADE_DURATION: float = 1.0

const TEX_DIR := "res://textures/kill_hud/"
const TEX_CARD_NORMAL := TEX_DIR + "card_normal.png"
const TEX_CARD_HEADSHOT := TEX_DIR + "card_headshot.png"
const TEX_CARD_ACE := TEX_DIR + "card_ace.png"
const TEX_EMBLEM := TEX_DIR + "emblem.png"
const TEX_SPARK := TEX_DIR + "spark.png"
const TEX_BEAM := TEX_DIR + "light_beam.png"

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.02, 0.02, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 0.85);
	float d = length(p) * 1.414;
	float v = smoothstep(0.35, 1.0, d);
	COLOR = vec4(tint.rgb, clamp(v * 1.25, 0.0, 1.0) * intensity);
}
"""

const BASELINE_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform vec4 core_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.88, 0.50, 1.0);
uniform float intensity = 1.4;
void fragment() {
	vec2 uv = UV;
	float xd = abs(uv.x - 0.5) * 2.0;
	float yd = abs(uv.y - 0.5) * 2.0;
	float a = pow(clamp(1.0 - xd, 0.0, 1.0), 1.6) * pow(clamp(1.0 - yd, 0.0, 1.0), 3.5);
	vec3 col = mix(core_color.rgb, hot_color.rgb, a * 0.55);
	COLOR = vec4(col * intensity, clamp(a * core_color.a, 0.0, 1.0));
}
"""

var _max_hp: float = 100.0
var _hp: float = 100.0
var _dead: bool = false
var _time: float = 0.0

var _hit: float = 0.0
var _hit_tween: Tween = null
var _vignette_mat: ShaderMaterial = null

var _hp_icon: Control = null
var _hp_num: Label = null
var _hp_fill: ColorRect = null
var _hp_tween: Tween = null
var _num_tween: Tween = null

var _fps_num: Label = null
var _fps_timer: float = 0.0
var _fps_shown: int = -1

var _kill_anchor: Control = null
var _baseline: ColorRect = null
var _emblem_node: Control = null
var _cards_fan: Control = null
var _card_list: Array[Control] = []
var _fade_tween: Tween = null
var _streak: int = 0

var _add_mat: CanvasItemMaterial = null
var _tex_card_normal: Texture2D = null
var _tex_card_headshot: Texture2D = null
var _tex_card_ace: Texture2D = null
var _tex_emblem: Texture2D = null
var _tex_spark: Texture2D = null
var _tex_beam: Texture2D = null


func _ready() -> void:
	layer = 4
	add_to_group("combat_hud")
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_load_textures()
	_build_vignette()
	_build_hp_panel()
	_build_cards()
	_build_fps_counter()
	set_health(_max_hp, _max_hp)


func _load_textures() -> void:
	_tex_card_normal = _try_load_tex(TEX_CARD_NORMAL)
	_tex_card_headshot = _try_load_tex(TEX_CARD_HEADSHOT)
	_tex_card_ace = _try_load_tex(TEX_CARD_ACE)
	_tex_emblem = _try_load_tex(TEX_EMBLEM)
	_tex_spark = _try_load_tex(TEX_SPARK)
	if _tex_spark == null:
		_tex_spark = _make_fallback_spark_tex()
	_tex_beam = _try_load_tex(TEX_BEAM)
	if _tex_beam == null:
		_tex_beam = _make_fallback_beam_tex()


func _try_load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _make_fallback_spark_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.8, 0.3, 0.7), Color(1, 0.4, 0.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 16
	tex.height = 16
	return tex


func _make_fallback_beam_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.65, 0.2, 0.0), Color(1, 0.65, 0.2, 0.9)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 32
	tex.height = 128
	return tex


# ------------------------------------------------------------------
# ПОБУДОВА UI
# ------------------------------------------------------------------

func _build_vignette() -> void:
	var rect := ColorRect.new()
	rect.name = "DamageVignette"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = shader
	rect.material = _vignette_mat
	add_child(rect)


func _build_hp_panel() -> void:
	var root := Control.new()
	root.name = "HpPanel"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.0
	root.anchor_right = 0.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 28.0
	root.offset_right = 28.0 + 250.0
	root.offset_top = -112.0
	root.offset_bottom = -28.0
	add_child(root)

	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.65)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 4
	sb.border_color = Color(1.0, 1.0, 1.0, 0.85)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)

	_hp_icon = Control.new()
	_hp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_icon.position = Vector2(20.0, 14.0)
	_hp_icon.custom_minimum_size = Vector2(34.0, 34.0)
	_hp_icon.size = Vector2(34.0, 34.0)
	_hp_icon.draw.connect(_draw_icon)
	root.add_child(_hp_icon)

	_hp_num = Label.new()
	_hp_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_num.position = Vector2(66.0, 0.0)
	_hp_num.size = Vector2(170.0, 62.0)
	_hp_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_num.add_theme_font_size_override("font_size", 50)
	_hp_num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hp_num.add_theme_constant_override("outline_size", 6)
	root.add_child(_hp_num)

	var bar_bg := ColorRect.new()
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.color = Color(1.0, 1.0, 1.0, 0.16)
	bar_bg.position = Vector2(20.0, 64.0)
	bar_bg.size = Vector2(BAR_W, 6.0)
	root.add_child(bar_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.position = Vector2.ZERO
	_hp_fill.size = Vector2(BAR_W, 6.0)
	bar_bg.add_child(_hp_fill)


func _build_cards() -> void:
	_kill_anchor = Control.new()
	_kill_anchor.name = "KillHudAnchor"
	_kill_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_anchor.anchor_left = 0.5
	_kill_anchor.anchor_right = 0.5
	_kill_anchor.anchor_top = 1.0
	_kill_anchor.anchor_bottom = 1.0
	_kill_anchor.offset_top = -48.0
	_kill_anchor.offset_bottom = -48.0
	_kill_anchor.visible = false
	add_child(_kill_anchor)

	# Тонка горизонтальна лінія світіння внизу (як у CS2)
	_baseline = ColorRect.new()
	_baseline.size = Vector2(480.0, 3.0)
	_baseline.position = Vector2(-240.0, -1.5)
	_baseline.color = Color(0, 0, 0, 0)
	_baseline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_shader := Shader.new()
	line_shader.code = BASELINE_SHADER
	var line_mat := ShaderMaterial.new()
	line_mat.shader = line_shader
	_baseline.material = line_mat
	_kill_anchor.add_child(_baseline)

	# Вільний контейнер для віяла карток ("як у колоді")
	_cards_fan = Control.new()
	_cards_fan.name = "KillCardsFan"
	_cards_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_fan.position = Vector2(0.0, -68.0)
	_kill_anchor.add_child(_cards_fan)

	# Центральна емблема поверх основи віяла
	_emblem_node = _create_emblem()
	_emblem_node.position = Vector2(-26.0, -26.0)
	_emblem_node.z_index = 20
	_kill_anchor.add_child(_emblem_node)


func _create_emblem() -> Control:
	if _tex_emblem != null:
		var tr := TextureRect.new()
		tr.texture = _tex_emblem
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(52.0, 52.0)
		tr.pivot_offset = Vector2(26.0, 26.0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr

	var badge := Panel.new()
	badge.size = Vector2(52.0, 52.0)
	badge.pivot_offset = Vector2(26.0, 26.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	sb.border_color = Color(0.96, 0.96, 0.96, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(26)
	badge.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = "✦"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.78, 0.24, 1.0))
	badge.add_child(lbl)
	return badge


# ------------------------------------------------------------------
# HP
# ------------------------------------------------------------------

func _hp_color() -> Color:
	if _dead or _hp <= 0.0:
		return Color(1.0, 0.22, 0.22)
	if _hp <= LOW_HP:
		return Color(1.0, 0.27, 0.22)
	if _hp <= 60.0:
		return Color(1.0, 0.72, 0.25)
	return Color(0.97, 0.97, 0.97)


func _draw_icon() -> void:
	var col := _hp_color()
	_hp_icon.draw_rect(Rect2(12.0, 2.0, 10.0, 30.0), col)
	_hp_icon.draw_rect(Rect2(2.0, 12.0, 30.0, 10.0), col)


func set_health(hp: float, max_hp: float = -1.0) -> void:
	if max_hp > 0.0:
		_max_hp = max_hp
	_hp = clampf(hp, 0.0, _max_hp)
	if _hp_num == null:
		return
	var col := _hp_color()
	_hp_num.text = str(int(ceil(_hp)))
	_hp_num.add_theme_color_override("font_color", col)
	_hp_fill.color = col
	_hp_icon.queue_redraw()

	var w: float = BAR_W * (_hp / _max_hp if _max_hp > 0.0 else 0.0)
	if _hp_tween:
		_hp_tween.kill()
	_hp_tween = create_tween()
	_hp_tween.tween_property(_hp_fill, "size:x", w, 0.15)


# ------------------------------------------------------------------
# УРОН / СМЕРТЬ
# ------------------------------------------------------------------

func on_damage(amount: float) -> void:
	var strength: float = clampf(0.4 + amount / 70.0, 0.4, 1.0)
	_hit = maxf(_hit, strength)
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "_hit", 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if _num_tween:
		_num_tween.kill()
	_hp_num.pivot_offset = Vector2(20.0, 31.0)
	_hp_num.scale = Vector2(1.18, 1.18)
	_hp_num.modulate = Color(1.0, 0.45, 0.45)
	_num_tween = create_tween().set_parallel(true)
	_num_tween.tween_property(_hp_num, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_num_tween.tween_property(_hp_num, "modulate", Color.WHITE, 0.35)


func on_death() -> void:
	_dead = true
	set_health(0.0)
	reset_streak()
	_hit = 0.85
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "_hit", 0.0, 1.4)


func on_revive() -> void:
	_dead = false
	_hit = 0.0
	if _hit_tween:
		_hit_tween.kill()
	set_health(_max_hp, _max_hp)


func _process(delta: float) -> void:
	_time += delta
	var base: float = 0.0
	if _dead:
		base = 0.45
	elif _hp <= LOW_HP:
		base = 0.22 + 0.12 * (0.5 + 0.5 * sin(_time * 5.0))
	if _vignette_mat:
		_vignette_mat.set_shader_parameter("intensity", clampf(maxf(_hit, base), 0.0, 1.0))
	_update_fps(delta)


# ------------------------------------------------------------------
# ЛІЧИЛЬНИК FPS (лівий верхній кут)
# ------------------------------------------------------------------
const FPS_FONT_BOLD := "res://fonts/Rajdhani-Bold.ttf"
const FPS_FONT_SEMI := "res://fonts/Rajdhani-SemiBold.ttf"
const FPS_COLOR_GOOD := Color(0.55, 0.95, 1.0, 1.0)    # холодний блакитний
const FPS_COLOR_MID := Color(0.78, 0.86, 1.0, 1.0)     # ніжно-бузковий
const FPS_COLOR_LOW := Color(1.0, 0.45, 0.5, 1.0)      # коралово-червоний


func _fps_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	# Запасний варіант, якщо шрифт ще не імпортований: гарні системні шрифти.
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Rajdhani", "Bahnschrift", "Segoe UI Semibold", "Consolas", "Arial"])
	sf.font_weight = 700
	return sf


func _build_fps_counter() -> void:
	var box := HBoxContainer.new()
	box.name = "FpsCounter"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(16, 10)
	add_child(box)

	_fps_num = Label.new()
	_fps_num.text = "--"
	_fps_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_num.add_theme_font_override("font", _fps_font(FPS_FONT_BOLD))
	_fps_num.add_theme_font_size_override("font_size", 28)
	_fps_num.add_theme_color_override("font_color", FPS_COLOR_GOOD)
	_fps_num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_num.add_theme_constant_override("outline_size", 6)
	box.add_child(_fps_num)

	var tag := Label.new()
	tag.text = "FPS"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_override("font", _fps_font(FPS_FONT_SEMI))
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tag.add_theme_constant_override("outline_size", 4)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	tag.add_theme_constant_override("line_spacing", 0)
	box.add_child(tag)


func _update_fps(delta: float) -> void:
	if _fps_num == null:
		return
	_fps_timer -= delta
	if _fps_timer > 0.0:
		return
	_fps_timer = 0.25   # оновлюємо 4 рази на секунду — число не мерехтить
	var fps: int = int(Engine.get_frames_per_second())
	if fps == _fps_shown:
		return
	_fps_shown = fps
	_fps_num.text = str(fps)
	var col: Color = FPS_COLOR_GOOD
	if fps < 30:
		col = FPS_COLOR_LOW
	elif fps < 60:
		col = FPS_COLOR_MID
	_fps_num.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------
# КАРТКИ СЕРІЇ ВБИВСТВ (ВІЯЛО ЯК У КОЛОДІ + ПЛАВНЕ ЗНИКНЕННЯ ПРОМЕНЯ)
# ------------------------------------------------------------------

func add_kill(headshot: bool = false) -> void:
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	_kill_anchor.visible = true
	_kill_anchor.modulate.a = 1.0

	_streak += 1
	if _card_list.size() >= MAX_CARDS:
		var old: Control = _card_list.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var is_ace := (_streak == 5)
	var accent := Color(1.0, 0.78, 0.18) if is_ace else (Color(1.0, 0.28, 0.14) if headshot else Color(1.0, 0.48, 0.10))
	var card_tex := _tex_card_ace if is_ace else (_tex_card_headshot if headshot else _tex_card_normal)

	var card := _create_cs2_card(_streak, headshot, is_ace, accent, card_tex)
	_cards_fan.add_child(card)
	_card_list.append(card)

	_relayout_fan()

	# Анімація появи самої картки
	card.modulate.a = 0.0
	card.scale = Vector2(1.45, 1.45)
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.12)

	# Промінь світла: яскраво з'являється і плавно зникає за 1 секунду
	var beam := card.get_node_or_null("LightBeam") as TextureRect
	if beam:
		beam.modulate = Color(accent.r * 1.15, accent.g * 1.15, accent.b * 1.15, 1.0)
		var b_tw := card.create_tween()
		b_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		b_tw.tween_property(beam, "modulate:a", 0.0, BEAM_FADE_DURATION)
		b_tw.tween_callback(beam.queue_free)

	# Пульс центральної емблеми
	_emblem_node.scale = Vector2(1.24, 1.24)
	var e_tw := create_tween()
	e_tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	e_tw.tween_property(_emblem_node, "scale", Vector2.ONE, 0.32)


func _relayout_fan() -> void:
	var count := _card_list.size()
	if count == 0:
		return

	# Параметри віяла: легкий нахил і дуга, як карти в руці/колоді
	var step_x: float = 25.0 if count <= 5 else maxf(16.0, 125.0 / float(count))
	var max_angle: float = minf(24.0, float(count - 1) * 7.5)
	var half_w := 24.0
	var half_h := 34.0

	for i in count:
		var card := _card_list[i]
		if not is_instance_valid(card):
			continue
		var t: float = 0.0 if count == 1 else (float(i) / float(count - 1)) * 2.0 - 1.0 # -1 .. +1
		var target_x: float = t * (float(count - 1) * 0.5 * step_x) - half_w
		var target_y: float = (t * t) * 9.0 - half_h
		var target_rot: float = t * max_angle

		card.z_index = i
		var tw := card.create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", Vector2(target_x, target_y), 0.22)
		tw.tween_property(card, "rotation_degrees", target_rot, 0.22)


func _create_cs2_card(idx: int, hs: bool, is_ace: bool, accent: Color, card_tex: Texture2D) -> Control:
	var holder := Control.new()
	holder.size = Vector2(48.0, 68.0)
	holder.pivot_offset = Vector2(24.0, 56.0) # обертання від нижньої частини, як у віялі колоди
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1. Вертикальний промінь світла (чиста текстура + ADD blending, без жодних рамок)
	var beam := TextureRect.new()
	beam.name = "LightBeam"
	beam.texture = _tex_beam
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.size = Vector2(68.0, 220.0)
	beam.position = Vector2(24.0 - 34.0, -185.0)
	beam.material = _add_mat
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(beam)

	# 2. Одноразовий спалах іскор при кілі
	var sparks := GPUParticles2D.new()
	sparks.position = Vector2(24.0, 32.0)
	sparks.amount = 20 if (hs or is_ace) else 12
	sparks.lifetime = 0.95
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.texture = _tex_spark
	sparks.material = _add_mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16.0, 12.0, 0.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 45.0
	pm.initial_velocity_min = 35.0
	pm.initial_velocity_max = 95.0
	pm.gravity = Vector3(0.0, -15.0, 0.0)
	pm.scale_min = 0.22
	pm.scale_max = 0.55
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.96, 0.72, 1), Color(accent.r, accent.g, accent.b, 0.85), Color(accent.r, accent.g * 0.4, 0, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	sparks.process_material = pm
	sparks.emitting = true
	holder.add_child(sparks)

	# 3. Сама картка (текстура або процедурна картка)
	if card_tex != null:
		var tr := TextureRect.new()
		tr.texture = card_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	else:
		var fallback := Panel.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(accent.r * 0.35, accent.g * 0.25, accent.b * 0.12, 0.94)
		sb.border_color = accent.lightened(0.4)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		fallback.add_theme_stylebox_override("panel", sb)
		holder.add_child(fallback)

	# Номер кіла у серії
	var num_lbl := Label.new()
	num_lbl.position = Vector2(7.0, 5.0)
	num_lbl.text = "A" if is_ace else str(idx)
	num_lbl.add_theme_font_size_override("font_size", 11)
	num_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 0.95))
	num_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	num_lbl.add_theme_constant_override("outline_size", 3)
	holder.add_child(num_lbl)

	return holder


func reset_streak() -> void:
	if _streak == 0 and _card_list.is_empty():
		return
	_streak = 0
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_kill_anchor, "modulate:a", 0.0, 0.45)
	_fade_tween.tween_callback(_clear_cards)


func _clear_cards() -> void:
	for c in _card_list:
		if is_instance_valid(c):
			c.queue_free()
	_card_list.clear()
	_kill_anchor.visible = false
	_kill_anchor.modulate.a = 1.0
