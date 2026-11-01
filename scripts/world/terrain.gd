class_name Terrain
extends Node3D
## Terreno 3D del estado por chunks de 256 m generados desde StateLayout.height_at().
## - 3 LOD según la distancia al foco (cámara o jugador): 4 m, 16 m y 32 m por celda.
## - Colisión HeightMapShape3D solo en los chunks cercanos (LOD 0 y 1).
## - Vegetación (pinos, árboles, palmeras, cactus, rocas, arbustos) con MultiMesh por
##   chunk y visibility range.
## - Streaming incremental: la malla se calcula en un hilo (WorkerThreadPool) y se monta
##   en la escena como mucho un chunk por frame, sin tirones.
## - Océano: un plano al nivel del mar con la profundidad del fondo.

const CHUNK := StateLayout.CHUNK
const RES := [4.0, 16.0, 32.0]
## Radio (m, al centro del chunk) de cada LOD.
const LOD_R := [430.0, 1350.0]
const HYST := 40.0
const VEG_STEP := 16.0

var focus_override: Vector3 = Vector3.INF
## false en los tests: sin LOD lejano (solo los chunks cercanos).
var far_enabled: bool = true
var veg_enabled: bool = true
var material: ShaderMaterial
var ocean: MeshInstance3D
var ocean_material: ShaderMaterial

var _chunks: Dictionary = {}     # Vector2i -> {lod, mesh, body, veg}
var _pending: Dictionary = {}    # Vector2i -> lod en cálculo
var _ready_queue: Array = []
var _task: int = -1
var _task_result: Dictionary = {}
var _grid_task: int = -1
var _grid_applied := false
var _scan_t := 0.0
var _want: Dictionary = {}       # Vector2i -> lod deseado
var _body: StaticBody3D
var _veg_meshes: Dictionary = {}
var _nx := 0
var _nz := 0
var applied_count := 0
var unloaded_count := 0


func _ready() -> void:
	StateLayout.ensure()
	_nx = int(StateLayout.RECT.size.x / CHUNK)
	_nz = int(StateLayout.RECT.size.y / CHUNK)
	material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/terrain.gdshader")
	material.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain/albedo_array.jpg"))
	material.set_shader_parameter("normal_arr", load("res://assets/textures/terrain/normal_array.jpg"))
	material.set_shader_parameter("sea_level", StateLayout.SEA)
	_body = StaticBody3D.new()
	_body.name = "TerrainCollision"
	add_child(_body)
	_make_ocean()
	_make_veg_meshes()
	if far_enabled:
		_grid_task = WorkerThreadPool.add_task(StateLayout.build_grid, false, "terrain_grid")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _grid_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1


func focus_position() -> Vector3:
	if focus_override != Vector3.INF:
		return focus_override
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.ZERO


func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - StateLayout.RECT.position.x) / CHUNK)), int(floor((p.z - StateLayout.RECT.position.y) / CHUNK)))


func chunk_origin(c: Vector2i) -> Vector2:
	return StateLayout.RECT.position + Vector2(c) * CHUNK


func chunk_lod(c: Vector2i) -> int:
	return int(_chunks[c]["lod"]) if _chunks.has(c) else -1


func loaded_chunks() -> Dictionary:
	return _chunks


## Sin trabajo pendiente: todo lo que se ve ya está cargado a su LOD.
func is_idle() -> bool:
	return _task < 0 and _ready_queue.is_empty() and _missing().is_empty() and (_grid_applied or not far_enabled)


# ----------------------------------------------------------------- streaming

func _process(delta: float) -> void:
	if _grid_task >= 0 and WorkerThreadPool.is_task_completed(_grid_task):
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1
		_apply_grid()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_ready_queue.append(_task_result)
	# Como mucho un chunk montado por frame.
	if not _ready_queue.is_empty():
		_apply(_ready_queue.pop_front())
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.15
		_scan(focus_position())
	if _task < 0:
		var job := _next_job()
		if not job.is_empty():
			var c: Vector2i = job["c"]
			var lod: int = job["lod"]
			_pending[c] = lod
			_task = WorkerThreadPool.add_task(_run_job.bind(c, lod), false, "terrain_chunk")


func _run_job(c: Vector2i, lod: int) -> void:
	_task_result = build_chunk_data(c, lod)


