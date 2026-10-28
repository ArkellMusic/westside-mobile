class_name CityBuilder
extends Node3D
## Genera Westbrook (South Veyra) a partir de CityLayout: suelo, calles, aceras,
## casas con jardín y piscina, comercios, playa, muelle, palmeras, farolas, coches
## aparcados, el skyline del centro y las montañas del fondo.
## Pensado para móvil: casi todo va en MultiMesh o en mallas fusionadas, y las
## colisiones son cajas simples.

const SEED := 20261028

var rng := RandomNumberGenerator.new()
var footprints: Array = []   # Rect2 de cada edificio jugable (mapa y radar)
var pools: Array = []        # Rect2 de piscinas (mapa)
var parked_spots: Array = [] # Transform3D de coches aparcados

var _buildings: Array = []   # {center, size, color, kind}
var _skyline: Array = []
var _static: StaticBody3D

var mat_building: ShaderMaterial
var mat_road: ShaderMaterial
var mat_lawn: ShaderMaterial
var mat_concrete: ShaderMaterial
var mat_sidewalk: ShaderMaterial
var mat_sand: ShaderMaterial
var mat_dirt: ShaderMaterial
var mat_water: ShaderMaterial
var lamp_material: StandardMaterial3D
var lamp_positions := PackedVector3Array()   # cabeza de cada farola (mundo)

const HOUSE_COLORS := [Color(0.93, 0.86, 0.72), Color(0.95, 0.78, 0.64), Color(0.72, 0.84, 0.88), Color(0.78, 0.88, 0.76), Color(0.97, 0.94, 0.86), Color(0.92, 0.70, 0.62), Color(0.84, 0.82, 0.80), Color(0.98, 0.89, 0.62)]
const SHOP_COLORS := [Color(0.62, 0.36, 0.28), Color(0.70, 0.68, 0.64), Color(0.86, 0.80, 0.68), Color(0.92, 0.91, 0.88), Color(0.45, 0.55, 0.58), Color(0.78, 0.55, 0.40), Color(0.55, 0.52, 0.50)]
const TOWER_COLORS := [Color(0.45, 0.55, 0.65), Color(0.70, 0.72, 0.75), Color(0.82, 0.76, 0.66), Color(0.35, 0.42, 0.50), Color(0.88, 0.88, 0.86)]
const CAR_COLORS := [Color(0.75, 0.08, 0.08), Color(0.08, 0.12, 0.30), Color(0.92, 0.92, 0.92), Color(0.08, 0.08, 0.08), Color(0.55, 0.56, 0.58), Color(0.15, 0.35, 0.22), Color(0.85, 0.65, 0.15), Color(0.35, 0.55, 0.75)]


func build() -> void:
	rng.seed = SEED
	_make_materials()
	_static = StaticBody3D.new()
	_static.name = "CityCollision"
	add_child(_static)
	_build_ground()
	_build_blocks_and_sidewalks()
	_build_roads()
	_build_residential_and_shops()
	_build_mack_house()
	_build_garage()
	_build_terminal()
	_build_veyra_mart()
	_flush_buildings()
	_build_beach_and_ocean()
	_build_pier()
	_build_vegetation()
	_build_street_lamps()
	_build_parked_cars()
	_build_river_and_bridge()
	_build_desert()
	_build_skyline()
	_build_mountains()
	_build_bounds()


# ---------------------------------------------------------------- materiales

func _make_materials() -> void:
	mat_building = ShaderMaterial.new()
	mat_building.shader = load("res://assets/shaders/building.gdshader")
	mat_road = ShaderMaterial.new()
	mat_road.shader = load("res://assets/shaders/road.gdshader")
	var ground_shader: Shader = load("res://assets/shaders/ground.gdshader")
	mat_lawn = _ground_mat(ground_shader, 0)
	mat_concrete = _ground_mat(ground_shader, 1)
	mat_sidewalk = _ground_mat(ground_shader, 2)
	mat_sand = _ground_mat(ground_shader, 3)
	mat_dirt = _ground_mat(ground_shader, 4)
	_texture_ground(mat_lawn, "grass", 3.0)
	mat_lawn.set_shader_parameter("tint", Color(1.55, 1.6, 1.25))
	_texture_ground(mat_concrete, "concrete", 4.0)
	_texture_ground(mat_sidewalk, "sidewalk", 2.4)
	_texture_ground(mat_sand, "sand", 14.0)
	_texture_ground(mat_dirt, "dirt", 7.0)
	if ResourceLoader.exists(TEX + "asphalt/albedo.jpg"):
		mat_road.set_shader_parameter("asphalt_albedo", load(TEX + "asphalt/albedo.jpg"))
		mat_road.set_shader_parameter("asphalt_normal", load(TEX + "asphalt/normal.jpg"))
		mat_road.set_shader_parameter("asphalt_rough", load(TEX + "asphalt/roughness.jpg"))
	for pair in [["house", "stucco"], ["shop", "brick"], ["tower", "concrete_wall"], ["roof", "roof"]]:
		if ResourceLoader.exists(TEX + pair[1] + "/albedo.jpg"):
			mat_building.set_shader_parameter(pair[0] + "_albedo", load(TEX + pair[1] + "/albedo.jpg"))
			mat_building.set_shader_parameter(pair[0] + "_normal", load(TEX + pair[1] + "/normal.jpg"))
	mat_water = ShaderMaterial.new()
	mat_water.shader = load("res://assets/shaders/water.gdshader")
	mat_water.set_shader_parameter("shore_x", CityLayout.SHORE_X)


const TEX := "res://assets/textures/"


func _texture_ground(m: ShaderMaterial, id: String, tile: float) -> void:
	if not ResourceLoader.exists(TEX + id + "/albedo.jpg"):
		return
	m.set_shader_parameter("use_texture", true)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("tex_albedo", load(TEX + id + "/albedo.jpg"))
	m.set_shader_parameter("tex_normal", load(TEX + id + "/normal.jpg"))
	m.set_shader_parameter("tex_rough", load(TEX + id + "/roughness.jpg"))


