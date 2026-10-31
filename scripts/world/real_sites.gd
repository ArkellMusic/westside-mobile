class_name RealSites
extends Node3D
## Edificios, vehículos y personajes de las descargas de Sketchfab (ver assets/CREDITOS.md),
## preparados con tools/bake_asset.gd (<= 150k triángulos por edificio, texturas de 1K):
##   - Westbrook General (hospital) con su helipuerto, ambulancias y un médico.
##   - Cárcel en el desierto (autopista este) con carretera de acceso.
##   - Aparcamiento vallado en una manzana comercial (sustituye edificios de CityBuilder).
##   - Entrada de metro "Estación Westbrook" (el interior lo construye Interiors).
##   - Flota de South Veyra PD delante de la comisaría: patrullas, motos y agentes.
## Todo lleva visibility ranges y colisiones simples para no cargar al móvil.

const BUILDINGS := "res://assets/buildings/"
const GROUND_Y := 0.1            # las manzanas están elevadas 0,10 m

## Hospital: el centro de la huella del modelo (ya girado para que el frente mire a +Z).
const HOSPITAL_POS := Vector3(200.0, -0.28, -138.6)   # la losa del modelo mide 0,4 m: el asfalto queda a 0,12
## Puerta principal del hospital (junto a la cruz roja) y punto de aparición fuera.
const HOSPITAL_DOOR := Vector3(193.9, 0.12, -129.9)
const HOSPITAL_VIS := 420.0
## Cárcel en el desierto, junto a la autopista (z = 0) hacia el este.
const PRISON_POS := Vector3(2000.0, -0.07, 190.0)
## Aparcamiento: centro del solar y giro (grados) en una manzana comercial.
const PARKING_POS := Vector3(-103.2, 0.1, -128.0)

var main
var city: CityBuilder
var interiors
var statics: StaticBody3D
var npcs: Array = []
var _model_cache: Dictionary = {}


func build(p_city: CityBuilder, p_interiors, p_main) -> void:
	city = p_city
	interiors = p_interiors
	main = p_main
	statics = StaticBody3D.new()
	statics.name = "RealSitesCollision"
	add_child(statics)
	_build_hospital()
	_build_prison()
	_build_parking()
	_build_police_fleet()
	_build_helipad()
	_build_subway_kiosk()


func _process(_delta: float) -> void:
	# Los NPC miran al jugador cuando se acercan; el jugador se crea después de Interiors.
	if main and main.player and not npcs.is_empty():
		for n in npcs:
			if is_instance_valid(n) and n.player == null:
				n.player = main.player


# ---------------------------------------------------------------- utilidades

func _scene_mesh(path: String) -> Mesh:
	if not _model_cache.has(path):
		var inst := (load(path) as PackedScene).instantiate()
		var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_model_cache[path] = mi.mesh
		inst.free()
	return _model_cache[path]


