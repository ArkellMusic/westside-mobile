class_name StateWorld
extends Node3D
## El estado alrededor de Westbrook: terreno por chunks, autopistas y carreteras con sus
## puentes (incluido el Puente Aurelio rojo de San Cordova), las ciudades lejanas como
## skyline con una cuadrícula de calles transitable, el aeropuerto, el tráfico de la
## autopista principal y las barreras de las zonas aún bloqueadas por misión.

const AURELIO_RED := Color(0.75, 0.21, 0.14)
## Hasta aquí la autopista del desierto la dibuja CityBuilder (sobre el puente de Veyra).
const HW_START_X := 450.0
const BARRIER_PATH := "res://assets/props/road_barrier/concrete_road_barrier_1k.gltf"

var city: CityBuilder
var terrain: Terrain
var highway_cars: Array = []
var _road_mat: ShaderMaterial
var _static: StaticBody3D
var _barriers: Node3D
var _unlock_key := ""
var _unlock_t := 0.0
var _rng := RandomNumberGenerator.new()
## Edificios de las ciudades (Rect2 en XZ) para el radar y el mapa.
var footprints: Array = []


func build(p_city: CityBuilder, with_terrain: bool = true) -> void:
	city = p_city
	_rng.seed = 4242
	StateLayout.ensure()
	_road_mat = city.mat_road if city else null
	if _road_mat == null:
		_road_mat = ShaderMaterial.new()
		_road_mat.shader = load("res://assets/shaders/road.gdshader")
	_static = StaticBody3D.new()
	_static.name = "StateCollision"
	add_child(_static)
	if with_terrain and not OS.get_cmdline_user_args().has("--no-terrain"):
		terrain = Terrain.new()
		terrain.name = "Terrain"
		add_child(terrain)
	_build_roads()
	_build_cities()
	_build_airport()
	_build_world_edge()
	_barriers = Node3D.new()
	_barriers.name = "ZoneBarriers"
	add_child(_barriers)
	refresh_barriers()
	_build_highway_traffic()


func _process(delta: float) -> void:
	_unlock_t -= delta
	if _unlock_t <= 0.0:
		_unlock_t = 1.0
		if _key() != _unlock_key:
			refresh_barriers()
	_update_traffic(delta)


# ---------------------------------------------------------------- carreteras

func _build_roads() -> void:
	for rd in StateLayout.roads():
		var pts: PackedVector2Array = rd["pts"]
		var hs: PackedFloat32Array = rd["h"]
		var w: float = rd["w"]
		var start := 0
		# La autopista arranca en Westbrook Blvd: el primer tramo lo dibuja ya CityBuilder
		# hasta el borde de la ciudad.
		if rd["id"] == "hw_desierto":
			while start < pts.size() - 1 and pts[start].x < HW_START_X - 0.5:
				start += 1
		var i := start
		while i < pts.size() - 1:
			var j := mini(i + 24, pts.size() - 1)
			_road_piece(pts, hs, w, i, j, String(rd["id"]))
			i = j
		_build_bridges(rd)