func _ground_mat(shader: Shader, surface: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("surface", surface)
	return m


func set_night(amount: float) -> void:
	mat_building.set_shader_parameter("night", amount)
	if lamp_material:
		lamp_material.emission_energy_multiplier = clampf((amount - 0.15) / 0.6, 0.0, 1.0) * 6.0


# ---------------------------------------------------------------- utilidades

func _mesh_instance(mesh: Mesh, node_name: String, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _collider_box(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	_static.add_child(cs)


func _flat_quad(b: MeshBuilder, key: String, r: Rect2, y: float) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	b.quad(key, a, Vector3(c.x, y, a.z), c, Vector3(a.x, y, c.z), Vector3.UP, Color.WHITE, r.size)


# ---------------------------------------------------------------- suelo

func _build_ground() -> void:
	var b := MeshBuilder.new()
	b.surface("dirt", mat_dirt)
	_flat_quad(b, "dirt", Rect2(CityLayout.BEACH_EAST, -3000, CityLayout.RIVER_X0 - CityLayout.BEACH_EAST, 6000), -0.02)
	_flat_quad(b, "dirt", Rect2(CityLayout.RIVER_X1, -3000, 4600, 6000), -0.02)
	_mesh_instance(b.commit(), "Ground", false)
	# Colisión del terreno firme (la playa tiene la suya propia).
	_collider_box(Vector3(CityLayout.BEACH_EAST + 1900.0, -0.5, 0), Vector3(3800, 1.0, 6000))


func _build_blocks_and_sidewalks() -> void:
	var b := MeshBuilder.new()
	b.surface("lawn", mat_lawn).surface("concrete", mat_concrete).surface("walk", mat_sidewalk)
	for blk in CityLayout.blocks():
		var r: Rect2 = blk["rect"]
		var inner := r.grow(-CityLayout.SIDEWALK)
		var key := "lawn" if blk["kind"] == "residential" else "concrete"
		_flat_quad(b, key, inner, 0.10)
		# Acera en anillo alrededor de la manzana.
		var y := 0.12
		_flat_quad(b, "walk", Rect2(r.position.x, r.position.y, r.size.x, CityLayout.SIDEWALK), y)
		_flat_quad(b, "walk", Rect2(r.position.x, r.end.y - CityLayout.SIDEWALK, r.size.x, CityLayout.SIDEWALK), y)
		_flat_quad(b, "walk", Rect2(r.position.x, r.position.y + CityLayout.SIDEWALK, CityLayout.SIDEWALK, r.size.y - CityLayout.SIDEWALK * 2.0), y)
		_flat_quad(b, "walk", Rect2(r.end.x - CityLayout.SIDEWALK, r.position.y + CityLayout.SIDEWALK, CityLayout.SIDEWALK, r.size.y - CityLayout.SIDEWALK * 2.0), y)
		# Bordillos.
		var x0 := r.position.x
		var x1 := r.end.x
		var z0 := r.position.y
		var z1 := r.end.y
		b.quad("walk", Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, y, z0), Vector3(x0, y, z0), Vector3.FORWARD)
		b.quad("walk", Vector3(x0, 0.0, z1), Vector3(x1, 0.0, z1), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.BACK)
		b.quad("walk", Vector3(x0, 0.0, z0), Vector3(x0, 0.0, z1), Vector3(x0, y, z1), Vector3(x0, y, z0), Vector3.LEFT)
		b.quad("walk", Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3.RIGHT)
	_mesh_instance(b.commit(), "Blocks", false)


# ---------------------------------------------------------------- calles

func _build_roads() -> void:
	var b := MeshBuilder.new()
	b.surface("road", mat_road)
	var y := 0.03
	var street_zs := CityLayout.street_zs()
	var avenue_xs := CityLayout.avenue_xs()
	var aw := {}
	for a in CityLayout.AVENUES:
		aw[a[0]] = a[1]
	var sw := {}
	for s in CityLayout.STREETS:
		sw[s[0]] = s[1]
	# Avenidas: tramos entre cruces.
	for a in CityLayout.AVENUES:
		var x: float = a[0]
		var w: float = a[1]
		var cuts: Array = [CityLayout.NORTH_EDGE - 30.0]
		for z in street_zs:
			cuts.append(z)
		cuts.append(CityLayout.SOUTH_EDGE + 30.0)
		for i in range(cuts.size() - 1):
			var z0: float = cuts[i] + (float(sw.get(cuts[i], 0.0)) * 0.5)
			var z1: float = cuts[i + 1] - (float(sw.get(cuts[i + 1], 0.0)) * 0.5)
			_road_piece_z(b, x, w, z0, z1, y)
	# Calles: tramos entre avenidas.
	for s in CityLayout.STREETS:
		var z: float = s[0]
		var w: float = s[1]
		for i in range(avenue_xs.size() - 1):
			var x0: float = avenue_xs[i] + float(aw[avenue_xs[i]]) * 0.5
			var x1: float = avenue_xs[i + 1] - float(aw[avenue_xs[i + 1]]) * 0.5
			_road_piece_x(b, z, w, x0, x1, y)
	# Cruces sin marcas.
	for x in avenue_xs:
		for z in street_zs:
			var hw: float = float(aw[x]) * 0.5
			var hz: float = float(sw[z]) * 0.5
			var pts := [Vector3(x - hw, y, z - hz), Vector3(x + hw, y, z - hz), Vector3(x + hw, y, z + hz), Vector3(x - hw, y, z + hz)]
			b.quad_uv2("road", pts, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(10, 0))
	_mesh_instance(b.commit(), "Roads", false)


func _road_piece_z(b: MeshBuilder, x: float, w: float, z0: float, z1: float, y: float) -> void:
	var length := z1 - z0
	var pts := [Vector3(x - w * 0.5, y, z0), Vector3(x + w * 0.5, y, z0), Vector3(x + w * 0.5, y, z1), Vector3(x - w * 0.5, y, z1)]
	b.quad_uv2("road", pts, [Vector2(0, 0), Vector2(1, 0), Vector2(1, length), Vector2(0, length)], Vector2(length, w))


func _road_piece_x(b: MeshBuilder, z: float, w: float, x0: float, x1: float, y: float) -> void:
	var length := x1 - x0
	var pts := [Vector3(x0, y, z + w * 0.5), Vector3(x0, y, z - w * 0.5), Vector3(x1, y, z - w * 0.5), Vector3(x1, y, z + w * 0.5)]
	b.quad_uv2("road", pts, [Vector2(0, 0), Vector2(1, 0), Vector2(1, length), Vector2(0, length)], Vector2(length, w))


# ---------------------------------------------------------------- edificios

func _add_building(center_xz: Vector2, size: Vector3, color: Color, kind: float, collide: bool = true) -> void:
	var center := Vector3(center_xz.x, size.y * 0.5, center_xz.y)
	_buildings.append({"center": center, "size": size, "color": color, "kind": kind})
	footprints.append(Rect2(center_xz.x - size.x * 0.5, center_xz.y - size.z * 0.5, size.x, size.z))
	if collide:
		_collider_box(center, size)


const RESERVED := [
	["mack_house", Vector2(15.0, 13.0)],
	["vargas_garage", Vector2(18.0, 16.0)],
	["terminal", Vector2(36.0, 20.0)],
	["veyra_mart", Vector2(14.0, 12.0)],
]


func _is_reserved(p: Vector2) -> bool:
	for r in RESERVED:
		var c := CityLayout.landmark(r[0])
		var half: Vector2 = r[1]
		if absf(p.x - c.x) < half.x and absf(p.y - c.z) < half.y:
			return true
	return false


func _build_residential_and_shops() -> void:
	for blk in CityLayout.blocks():
		var inner: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK)
		match blk["kind"]:
			"residential":
				_fill_residential(inner)
			"commercial":
				_fill_commercial(inner, blk["row"] <= 1 and blk["col"] >= 3)
			"beach":
				_fill_beachfront(inner)


func _fill_residential(inner: Rect2) -> void:
	var frontage := 17.0
	var count := int(floor(inner.size.x / frontage))
	var margin := (inner.size.x - count * frontage) * 0.5
	for row in 2:
		var facing_north := row == 0
		for i in count:
			var lot_x := inner.position.x + margin + frontage * (i + 0.5)
			var w := rng.randf_range(10.0, 13.0)
			var d := rng.randf_range(9.0, 12.0)
			var setback := rng.randf_range(5.0, 7.0)
			var z := inner.position.y + setback + d * 0.5 if facing_north else inner.end.y - setback - d * 0.5
			var c := Vector2(lot_x + rng.randf_range(-1.0, 1.0), z)
			if _is_reserved(c):
				continue
			var floors := 1 if rng.randf() < 0.55 else 2
			var h := 3.6 if floors == 1 else 6.4
			_add_building(c, Vector3(w, h, d), HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()], 0.15)
			# Garaje anexo de una planta en algunas casas.
			if rng.randf() < 0.45:
				var gx := c.x + (w * 0.5 + 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
				if absf(gx - lot_x) < frontage * 0.5 - 2.5:
					_add_building(Vector2(gx, c.y - (d * 0.5 - 3.0) * (1.0 if facing_north else -1.0)), Vector3(5.0, 3.0, 6.0), HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()], 0.1)
			# Piscina en el patio trasero.
			if rng.randf() < 0.4:
				var pz := c.y + (d * 0.5 + 4.5) * (1.0 if facing_north else -1.0)
				pools.append(Rect2(c.x - 3.0, pz - 2.0, rng.randf_range(5.0, 7.0), 4.0))


