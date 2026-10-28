class_name CarModel
extends RefCounted
## Modelos de coche procedurales (sin marcas reales). El frente mira a +Z,
## que es el "adelante" de VehicleBody3D.
## Estilos: 0 sedán, 1 coupé clásico, 2 SUV, 3 pickup.

const STYLE_NAMES := ["Veyra Sedan", "Westbrook Classic", "Canyon SUV", "Hauler Pickup"]

const PROFILES := {
	0: {
		"lower": [Vector2(-2.3, 0.30), Vector2(2.3, 0.30), Vector2(2.36, 0.52), Vector2(2.28, 0.74), Vector2(1.05, 0.86), Vector2(-1.45, 0.88), Vector2(-2.28, 0.84), Vector2(-2.36, 0.58)],
		"cabin": [Vector2(1.05, 0.86), Vector2(0.25, 1.36), Vector2(-0.95, 1.38), Vector2(-1.5, 0.88)],
		"roof": [Vector2(0.30, 1.33), Vector2(-1.0, 1.35), Vector2(-0.98, 1.43), Vector2(0.25, 1.41)],
		"half_w": 0.95, "cabin_w": 0.80, "wheel_r": 0.36, "wheel_z": 1.42, "track": 0.82, "length": 4.7, "height": 1.45,
	},
	1: {
		"lower": [Vector2(-2.3, 0.32), Vector2(2.35, 0.32), Vector2(2.42, 0.55), Vector2(2.35, 0.78), Vector2(0.75, 0.88), Vector2(-1.6, 0.88), Vector2(-2.3, 0.86), Vector2(-2.4, 0.6)],
		"cabin": [Vector2(0.75, 0.88), Vector2(0.0, 1.28), Vector2(-1.0, 1.28), Vector2(-1.65, 0.88)],
		"roof": [Vector2(0.05, 1.26), Vector2(-1.05, 1.26), Vector2(-1.03, 1.33), Vector2(0.0, 1.33)],
		"half_w": 0.97, "cabin_w": 0.80, "wheel_r": 0.37, "wheel_z": 1.48, "track": 0.84, "length": 4.8, "height": 1.35,
	},
	2: {
		"lower": [Vector2(-2.35, 0.42), Vector2(2.35, 0.42), Vector2(2.42, 0.72), Vector2(2.35, 1.0), Vector2(1.35, 1.12), Vector2(-2.35, 1.12), Vector2(-2.42, 0.75)],
		"cabin": [Vector2(1.35, 1.12), Vector2(0.75, 1.72), Vector2(-2.28, 1.74), Vector2(-2.34, 1.12)],
		"roof": [Vector2(0.8, 1.70), Vector2(-2.3, 1.72), Vector2(-2.28, 1.80), Vector2(0.76, 1.78)],
		"half_w": 1.0, "cabin_w": 0.86, "wheel_r": 0.42, "wheel_z": 1.5, "track": 0.86, "length": 4.85, "height": 1.8,
	},
	3: {
		"lower": [Vector2(-2.6, 0.44), Vector2(2.5, 0.44), Vector2(2.56, 0.72), Vector2(2.5, 1.0), Vector2(1.3, 1.08), Vector2(-2.6, 1.08), Vector2(-2.66, 0.72)],
		"cabin": [Vector2(1.3, 1.08), Vector2(0.75, 1.62), Vector2(-0.55, 1.64), Vector2(-0.62, 1.08)],
		"roof": [Vector2(0.78, 1.60), Vector2(-0.6, 1.62), Vector2(-0.6, 1.70), Vector2(0.74, 1.68)],
		"half_w": 1.0, "cabin_w": 0.86, "wheel_r": 0.42, "wheel_z": 1.65, "track": 0.86, "length": 5.3, "height": 1.7,
	},
}

static var _shared_materials: Dictionary = {}


static func spec(style: int) -> Dictionary:
	var base: Dictionary = PROFILES.get(style, PROFILES[0])
	var real_id := RealCarModel.for_style(style)
	if real_id == "":
		return base
	var d := RealCarModel.data(real_id)
	var out := base.duplicate()
	for k in ["half_w", "length", "height", "wheel_r", "track"]:
		out[k] = d[k]
	return out


