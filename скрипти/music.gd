extends AudioStreamPlayer

@export var fade_duration: float = 1.5 # Час згасання музики в секундах

func _ready() -> void:
	# Підключаємо сигнал завершення треку
	finished.connect(_on_finished)
	
	# Автоматично запускаємо музику, якщо вона призначена у стрімі
	if stream:
		play_menu_music(stream)

# Функція для запуску музики з меню (грає безкінечно в циклі)
func play_menu_music(stream_to_play: AudioStream) -> void:
	stream = stream_to_play
	# Вмикаємо безкінечний цикл на рівні імпорту аудіо, 
	# або керуємо цим через код:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
		
	volume_db = 0.0 # Скидаємо гучність
	play()

# Функція для плавного притихання при переході в іншу сцену
func fade_out_and_stop() -> void:
	var tween = create_tween()
	# Плавно знижуємо гучність до мінімуму (-80 dB) за заданий час
	tween.tween_property(self, "volume_db", -80.0, fade_duration)
	await tween.finished
	stop()
	volume_db = 0.0 # Повертаємо стандартну гучність для майбутніх відтворень

# Коли трек закінчується (якщо цикл вимкнено)
func _on_finished() -> void:
	var tween = create_tween()
	tween.tween_property(self, "volume_db", -80.0, fade_duration)
	await tween.finished
	stop()
	volume_db = 0.0
