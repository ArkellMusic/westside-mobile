class_name StateLayout
extends RefCounted
## Geografía del estado de Las Brisas a escala jugable (≈ 8,2 × 4,9 km).
## Fuente única de verdad para el terreno 3D, las carreteras del estado, las ciudades
## lejanas, el radar, el mapa ESTADO y la GPS. Coordenadas como CityLayout: X = este,
## -Z = norte, metros. Westbrook (South Veyra) se queda en el origen, al suroeste.
##
## Referencia: docs/mapa_estado_las_brisas.png — San Cordova al NO con su bahía y el
## puente rojo (Puente Aurelio), Las Brisas (desierto rojo con mesas) en el centro,
## Northpoint al NE bajo las montañas nevadas, Bahía Solana al E/SE con canales y las
## islas Brava, Coral y Nácar al sur unidas por puentes.

const CHUNK := 256.0
## Rectángulo del estado: 32 × 19 chunks de 256 m.
const RECT := Rect2(-1408.0, -3328.0, 8192.0, 4864.0)
const SEA := -0.45
## Rejilla gruesa (relieve lejano, mapa, profundidad del mar).
const GRID_RES := 32.0
## Rejilla de distancia a la costa.
const COAST_RES := 24.0
## Westbrook tiene su propio suelo, playa y colisiones: el terreno no se dibuja aquí.
const WB_HOLE := Rect2(-480.0, -300.0, 810.0, 600.0)
## Río de Veyra (canal de hormigón de CityBuilder).
const RIVER_Z0 := -1400.0
const RIVER_Z1 := 700.0

## Costa del continente (polígono cerrado).
const MAINLAND := [
	Vector2(-330, 300), Vector2(-330, 660), Vector2(100, 680), Vector2(500, 700), Vector2(1000, 690),
	Vector2(1600, 660), Vector2(2000, 600), Vector2(2400, 520), Vector2(2800, 420), Vector2(3200, 440),
	Vector2(3600, 470), Vector2(4000, 450), Vector2(4500, 420), Vector2(4900, 380), Vector2(5200, 370),
	Vector2(5500, 400), Vector2(5900, 380), Vector2(6200, 200), Vector2(6380, -200), Vector2(6400, -700),
	Vector2(6300, -1200), Vector2(6150, -1600), Vector2(6250, -2000), Vector2(6100, -2400), Vector2(5800, -2750),
	Vector2(5300, -2950), Vector2(4600, -3050), Vector2(3600, -3150), Vector2(2400, -3200), Vector2(1200, -3180),
	Vector2(200, -3080), Vector2(-400, -2900), Vector2(-850, -2650), Vector2(-1150, -2300), Vector2(-1250, -1900),
	Vector2(-1180, -1680), Vector2(-1100, -1450), Vector2(-1050, -1290), Vector2(-900, -1180), Vector2(-650, -1050),
	Vector2(-450, -880), Vector2(-360, -650), Vector2(-330, -300),
]
## Agua dentro del continente: bahía de San Cordova, puerto de Northpoint y marina de Bahía Solana.
const WATERS := [
	[Vector2(-1300, -1330), Vector2(-950, -1300), Vector2(-650, -1270), Vector2(-350, -1260), Vector2(-120, -1330),
		Vector2(-60, -1460), Vector2(-180, -1600), Vector2(-450, -1660), Vector2(-750, -1650), Vector2(-1000, -1615), Vector2(-1300, -1590)],
	[Vector2(6300, -2350), Vector2(5700, -2300), Vector2(5450, -2420), Vector2(5600, -2560), Vector2(6000, -2620), Vector2(6300, -2560)],
	[Vector2(5650, 500), Vector2(5680, 250), Vector2(5800, 150), Vector2(5950, 180), Vector2(6020, 300), Vector2(6050, 500)],
]
## Lago al norte del desierto: [centro, radios].
const LAKES := [[Vector2(2250, -2420), Vector2(380, 200)]]
const ISLANDS := {
	"isla_brava": {"c": Vector2(2700, 900), "r": Vector2(330, 220), "hill": 30.0, "seed": 1.0},
	"isla_coral": {"c": Vector2(4000, 980), "r": Vector2(290, 270), "hill": 85.0, "seed": 2.0},
	"isla_nacar": {"c": Vector2(5300, 900), "r": Vector2(300, 200), "hill": 26.0, "seed": 3.0},
}
const ISLETS := [
	[Vector2(2280, 1130), Vector2(70, 45)], [Vector2(3350, 1180), Vector2(55, 40)], [Vector2(4650, 1220), Vector2(80, 55)],
	[Vector2(6050, 950), Vector2(90, 60)], [Vector2(1750, 980), Vector2(75, 50)], [Vector2(6550, -1100), Vector2(70, 50)],
	[Vector2(6450, -2700), Vector2(90, 60)], [Vector2(-1250, -2550), Vector2(60, 45)],
]

