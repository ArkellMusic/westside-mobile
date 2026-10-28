extends Node
## Guardado en JSON con ranuras. La ranura 0 es el autoguardado; 1-3 son manuales.
## Escritura segura: se escribe a .tmp, se guarda copia .bak de la anterior y se renombra.

const SAVE_VERSION := 1
const AUTOSAVE_SLOT := 0
const MANUAL_SLOTS := [1, 2, 3]

var save_dir: String = "user://saves"


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]


func save_slot(slot: int) -> bool:
	var dir_abs := ProjectSettings.globalize_path(save_dir)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var payload := {
		"version": SAVE_VERSION,
		"game": "WESTSIDE LEGACY Mobile",
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"unix": Time.get_unix_time_from_system(),
		"state": GameState.to_dict(),
	}
	var final_abs := ProjectSettings.globalize_path(slot_path(slot))
	var tmp_abs := final_abs + ".tmp"
	var f := FileAccess.open(tmp_abs, FileAccess.WRITE)
	if f == null:
		push_error("No se pudo escribir la partida: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if FileAccess.file_exists(final_abs):
		DirAccess.copy_absolute(final_abs, final_abs + ".bak")
		DirAccess.remove_absolute(final_abs)
	var err := DirAccess.rename_absolute(tmp_abs, final_abs)
	if err != OK:
		push_error("No se pudo cerrar el guardado: %s" % error_string(err))
		return false
	EventBus.game_saved.emit(slot)
	return true


func autosave() -> bool:
	return save_slot(AUTOSAVE_SLOT)


func has_slot(slot: int) -> bool:
	return not read_slot(slot).is_empty()


## Devuelve el contenido válido de la ranura, o {} si no existe o está dañada.
func read_slot(slot: int) -> Dictionary:
	var final_abs := ProjectSettings.globalize_path(slot_path(slot))
	var data := _read_file(final_abs)
	if data.is_empty():
		data = _read_file(final_abs + ".bak")
	return data


func load_slot(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	GameState.from_dict(data["state"])
	EventBus.game_loaded.emit(slot)
	return true


func slot_summary(slot: int) -> Dictionary:
	var data := read_slot(slot)
	if data.is_empty():
		return {"exists": false}
	var st: Dictionary = data["state"]
	return {
		"exists": true,
		"saved_at": String(data.get("saved_at", "")),
		"money": int(st.get("money", 0)),
		"missions": (st.get("completed_missions", []) as Array).size(),
		"play_time": float(st.get("play_time", 0.0)),
	}


func _read_file(abs_path: String) -> Dictionary:
	if not FileAccess.file_exists(abs_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if int(d.get("version", 0)) < 1 or typeof(d.get("state")) != TYPE_DICTIONARY:
		return {}
	return d
