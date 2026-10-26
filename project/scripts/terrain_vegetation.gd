@tool
class_name TerrainVegetation
extends Node3D
## Vegetacion del terreno con MultiMesh (S14 CG-B).
##
## C++ (TerrainMesh.scatter_vegetation) reparte las plantas con muestreo con jitter y
## reglas por especie: region (costa/sierra/selva), pendiente, altura, distancia a rios
## y caminos, y manchas de ruido. Aqui se crea un MultiMeshInstance3D por especie y por
## chunk del mapa: asi Godot descarta los chunks que no ve la camara (frustum culling)
## y los lejanos (visibility range), y cada especie se dibuja en una sola llamada por chunk.
##
## Los modelos son provisionales (VegetationAssets): ver la lista en la respuesta/README.

## Reglas de cada especie. density = plantas por cada 100 m2 en el mejor sitio.
## biome = cuanto le gusta (costa, sierra, selva). slope_max = 1 - normal.y.
## alt_min/alt_max = fraccion del rango de alturas del mapa. wet_boost = cuanto mas
## crece junto a los rios (river_reach = metros en que se nota). range = distancia de dibujo.
const SPECIES := [
	{"name": "huarango", "density": 0.05, "biome": Vector3(1.0, 0.05, 0.0), "slope_max": 0.18, "wet_boost": 30.0, "river_reach": 30.0, "river_min": 2.5,
		"scale_min": 0.8, "scale_max": 1.5, "clump": 0.4, "canopy_radius": 2.6, "canopy_strength": 0.45, "range": 1400.0},
	{"name": "cactus", "density": 0.22, "biome": Vector3(0.7, 0.35, 0.0), "slope_max": 0.45, "slope_min": 0.03, "alt_max": 0.75, "wet_boost": 0.2, "river_reach": 30.0,
		"river_min": 6.0, "scale_min": 0.7, "scale_max": 1.4, "clump": 0.6, "range": 700.0},
	{"name": "ichu", "density": 5.0, "biome": Vector3(0.0, 1.0, 0.05), "slope_max": 0.42, "alt_min": 0.15, "tilt": 0.8, "scale_min": 0.7, "scale_max": 1.35,
		"clump": 0.65, "clump_scale": 25.0, "river_min": 1.5, "range": 170.0},
	{"name": "quenua", "density": 0.10, "biome": Vector3(0.0, 1.0, 0.0), "slope_max": 0.38, "alt_min": 0.35, "alt_max": 0.9, "clump": 0.9, "clump_scale": 70.0,
		"scale_min": 0.8, "scale_max": 1.3, "canopy_radius": 2.0, "canopy_strength": 0.45, "range": 1200.0},
	{"name": "eucalipto", "density": 0.05, "biome": Vector3(0.05, 1.0, 0.15), "slope_max": 0.25, "alt_max": 0.55, "wet_boost": 3.0, "river_reach": 60.0,
		"clump": 0.8, "clump_scale": 50.0, "scale_min": 0.8, "scale_max": 1.25, "canopy_radius": 2.2, "range": 1500.0},
	{"name": "arbol_selva", "density": 1.3, "biome": Vector3(0.0, 0.05, 1.0), "slope_max": 0.5, "scale_min": 0.75, "scale_max": 1.4, "clump": 0.3,
		"canopy_radius": 4.5, "canopy_strength": 0.55, "range": 1500.0},
	{"name": "palmera", "density": 0.08, "biome": Vector3(0.0, 0.0, 1.0), "slope_max": 0.2, "wet_boost": 10.0, "river_reach": 35.0, "river_min": 2.0,
		"scale_min": 0.8, "scale_max": 1.2, "clump": 0.5, "canopy_radius": 2.5, "range": 1400.0},
	{"name": "arbusto", "density": 1.2, "biome": Vector3(0.0, 0.15, 1.0), "slope_max": 0.6, "scale_min": 0.6, "scale_max": 1.3, "tilt": 0.3, "clump": 0.4,
		"range": 350.0},
]

## Multiplica la densidad de todas las especies (0.3 en el editor si va lento).
@export_range(0.0, 3.0, 0.05) var density := 1.0
## Cambia un modelo por uno real: {"huarango": load("res://models/huarango.res")}.
@export var mesh_overrides: Dictionary = {}

static var _material: ShaderMaterial
var counts := {}
var canopy_texture: ImageTexture
var total := 0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/vegetation.gdshader")
	return _material


## Reparte y crea las plantas sobre la superficie de 'builder'. Devuelve el numero de plantas.
func build(builder: TerrainMesh, terrain: TerrainNoise, options := {}) -> int:
	clear()
	if builder == null or terrain == null:
		return 0
	var opts := options.duplicate()
	opts["density_scale"] = density
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = builder.scatter_vegetation(terrain, SPECIES, opts)
	if result.is_empty():
		return 0
	var chunk_m: float = result["chunk_size_m"]
	var per_side: int = result["chunks_per_side"]
	var half := chunk_m * per_side * 0.5
	var species: Dictionary = result["species"]
	for rule: Dictionary in SPECIES:
		var name: String = rule["name"]
		if not species.has(name):
			continue
		var info: Dictionary = species[name]
		counts[name] = info["count"]
		var mesh: Mesh = mesh_overrides.get(name, VegetationAssets.get_mesh(name))
		var chunks: Dictionary = info["chunks"]
		for chunk_id: int in chunks:
			var buffer: PackedFloat32Array = chunks[chunk_id]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true  # variacion de color por planta (y en Compatibility, sin esto COLOR llega en negro)
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = buffer.size() / 20
			mm.buffer = buffer
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d" % [name, chunk_id]
			node.multimesh = mm
			node.material_override = shared_material()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Distancia de dibujo por especie: el pasto solo cerca de la camara.
			node.visibility_range_end = float(rule.get("range", 1000.0))
			node.visibility_range_end_margin = float(rule.get("range", 1000.0)) * 0.15
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(node)
	total = result["total"]
	var n: int = result["canopy_size"]
	var canopy := Image.create_from_data(n, n, false, Image.FORMAT_R8, result["canopy"])
	canopy_texture = ImageTexture.create_from_image(canopy)
	print("Vegetacion: %d plantas en %.1f s %s" % [total, (Time.get_ticks_msec() - t0) / 1000.0, counts])
	return total


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	counts.clear()
	total = 0


## Copia la luz del material del terreno al de la vegetacion (mismo sol, cielo y niebla).
## world_sun = direccion HACIA el sol en coordenadas del mundo (el shader de las plantas
## no puede usar la del terreno: su MODEL_MATRIX incluye el giro de cada planta).
static func sync_lighting(terrain_material: Material, world_sun: Vector3) -> void:
	if not (terrain_material is ShaderMaterial):
		return
	var veg := shared_material()
	veg.set_shader_parameter("sun_direction", world_sun.normalized())
	for param in ["sun_color", "sun_intensity", "sky_color", "ground_color", "ambient_intensity", "exposure", "fog_color", "fog_density"]:
		var value = terrain_material.get_shader_parameter(param)
		if value != null:
			veg.set_shader_parameter(param, value)