func _fill_commercial(inner: Rect2, taller: bool) -> void:
	var max_floors := 8 if taller else 5
	# Filas norte y sur.
	for row in 2:
		var x := inner.position.x
		while x < inner.end.x - 10.0:
			var w := minf(rng.randf_range(16.0, 30.0), inner.end.x - x)
			var d := rng.randf_range(16.0, 24.0)
			var floors := rng.randi_range(2, max_floors)
			var h := floors * 3.4
			var z := inner.position.y + d * 0.5 if row == 0 else inner.end.y - d * 0.5
			var c := Vector2(x + w * 0.5, z)
			if not _is_reserved(c):
				_add_building(c, Vector3(w - 0.6, h, d), SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], 0.5)
			x += w
	# Filas este y oeste entre medias (deja el centro como aparcamiento).
	for col in 2:
		var z := inner.position.y + 26.0
		while z < inner.end.y - 34.0:
			var dz := rng.randf_range(14.0, 22.0)
			var w := rng.randf_range(14.0, 20.0)
			var h := rng.randi_range(2, max_floors - 1) * 3.4
			var x := inner.position.x + w * 0.5 if col == 0 else inner.end.x - w * 0.5
			var c := Vector2(x, z + dz * 0.5)
			if not _is_reserved(c):
				_add_building(c, Vector3(w, h, dz - 0.6), SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], 0.5)
			z += dz


func _fill_beachfront(inner: Rect2) -> void:
	# Hoteles y apartamentos mirando al mar; hueco abierto frente al muelle.
	var z := inner.position.y
	while z < inner.end.y - 12.0:
		var dz := rng.randf_range(18.0, 28.0)
		var c := Vector2(inner.position.x + 12.0, z + dz * 0.5)
		var open_plaza := absf(c.y - CityLayout.PIER_Z) < 30.0
		if not open_plaza:
			var h := rng.randi_range(4, 10) * 3.4
			_add_building(c, Vector3(22.0, h, dz - 2.0), HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()].lerp(Color.WHITE, 0.4), 0.5)
		var c2 := Vector2(inner.end.x - 10.0, z + dz * 0.5)
		_add_building(c2, Vector3(18.0, rng.randi_range(2, 4) * 3.4, dz - 2.0), SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], 0.5)
		z += dz


## Material PBR con proyección triplanar en coordenadas de mundo (sin UV).
func _textured(id: String, tint: Color, tile: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	if ResourceLoader.exists(TEX + id + "/albedo.jpg"):
		m.albedo_texture = load(TEX + id + "/albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load(TEX + id + "/normal.jpg")
		m.roughness_texture = load(TEX + id + "/roughness.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile
	return m


func _flush_buildings() -> void:
	_add_roof_details()
	var mm := _box_multimesh(_buildings)
	var mi := MultiMeshInstance3D.new()
	mi.name = "Buildings"
	mi.multimesh = mm
	add_child(mi)
	_build_pools()


## Cornisas y aparatos de aire acondicionado en las azoteas.
func _add_roof_details() -> void:
	var caps: Array = []
	var units: Array = []
	for b in _buildings:
		var c: Vector3 = b["center"]
		var s: Vector3 = b["size"]
		if s.y < 3.2:
			continue
		var top := c.y + s.y * 0.5
		caps.append(Transform3D(Basis.from_scale(Vector3(s.x + 0.35, 0.45, s.z + 0.35)), Vector3(c.x, top + 0.05, c.z)))
		if float(b["kind"]) > 0.34 and s.x > 10.0:
			for k in rng.randi_range(1, 3):
				var p := Vector3(c.x + rng.randf_range(-s.x * 0.3, s.x * 0.3), top + 0.6, c.z + rng.randf_range(-s.z * 0.3, s.z * 0.3))
				units.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.6, 2.6), 1.2, rng.randf_range(1.2, 1.8))), p))
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3.ONE
	cap_mesh.material = _textured("concrete_wall", Color(0.82, 0.8, 0.78), 2.0)
	_multimesh(cap_mesh, caps, "Cornices")
	var unit_mesh := BoxMesh.new()
	unit_mesh.size = Vector3.ONE
	unit_mesh.material = MeshBuilder.material(Color(0.62, 0.64, 0.66), 0.45, 0.6)
	_multimesh(unit_mesh, units, "RoofUnits")


func _box_multimesh(items: Array) -> MultiMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat_building
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = items.size()
	for i in items.size():
		var it: Dictionary = items[i]
		var s: Vector3 = it["size"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(s), it["center"]))
		var col: Color = it["color"]
		mm.set_instance_custom_data(i, Color(col.r, col.g, col.b, it["kind"]))
	return mm


