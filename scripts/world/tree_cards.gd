class_name TreeCards
extends RefCounted
## Árboles realistas baratos para móvil: dos planos cruzados con la imagen de un árbol real
## (modelos CC0 de Poly Haven renderizados a textura con transparencia, ver assets/CREDITOS.md).
## Ocho triángulos por árbol; se usan en MultiMesh en la ciudad y en el terreno.

const DIR := "res://assets/props/trees/"
## id -> lado del cuadrado en metros (la imagen tiene la base del tronco en el borde inferior).
const KINDS := {
	"jacaranda_tree": 9.5,
	"island_tree_02": 7.5,
}

static var _cache: Dictionary = {}


static func available(kind: String) -> bool:
	return KINDS.has(kind) and ResourceLoader.exists(DIR + kind + "_0.png") and ResourceLoader.exists(DIR + kind + "_1.png")


static func _material(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# La imagen ya lleva su sombreado suave: se ilumina sobre todo con luz ambiente y sol difuso.
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.albedo_color = Color(1.15, 1.15, 1.15)
	return m


## Malla de dos planos cruzados (una superficie por imagen). El origen es la base del tronco.
static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var side: float = KINDS[kind]
	var out := ArrayMesh.new()
	for i in 2:
		var axis := Vector3(1, 0, 0) if i == 0 else Vector3(0, 0, -1)
		var h := side * 0.5
		var verts := PackedVector3Array([-axis * h, axis * h, axis * h + Vector3(0, side, 0), -axis * h + Vector3(0, side, 0)])
		var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		# Normales hacia arriba y un poco hacia fuera: luz uniforme por las dos caras.
		var normals := PackedVector3Array()
		for v in verts:
			normals.append(Vector3(0, 1, 0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		# Cada plano lleva sus dos caras como triángulos propios (sin cull_disabled, que
		# invertiría la normal de la cara trasera y la dejaría negra).
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 2, 1, 0, 3, 2, 0])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, _material(DIR + "%s_%d.png" % [kind, i]))
	_cache[kind] = out
	return out
