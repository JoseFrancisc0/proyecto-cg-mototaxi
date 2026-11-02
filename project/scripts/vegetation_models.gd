@tool
class_name VegetationModels
extends RefCounted
## Modelos 3D reales de la vegetación (S14), en lugar de los provisionales de VegetationAssets.
##
## Fuentes y licencias en res://assets/vegetation/SOURCE.md (Quaternius CC0 y un cactus CC-BY).
## Cada especie tiene una o más variantes; TerrainVegetation reparte las plantas entre ellas.
## Al cargar, cada modelo se lleva a la altura real de la especie con la base en y = 0 (las
## reglas de C++ suponen modelos a escala real), se le pone el material de vegetación con la
## misma luz del terreno y se arma una versión simplificada (LOD) del mismo modelo.
##
## LOD por planta (los árboles se ven hasta 1.5 km y hay cientos de miles): cada especie de
## árbol tiene una variante "cerca" (modelo completo) y una "lejos": el impostor octaédrico
## horneado (VegetationImpostors, 2 triángulos) o, si no está horneado, una versión
## simplificada con las mismas texturas. El shader decide por planta según la distancia a la cámara (LOD_DISTANCE): la
## versión lejana se oculta dentro del radio y la cercana fuera de él, sin dibujar dos veces.
## NearVegetation mantiene en la variante cercana solo los árboles alrededor de la cámara.

const DIR := "res://assets/vegetation/"
## Radio (m) dentro del cual los árboles usan el modelo completo (más allá, el impostor).
## 80 m: a esa distancia un árbol ocupa ~1 vista del atlas en pantalla y no se nota el cambio;
## con 130 m había el doble de triángulos (benchmark: ~115 -> ~155 FPS en RTX 3050 Laptop).
const LOD_DISTANCE := 80.0
## Triángulos objetivo de la versión lejana de cada árbol.
const FAR_TRIANGLES := 380
## Distancia máxima de dibujo de los árboles (m). Con impostores (2 triángulos por árbol)
## dibujarlos hasta 1.5 km casi no cuesta; con la versión simplificada se limita a 900 m.
const FAR_RANGE := 1500.0
const FAR_RANGE_SIMPLIFIED := 900.0

## height = altura del modelo a escala 1 (m). trunk = radio del tronco a escala 1 (m) para la
## colisión; 0 = sin colisión (se puede atravesar). leaf_tint / bark_tint tiñen las texturas.
const SPECIES := {
	"arbol_selva": {"files": ["CommonTree_3.gltf", "CommonTree_4.gltf", "CommonTree_5.gltf"], "height": 14.0,
		"leaf_tint": Color(0.27, 0.44, 0.14), "trunk": 0.45},
	"eucalipto": {"files": ["CommonTree_3.gltf"], "height": 16.0,
		"leaf_tint": Color(0.38, 0.47, 0.36), "bark_tint": Color(0.95, 0.88, 0.80), "trunk": 0.35},
	"huarango": {"files": ["TwistedTree_1.gltf"], "height": 5.5,
		"leaf_tint": Color(0.42, 0.48, 0.22), "bark_tint": Color(0.80, 0.70, 0.60), "trunk": 0.3},
	"quenua": {"files": ["TwistedTree_3.gltf"], "height": 5.0,
		"leaf_tint": Color(0.24, 0.36, 0.17), "bark_tint": Color(0.90, 0.60, 0.48), "trunk": 0.22},
	"palmera": {"files": ["palm_1.glb", "palm_2.glb"], "height": 9.5, "leafiness": 0.4, "trunk": 0.25,
		"bark_tint": Color(0.46, 0.54, 0.34)},
	"cactus": {"files": ["cactus_organ.glb"], "height": 3.2, "trunk": 0.45},
	"arbusto": {"files": ["Bush_Common.gltf", "Fern_1.gltf", "Plant_1_Big.gltf"], "height": 1.5,
		"leaf_tint": Color(0.30, 0.48, 0.18)},
	"ichu": {"files": ["Grass_Wispy_Tall.gltf"], "height": 0.9, "leaf_tint": Color(0.80, 0.68, 0.40)},
}