func _build_pools() -> void:
	var b := MeshBuilder.new()
	var water := MeshBuilder.material(Color(0.25, 0.75, 0.9), 0.05, 0.0, Color(0.05, 0.3, 0.4), 0.6)
	b.surface("water", water).surface("rim", MeshBuilder.material(Color(0.9, 0.9, 0.88), 0.7))
	for p in pools:
		var r: Rect2 = p
		_flat_quad(b, "water", r, 0.16)
		b.box("rim", Vector3(r.get_center().x, 0.14, r.position.y - 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
		b.box("rim", Vector3(r.get_center().x, 0.14, r.end.y + 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
		b.box("rim", Vector3(r.position.x - 0.25, 0.14, r.get_center().y), Vector3(0.5, 0.1, r.size.y))
		b.box("rim", Vector3(r.end.x + 0.25, 0.14, r.get_center().y), Vector3(0.5, 0.1, r.size.y))
	if b.has_geometry():
		_mesh_instance(b.commit(), "Pools", false)


# ---------------------------------------------------------------- lugares de la historia

func _build_mack_house() -> void:
	var c := CityLayout.landmark("mack_house")
	var b := MeshBuilder.new()
	var wall := _textured("stucco_beige", Color(1.0, 0.97, 0.92), 3.0)
	var trim := MeshBuilder.material(Color(0.12, 0.12, 0.13), 0.7)
	var gold := MeshBuilder.material(Color(0.83, 0.65, 0.17), 0.35, 0.7)
	var wood := MeshBuilder.material(Color(0.42, 0.28, 0.17), 0.8)
	var glass := MeshBuilder.material(Color(0.12, 0.15, 0.18), 0.1)
	b.surface("wall", wall).surface("trim", trim).surface("gold", gold).surface("wood", wood).surface("glass", glass)
	# Casa de dos alturas, porche con columnas y tejado plano con alero.
	b.box("wall", c + Vector3(0, 3.2, 0), Vector3(13.0, 6.4, 10.0))
	b.box("trim", c + Vector3(0, 6.55, 0), Vector3(14.0, 0.3, 11.0))
	b.box("wood", c + Vector3(0, 0.25, -6.6), Vector3(9.0, 0.3, 3.2))
	b.box("trim", c + Vector3(0, 3.3, -7.0), Vector3(9.4, 0.25, 3.8))
	for sx in [-4.2, 4.2]:
		b.box("wall", c + Vector3(sx, 1.75, -8.6), Vector3(0.35, 3.0, 0.35))
	b.box("wood", c + Vector3(0, 1.25, -5.02), Vector3(1.3, 2.3, 0.08))
	for wx in [-4.0, 4.0]:
		b.box("glass", c + Vector3(wx, 1.8, -5.02), Vector3(2.2, 1.4, 0.06))
		b.box("glass", c + Vector3(wx, 4.9, -5.02), Vector3(2.2, 1.3, 0.06))
	b.box("glass", c + Vector3(0, 4.9, -5.02), Vector3(1.6, 1.3, 0.06))
	# Franja dorada y buzón.
	b.box("gold", c + Vector3(0, 6.3, -5.52), Vector3(13.0, 0.12, 0.06))
	b.box("trim", c + Vector3(3.8, 0.7, -9.6), Vector3(0.12, 1.4, 0.12))
	b.box("gold", c + Vector3(3.8, 1.45, -9.6), Vector3(0.4, 0.3, 0.55))
	# Camino de entrada.
	b.box("wood", c + Vector3(0, 0.12, -10.4), Vector3(1.6, 0.04, 3.6))
	_mesh_instance(b.commit(), "MackHouse")
	_collider_box(c + Vector3(0, 3.2, 0), Vector3(13.0, 6.4, 10.0))
	_collider_box(c + Vector3(0, 0.25, -6.6), Vector3(9.0, 0.3, 3.2))
	footprints.append(Rect2(c.x - 6.5, c.z - 5.0, 13.0, 10.0))
	pools.append(Rect2(c.x - 3.5, c.z + 8.0, 7.0, 4.0))


func _build_garage() -> void:
	var c := CityLayout.landmark("vargas_garage")
	var b := MeshBuilder.new()
	b.surface("wall", _textured("concrete_wall", Color(0.85, 0.83, 0.8), 3.0))
	b.surface("door", MeshBuilder.material(Color(0.35, 0.37, 0.4), 0.5, 0.6))
	b.surface("sign", MeshBuilder.material(Color(0.9, 0.25, 0.15), 0.5, 0.0, Color(1.0, 0.35, 0.15), 1.5))
	b.surface("dark", MeshBuilder.material(Color(0.05, 0.05, 0.06), 0.9))
	b.box("wall", c + Vector3(0, 3.5, 0), Vector3(26.0, 7.0, 18.0))
	# Tres portones; el central abierto (interior oscuro).
	for i in 3:
		var x := (i - 1) * 8.0
		if i == 1:
			b.box("dark", c + Vector3(x, 2.2, 9.0), Vector3(5.6, 4.4, 0.1))
		else:
			b.box("door", c + Vector3(x, 2.2, 9.02), Vector3(5.6, 4.4, 0.1))
	b.box("sign", c + Vector3(0, 5.8, 9.1), Vector3(12.0, 1.2, 0.2))
	_mesh_instance(b.commit(), "VargasAutoWorks")
	_collider_box(c + Vector3(0, 3.5, -0.5), Vector3(26.0, 7.0, 17.0))
	footprints.append(Rect2(c.x - 13.0, c.z - 9.0, 26.0, 18.0))
	var label := Label3D.new()
	label.text = "VARGAS AUTO WORKS"
	label.font_size = 96
	label.pixel_size = 0.01
	label.modulate = Color(1, 0.95, 0.85)
	label.outline_size = 12
	label.position = c + Vector3(0, 5.8, 9.25)
	add_child(label)


func _build_terminal() -> void:
	var c := CityLayout.landmark("terminal")
	var b := MeshBuilder.new()
	b.surface("glass", MeshBuilder.material(Color(0.2, 0.28, 0.34), 0.08, 0.3))
	b.surface("frame", MeshBuilder.material(Color(0.82, 0.83, 0.85), 0.4, 0.5))
	b.surface("roof", MeshBuilder.material(Color(0.92, 0.92, 0.9), 0.6))
	b.surface("paint", MeshBuilder.material(Color(0.95, 0.85, 0.2), 0.7))
	b.surface("bench", MeshBuilder.material(Color(0.25, 0.25, 0.27), 0.5, 0.5))
	# Vestíbulo acristalado.
	b.box("glass", c + Vector3(0, 4.0, -10.0), Vector3(40.0, 8.0, 12.0))
	b.box("frame", c + Vector3(0, 8.15, -10.0), Vector3(41.0, 0.3, 13.0))
	var x := -20.0
	while x <= 20.0:
		b.box("frame", c + Vector3(x, 4.0, -3.95), Vector3(0.25, 8.0, 0.15))
		x += 4.0
	# Marquesina sobre los andenes.
	b.box("roof", c + Vector3(0, 5.6, 6.5), Vector3(46.0, 0.35, 17.0))
	for cx in [-21.0, -7.0, 7.0, 21.0]:
		for cz in [0.0, 13.5]:
			b.cylinder("frame", c + Vector3(cx, 0.1, cz), 0.25, 0.25, 5.5, 8)
	for bx in [-14.0, -2.0, 10.0]:
		b.box("bench", c + Vector3(bx, 0.55, 2.0), Vector3(3.5, 0.12, 0.6))
	_mesh_instance(b.commit(), "WestbrookTerminal")
	_collider_box(c + Vector3(0, 4.0, -10.0), Vector3(40.0, 8.0, 12.0))
	footprints.append(Rect2(c.x - 20.0, c.z - 16.0, 40.0, 12.0))
	var label := Label3D.new()
	label.text = "WESTBROOK TERMINAL"
	label.font_size = 128
	label.pixel_size = 0.012
	label.outline_size = 16
	label.modulate = Color(1, 1, 1)
	label.position = c + Vector3(0, 6.6, 15.1)
	add_child(label)


func _build_veyra_mart() -> void:
	var c := CityLayout.landmark("veyra_mart")
	var b := MeshBuilder.new()
	b.surface("wall", _textured("brick", Color(0.95, 0.88, 0.8), 2.5))
	b.surface("glass", MeshBuilder.material(Color(0.25, 0.22, 0.16), 0.1, 0.0, Color(1.0, 0.85, 0.55), 0.6))
	b.surface("awning", MeshBuilder.material(Color(0.12, 0.45, 0.35), 0.8))
	b.surface("sign", MeshBuilder.material(Color(0.95, 0.3, 0.2), 0.5, 0.0, Color(1.0, 0.3, 0.2), 1.8))
	b.surface("bars", MeshBuilder.material(Color(0.15, 0.15, 0.16), 0.5, 0.6))
	b.box("wall", c + Vector3(0, 2.6, 0), Vector3(16.0, 5.2, 12.0))
	b.box("glass", c + Vector3(-2.5, 1.5, 6.02), Vector3(9.0, 2.4, 0.06))
	# Rejas en el escaparate: el barrio no es tranquilo.
	var gx := -6.8
	while gx <= 1.8:
		b.box("bars", c + Vector3(gx, 1.5, 6.1), Vector3(0.05, 2.5, 0.05))
		gx += 0.45
	b.box("wall", c + Vector3(4.5, 1.3, 6.05), Vector3(1.4, 2.4, 0.05))
	b.box("awning", Vector3.ZERO, Vector3(16.4, 0.15, 2.2), Transform3D(Basis(Vector3.RIGHT, 0.25), c + Vector3(0, 3.3, 7.0)))
	b.box("sign", c + Vector3(0, 4.4, 6.1), Vector3(10.0, 1.0, 0.15))
	_mesh_instance(b.commit(), "VeyraMart")
	_collider_box(c + Vector3(0, 2.6, 0), Vector3(16.0, 5.2, 12.0))
	footprints.append(Rect2(c.x - 8.0, c.z - 6.0, 16.0, 12.0))
	var label := Label3D.new()
	label.text = "VEYRA MART"
	label.font_size = 110
	label.pixel_size = 0.009
	label.outline_size = 10
	label.position = c + Vector3(0, 4.4, 6.25)
	add_child(label)


func _build_river_and_bridge() -> void:
	var b := MeshBuilder.new()
	b.surface("concrete", mat_concrete)
	var x0 := CityLayout.RIVER_X0
	var x1 := CityLayout.RIVER_X1
	var depth := -5.0
	var z0 := -3000.0
	var z1 := 3000.0
	b.quad("concrete", Vector3(x0, 0, z0), Vector3(x0 + 15.0, depth, z0), Vector3(x0 + 15.0, depth, z1), Vector3(x0, 0, z1), Vector3(0.32, 0.95, 0).normalized())
	b.quad("concrete", Vector3(x0 + 15.0, depth, z0), Vector3(x1 - 15.0, depth, z0), Vector3(x1 - 15.0, depth, z1), Vector3(x0 + 15.0, depth, z1), Vector3.UP)
	b.quad("concrete", Vector3(x1 - 15.0, depth, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1 - 15.0, depth, z1), Vector3(-0.32, 0.95, 0).normalized())
	_mesh_instance(b.commit(), "RiverChannel", false)
	var river_water := mat_water.duplicate() as ShaderMaterial
	river_water.set_shader_parameter("shore_x", 99999.0)
	river_water.set_shader_parameter("shallow", Color(0.18, 0.32, 0.30))
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(x1 - x0 - 26.0, 6000.0)
	plane.material = river_water
	water.mesh = plane
	water.position = Vector3((x0 + x1) * 0.5, depth + 0.4, 0)
	water.name = "RiverWater"
	add_child(water)

	# Autopista hacia el este (entrada desde el desierto) y puente sobre el río.
	var r := MeshBuilder.new()
	r.surface("road", mat_road)
	var w := 16.0
	var start := CityLayout.EAST_EDGE + 7.0
	_road_piece_x(r, CityLayout.HIGHWAY_Z, w, start, CityLayout.HIGHWAY_END_X, 0.05)
	_mesh_instance(r.commit(), "Highway", false)
	var br := MeshBuilder.new()
	br.surface("deck", MeshBuilder.material(Color(0.62, 0.61, 0.58), 0.9))
	br.surface("steel", MeshBuilder.material(Color(0.86, 0.38, 0.18), 0.45, 0.5))
	var bx0 := x0 - 6.0
	var bx1 := x1 + 6.0
	var cx := (bx0 + bx1) * 0.5
	br.box("deck", Vector3(cx, -0.6, 0), Vector3(bx1 - bx0, 1.2, w + 3.0))
	for sz in [-1.0, 1.0]:
		br.box("deck", Vector3(cx, 0.55, sz * (w * 0.5 + 1.0)), Vector3(bx1 - bx0, 1.0, 0.5))
		# Arco atirantado.
		var seg := 16
		var prev := Vector3(bx0 + 4.0, 1.0, sz * (w * 0.5 + 1.0))
		for i in range(1, seg + 1):
			var t := float(i) / seg
			var p := Vector3(lerpf(bx0 + 4.0, bx1 - 4.0, t), 1.0 + sin(t * PI) * 20.0, sz * (w * 0.5 + 1.0))
			var mid := (prev + p) * 0.5
			var dir := (p - prev)
			var basis := Basis(Quaternion(Vector3.RIGHT, dir.normalized()))
			br.box("steel", Vector3.ZERO, Vector3(dir.length() + 0.3, 0.9, 0.9), Transform3D(basis, mid))
			if i < seg:
				br.box("steel", Vector3(p.x, (p.y + 1.0) * 0.5, p.z), Vector3(0.12, p.y - 1.0, 0.12))
			prev = p
	for px in [bx0 + 12.0, bx1 - 12.0]:
		br.box("deck", Vector3(px, -3.0, 0), Vector3(4.0, 5.0, 10.0))
	_mesh_instance(br.commit(), "VeyraRiverBridge")


func _build_desert() -> void:
	# Carretera del desierto por la que llega el autobús de la cinemática.
	var b := MeshBuilder.new()
	b.surface("pole", MeshBuilder.material(Color(0.35, 0.26, 0.18), 0.9))
	b.cylinder("pole", Vector3.ZERO, 0.14, 0.12, 9.0, 6)
	b.box("pole", Vector3(0, 8.4, 0), Vector3(2.4, 0.15, 0.15))
	var poles: Array = []
	var x := 500.0
	while x < CityLayout.HIGHWAY_END_X:
		poles.append(Transform3D(Basis.IDENTITY, Vector3(x, 0, -14.0)))
		x += 45.0
	_multimesh(b.commit(), poles, "TelegraphPoles", false)
	var cactus := MeshBuilder.new()
	cactus.surface("c", MeshBuilder.material(Color(0.26, 0.38, 0.2), 0.85))
	cactus.cylinder("c", Vector3.ZERO, 0.35, 0.3, 4.2, 8)
	cactus.sphere("c", Vector3(0, 4.2, 0), Vector3(0.3, 0.3, 0.3), 3, 8)
	cactus.cylinder("c", Vector3(0.35, 1.6, 0), 0.22, 0.2, 1.6, 6, Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3.ZERO))
	cactus.cylinder("c", Vector3(-0.3, 2.2, 0), 0.2, 0.18, 1.3, 6, Transform3D(Basis(Vector3.FORWARD, -0.25), Vector3.ZERO))
	var rocks := MeshBuilder.new()
	rocks.surface("r", MeshBuilder.material(Color(0.55, 0.36, 0.24), 0.95))
	rocks.sphere("r", Vector3.ZERO, Vector3(3.0, 1.6, 2.4), 4, 7)
	rocks.sphere("r", Vector3(2.2, -0.2, 1.0), Vector3(1.8, 1.0, 1.5), 3, 6)
	var ct: Array = []
	var rt: Array = []
	for i in 260:
		var p := Vector3(rng.randf_range(1500.0, CityLayout.HIGHWAY_END_X), 0, rng.randf_range(-400.0, 400.0))
		if absf(p.z) < 14.0:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), p)
		if i % 3 == 0:
			rt.append(t)
		else:
			ct.append(t)
	_multimesh(cactus.commit(), ct, "Cacti", false)
	_multimesh(rocks.commit(), rt, "DesertRocks", false)


# ---------------------------------------------------------------- playa y mar

func _sand_height(x: float) -> float:
	# 0 en el bulevar, nivel del agua en la orilla, más hondo mar adentro.
	var t := (CityLayout.BEACH_EAST - x) / (CityLayout.BEACH_EAST - CityLayout.SHORE_X)
	return lerpf(0.0, CityLayout.WATER_LEVEL - 0.05, t) if t <= 1.0 else CityLayout.WATER_LEVEL - 0.05 - (t - 1.0) * 1.5


func _build_beach_and_ocean() -> void:
	var b := MeshBuilder.new()
	b.surface("sand", mat_sand)
	var faces := PackedVector3Array()
	var xs: Array = []
	var x := CityLayout.BEACH_EAST
	while x > CityLayout.SHORE_X - 140.0:
		xs.append(x)
		x -= 6.0
	var z0 := -900.0
	var z1 := 900.0
	for i in range(xs.size() - 1):
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		var ya := _sand_height(xa)
		var yb := _sand_height(xb)
		var p := [Vector3(xa, ya, z0), Vector3(xb, yb, z0), Vector3(xb, yb, z1), Vector3(xa, ya, z1)]
		var n: Vector3 = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
		if n.y < 0:
			n = -n
		b.quad("sand", p[0], p[1], p[2], p[3], n)
		faces.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	_mesh_instance(b.commit(), "Beach", false)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	_static.add_child(cs)

	var water := MeshInstance3D.new()
	water.name = "Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 2400)
	plane.subdivide_width = 70
	plane.subdivide_depth = 120
	plane.material = mat_water
	water.mesh = plane
	water.position = Vector3(CityLayout.SHORE_X + 40.0 - 700.0, CityLayout.WATER_LEVEL, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(6000, 8000)
	far_plane.material = mat_water
	var far := MeshInstance3D.new()
	far.name = "OceanFar"
	far.mesh = far_plane
	far.position = Vector3(CityLayout.SHORE_X - 1400.0 - 2300.0, CityLayout.WATER_LEVEL - 0.05, 0)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)


func _build_pier() -> void:
	var b := MeshBuilder.new()
	b.surface("wood", MeshBuilder.material(Color(0.48, 0.36, 0.25), 0.85))
	b.surface("post", MeshBuilder.material(Color(0.30, 0.22, 0.15), 0.9))
	b.surface("rail", MeshBuilder.material(Color(0.92, 0.92, 0.9), 0.6))
	var z := CityLayout.PIER_Z
	var w := CityLayout.PIER_WIDTH
	var h := CityLayout.PIER_HEIGHT
	var x0 := CityLayout.PIER_FROM_X
	var x1 := CityLayout.PIER_TO_X
	var len := x0 - x1
	var cx := (x0 + x1) * 0.5
	b.box("wood", Vector3(cx, h - 0.15, z), Vector3(len, 0.3, w))
	_collider_box(Vector3(cx, h - 0.15, z), Vector3(len, 0.3, w))
	# Rampa desde la arena.
	var ramp_len := 14.0
	var rx := x0 + ramp_len * 0.5
	var ry := _sand_height(rx)
	var angle := atan2(h - ry, ramp_len)
	var ramp_basis := Basis(Vector3(0, 0, 1), -angle)
	var ramp_center := Vector3(rx, (h + ry) * 0.5 - 0.15, z)
	_collider_box(ramp_center, Vector3(ramp_len / cos(angle), 0.3, w - 1.0), ramp_basis)
	var x := x0
	while x > x1:
		for sz in [-1.0, 1.0]:
			b.cylinder("post", Vector3(x, -3.0, z + sz * (w * 0.5 - 0.3)), 0.22, 0.22, h + 3.0, 6)
			b.box("rail", Vector3(x, h + 0.55, z + sz * (w * 0.5 - 0.1)), Vector3(0.12, 1.1, 0.12))
		x -= 6.0
	for sz in [-1.0, 1.0]:
		b.box("rail", Vector3(cx, h + 1.05, z + sz * (w * 0.5 - 0.1)), Vector3(len, 0.1, 0.12))
		_collider_box(Vector3(cx, h + 0.6, z + sz * (w * 0.5 - 0.1)), Vector3(len, 1.2, 0.2))
	b.box("rail", Vector3(x1 + 0.1, h + 1.05, z), Vector3(0.12, 0.1, w))
	_collider_box(Vector3(x1 + 0.1, h + 0.6, z), Vector3(0.2, 1.2, w))
	# Caseta al final del muelle.
	b.box("rail", Vector3(x1 + 8.0, h + 1.6, z), Vector3(6.0, 3.2, 5.0))
	_collider_box(Vector3(x1 + 8.0, h + 1.6, z), Vector3(6.0, 3.2, 5.0))
	var mi := _mesh_instance(b.commit(), "Pier")
	# La rampa necesita su propia malla girada.
	var rb := MeshBuilder.new()
	rb.surface("wood", MeshBuilder.material(Color(0.48, 0.36, 0.25), 0.85))
	rb.box("wood", Vector3.ZERO, Vector3(ramp_len / cos(angle), 0.3, w - 1.0))
	var ramp := _mesh_instance(rb.commit(), "PierRamp")
	ramp.transform = Transform3D(ramp_basis, ramp_center)
	mi.name = "Pier"


# ---------------------------------------------------------------- vegetación

func _palm_mesh(height: float, lean: float) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.surface("trunk", MeshBuilder.material(Color(0.50, 0.40, 0.30), 0.95))
	var leaf_mat := MeshBuilder.material(Color(0.22, 0.42, 0.16), 0.8)
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.surface("leaf", leaf_mat)
	var segs := 6
	var prev := Vector3.ZERO
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := Vector3(lean * t0 * t0, height * t0, 0)
		var p1 := Vector3(lean * t1 * t1, height * t1, 0)
		var r0 := lerpf(0.28, 0.17, t0)
		var r1 := lerpf(0.28, 0.17, t1)
		var dir := (p1 - p0).normalized()
		var basis := Basis(Quaternion(Vector3.UP, dir))
		b.cylinder("trunk", Vector3.ZERO, r0, r1, (p1 - p0).length(), 7, Transform3D(basis, p0), Color.WHITE, false)
		prev = p1
	var top := prev
	b.sphere("trunk", top, Vector3(0.35, 0.3, 0.35), 3, 6)
	for k in 10:
		var a := TAU * k / 10.0 + 0.3
		var d := Vector3(cos(a), 0.25, sin(a)).normalized()
		b.leaf("leaf", top, d, 3.6 + 0.5 * sin(k * 2.3), 0.9, 2.2, Color(1.0, 1.0, 1.0).lerp(Color(0.8, 0.9, 0.6), (k % 3) / 3.0), 4)
	return b.commit()


func _tree_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.surface("trunk", MeshBuilder.material(Color(0.36, 0.26, 0.18), 0.95))
	b.surface("crown", MeshBuilder.material(Color(0.20, 0.36, 0.15), 0.85))
	b.cylinder("trunk", Vector3.ZERO, 0.22, 0.15, 3.2, 7)
	b.sphere("crown", Vector3(0, 4.2, 0), Vector3(2.2, 1.8, 2.2), 5, 9)
	b.sphere("crown", Vector3(0.9, 3.6, 0.5), Vector3(1.4, 1.2, 1.4), 4, 8, Transform3D.IDENTITY, Color(0.9, 1.0, 0.85))
	b.sphere("crown", Vector3(-0.8, 3.7, -0.6), Vector3(1.3, 1.1, 1.3), 4, 8, Transform3D.IDENTITY, Color(1.05, 1.05, 0.95))
	return b.commit()


func _multimesh(mesh: Mesh, transforms: Array, node_name: String, shadows: bool = true) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_vegetation() -> void:
	var palms: Array = [[], [], []]
	var palm_meshes := [_palm_mesh(10.0, 0.6), _palm_mesh(13.0, 1.4), _palm_mesh(8.5, -0.9)]
	var blvd_x := -235.0
	var z := CityLayout.NORTH_EDGE
	while z < CityLayout.SOUTH_EDGE:
		for side in [-1.0, 1.0]:
			if _near_crossing(Vector2(blvd_x + side * 10.0, z), 10.0):
				continue
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.15)), Vector3(blvd_x + side * 10.0, 0.1, z))
			palms[rng.randi() % 3].append(t)
		z += 14.0
	# Palmeras sueltas en la arena.
	for i in 40:
		var p := Vector3(rng.randf_range(CityLayout.BEACH_EAST - 5.0, CityLayout.BEACH_EAST - 40.0), 0, rng.randf_range(-260.0, 260.0))
		if absf(p.z - CityLayout.PIER_Z) < 10.0:
			continue
		p.y = _sand_height(p.x)
		palms[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
	# Westbrook Blvd y Westbrook Ave con palmeras en la acera.
	var x := -225.0
	while x < 245.0:
		for side in [-1.0, 1.0]:
			var p := Vector2(x, side * 8.0)
			if not _near_crossing(p, 12.0) and p.distance_to(Vector2(-100, 8)) > 6.0 and not _hits_footprint(p, 1.0) and absf(p.x - 100.0) > 30.0:
				palms[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0.1, p.y)))
		x += 22.0
	z = CityLayout.NORTH_EDGE
	while z < CityLayout.SOUTH_EDGE:
		for side in [-1.0, 1.0]:
			var p := Vector2(-50.0 + side * 9.0, z)
			if not _near_crossing(p, 12.0):
				palms[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0.1, p.y)))
		z += 24.0
	for i in 3:
		_multimesh(palm_meshes[i], palms[i], "Palms%d" % i)
		for t in palms[i]:
			var tt: Transform3D = t
			if tt.origin.x > CityLayout.BEACH_EAST:
				_collider_box(tt.origin + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))
	# Árboles de copa redonda en los patios.
	var trees: Array = []
	for blk in CityLayout.blocks():
		if blk["kind"] != "residential":
			continue
		var inner: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK - 2.0)
		for i in 14:
			var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
			if _hits_footprint(p, 3.0) or _hits_pool(p, 3.0):
				continue
			trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), Vector3(p.x, 0.1, p.y)))
	_multimesh(_tree_mesh(), trees, "YardTrees")
	# Setos delante de las casas.
	var hedge := MeshBuilder.new()
	hedge.surface("h", MeshBuilder.material(Color(0.16, 0.30, 0.12), 0.9))
	for blk in CityLayout.blocks():
		if blk["kind"] != "residential":
			continue
		var inner: Rect2 = (blk["rect"] as Rect2).grow(-CityLayout.SIDEWALK)
		for zz in [inner.position.y + 0.5, inner.end.y - 0.5]:
			var xx := inner.position.x + 1.0
			while xx < inner.end.x - 6.0:
				var seg := 5.0
				if not _is_reserved(Vector2(xx + seg * 0.5, zz)):
					hedge.box("h", Vector3(xx + seg * 0.5, 0.55, zz), Vector3(seg, 0.9, 0.7))
				xx += 8.5
	_mesh_instance(hedge.commit(), "Hedges")


