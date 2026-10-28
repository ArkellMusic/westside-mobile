class_name KitBuildings
extends Node3D
## Sustituye las cajas de los comercios, hoteles y torres del centro por edificios
## montados con el Downtown City MegaKit de Quaternius (CC0): fachadas modulares de
## 2 m x 3 m (planta baja de tienda, plantas de ladrillo con ventanas, columnas en
## las esquinas, cornisa, azotea con aire acondicionado) y, para variar, algunos
## edificios prefabricados completos del kit.
##
## Uso: var kb := KitBuildings.new(); add_child(kb); kb.build(city)
##
## Rendimiento: cada pieza se dibuja con un MultiMesh por (celda de 160 m, malla),
## de modo que el culling por frustum y la distancia de visibilidad funcionan por
## zona. Las colisiones y los footprints siguen siendo los de las cajas originales.

const KIT := "res://assets/kit/city/"
const CHUNK := 160.0            # tamaño de la celda de agrupación (m)
const VIS_END := 350.0          # distancia máxima de dibujado (m)
const PREFAB_VIS_END := 300.0
const PREFAB_CHANCE := 0.3
const MAX_PREFABS := 16         # los prefabricados tienen 18k-45k triángulos
const GROUND_Y := 0.1           # las manzanas están elevadas 0,10 m
const FLOOR_H := 3.0
const STREET_GAP := 10.0        # un lado con calle a menos de esto es "fachada principal"
const SEED_OFFSET := 9173

const PREFABS := ["Building_Small_1", "Building_Medium_2_001", "Building_Large_2"]

## Estilos de fachada. shop/alt/door: planta baja; win/win4/plain: plantas altas.
const STYLES := [
	{"id": "brick", "shop": "Metal_FirstFloor_Window", "alt": "Metal_FirstFloor_Wall", "door": "DoorFrame_Metal_Single",
		"win": "Brick_Window_Square_Single", "win4": "Brick_Inset_Window", "plain": "Brick_Plain_3", "cornice": "Cornice_Brick_Center"},
	{"id": "stone", "shop": "Trim_FirstFloor_Window_001", "alt": "Trim_FirstFloor_Wall", "door": "DoorFrame_Trim",
		"win": "Brick_Window_Square_Single", "win4": "Brick_Inset_Window", "plain": "Brick_Plain_3", "cornice": "Cornice_Trim_Center"},
	{"id": "modern", "shop": "Metal_FullWindow", "alt": "Metal_Plain_3", "door": "DoorFrame_Metal_Single",
		"win": "Metal_FullWindow", "win4": "Metal_Window", "plain": "Metal_Plain_3", "cornice": "Cornice_Metal_Center"},
]

var stats := {"buildings": 0, "prefabs": 0, "instances": 0, "multimeshes": 0, "triangles": 0}

var _rng := RandomNumberGenerator.new()
var _meshes: Dictionary = {}        # nombre -> Mesh con materiales corregidos
var _tris: Dictionary = {}          # nombre -> triángulos
var _prefab_boxes: Dictionary = {}  # nombre -> AABB local del prefabricado
var _mat_cache: Dictionary = {}     # id del material original -> copia corregida
var _lit_mats: Array = []           # materiales de interior para encender de noche
var _buckets: Dictionary = {}       # Vector2i -> {malla: Array[Transform3D]}
var _prefab_count := 0


func build(city: CityBuilder) -> void:
	_rng.seed = CityBuilder.SEED + SEED_OFFSET
	var taken := {}
	var rects: Array = []   # rect original (colisión) de cada candidato, para los prefabricados
	for cand in city.kit_candidates():
		rects.append(cand)
	for cand in rects:
		var c: Vector3 = cand["center"]
		var size: Vector3 = cand["size"]
		if size.x < 8.0 or size.z < 8.0 or size.y < 5.0:
			continue
		var side := _street_side(Vector2(c.x, c.z), size)
		if _try_prefab(Vector2(c.x, c.z), size, side):
			taken[cand["index"]] = true
			continue
		_build_modular(Vector2(c.x, c.z), size, side)
		taken[cand["index"]] = true
		stats["buildings"] += 1
	_flush()
	city.rebuild_boxes(taken, VIS_END - 20.0)
	if not city.night_changed.is_connected(set_night):
		city.night_changed.connect(set_night)
	print("[KitBuildings] edificios=%d (prefabricados=%d) instancias=%d multimeshes=%d triangulos~%d" % [
		stats["buildings"] + stats["prefabs"], stats["prefabs"], stats["instances"], stats["multimeshes"], stats["triangles"]])