func _road_piece(pts: PackedVector2Array, hs: PackedFloat32Array, w: float, i0: int, i1: int, id: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var s := 0.0
	for i in range(i0):
		s += pts[i].distance_to(pts[i + 1])
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_s := 0.0
	for i in range(i0, i1 + 1):
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := (b - a).normalized()
		var right := Vector2(-dir.y, dir.x)
		var y := hs[i] + 0.06
		var l3 := Vector3(pts[i].x - right.x * w * 0.5, y, pts[i].y - right.y * w * 0.5)
		var r3 := Vector3(pts[i].x + right.x * w * 0.5, y, pts[i].y + right.y * w * 0.5)
		if i > i0:
			s += pts[i - 1].distance_to(pts[i])
			var quad := [prev_l, prev_r, r3, l3]
			var uvs := [Vector2(0, prev_s + 1000.0), Vector2(1, prev_s + 1000.0), Vector2(1, s + 1000.0), Vector2(0, s + 1000.0)]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				st.set_uv(uvs[k])
				st.set_uv2(Vector2(1.0e6, w))
				st.add_vertex(quad[k])
			faces.append_array([prev_l, r3, prev_r, prev_l, l3, r3])
		prev_l = l3
		prev_r = r3
		prev_s = s
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Road_" + id
	mi.mesh = st.commit()
	mi.material_override = _road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 6000.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	_static.add_child(cs)


func _box_collider(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	_static.add_child(cs)


func _build_bridges(rd: Dictionary) -> void:
	var pts: PackedVector2Array = rd["pts"]
	var hs: PackedFloat32Array = rd["h"]
	var br: PackedByteArray = rd["bridge"]
	var w: float = rd["w"]
	var n := pts.size()
	var i := 0
	while i < n:
		if br[i] == 0:
			i += 1
			continue
		var j := i
		while j < n and br[j] == 1:
			j += 1
		var a := maxi(i - 1, 0)
		var b := mini(j, n - 1)
		var aurelio: bool = rd["id"] == "costa_norte" and (b - a) > 12
		_bridge(pts, hs, a, b, w, aurelio)
		i = j


func _bridge(pts: PackedVector2Array, hs: PackedFloat32Array, a: int, b: int, w: float, aurelio: bool) -> void:
	var mb := MeshBuilder.new()
	var deck_col := Color(0.58, 0.57, 0.55)
	mb.surface("deck", MeshBuilder.material(deck_col, 0.85))
	mb.surface("steel", MeshBuilder.material(AURELIO_RED if aurelio else Color(0.72, 0.72, 0.70), 0.5, 0.4))
	var cable_pts: Array = []
	for i in range(a, b):
		var p0 := Vector3(pts[i].x, hs[i], pts[i].y)
		var p1 := Vector3(pts[i + 1].x, hs[i + 1], pts[i + 1].y)
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		var flat := Vector2(d.x, d.z)
		var yaw := atan2(-flat.y, flat.x)
		var pitch := atan2(d.y, flat.length())
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
		var length := d.length() + 0.4
		mb.box("deck", Vector3.ZERO, Vector3(length, 1.4, w + 2.0), Transform3D(basis, mid + Vector3(0, -0.66, 0)))
		for side in [-1.0, 1.0]:
			var off := basis * Vector3(0, 0.55, side * (w * 0.5 + 0.6))
			mb.box("steel" if aurelio else "deck", Vector3.ZERO, Vector3(length, 1.1, 0.35), Transform3D(basis, mid + off))
			_box_collider(mid + off, Vector3(length, 1.1, 0.35), basis)
		# Pilas cada ~60 m hasta el fondo.
		if (i - a) % 3 == 1:
			var ground := StateLayout.height_at(mid.x, mid.z)
			var top := mid.y - 1.3
			if top - ground > 1.5:
				var hgt := top - ground + 2.0
				mb.box("deck", Vector3.ZERO, Vector3(3.0, hgt, w * 0.6), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, ground - 2.0 + hgt * 0.5, mid.z)))
		cable_pts.append(p0)
	cable_pts.append(Vector3(pts[b].x, hs[b], pts[b].y))
	if aurelio:
		_aurelio(mb, cable_pts, w)
	var mi := MeshInstance3D.new()
	mi.name = "Bridge"
	mi.mesh = mb.commit()
	mi.visibility_range_end = 7000.0
	add_child(mi)


