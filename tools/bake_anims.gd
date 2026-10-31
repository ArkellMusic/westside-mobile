extends SceneTree
## Construye la AnimationLibrary compartida de Mixamo (walk, run, sit_talk, phone, idle).
##   godot --headless --path <trabajo> -s res://tools/bake_anims.gd -- --out=/ruta/lib.res
## - pistas "Skeleton3D:mixamorig_<hueso>", solo rotaciones + posicion de Hips
## - sin root motion: se bloquea la traslacion X/Z de Hips (solo queda la altura Y)
## - walk = ciclo estable recortado de Start_Walking; bucles cerrados (ultimo frame = primero)

var out := "/home/claude/westside-mobile/assets/animations/mixamo/lib.res"
const POS_SCALE := 100.0   # el importador reduce x0.01 las traslaciones de las animaciones sin piel


class Clip:
	var bones: PackedStringArray = []   # nombres de pista (ruta)
	var rot: Array = []                 # por pista: Array[Quaternion] por frame
	var hips_y: PackedFloat32Array = []
	var hips_z: PackedFloat32Array = []
	var dt: float = 1.0 / 30.0
	var n: int = 0


func _init() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		if kv[0] == "out": out = kv[1]
	_run()
	quit()


func _sample(file: String, fps: float, t_from: float = 0.0, t_to: float = -1.0) -> Clip:
	var root: Node = (load("res://in/%s.fbx" % file) as PackedScene).instantiate()
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	var an := ap.get_animation("mixamo_com")
	var c := Clip.new()
	c.dt = 1.0 / fps
	if t_to < 0.0: t_to = an.length
	c.n = int(floor((t_to - t_from) * fps + 0.0001)) + 1
	var hips_t := -1
	for i in an.get_track_count():
		var p := String(an.track_get_path(i))
		if an.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			c.bones.append(p)
			var arr := []
			for f in c.n:
				arr.append(an.rotation_track_interpolate(i, t_from + f * c.dt))
			c.rot.append(arr)
		elif an.track_get_type(i) == Animation.TYPE_POSITION_3D and p.ends_with("Hips"):
			hips_t = i
	for f in c.n:
		var v: Vector3 = an.position_track_interpolate(hips_t, t_from + f * c.dt) * POS_SCALE
		c.hips_y.append(v.y)
		c.hips_z.append(v.z)
	root.free()
	print("  muestreado ", file, " ", c.n, " frames @", fps, " pistas rot=", c.bones.size())
	return c


func _pose_err(c: Clip, a: int, b: int) -> float:
	var e := 0.0
	for ti in c.bones.size():
		var qa: Quaternion = c.rot[ti][a]
		var qb: Quaternion = c.rot[ti][b]
		e += 1.0 - absf(qa.dot(qb))
	e = e * 100.0 + absf(c.hips_y[a] - c.hips_y[b]) * 5.0
	return e


## Devuelve [inicio, longitud] en frames del mejor ciclo.
func _find_cycle(c: Clip, min_p: int, max_p: int, min_start: int) -> Array:
	var best := [0, 0]
	var be := 1e9
	for p in range(min_p, max_p + 1):
		for s in range(min_start, c.n - p - 3):
			var e := _pose_err(c, s, s + p) + _pose_err(c, s + 1, s + p + 1) + _pose_err(c, s + 2, s + p + 2)
			if p % 4 == 0 and s % 4 == 0: print("   cand s=", s, " p=", p, " e=", snappedf(e, 0.1))
			if e < be:
				be = e
				best = [s, p]
	print("  ciclo: inicio=", best[0], " longitud=", best[1], " error=", be)
	return best