func _near_crossing(p: Vector2, dist: float) -> bool:
	for x in CityLayout.avenue_xs():
		for z in CityLayout.street_zs():
			if absf(p.x - x) < dist + 7.0 and absf(p.y - z) < dist + 6.0:
				return true
	return false


func _hits_footprint(p: Vector2, margin: float) -> bool:
	for f in footprints:
		if (f as Rect2).grow(margin).has_point(p):
			return true
	return false


func _hits_pool(p: Vector2, margin: float) -> bool:
	for f in pools:
		if (f as Rect2).grow(margin).has_point(p):
			return true
	return false


# ---------------------------------------------------------------- farolas

func _build_street_lamps() -> void:
	var b := MeshBuilder.new()
	b.surface("pole", MeshBuilder.material(Color(0.25, 0.26, 0.28), 0.5, 0.6))
	lamp_material = MeshBuilder.material(Color(1, 0.9, 0.7), 0.3, 0.0, Color(1.0, 0.82, 0.55), 0.0)
	lamp_material.emission_enabled = true
	b.surface("lamp", lamp_material)
	b.cylinder("pole", Vector3.ZERO, 0.11, 0.08, 7.0, 6)
	b.box("pole", Vector3(0, 7.0, 1.0), Vector3(0.12, 0.12, 2.0))
	b.box("lamp", Vector3(0, 6.88, 1.9), Vector3(0.35, 0.12, 0.6))
	var mesh := b.commit()
	var lamps: Array = []
	for s in CityLayout.road_segments():
		var a: Vector2 = s["a"]
		var e: Vector2 = s["b"]
		var w: float = s["width"]
		var dir := (e - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var t := 15.0
		var flip := 1.0
		while t < a.distance_to(e) - 5.0:
			var p := a + dir * t + normal * (w * 0.5 + 0.6) * flip
			if not _near_crossing(p, 6.0) and not _hits_footprint(p, 0.5):
				var face := Vector3(-normal.x * flip, 0, -normal.y * flip)
				var basis := Basis.looking_at(-face, Vector3.UP)
				lamps.append(Transform3D(basis, Vector3(p.x, 0.12, p.y)))
				lamp_positions.append(Vector3(p.x + face.x * 1.9, 7.0, p.y + face.z * 1.9))
				_collider_box(Vector3(p.x, 3.5, p.y), Vector3(0.3, 7.0, 0.3))
			t += 34.0
			flip = -flip
	_multimesh(mesh, lamps, "StreetLamps")


# ---------------------------------------------------------------- coches aparcados

func _build_parked_cars() -> void:
	var variants: Array = []
	for i in 8:
		variants.append({"mesh": CarModel.build(i % 4, CAR_COLORS[(i * 3) % CAR_COLORS.size()], true), "list": []})
	var keep_clear: Array = []
	for id in ["ray_car", "bus_bay", "mart_stop", "mack_house_curb", "vargas_front", "player_spawn"]:
		var l := CityLayout.landmark(id)
		keep_clear.append(Vector2(l.x, l.z))
	for s in CityLayout.STREETS:
		var z: float = s[0]
		var w: float = s[1]
		for side in [-1.0, 1.0]:
			var x := CityLayout.WEST_EDGE + 16.0
			while x < CityLayout.EAST_EDGE - 10.0:
				var p := Vector3(x, 0.03, z + side * (w * 0.5 - 1.05))
				var skip := _near_crossing(Vector2(p.x, p.z), 8.0)
				for k in keep_clear:
					if Vector2(p.x, p.z).distance_to(k) < 22.0:
						skip = true
				if not skip and rng.randf() < 0.3:
					var heading := Vector3(side * -1.0, 0, 0)
					var basis := Basis.looking_at(-heading, Vector3.UP)
					var t := Transform3D(basis, p)
					var v: Dictionary = variants[rng.randi() % variants.size()]
					(v["list"] as Array).append(t)
					parked_spots.append(t)
					_collider_box(p + Vector3(0, 0.75, 0), Vector3(1.9, 1.4, 4.6), basis)
				x += rng.randf_range(7.0, 14.0)
	for i in variants.size():
		_multimesh(variants[i]["mesh"], variants[i]["list"], "ParkedCars%d" % i)


# ---------------------------------------------------------------- fondo

func _build_skyline() -> void:
	# Centro de South Veyra hacia el noreste, como en el mapa.
	var center := Vector2(620, -560)
	for i in 46:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 230.0
		var p := center + Vector2(cos(a), sin(a) * 0.7) * r
		if p.x < CityLayout.RIVER_X1 + 30.0:
			p.x += 120.0
		var h := lerpf(220.0, 45.0, r / 230.0) * rng.randf_range(0.6, 1.1)
		var w := rng.randf_range(22.0, 42.0)
		var col: Color = TOWER_COLORS[rng.randi() % TOWER_COLORS.size()]
		_skyline.append({"center": Vector3(p.x, h * 0.5, p.y), "size": Vector3(w, h, w * rng.randf_range(0.8, 1.2)), "color": col, "kind": 0.9})
		if rng.randf() < 0.4:
			var h2 := h * rng.randf_range(0.12, 0.25)
			_skyline.append({"center": Vector3(p.x, h + h2 * 0.5, p.y), "size": Vector3(w * 0.6, h2, w * 0.6), "color": col, "kind": 0.9})
	# Edificios medianos entre el barrio y el centro.
	for i in 70:
		var p := Vector2(rng.randf_range(450.0, 640.0), rng.randf_range(-480.0, -40.0))
		var h := rng.randf_range(10.0, 45.0)
		_skyline.append({"center": Vector3(p.x, h * 0.5, p.y), "size": Vector3(rng.randf_range(18, 34), h, rng.randf_range(18, 34)), "color": SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], "kind": 0.5})
	for i in 50:
		var p := Vector2(rng.randf_range(-220.0, 260.0), rng.randf_range(-640.0, -330.0))
		var h := rng.randf_range(8.0, 28.0)
		_skyline.append({"center": Vector3(p.x, h * 0.5, p.y), "size": Vector3(rng.randf_range(16, 30), h, rng.randf_range(16, 30)), "color": SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], "kind": 0.5})
	var mi := MultiMeshInstance3D.new()
	mi.name = "Skyline"
	mi.multimesh = _box_multimesh(_skyline)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Puerto al sur: grúas de contenedores.
	var b := MeshBuilder.new()
	b.surface("crane", MeshBuilder.material(Color(0.8, 0.25, 0.15), 0.6, 0.3))
	b.surface("box", MeshBuilder.material(Color(0.3, 0.45, 0.6), 0.8))
	for i in 5:
		var base := Vector3(-120.0 + i * 70.0, 0, 520.0)
		for dx in [-6.0, 6.0]:
			for dz in [-5.0, 5.0]:
				b.box("crane", base + Vector3(dx, 17.0, dz), Vector3(1.2, 34.0, 1.2))
		b.box("crane", base + Vector3(0, 34.0, -12.0), Vector3(3.0, 2.5, 60.0))
		for k in 12:
			b.box("box", base + Vector3(rng.randf_range(-30, 30), 1.3 + 2.6 * (k % 3), rng.randf_range(20, 60)), Vector3(12.0, 2.6, 2.5), Transform3D.IDENTITY, Color.WHITE.lerp(Color(rng.randf(), rng.randf() * 0.5, 0.2), 0.6))
	_mesh_instance(b.commit(), "Port", false)


