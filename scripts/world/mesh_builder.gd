class_name MeshBuilder
extends RefCounted
## Construye ArrayMesh con varias superficies (una por material) a partir de
## primitivas: cajas, cilindros, esferas, quads y extrusiones de perfiles 2D.
## Todo el formato de vértice es uniforme (posición, normal, UV, color), y el
## orden de los triángulos se corrige solo para que la cara frontal mire a la normal.

var _tools: Dictionary = {}
var _materials: Dictionary = {}
var _counts: Dictionary = {}
var _order: Array = []


func surface(key: String, material: Material) -> MeshBuilder:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		_materials[key] = material
		_counts[key] = 0
		_order.append(key)
	return self


func has_geometry() -> bool:
	for k in _order:
		if int(_counts[k]) > 0:
			return true
	return false


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in _order:
		if int(_counts[key]) == 0:
			continue
		var st: SurfaceTool = _tools[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[key])
	return mesh


func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## Triángulo con normales por vértice. Corrige el orden (Godot: horario = frontal).
## uv2 opcional: si una superficie la usa, todos sus triángulos deben pasarla.
func tri(key: String, p: Array, n: Array, uv: Array, c: Color = Color.WHITE, uv2: Array = []) -> void:
	var st: SurfaceTool = _tools[key]
	var face_n: Vector3 = (n[0] + n[1] + n[2]).normalized()
	var cross := (p[1] - p[0]).cross(p[2] - p[0])
	var order := [0, 1, 2]
	if cross.dot(face_n) > 0.0:
		order = [0, 2, 1]
	for i in order:
		if not uv2.is_empty():
			st.set_uv2(uv2[i])
		_vertex(st, p[i], n[i], uv[i], c)
	_counts[key] = int(_counts[key]) + 3


## Quad con UV y una UV2 constante (datos por tramo para shaders).
func quad_uv2(key: String, pts: Array, uvs: Array, data: Vector2, n: Vector3 = Vector3.UP) -> void:
	var d := [data, data, data]
	tri(key, [pts[0], pts[1], pts[2]], [n, n, n], [uvs[0], uvs[1], uvs[2]], Color.WHITE, d)
	tri(key, [pts[0], pts[2], pts[3]], [n, n, n], [uvs[0], uvs[2], uvs[3]], Color.WHITE, d)


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color = Color.WHITE, uv_scale: Vector2 = Vector2.ONE) -> void:
	tri(key, [a, b, c], [n, n, n], [Vector2(0, 0), Vector2(uv_scale.x, 0), uv_scale], color)
	tri(key, [a, c, d], [n, n, n], [Vector2(0, 0), uv_scale, Vector2(0, uv_scale.y)], color)


## Quad con UV y UV2 explícitas (para el shader de carreteras).
func quad_uv(key: String, pts: Array, uvs: Array, n: Vector3, color: Color = Color.WHITE) -> void:
	tri(key, [pts[0], pts[1], pts[2]], [n, n, n], [uvs[0], uvs[1], uvs[2]], color)
	tri(key, [pts[0], pts[2], pts[3]], [n, n, n], [uvs[0], uvs[2], uvs[3]], color)


func box(key: String, center: Vector3, size: Vector3, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, skip_bottom: bool = true) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		if skip_bottom and n == Vector3.DOWN:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := center + n * (h * n.abs()).length()
		var hu := (h * u.abs()).length()
		var hv := (h * v.abs()).length()
		var pts := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		for i in 4:
			pts[i] = xf * pts[i]
		quad(key, pts[0], pts[1], pts[2], pts[3], (xf.basis * n).normalized(), color, Vector2(hu * 2.0, hv * 2.0))


## Cilindro (o tronco de cono) a lo largo del eje Y local, con base en `base`.
func cylinder(key: String, base: Vector3, r_bottom: float, r_top: float, height: float, segments: int = 10, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, caps: bool = true) -> void:
	var slope := (r_bottom - r_top) / maxf(height, 0.001)
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var p0 := base + d0 * r_bottom
		var p1 := base + d1 * r_bottom
		var p2 := base + d1 * r_top + Vector3(0, height, 0)
		var p3 := base + d0 * r_top + Vector3(0, height, 0)
		var bn := xf.basis
		var u0 := float(i) / segments
		var u1 := float(i + 1) / segments
		tri(key, [xf * p0, xf * p1, xf * p2], [bn * n0, bn * n1, bn * n1], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)], color)
		tri(key, [xf * p0, xf * p2, xf * p3], [bn * n0, bn * n1, bn * n0], [Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0)], color)
		if caps:
			var top := base + Vector3(0, height, 0)
			if r_top > 0.001:
				tri(key, [xf * top, xf * p3, xf * p2], [bn * Vector3.UP, bn * Vector3.UP, bn * Vector3.UP], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)], color)
			if r_bottom > 0.001:
				tri(key, [xf * base, xf * p0, xf * p1], [bn * Vector3.DOWN, bn * Vector3.DOWN, bn * Vector3.DOWN], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)], color)


