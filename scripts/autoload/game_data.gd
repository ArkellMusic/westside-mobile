extends Node
## Datos estáticos del juego (zonas, bandas, misiones) cargados desde res://data.
## Todo lo que es contenido vive en JSON para poder ampliar el mundo sin tocar código.

var zones: Array = []
var factions: Array = []
var characters: Dictionary = {}
var _zones_by_id: Dictionary = {}
var _factions_by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	zones = load_json("res://data/zones.json").get("zones", [])
	factions = load_json("res://data/factions.json").get("factions", [])
	characters = load_json("res://data/characters.json").get("characters", {})
	_zones_by_id.clear()
	_factions_by_id.clear()
	for z in zones:
		_zones_by_id[z["id"]] = z
	for f in factions:
		_factions_by_id[f["id"]] = f


func zone(id: String) -> Dictionary:
	return _zones_by_id.get(id, {})


func faction(id: String) -> Dictionary:
	return _factions_by_id.get(id, {})


func faction_color(id: String) -> Color:
	var f := faction(id)
	if f.is_empty():
		return Color.WHITE
	return Color.html(String(f.get("color", "#FFFFFF")))


## Zonas que se abren al completar la misión indicada.
func zones_unlocked_by(mission_number: int) -> Array:
	var result: Array = []
	for z in zones:
		var m := int(z.get("unlock_after_mission", 0))
		if m != 0 and m == mission_number:
			result.append(String(z["id"]))
	return result


func character(id: String) -> Dictionary:
	return characters.get(id, {})


## Aspecto listo para Humanoid.setup(): convierte los colores hex en Color.
func character_look(id: String) -> Dictionary:
	var raw: Dictionary = character(id).get("look", {})
	var look := {}
	for k in raw:
		var v: Variant = raw[k]
		if typeof(v) == TYPE_STRING and String(v).begins_with("#"):
			look[k] = Color.html(String(v))
		elif typeof(v) == TYPE_FLOAT:
			look[k] = float(v)
		else:
			look[k] = v
	return look


func character_name(id: String) -> String:
	return String(character(id).get("alias", id))


func load_mission(mission_id: String) -> Dictionary:
	return load_json("res://data/missions/%s.json" % mission_id)


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("No existe el archivo de datos: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON inválido en %s" % path)
		return {}
	return parsed