func _build_mountains() -> void:
	var b := MeshBuilder.new()
	var m := MeshBuilder.material(Color(0.33, 0.33, 0.26), 0.95)
	b.surface("rock", m)
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 0.004
	# Sierra al norte y colinas al este (el mapa pone la Sierra Norte arriba).
	_ridge(b, noise, Vector2(-2200, -1500), Vector2(2800, -1500), 360.0, 420.0)
	_ridge(b, noise, Vector2(-1600, -1050), Vector2(1400, -1050), 160.0, 260.0)
	_ridge(b, noise, Vector2(1300, -900), Vector2(1300, -160), 140.0, 380.0)
	_ridge(b, noise, Vector2(1300, 160), Vector2(1300, 900), 140.0, 380.0)
	_mesh_instance(b.commit(), "Mountains", false)


func _ridge(b: MeshBuilder, noise: FastNoiseLite, from: Vector2, to: Vector2, height: float, depth: float) -> void:
	var steps := 70
	var rows := 6
	var dir := (to - from).normalized()
	var across := Vector2(-dir.y, dir.x)
	var len := from.distance_to(to)
	var grid: Array = []
	for r in rows + 1:
		var line: Array = []
		var v := float(r) / rows
		for i in steps + 1:
			var t := float(i) / steps
			var p := from + dir * len * t + across * (v - 0.5) * depth * 2.0
			var ridge := sin(v * PI)
			var hgt := height * ridge * (0.55 + 0.9 * noise.get_noise_2d(p.x, p.y)) * (0.6 + 0.4 * sin(t * PI))
			line.append(Vector3(p.x, maxf(hgt, -2.0), p.y))
		grid.append(line)
	for r in rows:
		for i in steps:
			var a: Vector3 = grid[r][i]
			var c: Vector3 = grid[r][i + 1]
			var d: Vector3 = grid[r + 1][i + 1]
			var e: Vector3 = grid[r + 1][i]
			var n := (c - a).cross(e - a).normalized()
			if n.y < 0:
				n = -n
			var shade := Color(1, 1, 1).lerp(Color(0.85, 0.75, 0.6), clampf(a.y / height, 0.0, 1.0))
			if a.y > height * 0.75:
				shade = Color(1.6, 1.6, 1.65)
			b.quad("rock", a, c, d, e, n, shade)