## Enciende los interiores falsos de las ventanas al anochecer (0 = día, 1 = noche).
func set_night(amount: float) -> void:
	var e := clampf((amount - 0.2) / 0.6, 0.0, 1.0) * 0.9
	for m in _lit_mats:
		(m as BaseMaterial3D).emission_energy_multiplier = e


# ---------------------------------------------------------------- calles

## Índice del lado (0=+Z, 1=+X, 2=-Z, 3=-X) cuya calle queda más cerca.
func _street_side(c: Vector2, size: Vector3) -> int:
	var best := 0
	var best_gap := 1e9
	for s in 4:
		var gap := _street_gap(c, size, s)
		if gap < best_gap:
			best_gap = gap
			best = s
	return best


func _side_normal(s: int) -> Vector2:
	match s:
		0: return Vector2(0, 1)
		1: return Vector2(1, 0)
		2: return Vector2(0, -1)
	return Vector2(-1, 0)


## Distancia libre entre la fachada del lado `s` y el borde de la calzada más cercana.
func _street_gap(c: Vector2, size: Vector3, s: int) -> float:
	var n := _side_normal(s)
	var face := c + n * (size.z * 0.5 if n.x == 0.0 else size.x * 0.5)
	var best := 1e9
	if n.x != 0.0:
		for a in CityLayout.AVENUES:
			var d: float = (float(a[0]) - face.x) * n.x
			if d > -0.5:
				best = minf(best, maxf(d - float(a[1]) * 0.5, 0.0))
	else:
		for st in CityLayout.STREETS:
			var d: float = (float(st[0]) - face.y) * n.y
			if d > -0.5:
				best = minf(best, maxf(d - float(st[1]) * 0.5, 0.0))
	return best


# ---------------------------------------------------------------- prefabricados

