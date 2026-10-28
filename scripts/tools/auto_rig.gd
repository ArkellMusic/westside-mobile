extends SceneTree
## Monta un esqueleto humanoide automático en modelos sin rig en pose T (Meshy).
## Normaliza el modelo (metros, mirando a -Z, pies en y=0), calcula pesos de piel
## por regiones con mezcla suave en las articulaciones y guarda una escena lista
## para animar: res://assets/characters/<id>/<id>_rigged.scn
##
## Uso: godot --headless --path . -s res://scripts/tools/auto_rig.gd
## (un rig de Mixamo o de Meshy siempre dará mejores deformaciones; esto es el
## puente para que los modelos se muevan ya).

const MODELS := {
	"mack": ["res://assets/characters/streetwear/Meshy_AI_Streetwear_Stance_20261025_texture", 1.83],
	"big_ray": ["res://assets/characters/oakland/Meshy_AI_Arms_of_Oakland_20261025_texture", 1.86],
	"keisha": ["res://assets/characters/urban/Meshy_AI_Urban_Balance_20261025_texture", 1.70],
	"dre": ["res://assets/characters/tpose/Meshy_AI_T_Pose_Urban_Model_20261028_texture", 1.86],
	"loco": ["res://assets/characters/stance2/Meshy_AI_Streetwear_Stance_20261028_texture", 1.78],
	"ghost": ["res://assets/characters/shadow/Meshy_AI_Shadow_Spread_20261028_texture", 1.83],
	"viper": ["res://assets/characters/tatted/Meshy_AI_Tatted_in_Black_20261028_texture", 1.77],
}

const BONES := ["hips", "spine", "chest", "neck", "head",
	"l_upperarm", "l_forearm", "l_hand", "r_upperarm", "r_forearm", "r_hand",
	"l_thigh", "l_shin", "l_foot", "r_thigh", "r_shin", "r_foot"]
const PARENT := {"spine": "hips", "chest": "spine", "neck": "chest", "head": "neck",
	"l_upperarm": "chest", "l_forearm": "l_upperarm", "l_hand": "l_forearm",
	"r_upperarm": "chest", "r_forearm": "r_upperarm", "r_hand": "r_forearm",
	"l_thigh": "hips", "l_shin": "l_thigh", "l_foot": "l_shin",
	"r_thigh": "hips", "r_shin": "r_thigh", "r_foot": "r_shin"}


func _init() -> void:
	for id in MODELS:
		_rig(id, MODELS[id][0], MODELS[id][1])
	quit()