static func _mats() -> Dictionary:
	if _shared_materials.is_empty():
		var body := MeshBuilder.material(Color.WHITE, 0.32, 0.35)
		body.clearcoat_enabled = true
		body.clearcoat = 0.6
		_shared_materials = {
			"body": body,
			"trim": MeshBuilder.material(Color(0.06, 0.06, 0.07), 0.6),
			"chrome": MeshBuilder.material(Color(0.75, 0.76, 0.78), 0.2, 0.9),
			"glass": MeshBuilder.material(Color(0.05, 0.07, 0.09), 0.05, 0.0),
			"tire": MeshBuilder.material(Color(0.04, 0.04, 0.045), 0.95),
			"rim": MeshBuilder.material(Color(0.62, 0.63, 0.66), 0.3, 0.8),
			"head": MeshBuilder.material(Color(1, 0.97, 0.88), 0.2, 0.0, Color(1.0, 0.95, 0.8), 2.0),
			"tail": MeshBuilder.material(Color(0.7, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03), 1.5),
		}
	return _shared_materials


## Carrocería (con o sin ruedas). body_color se aplica por color de vértice, así
## que un mismo material sirve para todos los coches y para MultiMesh.
static func build(style: int, body_color: Color, with_wheels: bool) -> ArrayMesh:
	# Si hay modelo real para este estilo, se usa (malla completa con ruedas).
	if with_wheels:
		var real_id := RealCarModel.for_style(style)
		if real_id != "":
			return RealCarModel.full_mesh(real_id, body_color)
	var s := spec(style)
	var m := _mats()
	var b := MeshBuilder.new()
	for k in ["body", "trim", "chrome", "glass", "tire", "rim", "head", "tail"]:
		b.surface(k, m[k])
	var hw: float = s["half_w"]
	var cw: float = s["cabin_w"]
	b.extrude("body", PackedVector2Array(s["lower"]), -hw, hw, Transform3D.IDENTITY, body_color)
	b.extrude("glass", PackedVector2Array(s["cabin"]), -cw, cw)
	b.extrude("body", PackedVector2Array(s["roof"]), -cw - 0.01, cw + 0.01, Transform3D.IDENTITY, body_color)
	var half_l: float = s["length"] * 0.5
	var lower: Array = s["lower"]
	var front_y: float = (lower[2] as Vector2).y
	# Parachoques, rejilla y bajos.
	b.box("trim", Vector3(0, 0.36, half_l - 0.02), Vector3(hw * 2.0 - 0.06, 0.18, 0.16))
	b.box("trim", Vector3(0, 0.36, -half_l + 0.02), Vector3(hw * 2.0 - 0.06, 0.18, 0.16))
	b.box("trim", Vector3(0, front_y + 0.02, half_l + 0.03), Vector3(hw * 0.9, 0.16, 0.05))
	b.box("trim", Vector3(0, 0.22, 0), Vector3(hw * 1.9, 0.12, s["length"] - 0.6))
	# Retrovisores.
	var cabin: Array = s["cabin"]
	var mirror_z: float = (cabin[0] as Vector2).x - 0.25
	for sx in [-1.0, 1.0]:
		b.box("trim", Vector3(sx * (hw + 0.08), (cabin[0] as Vector2).y + 0.12, mirror_z), Vector3(0.14, 0.1, 0.18))
	# Faros y pilotos.
	for sx in [-1.0, 1.0]:
		b.box("head", Vector3(sx * (hw - 0.28), front_y - 0.02, half_l + 0.04), Vector3(0.36, 0.12, 0.05))
		b.box("tail", Vector3(sx * (hw - 0.22), front_y + 0.04, -half_l - 0.04), Vector3(0.32, 0.12, 0.05))
	# Tiradores cromados.
	for sx in [-1.0, 1.0]:
		b.box("chrome", Vector3(sx * (hw + 0.005), (cabin[0] as Vector2).y - 0.12, 0.2), Vector3(0.02, 0.03, 0.18))
	if with_wheels:
		var r: float = s["wheel_r"]
		for sz in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				_add_wheel(b, Vector3(sx * float(s["track"]), r, sz * float(s["wheel_z"])), r, sx)
	return b.commit()


static func wheel_mesh(style: int) -> ArrayMesh:
	var s := spec(style)
	var m := _mats()
	var b := MeshBuilder.new()
	b.surface("tire", m["tire"]).surface("rim", m["rim"])
	_add_wheel(b, Vector3.ZERO, s["wheel_r"], 1.0)
	return b.commit()


static func _add_wheel(b: MeshBuilder, center: Vector3, r: float, side: float) -> void:
	var w := 0.26
	# Eje del cilindro: X (rotamos Y -> X).
	var xf := Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), center + Vector3(-w * 0.5, 0, 0))
	b.cylinder("tire", Vector3.ZERO, r, r, w, 14, xf)
	var rim_xf := Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), center + Vector3(side * w * 0.5 - 0.01 * side - (0.02 if side > 0 else -0.02), 0, 0))
	b.cylinder("rim", Vector3(0, -0.01, 0), r * 0.62, r * 0.55, 0.03, 10, rim_xf)