func _desired_lod(c: Vector2i, f: Vector3, current: int) -> int:
	var o := chunk_origin(c) + Vector2(CHUNK, CHUNK) * 0.5
	var d := Vector2(f.x, f.z).distance_to(o)
	# Desde muy alto (vista aérea) todo es lejano.
	d = maxf(d, f.y * 0.8)
	var lod := 2
	for i in LOD_R.size():
		var r: float = LOD_R[i] + (HYST if current >= 0 and current <= i else 0.0)
		if d < r:
			lod = i
			break
	if lod == 2 and not far_enabled:
		return -1
	if lod == 2 and not StateLayout.grid_ready():
		return -1
	return lod


func _scan(f: Vector3) -> void:
	_want.clear()
	for j in _nz:
		for i in _nx:
			var c := Vector2i(i, j)
			var lod := _desired_lod(c, f, chunk_lod(c))
			if lod >= 0:
				_want[c] = lod
	# Fuera del alcance (sin LOD lejano): descargar.
	for c in _chunks.keys():
		if not _want.has(c) and not _pending.has(c):
			_unload(c)


func _missing() -> Array:
	var out: Array = []
	for c in _want:
		if chunk_lod(c) != int(_want[c]) and not _pending.has(c):
			out.append(c)
	return out


func _next_job() -> Dictionary:
	var f := focus_position()
	var best := Vector2i(-1, -1)
	var best_score := INF
	for c in _want:
		var lod: int = _want[c]
		if chunk_lod(c) == lod or _pending.has(c):
			continue
		var o := chunk_origin(c) + Vector2(CHUNK, CHUNK) * 0.5
		var score := Vector2(f.x, f.z).distance_to(o) + lod * 600.0
		# Mejorar el detalle va antes que reducirlo.
		if chunk_lod(c) >= 0 and chunk_lod(c) < lod:
			score += 4000.0
		if score < best_score:
			best_score = score
			best = c
	if best.x < 0:
		return {}
	return {"c": best, "lod": _want[best]}


## Carga síncrona alrededor de `f` (tests y capturas).
func update_sync(f: Vector3) -> void:
	focus_override = f
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_ready_queue.append(_task_result)
	while not _ready_queue.is_empty():
		_apply(_ready_queue.pop_front())
	_scan(f)
	for c in _missing():
		_apply(build_chunk_data(c, _want[c]))


func _unload(c: Vector2i) -> void:
	var ch: Dictionary = _chunks[c]
	for k in ["mesh", "shape", "veg"]:
		var n = ch.get(k)
		if n is Node and is_instance_valid(n):
			n.queue_free()
	_chunks.erase(c)
	unloaded_count += 1