func _try_prefab(c: Vector2, size: Vector3, side: int) -> bool:
	if _prefab_count >= MAX_PREFABS or _rng.randf() > PREFAB_CHANCE:
		return false
	var best := ""
	var best_waste := 1e9
	for nm in PREFABS:
		_load_mesh(nm)
		var bb: AABB = _prefab_boxes[nm]
		var dx := bb.size.x if side % 2 == 0 else bb.size.z
		var dz := bb.size.z if side % 2 == 0 else bb.size.x
		if dx > size.x + 0.2 or dz > size.z + 0.2:
			continue
		if size.x - dx > 4.0 or size.z - dz > 4.0:
			continue
		if bb.size.y < size.y * 0.55 or bb.size.y > size.y * 1.4 + 2.0:
			continue
		var waste := (size.x - dx) + (size.z - dz) + absf(bb.size.y - size.y) * 0.3
		if waste < best_waste:
			best_waste = waste
			best = nm
	if best == "":
		return false
	var bb: AABB = _prefab_boxes[best]
	var basis := Basis(Vector3.UP, side * PI * 0.5)
	var local_c := Vector3(bb.position.x + bb.size.x * 0.5, 0.0, bb.position.z + bb.size.z * 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Prefab_%s_%d" % [best, _prefab_count]
	mi.mesh = _meshes[best]
	mi.transform = Transform3D(basis, Vector3(c.x, GROUND_Y, c.y) - basis * local_c)
	mi.visibility_range_end = PREFAB_VIS_END
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	_prefab_count += 1
	stats["prefabs"] += 1
	stats["triangles"] += int(_tris[best])
	return true


# ---------------------------------------------------------------- edificio modular

func _build_modular(c: Vector2, size: Vector3, front: int) -> void:
	var w := maxi(int(floor(size.x / 2.0)) * 2, 6)
	var d := maxi(int(floor(size.z / 2.0)) * 2, 6)
	var floors := maxi(int(round(size.y / FLOOR_H)), 2)
	var style: Dictionary = STYLES[_pick_style(floors)]
	var hx := w * 0.5
	var hz := d * 0.5
	var origin := Vector3(c.x, GROUND_Y, c.y)
	var top_y := floors * FLOOR_H

	# Cuatro fachadas.
	for s in 4:
		var theta := s * PI * 0.5
		var basis := Basis(Vector3.UP, theta)
		var n := basis * Vector3.BACK
		var t := basis * Vector3.RIGHT
		var length := (w if s % 2 == 0 else d)
		var half_n := (hz if s % 2 == 0 else hx)
		var base := origin + n * half_n
		var slots := (length - 2) / 2
		var is_front := _street_gap(c, size, s) <= STREET_GAP
		var ground: Array = _ground_pattern(style, slots, length, is_front)
		var upper: Array = _upper_pattern(style, slots, is_front)
		# Planta baja.
		_place_row(ground, base, t, basis, slots, 0.0)
		# Plantas altas (mismo patrón en vertical para que las ventanas alineen).
		for f in range(1, floors):
			_place_row(upper, base, t, basis, slots, f * FLOOR_H)
		# Cornisa.
		for i in slots:
			var u := (i - (slots - 1) * 0.5) * 2.0
			_add(style["cornice"], Transform3D(basis, base + t * u + Vector3(0, top_y, 0)))

	# Columnas de esquina (y su remate bajo la cornisa).
	for sx in [1, -1]:
		for sz in [1, -1]:
			var angle := 0.0
			if sx > 0 and sz < 0:
				angle = 90.0
			elif sx < 0 and sz < 0:
				angle = 180.0
			elif sx < 0 and sz > 0:
				angle = 270.0
			var cb := Basis(Vector3.UP, deg_to_rad(angle))
			var cp := origin + Vector3(sx * hx, 0, sz * hz)
			_add("Brick_CornerColumn_Bottom", Transform3D(cb, cp))
			for f in range(1, floors):
				_add("Brick_CornerColumn_Center", Transform3D(cb, cp + Vector3(0, f * FLOOR_H, 0)))
			_add("Brick_CornerColumn_Cap", Transform3D(cb, cp + Vector3(0, top_y - 2.0, 0)))

	_build_roof(origin, w, d, top_y, size)


func _pick_style(floors: int) -> int:
	var r := _rng.randf()
	if floors >= 8:
		return 2 if r < 0.6 else 0
	if r < 0.5:
		return 0
	return 1 if r < 0.8 else 2


## Patrón de la planta baja: lista de [pieza, ancho_en_slots, desplazamiento_x_puerta]
func _ground_pattern(style: Dictionary, slots: int, length: int, is_front: bool) -> Array:
	var out: Array = []
	var doors := {}
	if is_front:
		var n_doors := maxi(1, int(round(length / 10.0)))
		for k in n_doors:
			doors[clampi(int(round((k + 0.5) * slots / n_doors - 0.5)), 0, slots - 1)] = true
	for i in slots:
		if doors.has(i):
			out.append([style["door"], 1])
		elif is_front:
			out.append([style["shop"] if _rng.randf() < 0.85 else style["alt"], 1])
		else:
			var r := _rng.randf()
			out.append([style["plain"] if r < 0.7 else (style["alt"] if r < 0.85 else style["win"]), 1])
	return out


func _upper_pattern(style: Dictionary, slots: int, is_front: bool) -> Array:
	var out: Array = []
	var i := 0
	while i < slots:
		var r := _rng.randf()
		if is_front:
			if slots - i >= 2 and r < 0.2:
				out.append([style["win4"], 2])
				i += 2
				continue
			out.append([style["win"] if r < 0.9 else style["plain"], 1])
		else:
			out.append([style["win"] if r < 0.3 else style["plain"], 1])
		i += 1
	return out


func _place_row(pattern: Array, base: Vector3, t: Vector3, basis: Basis, slots: int, y: float) -> void:
	var i := 0.0
	for p in pattern:
		var width: int = p[1]
		var u := (i + width * 0.5 - slots * 0.5) * 2.0
		_add(p[0], Transform3D(basis, base + t * u + Vector3(0, y, 0)))
		i += width


func _build_roof(origin: Vector3, w: int, d: int, top_y: float, size: Vector3) -> void:
	var y := origin.y + top_y + 0.2
	var nx := w / 4
	var nz := d / 4
	var x0 := origin.x - w * 0.5
	var z0 := origin.z - d * 0.5
	for i in nx:
		for j in nz:
			_add("Roof_4x4", Transform3D(Basis.IDENTITY, Vector3(x0 + 2.0 + i * 4.0, y, z0 + 2.0 + j * 4.0)))
	if w % 4 == 2:
		for j in d / 2:
			_add("Roof_2x2", Transform3D(Basis.IDENTITY, Vector3(x0 + nx * 4.0 + 1.0, y, z0 + 1.0 + j * 2.0)))
	if d % 4 == 2:
		for i in nx * 2:
			_add("Roof_2x2", Transform3D(Basis.IDENTITY, Vector3(x0 + 1.0 + i * 2.0, y, z0 + nz * 4.0 + 1.0)))
	# Aparatos de aire acondicionado.
	for k in _rng.randi_range(1, 3):
		var p := Vector3(origin.x + _rng.randf_range(-w * 0.3, w * 0.3), y - 0.2, origin.z + _rng.randf_range(-d * 0.3, d * 0.3))
		var b := Basis(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5).scaled(Vector3.ONE * 1.6)
		_add("Prop_ACUnit", Transform3D(b, p))


# ---------------------------------------------------------------- mallas y materiales

func _add(mesh_name: String, xf: Transform3D) -> void:
	_load_mesh(mesh_name)
	var key := Vector2i(int(floor(xf.origin.x / CHUNK)), int(floor(xf.origin.z / CHUNK)))
	if not _buckets.has(key):
		_buckets[key] = {}
	var cell: Dictionary = _buckets[key]
	if not cell.has(mesh_name):
		cell[mesh_name] = []
	(cell[mesh_name] as Array).append(xf)


func _load_mesh(mesh_name: String) -> void:
	if _meshes.has(mesh_name):
		return
	var scene := load(KIT + mesh_name + ".gltf") as PackedScene
	var root := scene.instantiate()
	var found: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		found = n
		break
	var mesh := found.mesh.duplicate() as Mesh
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, _fixed_material(mesh.surface_get_material(i)))
	_meshes[mesh_name] = mesh
	_tris[mesh_name] = mesh.get_faces().size() / 3
	_prefab_boxes[mesh_name] = found.get_aabb()
	root.free()


