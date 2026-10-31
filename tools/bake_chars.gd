extends SceneTree
## Hornea los personajes Mixamo (FBX reparados) a escenas ligeras para móvil:
##   godot --headless --path <trabajo> -s res://tools/bake_chars.gd -- --id=Ch07 [--out=/ruta/assets/characters/mixamo]
## - huesos renombrados a mixamorig_* (sin numerar) para compartir una AnimationLibrary
## - mallas decimadas (meshopt) hasta ~15k triángulos, 4 pesos por vértice, sin tangentes
## - texturas a <=1K en WebP, materiales opacos (alpha scissor solo en pelo y pestañas)
## - escala normalizada para que la cadera mida 1,0 m de alto (misma que las animaciones)

const SRC := "/home/claude/mixamo_src/tex"
# Altura objetivo (m) de cada modelo: algo de variedad entre personas
const HEIGHT := {"Ch07": 1.70, "Ch22": 1.69, "Ch28": 1.82, "Ch12": 1.80, "Ch06": 1.84, "Remy": 1.77}
const TRI_BUDGET := 15000
const TEX_MAX := 1024

# Texturas por personaje: clave -> [archivo, archivo_opacidad|""].
const TEX := {
	"Ch07": {"body": ["Ch07/file1__Ch07_1001_Diffuse.png", ""], "hair": ["Ch07/file9__Ch07_1002_Diffuse.png", ""]},
	"Ch22": {"body": ["Ch22/file1__Ch22_1001_Diffuse.png", ""], "hair": ["Ch22/file7__Ch22_1002_Diffuse.png", ""]},
	"Ch28": {"body": ["Ch28/file9__Ch28_1001_Diffuse.png", ""]},
	"Ch12": {"body": ["Ch12/file10__Ch12_1001_Diffuse.png", ""]},
	"Ch06": {"body": ["Ch06/file1__Ch06_1001_Diffuse.png", ""], "extra": ["Ch06/file9__Ch06_1002_Diffuse.png", ""]},
	"Remy": {
		"body": ["Remy/Remy_Body_Diffuse__Remy_Body_Diffuse.png", ""],
		"lash": ["Remy/Remy_Body_Diffuse__Remy_Body_Diffuse.png", "Remy/Remy_Body_Opacity1__Remy_Body_Opacity.png"],
		"hair": ["Remy/Remy_Hair_Diffuse__Remy_Hair_Diffuse.png", "Remy/Remy_Hair_Opacity__Remy_Hair_Opacity.png"],
		"shoes": ["Remy/Remy_Shoes_Diffuse__Remy_Shoes_Diffuse.png", ""],
		"top": ["Remy/Remy_Top_Diffuse__Remy_Top_Diffuse.png", ""],
		"bottom": ["Remy/Remy_Bottom_Diffuse__Remy_Bottom_Diffuse.png", ""],
	},
}

var A := {}
var out_dir := "/home/claude/westside-mobile/assets/characters/mixamo"
var id := ""
var _tex_cache := {}


func _init() -> void:
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	id = A["id"]
	out_dir = A.get("out", out_dir)
	if A.get("phase", "mesh") == "tex":
		for k in TEX[id]:
			_texture(k)
	else:
		_run()
	quit()


## Elige clave de textura y si lleva alpha scissor para una superficie.
func _pick(mesh_name: String, surf: int) -> Array:
	var n := mesh_name.to_lower()
	var hairish := n.contains("hair") or n.contains("eyelash")
	match id:
		"Ch07", "Ch22":
			return ["hair", true] if hairish else ["body", false]
		"Ch28":
			return ["body", hairish]
		"Ch12":
			return ["body", surf == 1]
		"Ch06":
			return [["body", false], ["body", true], ["extra", false]][surf]
		"Remy":
			if n == "shoes": return ["shoes", false]
			if n == "tops": return ["top", false]
			if n == "bottoms": return ["bottom", false]
			if n == "hair": return ["hair", true]
			if n == "eyelashes": return ["lash", true]
			return ["body", false]
	return ["body", false]


func _tex_path(key: String) -> String:
	return "res://assets/characters/mixamo/tex/%s_%s.webp" % [id.to_lower(), key]


