class_name IntroCinematic
extends Node
## Cinemática de apertura: noche, autobús de línea cruzando el desierto, llamada
## de Big Ray, la foto vieja, amanecer sobre el puente y título WESTSIDE LEGACY.
## Termina con el autobús parado en la terminal de Westbrook (empieza la misión 01).

signal finished

var world: Node
var bus: Node3D
var mack: Humanoid
var phone_light: OmniLight3D
var _speed: float = 0.0
var _skip_all: bool = false

const CALL := [
	{"speaker": "Mack", "en": "Ray? It's three in the morning.", "es": "¿Ray? Son las tres de la mañana.", "t": 3.0},
	{"speaker": "Big Ray", "en": "And you've gone eight years without picking up my calls at any hour. Tonight you're gonna listen.", "es": "Y tú llevas ocho años sin cogerme el teléfono a ninguna hora. Hoy me vas a escuchar.", "t": 5.0},
	{"speaker": "Mack", "en": "What happened?", "es": "¿Qué ha pasado?", "t": 2.0},
	{"speaker": "Big Ray", "en": "Your mama's house. A letter came from a bank nobody's ever heard of. Says there's a debt in her name. Thirty days, Mack. Then they auction it.", "es": "La casa de tu madre. Ha llegado una carta de un banco del que nadie ha oído hablar. Dicen que hay una deuda a su nombre. Treinta días, Mack. Luego la subastan.", "t": 7.5},
	{"speaker": "Mack", "en": "My mother didn't owe nobody nothing.", "es": "Mi madre no le debía nada a nadie.", "t": 3.0},
	{"speaker": "Big Ray", "en": "I know. And it ain't just your house. They're buying up half of Westbrook. The corner store, the Vargas garage... Whoever won't sell, things happen to them.", "es": "Ya lo sé. Y no es solo tu casa. Están comprando media Westbrook: la tienda de la esquina, el taller de los Vargas… Al que no vende, le pasan cosas.", "t": 7.5},
	{"speaker": "Mack", "en": "What things?", "es": "¿Qué cosas?", "t": 2.0},
	{"speaker": "Big Ray", "en": "Things. Last month a warehouse burned on Ninth Street. Nobody saw nothing. In Westbrook nobody ever sees nothing.", "es": "Cosas. El mes pasado ardió un almacén en la calle Nueve. Nadie vio nada. En Westbrook nadie ve nunca nada.", "t": 6.0},
	{"speaker": "Mack", "en": "...And Dre?", "es": "…¿Y Dre?", "t": 2.2},
	{"speaker": "Big Ray", "en": "Dre's still here. And he still don't wanna hear your name. But this is about him too.", "es": "Dre sigue aquí. Y sigue sin querer oír tu nombre. Pero esto también va con él.", "t": 5.0},
	{"speaker": "Mack", "en": "Ray, I left so I'd never come back.", "es": "Ray, yo me fui para no volver.", "t": 3.0},
	{"speaker": "Big Ray", "en": "I know. That's why I'm calling you and not the cops. The house papers are in your name. You don't come, you lose it. And with it, what little's left of your mama in this neighborhood.", "es": "Lo sé. Por eso te llamo a ti y no a la policía. Los papeles de la casa están a tu nombre. Si no vienes, la pierdes. Y con ella, lo poco que queda de tu madre en este barrio.", "t": 8.0},
	{"speaker": "Mack", "en": "...I'll catch a bus tomorrow.", "es": "…Mañana cojo un autobús.", "t": 3.0},
	{"speaker": "Big Ray", "en": "You're already on one. I know you, kid. I'll pick you up at Westbrook terminal. And don't be late... again.", "es": "Ya vas en uno. Te conozco, chaval. Te recojo en la terminal de Westbrook. Y no llegues tarde… otra vez.", "t": 6.5},
]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_skip_all = true


func _process(delta: float) -> void:
	if bus and is_instance_valid(bus):
		bus.global_position += bus.global_basis.z * _speed * delta


