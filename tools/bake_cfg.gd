extends RefCounted
## Configuración de bake_asset.gd (un bloque por modelo).
var CFG := {
	"cuda71": {
		"kind": "car", "src": "res://in/cuda/cuda.glb", "out": "res://assets/cars/cuda71/",
		"yaw_deg": 90.0, "length": 4.85, "tris": 38000, "wheel_tris": 2400, "tex": 1024,
		"wheel_nodes": ["Wheel2A_"], "drop_nodes": ["Caliper"],
		"drop_mats": ["Badge", "Engine_Badge", "Int_Badges", "Plate", "Engine", "Caliper", "Caliper_Color", "body_grille_1"],
		"weights": {"Interrior": 0.12, "Color_Interior": 0.12, "interior_Tiling": 0.25, "Wood": 0.25, "Light inside": 0.5, "Int_Grille1": 0.1, "interiorb_grille2": 0.2, "colour": 0.6},
		"paint_mat": "CarPaint",
	},
	"patrol": {
		"kind": "car", "src": "res://in/patrol/FINAL_MOPDEL_COP13.fbx", "out": "res://assets/cars/patrol/",
		"yaw_deg": 90.0, "length": 4.8, "tris": 38000, "wheel_tris": 2400, "tex": 1024, "tex_big": {"Chassis": 2048},
		"opaque_color": true,
		"wheel_mats": ["tire", "rim", "breaks"], "drop_mats": ["Badges", "Caliper", "internal", "grille_A", "plate"],
		"weights": {"CopProp": 1.0, "plasS": 0.6},
		"mat_over": {"tire": {"albedo_texture": null, "albedo_color": Color(0.045, 0.045, 0.05), "roughness": 0.9}},
	},
	"ambulance": {
		"kind": "car", "src": "res://in/ambulance/Ambulance.fbx", "out": "res://assets/cars/ambulance/",
		"yaw_deg": 90.0, "length": 6.4, "tris": 6000, "wheel_tris": 400, "tex": 1024,
		"drop_nodes": ["shd"], "drop_mats": ["SHD"], "opaque_color": true,
		"wheel_components": true,
		"extra_tex": {"Material #84": {"albedo": "res://in/ambulance/Ambulance_D.png", "normal": "res://in/ambulance/Ambulance_N.png"}},
	},
	"harley": {
		"kind": "prop", "src": "res://in/harley/3596744be93c4762ab0f915316798460.fbx", "out": "res://assets/vehicles/harley/",
		"yaw_deg": 90.0, "length": 2.3, "tris": 30000, "tex": 1024, "drop_tex": ["floor"], "drop_mats": ["circle logo", "trunk logo", "gauge", "floor"], "opaque_color": true,
	},
	"heli": {
		"kind": "prop", "src": "res://in/heli/md_500_war_thunder.glb", "out": "res://assets/vehicles/heli/",
		"yaw_deg": 0.0, "scale": 1.0, "tris": 28000, "tex": 1024,
	},
	"hospital": {
		"kind": "building", "src": "res://in/hospital/Hospital.fbx", "out": "res://assets/buildings/hospital/",
		"yaw_deg": -90.0, "scale": 0.9, "tris": 12000, "tex": 1024, "opaque_color": true,
	},
	"prison": {
		"kind": "building", "src": "res://in/prison/Prison.FBX", "out": "res://assets/buildings/prison/",
		"yaw_deg": 0.0, "scale": 1.0, "tris": 140000, "tex": 1024,
		"drop_nodes": ["LightsTower", "Streetlight", "Cam", "SpeakerMount", "Basket", "Trashcan", "Dumpster", "Bench", "Table", "Shed"],
		"weights": {"fence": 0.7, "barbed": 0.8, "Landscape": 0.3},
	},
	"parking": {
		"kind": "building", "src": "res://in/parking/Parking.FBX", "out": "res://assets/buildings/parking/",
		"yaw_deg": 0.0, "scale": 1.0, "tris": 24000, "tex": 1024, "tex_big": {"marks": 2048, "concrete_floor": 2048},
	},
	"police_pd": {
		"kind": "building", "src": "res://in/police_station/PoliceStation.FBX", "out": "res://assets/buildings/police_pd/",
		"yaw_deg": 0.0, "scale": 1.0, "tris": 85000, "tex": 1024, "origin": "keep",
	},
	"subway": {
		"kind": "building", "src": "res://in/subway/Subway.FBX", "out": "res://assets/buildings/subway/",
		"yaw_deg": 0.0, "scale": 1.0, "tris": 120000, "tex": 1024, "origin": "keep",
	},
	"doctor": {
		"kind": "prop", "src": "res://in/doctor/Doctor_Pinch.fbx", "out": "res://assets/characters/doctor/",
		"yaw_deg": 180.0, "height": 1.78, "tris": 15000, "tex": 1024, "opaque_color": true, "uv_weight": 2.0,
	},
	"police_static": {
		"kind": "prop", "src": "res://in/police_old/policeman.obj", "out": "res://assets/characters/police_static/",
		"yaw_deg": 180.0, "height": 1.8, "tris": 8000, "tex": 1024, "opaque_color": true,
	},
	"cop": {
		"kind": "prop", "src": "res://in/cop/MP1.obj", "out": "res://assets/characters/police/",
		"yaw_deg": 0.0, "height": 1.82, "tris": 14000, "tex": 1024, "opaque_color": true, "uv_weight": 3.0,
	},
	"cuda71_lod": {
		"kind": "car", "src": "res://in/cuda/cuda.glb", "out": "res://assets/cars/cuda71/", "tex_id": "cuda71",
		"yaw_deg": 90.0, "length": 4.85, "tris": 8000, "wheel_tris": 600, "tex": 1024,
		"wheel_nodes": ["Wheel2A_"], "drop_nodes": ["Caliper"],
		"drop_mats": ["Badge", "Engine_Badge", "Int_Badges", "Plate", "Engine", "Caliper", "Caliper_Color", "body_grille_1", "Interrior", "Color_Interior", "interior_Tiling", "Wood", "Int_Grille1", "interiorb_grille2"],
		"paint_mat": "CarPaint",
	},
	"patrol_lod": {
		"kind": "car", "src": "res://in/patrol/FINAL_MOPDEL_COP13.fbx", "out": "res://assets/cars/patrol/", "tex_id": "FINAL_MOPDEL_COP13",
		"yaw_deg": 90.0, "length": 4.8, "tris": 11000, "wheel_tris": 700, "tex": 1024, "opaque_color": true,
		"wheel_mats": ["tire", "rim", "breaks"], "drop_mats": ["Badges", "Caliper", "internal", "grille_A", "plate", "Chassis"],
		"mat_over": {"tire": {"albedo_texture": null, "albedo_color": Color(0.045, 0.045, 0.05), "roughness": 0.9}},
	},
}