func _build(c: Clip, start: int, length: int, blend: int, loop: bool, extra_y: float = 0.0) -> Animation:
	var an := Animation.new()
	an.length = length * c.dt
	an.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for ti in c.bones.size():
		var tr := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(tr, NodePath(c.bones[ti]))
		an.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		var first: Quaternion = c.rot[ti][start]
		for f in range(length + 1):
			var q: Quaternion = c.rot[ti][start + mini(f, c.n - 1 - start)] if f < length else first
			if loop and f >= length - blend and f < length:
				var w := float(f - (length - blend) + 1) / float(blend + 1)
				w = w * w * (3.0 - 2.0 * w)
				q = q.slerp(first, w)
			an.rotation_track_insert_key(tr, f * c.dt, q)
	var pt := an.add_track(Animation.TYPE_POSITION_3D)
	an.track_set_path(pt, NodePath("Skeleton3D:mixamorig_Hips"))
	var y0: float = c.hips_y[start]
	for f in range(length + 1):
		var y: float = c.hips_y[start + mini(f, c.n - 1 - start)] if f < length else y0
		if loop and f >= length - blend and f < length:
			var w := float(f - (length - blend) + 1) / float(blend + 1)
			w = w * w * (3.0 - 2.0 * w)
			y = lerpf(y, y0, w)
		an.position_track_insert_key(pt, f * c.dt, Vector3(0.0, y + extra_y, 0.0))
	return an


func _idle(c: Clip) -> Animation:
	# Pose estable = primer frame de Start_Walking + respiración sutil en columna y cabeza.
	var period := 4.0
	var fps := 15.0
	var n := int(period * fps)
	var an := Animation.new()
	an.length = period
	an.loop_mode = Animation.LOOP_LINEAR
	for ti in c.bones.size():
		var name := c.bones[ti].get_slice(":", 1)
		var tr := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(tr, NodePath(c.bones[ti]))
		var base: Quaternion = c.rot[ti][0]
		var amp := 0.0
		var ph := 0.0
		match name:
			"mixamorig_Spine": amp = 0.010
			"mixamorig_Spine1": amp = 0.014; ph = 0.3
			"mixamorig_Spine2": amp = 0.018; ph = 0.6
			"mixamorig_Head": amp = -0.016; ph = 0.9
			"mixamorig_LeftShoulder", "mixamorig_RightShoulder": amp = 0.012; ph = 0.8
		for f in range(n + 1):
			var s := sin(TAU * (float(f) / n) - ph)
			an.rotation_track_insert_key(tr, f / fps, base * Quaternion(Vector3.RIGHT, amp * s) if amp != 0.0 else base)
	var pt := an.add_track(Animation.TYPE_POSITION_3D)
	an.track_set_path(pt, NodePath("Skeleton3D:mixamorig_Hips"))
	for f in range(n + 1):
		an.position_track_insert_key(pt, f / fps, Vector3(0.0, c.hips_y[0] - 0.004 * (0.5 - 0.5 * cos(TAU * float(f) / n)), 0.0))
	return an


func _run() -> void:
	var lib := AnimationLibrary.new()
	# --- walk ---
	var w := _sample("Start_Walking", 30.0)
	var cyc := _find_cycle(w, 26, 40, 40)
	var walk := _build(w, cyc[0], cyc[1], 4, true)
	var dz: float = (w.hips_z[cyc[0] + cyc[1]] - w.hips_z[cyc[0]])
	walk.set_meta("speed", absf(dz) / (cyc[1] * w.dt))
	print("  walk: ", cyc[1] * w.dt, " s, velocidad=", walk.get_meta("speed"), " m/s")
	lib.add_animation("walk", walk)
	# --- idle (primer frame de Start_Walking) ---
	lib.add_animation("idle", _idle(w))
	# --- run ---
	var r := _sample("Running", 30.0)
	var run := _build(r, 0, r.n - 1, 3, true)
	var rdz: float = r.hips_z[r.n - 1] - r.hips_z[0]
	# el último frame del clip ya duplica el primero: velocidad = recorrido / duración
	run.set_meta("speed", absf(rdz) / ((r.n - 1) * r.dt))
	print("  run: ", (r.n - 1) * r.dt, " s, velocidad=", run.get_meta("speed"), " m/s; err ciclo=", _pose_err(r, 0, r.n - 1))
	lib.add_animation("run", run)
	# --- sit_talk / phone: se recortan a 20 s ---
	var st := _sample("Sitting_Talking", 20.0, 0.0, 20.0)
	lib.add_animation("sit_talk", _build(st, 0, st.n - 1, 10, true))
	var ph := _sample("Talking_On_Phone", 20.0, 0.0, 20.0)
	lib.add_animation("phone", _build(ph, 0, ph.n - 1, 10, true))
	var err := ResourceSaver.save(lib, out, ResourceSaver.FLAG_COMPRESS)
	print("guardado ", out, " err=", err, " tamaño=", FileAccess.get_file_as_bytes(out).size())
