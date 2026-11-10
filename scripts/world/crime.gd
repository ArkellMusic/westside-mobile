class_name CrimeSystem
extends Node
## Delitos, testigos y descripción policial.
## La policía no sabe quién eres por arte de magia: alguien tiene que verte.
## - Si un agente ve el delito, te identifica al momento.
## - Si no, los peatones cercanos llaman (tardan CALL_TIME s; si los tumbas antes, no hay aviso).
## - El aviso lleva una DESCRIPCIÓN: la ropa que llevabas y, si ibas en coche, el coche y su color.
## - Los agentes van al último lugar conocido y buscan a alguien que encaje. Si encajas te
##   reconocen de lejos; si te has cambiado de ropa o de coche (o lo has repintado) solo te
##   reconocen de muy cerca.
## - Cuando un agente te reconoce, la descripción se actualiza con lo que llevas en ese momento.

const CALL_TIME := 5.0
const WITNESS_RADIUS := 24.0
const WITNESS_RADIUS_LOUD := 42.0
const RANGE_MATCH_FOOT := 34.0
const RANGE_NO_MATCH_FOOT := 7.0
const RANGE_MATCH_CAR := 42.0
const RANGE_NO_MATCH_CAR := 9.0

signal reported(look: Dictionary)

## Nodo principal (main.gd).
var main
## {"outfit": int, "car": String, "car_color": Color, "car_name": String}; vacío = sin descripción.
var description: Dictionary = {}
var last_known: Vector3 = Vector3.ZERO
var _crime_n: int = 0
var _reported_ids: Dictionary = {}
var _hint_cd: float = 0.0
var _recog_cd: float = 0.0
var _was_known: bool = false
var _loud_cd: float = 0.0


func _process(delta: float) -> void:
	_hint_cd = maxf(0.0, _hint_cd - delta)
	_recog_cd = maxf(0.0, _recog_cd - delta)
	_loud_cd = maxf(0.0, _loud_cd - delta)


## Aspecto actual del jugador tal y como lo describiría un testigo.
func current_look() -> Dictionary:
	var car: Car = main.current_vehicle
	return {
		"outfit": GameState.outfit,
		"head": GameState.head_style,
		"car": car.vehicle_id if car else "",
		"car_color": car.body_color if car else Color.BLACK,
		"car_name": car.display_name if car else "",
	}


static func describe(look: Dictionary) -> String:
	var txt := Humanoid.outfit_name(int(look.get("outfit", 0)))
	if int(look.get("head", 0)) != 0:
		txt += " · barba y gorra %s" % Humanoid.head_name(int(look.get("head", 0))).to_lower()
	if String(look.get("car", "")) != "":
		txt += " · en un %s" % String(look.get("car_name", "coche"))
	return txt


## ¿El jugador encaja ahora con la descripción que tiene la policía?
func matches() -> bool:
	if description.is_empty():
		return false
	var look := current_look()
	if String(look["car"]) != "":
		return look["car"] == description.get("car", "") and (look["car_color"] as Color).is_equal_approx(description.get("car_color", Color.BLACK))
	return int(look["outfit"]) == int(description.get("outfit", -1)) and int(look["head"]) == int(description.get("head", 0))


## Distancia a la que un agente con línea de visión reconoce al jugador.
func recognition_range() -> float:
	var in_car: bool = main.current_vehicle != null
	if matches():
		return RANGE_MATCH_CAR if in_car else RANGE_MATCH_FOOT
	return RANGE_NO_MATCH_CAR if in_car else RANGE_NO_MATCH_FOOT


## El jugador comete un delito en `pos`. `severity` = estrellas que suma si se denuncia.
## `loud` (disparos) se oye desde más lejos. Devuelve el número de testigos que llaman.
func commit(pos: Vector3, severity: int, loud: bool = false) -> int:
	if loud:
		# Una ráfaga de disparos cuenta como un solo delito.
		if _loud_cd > 0.0:
			return 0
		_loud_cd = 10.0
	_crime_n += 1
	var id := _crime_n
	var look := current_look()
	if main.police.sees_player_now():
		report({"id": id, "look": look, "pos": pos, "severity": severity})
		return 0
	var payload := {"id": id, "look": look, "pos": pos, "severity": severity}
	var n: int = main.pedestrians.call_witnesses(pos, WITNESS_RADIUS_LOUD if loud else WITNESS_RADIUS, 2, CALL_TIME, payload)
	if n > 0 and _hint_cd <= 0.0 and main.wanted == 0:
		_hint_cd = 12.0
		main.hud.toast("UN TESTIGO ESTÁ LLAMANDO", "Detenlo antes de que cuelgue o aléjate y cambia de aspecto", 3.5)
	return n


## Un testigo (o un agente) da el aviso: sube la búsqueda una vez por delito.
func report(payload: Dictionary) -> void:
	description = (payload["look"] as Dictionary).duplicate()
	last_known = payload["pos"]
	var id := int(payload["id"])
	if not _reported_ids.has(id):
		_reported_ids[id] = true
		var first: bool = main.wanted == 0
		main.set_wanted(mini(main.wanted + int(payload["severity"]), 6))
		if first:
			main.hud.toast("DESCRIPCIÓN POLICIAL", describe(description), 4.0)
	else:
		main.refresh_wanted()
	reported.emit(description)


## Un agente reconoce al jugador: sabe dónde está y qué lleva puesto ahora.
func on_recognised(pos: Vector3) -> void:
	last_known = pos
	description = current_look()
	if not _was_known and _recog_cd <= 0.0 and main.wanted > 0:
		_recog_cd = 8.0
		main.hud.toast("TE HAN RECONOCIDO", describe(description), 2.5)
	_was_known = true


## Llamado por main cada fotograma con el estado de la policía.
func set_known(known: bool) -> void:
	if not known:
		_was_known = false


## El jugador se cambia de ropa, de coche o repinta: avisa si ya no encaja.
func look_changed() -> void:
	if main.wanted > 0 and not main.police.any_seen and not description.is_empty() and not matches():
		main.hud.toast("YA NO ENCAJAS CON LA DESCRIPCIÓN", "Mantente lejos de los agentes hasta que se calme", 3.5)


func clear() -> void:
	description = {}
	_reported_ids.clear()
	_was_known = false
	_loud_cd = 0.0
