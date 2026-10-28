class_name RealCarModel
extends RefCounted
## Coches con modelo real (Sketchfab, CC-BY, Daniel Zhabotinsky — ver assets/CREDITOS.md).
## Junta todas las piezas de la carrocería en una sola malla con varias superficies
## (pocas llamadas de dibujo), gira el modelo para que el frente mire a +Z como
## espera Car/VehicleBody3D y separa las ruedas para que giren.
## El color de pintura se aplica duplicando solo el material de carrocería.

const MODELS := {
	"kiri86": "res://assets/cars/kiri86/kiri86.fbx",
	"doutrive78": "res://assets/cars/doutrive78/doutrive78.fbx",
	"eugene65": "res://assets/cars/eugene65/eugene65.fbx",
}
## Estilo procedural -> modelo real.
const STYLE_MODEL := {0: "kiri86", 1: "kiri86", 2: "eugene65", 3: "doutrive78"}

static var _cache: Dictionary = {}       # id -> datos base
static var _painted: Dictionary = {}     # id+color -> ArrayMesh


static func available(id: String) -> bool:
	return MODELS.has(id) and ResourceLoader.exists(MODELS[id])


static func for_style(style: int) -> String:
	var id: String = STYLE_MODEL.get(style, "")
	return id if available(id) else ""


## {body: ArrayMesh, wheels: [{pos, mesh, front, side}], wheel_r, half_w, length, height, track, wheel_z}
static func data(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var root: Node3D = (load(MODELS[id]) as PackedScene).instantiate()
	var rot := Basis(Vector3.UP, -PI * 0.5)  # +X del modelo -> +Z del juego
	var st_by_mat: Dictionary = {}
	var mats: Dictionary = {}
	var wheels: Array = []
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D(rot, Vector3.ZERO) * _world_xf(mi)
		var nm := String(mi.name).to_lower()
		if nm.contains("wheel"):
			var wa := xf * mi.mesh.get_aabb()
			var c := wa.get_center()
			var wmesh := _transformed(mi.mesh, Transform3D(Basis.IDENTITY, -c) * xf)
			wheels.append({"pos": c, "mesh": wmesh, "radius": wa.size.y * 0.5})
			continue
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var key := mat.resource_name if mat else "default"
			if not st_by_mat.has(key):
				var stool := SurfaceTool.new()
				stool.begin(Mesh.PRIMITIVE_TRIANGLES)
				st_by_mat[key] = stool
				mats[key] = _fix_material(mat)
			var arrays := mi.mesh.surface_get_arrays(s)
			(st_by_mat[key] as SurfaceTool).append_from(_single_surface(arrays, mat), 0, xf)
		var b := xf * mi.mesh.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	var body := ArrayMesh.new()
	var body_surface := -1
	for key in st_by_mat:
		var stool: SurfaceTool = st_by_mat[key]
		stool.commit(body)
		body.surface_set_material(body.get_surface_count() - 1, mats[key])
		if String(key).to_lower().contains("bodymat"):
			body_surface = body.get_surface_count() - 1
	root.free()
	var r := 0.3
	var track := 0.8
	var wheel_z := 1.4
	for w in wheels:
		var p: Vector3 = w["pos"]
		w["front"] = p.z > 0.0
		w["side"] = signf(p.x)
		r = w["radius"]
		track = absf(p.x)
		wheel_z = absf(p.z)
	var d := {
		"body": body, "body_surface": body_surface, "wheels": wheels, "wheel_r": r,
		"half_w": (hi.x - lo.x) * 0.5, "length": hi.z - lo.z, "height": hi.y,
		"track": track, "center_z": (hi.z + lo.z) * 0.5,
	}
	_cache[id] = d
	return d


## Carrocería pintada del color pedido (el material de pintura se duplica y cachea).
static func painted_body(id: String, color: Color) -> ArrayMesh:
	var key := id + color.to_html()
	if _painted.has(key):
		return _painted[key]
	var d := data(id)
	var base: ArrayMesh = d["body"]
	var mesh := base.duplicate() as ArrayMesh
	var si: int = d["body_surface"]
	if si >= 0:
		var m := base.surface_get_material(si)
		if m is StandardMaterial3D:
			var pm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			pm.albedo_color = color
			pm.metallic = maxf(pm.metallic, 0.35)
			pm.roughness = minf(pm.roughness, 0.35)
			pm.clearcoat_enabled = true
			pm.clearcoat = 0.7
			mesh.surface_set_material(si, pm)
	_painted[key] = mesh
	return mesh


## Malla completa (carrocería + ruedas) para coches aparcados y de tráfico.
static func full_mesh(id: String, color: Color) -> ArrayMesh:
	var key := "full" + id + color.to_html()
	if _painted.has(key):
		return _painted[key]
	var d := data(id)
	var body := painted_body(id, color)
	var mesh := ArrayMesh.new()
	for s in body.get_surface_count():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body.surface_get_arrays(s))
		mesh.surface_set_material(s, body.surface_get_material(s))
	var tyre_tool := SurfaceTool.new()
	tyre_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tyre_mat: Material = null
	for w in d["wheels"]:
		var wm: ArrayMesh = w["mesh"]
		for s in wm.get_surface_count():
			tyre_tool.append_from(wm, s, Transform3D(Basis.IDENTITY, w["pos"]))
			tyre_mat = wm.surface_get_material(s)
	if not (d["wheels"] as Array).is_empty():
		tyre_tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tyre_mat)
	_painted[key] = mesh
	return mesh


static func _single_surface(arrays: Array, mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat:
		m.surface_set_material(0, mat)
	return m


static func _transformed(src: Mesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(_single_surface(src.surface_get_arrays(s), null), 0, xf)
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _fix_material(src.surface_get_material(s)))
	return out


static func _fix_material(mat: Material) -> Material:
	if mat is StandardMaterial3D:
		var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = false
		var n := String(mat.resource_name).to_lower()
		if n.contains("transperent") or n.contains("glass"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if m.albedo_color.a > 0.6:
				m.albedo_color.a = 0.45
			m.roughness = 0.05
			m.metallic = 0.2
		return m
	return mat


static func _world_xf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