func run() -> void:
	var hud: HUD = world.hud
	world.set_gameplay(false)
	world.player.visible = false
	hud.fade_to(1.0, 0.01)
	hud.set_letterbox(true)
	world.sky.apply_preset("night_desert", 0.0)
	bus = BusModel.build()
	world.add_child(bus)
	_place_bus(Vector3(3050.0, 0.05, -3.0))
	_speed = 24.0
	_add_bus_interior()

	# 1. Exterior: el autobús cruza el desierto de noche.
	var road_cam := Vector3(2880.0, 1.6, 9.0)
	world.rig.cinematic_shot(CameraRig.look_from(road_cam, Vector3(3050, 1.5, -3)), CameraRig.look_from(road_cam + Vector3(0, 0.3, 0), Vector3(2830, 1.8, -3)), 9.0, 45.0, 40.0)
	hud.fade_to(0.0, 2.0)
	hud.show_subtitle("", "Carretera del desierto · 3:04", 4.0)
	await _hold(9.0)
	if _skip_all:
		_finish()
		return

	# 2. Interior: Mack junto a la ventanilla. Vibra el móvil: BIG RAY.
	var seat := BusModel.window_seat()
	var face := Vector3(seat.x, seat.y + 1.25, seat.z)
	var o1 := face + Vector3(-0.55, 0.12, 0.9)
	var o2 := face + Vector3(-0.45, 0.05, 0.6)
	var c1_from := Transform3D(Basis.looking_at(face - o1, Vector3.UP), o1)
	var c1_to := Transform3D(Basis.looking_at(face - o2, Vector3.UP), o2)
	world.rig.attached_shot(bus, c1_from, c1_to, 7.0, 38.0, 34.0)
	phone_light.light_energy = 0.0
	hud.show_subtitle("", "Móvil: BIG RAY", 3.0)
	await _hold(1.5)
	phone_light.light_energy = 2.5
	mack.pose_idle_stance("phone")
	await _hold(2.5)
	if _skip_all:
		_finish()
		return
	var shots := [
		[face + Vector3(0.85, 0.05, 1.3), face + Vector3(0.75, 0.0, 1.0), 34.0],
		[face + Vector3(1.05, 0.25, -0.5), face + Vector3(0.95, 0.2, -0.2), 40.0],
		[face + Vector3(-0.4, 0.1, 1.2), face + Vector3(-0.35, 0.05, 0.9), 30.0],
	]
	var shot_i := 0
	var since_cut := 100.0
	for line in CALL:
		if since_cut > 9.0:
			var sh: Array = shots[shot_i % shots.size()]
			var a: Vector3 = sh[0]
			var b: Vector3 = sh[1]
			world.rig.attached_shot(bus, Transform3D(Basis.looking_at(face - a, Vector3.UP), a), Transform3D(Basis.looking_at(face - b, Vector3.UP), b), 10.0, sh[2], float(sh[2]) - 3.0)
			shot_i += 1
			since_cut = 0.0
		var t := float(line["t"])
		hud.show_subtitle(String(line["speaker"]), String(line["es"]), t)
		world.on_dialogue_line(String(line["speaker"]), String(line["en"]))
		since_cut += t
		await _hold(t)
		if _skip_all:
			_finish()
			return
	hud.show_subtitle("", "", 0.01)
	phone_light.light_energy = 0.0
	mack.set_seated(true)

	# 3. La foto: Mack, Dre y Big Ray delante del taller Vargas.
	world.show_photo("Mack, Dre y Big Ray · Vargas Auto Works", 5.5)
	await _hold(6.0)
	if _skip_all:
		_finish()
		return

	# 4. Amanece. El autobús cruza el puente hacia South Veyra. Título.
	hud.fade_to(1.0, 1.0)
	await _hold(1.1)
	world.sky.apply_preset("dawn", 0.0)
	_place_bus(Vector3(560.0, 0.05, -3.0))
	_speed = 15.0
	var bank := Vector3(318.0, 1.2, 36.0)
	world.rig.cinematic_shot(CameraRig.look_from(bank, Vector3(470, 4, -3)), CameraRig.look_from(bank + Vector3(-6, 1.5, 4), Vector3(330, 6, -3)), 13.0, 50.0, 44.0)
	hud.fade_to(0.0, 1.5)
	world.sky.apply_preset("morning", 16.0)
	await _hold(3.0)
	hud.title_card("WESTSIDE LEGACY", "Respect Is Earned. Legacy Is Taken.", 7.0)
	await _hold(10.0)
	if _skip_all:
		_finish()
		return

	# 5. Llegada a la terminal de Westbrook.
	hud.fade_to(1.0, 0.8)
	await _hold(0.9)
	_finish()


func _finish() -> void:
	var hud: HUD = world.hud
	world.sky.apply_preset("morning", 0.0)
	_speed = 0.0
	if mack:
		mack.queue_free()
		mack = null
	_place_bus(CityLayout.landmark("bus_bay") + Vector3(0, 0.05, 0))
	world.parked_bus = bus
	hud.show_subtitle("", "", 0.01)
	hud.set_letterbox(false)
	hud.fade_to(0.0, 1.0)
	finished.emit()


func _place_bus(pos: Vector3) -> void:
	# El autobús va hacia el oeste (-X); su frente es +Z local.
	bus.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), pos)


func _add_bus_interior() -> void:
	mack = Humanoid.new()
	bus.add_child(mack)
	mack.setup(GameData.character_look("mack"))
	mack.set_seated(true)
	var seat := BusModel.window_seat()
	mack.position = Vector3(seat.x, seat.y - 0.5, seat.z)
	mack.rotation.y = PI
	var phone := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 0.15, 0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.75, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.75, 1.0)
	mat.emission_energy_multiplier = 2.0
	pm.material = mat
	phone.mesh = pm
	phone.position = Vector3(seat.x - 0.1, seat.y + 1.35, seat.z - 0.12)
	bus.add_child(phone)
	phone_light = OmniLight3D.new()
	phone_light.light_color = Color(0.65, 0.78, 1.0)
	phone_light.omni_range = 1.4
	phone_light.light_energy = 0.0
	phone_light.position = Vector3(seat.x - 0.05, seat.y + 1.45, seat.z - 0.3)
	bus.add_child(phone_light)
	var cabin := OmniLight3D.new()
	cabin.light_color = Color(0.35, 0.45, 0.7)
	cabin.omni_range = 9.0
	cabin.light_energy = 1.3
	cabin.position = Vector3(0, 2.9, 0)
	bus.add_child(cabin)
	var head := SpotLight3D.new()
	head.light_color = Color(1.0, 0.93, 0.8)
	head.spot_range = 70.0
	head.spot_angle = 28.0
	head.light_energy = 3.0
	head.position = Vector3(0, 1.0, BusModel.LENGTH * 0.5 + 0.2)
	head.rotation.x = -0.08
	head.rotation.y = PI
	bus.add_child(head)


## Espera t segundos; devuelve true si el jugador pidió saltar la cinemática.
func _hold(t: float) -> bool:
	var e := 0.0
	while e < t:
		if _skip_all:
			return true
		await get_tree().process_frame
		e += get_process_delta_time()
	return _skip_all
