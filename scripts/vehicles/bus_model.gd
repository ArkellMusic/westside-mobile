class_name BusModel
extends RefCounted
## Autobús de línea para la cinemática de apertura. Carcasa abierta (ventanas
## de cristal y paredes de doble cara) para poder rodar planos desde dentro.
## Frente hacia +Z, largo 12 m.

const LENGTH := 12.0
const WIDTH := 2.55
const HEIGHT := 3.2
const SEAT_LEFT_X := -0.75   # pasillo en x = 0
const WINDOW_BOTTOM := 1.25
const WINDOW_TOP := 2.45


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Bus"
	var b := MeshBuilder.new()
	var shell := MeshBuilder.material(Color(0.92, 0.92, 0.9), 0.45, 0.2)
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var stripe := MeshBuilder.material(Color(0.12, 0.42, 0.7), 0.5)
	stripe.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inner := MeshBuilder.material(Color(0.22, 0.23, 0.26), 0.9)
	inner.cull_mode = BaseMaterial3D.CULL_DISABLED
	var seat := MeshBuilder.material(Color(0.12, 0.17, 0.32), 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.32, 0.38, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tire := MeshBuilder.material(Color(0.04, 0.04, 0.045), 0.95)
	var head := MeshBuilder.material(Color(1, 0.97, 0.88), 0.2, 0.0, Color(1.0, 0.95, 0.8), 3.0)
	var tail := MeshBuilder.material(Color(0.7, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03), 2.0)
	var sign_mat := MeshBuilder.material(Color(0.1, 0.06, 0.0), 0.3, 0.0, Color(1.0, 0.6, 0.1), 2.5)
	b.surface("shell", shell).surface("stripe", stripe).surface("inner", inner).surface("seat", seat).surface("glass", glass)
	b.surface("tire", tire).surface("head", head).surface("tail", tail).surface("sign", sign_mat)
	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	var floor_y := 0.75
	# Laterales: zócalo, franja de ventanas (pilares) y friso superior.
	for sx in [-1.0, 1.0]:
		var x: float = sx * hw
		b.box("shell", Vector3(x, (0.45 + WINDOW_BOTTOM) * 0.5, 0), Vector3(0.06, WINDOW_BOTTOM - 0.45, LENGTH))
		b.box("stripe", Vector3(x * 1.002, 0.95, 0), Vector3(0.065, 0.25, LENGTH))
		b.box("shell", Vector3(x, (WINDOW_TOP + HEIGHT) * 0.5, 0), Vector3(0.06, HEIGHT - WINDOW_TOP, LENGTH))
		b.box("glass", Vector3(x, (WINDOW_BOTTOM + WINDOW_TOP) * 0.5, 0), Vector3(0.03, WINDOW_TOP - WINDOW_BOTTOM, LENGTH - 0.4))
		var z := -hl + 0.3
		while z < hl - 1.6:
			b.box("shell", Vector3(x, (WINDOW_BOTTOM + WINDOW_TOP) * 0.5, z), Vector3(0.08, WINDOW_TOP - WINDOW_BOTTOM, 0.18))
			z += 1.55
	b.box("shell", Vector3(0, HEIGHT, 0), Vector3(WIDTH, 0.08, LENGTH))
	b.box("inner", Vector3(0, floor_y, 0), Vector3(WIDTH - 0.1, 0.06, LENGTH - 0.2))
	b.box("inner", Vector3(0, HEIGHT - 0.06, 0), Vector3(WIDTH - 0.14, 0.04, LENGTH - 0.3))
	# Frontal con parabrisas y trasera.
	b.box("shell", Vector3(0, 0.8, hl), Vector3(WIDTH, 1.1, 0.08))
	b.box("glass", Vector3(0, 2.05, hl), Vector3(WIDTH - 0.1, 1.4, 0.04))
	b.box("sign", Vector3(0, 2.95, hl + 0.02), Vector3(1.9, 0.32, 0.04))
	b.box("shell", Vector3(0, HEIGHT * 0.5 + 0.2, -hl), Vector3(WIDTH, HEIGHT - 0.4, 0.08))
	b.box("shell", Vector3(0, 0.45, 0), Vector3(WIDTH, 0.5, LENGTH))
	for sx in [-1.0, 1.0]:
		b.box("head", Vector3(sx * (hw - 0.3), 0.75, hl + 0.03), Vector3(0.4, 0.18, 0.04))
		b.box("tail", Vector3(sx * (hw - 0.25), 0.9, -hl - 0.03), Vector3(0.25, 0.35, 0.04))
	# Asientos a ambos lados del pasillo.
	var sz := -hl + 1.2
	while sz < hl - 2.2:
		for side in [-1.0, 1.0]:
			var cx: float = side * 0.75
			b.box("seat", Vector3(cx, floor_y + 0.45, sz), Vector3(0.95, 0.12, 0.5))
			b.box("seat", Vector3(cx, floor_y + 0.85, sz + 0.28), Vector3(0.95, 0.75, 0.1))
		sz += 1.0
	for z in [-hl + 2.2, hl - 2.6]:
		for sx in [-1.0, 1.0]:
			b.cylinder("tire", Vector3.ZERO, 0.5, 0.5, 0.32, 14, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(sx * (hw - 0.18) - 0.16, 0.5, z)))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	root.add_child(mi)
	var label := Label3D.new()
	label.text = "WESTBROOK"
	label.font_size = 64
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.7, 0.2)
	label.position = Vector3(0, 2.95, hl + 0.05)
	root.add_child(label)
	return root


## Posición local del asiento de ventanilla (lado izquierdo, mitad del bus).
static func window_seat() -> Vector3:
	return Vector3(-0.95, 0.75 + 0.05, 0.6)