func _place(path: String, xf: Transform3D, vis_end: float = 0.0, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _scene_mesh(path)
	mi.transform = xf
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Colisión triangular de la malla sin el suelo (triángulos con todos los vértices por debajo
## de min_y), para que coches y jugador choquen con muros y columnas pero no con la losa.
func _trimesh(mesh: Mesh, xf: Transform3D, min_y: float = 0.35) -> void:
	var faces := PackedVector3Array()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var p0 := v[idx[t]]
			var p1 := v[idx[t + 1]]
			var p2 := v[idx[t + 2]]
			if maxf(p0.y, maxf(p1.y, p2.y)) < min_y:
				continue
			faces.append(p0)
			faces.append(p1)
			faces.append(p2)
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	statics.add_child(cs)


func _box(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	statics.add_child(cs)


func _mat(color: Color, rough: float = 0.7, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _car_static(style: int, color: Color, pos: Vector3, yaw: float, vis_end: float = 140.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CarModel.build(style, color, true)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	mi.visibility_range_end = vis_end
	mi.visibility_range_end_margin = 10.0
	add_child(mi)
	var spec := CarModel.spec(style)
	var hw: float = spec["half_w"]
	var l: float = spec["length"]
	var h: float = spec["height"]
	# yaw = 0: el frente mira a +Z (cuerpo largo en Z); yaw = PI/2 lo gira hacia +X.
	_box(pos + Vector3(0, h * 0.5 + 0.1, 0), Vector3(hw * 2.0, h - 0.2, l), yaw)
	return mi


func _npc(id: String, pos: Vector3, face_to: Vector3, stance: String = "") -> NPC:
	var n := NPC.new()
	add_child(n)
	n.setup(id, stance)
	n.global_position = pos
	n.face(face_to)
	npcs.append(n)
	return n


# ---------------------------------------------------------------- hospital

func _build_hospital() -> void:
	var xf := Transform3D(Basis.IDENTITY, HOSPITAL_POS)
	var mi := _place(BUILDINGS + "hospital/hospital.scn", xf, HOSPITAL_VIS)
	mi.name = "WestbrookGeneral"
	_trimesh(mi.mesh, xf, 0.55)
	city.footprints.append(Rect2(HOSPITAL_POS.x - 31.3, HOSPITAL_POS.z - 27.6, 62.6, 36.6))
	var sign_pos := HOSPITAL_POS + Vector3(-6.0, 0.3, 9.4)
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 1.0, 1.0)
	l.light_energy = 1.2
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = Vector3(HOSPITAL_DOOR.x, 3.0, HOSPITAL_DOOR.z + 1.5)
	add_child(l)
	# Ambulancia aparcada junto a la entrada de urgencias y un médico en la puerta.
	_car_static(6, Color.WHITE, Vector3(208.0, 0.12, -125.6), PI * 0.5, 150.0)
	_npc("doctor_pinch", Vector3(HOSPITAL_DOOR.x + 2.8, 0.12, HOSPITAL_DOOR.z + 1.6), Vector3(HOSPITAL_DOOR.x + 6.0, 0.0, HOSPITAL_DOOR.z + 14.0))
	var label := Label3D.new()
	label.text = "URGENCIAS"
	label.visible = false  # Nombres de edificios solo en el mapa/radar.
	label.font_size = 90
	label.pixel_size = 0.009
	label.modulate = Color(0.85, 0.05, 0.08)
	label.outline_size = 8
	label.outline_modulate = Color(1, 1, 1, 0.9)
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.position = Vector3(208.0, 0.16, -121.2)
	add_child(label)


## Helipuerto detrás del hospital con el MD-500 (decorado, sin física).
func _build_helipad() -> void:
	var c := Vector3(200.0, 0.1, -178.5)
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 9.0
	cyl.bottom_radius = 9.0
	cyl.height = 0.06
	cyl.radial_segments = 40
	cyl.rings = 1
	cyl.material = _mat(Color(0.2, 0.21, 0.23), 0.85)
	pad.mesh = cyl
	pad.position = c + Vector3(0, 0.03, 0)
	add_child(pad)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 8.2
	tor.outer_radius = 8.7
	tor.rings = 40
	tor.ring_segments = 3
	tor.material = _mat(Color(0.95, 0.8, 0.15), 0.6)
	ring.mesh = tor
	ring.scale = Vector3(1, 0.04, 1)
	ring.position = c + Vector3(0, 0.07, 0)
	add_child(ring)
	var h := Label3D.new()
	h.text = "H"
	h.font_size = 420
	h.pixel_size = 0.012
	h.modulate = Color(0.95, 0.95, 0.95)
	h.rotation_degrees = Vector3(-90, 0, 0)
	h.position = c + Vector3(0, 0.1, 0)
	add_child(h)
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), c + Vector3(0, 0.09, 0))
	var heli := _place("res://assets/vehicles/heli/heli.scn", xf, 220.0)
	heli.name = "HelicopteroPolicia"
	_box(c + Vector3(0, 1.4, 0), Vector3(3.2, 2.8, 8.0), deg_to_rad(-25.0))


# ---------------------------------------------------------------- cárcel

## Cárcel estatal en el desierto al sureste de la autopista, con la puerta mirando al norte
## (hacia la carretera de acceso). Colisiones simples: muros, edificio y torres.
func _build_prison() -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI), PRISON_POS)
	var mi := _place(BUILDINGS + "prison/prison.scn", xf, 900.0)
	mi.name = "CarcelEstatal"
	var l2w := func(v: Vector3) -> Vector3: return xf * v
	for sz in [-1.0, 1.0]:
		_box(l2w.call(Vector3(0.3, 3.0, sz * 28.9 - 0.6)), Vector3(77.6, 6.0, 1.2), PI)
	for sx in [-1.0, 1.0]:
		_box(l2w.call(Vector3(sx * 38.5 + 0.3, 3.0, -0.6)), Vector3(1.2, 6.0, 58.0), PI)
		for sz in [-1.0, 1.0]:
			_box(l2w.call(Vector3(sx * 36.5, 5.8, sz * 26.8)), Vector3(6.5, 11.7, 6.5), PI)
	_box(l2w.call(Vector3(-1.3, 8.5, -15.9)), Vector3(52.3, 17.0, 13.1), PI)
	# Carretera de acceso: desde el arcén de la autopista hasta la puerta.
	var gate_z := PRISON_POS.z - 28.2
	var b := MeshBuilder.new()
	b.surface("road", city.mat_road)
	city._road_piece_z(b, PRISON_POS.x, 9.0, 8.0, gate_z - 1.0, 0.05)
	city._road_piece_z(b, PRISON_POS.x, 22.0, gate_z - 14.0, gate_z - 1.0, 0.05)
	var road := MeshInstance3D.new()
	road.mesh = b.commit()
	road.name = "CarreteraCarcel"
	add_child(road)
	var sign_post := _label_sign("CÁRCEL ESTATAL DE VEYRA", Vector3(PRISON_POS.x + 7.5, 0.0, 12.0), -90.0)
	var sign2 := _label_sign("CÁRCEL ESTATAL DE VEYRA", Vector3(PRISON_POS.x + 7.5, 0.0, gate_z - 8.0), -90.0)
	if sign_post == null or sign2 == null:
		pass