func _texture(key: String) -> String:
	var tag := "%s_%s" % [id, key]
	if _tex_cache.has(tag):
		return _tex_cache[tag]
	var pair: Array = TEX[id][key]
	var img := Image.load_from_file("%s/%s" % [SRC, pair[0]])
	assert(img != null)
	img.convert(Image.FORMAT_RGBA8)
	if pair[1] != "":
		var op := Image.load_from_file("%s/%s" % [SRC, pair[1]])
		op.convert(Image.FORMAT_L8)
		if op.get_size() != img.get_size():
			op.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_LANCZOS)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				c.a = op.get_pixel(x, y).r
				img.set_pixel(x, y, c)
	var m := maxi(img.get_width(), img.get_height())
	if m > TEX_MAX:
		var k := float(TEX_MAX) / float(m)
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	# Sin canal alfa útil -> opaco (evita transparencias rotas)
	var has_alpha := false
	var amin := 1.0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			amin = minf(amin, img.get_pixel(x, y).a)
	has_alpha = amin < 0.99
	var path := "%s/tex/%s.webp" % [out_dir, tag.to_lower()]
	print("textura ", path, " ", img.get_size(), " alpha=", has_alpha)
	if not has_alpha:
		img.convert(Image.FORMAT_RGB8)
	img.save_webp(path, true, 0.9)
	_tex_cache[tag] = _tex_path(key)
	return _tex_cache[tag]


func _decimate(arr: Array, target_tris: int) -> PackedInt32Array:
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if I.size() / 3 <= target_tris:
		return I
	var f := FileAccess.open("/tmp/claude-0/dec_in.bin", FileAccess.WRITE)
	f.store_32(V.size()); f.store_32(I.size())
	var b := PackedFloat32Array()
	for v in V: b.append(v.x); b.append(v.y); b.append(v.z)
	f.store_buffer(b.to_byte_array())
	b = PackedFloat32Array()
	for v in N: b.append(v.x); b.append(v.y); b.append(v.z)
	f.store_buffer(b.to_byte_array())
	b = PackedFloat32Array()
	for v in UV: b.append(v.x); b.append(v.y)
	f.store_buffer(b.to_byte_array())
	f.store_buffer(I.to_byte_array())
	f.close()
	var o := []
	OS.execute("python3", ["-I", "res://tools/decimate.py".replace("res://", ProjectSettings.globalize_path("res://")), "/tmp/claude-0/dec_in.bin", "/tmp/claude-0/dec_out.bin", str(target_tris)], o)
	print("   ", String(o[0]).strip_edges())
	var g := FileAccess.open("/tmp/claude-0/dec_out.bin", FileAccess.READ)
	var n := g.get_32()
	return g.get_buffer(n * 4).to_int32_array()


## Compacta vértices usados, reduce a 4 pesos, descarta tangentes/colores.
func _build_surface(arr: Array, idx: PackedInt32Array, us: float) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var newi := PackedInt32Array()
	newi.resize(idx.size())
	for k in idx.size():
		var o := idx[k]
		if not remap.has(o):
			remap[o] = order.size()
			order.append(o)
		newi[k] = remap[o]
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := B.size() / V.size()
	var nV := PackedVector3Array(); var nN := PackedVector3Array(); var nUV := PackedVector2Array()
	var nB := PackedInt32Array(); var nW := PackedFloat32Array()
	for o in order:
		nV.append(V[o] * us); nN.append(N[o]); nUV.append(UV[o])
		var pairs := []
		for j in per:
			pairs.append([W[o * per + j], B[o * per + j]])
		pairs.sort_custom(func(a, b): return a[0] > b[0])
		var tot := 0.0
		for j in 4: tot += pairs[j][0]
		for j in 4:
			nB.append(pairs[j][1])
			nW.append(pairs[j][0] / tot if tot > 0.0 else (1.0 if j == 0 else 0.0))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nV; out[Mesh.ARRAY_NORMAL] = nN; out[Mesh.ARRAY_TEX_UV] = nUV
	out[Mesh.ARRAY_BONES] = nB; out[Mesh.ARRAY_WEIGHTS] = nW; out[Mesh.ARRAY_INDEX] = newi
	return out