static var _cache := {}
static var _materials: Array[ShaderMaterial] = []
static var _far_materials: Array[ShaderMaterial] = []


## Variantes completas listas para MultiMesh (vacío si la especie no tiene modelo).
static func get_variants(species: String) -> Array[Mesh]:
	return _entry(species)["near"]


## Variantes lejanas: impostores o simplificadas (solo árboles; vacío para arbustos y pasto, que se ven de cerca).
static func get_far_variants(species: String) -> Array[Mesh]:
	return _entry(species)["far"]


## true si la especie usa LOD por distancia (árboles con tronco).
static func uses_lod(species: String) -> bool:
	return trunk_radius(species) > 0.0


## En el editor no hay NearVegetation (no sigue a la cámara del editor): se ve todo simplificado.
static func set_editor_mode(on: bool) -> void:
	for m in _far_materials:
		m.set_shader_parameter("hide_inside", 0.0 if on else LOD_DISTANCE)


static func _entry(species: String) -> Dictionary:
	if _cache.has(species):
		return _cache[species]
	var near: Array[Mesh] = []
	var far: Array[Mesh] = []
	var info: Dictionary = SPECIES.get(species, {})
	for file: String in info.get("files", []):
		var built := _build(species, file, info, uses_lod(species))
		if built.is_empty():
			continue
		near.append(built["near"])
		if built.has("far"):
			far.append(built["far"])
	var impostors := not far.is_empty()
	for m in far:
		impostors = impostors and VegetationImpostors.is_impostor(m)
	var entry := {"near": near, "far": far, "impostors": impostors}
	_cache[species] = entry
	return entry


## Distancia de dibujo con modelos reales: la de la regla de C++, con tope en los árboles.
static func draw_range(species: String, rule_range: float) -> float:
	if not uses_lod(species):
		return rule_range
	return minf(rule_range, FAR_RANGE if uses_impostors(species) else FAR_RANGE_SIMPLIFIED)


## true si los árboles lejanos de la especie son impostores horneados.
static func uses_impostors(species: String) -> bool:
	return _entry(species)["impostors"]


static func trunk_radius(species: String) -> float:
	return float(SPECIES.get(species, {}).get("trunk", 0.0))


## Todos los materiales creados (para copiarles la luz del terreno).
static func materials() -> Array[ShaderMaterial]:
	return _materials


