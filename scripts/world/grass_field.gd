class_name GrassField
extends Node3D
## Hierba 3D en los céspedes cerca de la cámara: una rejilla de celdas de 8 m que
## comparten dos MultiMesh (densa cerca y ligera en el anillo exterior) y se
## recolocan al moverse la cámara. Una máscara de los jardines (sin casas ni
## piscinas) decide en el shader dónde aparecen las matas; con la distancia se
## encogen hasta desaparecer. No proyectan sombra ni entran en el SDFGI.

const CELL := 8.0
const MASK_RES := 0.5          # metros por píxel de la máscara
const DENSE := 1400            # matas por celda cercana
const SPARSE := 500           # matas por celda del anillo exterior

var _mat: ShaderMaterial
var _dense: MultiMesh
var _sparse: MultiMesh
var _nodes: Array = []
var _cells: int = 0
var _center := Vector2i(1 << 30, 0)
var _mask_img: Image
var _rect := Rect2()


func setup(city: CityBuilder) -> void:
	var rects: Array = []
	for blk in CityLayout.blocks():
		if blk["kind"] == "residential":
			rects.append((blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK - 0.6))
	if rects.is_empty():
		return
	_rect = rects[0]
	for r in rects:
		_rect = _rect.merge(r)
	_build_mask(rects, city.footprints, city.pools)
	var mesh := _clump_mesh()
	_dense = _make_multimesh(mesh, DENSE, 1)
	_sparse = _make_multimesh(mesh, SPARSE, 2)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/grass.gdshader")
	_mat.set_shader_parameter("lawn_mask", ImageTexture.create_from_image(_mask_img))
	_mat.set_shader_parameter("mask_rect", Vector4(_rect.position.x, _rect.position.y, _rect.size.x, _rect.size.y))
	var lawn := city.mat_lawn
	if lawn:
		var tex: Variant = lawn.get_shader_parameter("tex_albedo")
		if tex is Texture2D:
			_mat.set_shader_parameter("ground_albedo", tex)
		var tile: Variant = lawn.get_shader_parameter("tile")
		if tile != null:
			_mat.set_shader_parameter("ground_tile", float(tile))
		var tint: Variant = lawn.get_shader_parameter("tint")
		if tint is Color:
			_mat.set_shader_parameter("ground_tint", tint)
		# Segunda textura de césped en el suelo para romper la repetición.
		var mix_path := "res://assets/textures/grass_mix/albedo.jpg"
		if ResourceLoader.exists(mix_path):
			lawn.set_shader_parameter("tex_albedo2", load(mix_path))
			lawn.set_shader_parameter("use_texture2", true)
	_dense.mesh.surface_set_material(0, _mat)


func set_cells(cells: int) -> void:
	if _dense == null:
		return
	cells = clampi(cells, 0, 3)
	if cells == _cells and not _nodes.is_empty():
		return
	_cells = cells
	for n in _nodes:
		(n as Node).queue_free()
	_nodes.clear()
	_center = Vector2i(1 << 30, 0)
	var side := cells * 2 + 1
	for i in (side * side if cells > 0 else 0):
		var mmi := MultiMeshInstance3D.new()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.extra_cull_margin = 1.0
		mmi.top_level = true
		add_child(mmi)
		_nodes.append(mmi)
	var far := CELL * (float(cells) + 0.5)
	_mat.set_shader_parameter("fade_start", far * 0.45)
	_mat.set_shader_parameter("fade_end", far * 0.92)


func _process(_delta: float) -> void:
	if _nodes.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if c == _center:
		return
	_center = c
	var i := 0
	for dz in range(-_cells, _cells + 1):
		for dx in range(-_cells, _cells + 1):
			var mmi := _nodes[i] as MultiMeshInstance3D
			i += 1
			var cx := c.x + dx
			var cz := c.y + dz
			var origin := Vector3(cx * CELL, 0.1, cz * CELL)
			if p.y > 40.0 or not _cell_has_lawn(cx, cz):
				mmi.visible = false
				continue
			var ring := maxi(absi(dx), absi(dz))
			mmi.multimesh = _dense if ring <= 1 else _sparse
			mmi.global_transform = Transform3D(Basis.IDENTITY, origin)
			mmi.visible = true


