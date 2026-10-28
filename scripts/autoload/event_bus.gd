extends Node
## Bus de eventos global. Los sistemas se comunican por señales aquí
## en vez de referenciarse entre sí directamente.

@warning_ignore("unused_signal")
signal money_changed(new_value: int)
@warning_ignore("unused_signal")
signal reputation_changed(faction_id: String, new_value: int)
@warning_ignore("unused_signal")
signal mission_completed(mission_number: int)
@warning_ignore("unused_signal")
signal zone_unlocked(zone_id: String)
@warning_ignore("unused_signal")
signal game_saved(slot: int)
@warning_ignore("unused_signal")
signal game_loaded(slot: int)
@warning_ignore("unused_signal")
signal settings_changed()