## Los colores de vértice del kit son una máscara de desgaste: hay que ignorarlos.
func _fixed_material(src: Material) -> Material:
	if src == null:
		return null
	var id := src.get_instance_id()
	if _mat_cache.has(id):
		return _mat_cache[id]
	var m := src.duplicate() as Material
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		b.vertex_color_use_as_albedo = false
		if b.resource_name.begins_with("MI_FakeInterior"):
			b.emission_enabled = true
			b.emission = Color(1.0, 0.82, 0.55)
			b.emission_energy_multiplier = 0.0
			if b.albedo_texture:
				b.emission_texture = b.albedo_texture
			_lit_mats.append(b)
	_mat_cache[id] = m
	return m


func _flush() -> void:
	for key in _buckets:
		var cell: Dictionary = _buckets[key]
		for mesh_name in cell:
			var xfs: Array = cell[mesh_name]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _meshes[mesh_name]
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mi := MultiMeshInstance3D.new()
			mi.name = "Kit_%d_%d_%s" % [key.x, key.y, mesh_name]
			mi.multimesh = mm
			mi.visibility_range_end = VIS_END
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			stats["instances"] += xfs.size()
			stats["multimeshes"] += 1
			stats["triangles"] += int(_tris[mesh_name]) * xfs.size()
	_buckets.clear()
