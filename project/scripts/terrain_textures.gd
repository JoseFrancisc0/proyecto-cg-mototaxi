@tool
class_name TerrainTextures
extends RefCounted
## Carga las texturas de ambientCG y arma el material del terreno (terrain_splat.gdshader).
##
## Donde van las texturas: una carpeta por material dentro de res://textures/,
## con el nombre del ID de ambientCG al inicio, por ejemplo:
##   res://textures/Ground054_2K-JPG/Ground054_2K-JPG_Color.jpg
##   res://textures/Ground054_2K-JPG/Ground054_2K-JPG_NormalGL.jpg
##   res://textures/Ground054_2K-JPG/Ground054_2K-JPG_Roughness.jpg
## Basta con descomprimir cada .zip dentro de res://textures/ ("Extraer todo" de Windows).
##
## Las 7 texturas de cada tipo se juntan en un Texture2DArray (una capa por material).
## Asi el shader usa 4 samplers en vez de 28; el renderer Compatibility tiene pocos.
## Las imagenes ya comprimidas se guardan en res://textures/_cache/ y solo se rehacen si
## cambian los archivos. (Antes se guardaba el Texture2DArray con ResourceSaver: Godot lo
## escribia vacio, porque lee las capas desde la GPU, y el cache se rehacia en cada inicio.)

const TEXTURE_DIR := "res://textures/"
const CACHE_DIR := "res://textures/_cache/"
const LAYER_SIZE := 1024

## Orden = numero de capa en el shader. Para cambiar una textura, cambia el "id".
const MATERIALS := [
	{"id": "Ground054", "use": "costa, plano: arena", "fallback": Color(0.78, 0.70, 0.52)},
	{"id": "Rocks021", "use": "costa, ladera: piedras sobre arena", "fallback": Color(0.62, 0.58, 0.50)},
	{"id": "Rocks007", "use": "sierra, plano: roca con pasto", "fallback": Color(0.50, 0.48, 0.38)},
	{"id": "Rocks011", "use": "sierra, ladera: lajas (triplanar)", "fallback": Color(0.55, 0.53, 0.50)},
	{"id": "Snow015", "use": "sierra, cumbre: nieve", "fallback": Color(0.92, 0.93, 0.95)},
	{"id": "Ground037", "use": "selva, plano: musgo", "fallback": Color(0.30, 0.42, 0.16)},
	{"id": "Rock059", "use": "selva, ladera: roca verde (triplanar)", "fallback": Color(0.36, 0.42, 0.33)},
]

## Mapa del shader -> sufijo del archivo de ambientCG.
const MAPS := {
	"albedo": "_Color",
	"normal": "_NormalGL",
	"roughness": "_Roughness",
	"height": "_Displacement", # relieve para POM (S12)
}

static var _material: ShaderMaterial


## Material compartido del terreno. La primera vez arma (o lee del cache) las texturas.
static func get_material(force_rebuild := false) -> ShaderMaterial:
	if _material != null and not force_rebuild:
		return _material
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_splat.gdshader")
	for map_name: String in MAPS:
		material.set_shader_parameter(map_name + "_maps", _texture_array(map_name, force_rebuild))
	_material = material
	return _material


## Lista que archivo se usa para cada material (o que falta). Util para revisar la carpeta.
static func report() -> String:
	var lines := PackedStringArray()
	for i in MATERIALS.size():
		var item: Dictionary = MATERIALS[i]
		var found := PackedStringArray()
		for map_name: String in MAPS:
			var path := _find_file(item.id, MAPS[map_name])
			found.append("%s=%s" % [map_name, path.get_file() if path != "" else "FALTA"])
		lines.append("capa %d %s (%s): %s" % [i, item.id, item.use, ", ".join(found)])
	return "\n".join(lines)