## Cartel de carretera: poste y panel con texto en ambas caras.
func _label_sign(text: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	var post_m := _mat(Color(0.3, 0.3, 0.32), 0.6, 0.6)
	var panel_m := _mat(Color(0.05, 0.3, 0.14), 0.6)
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 3.4, 0.2)
	bm.material = post_m
	post.mesh = bm
	post.position = Vector3(0, 1.7, 0)
	n.add_child(post)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 1.3, 4.2)
	pm.material = panel_m
	panel.mesh = pm
	panel.position = Vector3(0, 3.6, 0)
	n.add_child(panel)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = text
		l.visible = false  # Nombres de edificios solo en el mapa/radar.
		l.font_size = 64
		l.pixel_size = 0.0058
		l.modulate = Color(0.95, 0.95, 0.95)
		l.outline_size = 0
		l.position = Vector3(side * 0.07, 3.6, 0)
		l.rotation_degrees.y = 90.0 * side
		n.add_child(l)
	add_child(n)
	_box(pos + Vector3(0, 1.7, 0), Vector3(0.3, 3.4, 0.3))
	return n


# ---------------------------------------------------------------- aparcamiento

## Aparcamiento vallado con garita en el solar de la manzana comercial del oeste
## (CityBuilder.REPLACED_SITES retira el edificio que había). La puerta mira a Kingsley St.
func _build_parking() -> void:
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), PARKING_POS)
	var mi := _place(BUILDINGS + "parking/parking.scn", xf, 260.0)
	mi.name = "AparcamientoWestbrook"
	var w := func(v: Vector3) -> Vector3: return xf * v
	# Vallado (lado de la puerta, +X local, con un hueco de 7 m).
	for sz in [-1.0, 1.0]:
		_box(w.call(Vector3(0.0, 1.2, sz * 8.6)), Vector3(35.8, 2.4, 0.2), -PI * 0.5)
	_box(w.call(Vector3(-17.9, 1.2, 0.0)), Vector3(0.2, 2.4, 17.2), -PI * 0.5)
	_box(w.call(Vector3(17.7, 1.2, -6.5)), Vector3(0.3, 2.4, 4.4), -PI * 0.5)
	_box(w.call(Vector3(17.7, 1.2, 5.3)), Vector3(0.3, 2.4, 6.6), -PI * 0.5)
	city.footprints.append(Rect2(PARKING_POS.x - 8.7, PARKING_POS.z - 18.0, 17.4, 36.0))
	# Coches aparcados dentro (los que tienen modelo real).
	var spots := [[Vector3(-12.5, 0.0, -5.0), 4, Color(0.78, 0.45, 0.1)], [Vector3(-8.2, 0.0, -5.0), 1, Color(0.1, 0.12, 0.3)],
		[Vector3(-3.4, 0.0, 5.0), 0, Color(0.7, 0.7, 0.72)], [Vector3(2.8, 0.0, -5.0), 3, Color(0.55, 0.06, 0.07)]]
	for sp in spots:
		var local: Vector3 = sp[0]
		var yaw_local := 0.0 if local.z < 0.0 else PI
		var pos: Vector3 = w.call(local)
		_car_static(int(sp[1]), sp[2], pos, -PI * 0.5 + yaw_local, 120.0)