func _run() -> void:
	var root: Node3D = (load("res://in/%s.fbx" % id) as PackedScene).instantiate()
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	var rx := RegEx.create_from_string("^mixamorig\\d*_")
	for i in sk.get_bone_count():
		sk.set_bone_name(i, rx.sub(sk.get_bone_name(i), "mixamorig_"))
	var hips_y := sk.get_bone_global_rest(sk.find_bone("mixamorig_Hips")).origin.y
	var s := 1.0 / hips_y
	# Normaliza unidades EN LOS DATOS (huesos, mallas, enlaces de piel) para que la cadera mida 1,0 m
	# y las pistas de posición de Hips de la librería valgan para todos (Remy viene x2,1).
	for i in sk.get_bone_count():
		var rt := sk.get_bone_rest(i)
		rt.origin *= s
		sk.set_bone_rest(i, rt)
	sk.reset_bone_poses()
	var head_y := sk.get_bone_global_rest(sk.find_bone("mixamorig_HeadTop_End")).origin.y
	var fit := clampf(float(HEIGHT.get(id, 1.78)) / head_y, 0.92, 1.06)
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap); ap.free()
	root.name = "Model"
	root.scale = Vector3.ONE * fit
	root.set_meta("hips_y", hips_y)
	root.set_meta("head_y", head_y * fit)
	var meshes: Array = sk.find_children("*", "MeshInstance3D", true, false)
	var total := 0
	var small := 0
	for mi in meshes:
		for k in (mi as MeshInstance3D).mesh.get_surface_count():
			var t := ((mi as MeshInstance3D).mesh.surface_get_arrays(k)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			total += t
			if t < 1500: small += t
	var big := total - small
	var r := minf(1.0, float(TRI_BUDGET - small) / float(maxi(big, 1)))
	print("== ", id, " tris=", total, " factor=", r, " hips_y=", hips_y, " unidades x", s, " altura=", head_y * fit, " fit=", fit)
	var final_tris := 0
	# Fusiona todas las superficies en UNA malla con una superficie por grupo (textura, alpha, tinte)
	var groups := {}      # clave -> {arrays...}
	var group_order := []
	var merged_binds := PackedStringArray()
	var merged_poses := []
	for mi: MeshInstance3D in meshes:
		var lname := String(mi.name).to_lower()
		var tint := false
		for key in ["shirt", "pants", "suit", "hoody", "tops", "bottoms"]:
			if lname.contains(key): tint = true
		# remapeo de índices de hueso de este Skin al Skin fusionado
		var remap := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bn := rx.sub(mi.skin.get_bind_name(b), "mixamorig_")
			var at := merged_binds.find(bn)
			if at < 0:
				merged_binds.append(bn)
				var bp: Transform3D = mi.skin.get_bind_pose(b)
				bp.origin *= s
				merged_poses.append(bp)
				at = merged_binds.size() - 1
			remap.append(at)
		for k in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(k)
			var t: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var target := t if t < 1500 else int(t * r)
			print("  ", mi.name, " surf", k, " ", t, " -> ", target)
			var idx := _decimate(arr, target)
			var sa := _build_surface(arr, idx, s)
			var bb: PackedInt32Array = sa[Mesh.ARRAY_BONES]
			for q in bb.size():
				bb[q] = remap[bb[q]]
			sa[Mesh.ARRAY_BONES] = bb
			final_tris += idx.size() / 3
			var pk := _pick(String(mi.name), k)
			var gk := "%s|%s|%s" % [pk[0], pk[1], tint]
			if not groups.has(gk):
				groups[gk] = {"tex": pk[0], "alpha": pk[1], "tint": tint, "arrs": []}
				group_order.append(gk)
			groups[gk]["arrs"].append(sa)
	var am := ArrayMesh.new()
	var cloth_surfaces := []
	for gk in group_order:
		var g: Dictionary = groups[gk]
		var V := PackedVector3Array(); var N := PackedVector3Array(); var UV := PackedVector2Array()
		var B := PackedInt32Array(); var W := PackedFloat32Array(); var I := PackedInt32Array()
		for sa in g["arrs"]:
			var off := V.size()
			V.append_array(sa[Mesh.ARRAY_VERTEX]); N.append_array(sa[Mesh.ARRAY_NORMAL]); UV.append_array(sa[Mesh.ARRAY_TEX_UV])
			B.append_array(sa[Mesh.ARRAY_BONES]); W.append_array(sa[Mesh.ARRAY_WEIGHTS])
			for ix in sa[Mesh.ARRAY_INDEX]: I.append(ix + off)
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = V; arrs[Mesh.ARRAY_NORMAL] = N; arrs[Mesh.ARRAY_TEX_UV] = UV
		arrs[Mesh.ARRAY_BONES] = B; arrs[Mesh.ARRAY_WEIGHTS] = W; arrs[Mesh.ARRAY_INDEX] = I
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		var m := StandardMaterial3D.new()
		m.resource_name = "%s_%s%s" % [id, g["tex"], "_ropa" if g["tint"] else ""]
		m.albedo_texture = load(_tex_path(g["tex"]))
		m.roughness = 0.88
		m.metallic = 0.0
		m.metallic_specular = 0.25
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if g["alpha"]:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		am.surface_set_material(am.get_surface_count() - 1, m)
		if g["tint"]: cloth_surfaces.append(am.get_surface_count() - 1)
		print("  superficie ", am.get_surface_count() - 1, " ", gk, " tris=", I.size() / 3)
	var skin := Skin.new()
	for b in merged_binds.size():
		skin.add_named_bind(merged_binds[b], merged_poses[b])
	for mi: MeshInstance3D in meshes:
		sk.remove_child(mi)
		mi.free()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = am
	body.skin = skin
	sk.add_child(body)
	body.skeleton = NodePath("..")
	body.set_meta("cloth_surfaces", cloth_surfaces)
	meshes = [body]
	print("== ", id, " triángulos finales: ", final_tris)
	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "%s/%s.scn" % [out_dir, id.to_lower()]
	ResourceSaver.save(ps, path)
	print("guardado ", path, " ", FileAccess.get_file_as_bytes(path).size(), " bytes")


func _set_owner(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_set_owner(c, o)