## Ciudades: rectángulo de la cuadrícula, cota (m), separación de calles y altura máxima de torres.
const CITIES := {
	"sv_norte": {"zone": "south_veyra", "name": "Northgate", "rect": Rect2(-230, -900, 520, 520), "level": 0.0, "block": 90.0, "tower": 16.0, "houses": true},
	"sv_este": {"zone": "south_veyra", "name": "Distrito del Río", "rect": Rect2(470, -330, 700, 260), "level": 0.0, "block": 95.0, "tower": 34.0},
	"sv_centro": {"zone": "south_veyra", "name": "Centro de South Veyra", "rect": Rect2(460, -880, 520, 500), "level": 0.0, "block": 100.0, "tower": 210.0},
	"san_cordova": {"zone": "san_cordova", "name": "San Cordova", "rect": Rect2(-760, -2180, 820, 460), "level": 6.0, "block": 105.0, "tower": 190.0},
	"las_brisas": {"zone": "las_brisas", "name": "Las Brisas", "rect": Rect2(2450, -1610, 700, 520), "level": 28.0, "block": 110.0, "tower": 150.0},
	"northpoint": {"zone": "northpoint", "name": "Northpoint", "rect": Rect2(4450, -2700, 900, 480), "level": 14.0, "block": 105.0, "tower": 250.0},
	"bahia_solana": {"zone": "bahia_solana", "name": "Bahía Solana", "rect": Rect2(5050, -700, 1100, 1000), "level": 1.2, "block": 115.0, "tower": 165.0},
	"isla_brava": {"zone": "isla_brava", "name": "Isla Brava", "rect": Rect2(2560, 790, 300, 190), "level": 2.5, "block": 75.0, "tower": 26.0},
	"isla_nacar": {"zone": "isla_nacar", "name": "Isla Nácar", "rect": Rect2(5170, 820, 260, 160), "level": 2.5, "block": 70.0, "tower": 18.0},
	"isla_coral": {"zone": "isla_coral", "name": "Isla Coral", "rect": Rect2(3900, 1080, 200, 90), "level": 2.5, "block": 70.0, "tower": 14.0},
}
## Centro de cada zona (destino de la GPS y etiqueta del mapa).
const ZONE_CENTERS := {
	"south_veyra": Vector2(0, 0),
	"san_cordova": Vector2(-350, -1900),
	"las_brisas": Vector2(2800, -1350),
	"northpoint": Vector2(4900, -2450),
	"bahia_solana": Vector2(5600, -250),
	"isla_brava": Vector2(2700, 880),
	"isla_coral": Vector2(4000, 980),
	"isla_nacar": Vector2(5300, 900),
}
## Zonas llanas extra: [rect, cota, transición].
const FLATS := [
	[Rect2(-330, -950, 1880, 1700), 0.0, 300.0],   # South Veyra urbano, puerto y aeropuerto
	[Rect2(1800, 40, 400, 300), 0.0, 140.0],       # cárcel
]
## Aeropuerto de South Veyra (pistas).
const AIRPORT := Rect2(650, 160, 900, 430)
## Colinas: [centro, radios, altura].
const HILLS := [
	[Vector2(600, -1150), Vector2(750, 260), 70.0],
	[Vector2(-450, -2500), Vector2(800, 420), 150.0],
	[Vector2(-960, -1160), Vector2(220, 130), 30.0],
	[Vector2(-1020, -1760), Vector2(240, 160), 36.0],
	[Vector2(1700, -450), Vector2(380, 260), 55.0],
	[Vector2(4400, -1000), Vector2(420, 900), 110.0],
	[Vector2(6000, -1300), Vector2(400, 500), 80.0],
	[Vector2(3500, 280), Vector2(700, 160), 25.0],
	[Vector2(5700, -2950), Vector2(600, 260), 140.0],
]
## Desierto: [centro, radios].
const DESERT := [
	[Vector2(2850, -1350), Vector2(1650, 1050)],
	[Vector2(3000, -150), Vector2(1450, 520)],
]

## Autopistas y carreteras principales. level = cota fija (autopista del desierto, la de
## la cinemática del autobús); clear = gálibo de los puentes sobre el agua.
const ROADS := [
	{"id": "hw_desierto", "name": "Autopista del Desierto", "w": 16.0, "level": 0.0, "main": true,
		"pts": [Vector2(250, 0), Vector2(620, 0), Vector2(900, 0), Vector2(2800, 0), Vector2(4200, 0)]},
	{"id": "hw_este", "name": "Autopista Este", "w": 16.0, "main": true,
		"pts": [Vector2(4200, 0), Vector2(4600, -60), Vector2(4900, -160), Vector2(5300, -250), Vector2(5600, -250)]},
	{"id": "costa_norte", "name": "Carretera de la Costa", "w": 14.0, "clear": 24.0,
		"pts": [Vector2(-235, -262), Vector2(-260, -500), Vector2(-380, -820), Vector2(-600, -1020), Vector2(-820, -1120),
			Vector2(-900, -1220), Vector2(-900, -1700), Vector2(-820, -1800), Vector2(-600, -1880), Vector2(-350, -1900)]},
	{"id": "colinas", "name": "Ruta de las Colinas", "w": 14.0,
		"pts": [Vector2(150, -262), Vector2(150, -600), Vector2(400, -900), Vector2(900, -1100), Vector2(1400, -1200),
			Vector2(1900, -1350), Vector2(2800, -1350)]},
	{"id": "acceso_lb", "name": "Acceso a Las Brisas", "w": 14.0,
		"pts": [Vector2(2800, 0), Vector2(2800, -600), Vector2(2830, -1000), Vector2(2800, -1350)]},
	{"id": "lb_np", "name": "Autopista del Norte", "w": 16.0, "main": true,
		"pts": [Vector2(2800, -1350), Vector2(3250, -1650), Vector2(3800, -2050), Vector2(4400, -2350), Vector2(4900, -2450)]},
	{"id": "sierra", "name": "Carretera de la Sierra", "w": 12.0,
		"pts": [Vector2(-350, -1900), Vector2(100, -2150), Vector2(800, -2250), Vector2(1500, -2060), Vector2(2400, -1960), Vector2(3250, -1650)]},
	{"id": "np_bs", "name": "Carretera del Litoral", "w": 14.0,
		"pts": [Vector2(4900, -2450), Vector2(5500, -2150), Vector2(5800, -1500), Vector2(5800, -800), Vector2(5600, -250)]},
	{"id": "lb_bs", "name": "Carretera de los Cañones", "w": 12.0,
		"pts": [Vector2(2800, -1350), Vector2(3600, -1100), Vector2(4300, -750), Vector2(4900, -500), Vector2(5600, -250)]},
	{"id": "islas", "name": "Ruta de las Islas", "w": 12.0, "clear": 8.0,
		"pts": [Vector2(2800, 0), Vector2(2800, 300), Vector2(2780, 400), Vector2(2730, 700), Vector2(2700, 880), Vector2(2960, 900),
			Vector2(3060, 920), Vector2(3690, 960), Vector2(3800, 975), Vector2(4000, 980), Vector2(4200, 970), Vector2(4310, 960),
			Vector2(4990, 910), Vector2(5100, 905), Vector2(5300, 900), Vector2(5320, 780), Vector2(5330, 690), Vector2(5330, 360),
			Vector2(5350, 150), Vector2(5600, -250)]},
	{"id": "aeropuerto", "name": "Acceso al Aeropuerto", "w": 12.0,
		"pts": [Vector2(900, 0), Vector2(900, 190)]},
	{"id": "centro_sv", "name": "Avenida del Centro", "w": 14.0,
		"pts": [Vector2(620, 0), Vector2(620, -380)]},
]