# ---------------------------------------------------------------- comisaría

## Flota de South Veyra PD delante de la comisaría: dos patrullas, dos motos y tres agentes.
func _build_police_fleet() -> void:
	_car_static(5, Color.WHITE, Vector3(116.4, 0.12, -108.3), PI * 0.5, 150.0)
	_car_static(5, Color.WHITE, Vector3(128.2, 0.12, -108.3), PI * 0.5, 150.0)
	for x in [109.6, 134.9]:
		var xf := Transform3D(Basis(Vector3.UP, 0.0 if x < 120.0 else PI), Vector3(x, 0.12, -108.6))
		var mi := _place("res://assets/vehicles/harley/harley.scn", xf, 120.0)
		mi.name = "MotoPolicia"
		_box(xf.origin + Vector3(0, 0.65, 0), Vector3(2.3, 1.3, 0.8))
	var face := Vector3(122.25, 0.0, -90.0)
	_npc("cop_reyes", Vector3(119.8, 0.12, -106.8), face, "arms_crossed")
	_npc("cop_park", Vector3(124.9, 0.12, -106.6), face, "hands_together")
	_npc("cop_guard", Vector3(131.8, 0.12, -106.7), face)


# ---------------------------------------------------------------- metro

## Boca de metro en la acera oeste: escalera hundida, barandillas y letrero. Interiors
## ofrece "Entrar" en este punto y construye el interior "Estación Westbrook".
func _build_subway_kiosk() -> void:
	var c := Vector3(-59.0, 0.1, -20.0)
	var rail := _mat(Color(0.1, 0.35, 0.3), 0.5, 0.5)
	var dark := _mat(Color(0.02, 0.02, 0.03), 1.0)
	var pit := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(3.4, 0.05, 3.0)
	pm.material = dark
	pit.mesh = pm
	pit.position = c + Vector3(0, 0.03, 0)
	add_child(pit)
	for sx in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 1.0, 3.0)
		bm.material = rail
		r.mesh = bm
		r.position = c + Vector3(sx * 1.7, 0.6, 0)
		add_child(r)
		_box(c + Vector3(sx * 1.7, 0.6, 0), Vector3(0.2, 1.2, 3.0))
	var back := MeshInstance3D.new()
	var bk := BoxMesh.new()
	bk.size = Vector3(3.4, 1.0, 0.08)
	bk.material = rail
	back.mesh = bk
	back.position = c + Vector3(0, 0.6, -1.5)
	add_child(back)
	_box(c + Vector3(0, 0.6, -1.5), Vector3(3.4, 1.2, 0.2))
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.14, 3.0, 0.14)
		pb.material = rail
		post.mesh = pb
		post.position = c + Vector3(sx * 1.7, 1.5, 1.4)
		add_child(post)
	var sign_box := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(3.6, 0.7, 0.12)
	sb.material = _mat(Color(0.05, 0.4, 0.3), 0.5, 0.0, Color(0.1, 0.7, 0.5), 0.8)
	sign_box.mesh = sb
	sign_box.position = c + Vector3(0, 3.1, 1.4)
	add_child(sign_box)
	var t := Label3D.new()
	t.text = "METRO"
	t.visible = false  # Nombres de edificios solo en el mapa/radar.
	t.font_size = 96
	t.pixel_size = 0.0065
	t.modulate = Color(1, 1, 1)
	t.position = c + Vector3(0, 3.1, 1.47)
	add_child(t)
	var t2 := Label3D.new()
	t2.text = "METRO"
	t2.visible = false
	t2.font_size = 96
	t2.pixel_size = 0.0065
	t2.modulate = Color(1, 1, 1)
	t2.rotation_degrees.y = 180
	t2.position = c + Vector3(0, 3.1, 1.33)
	add_child(t2)
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 1.0, 0.85)
	l.light_energy = 1.0
	l.omni_range = 6.0
	l.shadow_enabled = false
	l.position = c + Vector3(0, 2.6, 0.8)
	add_child(l)
