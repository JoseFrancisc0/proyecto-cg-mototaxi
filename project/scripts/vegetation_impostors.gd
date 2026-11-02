@tool
class_name VegetationImpostors
extends RefCounted
## Impostores octaédricos de los árboles lejanos (S14): cada árbol a más de LOD_DISTANCE se
## dibuja con 2 triángulos que muestran una "foto" del modelo real tomada desde el ángulo más
## parecido al de la cámara, en lugar de una versión simplificada de cientos de triángulos.
##
## Las fotos se hornean una vez (no en el juego) con:
##   Godot --path project -s res://tools/bake_impostors.gd        (con ventana, necesita GPU)
## que deja en DIR, por cada especie y variante, <clave>_albedo.png, <clave>_normal.png y
## <clave>.json (centro y radio del modelo). Si faltan, VegetationModels usa la versión
## simplificada de siempre. El shader está en res://shaders/vegetation_impostor.gdshader.
##
## Direcciones: FRAMES x FRAMES vistas del hemisferio superior repartidas con la proyección
## hemi-octaédrica (un punto g de [-1, 1]^2 -> dirección; el borde del cuadrado es el horizonte).

const DIR := "res://assets/vegetation/impostors/"
## Vistas por lado del atlas (FRAMES^2 en total).
const FRAMES := 8
## Píxeles de cada vista en el atlas final (se dibuja al doble y se reduce: antialiasing).
const FRAME_PX := 128
const BAKE_PX := 256
const SHADER := "res://shaders/vegetation_impostor.gdshader"

## false = usar la versión simplificada aunque haya impostores (para comparar).
static var enabled := true
static var _cache := {}


static func key(species: String, file: String) -> String:
	return "%s_%s" % [species, file.get_basename()]


## Dirección (hacia la cámara) de la vista en la celda (i, j) del atlas.
static func frame_direction(i: int, j: int) -> Vector3:
	var g := Vector2(i, j) / float(FRAMES - 1) * 2.0 - Vector2.ONE
	var x := (g.x + g.y) * 0.5
	var z := (g.x - g.y) * 0.5
	return Vector3(x, 1.0 - absf(x) - absf(z), z).normalized()


## Ejes de la cámara que mira desde d hacia el modelo (x = derecha, y = arriba, z = d).
## Debe coincidir con frame_axes() del shader.
static func frame_basis(d: Vector3) -> Basis:
	var up_ref := Vector3(0, 0, -1) if absf(d.y) > 0.999 else Vector3.UP
	var right := up_ref.cross(d).normalized()
	return Basis(right, d.cross(right), d)


## Esfera que envuelve el modelo: centro de su caja y distancia al vértice más lejano.
static func bounds(mesh: Mesh) -> Dictionary:
	var center := mesh.get_aabb().get_center()
	var r2 := 0.0
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			r2 = maxf(r2, v.distance_squared_to(center))
	return {"center": center, "radius": sqrt(r2)}


## Quad con el material del impostor de esa variante; null si no está horneado.
static func get_mesh(species: String, file: String, height: float) -> Mesh:
	var k := key(species, file)
	if _cache.has(k):
		return _cache[k]
	var mesh: Mesh = null
	var albedo := DIR + k + "_albedo.png"
	var normal := DIR + k + "_normal.png"
	var info_path := DIR + k + ".json"
	if enabled and ResourceLoader.exists(albedo) and ResourceLoader.exists(normal) and FileAccess.file_exists(info_path):
		var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(info_path))
		var c: Array = info["center"]
		var center := Vector3(c[0], c[1], c[2])
		var radius := float(info["radius"])
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		mat.set_shader_parameter("albedo_atlas", load(albedo))
		mat.set_shader_parameter("normal_atlas", load(normal))
		mat.set_shader_parameter("frames", float(info.get("frames", FRAMES)))
		mat.set_shader_parameter("center", center)
		mat.set_shader_parameter("radius", radius)
		mat.set_shader_parameter("model_height", height)
		mesh = _quad(center, radius, mat)
	_cache[k] = mesh
	return mesh


static func is_impostor(mesh: Mesh) -> bool:
	var mat := mesh.surface_get_material(0) as ShaderMaterial if mesh.get_surface_count() > 0 else null
	return mat != null and mat.shader != null and mat.shader.resource_path == SHADER


## 4 vértices: el shader los coloca según la cámara (solo usa UV). La caja de cálculo de
## visibilidad es la de la esfera del modelo, no la del quad.
static func _quad(center: Vector3, radius: float, mat: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([center, center, center, center])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var r := radius * 1.15
	mesh.custom_aabb = AABB(center - Vector3.ONE * r, Vector3.ONE * r * 2.0)
	return mesh