func _rig(id: String, base: String, height: float) -> void:
	var ps: PackedScene = load(base + ".fbx")
	var src := ps.instantiate()
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# 1) Normalizar: transformación de importación + giro de 180º (mirar a -Z) + escala.
	var xf := Basis(Vector3.UP, PI) * mi.transform.basis
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in verts:
		var p := xf * v
		lo = lo.min(p)
		hi = hi.max(p)
	var s := height / (hi.y - lo.y)
	var center := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var out_v := PackedVector3Array()
	out_v.resize(verts.size())
	var out_n := PackedVector3Array()
	out_n.resize(verts.size())
	for i in verts.size():
		out_v[i] = (xf * verts[i] - center) * s
		out_n[i] = (xf * normals[i]).normalized()
	var H := height

	# 2) Puntos de referencia del cuerpo en pose T.
	var span := 0.0
	var arm_y_sum := 0.0
	var arm_n := 0
	for p in out_v:
		span = maxf(span, absf(p.x))
		if absf(p.x) > 0.3 * H and p.y > 0.6 * H:
			arm_y_sum += p.y
			arm_n += 1
	var sh_y := arm_y_sum / maxf(arm_n, 1)
	var leg_x_sum := 0.0
	var leg_n := 0
	for p in out_v:
		if absf(p.y - 0.28 * H) < 0.03 * H and absf(p.x) < 0.2 * H:
			leg_x_sum += absf(p.x)
			leg_n += 1
	var leg_x := leg_x_sum / maxf(leg_n, 1)
	var sh_x := 0.1 * H
	var wrist_x := span - 0.1 * H
	var elbow_x := (sh_x + wrist_x) * 0.5
	var hip_y := 0.52 * H
	var knee_y := 0.285 * H
	var ankle_y := 0.05 * H
	var joints := {
		"hips": Vector3(0, hip_y, 0), "spine": Vector3(0, 0.6 * H, 0), "chest": Vector3(0, 0.7 * H, 0),
		"neck": Vector3(0, 0.83 * H, 0), "head": Vector3(0, 0.875 * H, 0),
		"l_upperarm": Vector3(-sh_x, sh_y, 0), "l_forearm": Vector3(-elbow_x, sh_y, 0), "l_hand": Vector3(-wrist_x, sh_y, 0),
		"r_upperarm": Vector3(sh_x, sh_y, 0), "r_forearm": Vector3(elbow_x, sh_y, 0), "r_hand": Vector3(wrist_x, sh_y, 0),
		"l_thigh": Vector3(-leg_x, hip_y - 0.03 * H, 0), "l_shin": Vector3(-leg_x, knee_y, 0), "l_foot": Vector3(-leg_x, ankle_y, 0),
		"r_thigh": Vector3(leg_x, hip_y - 0.03 * H, 0), "r_shin": Vector3(leg_x, knee_y, 0), "r_foot": Vector3(leg_x, ankle_y, 0),
	}
	print(id, ": altura ", H, " hombros y=", sh_y, " envergadura ", span, " piernas x=", leg_x)

	# 3) Pesos por regiones con mezcla en las articulaciones.
	var bone_idx := {}
	for i in BONES.size():
		bone_idx[BONES[i]] = i
	var w_bones := PackedInt32Array()
	var w_weights := PackedFloat32Array()
	w_bones.resize(verts.size() * 4)
	w_weights.resize(verts.size() * 4)
	var band := 0.035 * H
	for i in out_v.size():
		var p := out_v[i]
		var ax := absf(p.x)
		var side := "l_" if p.x < 0.0 else "r_"
		var pair: Array
		if ax > sh_x * 1.05 and p.y > sh_y - 0.13 * H:
			# Brazo: hombro -> codo -> muñeca a lo largo de X.
			if ax < (sh_x + elbow_x) * 0.5:
				pair = _blend("chest", side + "upperarm", ax, sh_x * 1.05, sh_x * 1.05 + band * 2.0)
			elif ax < (elbow_x + wrist_x) * 0.5:
				pair = _blend(side + "upperarm", side + "forearm", ax, elbow_x - band, elbow_x + band)
			else:
				pair = _blend(side + "forearm", side + "hand", ax, wrist_x - band, wrist_x + band)
		elif p.y < hip_y - 0.02 * H and ax > 0.005 * H:
			# Pierna: cadera -> rodilla -> tobillo a lo largo de -Y.
			if p.y > (hip_y + knee_y) * 0.5:
				pair = _blend(side + "thigh", "hips", p.y, hip_y - 0.12 * H, hip_y - 0.02 * H)
			elif p.y > (knee_y + ankle_y) * 0.5:
				pair = _blend(side + "shin", side + "thigh", p.y, knee_y - band, knee_y + band)
			else:
				pair = _blend(side + "foot", side + "shin", p.y, ankle_y - band * 0.6, ankle_y + band * 0.6)
		else:
			# Tronco y cabeza.
			if p.y < 0.6 * H:
				pair = _blend("hips", "spine", p.y, 0.6 * H - band, 0.6 * H + band)
			elif p.y < 0.7 * H:
				pair = _blend("spine", "chest", p.y, 0.7 * H - band, 0.7 * H + band)
			elif p.y < 0.83 * H:
				pair = _blend("chest", "neck", p.y, 0.83 * H - band, 0.83 * H + band)
			else:
				pair = _blend("neck", "head", p.y, 0.86 * H - band * 0.5, 0.86 * H + band * 0.5)
		w_bones[i * 4] = bone_idx[pair[0]]
		w_bones[i * 4 + 1] = bone_idx[pair[1]]
		w_bones[i * 4 + 2] = 0
		w_bones[i * 4 + 3] = 0
		w_weights[i * 4] = pair[2]
		w_weights[i * 4 + 1] = 1.0 - float(pair[2])
		w_weights[i * 4 + 2] = 0.0
		w_weights[i * 4 + 3] = 0.0

	# 4) Malla con piel.
	var new_arrays := []
	new_arrays.resize(Mesh.ARRAY_MAX)
	new_arrays[Mesh.ARRAY_VERTEX] = out_v
	new_arrays[Mesh.ARRAY_NORMAL] = out_n
	new_arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	new_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	new_arrays[Mesh.ARRAY_BONES] = w_bones
	new_arrays[Mesh.ARRAY_WEIGHTS] = w_weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(base + ".png")
	mat.normal_enabled = true
	mat.normal_texture = load(base + "_normal.png")
	mat.metallic_texture = load(base + "_metallic.png")
	mat.metallic = 1.0
	if ResourceLoader.exists(base + "_roughness.png"):
		mat.roughness_texture = load(base + "_roughness.png")
		mat.roughness = 1.0
	else:
		mat.roughness = 0.75
	mesh.surface_set_material(0, mat)

	# 5) Esqueleto y bind poses.
	var root := Node3D.new()
	root.name = id
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	skel.owner = root
	var skin := Skin.new()
	for b in BONES:
		skel.add_bone(b)
	for b in BONES:
		var bi: int = bone_idx[b]
		var parent_pos := Vector3.ZERO
		if PARENT.has(b):
			skel.set_bone_parent(bi, bone_idx[PARENT[b]])
			parent_pos = joints[PARENT[b]]
		skel.set_bone_rest(bi, Transform3D(Basis.IDENTITY, joints[b] - parent_pos))
		skin.add_bind(bi, Transform3D(Basis.IDENTITY, -joints[b]))
	skel.reset_bone_poses()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skin = skin
	skel.add_child(body)
	body.owner = root
	body.skeleton = NodePath("..")
	var packed := PackedScene.new()
	packed.pack(root)
	var out := base.get_base_dir() + "/" + id + "_rigged.scn"
	var err := ResourceSaver.save(packed, out)
	print("  guardado ", out, " err=", err, " vértices=", out_v.size())
	src.free()
	root.free()


## [hueso_a, hueso_b, peso_a]: mezcla lineal suave de a (en lo) a b (en hi).
func _blend(a: String, b: String, value: float, lo: float, hi: float) -> Array:
	var t := clampf((value - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return [a, b, 1.0 - t]