## Puente colgante rojo: dos torres, cables principales en catenaria y péndolas.
func _aurelio(mb: MeshBuilder, deck: Array, w: float) -> void:
	var n := deck.size()
	var t_a := int(n * 0.22)
	var t_b := int(n * 0.78)
	var tower_h := 95.0
	var half := w * 0.5 + 1.6
	var towers := [t_a, t_b]
	var dir: Vector3 = ((deck[n - 1] as Vector3) - (deck[0] as Vector3))
	dir.y = 0.0
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0, dir.x)
	var yaw := atan2(-dir.z, dir.x)
	var tb := Basis(Vector3.UP, yaw)
	for ti in towers:
		var base: Vector3 = deck[ti]
		var ground := StateLayout.height_at(base.x, base.z)
		for side in [-1.0, 1.0]:
			var c: Vector3 = base + right * float(side) * half
			var hgt := base.y + tower_h - ground
			mb.box("steel", Vector3.ZERO, Vector3(4.5, hgt, 4.5), Transform3D(tb, Vector3(c.x, ground + hgt * 0.5, c.z)))
		for k in 4:
			var yy := base.y + 12.0 + k * 24.0
			mb.box("steel", Vector3.ZERO, Vector3(3.0, 3.0, half * 2.0 + 4.5), Transform3D(tb, Vector3(base.x, yy, base.z)))
	# Cables: anclaje -> torre -> vano central (catenaria) -> torre -> anclaje.
	for side in [-1.0, 1.0]:
		var prev := Vector3.INF
		for i in n:
			var p: Vector3 = deck[i]
			var top_a: float = (deck[t_a] as Vector3).y + tower_h
			var top_b: float = (deck[t_b] as Vector3).y + tower_h
			var y: float
			if i <= t_a:
				y = lerpf(p.y + 2.0, top_a, float(i) / maxf(t_a, 1))
			elif i >= t_b:
				y = lerpf(top_b, p.y + 2.0, float(i - t_b) / maxf(n - 1 - t_b, 1))
			else:
				var u := float(i - t_a) / float(t_b - t_a)
				y = lerpf(top_a, top_b, u) - (tower_h - 6.0) * (1.0 - pow(2.0 * u - 1.0, 2.0))
			var q: Vector3 = p + right * float(side) * half
			q.y = y
			if prev != Vector3.INF:
				var mid := (prev + q) * 0.5
				var dd := q - prev
				var basis := Basis(Quaternion(Vector3.RIGHT, dd.normalized()))
				mb.box("steel", Vector3.ZERO, Vector3(dd.length() + 0.4, 0.9, 0.9), Transform3D(basis, mid))
			# Péndola vertical hasta el tablero.
			if y - p.y > 3.0:
				mb.box("steel", Vector3(q.x, (y + p.y) * 0.5, q.z), Vector3(0.22, y - p.y, 0.22))
			prev = q


# ------------------------------------------------------------------ ciudades

func _build_cities() -> void:
	for id in StateLayout.CITIES:
		_build_city(String(id))