func _build_bounds() -> void:
	var mn := CityLayout.PLAY_MIN
	var mx := CityLayout.PLAY_MAX
	var h := 40.0
	_collider_box(Vector3((mn.x + mx.x) * 0.5, h * 0.5, mn.y), Vector3(mx.x - mn.x, h, 1.0))
	_collider_box(Vector3((mn.x + mx.x) * 0.5, h * 0.5, mx.y), Vector3(mx.x - mn.x, h, 1.0))
	_collider_box(Vector3(mx.x, h * 0.5, 0), Vector3(1.0, h, mx.y - mn.y))
	_collider_box(Vector3(mn.x, h * 0.5, 0), Vector3(1.0, h, mx.y - mn.y))
	# Pared en el agua (por debajo del muelle) para no adentrarse en el mar.
	var wx := CityLayout.SHORE_X - 15.0
	var gap0 := CityLayout.PIER_Z - CityLayout.PIER_WIDTH * 0.5
	var gap1 := CityLayout.PIER_Z + CityLayout.PIER_WIDTH * 0.5
	_collider_box(Vector3(wx, -1.6, (mn.y + gap0) * 0.5), Vector3(1.0, 4.8, gap0 - mn.y))
	_collider_box(Vector3(wx, -1.6, (gap1 + mx.y) * 0.5), Vector3(1.0, 4.8, mx.y - gap1))
