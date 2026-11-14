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
	# Старий текстовий рахунок більше не потрібен: його замінило табло з ніками.
	if score_label:
		score_label.visible = false


func _labels_ok() -> bool:
	return is_instance_valid(timer_label) and is_instance_valid(score_label) and is_instance_valid(damage_label)


func set_state(state: int, value: int) -> void:
	if not _labels_ok():
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
				score_label.visible = false
		State.ROUND_END:
			if timer_label:
				timer_label.text = "Раунд завершено..."
				timer_label.visible = true
		State.GAME_OVER:
			if timer_label:
				timer_label.text = "Ви перемогли!" if value == multiplayer.get_unique_id() else "Ви програли"
				timer_label.visible = true
			if score_label:
				score_label.visible = false


func set_scores(scores: Dictionary) -> void:
	_scores = scores
	if not _labels_ok():
		_find_labels()
	if score_label:
		score_label.visible = false
		var me := multiplayer.get_unique_id()
		var mine: int = 0
		var theirs: int = 0
		for id in scores.keys():
			if id == me:
				mine = scores[id]
			else:
				theirs = scores[id]
		score_label.text = "Ви: %d   |   Суперник: %d" % [mine, theirs]


func _on_damage_dealt(amount: float, target_name: String) -> void:
	if not _labels_ok():
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
