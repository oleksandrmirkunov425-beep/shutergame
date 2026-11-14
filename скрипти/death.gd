extends RefCounted
# Візуальна частина смерті гравця: анімація "die" + камера від третьої особи.
# Створюється в player.gd:  _death = PlayerDeath.new(self, death_anim, death_cam)
#   play()  — гравець загинув (викликається на ВСІХ клієнтах, тож суперник теж бачить падіння)
#   reset() — гравець відродився, все повертається як було

const DIE_ANIM := "die"
const TEAM_CT := 0   # має збігатися з Player.Team у player.gd

var _player: CharacterBody3D
var _anim: AnimationPlayer
var _cam: Camera3D


func _init(player: CharacterBody3D, anim: AnimationPlayer, cam: Camera3D) -> void:
	_player = player
	_anim = anim
	_cam = cam


func play() -> void:
	if _anim and _anim.has_animation(DIE_ANIM):
		_anim.stop()
		_anim.play(DIE_ANIM)

	# Камеру смерті вмикаємо тільки власнику; суперник камеру не міняє.
	if _player.is_multiplayer_authority():
		_enter_death_view()


func reset() -> void:
	if _anim and _anim.has_animation(DIE_ANIM):
		_anim.stop()
		_anim.assigned_animation = DIE_ANIM
		_anim.seek(0.0, true)   # перший ключ анімації = нормальна поза
		_anim.stop()

	if _player.is_multiplayer_authority():
		_exit_death_view()


func _enter_death_view() -> void:
	if _cam:
		_cam.current = true
	_player.head.visible = false   # ховає руки й зброю від першої особи

	# Свою модель у цей момент показуємо, бо камера тепер збоку.
	var is_ct: bool = _player.team == TEAM_CT
	if _player.model_ct:
		_player.model_ct.visible = is_ct
	if _player.model_t:
		_player.model_t.visible = not is_ct


func _exit_death_view() -> void:
	if _cam:
		_cam.current = false
	_player.camera.current = true
	_player.head.visible = true
	# модель знову ховає _apply_team_visual() у _revive()