func _build_city(id: String) -> void:
	var c: Dictionary = StateLayout.CITIES[id]
	var g := StateLayout.city_grid(id)
	var xs: Array = g["xs"]
	var zs: Array = g["zs"]
	var r: Rect2 = g["rect"]
	var level: float = g["level"]
	var tower: float = c["tower"]
	var center := r.get_center()
	if StateLayout.ZONE_CENTERS.has(String(c["zone"])) and r.has_point(StateLayout.zone_center(String(c["zone"]))):
		center = StateLayout.zone_center(String(c["zone"]))
	var island: bool = String(c["zone"]).begins_with("isla") or c.get("houses", false)
	var sw := 10.0 if island else 12.0
	# Calles (con pasos de cebra en cada cruce, como Westbrook).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_street := false
	for x in xs:
		for k in range(zs.size() - 1):
			any_street = _street(st, Vector2(x, zs[k]), Vector2(x, zs[k + 1]), sw, level) or any_street
	for z in zs:
		for k in range(xs.size() - 1):
			any_street = _street(st, Vector2(xs[k], z), Vector2(xs[k + 1], z), sw, level) or any_street
	if any_street:
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Streets_" + id
		mi.mesh = st.commit()
		mi.material_override = _road_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 2500.0
		add_child(mi)
	# Edificios por parcelas dentro de cada manzana.
	var items: Array = []
	var details: Array = []
	var radius := maxf(r.size.x, r.size.y) * 0.55
	var palette: Array = CityBuilder.TOWER_COLORS + CityBuilder.SHOP_COLORS
	if island:
		palette = CityBuilder.HOUSE_COLORS
	for i in range(-1, xs.size()):
		var bx0: float = (xs[i] if i >= 0 else r.position.x - 1.0) + sw * 0.5 + 4.0
		var bx1: float = (xs[i + 1] if i + 1 < xs.size() else r.end.x + 1.0) - sw * 0.5 - 4.0
		for j in range(-1, zs.size()):
			var bz0: float = (zs[j] if j >= 0 else r.position.y - 1.0) + sw * 0.5 + 4.0
			var bz1: float = (zs[j + 1] if j + 1 < zs.size() else r.end.y + 1.0) - sw * 0.5 - 4.0
			if bx1 - bx0 < 14.0 or bz1 - bz0 < 14.0:
				continue
			var lots_x := maxi(1, int((bx1 - bx0) / (24.0 if island else 38.0)))
			var lots_z := maxi(1, int((bz1 - bz0) / (24.0 if island else 38.0)))
			var lw := (bx1 - bx0) / lots_x
			var lz := (bz1 - bz0) / lots_z
			for a in lots_x:
				for b in lots_z:
					var p := Vector2(bx0 + (a + 0.5) * lw, bz0 + (b + 0.5) * lz)
					if not r.grow(10.0).has_point(p):
						continue
					if _rng.randf() < 0.12:
						continue
					var fw := lw * _rng.randf_range(0.62, 0.9)
					var fd := lz * _rng.randf_range(0.62, 0.9)
					var hgt := StateLayout.height_at(p.x, p.y)
					if absf(hgt - level) > 1.5:
						continue
					if StateLayout.road_query(p.x, p.y, true).x < maxf(fw, fd) * 0.5 + 6.0:
						continue
					if _in_canal(p, maxf(fw, fd) * 0.5 + 3.0):
						continue
					var t := clampf(1.0 - p.distance_to(center) / radius, 0.0, 1.0)
					var h := lerpf(7.0, tower, t * t) * _rng.randf_range(0.45, 1.1)
					if island:
						h = _rng.randf_range(5.0, tower)
					h = maxf(h, 5.0)
					var kind := 0.9 if h > 38.0 else (0.5 if not island else 0.2)
					var col: Color = palette[_rng.randi() % palette.size()]
					items.append({"center": Vector3(p.x, level + h * 0.5, p.y), "size": Vector3(fw, h, fd), "color": col, "kind": kind})
					footprints.append(Rect2(p.x - fw * 0.5, p.y - fd * 0.5, fw, fd))
					_box_collider(Vector3(p.x, level + h * 0.5, p.y), Vector3(fw, h, fd))
					# Remate escalonado en las torres altas (solo de cerca).
					if h > 70.0:
						var h2 := h * _rng.randf_range(0.08, 0.18)
						details.append({"center": Vector3(p.x, level + h + h2 * 0.5, p.y), "size": Vector3(fw * 0.62, h2, fd * 0.62), "color": col, "kind": kind})
	if items.is_empty() or city == null:
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Skyline_" + id
	mmi.multimesh = city._box_multimesh(items)
	mmi.visibility_range_end = 9000.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	if not details.is_empty():
		var dmi := MultiMeshInstance3D.new()
		dmi.name = "SkylineTops_" + id
		dmi.multimesh = city._box_multimesh(details)
		dmi.visibility_range_end = 3500.0
		add_child(dmi)


func _in_canal(p: Vector2, margin: float) -> bool:
	for c in StateLayout.canals():
		if (c as Rect2).grow(margin).has_point(p):
			return true
	return false


