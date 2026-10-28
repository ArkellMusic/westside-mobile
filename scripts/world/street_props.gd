class_name StreetProps
extends Node3D
## Mobiliario urbano real (modelos CC0 de Poly Haven en assets/props): bocas de
## incendio, papeleras, cajas eléctricas, alcantarillas, aires acondicionados en
## fachadas, escaleras de incendios y farolas del paseo marítimo.
## Cada pieza va en MultiMesh (pocas llamadas de dibujo) con distancia de
## visibilidad para que el iPhone no dibuje lo que está lejos.

const PROPS := "res://assets/props/"

var rng := RandomNumberGenerator.new()
var _static: StaticBody3D
var _cache: Dictionary = {}


func build(city: CityBuilder) -> void:
	rng.seed = 5150
	_static = StaticBody3D.new()
	_static.name = "PropCollision"
	add_child(_static)
	_hydrants_and_bins(city)
	_manholes()
	_wall_units(city)
	_fire_escapes(city)
	_promenade_lamps()


# ------------------------------------------------------------------ utilidades

## Carga un modelo y devuelve [[malla, transform_local_normalizado], ...] para las
## mallas elegidas (por prefijo de nombre; vacío = todas), con la base en y=0 y
## centrado en XZ.
func _parts(file: String, include: Array = [], exclude: Array = []) -> Array:
	var key := file + str(include) + str(exclude)
	if _cache.has(key):
		return _cache[key]
	var result: Array = []
	if not ResourceLoader.exists(PROPS + file):
		_cache[key] = result
		return result
	var root: Node3D = (load(PROPS + file) as PackedScene).instantiate()
	var picked: Array = []
	var aabb := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var nm := String(mi.name)
		var ok := include.is_empty()
		for inc in include:
			if nm == inc or nm.begins_with(String(inc) + "_") and not nm.contains("aged") and not nm.contains("rust"):
				ok = true
		for exc in exclude:
			if nm.contains(String(exc)):
				ok = false
		if not ok:
			continue
		var xf := _world_xf(mi)
		picked.append([mi.mesh, xf])
		var b := xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var offset := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	for p in picked:
		result.append([p[0], Transform3D(Basis.IDENTITY, offset) * (p[1] as Transform3D)])
	root.free()
	_cache[key] = result
	return result


