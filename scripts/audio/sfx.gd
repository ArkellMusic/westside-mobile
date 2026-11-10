class_name Sfx
extends RefCounted
## Efectos de sonido sintetizados por código (sin ficheros): disparo, puñetazo, clic de arma
## vacía, impacto de bala y sirena en bucle. Se generan una vez y se guardan en caché.

const RATE := 22050

static var _cache: Dictionary = {}


static func stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var length := 0.3
	match kind:
		"shot": length = 0.42
		"punch": length = 0.14
		"click": length = 0.04
		"impact": length = 0.09
		"siren": length = 1.2
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		match kind:
			"shot":
				var noise := rng.randf_range(-1.0, 1.0)
				lp = lerpf(lp, noise, 0.25)
				v = noise * exp(-t * 38.0) * 0.9 + sin(TAU * 95.0 * t) * exp(-t * 26.0) * 0.8 + lp * exp(-t * 9.0) * 0.35
			"punch":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)
				v = lp * exp(-t * 34.0) * 1.4 + sin(TAU * 70.0 * t) * exp(-t * 30.0) * 0.8
			"click":
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 160.0) * 0.5
			"impact":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.5)
				v = lp * exp(-t * 60.0) * 0.7
			"siren":
				# Dos tonos que suben y bajan; el bucle empalma en el mismo punto de la onda.
				var f := 760.0 + 260.0 * sin(TAU * t / length)
				phase += TAU * f / RATE
				v = (sin(phase) * 0.6 + sin(phase * 2.0) * 0.18) * 0.5
		var s := int(clampf(v, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if kind == "siren":
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	_cache[kind] = w
	return w


## Sonido 3D de un solo uso en `pos`; se libera al terminar.
static func play_at(parent: Node, pos: Vector3, kind: String, volume_db: float = 0.0, max_distance: float = 90.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(kind)
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 8.0
	p.pitch_scale = randf_range(0.94, 1.06)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