## Polígonos de zona (id de zones.json). Las islas se miran antes que el continente.
const ZONES := {
	"south_veyra": [Vector2(-1408, -1260), Vector2(1000, -1260), Vector2(1500, -700), Vector2(4300, -700), Vector2(4300, 1536), Vector2(-1408, 1536)],
	"san_cordova": [Vector2(-1408, -3328), Vector2(1000, -3328), Vector2(1000, -1260), Vector2(-1408, -1260)],
	"las_brisas": [Vector2(1000, -2700), Vector2(4000, -2700), Vector2(4300, -1900), Vector2(4300, -700), Vector2(1500, -700), Vector2(1000, -1260)],
	"northpoint": [Vector2(1000, -3328), Vector2(6784, -3328), Vector2(6784, -1900), Vector2(4300, -1900), Vector2(4000, -2700), Vector2(1000, -2700)],
	"bahia_solana": [Vector2(4300, -1900), Vector2(6784, -1900), Vector2(6784, 1536), Vector2(4300, 1536)],
}
const ZONE_ORDER := ["isla_brava", "isla_coral", "isla_nacar", "south_veyra", "san_cordova", "las_brisas", "northpoint", "bahia_solana"]

# ----------------------------------------------------------------- estado interno

static var _built := false
static var _mutex := Mutex.new()
static var _cw := 0
static var _ch := 0
static var _coast := PackedFloat32Array()
static var _n_hills: FastNoiseLite
static var _n_mtn: FastNoiseLite
static var _n_mesa: FastNoiseLite
static var _n_detail: FastNoiseLite
static var _n_coast: FastNoiseLite
## Segmentos de carretera: arrays paralelos (rápidos en GDScript).
static var _sa := PackedVector2Array()
static var _sb := PackedVector2Array()
static var _sha := PackedFloat32Array()
static var _shb := PackedFloat32Array()
static var _sw := PackedFloat32Array()
static var _sbridge := PackedByteArray()
static var _sroad := PackedInt32Array()
static var _hash := {}
## Polilíneas finales: [{id, name, w, main, pts: PackedVector2Array, h: PackedFloat32Array, bridge: PackedByteArray}]
static var _roads: Array = []
static var _canals: Array = []   # Rect2
static var _polys := {}          # caché de polígonos (islas, lagos, zonas)
static var _flats: Array = []    # [rect, level, blend]
## Rejilla gruesa (lazy): alturas y biomas.
static var _grid_h := PackedFloat32Array()
static var _grid_b := PackedColorArray()
static var _grid_ready := false


static var _building := false


static func ensure() -> void:
	if _built or _building:
		return
	_mutex.lock()
	if not _built:
		_building = true
		_build()
		_built = true
		_building = false
	_mutex.unlock()


static func _build() -> void:
	_n_hills = _noise(11, 0.0016, 4)
	_n_mtn = _noise(23, 0.0011, 5)
	_n_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_mesa = _noise(37, 0.0019, 2)
	_n_detail = _noise(41, 0.012, 3)
	_n_coast = _noise(53, 0.004, 3)
	_flats.clear()
	for f in FLATS:
		_flats.append(f)
	for id in CITIES:
		var c: Dictionary = CITIES[id]
		var blend := 90.0 if String(c["zone"]).begins_with("isla") else 230.0
		_flats.append([c["rect"], c["level"], blend])
	var t0 := Time.get_ticks_usec()
	_build_canals()
	_build_coast_grid()
	var t1 := Time.get_ticks_usec()
	_build_road_geometry()
	var t2 := Time.get_ticks_usec()
	_build_road_profiles()
	print("StateLayout: costa %d ms, carreteras %d ms, perfiles %d ms" % [(t1 - t0) / 1000, (t2 - t1) / 1000, (Time.get_ticks_usec() - t2) / 1000])


