extends SceneTree
## Herramienta de preparación de modelos externos (Sketchfab) para móvil.
## Se ejecuta fuera del juego (proyecto de trabajo con los originales en res://in/):
##   godot --headless --path <trabajo> -s res://tools/bake_asset.gd -- --id=cuda71 --pass=1
##   godot --headless --path <trabajo> --import
##   godot --headless --path <trabajo> -s res://tools/bake_asset.gd -- --id=cuda71 --pass=2
## Pasada 1: reduce las texturas (<= tex px, JPG/PNG) y las guarda en la carpeta de salida.
## Pasada 2: fusiona por material, decima con SurfaceTool.generate_lod (meshopt), elimina
## logotipos/piezas ocultas y guarda <out>/<id>.scn con las texturas reducidas.
## Los coches salen normalizados: frente a +X, y=0 en el suelo, centrados, ruedas separadas
## (wheel_fl/fr/rl/rr) para RealCarModel.

var A := {}
var C := {}
var pass_n := 1
var out_dir := ""
var _tex_done := {}
var _mat_info := {}

func _init() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	pass_n = int(A.get("pass", "1"))
	var cfgs: Dictionary = (load("res://tools/bake_cfg.gd") as GDScript).new().CFG
	C = (cfgs[A["id"]] as Dictionary).duplicate()
	C["id"] = A["id"]
	out_dir = C["out"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run()
	quit()


# ------------------------------------------------------------------ recogida

func _world_xf(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _load_root() -> Node3D:
	var res = load(C["src"])
	if res is PackedScene:
		return res.instantiate()
	var r := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = res
	r.add_child(mi)
	return r


func _tex_path(t: Texture2D) -> String:
	return t.resource_path if t else ""


func _matches(s: String, pats: Array) -> bool:
	var l := s.to_lower()
	for p in pats:
		if l.contains(String(p).to_lower()):
			return true
	return false


## Devuelve [{arrays, mat, xf, node, ancestors}] de todas las superficies útiles.
func _gather(root: Node3D) -> Array:
	var parts: Array = []
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var anc := ""
		var p := mi.get_parent()
		while p and p != root:
			anc += String(p.name) + "/"
			p = p.get_parent()
		if _matches(String(mi.name), C.get("drop_nodes", [])) or _matches(anc, C.get("drop_nodes", [])):
			continue
		var xf := _world_xf(mi, root)
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var mname := mat.resource_name if mat else ""
			var xt: Dictionary = C.get("extra_tex", {})
			if mat is BaseMaterial3D and xt.has(mname):
				var bm := mat as BaseMaterial3D
				if xt[mname].has("albedo"): bm.albedo_texture = load(xt[mname]["albedo"])
				if xt[mname].has("normal"):
					bm.normal_enabled = true
					bm.normal_texture = load(xt[mname]["normal"])
			if _matches(mname, C.get("drop_mats", [])):
				continue
			var tp := ""
			if mat is BaseMaterial3D:
				tp = _tex_path((mat as BaseMaterial3D).albedo_texture)
			if tp != "" and _matches(tp.get_file(), C.get("drop_tex", [])):
				continue
			parts.append({"mesh": mi.mesh, "surf": s, "mat": mat, "xf": xf, "node": String(mi.name), "anc": anc})
	return parts


func _tri_count(arrays: Array) -> int:
	var idx = arrays[Mesh.ARRAY_INDEX]
	if idx != null and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


# ------------------------------------------------------------------ texturas (pasada 1)

func _slot_tex(b: BaseMaterial3D) -> Dictionary:
	var d := {}
	if b.albedo_texture: d["albedo"] = b.albedo_texture
	if b.normal_enabled and b.normal_texture: d["normal"] = b.normal_texture
	if b.metallic_texture: d["metallic"] = b.metallic_texture
	if b.roughness_texture: d["roughness"] = b.roughness_texture
	if b.emission_enabled and b.emission_texture: d["emission"] = b.emission_texture
	return d


func _img_of(t: Texture2D) -> Image:
	var p := t.resource_path
	if p.begins_with("res://in/") and not p.contains("::") and FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img:
			return img
	var im := t.get_image()
	if im == null:
		return null
	if im.is_compressed():
		im.decompress()
	return im


func _tex_key(t: Texture2D, slot: String, mat_name: String) -> String:
	var p := t.resource_path
	var base := p.get_file().get_basename() if p != "" else mat_name
	if p.contains("::") or p.get_extension() in ["glb", "fbx", "ctex", "scn"]:
		base = String(C.get("tex_id", C["id"])) + "_" + mat_name
	var s := base.validate_filename().replace(" ", "_").replace("#", "")
	return s + "_" + slot if not s.ends_with(slot) else s


func _opacity_for(t: Texture2D) -> Image:
	var p := t.resource_path
	if not p.begins_with("res://in/"):
		return null
	var stem := p.get_file().get_basename()
	var dir := p.get_base_dir()
	var cands: Array = []
	for pair in [["_bc", "_opacity"], ["_c", "_opac"], ["_color", "_opacity"], ["_diffuse", "_opacity"], ["_Diffuse", "_Opacity"], ["_D", "_O"]]:
		if stem.ends_with(pair[0]):
			cands.append(stem.left(stem.length() - pair[0].length()) + pair[1])
	if stem.ends_with("c") and stem.left(stem.length() - 1).is_valid_int():
		cands.append(stem.left(stem.length() - 1) + "_opac")
	for c in cands:
		for ext in ["jpg", "jpeg", "png"]:
			var f: String = dir + "/" + String(c) + "." + ext
			if FileAccess.file_exists(f):
				return Image.load_from_file(ProjectSettings.globalize_path(f))
	return null


func _export_tex(t: Texture2D, slot: String, mat_name: String) -> String:
	var key := _tex_key(t, slot, mat_name)
	if _tex_done.has(key):
		return _tex_done[key]
	var img := _img_of(t)
	if img == null:
		push_warning("sin imagen: " + key)
		return ""
	var cap: int = C.get("tex", 1024)
	var big: Dictionary = C.get("tex_big", {})
	for k in big:
		if key.to_lower().contains(String(k).to_lower()):
			cap = int(big[k])
	var has_alpha := false
	img.convert(Image.FORMAT_RGBA8)
	if slot == "albedo":
		var op := _opacity_for(t)
		if op != null:
			op.convert(Image.FORMAT_L8)
			if op.get_size() != img.get_size():
				op.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					c.a = op.get_pixel(x, y).r
					img.set_pixel(x, y, c)
			has_alpha = true
		else:
			# ¿alfa real?
			var d := img.get_data()
			for i in range(3, d.size(), 4):
				if d[i] < 250:
					has_alpha = true
					break
	var w := img.get_width()
	var h := img.get_height()
	var m := maxi(w, h)
	if m > cap:
		var s := float(cap) / float(m)
		img.resize(maxi(int(w * s), 4), maxi(int(h * s), 4), Image.INTERPOLATE_LANCZOS)
	var path := out_dir + key + (".png" if has_alpha else ".jpg")
	var abs := ProjectSettings.globalize_path(path)
	if has_alpha:
		img.save_png(abs)
	else:
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(abs, 0.88)
	_tex_done[key] = path
	return path


func _export_all_textures(parts: Array) -> void:
	var seen := {}
	for p in parts:
		var mat: Material = p["mat"]
		if mat == null or seen.has(mat) or not (mat is BaseMaterial3D):
			continue
		seen[mat] = true
		var b := mat as BaseMaterial3D
		for slot in _slot_tex(b):
			var pth := _export_tex(_slot_tex(b)[slot], slot, mat.resource_name)
			print("TEX ", mat.resource_name, " ", slot, " -> ", pth.get_file())


# ------------------------------------------------------------------ materiales (pasada 2)

func _new_mat(src: Material, name_override: String = "") -> Material:
	if not (src is BaseMaterial3D):
		return src
	var b := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	b.resource_name = name_override if name_override != "" else src.resource_name
	b.vertex_color_use_as_albedo = false
	var srcb := src as BaseMaterial3D
	var st := _slot_tex(srcb)
	var alpha_tex := false
	for slot in st:
		var key := _tex_key(st[slot], slot, src.resource_name)
		var path := ""
		for ext in ["jpg", "png"]:
			if ResourceLoader.exists(out_dir + key + "." + ext):
				path = out_dir + key + "." + ext
		if path == "":
			continue
		var tex := load(path) as Texture2D
		match slot:
			"albedo": b.albedo_texture = tex
			"normal": b.normal_texture = tex
			"metallic": b.metallic_texture = tex
			"roughness": b.roughness_texture = tex
			"emission": b.emission_texture = tex
		if slot == "albedo" and path.ends_with(".png"):
			alpha_tex = true
	if alpha_tex and b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		b.alpha_scissor_threshold = 0.5
		b.cull_mode = BaseMaterial3D.CULL_DISABLED
	if C.get("opaque_color", false):
		b.albedo_color = Color(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b, 1.0)
	var ov: Dictionary = C.get("mat_over", {})
	for k in ov:
		if String(src.resource_name).to_lower() == String(k).to_lower():
			for prop in ov[k]:
				b.set(prop, ov[k][prop])
	if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and not String(b.resource_name).to_lower().contains("glass"):
		pass
	return b


# ------------------------------------------------------------------ geometría

func _xform_arrays(arrays: Array, xf: Transform3D) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n = arrays[Mesh.ARRAY_NORMAL]
	var uv = arrays[Mesh.ARRAY_TEX_UV]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var nv := PackedVector3Array()
	nv.resize(v.size())
	var nb := xf.basis.inverse().transposed()
	for i in v.size():
		nv[i] = xf * v[i]
	out[Mesh.ARRAY_VERTEX] = nv
	if n != null and (n as PackedVector3Array).size() == v.size():
		var nn := PackedVector3Array()
		nn.resize(v.size())
		for i in v.size():
			nn[i] = (nb * (n as PackedVector3Array)[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = nn
	if uv != null and (uv as PackedVector2Array).size() == v.size():
		out[Mesh.ARRAY_TEX_UV] = uv
	if idx != null and (idx as PackedInt32Array).size() > 0:
		out[Mesh.ARRAY_INDEX] = idx
	else:
		var ii := PackedInt32Array()
		ii.resize(v.size())
		for i in v.size():
			ii[i] = i
		out[Mesh.ARRAY_INDEX] = ii
	return out


## Concatena varios arrays (ya transformados) en uno.
func _concat(list: Array) -> Array:
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	var has_n := true
	var has_u := true
	for a in list:
		has_n = has_n and a[Mesh.ARRAY_NORMAL] != null
		has_u = has_u and a[Mesh.ARRAY_TEX_UV] != null
	for a in list:
		var off := V.size()
		V.append_array(a[Mesh.ARRAY_VERTEX])
		if has_n:
			N.append_array(a[Mesh.ARRAY_NORMAL])
		if has_u:
			U.append_array(a[Mesh.ARRAY_TEX_UV])
		var ii: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var base := I.size()
		I.resize(base + ii.size())
		for k in ii.size():
			I[base + k] = ii[k] + off
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = V
	if has_n: out[Mesh.ARRAY_NORMAL] = N
	if has_u: out[Mesh.ARRAY_TEX_UV] = U
	out[Mesh.ARRAY_INDEX] = I
	return out


## Decima a ~target triángulos (meshopt vía SurfaceTool) y compacta los vértices.
func _decimate(arrays: Array, target_tris: int) -> Array:
	var tris := _tri_count(arrays)
	if tris <= target_tris:
		return _compact(arrays, arrays[Mesh.ARRAY_INDEX])
	var V: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var U: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if N.size() != V.size():
		N.resize(V.size())
	if U.size() != V.size():
		U.resize(V.size())
	var I: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tmp_in := ProjectSettings.globalize_path("res://.bake_in.bin")
	var tmp_out := ProjectSettings.globalize_path("res://.bake_out.bin")
	var f := FileAccess.open(tmp_in, FileAccess.WRITE)
	f.store_32(V.size())
	f.store_32(I.size())
	f.store_buffer(V.to_byte_array())
	f.store_buffer(N.to_byte_array())
	f.store_buffer(U.to_byte_array())
	f.store_buffer(I.to_byte_array())
	f.close()
	var outp := []
	var code := OS.execute("python3", ["-I", ProjectSettings.globalize_path("res://tools/decimate.py"), tmp_in, tmp_out, str(target_tris), str(C.get("uv_weight", 1.0))], outp, true)
	if code != 0 or not FileAccess.file_exists(tmp_out):
		push_warning("decimate falló: " + str(outp))
		return _compact(arrays, arrays[Mesh.ARRAY_INDEX])
	var fo := FileAccess.open(tmp_out, FileAccess.READ)
	var n := fo.get_32()
	var lod := fo.get_buffer(n * 4).to_int32_array()
	fo.close()
	DirAccess.remove_absolute(tmp_out)
	return _compact(arrays, lod)


func _compact(arrays: Array, idx: PackedInt32Array) -> Array:
	var V: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var N = arrays[Mesh.ARRAY_NORMAL]
	var U = arrays[Mesh.ARRAY_TEX_UV]
	var remap := PackedInt32Array()
	remap.resize(V.size())
	remap.fill(-1)
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nu := PackedVector2Array()
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for k in idx.size():
		var o := idx[k]
		var r := remap[o]
		if r < 0:
			r = nv.size()
			remap[o] = r
			nv.append(V[o])
			if N != null: nn.append((N as PackedVector3Array)[o])
			if U != null: nu.append((U as PackedVector2Array)[o])
		ni[k] = r
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	if N != null: out[Mesh.ARRAY_NORMAL] = nn
	if U != null: out[Mesh.ARRAY_TEX_UV] = nu
	out[Mesh.ARRAY_INDEX] = ni
	return out


## Divide un array por cuadrante (x>cx, z>cz) del centroide de cada triángulo.
func _split_quadrants(arrays: Array, cx: float, cz: float) -> Dictionary:
	var V: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var buckets := {"fl": PackedInt32Array(), "fr": PackedInt32Array(), "rl": PackedInt32Array(), "rr": PackedInt32Array()}
	for t in range(0, I.size(), 3):
		var c := (V[I[t]] + V[I[t + 1]] + V[I[t + 2]]) / 3.0
		var key := ("f" if c.x > cx else "r") + ("l" if c.z < cz else "r")
		var arr: PackedInt32Array = buckets[key]
		arr.append(I[t]); arr.append(I[t + 1]); arr.append(I[t + 2])
		buckets[key] = arr
	var out := {}
	for k in buckets:
		if (buckets[k] as PackedInt32Array).size() > 0:
			out[k] = _compact(arrays, buckets[k])
	return out


func _with_tangents(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_NORMAL] == null:
		return arrays
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	return st.commit_to_arrays()


func _aabb_of(list: Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for a in list:
		for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = lo.min(v)
			hi = hi.max(v)
	return AABB(lo, hi - lo)


# ------------------------------------------------------------------ construcción

func _run() -> void:
	var root := _load_root()
	var parts := _gather(root)
	var tris_in := 0
	for p in parts:
		tris_in += _tri_count((p["mesh"] as Mesh).surface_get_arrays(p["surf"]))
	print("[%s] superficies=%d triángulos de entrada=%d" % [C["id"], parts.size(), tris_in])
	if pass_n == 1:
		_export_all_textures(parts)
		return
	# Transformar a espacio normalizado.
	var N := _normalization(parts)
	var items: Array = []     # {arrays, mat, wheel}
	var wheel_mats: Array = C.get("wheel_mats", [])
	var wheel_nodes: Array = C.get("wheel_nodes", [])
	for p in parts:
		var arr := _xform_arrays((p["mesh"] as Mesh).surface_get_arrays(p["surf"]), N * (p["xf"] as Transform3D))
		var mname: String = (p["mat"] as Material).resource_name if p["mat"] else ""
		var is_wheel: bool = C["kind"] == "car" and (_matches(mname, wheel_mats) or _matches(String(p["anc"]) + String(p["node"]), wheel_nodes))
		items.append({"arrays": arr, "mat": p["mat"], "wheel": is_wheel, "name": mname})
	if C["kind"] == "car":
		_build_car(items)
	else:
		_build_static(items)


func _normalization(parts: Array) -> Transform3D:
	# Caja de todo el modelo en el espacio de origen.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in parts:
		var a := (p["mesh"] as Mesh).surface_get_arrays(p["surf"])
		var xf: Transform3D = p["xf"]
		for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var w := xf * v
			lo = lo.min(w)
			hi = hi.max(w)
	var yaw := float(C.get("yaw_deg", 0.0))
	var R := Basis(Vector3.UP, deg_to_rad(yaw))
	# Segunda pasada con la rotación para medir.
	var lo2 := Vector3(INF, INF, INF)
	var hi2 := -lo2
	var corners := [lo, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), hi]
	for c in corners:
		var w: Vector3 = R * c
		lo2 = lo2.min(w)
		hi2 = hi2.max(w)
	var ext := hi2 - lo2
	var s := 1.0
	if C.has("length"):
		s = float(C["length"]) / ext.x
	elif C.has("height"):
		s = float(C["height"]) / ext.y
	elif C.has("scale"):
		s = float(C["scale"])
	var ctr := Vector3((lo2.x + hi2.x) * 0.5, lo2.y, (lo2.z + hi2.z) * 0.5)
	if C.get("origin", "center") == "corner":
		ctr = Vector3(lo2.x, lo2.y, lo2.z)
	elif C.get("origin", "center") == "keep":
		ctr = Vector3.ZERO
	var off: Vector3 = C.get("offset", Vector3.ZERO)
	print("   caja origen ", ext, " escala ", s, " -> ", ext * s)
	return Transform3D(Basis.from_scale(Vector3.ONE * s) * R, -(ctr * s) + off)


func _budget(groups: Array, total: int) -> Array:
	var sum := 0
	for g in groups:
		sum += int(g["tris"])
	if sum <= total:
		return groups.map(func(g): return int(g["tris"]))
	var lo := 0.0
	var hi := 1.0
	var out: Array = []
	for it in 24:
		var r := (lo + hi) * 0.5
		var t := 0
		out.clear()
		for g in groups:
			var n: int = g["tris"]
			var w: float = g["w"]
			var tgt := n if n <= 48 else clampi(int(n * r * w), 48, n)
			out.append(tgt)
			t += tgt
		if t > total:
			hi = r
		else:
			lo = r
	out.clear()
	for g in groups:
		var n: int = g["tris"]
		out.append(n if n <= 48 else clampi(int(n * lo * float(g["w"])), 48, n))
	return out


## Agrupa por material, decima y devuelve un ArrayMesh con una superficie por material.
func _mesh_from(items: Array, total_tris: int, name_fix: Callable) -> ArrayMesh:
	var by_mat := {}
	var order: Array = []
	for it in items:
		var key = it["mat"]
		if not by_mat.has(key):
			by_mat[key] = []
			order.append(key)
		(by_mat[key] as Array).append(it["arrays"])
	var groups: Array = []
	for key in order:
		var merged := _concat(by_mat[key])
		var mname: String = (key as Material).resource_name if key else ""
		var w := 1.0
		var ws: Dictionary = C.get("weights", {})
		for k in ws:
			if mname.to_lower().contains(String(k).to_lower()):
				w = float(ws[k])
		groups.append({"mat": key, "arrays": merged, "tris": _tri_count(merged), "w": w})
	var targets := _budget(groups, total_tris)
	var mesh := ArrayMesh.new()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var arr := _decimate(g["arrays"], targets[gi])
		if (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < 3:
			continue
		var mat: Material = g["mat"]
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_enabled and (mat as BaseMaterial3D).normal_texture != null:
			arr = _with_tangents(arr)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var nm: Material = _new_mat(mat, name_fix.call(mat.resource_name if mat else ""))
		mesh.surface_set_material(mesh.get_surface_count() - 1, nm)
	return mesh


func _fix_name(n: String) -> String:
	var l := n.to_lower()
	var rn: Dictionary = C.get("rename_mats", {})
	for k in rn:
		if l == String(k).to_lower():
			return rn[k]
	if l.contains("window") or l.contains("windwos") or l == "ight_glass":
		return "glass_" + n
	return n


func _surface_tris(m: ArrayMesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		t += _tri_count(m.surface_get_arrays(s))
	return t


func _save(root: Node3D) -> void:
	var ps := PackedScene.new()
	ps.pack(root)
	var path := out_dir + String(C["id"]) + ".scn"
	var err := ResourceSaver.save(ps, path)
	print("GUARDADO ", path, " err=", err)


## Separa componentes conexos de las mallas del cuerpo y marca como rueda los redondos y bajos.
func _extract_wheels(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if it["wheel"]:
			out.append(it)
			continue
		var a: Array = it["arrays"]
		var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var weld := {}
		var rep := PackedInt32Array()
		rep.resize(V.size())
		for i in V.size():
			var k := Vector3i((V[i] * 2000.0).round())
			if not weld.has(k):
				weld[k] = i
			rep[i] = weld[k]
		var parent := PackedInt32Array()
		parent.resize(V.size())
		for i in V.size():
			parent[i] = i
		for t in range(0, I.size(), 3):
			for e in 2:
				var x := _find(parent, rep[I[t + e]])
				var y := _find(parent, rep[I[t + e + 1]])
				if x != y:
					parent[x] = y
		var comp := {}
		for t in range(0, I.size(), 3):
			var r := _find(parent, rep[I[t]])
			if not comp.has(r):
				comp[r] = PackedInt32Array()
			var arr: PackedInt32Array = comp[r]
			arr.append(I[t]); arr.append(I[t + 1]); arr.append(I[t + 2])
			comp[r] = arr
		var rest := PackedInt32Array()
		for r in comp:
			var ci := _compact(a, comp[r])
			var bb := _aabb_of([ci])
			var is_w: bool = bb.size.y > 0.45 and bb.size.y < 1.3 and absf(bb.size.x - bb.size.y) < 0.25 * bb.size.y and bb.size.z < 0.55 * bb.size.y and bb.position.y < 0.2
			print("   comp tris=%d size=%s pos=%s wheel=%s" % [_tri_count(ci), str(bb.size.snapped(Vector3(0.01, 0.01, 0.01))), str(bb.position.snapped(Vector3(0.01, 0.01, 0.01))), str(is_w)])
			if is_w:
				out.append({"arrays": ci, "mat": it["mat"], "wheel": true, "name": it["name"]})
			else:
				rest.append_array(comp[r])
		out.append({"arrays": _compact(a, rest), "mat": it["mat"], "wheel": false, "name": it["name"]})
	return out


func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


func _build_car(items: Array) -> void:
	if C.get("wheel_components", false):
		items = _extract_wheels(items)
	var body_items: Array = []
	var wheel_items: Array = []
	for it in items:
		(wheel_items if it["wheel"] else body_items).append(it)
	var all_arr: Array = []
	for it in body_items:
		all_arr.append(it["arrays"])
	var bb := _aabb_of(all_arr)
	var cx := bb.position.x + bb.size.x * 0.5
	var cz := bb.position.z + bb.size.z * 0.5
	# Ruedas: separar por cuadrante (X>cx = delante).
	var quads := {"fl": [], "fr": [], "rl": [], "rr": []}
	for it in wheel_items:
		var sp := _split_quadrants(it["arrays"], cx, cz)
		for k in sp:
			(quads[k] as Array).append({"arrays": sp[k], "mat": it["mat"]})
	var root := Node3D.new()
	root.name = C["id"]
	var wt: int = C.get("wheel_tris", 2000)
	var tot := 0
	for k in quads:
		if (quads[k] as Array).is_empty():
			continue
		var wm := _mesh_from(quads[k], wt, Callable(self, "_fix_name"))
		var mi := MeshInstance3D.new()
		mi.name = "wheel_" + k
		mi.mesh = wm
		root.add_child(mi)
		mi.owner = root
		tot += _surface_tris(wm)
	var body := _mesh_from(body_items, int(C["tris"]) - tot, Callable(self, "_fix_name"))
	# El material de pintura se llama "bodymat" para que RealCarModel lo pueda teñir.
	if C.has("paint_mat"):
		for s in body.get_surface_count():
			var m := body.surface_get_material(s)
			if m and String(m.resource_name).to_lower() == String(C["paint_mat"]).to_lower():
				m.resource_name = "bodymat"
	var bmi := MeshInstance3D.new()
	bmi.name = "Body"
	bmi.mesh = body
	root.add_child(bmi)
	bmi.owner = root
	print("   triángulos: carrocería=%d ruedas=%d total=%d" % [_surface_tris(body), tot, _surface_tris(body) + tot])
	_save(root)


func _build_static(items: Array) -> void:
	var root := Node3D.new()
	root.name = C["id"]
	var parts_n: int = C.get("split", 1)
	var mesh := _mesh_from(items, int(C["tris"]), Callable(self, "_fix_name"))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	var aabb := mesh.get_aabb()
	print("   triángulos=%d aabb=%s" % [_surface_tris(mesh), str(aabb)])
	_save(root)
