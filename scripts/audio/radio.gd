class_name Radio
extends Node
## Radio del juego como en los clásicos de mundo abierto: solo suena dentro de los
## coches, con sonido de altavoz de coche (bus "Radio" con ecualizador y compresor),
## cartel con el nombre de la emisora y emisión "continua": las emisoras siguen
## avanzando aunque no estés escuchando, y al volver entras a mitad de canción.
##
## Las emisoras y pistas se definen en data/radio.json (lo regenera
## tools/build_radio_index.py a partir de assets/audio/radio/<emisora>/).

signal station_changed(index: int, station: Dictionary)

const BUS := "Radio"
const OFF := -1

var stations: Array = []
var current: int = 0
var playing: bool = false
var volume_db: float = -2.0

var _player: AudioStreamPlayer
var _clock: float = 0.0          # segundos de emisión desde que arrancó el juego
var _lengths: Dictionary = {}    # ruta -> duración (s)
var _streams: Dictionary = {}
var _station_offsets: Array = []
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	add_child(_player)
	_player.finished.connect(_on_finished)
	var data := GameData.load_json("res://data/radio.json")
	for s in data.get("stations", []):
		var tracks: Array = []
		for t in s.get("tracks", []):
			if ResourceLoader.exists(String(t["path"])):
				tracks.append(t)
		if not tracks.is_empty():
			var st: Dictionary = s.duplicate()
			st["tracks"] = tracks
			stations.append(st)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for s in stations:
		_station_offsets.append(rng.randf_range(0.0, 3600.0))


func has_music() -> bool:
	return not stations.is_empty()


func _process(delta: float) -> void:
	_clock += delta


## Llamar al subir a un coche: empieza la emisora actual en su punto de emisión.
func enter_vehicle() -> void:
	if not has_music() or current == OFF:
		return
	playing = true
	_tune(current, true)


func exit_vehicle() -> void:
	playing = false
	_fade_to(-40.0, 0.4, true)


func next_station() -> void:
	if not has_music():
		return
	# Ciclo: emisoras ... -> apagada -> primera.
	if current == OFF:
		current = 0
	elif current >= stations.size() - 1:
		current = OFF
	else:
		current += 1
	if current == OFF:
		_fade_to(-40.0, 0.25, true)
		station_changed.emit(OFF, {"name": "Radio apagada", "genre": ""})
		return
	_tune(current, false)


func station_name() -> String:
	if current == OFF or current >= stations.size():
		return "Radio apagada"
	return String(stations[current].get("name", ""))


func _tune(index: int, quiet_intro: bool) -> void:
	var st: Dictionary = stations[index]
	var tracks: Array = st["tracks"]
	var total := 0.0
	for t in tracks:
		total += _length(t)
	if total <= 0.0:
		return
	# Posición de emisión: el tiempo avanza aunque no estés sintonizado.
	var pos := fposmod(_clock + float(_station_offsets[index]), total)
	var i := 0
	while i < tracks.size() and pos > _length(tracks[i]):
		pos -= _length(tracks[i])
		i += 1
	i = mini(i, tracks.size() - 1)
	_play_track(st, i, pos)
	_player.volume_db = -40.0
	_fade_to(volume_db, 0.6 if quiet_intro else 0.2, false)
	station_changed.emit(index, st)


func _play_track(st: Dictionary, i: int, at: float) -> void:
	var t: Dictionary = st["tracks"][i]
	var path := String(t["path"])
	if not _streams.has(path):
		_streams[path] = load(path)
	_player.stream = _streams[path]
	_player.set_meta("track", i)
	_player.play(clampf(at, 0.0, maxf(_length(t) - 0.5, 0.0)))


func _on_finished() -> void:
	if not playing or current == OFF:
		return
	var st: Dictionary = stations[current]
	var i := (int(_player.get_meta("track", 0)) + 1) % (st["tracks"] as Array).size()
	_play_track(st, i, 0.0)


func _length(t: Dictionary) -> float:
	var path := String(t["path"])
	if not _lengths.has(path):
		var l := float(t.get("seconds", 0.0))
		if l <= 0.0 and ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			l = s.get_length()
		_lengths[path] = maxf(l, 1.0)
	return _lengths[path]


func _fade_to(db: float, time: float, stop_after: bool) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", db, time)
	if stop_after:
		_fade.tween_callback(_player.stop)


## Bus con sonido de altavoz de coche: graves y agudos recortados y algo comprimido.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 90.0
	AudioServer.add_bus_effect(idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 9500.0
	AudioServer.add_bus_effect(idx, lp)
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, 2.0)   # 32 Hz
	eq.set_band_gain_db(1, 3.0)   # 100 Hz: pegada de los graves del coche
	eq.set_band_gain_db(4, -2.0)  # 3.2 kHz
	AudioServer.add_bus_effect(idx, eq)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(idx, comp)
	var room := AudioEffectReverb.new()
	room.room_size = 0.12
	room.damping = 0.8
	room.wet = 0.06
	room.dry = 1.0
	AudioServer.add_bus_effect(idx, room)