## Esfera / elipsoide de baja resolución.
func sphere(key: String, center: Vector3, radii: Vector3, rings: int = 6, segments: int = 10, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE) -> void:
	for r in rings:
		var t0 := PI * float(r) / rings
		var t1 := PI * float(r + 1) / rings
		for s in segments:
			var a0 := TAU * float(s) / segments
			var a1 := TAU * float(s + 1) / segments
			var dirs := [
				Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)),
				Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
				Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)),
				Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0)),
			]
			var pts: Array = []
			var ns: Array = []
			for d in dirs:
				pts.append(xf * (center + d * radii))
				ns.append((xf.basis * (d / radii)).normalized())
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			if r > 0:
				tri(key, [pts[0], pts[1], pts[2]], [ns[0], ns[1], ns[2]], [uv[0], uv[1], uv[2]], color)
			if r < rings - 1:
				tri(key, [pts[0], pts[2], pts[3]], [ns[0], ns[2], ns[3]], [uv[0], uv[2], uv[3]], color)


## Extruye un perfil 2D (x = eje Z local, y = eje Y local) a lo ancho del eje X.
func extrude(key: String, profile: PackedVector2Array, x_min: float, x_max: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE) -> void:
	var poly := profile
	if Geometry2D.is_polygon_clockwise(poly):
		poly = PackedVector2Array()
		for i in range(profile.size() - 1, -1, -1):
			poly.append(profile[i])
	var idx := Geometry2D.triangulate_polygon(poly)
	var bn := xf.basis
	for side in [x_min, x_max]:
		var n := Vector3.RIGHT if side == x_max else Vector3.LEFT
		for t in range(0, idx.size(), 3):
			var pts: Array = []
			var uvs: Array = []
			for k in 3:
				var q: Vector2 = poly[idx[t + k]]
				pts.append(xf * Vector3(side, q.y, q.x))
				uvs.append(q)
			tri(key, pts, [bn * n, bn * n, bn * n], uvs, color)
	var count := poly.size()
	var centroid := Vector2.ZERO
	for q in poly:
		centroid += q
	centroid /= float(count)
	for i in count:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % count]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a + b) * 0.5 - centroid) < 0.0:
			n2 = -n2
		var n := (bn * Vector3(0, n2.y, n2.x)).normalized()
		var p0 := xf * Vector3(x_min, a.y, a.x)
		var p1 := xf * Vector3(x_max, a.y, a.x)
		var p2 := xf * Vector3(x_max, b.y, b.x)
		var p3 := xf * Vector3(x_min, b.y, b.x)
		quad(key, p0, p1, p2, p3, n, color)


## Hoja plana doblada (frondas de palmera). Cara doble para no depender del culling.
func leaf(key: String, root: Vector3, dir: Vector3, length: float, width: float, droop: float, color: Color, segments: int = 4) -> void:
	var side := dir.cross(Vector3.UP).normalized() * width * 0.5
	if side.length() < 0.001:
		side = Vector3.RIGHT * width * 0.5
	var prev_c := root
	var prev_w := 0.15
	for i in segments:
		var t := float(i + 1) / segments
		var c := root + dir * length * t + Vector3.DOWN * droop * t * t
		var w := sin(t * PI) * 0.9 + 0.1
		if i == segments - 1:
			w = 0.05
		var a := prev_c - side * prev_w
		var b := prev_c + side * prev_w
		var cc := c + side * w
		var d := c - side * w
		var n := (b - a).cross(d - a).normalized()
		if n.y < 0.0:
			n = -n
		quad(key, a, b, cc, d, n, color)
		quad(key, a, d, cc, b, -n, color)
		prev_c = c
		prev_w = w


static func material(color: Color, roughness: float = 0.8, metallic: float = 0.0, emission: Color = Color.BLACK, emission_energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m