func _street(st: SurfaceTool, a: Vector2, b: Vector2, w: float, level: float) -> bool:
	var mid := (a + b) * 0.5
	# Sin calle donde ya pasa una carretera del estado, ni sobre el agua.
	if StateLayout.road_query(mid.x, mid.y, true).x < 3.0:
		return false
	for p in [a, mid, b]:
		if StateLayout.height_at(p.x, p.y) < level - 1.0:
			return false
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x) * w * 0.5
	var y := level + 0.04
	var len := a.distance_to(b)
	var quad := [Vector3(a.x - right.x, y, a.y - right.y), Vector3(a.x + right.x, y, a.y + right.y), Vector3(b.x + right.x, y, b.y + right.y), Vector3(b.x - right.x, y, b.y - right.y)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, len), Vector2(0, len)]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(len, w))
		st.add_vertex(quad[k])
	return true


func _build_airport() -> void:
	var r := StateLayout.AIRPORT
	var mb := MeshBuilder.new()
	mb.surface("tarmac", MeshBuilder.material(Color(0.20, 0.20, 0.21), 0.9))
	mb.surface("paint", MeshBuilder.material(Color(0.92, 0.92, 0.9), 0.7))
	mb.surface("apron", MeshBuilder.material(Color(0.52, 0.52, 0.50), 0.85))
	var y := 0.05
	var runways := [[Vector2(r.position.x + 40.0, r.position.y + 290.0), Vector2(r.end.x - 40.0, r.position.y + 290.0), 50.0],
		[Vector2(r.position.x + 120.0, r.position.y + 390.0), Vector2(r.end.x - 120.0, r.position.y + 390.0), 40.0]]
	for rw in runways:
		var a: Vector2 = rw[0]
		var b: Vector2 = rw[1]
		var w: float = rw[2]
		mb.box("tarmac", Vector3((a.x + b.x) * 0.5, y, a.y), Vector3(b.x - a.x, 0.1, w))
		var x := a.x + 60.0
		while x < b.x - 60.0:
			mb.box("paint", Vector3(x, y + 0.06, a.y), Vector3(24.0, 0.02, 0.9))
			x += 45.0
		for k in 8:
			for side in [a.x + 20.0, b.x - 20.0]:
				mb.box("paint", Vector3(side, y + 0.06, a.y - w * 0.4 + k * w * 0.8 / 7.0), Vector3(22.0, 0.02, 1.6))
	# Plataforma y terminal.
	mb.box("apron", Vector3(r.position.x + 330.0, y, r.position.y + 150.0), Vector3(520.0, 0.08, 120.0))
	mb.box("tarmac", Vector3(r.position.x + 330.0, y, r.position.y + 240.0), Vector3(640.0, 0.09, 22.0))
	var mi := MeshInstance3D.new()
	mi.name = "Airport"
	mi.mesh = mb.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if city:
		var items := [
			{"center": Vector3(r.position.x + 330.0, 9.0, r.position.y + 60.0), "size": Vector3(300.0, 18.0, 55.0), "color": Color(0.85, 0.86, 0.88), "kind": 0.5},
			{"center": Vector3(r.position.x + 560.0, 22.0, r.position.y + 70.0), "size": Vector3(10.0, 44.0, 10.0), "color": Color(0.8, 0.8, 0.82), "kind": 0.9},
			{"center": Vector3(r.position.x + 720.0, 8.0, r.position.y + 90.0), "size": Vector3(90.0, 16.0, 60.0), "color": Color(0.6, 0.62, 0.64), "kind": 0.5},
		]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "AirportBuildings"
		mmi.multimesh = city._box_multimesh(items)
		add_child(mmi)
		for it in items:
			_box_collider(it["center"], it["size"])
			var s: Vector3 = it["size"]
			var c: Vector3 = it["center"]
			footprints.append(Rect2(c.x - s.x * 0.5, c.z - s.z * 0.5, s.x, s.z))