static func _texture_array(map_name: String, force_rebuild: bool) -> Texture2DArray:
	var cache_path := CACHE_DIR + "terrain_%s.imgcache" % map_name
	var signature := _signature(map_name)
	if not force_rebuild:
		var cached := _load_cache(cache_path, signature)
		if cached != null:
			return cached

	var t0 := Time.get_ticks_msec()
	var images: Array[Image] = []
	for item: Dictionary in MATERIALS:
		images.append(_load_layer(item, map_name))
	# Comprimir (BC1/DXT1) baja ~6 veces la memoria. Todas las capas deben quedar
	# con el mismo formato; si alguna no se pudo comprimir, se dejan todas sin comprimir.
	var compressed := true
	for image in images:
		var source := Image.COMPRESS_SOURCE_SRGB if map_name == "albedo" else Image.COMPRESS_SOURCE_GENERIC
		if image.compress(Image.COMPRESS_S3TC, source) != OK:
			compressed = false
	var formats := {}
	for image in images:
		formats[image.get_format()] = true
	if not compressed or formats.size() > 1:
		# Respaldo: todas sin comprimir y en RGBA8, para que compartan formato.
		for i in images.size():
			var image := images[i]
			if image.is_compressed():
				image.decompress()
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			if not image.has_mipmaps():
				image.generate_mipmaps()

	var array := Texture2DArray.new()
	if array.create_from_images(images) != OK:
		push_error("No se pudo crear el Texture2DArray de '%s'." % map_name)
		return array
	_save_cache(cache_path, signature, images)
	print("Texturas '%s' preparadas en %.1f s" % [map_name, (Time.get_ticks_msec() - t0) / 1000.0])
	return array


## Cache: las 7 imagenes (ya comprimidas y con mipmaps) en un archivo binario de Godot.
static func _save_cache(path: String, signature: String, images: Array[Image]) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var data := []
	for image in images:
		data.append({"width": image.get_width(), "height": image.get_height(), "mipmaps": image.has_mipmaps(),
			"format": image.get_format(), "data": image.get_data()})
	file.store_var({"signature": signature, "layers": data})


static func _load_cache(path: String, signature: String) -> Texture2DArray:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var stored = file.get_var()
	if not (stored is Dictionary) or stored.get("signature", "") != signature or stored.get("layers", []).size() != MATERIALS.size():
		return null
	var images: Array[Image] = []
	for layer: Dictionary in stored["layers"]:
		var image := Image.create_from_data(layer["width"], layer["height"], layer["mipmaps"], layer["format"], layer["data"])
		if image == null or image.is_empty():
			return null
		images.append(image)
	var array := Texture2DArray.new()
	return array if array.create_from_images(images) == OK else null


static func _load_layer(item: Dictionary, map_name: String) -> Image:
	var path := _find_file(item.id, MAPS[map_name])
	var image: Image = null
	if path != "":
		# Se leen los bytes del archivo original (8 bits por canal), no la version
		# importada por Godot, que puede venir comprimida en otro formato.
		var bytes := FileAccess.get_file_as_bytes(path)
		image = Image.new()
		var err := image.load_png_from_buffer(bytes) if path.to_lower().ends_with(".png") else image.load_jpg_from_buffer(bytes)
		if err != OK:
			image = null
	if image == null or image.is_empty():
		push_warning("Textura no encontrada: %s%s en %s. Se usa un color plano." % [item.id, MAPS[map_name], TEXTURE_DIR])
		return _flat_layer(map_name, item.fallback)
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != LAYER_SIZE or image.get_height() != LAYER_SIZE:
		image.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_CUBIC)
	image.generate_mipmaps()
	return image


## Capa de respaldo cuando falta un archivo: color plano, normal recta, rugosidad alta.
static func _flat_layer(map_name: String, color: Color) -> Image:
	var fill := color
	if map_name == "normal":
		fill = Color(0.5, 0.5, 1.0)
	elif map_name == "roughness":
		fill = Color(0.9, 0.9, 0.9)
	elif map_name == "height":
		fill = Color(1.0, 1.0, 1.0) # sin relieve
	var image := Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	image.generate_mipmaps()
	return image


## Busca "<id>...<sufijo>.jpg|.png" en res://textures/ y en sus subcarpetas que empiecen con el id.
static func _find_file(id: String, suffix: String) -> String:
	var folders := PackedStringArray([TEXTURE_DIR])
	for folder in DirAccess.get_directories_at(TEXTURE_DIR):
		if folder.begins_with(id):
			folders.append(TEXTURE_DIR + folder + "/")
	for folder in folders:
		for file in DirAccess.get_files_at(folder):
			var lower := file.to_lower()
			if file.begins_with(id) and file.contains(suffix) and (lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".png")):
				return folder + file
	return ""


## Firma de los archivos fuente: si cambian (o aparecen), el cache se rehace.
static func _signature(map_name: String) -> String:
	var parts := PackedStringArray(["v2", str(LAYER_SIZE)])
	for item: Dictionary in MATERIALS:
		var path := _find_file(item.id, MAPS[map_name])
		parts.append("%s:%d" % [path, FileAccess.get_modified_time(path) if path != "" else 0])
	return "|".join(parts)