func _cell_has_lawn(cx: int, cz: int) -> bool:
	var r := Rect2(cx * CELL, cz * CELL, CELL, CELL)
	if not r.intersects(_rect):
		return false
	var step := 4
	var x0 := int((r.position.x - _rect.position.x) / MASK_RES)
	var z0 := int((r.position.y - _rect.position.y) / MASK_RES)
	var n := int(CELL / MASK_RES)
	for z in range(0, n, step):
		for x in range(0, n, step):
			var px := x0 + x
			var pz := z0 + z
			if px >= 0 and pz >= 0 and px < _mask_img.get_width() and pz < _mask_img.get_height():
				if _mask_img.get_pixel(px, pz).r > 0.5:
					return true
	return false


func _build_mask(rects: Array, footprints: Array, pools: Array) -> void:
	var w := int(ceil(_rect.size.x / MASK_RES))
	var h := int(ceil(_rect.size.y / MASK_RES))
	_mask_img = Image.create_empty(w, h, false, Image.FORMAT_L8)
	for r in rects:
		_fill(r, Color(1, 1, 1))
	for f in footprints:
		_fill((f as Rect2).grow(0.7), Color(0, 0, 0))
	for pl in pools:
		_fill((pl as Rect2).grow(0.8), Color(0, 0, 0))


func _fill(r: Rect2, c: Color) -> void:
	var x0 := int(floor((r.position.x - _rect.position.x) / MASK_RES))
	var z0 := int(floor((r.position.y - _rect.position.y) / MASK_RES))
	var x1 := int(ceil((r.end.x - _rect.position.x) / MASK_RES))
	var z1 := int(ceil((r.end.y - _rect.position.y) / MASK_RES))
	x0 = clampi(x0, 0, _mask_img.get_width())
	z0 = clampi(z0, 0, _mask_img.get_height())
	x1 = clampi(x1, 0, _mask_img.get_width())
	z1 = clampi(z1, 0, _mask_img.get_height())
	if x1 > x0 and z1 > z0:
		_mask_img.fill_rect(Rect2i(x0, z0, x1 - x0, z1 - z0), c)


func _make_multimesh(mesh: ArrayMesh, count: int, seed_v: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var r := RandomNumberGenerator.new()
	r.seed = 7331 + seed_v
	for i in count:
		var b := Basis(Vector3.UP, r.randf() * TAU)
		b = b.scaled(Vector3(1.0, r.randf_range(0.7, 1.3), 1.0))
		mm.set_instance_transform(i, Transform3D(b, Vector3(r.randf() * CELL, 0.0, r.randf() * CELL)))
	mm.custom_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(CELL + 2.0, 2.0, CELL + 2.0))
	return mm


## Mata de 7 hojas finas y curvadas (2 tramos + punta) que se abren desde el centro.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for blade in 7:
		var ang := TAU * float(blade) / 7.0 + r.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var height := r.randf_range(0.14, 0.26)
		var lean := r.randf_range(0.04, 0.1)
		var width := r.randf_range(0.01, 0.016)
		var base := dir * r.randf_range(0.0, 0.06)
		var pts: Array = []
		for k in 3:
			var t := float(k) / 2.0
			var c := base + dir * lean * t * t + Vector3.UP * height * t
			var wk := width * (1.0 - t * 0.55)
			pts.append([c - side * wk, c + side * wk, t])
		var tip := base + dir * lean * 1.4 + Vector3.UP * height * 1.12
		var n := (dir * -0.3 + Vector3.UP).normalized()
		for k in 2:
			var a: Array = pts[k]
			var b: Array = pts[k + 1]
			_tri(st, a[0], a[1], b[1], float(a[2]), float(a[2]), float(b[2]), n)
			_tri(st, a[0], b[1], b[0], float(a[2]), float(b[2]), float(b[2]), n)
		var l: Array = pts[2]
		_tri(st, l[0], l[1], tip, float(l[2]), float(l[2]), 1.0, n)
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: float, ub: float, uc: float, n: Vector3) -> void:
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(n)
		st.set_uv(Vector2(0.5, pair[1]))
		st.add_vertex(pair[0])