## {"near": Mesh, "far": Mesh (si lod)}; vacío si falta el archivo.
static func _build(species: String, file: String, info: Dictionary, lod: bool) -> Dictionary:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		push_warning("VegetationModels: falta " + path)
		return {}
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		root.free()
		return {}
	var src: MeshInstance3D = mi[0]
	# Transform del modelo respecto de la raíz (algunos GLB traen escala 100 en el nodo).
	var xf := Transform3D.IDENTITY
	var n: Node = src
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var mesh: Mesh = src.mesh
	var box := xf * mesh.get_aabb()
	var height := float(info.get("height", box.size.y))
	var k := height / maxf(box.size.y, 0.001)
	var center := box.get_center()
	# Escala uniforme a la altura de la especie, base en y = 0 y centrada en x, z.
	var fit := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-center.x * k, -box.position.y * k, -center.z * k)) * xf
	var near_mesh := ArrayMesh.new()
	var importer := ImporterMesh.new()
	var all_arrays: Array = []
	var total_tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		_transform_arrays(arrays, fit)
		all_arrays.append(arrays)
		total_tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var mat := _material(species, info, mesh.surface_get_material(s), height)
		if lod:
			mat.set_shader_parameter("hide_outside", LOD_DISTANCE)
		near_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		near_mesh.surface_set_material(s, mat)
		if lod:
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null)
	root.free()
	var out := {"near": near_mesh}
	if not lod:
		return out
	# Versión lejana: el impostor horneado (2 triángulos, VegetationImpostors) si existe.
	var impostor := VegetationImpostors.get_mesh(species, file, height)
	if impostor:
		var imp_mat := impostor.surface_get_material(0) as ShaderMaterial
		if not _far_materials.has(imp_mat):
			imp_mat.set_shader_parameter("hide_inside", LOD_DISTANCE)
			_materials.append(imp_mat)
			_far_materials.append(imp_mat)
		out["far"] = impostor
		return out
	# Si no, el nivel de simplificación más cercano a FAR_TRIANGLES (mismas texturas).
	importer.generate_lods(25.0, 60.0, [])
	var far_mesh := ArrayMesh.new()
	var ratio := minf(float(FAR_TRIANGLES) / maxf(total_tris, 1), 1.0)
	for s in all_arrays.size():
		var arrays: Array = all_arrays[s].duplicate()
		var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var best := full
		var want := full.size() * ratio
		for l in importer.get_surface_lod_count(s):
			var idx := importer.get_surface_lod_indices(s, l)
			if absf(idx.size() - want) < absf(best.size() - want):
				best = idx
		arrays[Mesh.ARRAY_INDEX] = best
		far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var far_mat := (near_mesh.surface_get_material(s) as ShaderMaterial).duplicate() as ShaderMaterial
		far_mat.set_shader_parameter("hide_outside", 1.0e9)
		far_mat.set_shader_parameter("hide_inside", LOD_DISTANCE)
		far_mesh.surface_set_material(s, far_mat)
		_materials.append(far_mat)
		_far_materials.append(far_mat)
	out["far"] = far_mesh
	return out


static func _transform_arrays(arrays: Array, xf: Transform3D) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = xf * verts[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	var basis := xf.basis.orthonormalized()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size():
			normals[i] = (basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in range(0, tangents.size(), 4):
			var t := (basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
			tangents[i] = t.x
			tangents[i + 1] = t.y
			tangents[i + 2] = t.z
		arrays[Mesh.ARRAY_TANGENT] = tangents
	# El color de vértice de algunos GLB oscurecería el tinte: el color lo da la instancia.
	arrays[Mesh.ARRAY_COLOR] = null


## Material de vegetación a partir del material importado (textura, normal map, tipo).
static func _material(species: String, info: Dictionary, src: Material, height: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vegetation_textured.gdshader")
	var std := src as BaseMaterial3D
	var tex: Texture2D = std.albedo_texture if std else null
	var mat_name := (src.resource_name if src else "").to_lower()
	var tex_path := tex.resource_path if tex else ""
	var is_leaf := mat_name.contains("lea") or mat_name.contains("grass") or tex_path.to_lower().contains("lea") \
		or (std != null and std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	if tex_path.ends_with("_C.png"):
		# Versión coloreada -> máscara blanca, que se tiñe con el verde de la especie.
		var mask := tex_path.replace("_C.png", ".png")
		if ResourceLoader.exists(mask):
			tex = load(mask)
	if tex == null:
		tex = _white()
	mat.set_shader_parameter("albedo_tex", tex)
	var tint := Color.WHITE
	if is_leaf:
		tint = info.get("leaf_tint", Color.WHITE)
	elif info.has("bark_tint"):
		tint = info["bark_tint"]
	if std:
		tint *= Color(std.albedo_color.r, std.albedo_color.g, std.albedo_color.b)
	mat.set_shader_parameter("tint", tint)
	if std and std.normal_enabled and std.normal_texture:
		mat.set_shader_parameter("normal_tex", std.normal_texture)
		mat.set_shader_parameter("use_normal_map", true)
	mat.set_shader_parameter("leafiness", float(info.get("leafiness", 1.0 if is_leaf else 0.0)))
	mat.set_shader_parameter("alpha_cut", 0.45 if is_leaf else 0.05)
	mat.set_shader_parameter("model_height", height)
	_materials.append(mat)
	return mat


static func _white() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