# ---------------------------------------------------------------- barreras

func _key() -> String:
	var k := ""
	for id in StateLayout.ZONE_ORDER:
		k += "1" if GameState.is_zone_unlocked(id) else "0"
	return k


func _build_world_edge() -> void:
	var r := StateLayout.RECT
	var h := 400.0
	_box_collider(Vector3(r.get_center().x, 0, r.position.y), Vector3(r.size.x, h, 2.0))
	_box_collider(Vector3(r.get_center().x, 0, r.end.y), Vector3(r.size.x, h, 2.0))
	_box_collider(Vector3(r.position.x, 0, r.get_center().y), Vector3(2.0, h, r.size.y))
	_box_collider(Vector3(r.end.x, 0, r.get_center().y), Vector3(2.0, h, r.size.y))


## Zonas bloqueadas: muro invisible en su borde y cortes de carretera con barreras de
## hormigón donde una carretera entra en ellas. Se rehace al desbloquear una zona.
func refresh_barriers() -> void:
	_unlock_key = _key()
	for ch in _barriers.get_children():
		ch.queue_free()
	var body := StaticBody3D.new()
	body.name = "Walls"
	_barriers.add_child(body)
	var r := StateLayout.RECT.grow(-1.0)
	var barrier_scene: PackedScene = load(BARRIER_PATH) if ResourceLoader.exists(BARRIER_PATH) else null
	for id in StateLayout.ZONE_ORDER:
		if GameState.is_zone_unlocked(id):
			continue
		var poly := StateLayout.zone_polygon(id)
		for e in poly.size():
			var a := poly[e]
			var b := poly[(e + 1) % poly.size()]
			# Bordes exteriores del estado: ya hay muro.
			if (not r.has_point(a) and not r.has_point(b)) and (absf(a.x - b.x) < 1.0 or absf(a.y - b.y) < 1.0):
				continue
			var mid := (a + b) * 0.5
			var len := a.distance_to(b)
			var yaw := atan2(-(b - a).y, (b - a).x)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(len + 1.0, 600.0, 1.5)
			cs.shape = shape
			cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.0, mid.y))
			body.add_child(cs)
			# Cortes de carretera.
			for rd in StateLayout.roads():
				var pts: PackedVector2Array = rd["pts"]
				var hs: PackedFloat32Array = rd["h"]
				for k in range(pts.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(pts[k], pts[k + 1], a, b)
					if hit == null:
						continue
					var dir := (pts[k + 1] - pts[k]).normalized()
					var y := lerpf(hs[k], hs[k + 1], (hit as Vector2).distance_to(pts[k]) / maxf(pts[k].distance_to(pts[k + 1]), 0.01))
					_roadblock(hit, dir, float(rd["w"]), y, barrier_scene)


func _roadblock(p: Vector2, dir: Vector2, w: float, y: float, scene: PackedScene) -> void:
	var right := Vector2(-dir.y, dir.x)
	var yaw := atan2(-right.y, right.x)
	var root := Node3D.new()
	root.name = "Roadblock"
	_barriers.add_child(root)
	var count := int(w / 2.6) + 1
	for k in count:
		var q := p + right * (-w * 0.5 + 1.3 + k * (w - 2.6) / maxf(count - 1, 1))
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y + 0.06, q.y))
		if scene:
			var inst := scene.instantiate() as Node3D
			inst.transform = xf
			root.add_child(inst)
	# Valla rayada roja y blanca con un letrero de cierre.
	var mb := MeshBuilder.new()
	mb.surface("r", MeshBuilder.material(Color(0.85, 0.12, 0.1), 0.6))
	mb.surface("w", MeshBuilder.material(Color(0.95, 0.95, 0.95), 0.6))
	var stripes := 8
	for k in stripes:
		var u := -w * 0.5 + (k + 0.5) * w / stripes
		mb.box("r" if k % 2 == 0 else "w", Vector3(u, 1.6, 0), Vector3(w / stripes, 0.45, 0.15))
	for side in [-1.0, 1.0]:
		mb.box("w", Vector3(side * w * 0.5, 1.0, 0), Vector3(0.2, 2.0, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + 0.06, p.y))
	mi.visibility_range_end = 600.0
	root.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "ZONA CERRADA"
	lbl.font_size = 96
	lbl.pixel_size = 0.012
	lbl.outline_size = 12
	lbl.modulate = Color(1, 0.9, 0.3)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.position = Vector3(p.x, y + 3.2, p.y)
	lbl.visibility_range_end = 300.0
	root.add_child(lbl)