func _apply(data: Dictionary) -> void:
	var c: Vector2i = data["c"]
	var lod: int = data["lod"]
	_pending.erase(c)
	if _chunks.has(c):
		_unload(c)
		unloaded_count -= 1
	var ch := {"lod": lod}
	if not data.get("empty", false):
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["arrays"])
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		mi.name = "T_%d_%d_L%d" % [c.x, c.y, lod]
		mi.mesh = mesh
		var o := chunk_origin(c)
		mi.position = Vector3(o.x, 0.0, o.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		ch["mesh"] = mi
		if data.has("heights"):
			var n: int = data["n"]
			var shape := HeightMapShape3D.new()
			shape.map_width = n
			shape.map_depth = n
			shape.map_data = data["heights"]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			var res: float = RES[lod]
			cs.transform = Transform3D(Basis.from_scale(Vector3(res, 1.0, res)), Vector3(o.x + CHUNK * 0.5, 0.0, o.y + CHUNK * 0.5))
			_body.add_child(cs)
			ch["shape"] = cs
		if data.has("veg"):
			ch["veg"] = _make_veg(data["veg"])
	_chunks[c] = ch
	applied_count += 1


# ------------------------------------------------------------ datos del chunk

## Calcula la malla (y colisión y vegetación si es cercano) de un chunk. Sin acceso a
## la escena: se puede llamar desde un hilo.
func build_chunk_data(c: Vector2i, lod: int) -> Dictionary:
	var res: float = RES[lod]
	var n := int(CHUNK / res) + 1
	var o := chunk_origin(c)
	var m := n + 2
	var hh := PackedFloat32Array()
	hh.resize(m * m)
	var cols := PackedColorArray()
	cols.resize(n * n)
	var max_h := -INF
	if lod == 2:
		var gh := StateLayout.grid_heights()
		var gb := StateLayout.grid_biomes()
		var gs := StateLayout.grid_size()
		var step := int(res / StateLayout.GRID_RES)
		var gi0 := c.x * int(CHUNK / StateLayout.GRID_RES)
		var gj0 := c.y * int(CHUNK / StateLayout.GRID_RES)
		for j in m:
			for i in m:
				var gi := clampi(gi0 + (i - 1) * step, 0, gs.x - 1)
				var gj := clampi(gj0 + (j - 1) * step, 0, gs.y - 1)
				var h := gh[gj * gs.x + gi]
				hh[j * m + i] = h
				if i >= 1 and j >= 1 and i <= n and j <= n:
					cols[(j - 1) * n + (i - 1)] = gb[gj * gs.x + gi]
					max_h = maxf(max_h, h)
	else:
		for j in m:
			for i in m:
				var x := o.x + (i - 1) * res
				var z := o.y + (j - 1) * res
				if i >= 1 and j >= 1 and i <= n and j <= n:
					var s: Array = StateLayout.sample_full(x, z)
					hh[j * m + i] = s[0]
					cols[(j - 1) * n + (i - 1)] = s[1]
					max_h = maxf(max_h, s[0])
				else:
					hh[j * m + i] = StateLayout.height_at(x, z)
	if max_h < StateLayout.SEA - 4.0:
		return {"c": c, "lod": lod, "empty": true}
	# Vértices de la rejilla + faldón en el borde (tapa grietas entre LOD distintos).
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var k := (j + 1) * m + (i + 1)
			var h := hh[k]
			# A lo lejos el terreno baja un poco junto a las carreteras para no taparlas.
			verts[j * n + i] = Vector3(i * res, h, j * res)
			norms[j * n + i] = Vector3(hh[k - 1] - hh[k + 1], 2.0 * res, hh[k - m] - hh[k + m]).normalized()
	vcols = cols
	var hole := StateLayout.WB_HOLE.grow(-2.0)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			if hole.has_point(Vector2(o.x + i * res, o.y + j * res)) and hole.has_point(Vector2(o.x + (i + 1) * res, o.y + (j + 1) * res)):
				continue
			var b := a + 1
			var cc := a + n
			var d := cc + 1
			# Diagonal alterna para un relieve más uniforme.
			if (i + j) % 2 == 0:
				idx.append_array([a, b, d, a, d, cc])
			else:
				idx.append_array([a, b, cc, b, d, cc])
	var drop := res * 0.6 + 1.5
	var ring: Array = []
	for i in n:
		ring.append(i)
	for j in range(1, n):
		ring.append(j * n + n - 1)
	for i in range(n - 2, -1, -1):
		ring.append((n - 1) * n + i)
	for j in range(n - 2, 0, -1):
		ring.append(j * n)
	ring.append(0)
	var base := verts.size()
	for r in ring:
		verts.append(verts[r] - Vector3(0, drop, 0))
		norms.append(norms[r])
		vcols.append(vcols[r])
	for q in ring.size() - 1:
		var t0: int = ring[q]
		var t1: int = ring[q + 1]
		var s0 := base + q
		var s1 := base + q + 1
		idx.append_array([t0, s0, t1, t1, s0, s1])
		idx.append_array([t0, t1, s0, t1, s1, s0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := {"c": c, "lod": lod, "arrays": arrays, "n": n}
	if lod <= 1:
		var heights := PackedFloat32Array()
		heights.resize(n * n)
		for j in n:
			for i in n:
				heights[j * n + i] = hh[(j + 1) * m + (i + 1)]
		out["heights"] = heights
		if veg_enabled:
			out["veg"] = _veg_data(c)
	return out


# ----------------------------------------------------------------- vegetación

func _veg_data(c: Vector2i) -> Dictionary:
	var o := chunk_origin(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) + 991
	var out := {"pine": [], "tree": [], "palm": [], "cactus": [], "rock": [], "bush": []}
	var steps := int(CHUNK / VEG_STEP)
	for j in steps:
		for i in steps:
			var x := o.x + (i + rng.randf()) * VEG_STEP
			var z := o.y + (j + rng.randf()) * VEG_STEP
			var roll := rng.randf()
			var s: Array = StateLayout.sample_full(x, z)
			var h: float = s[0]
			var b: Color = s[1]
			if h < StateLayout.SEA + 0.6 or b.a > 0.35:
				continue
			if StateLayout.WB_HOLE.grow(30.0).has_point(Vector2(x, z)):
				continue
			var rq := StateLayout.road_query(x, z, true)
			if rq.x < 7.0:
				continue
			var slope := absf(StateLayout.height_at(x + 3.0, z) - h) + absf(StateLayout.height_at(x, z + 3.0) - h)
			var kind := ""
			if slope > 3.2:
				kind = "rock" if roll < 0.10 else ""
			elif b.r > 0.5:
				if roll < 0.10:
					kind = "cactus"
				elif roll < 0.16:
					kind = "rock"
				elif roll < 0.21:
					kind = "bush"
			elif b.b > 0.45:
				kind = "palm" if roll < 0.16 else ""
			elif h > 330.0:
				kind = ""
			elif b.g > 0.25:
				var p := 0.62 * b.g
				if roll < p:
					kind = "pine" if (h > 90.0 or rng.randf() < 0.45) else "tree"
				elif roll < p + 0.05:
					kind = "rock"
			else:
				if roll < 0.035:
					kind = "tree"
				elif roll < 0.075:
					kind = "bush"
				elif roll < 0.085:
					kind = "rock"
			if kind == "":
				continue
			var sc := rng.randf_range(0.75, 1.35)
			if kind == "rock":
				sc = rng.randf_range(0.6, 2.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			(out[kind] as Array).append(Transform3D(basis, Vector3(x, h - 0.15, z)))
	return out


func _make_veg(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Veg"
	add_child(root)
	for kind in data:
		var list: Array = data[kind]
		if list.is_empty():
			continue
		var info: Dictionary = _veg_meshes[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = info["mesh"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = info["vis"]
		mi.visibility_range_end_margin = 40.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if info["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _make_veg_meshes() -> void:
	var leaf := MeshBuilder.material(Color(0.16, 0.30, 0.14), 0.9)
	var bark := MeshBuilder.material(Color(0.33, 0.24, 0.17), 0.95)
	# Pino: tronco y tres conos.
	var pine := MeshBuilder.new()
	pine.surface("bark", bark)
	pine.surface("leaf", MeshBuilder.material(Color(0.11, 0.24, 0.13), 0.9))
	pine.cylinder("bark", Vector3.ZERO, 0.28, 0.18, 3.0, 6)
	for k in 3:
		pine.cylinder("leaf", Vector3(0, 2.4 + k * 2.6, 0), 2.6 - k * 0.65, 0.15, 4.2 - k * 0.6, 8, Transform3D.IDENTITY, Color(1, 1, 1).lerp(Color(0.85, 1.0, 0.9), k * 0.3))
	# Árbol de hoja ancha.
	var tree := MeshBuilder.new()
	tree.surface("bark", bark)
	tree.surface("leaf", leaf)
	tree.cylinder("bark", Vector3.ZERO, 0.25, 0.17, 3.4, 6)
	tree.sphere("leaf", Vector3(0, 4.6, 0), Vector3(2.6, 2.1, 2.6), 4, 8)
	tree.sphere("leaf", Vector3(1.0, 3.9, 0.6), Vector3(1.6, 1.3, 1.6), 3, 7, Transform3D.IDENTITY, Color(0.9, 1.05, 0.85))
	tree.sphere("leaf", Vector3(-0.9, 4.0, -0.7), Vector3(1.5, 1.2, 1.5), 3, 7, Transform3D.IDENTITY, Color(1.1, 1.05, 0.9))
	# Palmera.
	var palm := MeshBuilder.new()
	palm.surface("bark", MeshBuilder.material(Color(0.50, 0.41, 0.31), 0.95))
	var pl := MeshBuilder.material(Color(0.22, 0.42, 0.16), 0.8)
	pl.cull_mode = BaseMaterial3D.CULL_DISABLED
	palm.surface("leaf", pl)
	var top := Vector3(0.8, 10.0, 0)
	palm.cylinder("bark", Vector3.ZERO, 0.28, 0.18, 10.1, 6, Transform3D(Basis(Vector3.BACK, -0.08), Vector3.ZERO))
	for k in 8:
		var a := TAU * k / 8.0
		palm.leaf("leaf", top, Vector3(cos(a), 0.25, sin(a)).normalized(), 3.8, 0.9, 2.0, Color.WHITE, 3)
	# Cactus (saguaro).
	var cactus := MeshBuilder.new()
	cactus.surface("c", MeshBuilder.material(Color(0.27, 0.38, 0.2), 0.85))
	cactus.cylinder("c", Vector3.ZERO, 0.35, 0.3, 4.2, 7)
	cactus.sphere("c", Vector3(0, 4.2, 0), Vector3(0.3, 0.3, 0.3), 3, 7)
	cactus.cylinder("c", Vector3(0.35, 1.6, 0), 0.22, 0.2, 1.6, 6, Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3.ZERO))
	cactus.cylinder("c", Vector3(-0.3, 2.2, 0), 0.2, 0.18, 1.3, 6, Transform3D(Basis(Vector3.FORWARD, -0.25), Vector3.ZERO))
	# Roca.
	var rock := MeshBuilder.new()
	rock.surface("r", MeshBuilder.material(Color(0.52, 0.42, 0.34), 0.95))
	rock.sphere("r", Vector3(0, 0.3, 0), Vector3(1.6, 1.0, 1.3), 3, 6)
	rock.sphere("r", Vector3(1.0, 0.1, 0.5), Vector3(0.9, 0.6, 0.8), 3, 5, Transform3D.IDENTITY, Color(0.85, 0.85, 0.85))
	# Arbusto.
	var bush := MeshBuilder.new()
	bush.surface("b", MeshBuilder.material(Color(0.30, 0.36, 0.17), 0.9))
	bush.sphere("b", Vector3(0, 0.5, 0), Vector3(1.1, 0.7, 1.1), 3, 6)
	_veg_meshes = {
		"pine": {"mesh": pine.commit(), "vis": 1200.0, "shadow": true},
		"tree": {"mesh": tree.commit(), "vis": 1000.0, "shadow": true},
		"palm": {"mesh": palm.commit(), "vis": 900.0, "shadow": true},
		"cactus": {"mesh": cactus.commit(), "vis": 600.0, "shadow": false},
		"rock": {"mesh": rock.commit(), "vis": 650.0, "shadow": false},
		"bush": {"mesh": bush.commit(), "vis": 320.0, "shadow": false},
	}


# --------------------------------------------------------------------- océano

func _make_ocean() -> void:
	ocean_material = ShaderMaterial.new()
	ocean_material.shader = load("res://assets/shaders/ocean.gdshader")
	var r := StateLayout.RECT
	ocean_material.set_shader_parameter("map_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var img := Image.create(4, 4, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	ocean_material.set_shader_parameter("depth_map", ImageTexture.create_from_image(img))
	var plane := PlaneMesh.new()
	plane.size = Vector2(r.size.x + 60000.0, r.size.y + 60000.0)
	# Subdividido para que la niebla por vértice (Compatibility) no se note.
	plane.subdivide_width = 96
	plane.subdivide_depth = 80
	plane.material = ocean_material
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = plane
	ocean.position = Vector3(r.get_center().x, StateLayout.SEA, r.get_center().y)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)


func _apply_grid() -> void:
	_grid_applied = true
	var gs := StateLayout.grid_size()
	var gh := StateLayout.grid_heights()
	var img := Image.create(gs.x, gs.y, false, Image.FORMAT_L8)
	for j in gs.y:
		for i in gs.x:
			var d := clampf((StateLayout.SEA - gh[j * gs.x + i]) / 25.0, 0.0, 1.0)
			img.set_pixel(i, j, Color(d, d, d))
	ocean_material.set_shader_parameter("depth_map", ImageTexture.create_from_image(img))


## Para tests y capturas: espera a la rejilla gruesa (océano y LOD lejano).
func wait_grid() -> void:
	if _grid_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1
	if not _grid_applied:
		StateLayout.build_grid()
		_apply_grid()