static func _noise(seed_v: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


# ------------------------------------------------------------------- polígonos

static func ellipse_poly(c: Vector2, r: Vector2, seed_v: float, wobble: float = 0.12, n: int = 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		var k := 1.0 + wobble * (sin(a * 3.0 + seed_v * 1.7) * 0.6 + sin(a * 5.0 + seed_v * 4.1) * 0.4)
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * k)
	return out


## Polígonos de tierra (continente + islas + islotes).
static func land_polygons() -> Array:
	if _polys.has("land"):
		return _polys["land"]
	var out: Array = [PackedVector2Array(MAINLAND)]
	for id in ISLANDS:
		var d: Dictionary = ISLANDS[id]
		out.append(ellipse_poly(d["c"], d["r"], d["seed"]))
	var k := 0
	for it in ISLETS:
		k += 1
		out.append(ellipse_poly(it[0], it[1], 10.0 + k, 0.2, 16))
	_polys["land"] = out
	return out


## Agua interior (bahía, puertos, marina y lago).
static func water_polygons() -> Array:
	if _polys.has("water"):
		return _polys["water"]
	var out: Array = []
	for w in WATERS:
		out.append(PackedVector2Array(w))
	for l in LAKES:
		out.append(ellipse_poly(l[0], l[1], 7.0, 0.1, 32))
	_polys["water"] = out
	return out


static func zone_polygon(id: String) -> PackedVector2Array:
	var key := "zone_" + id
	if _polys.has(key):
		return _polys[key]
	var p := PackedVector2Array()
	if ZONES.has(id):
		p = PackedVector2Array(ZONES[id])
	elif ISLANDS.has(id):
		var d: Dictionary = ISLANDS[id]
		p = ellipse_poly(d["c"], d["r"] + Vector2(140, 140), 0.0, 0.0, 28)
	_polys[key] = p
	return p


static func zone_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	for id in ZONE_ORDER:
		if Geometry2D.is_point_in_polygon(p, zone_polygon(id)):
			return id
	return ""


static func zone_center(id: String) -> Vector2:
	return ZONE_CENTERS.get(id, Vector2.ZERO)


## Desierto como polígonos (radar y mapa).
static func desert_polygons() -> Array:
	var out: Array = []
	for d in DESERT:
		out.append(ellipse_poly(d[0], d[1] * 0.92, 5.0, 0.08, 36))
	return out


static func canals() -> Array:
	ensure()
	return _canals


static func _build_canals() -> void:
	# Canales de Bahía Solana: por el centro de las manzanas, cortados en cada calle.
	_canals.clear()
	var c: Dictionary = CITIES["bahia_solana"]
	var r: Rect2 = c["rect"]
	var blk: float = c["block"]
	var cx := ZONE_CENTERS["bahia_solana"] as Vector2
	var xs := _grid_lines(r.position.x, r.end.x, cx.x, blk)
	var zs := _grid_lines(r.position.y, r.end.y, cx.y, blk)
	for i in range(xs.size() - 1):
		if i % 2 == 1:
			continue
		var mx: float = (xs[i] + xs[i + 1]) * 0.5
		for j in range(zs.size() - 1):
			if j < 2:
				continue
			_canals.append(Rect2(mx - 11.0, zs[j] + 8.0, 22.0, zs[j + 1] - zs[j] - 16.0))


## Líneas de una cuadrícula que pasa por `center` con paso `step`, dentro de [a, b].
static func _grid_lines(a: float, b: float, center: float, step: float) -> Array:
	var out: Array = []
	var k := ceilf((a - center) / step)
	var v := center + k * step
	while v <= b + 0.01:
		out.append(v)
		v += step
	return out


# ------------------------------------------------------------- distancia a costa

static func _build_coast_grid() -> void:
	_cw = int(ceil(RECT.size.x / COAST_RES)) + 1
	_ch = int(ceil(RECT.size.y / COAST_RES)) + 1
	var n := _cw * _ch
	var land := PackedByteArray()
	land.resize(n)
	land.fill(0)
	for poly in land_polygons():
		_scan_fill(land, poly, 1)
	for poly in water_polygons():
		_scan_fill(land, poly, 0)
	# Transformada de distancia (chamfer 3-4) sembrada en la frontera tierra/agua.
	var big := 1.0e9
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(big)
	for j in _ch:
		for i in _cw:
			var k := j * _cw + i
			var v := land[k]
			if (i > 0 and land[k - 1] != v) or (i < _cw - 1 and land[k + 1] != v) or (j > 0 and land[k - _cw] != v) or (j < _ch - 1 and land[k + _cw] != v):
				dist[k] = 0.5
	var d1 := 1.0
	var d2 := 1.4142
	for j in _ch:
		for i in _cw:
			var k := j * _cw + i
			var m := dist[k]
			if i > 0:
				m = minf(m, dist[k - 1] + d1)
			if j > 0:
				m = minf(m, dist[k - _cw] + d1)
				if i > 0:
					m = minf(m, dist[k - _cw - 1] + d2)
				if i < _cw - 1:
					m = minf(m, dist[k - _cw + 1] + d2)
			dist[k] = m
	for j in range(_ch - 1, -1, -1):
		for i in range(_cw - 1, -1, -1):
			var k := j * _cw + i
			var m := dist[k]
			if i < _cw - 1:
				m = minf(m, dist[k + 1] + d1)
			if j < _ch - 1:
				m = minf(m, dist[k + _cw] + d1)
				if i < _cw - 1:
					m = minf(m, dist[k + _cw + 1] + d2)
				if i > 0:
					m = minf(m, dist[k + _cw - 1] + d2)
			dist[k] = m
	_coast.resize(n)
	for k in n:
		_coast[k] = dist[k] * COAST_RES * (1.0 if land[k] == 1 else -1.0)


static func _scan_fill(mask: PackedByteArray, poly: PackedVector2Array, value: int) -> void:
	var m := poly.size()
	for j in _ch:
		var z := RECT.position.y + j * COAST_RES
		var xs: Array = []
		for e in m:
			var a := poly[e]
			var b := poly[(e + 1) % m]
			if (a.y <= z) != (b.y <= z):
				xs.append(a.x + (z - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		var q := 0
		while q + 1 < xs.size():
			var i0 := int(ceil((float(xs[q]) - RECT.position.x) / COAST_RES))
			var i1 := int(floor((float(xs[q + 1]) - RECT.position.x) / COAST_RES))
			for i in range(maxi(i0, 0), mini(i1, _cw - 1) + 1):
				mask[j * _cw + i] = value
			q += 2


## Distancia con signo a la costa (m): positiva en tierra, negativa en el agua.
static func coast_distance(x: float, z: float) -> float:
	ensure()
	var fx := (x - RECT.position.x) / COAST_RES
	var fz := (z - RECT.position.y) / COAST_RES
	if fx < 0.0 or fz < 0.0 or fx >= _cw - 1 or fz >= _ch - 1:
		return -2000.0
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * _cw + i
	var a := lerpf(_coast[k], _coast[k + 1], tx)
	var b := lerpf(_coast[k + _cw], _coast[k + _cw + 1], tx)
	return lerpf(a, b, tz)


# ---------------------------------------------------------------- carreteras

static func _build_road_geometry() -> void:
	_roads.clear()
	for r in ROADS:
		var ctrl: Array = r["pts"]
		var pts := _spline(ctrl, 20.0)
		_roads.append({"id": r["id"], "name": r["name"], "w": r["w"], "main": r.get("main", false),
			"level": r.get("level", null), "clear": r.get("clear", 7.0), "ctrl": ctrl, "pts": pts,
			"h": PackedFloat32Array(), "bridge": PackedByteArray()})
	# Índice espacial provisional (sin alturas) para suavizar mesas junto a las carreteras.
	_sa.clear(); _sb.clear(); _sw.clear(); _sha.clear(); _shb.clear(); _sbridge.clear(); _sroad.clear()
	for ri in _roads.size():
		var rd: Dictionary = _roads[ri]
		var pts: PackedVector2Array = rd["pts"]
		for i in range(pts.size() - 1):
			_sa.append(pts[i])
			_sb.append(pts[i + 1])
			_sw.append(float(rd["w"]))
			_sha.append(0.0)
			_shb.append(0.0)
			_sbridge.append(0)
			_sroad.append(ri)
	_hash.clear()
	for s in _sa.size():
		var lo := _sa[s].min(_sb[s]) - Vector2.ONE * (_sw[s] * 0.5 + 60.0)
		var hi := _sa[s].max(_sb[s]) + Vector2.ONE * (_sw[s] * 0.5 + 60.0)
		for cx in range(int(floor(lo.x / 128.0)), int(floor(hi.x / 128.0)) + 1):
			for cz in range(int(floor(lo.y / 128.0)), int(floor(hi.y / 128.0)) + 1):
				var key := Vector2i(cx, cz)
				if not _hash.has(key):
					_hash[key] = PackedInt32Array()
				var arr: PackedInt32Array = _hash[key]
				arr.append(s)
				_hash[key] = arr


## Interpola una curva suave por los puntos de control (pasa por todos) cada `step` m.
static func _spline(ctrl: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	var t := PackedFloat32Array()
	t.append(0.0)
	for i in range(1, n):
		t.append(t[i - 1] + (ctrl[i] as Vector2).distance_to(ctrl[i - 1]))
	for i in range(n - 1):
		var a: Vector2 = ctrl[i]
		var b: Vector2 = ctrl[i + 1]
		var pre: Vector2 = ctrl[i - 1] if i > 0 else a - (b - a)
		var post: Vector2 = ctrl[i + 2] if i + 2 < n else b + (b - a)
		var pre_t: float = t[i - 1] - t[i] if i > 0 else -(t[i + 1] - t[i])
		var post_t: float = t[i + 2] - t[i] if i + 2 < n else 2.0 * (t[i + 1] - t[i])
		var seg := t[i + 1] - t[i]
		var steps := maxi(1, int(ceil(seg / step)))
		for k in steps:
			var w := float(k) / steps
			out.append(a.cubic_interpolate_in_time(b, pre, post, w, seg, pre_t, post_t))
	out.append(ctrl[n - 1])
	return out


static func _build_road_profiles() -> void:
	var ds := 20.0
	for ri in _roads.size():
		var rd: Dictionary = _roads[ri]
		var pts: PackedVector2Array = rd["pts"]
		var n := pts.size()
		var nat := PackedFloat32Array()
		var water := PackedByteArray()
		for p in pts:
			var h := natural_height(p.x, p.y)
			nat.append(h)
			water.append(1 if h < SEA + 0.25 else 0)
		# Junto al puente de Veyra (Westbrook) ya hay puente: no es agua para la carretera.
		for i in n:
			if absf(pts[i].y) < 30.0 and pts[i].x > 300.0 and pts[i].x < 440.0:
				water[i] = 0
				nat[i] = 0.0
		var h := PackedFloat32Array()
		h.resize(n)
		if rd["level"] != null:
			h.fill(float(rd["level"]))
		else:
			# Media móvil de la cota natural en tierra (±140 m).
			for i in n:
				var acc := 0.0
				var wsum := 0.0
				for k in range(maxi(0, i - 7), mini(n, i + 8)):
					if water[k] == 1:
						continue
					var wk := 1.0 - absf(k - i) / 8.0
					acc += maxf(nat[k], 0.3) * wk
					wsum += wk
				h[i] = acc / wsum if wsum > 0.0 else 0.5
			# Puentes: tablero entre los dos estribos, con gálibo mínimo.
			var clear: float = rd["clear"]
			var i := 0
			while i < n:
				if water[i] == 0:
					i += 1
					continue
				var j := i
				while j < n and water[j] == 1:
					j += 1
				var ha := h[i - 1] if i > 0 else SEA + clear
				var hb := h[j] if j < n else ha
				var deck := maxf(maxf(ha, hb), SEA + clear)
				for k in range(i, j):
					h[k] = deck
				i = j
			# Pendiente máxima (rampas de acceso a los puentes).
			var g := 0.075 * ds
			for k in range(1, n):
				h[k] = maxf(h[k], h[k - 1] - g)
			for k in range(n - 2, -1, -1):
				h[k] = maxf(h[k], h[k + 1] - g)
		rd["h"] = h
		rd["bridge"] = water
	# Alturas de los segmentos.
	var s := 0
	for ri in _roads.size():
		var rd: Dictionary = _roads[ri]
		var h: PackedFloat32Array = rd["h"]
		var br: PackedByteArray = rd["bridge"]
		for i in range(h.size() - 1):
			_sha[s] = h[i]
			_shb[s] = h[i + 1]
			_sbridge[s] = 1 if (br[i] == 1 or br[i + 1] == 1) else 0
			s += 1
	# Ajuste de cruces: el final de una carretera toma la cota de la carretera en la que muere.
	for ri in _roads.size():
		var rd: Dictionary = _roads[ri]
		if rd["level"] != null:
			continue
		var pts: PackedVector2Array = rd["pts"]
		var h: PackedFloat32Array = rd["h"]
		for end_i in [0, pts.size() - 1]:
			var q := _nearest_segment(pts[end_i], ri)
			if q.x >= 0 and q.y < 2.0:
				var target := q.z
				var n := pts.size()
				for k in range(n):
					var idx: int = end_i + k if end_i == 0 else end_i - k
					var dist := k * ds
					if dist > 200.0:
						break
					h[idx] = lerpf(target, h[idx], smoothstep(0.0, 200.0, dist))
		rd["h"] = h
	s = 0
	for ri in _roads.size():
		var h: PackedFloat32Array = _roads[ri]["h"]
		for i in range(h.size() - 1):
			_sha[s] = h[i]
			_shb[s] = h[i + 1]
			s += 1


## Segmento más cercano de otra carretera: Vector3(índice, distancia, cota).
static func _nearest_segment(p: Vector2, skip_road: int) -> Vector3:
	var key := Vector2i(int(floor(p.x / 128.0)), int(floor(p.y / 128.0)))
	if not _hash.has(key):
		return Vector3(-1, INF, 0)
	var best := Vector3(-1, INF, 0)
	for s in (_hash[key] as PackedInt32Array):
		if _sroad[s] == skip_road:
			continue
		var a := _sa[s]
		var ab := _sb[s] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(p)
		if d < best.y:
			best = Vector3(s, d, lerpf(_sha[s], _shb[s], t))
	return best


## Carreteras ya calculadas: [{id, name, w, main, pts, h, bridge}].
static func roads() -> Array:
	ensure()
	return _roads


static func road(id: String) -> Dictionary:
	for r in roads():
		if r["id"] == id:
			return r
	return {}


## Distancia a la carretera más cercana y su cota: Vector3(distancia, cota, semiancho).
## Los puentes solo cuentan si `include_bridges`.
static func road_query(x: float, z: float, include_bridges: bool = false) -> Vector3:
	var key := Vector2i(int(floor(x / 128.0)), int(floor(z / 128.0)))
	var arr = _hash.get(key)
	if arr == null:
		return Vector3(INF, 0.0, 0.0)
	var best_d := INF
	var best_h := 0.0
	var best_w := 0.0
	var p := Vector2(x, z)
	for s in (arr as PackedInt32Array):
		if not include_bridges and _sbridge[s] == 1:
			continue
		var a := _sa[s]
		var ab := _sb[s] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(p) - _sw[s] * 0.5
		if d < best_d:
			best_d = d
			best_h = lerpf(_sha[s], _shb[s], t)
			best_w = _sw[s] * 0.5
	return Vector3(best_d, best_h, best_w)


# --------------------------------------------------------------------- relieve

static func _soft_ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	var q := Vector2((p.x - c.x) / r.x, (p.y - c.y) / r.y).length()
	return 1.0 - smoothstep(0.55, 1.0, q)


static func desert_mask(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var m := 0.0
	for d in DESERT:
		m = maxf(m, _soft_ellipse(p, d[0], d[1]))
	return m


static func _mountain_mask(x: float, z: float) -> float:
	return smoothstep(-2250.0, -2950.0, z) * smoothstep(150.0, 800.0, x) * (1.0 - smoothstep(3900.0, 4500.0, x))


static func _flat_mask(x: float, z: float) -> Vector2:
	# Vector2(peso, cota) de la zona llana más influyente.
	var best := Vector2(0.0, 0.0)
	for f in _flats:
		var r: Rect2 = f[0]
		var blend: float = f[2]
		var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		if d >= blend:
			continue
		var w := 1.0 - smoothstep(0.0, blend, d)
		if w > best.x:
			best = Vector2(w, float(f[1]))
	return best


## Altura del terreno sin aplanar bajo las carreteras (ciudades sí aplanadas).
static func natural_height(x: float, z: float) -> float:
	return _eval(x, z, false, null)


## Altura final del terreno en (x, z): llano en Westbrook, ciudades y carreteras.
static func height_at(x: float, z: float) -> float:
	ensure()
	return _eval(x, z, true, null)


## Altura y biomas: [altura, Color(r desierto, g bosque, b arena, a ciudad)].
static func sample_full(x: float, z: float) -> Array:
	ensure()
	var out: Array = [Color()]
	var h := _eval(x, z, true, out)
	return [h, out[0]]


static func _eval(x: float, z: float, with_roads: bool, out) -> float:
	# Westbrook: suelo propio (la playa sigue su perfil).
	if x >= WB_HOLE.position.x and x <= WB_HOLE.end.x and z >= WB_HOLE.position.y and z <= WB_HOLE.end.y:
		if out != null:
			out[0] = Color(0, 0, 1.0 if x < CityLayout.BEACH_EAST else 0.0, 1.0)
		return _wb_sand(x) - 0.06 if x < CityLayout.BEACH_EAST else -0.06
	# Río de Veyra (canal de hormigón).
	if x > CityLayout.RIVER_X0 - 1.0 and x < CityLayout.RIVER_X1 + 1.0 and z > RIVER_Z0 and z < RIVER_Z1:
		if out != null:
			out[0] = Color(0, 0, 0, 1)
		return -6.0
	# Canales de Bahía Solana.
	for c in _canals:
		var cr: Rect2 = c
		if x > cr.position.x and x < cr.end.x and z > cr.position.y and z < cr.end.y:
			if out != null:
				out[0] = Color(0, 0, 0, 1)
			return -3.0
	var d := coast_distance(x, z)
	var fm := _flat_mask(x, z)
	# Costa irregular, salvo en las zonas urbanas (playa y puerto rectos).
	d += _n_coast.get_noise_2d(x, z) * 40.0 * (1.0 - fm.x)
	# Playa de Westbrook prolongada hacia el norte y el sur.
	var wb_beach := 0.0
	if x > -600.0 and x < -150.0 and z > -760.0 and z < 760.0:
		wb_beach = (1.0 - smoothstep(300.0, 700.0, absf(z))) * (1.0 - smoothstep(-260.0, -150.0, x))
	var des := desert_mask(x, z)
	if d < 0.0:
		var h := SEA - 1.6 * smoothstep(0.0, 30.0, -d) - 20.0 * smoothstep(30.0, 420.0, -d)
		# Arrecifes y aguas turquesa alrededor de las islas.
		var reef := 0.0
		for id in ISLANDS:
			var isl: Dictionary = ISLANDS[id]
			reef = maxf(reef, _soft_ellipse(Vector2(x, z), isl["c"], (isl["r"] as Vector2) + Vector2(330, 330)))
		if reef > 0.0:
			var reef_h := SEA - 1.3 - 1.6 * (_n_detail.get_noise_2d(x, z) * 0.5 + 0.5)
			h = lerpf(h, maxf(h, reef_h), reef)
		if wb_beach > 0.0:
			h = lerpf(h, _wb_sand(x), wb_beach)
		if out != null:
			out[0] = Color(des, 0.0, 1.0, 0.0)
		return h
	var beach := SEA + 2.0 * smoothstep(0.0, 45.0, d)
	var coastk := smoothstep(25.0, 260.0, d)
	var p := Vector2(x, z)
	var rq := road_query(x, z) if _hash.size() > 0 else Vector3(INF, 0, 0)
	# Colinas suaves por todas partes, más fuertes en las sierras.
	var hill_amp := 14.0
	var forest := 0.0
	for hl in HILLS:
		var m := _soft_ellipse(p, hl[0], hl[1])
		if m > 0.0:
			hill_amp += float(hl[2]) * m
			forest = maxf(forest, m)
	# Junto a la autopista del desierto el terreno es llano (cinemática del autobús).
	var hw_band := 1.0
	if x > 200.0 and x < 4400.0:
		hw_band = smoothstep(60.0, 520.0, absf(z))
	var n1 := _n_hills.get_noise_2d(x, z) * 0.5 + 0.5
	var relief := n1 * hill_amp * hw_band
	# Montañas nevadas del norte.
	var mm := _mountain_mask(x, z)
	if mm > 0.0:
		var rr := _n_mtn.get_noise_2d(x, z) * 0.5 + 0.5
		relief += mm * (90.0 + 470.0 * rr * rr)
		forest = maxf(forest, mm * (1.0 - smoothstep(-2500.0, -2800.0, z)))
	# Desierto de Las Brisas: meseta, mesas de paredes verticales y cañones.
	if des > 0.0:
		var plateau := 24.0 * smoothstep(-350.0, -1000.0, z)
		var nm := _n_mesa.get_noise_2d(x, z)
		var away := smoothstep(30.0, 140.0, rq.x)
		var mesa := smoothstep(0.30, 0.355, nm) * (42.0 + 26.0 * (_n_detail.get_noise_2d(x * 0.2, z * 0.2) * 0.5 + 0.5))
		mesa += smoothstep(0.52, 0.56, nm) * 22.0
		var canyon := (1.0 - smoothstep(0.0, 0.035, absf(_n_mesa.get_noise_2d(x * 0.7 + 900.0, z * 0.7)))) * 14.0
		var dunes := (_n_detail.get_noise_2d(x, z) * 0.5 + 0.5) * 2.5
		var des_h := plateau + (mesa * away - canyon * away) * (0.3 + 0.7 * smoothstep(-200.0, -700.0, z) * hw_band) + dunes
		des_h = maxf(des_h, plateau * 0.4)
		relief = lerpf(relief, des_h, des)
		forest *= 1.0 - des
	# Colinas de las islas.
	var urban := 0.0
	for id in ISLANDS:
		var isl: Dictionary = ISLANDS[id]
		var rad: Vector2 = isl["r"]
		var q := Vector2((x - isl["c"].x) / rad.x, (z - isl["c"].y) / rad.y).length()
		if q < 1.3:
			relief += float(isl["hill"]) * exp(-q * q * 3.2)
			forest = maxf(forest, (1.0 - q) * 0.9)
	var h := beach + relief * coastk
	# Aplanado de ciudades y zonas urbanas.
	if fm.x > 0.0:
		var target := lerpf(SEA, fm.y, smoothstep(0.0, 22.0, d))
		h = lerpf(h, target, fm.x)
		urban = fm.x
		forest *= 1.0 - fm.x
	if wb_beach > 0.0:
		h = lerpf(h, _wb_sand(x), wb_beach)
	# Carreteras: el terreno se aplana bajo la calzada.
	if with_roads and rq.x < 40.0:
		var k := 1.0 - smoothstep(1.5, 40.0, rq.x)
		h = lerpf(h, rq.y - 0.04, k)
	if out != null:
		var sand := (1.0 - smoothstep(15.0, 55.0, d)) * (1.0 - urban * 0.7)
		sand = maxf(sand, wb_beach)
		out[0] = Color(des, clampf(forest, 0.0, 1.0), sand, urban)
	return h


static func _wb_sand(x: float) -> float:
	var t := (CityLayout.BEACH_EAST - x) / (CityLayout.BEACH_EAST - CityLayout.SHORE_X)
	return lerpf(0.0, SEA - 0.05, t) if t <= 1.0 else SEA - 0.05 - (t - 1.0) * 1.5


# --------------------------------------------------------------- rejilla gruesa

static func grid_size() -> Vector2i:
	return Vector2i(int(RECT.size.x / GRID_RES) + 1, int(RECT.size.y / GRID_RES) + 1)


## Calcula (una vez) la rejilla gruesa de alturas y biomas. Lenta: llamar desde un hilo.
static func build_grid() -> void:
	ensure()
	if _grid_ready:
		return
	var gs := grid_size()
	var hh := PackedFloat32Array()
	var bb := PackedColorArray()
	hh.resize(gs.x * gs.y)
	bb.resize(gs.x * gs.y)
	var out: Array = [Color()]
	for j in gs.y:
		for i in gs.x:
			var x := RECT.position.x + i * GRID_RES
			var z := RECT.position.y + j * GRID_RES
			hh[j * gs.x + i] = _eval(x, z, true, out)
			bb[j * gs.x + i] = out[0]
	_grid_h = hh
	_grid_b = bb
	_grid_ready = true


static func grid_ready() -> bool:
	return _grid_ready


static func grid_heights() -> PackedFloat32Array:
	return _grid_h


static func grid_biomes() -> PackedColorArray:
	return _grid_b


# --------------------------------------------------------------- red para la GPS

## Grafo de las carreteras del estado y de las cuadrículas de las ciudades:
## {nodes: Array[Vector2], links: Array[Array[int]]}. Se une a Westbrook por los
## extremos de las carreteras que coinciden con nodos de CityLayout.road_graph().
static func road_graph() -> Dictionary:
	ensure()
	var nodes: Array = []
	var links: Array = []
	var index := {}
	var add := func(p: Vector2) -> int:
		var key := Vector2i(roundi(p.x), roundi(p.y))
		if index.has(key):
			return index[key]
		nodes.append(p)
		links.append([])
		index[key] = nodes.size() - 1
		return nodes.size() - 1
	var link := func(a: int, b: int) -> void:
		if a == b:
			return
		if not (links[a] as Array).has(b):
			(links[a] as Array).append(b)
			(links[b] as Array).append(a)
	for rd in _roads:
		var pts: PackedVector2Array = rd["pts"]
		var ctrl: Array = rd["ctrl"]
		var prev := -1
		for i in pts.size():
			# Un punto de cada tres (≈ 60 m) más los puntos de control (cruces).
			var keep: bool = i == 0 or i == pts.size() - 1 or i % 3 == 0
			if not keep:
				for c in ctrl:
					if (c as Vector2).distance_to(pts[i]) < 0.5:
						keep = true
						break
			if not keep:
				continue
			var k: int = add.call(pts[i])
			if prev >= 0:
				link.call(prev, k)
			prev = k
	var grid_nodes: Array = []
	for id in CITIES:
		var g := city_grid(id)
		var xs: Array = g["xs"]
		var zs: Array = g["zs"]
		var ids := {}
		for x in xs:
			for z in zs:
				ids[Vector2(x, z)] = add.call(Vector2(x, z))
				grid_nodes.append(ids[Vector2(x, z)])
		for x in xs:
			for k in range(zs.size() - 1):
				link.call(ids[Vector2(x, zs[k])], ids[Vector2(x, zs[k + 1])])
		for z in zs:
			for k in range(xs.size() - 1):
				link.call(ids[Vector2(xs[k], z)], ids[Vector2(xs[k + 1], z)])
	# Las carreteras que entran en una ciudad se enganchan a su cruce más cercano.
	for rd in _roads:
		for p in rd["ctrl"]:
			var pk := Vector2i(roundi(p.x), roundi(p.y))
			if not index.has(pk):
				continue
			var best := -1
			var bd := 70.0
			for gi in grid_nodes:
				var d := (nodes[gi] as Vector2).distance_to(p)
				if d < bd:
					bd = d
					best = gi
			if best >= 0:
				link.call(index[pk], best)
	return {"nodes": nodes, "links": links}


## Cuadrícula de calles de una ciudad: {xs, zs, rect, level}. Pasa por el centro de la zona.
static func city_grid(id: String) -> Dictionary:
	var c: Dictionary = CITIES[id]
	var r: Rect2 = c["rect"]
	var center: Vector2 = ZONE_CENTERS.get(String(c["zone"]), r.get_center())
	if id == "sv_centro" or not r.has_point(center):
		center = Vector2(620, r.get_center().y) if id == "sv_centro" else r.get_center()
	var blk: float = c["block"]
	return {"xs": _grid_lines(r.position.x, r.end.x, center.x, blk), "zs": _grid_lines(r.position.y, r.end.y, center.y, blk), "rect": r, "level": c["level"]}


# ------------------------------------------------------------------ mapa raster

## Mapa de relieve del estado (colores tipo atlas con sombreado) a partir de la rejilla
## gruesa. `scale` = píxeles por celda (se reescala con filtro bilineal).
static func make_map_image(scale: int = 3) -> Image:
	build_grid()
	var gs := grid_size()
	var img := Image.create(gs.x, gs.y, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	for j in gs.y:
		for i in gs.x:
			var k := j * gs.x + i
			var h := _grid_h[k]
			var b := _grid_b[k]
			var col: Color
			if h < SEA - 0.05:
				var depth := clampf((SEA - h) / 18.0, 0.0, 1.0)
				col = Color(0.36, 0.78, 0.80).lerp(Color(0.07, 0.25, 0.42), sqrt(depth))
			else:
				var grass := Color(0.36, 0.52, 0.25).lerp(Color(0.48, 0.55, 0.30), clampf(h / 120.0, 0.0, 1.0))
				col = grass.lerp(Color(0.18, 0.36, 0.17), b.g * 0.85)
				col = col.lerp(Color(0.80, 0.47, 0.30), b.r)
				col = col.lerp(Color(0.90, 0.84, 0.64), b.b * 0.9)
				col = col.lerp(Color(0.62, 0.62, 0.60), b.a * 0.55)
				if h > 230.0:
					col = col.lerp(Color(0.95, 0.96, 0.98), smoothstep(230.0, 320.0, h))
				# Sombreado del relieve.
				var hx := _grid_h[k + 1] - _grid_h[k - 1] if i > 0 and i < gs.x - 1 else 0.0
				var hz := _grid_h[k + gs.x] - _grid_h[k - gs.x] if j > 0 and j < gs.y - 1 else 0.0
				var n := Vector3(-hx, 2.0 * GRID_RES, -hz).normalized()
				var shade := clampf(n.dot(light) * 1.25, 0.35, 1.25)
				col = Color(col.r * shade, col.g * shade, col.b * shade)
			img.set_pixel(i, j, col)
	if scale > 1:
		img.resize(gs.x * scale, gs.y * scale, Image.INTERPOLATE_CUBIC)
	return img


## Píxel del mapa raster -> mundo y viceversa (normalizado 0..1 sobre RECT).
static func world_to_uv(p: Vector2) -> Vector2:
	return (p - RECT.position) / RECT.size


static func uv_to_world(uv: Vector2) -> Vector2:
	return RECT.position + uv * RECT.size
