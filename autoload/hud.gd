extends Node

enum State { WAITING, COUNTDOWN, PLAYING, ROUND_END, GAME_OVER }

var timer_label: Label
var score_label: Label
var damage_label: Label
var _scores: Dictionary = {}
var _damage_hide_timer: SceneTreeTimer = null


func _ready() -> void:
	call_deferred("_find_labels")
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _find_labels() -> void:
	timer_label = get_tree().get_first_node_in_group("round_timer_label")
	score_label = get_tree().get_first_node_in_group("score_label")
	damage_label = get_tree().get_first_node_in_group("damage_label")
	if damage_label:
		damage_label.visible = false


func set_state(state: int, value: int) -> void:
	if not timer_label or not score_label:
		_find_labels()

	match state:
		State.WAITING:
			if timer_label:
				timer_label.text = "Очікування другого гравця..."
				timer_label.visible = true
			if score_label:
				score_label.visible = false
		State.COUNTDOWN:
			if timer_label:
				timer_label.text = str(value)
				timer_label.visible = true
			if score_label:
				score_label.visible = false
		State.PLAYING:
			if timer_label:
				timer_label.visible = false
			if score_label:
				score_label.visible = true
		State.ROUND_END:
			if timer_label:
				timer_label.text = "Раунд завершено..."
				timer_label.visible = true
		State.GAME_OVER:
			if timer_label:
				timer_label.text = "Гру завершено!"
				timer_label.visible = true
			if score_label:
				score_label.visible = false


func set_scores(scores: Dictionary) -> void:
	_scores = scores
	if not score_label:
		_find_labels()
	if score_label:
		var parts: Array = []
		for id in scores.keys():
			parts.append("Гравець %d: %d" % [id, scores[id]])
		score_label.text = "   |   ".join(parts)


func _on_damage_dealt(amount: float, target_name: String) -> void:
	if not damage_label:
		_find_labels()
	if not damage_label:
		return

	damage_label.text = "Урон: %d" % int(amount)
	damage_label.visible = true

	if _damage_hide_timer:
		_damage_hide_timer.timeout.disconnect(_hide_damage_label)

	_damage_hide_timer = get_tree().create_timer(1.0)
	_damage_hide_timer.timeout.connect(_hide_damage_label)


func _hide_damage_label() -> void:
	if damage_label:
		damage_label.visible = false