# ------------------------------------------------------- tráfico de autopista

func _build_highway_traffic() -> void:
	var main_roads: Array = []
	for rd in StateLayout.roads():
		if rd["main"]:
			main_roads.append(rd)
	var count := 10
	for i in count:
		var rd: Dictionary = main_roads[i % main_roads.size()]
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		var style: int = CarModel.TRAFFIC_STYLES[_rng.randi() % CarModel.TRAFFIC_STYLES.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = CarModel.build(style, CityBuilder.CAR_COLORS[_rng.randi() % CityBuilder.CAR_COLORS.size()], true)
		mi.visibility_range_end = 900.0
		body.add_child(mi)
		var spec := CarModel.spec(style)
		var shape := BoxShape3D.new()
		shape.size = Vector3(float(spec["half_w"]) * 2.0, float(spec["height"]) - 0.3, spec["length"])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.3 + (float(spec["height"]) - 0.3) * 0.5
		body.add_child(cs)
		body.name = "HighwayCar%d" % i
		add_child(body)
		var pts: PackedVector2Array = rd["pts"]
		var total := _road_len(pts)
		highway_cars.append({"node": body, "road": rd, "total": total, "s": _rng.randf() * total, "dir": 1.0 if i % 2 == 0 else -1.0, "speed": _rng.randf_range(22.0, 30.0)})


func _road_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(pts.size() - 1):
		l += pts[i].distance_to(pts[i + 1])
	return l


## Posición, cota y dirección en la carretera a la distancia s desde el inicio.
static func road_point(rd: Dictionary, s: float) -> Dictionary:
	var pts: PackedVector2Array = rd["pts"]
	var hs: PackedFloat32Array = rd["h"]
	var acc := 0.0
	for i in range(pts.size() - 1):
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(l, 0.001), 0.0, 1.0)
			return {"p": pts[i].lerp(pts[i + 1], t), "h": lerpf(hs[i], hs[i + 1], t), "dir": (pts[i + 1] - pts[i]).normalized()}
		acc += l
	return {"p": pts[0], "h": hs[0], "dir": Vector2.RIGHT}


func _update_traffic(delta: float) -> void:
	var f := terrain.focus_position() if terrain else Vector3.ZERO
	if OS.get_cmdline_user_args().has("--no-traffic-hw"):
		return
	for car in highway_cars:
		var rd: Dictionary = car["road"]
		var total: float = car["total"]
		var s: float = car["s"] + float(car["dir"]) * float(car["speed"]) * delta
		if s > total or s < 0.0:
			car["dir"] = -float(car["dir"])
			s = clampf(s, 0.0, total)
		car["s"] = s
		var rp := road_point(rd, s)
		var dir: Vector2 = rp["dir"] * float(car["dir"])
		var right := Vector2(-dir.y, dir.x)
		var p: Vector2 = rp["p"] + right * 2.4
		var node: AnimatableBody3D = car["node"]
		var pos := Vector3(p.x, float(rp["h"]) + 0.08, p.y)
		# Lejos del jugador no se dibuja (visibility range); de cerca no se solapa con él.
		if pos.distance_to(f) < 6.0:
			continue
		node.global_transform = Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), pos)