func _world_xf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _place(parts: Array, transforms: Array, node_name: String, view_dist: float, shadows: bool = true) -> void:
	if parts.is_empty() or transforms.is_empty():
		return
	for i in parts.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = parts[i][0]
		mm.instance_count = transforms.size()
		var local: Transform3D = parts[i][1]
		for k in transforms.size():
			mm.set_instance_transform(k, (transforms[k] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [node_name, i]
		mmi.multimesh = mm
		mmi.visibility_range_end = view_dist
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _collider(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	_static.add_child(cs)


func _near_crossing(p: Vector2, dist: float) -> bool:
	for x in CityLayout.avenue_xs():
		for z in CityLayout.street_zs():
			if absf(p.x - x) < dist and absf(p.y - z) < dist:
				return true
	return false


# ------------------------------------------------------------------ colocación

func _hydrants_and_bins(city: CityBuilder) -> void:
	var hydrants: Array = []
	var bins: Array = []
	var boxes: Array = []
	for s in CityLayout.road_segments():
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var w: float = s["width"]
		var dir := (b - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var t := 22.0
		while t < a.distance_to(b) - 10.0:
			for side in [-1.0, 1.0]:
				var p: Vector2 = a + dir * t + normal * (w * 0.5 + 0.9) * side
				if _near_crossing(p, 11.0) or p.x < CityLayout.WEST_EDGE + 8.0:
					continue
				var face: Vector3 = Vector3(-normal.x * side, 0, -normal.y * side)
				var basis := Basis.looking_at(face, Vector3.UP)
				var r := rng.randf()
				var pos := Vector3(p.x, 0.12, p.y)
				if r < 0.16:
					hydrants.append(Transform3D(basis, pos))
					_collider(pos + Vector3(0, 0.4, 0), Vector3(0.35, 0.8, 0.35))
				elif r < 0.34:
					bins.append(Transform3D(basis.rotated(Vector3.UP, rng.randf_range(-0.3, 0.3)), pos + Vector3(face.x, 0, face.z) * -1.2))
					_collider(pos + Vector3(0, 0.45, 0) - face * 1.2, Vector3(0.6, 0.9, 0.6))
				elif r < 0.42:
					var bp := pos - face * 1.6
					boxes.append(Transform3D(basis, bp))
					_collider(bp + Vector3(0, 0.56, 0), Vector3(0.6, 1.12, 0.45), basis)
			t += rng.randf_range(26.0, 40.0)
	_place(_parts("fire_hydrant/fire_hydrant_1k.gltf", ["fire_hydrant"], ["aged"]), hydrants, "Hydrants", 70.0)
	_place(_parts("trash_can/metal_trash_can_1k.gltf", ["metal_trash_can"], ["rust"]), bins, "TrashCans", 70.0)
	_place(_parts("utility_box_01/utility_box_01_1k.gltf"), boxes, "UtilityBoxes", 80.0)


func _manholes() -> void:
	var list: Array = []
	for x in CityLayout.avenue_xs():
		for z in CityLayout.street_zs():
			if rng.randf() < 0.6:
				list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + rng.randf_range(-3, 3), 0.035, z + 9.0 + rng.randf_range(0, 6))))
	_place(_parts("manhole/water_manhole_cover_1k.gltf"), list, "Manholes", 60.0, false)


func _wall_units(city: CityBuilder) -> void:
	# Aires acondicionados colgados en fachadas de comercios y apartamentos.
	var list: Array = []
	for f in city.footprints:
		var r: Rect2 = f
		if r.size.x < 14.0 or rng.randf() < 0.45:
			continue
		var floors := rng.randi_range(1, 3)
		for k in floors:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var x := rng.randf_range(r.position.x + 2.0, r.end.x - 2.0)
			var z: float = r.position.y - 0.25 if side < 0 else r.end.y + 0.25
			var y := 3.4 * (k + 1) + 1.0
			var basis := Basis.looking_at(Vector3(0, 0, side), Vector3.UP)
			list.append(Transform3D(basis.scaled(Vector3.ONE * 0.75), Vector3(x, y, z)))
	_place(_parts("aircon_unit/exterior_aircon_unit_1k.gltf", ["exterior_aircon_unit"], ["rusted"]), list, "WallAircon", 90.0, false)


func _fire_escapes(city: CityBuilder) -> void:
	var list: Array = []
	var parts := _parts("fire_escape/modular_fire_escape_1k.gltf")
	if parts.is_empty():
		return
	for b in city.footprints:
		var r: Rect2 = b
		if r.size.y < 14.0 or r.size.x < 14.0 or rng.randf() < 0.55:
			continue
		# En la cara lateral (callejón), mirando hacia fuera.
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var x: float = r.end.x + 0.8 if side > 0 else r.position.x - 0.8
		var z := r.get_center().y
		var basis := Basis.looking_at(Vector3(-side, 0, 0), Vector3.UP)
		list.append(Transform3D(basis, Vector3(x, 3.6, z)))
		if list.size() >= 18:
			break
	_place(parts, list, "FireEscapes", 120.0)


func _promenade_lamps() -> void:
	var list: Array = []
	var x := CityLayout.BEACH_EAST - 1.5
	var z := CityLayout.NORTH_EDGE + 10.0
	while z < CityLayout.SOUTH_EDGE:
		if absf(z - CityLayout.PIER_Z) > 8.0:
			list.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
			_collider(Vector3(x, 1.9, z), Vector3(0.3, 3.8, 0.3))
		z += 18.0
	# A lo largo del muelle.
	var px := CityLayout.PIER_FROM_X - 6.0
	while px > CityLayout.PIER_TO_X + 6.0:
		for sz in [-1.0, 1.0]:
			list.append(Transform3D(Basis.IDENTITY, Vector3(px, CityLayout.PIER_HEIGHT, CityLayout.PIER_Z + sz * (CityLayout.PIER_WIDTH * 0.5 - 0.4))))
		px -= 18.0
	_place(_parts("street_lamp_01/street_lamp_01_1k.gltf"), list, "PromenadeLamps", 150.0)
