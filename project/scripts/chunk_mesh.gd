@tool
extends MeshInstance3D
## Controlador del terreno de terrain_demo.tscn.
##
## Flujo de trabajo (botones al final del Inspector):
##   1. "Generar terreno nuevo (T0)": crea el terreno desde el ruido con la configuracion
##      actual del Inspector (regiones, rios y caminos segun sus opciones). Sin erosion.
##   2. "Aplicar erosion al terreno actual": erosiona el terreno que se esta viendo, no uno
##      nuevo. Cada clic se acumula. Los rios y caminos se recalculan encima del suelo erosionado.
##      Si "Capturas de la erosion" esta activo, guarda las fotos de la evolucion en una carpeta
##      con la fecha (output/capturas_erosion/<fecha>/), mas tiempos y figuras de cada etapa.
##   3. "Volver a la version guardada": restaura la malla guardada en la escena y su configuracion.
##
## Los botones corren el calculo en otro hilo: el editor no se congela y el avance sale en Salida.
##
## Al guardar la escena (Ctrl+S) se guardan juntos la configuracion con la que se genero
## (terrain_snapshot) y el suelo (ground_bytes = T0 + erosiones, sin rios ni caminos).
## Al abrir la escena, el Inspector muestra la configuracion del terreno guardado.

## Avance del calculo en curso (pantalla de carga). fraction va de 0 a 1.
signal job_progress(stage: String, fraction: float)

@export_range(1, 4096, 1) var grid_size: int = 128
@export_range(0.01, 100.0, 0.01) var cell_size: float = 1.0
@export var noise_seed: int = 1337

@export_group("Red de caminos")
## Activa o desactiva todos los caminos.
@export var preview_roads := true
@export var num_points := 6
@export var min_point_dist := 25.0
@export var k_neighbors := 2
@export var hierarchical_roads := true
@export_range(2, 8) var town_count := 4
@export var block_size := 32.0
@export var highway_width := 14.0
@export var avenue_width := 10.0
@export var street_width := 6.0
@export var road_width := 4.0
@export var road_fade := 3.0
@export var road_smooth := 3
## Pendiente maxima de las vias (tan del angulo; 0.25 = 14 grados) para que el vehiculo
## pueda recorrerlas: corta lomas y rellena hoyos del perfil. 0 = sin limite.
@export_range(0.0, 1.0, 0.01) var road_max_grade := 0.0

@export_group("Rios y drenaje")
@export var hydrology_enabled := true
## No es cantidad de rios. Mayor valor = menos cauces visibles; menor = mas.
## Area de terreno (m2) que aporta agua al cauce. No define el ancho del rio.
## La vista de rios principales usa como minimo el 1% del area del mapa.
@export_range(1000, 500000, 1000) var river_catchment := 60000.0
## Radio inicial en metros; se reduce a la mitad en cada etapa de apertura.
@export_range(2, 100, 1) var breach_radius := 24.0

@export_group("Erosion (paper)")
## Pasos de la primera resolucion. Se aplican con el boton "2. Aplicar erosion".
@export var erosion_fluvial := 3000
@export var erosion_thermal := 600
@export var erosion_deposition := 2000
## Rondas de upsampling x2 (0 = una sola resolucion). La base es grid_size / 2^levels.
@export_range(0, 3) var erosion_levels := 0
## Fraccion de TODAS las iteraciones (todos los niveles). 1 = receta completa del paper.
@export_range(0.01, 1.0, 0.01) var erosion_iteration_scale := 1.0
## Upsampling entre niveles: bicubico (lo que dice el paper) o lineal (lo que hace el repo oficial).
@export_enum("Lineal (repo oficial)", "Bicubico (paper)") var erosion_upsampling := 1

@export_group("Retargeting (paper 5.1)")
## Devuelve crestas y picos a la altura de T0 con un mapa de error difundido (paper 5.1).
@export var retarget_enabled := true
## Umbral a0 del area de drenaje, en celdas: puntos con menos agua que esto son crestas.
## Menor = solo las crestas principales; mayor = una red de crestas mas densa (Fig. 12).
@export_range(0.1, 16.0, 0.1) var retarget_threshold := 1.0
## Pasos de difusion (el paper usa 500).
@export_range(0, 2000, 10) var retarget_iterations := 500

@export_group("S11 CG-B - regiones del T0")
@export var three_regions := true
@export_range(6, 32, 1) var region_patches := 16
@export_range(0.02, 0.25, 0.01) var transition_width := 0.16
@export_range(0.0, 0.30, 0.01) var border_warp := 0.16
@export var coast_base := 4.0
@export var coast_amplitude := 4.0
@export var coast_frequency := 0.003
@export var mountain_base := 130.0
@export var mountain_amplitude := 85.0
@export var mountain_frequency := 0.008
@export var jungle_base := 28.0
@export var jungle_amplitude := 14.0
@export var jungle_frequency := 0.004
@export_group("Mapas del paper - parametros iniciales a calibrar")
@export_range(0, 1, 0.01) var coast_hardness := 0.10
@export_range(0, 1, 0.01) var mountain_hardness := 0.65
@export_range(0, 1, 0.01) var jungle_hardness := 0.35
@export var coast_talus := 0.25
@export var mountain_talus := 1.15
@export var jungle_talus := 0.60
## Usa rho/s0 de cada region cuando se aplica la erosion.
@export var use_regional_erosion_maps := true
@export_group("Texturas (S10)")
## Texturas de ambientCG por region, pendiente y altura (terrain_splat.gdshader).
## Desactivado = colores por vertice. Los ajustes finos estan en Material Override.
@export var use_textures := true:
	set(value):
		use_textures = value
		if is_inside_tree():
			_apply_material()
## Fraccion del mapa que queda por debajo de la nieve. 0.97 = solo el 3% mas alto lleva nieve.
@export_range(0.5, 1.0, 0.005) var snow_percentile := 0.97:
	set(value):
		snow_percentile = value
		if is_inside_tree() and material_override is ShaderMaterial:
			_update_snow_line(material_override)
@export_group("Iluminacion (S12)")
## Direccion del sol. Mueve tambien el nodo "Lighting" de la escena (agua y puentes).
@export_range(0.0, 360.0, 1.0) var sun_azimuth := 135.0:
	set(value):
		sun_azimuth = value
		_update_sun(true)
## 90 = mediodia (sin sombras largas), 5 = atardecer (sombras muy largas).
@export_range(1.0, 90.0, 0.5) var sun_elevation := 28.0:
	set(value):
		sun_elevation = value
		_update_sun(true)

@export_group("Agua y rios (S14)")
## Shader: rios pintados sobre el terreno desde el drenaje (campo de distancia, con reflejos y
## corriente). Malla: las cintas de agua anteriores. Ambos: las dos cosas.
@export_enum("Shader (S14)", "Malla anterior", "Ambos") var water_style := 0
## Semiancho del rio (m) cuando su area de drenaje es igual a River Catchment (crece con la raiz del area).
@export_range(0.3, 6.0, 0.1) var river_width := 1.4

@export_group("Vegetacion (S14)")
## Arboles, cactus y pastos con MultiMesh segun region, pendiente, altura y rios.
@export var vegetation_enabled := true:
	set(value):
		vegetation_enabled = value
		if is_inside_tree() and last_surface != null:
			_build_vegetation()
## Multiplica la cantidad de plantas (bajar a 0.3 si el editor va lento).
@export_range(0.0, 3.0, 0.05) var vegetation_density := 1.0

@export_group("Capturas de la erosion (S14)")
## Al aplicar la erosion, guarda fotos de la evolucion del terreno en una carpeta con la fecha.
@export var capture_enabled := true
## Cuantas fotos repartidas de forma pareja entre todas las iteraciones (incluye T0 y el final).
@export_range(2, 60, 1) var capture_count := 12
## Ademas, una foto al terminar cada proceso (fluvial, termica, deposicion) de cada resolucion.
@export var capture_stage_ends := true
## Vista desde arriba (mapa sombreado) y vista 3D por software (no necesitan GPU).
@export var capture_map := true
@export var capture_perspective := true
## Render real de Godot (texturas e iluminacion), desde la camara del editor.
@export var capture_godot := true
@export var capture_size := Vector2i(1280, 720)
## Carpeta base. Vacio = <repo>/output/capturas_erosion. Dentro se crea una carpeta por fecha y hora.
@export_global_dir var capture_folder := ""
@export_group("")

@export_tool_button("1. Generar terreno nuevo (T0)") var boton_generar = _boton_t0
@export_tool_button("2. Aplicar erosion al terreno actual") var boton_erosion = _boton_erosion
@export_tool_button("Volver a la version guardada") var boton_restaurar = restore_saved_mesh
@export_tool_button("Recargar texturas") var boton_texturas = reload_textures
@export_tool_button("Exportar figuras de las etapas") var boton_figuras = _boton_figuras
@export_tool_button("Abrir carpeta de capturas") var boton_carpeta = open_capture_folder

## Configuracion con la que se genero la malla visible, mas la lista de erosiones aplicadas.
@export_storage var terrain_snapshot: Dictionary = {}
## Suelo de la malla visible (T0 + erosiones), sin rios ni caminos, en float32.
@export_storage var ground_bytes: PackedByteArray = PackedByteArray()

## Parametros que definen el terreno. Se guardan con la malla y se restauran con ella.
const BASE_PARAMS := [
	"grid_size", "cell_size", "noise_seed",
	"preview_roads", "num_points", "min_point_dist", "k_neighbors", "hierarchical_roads", "town_count",
	"block_size", "highway_width", "avenue_width", "street_width", "road_width", "road_fade", "road_smooth", "road_max_grade",
	"hydrology_enabled", "river_catchment", "breach_radius",
	"three_regions", "region_patches", "transition_width", "border_warp",
	"coast_base", "coast_amplitude", "coast_frequency",
	"mountain_base", "mountain_amplitude", "mountain_frequency",
	"jungle_base", "jungle_amplitude", "jungle_frequency",
	"coast_hardness", "mountain_hardness", "jungle_hardness",
	"coast_talus", "mountain_talus", "jungle_talus", "use_regional_erosion_maps",
]
## Parametros de cada aplicacion de erosion (se registran en el historial).
const EROSION_PARAMS := ["erosion_fluvial", "erosion_thermal", "erosion_deposition", "erosion_levels",
	"erosion_iteration_scale", "erosion_upsampling", "retarget_enabled", "retarget_threshold", "retarget_iterations"]

const TerrainStub = preload("res://scripts/terrain_world_stub.gd")
var terrain_world
var last_road_count := 0
var last_surface: TerrainMesh
var last_roads: RoadNetwork
var last_terrain: TerrainNoise
var _saved_mesh: Mesh
var _saved_material: Material
var _strip_material_on_save := false
var _saved_snapshot: Dictionary = {}
var _saved_ground: PackedByteArray = PackedByteArray()
var _saved_details: Array[Dictionary] = []
var _generated_details: Array[Node3D] = []
## false = _ready no genera un T0 cuando no hay malla (el juego reconstruye el suelo guardado).
var auto_generate := true
## El juego guarda los atributos de la malla para partirla en chunks (TerrainMesh.build_chunks).
var keep_surface_arrays := false
## Capturas tambien desde scripts (apply_erosion sin boton). Por defecto solo los botones.
var capture_in_scripts := false
## Tamano (ancho) de la vista previa de la pantalla de carga. 0 = sin vista previa.
var preview_size := 0
## true mientras un calculo corre en otro hilo.
var busy := false
## TerrainMesh del calculo en curso o del ultimo (la pantalla de carga lee su avance y vista previa).
var current_builder: TerrainMesh
var vegetation: TerrainVegetation
var _sun_timer: SceneTreeTimer


func _ready() -> void:
	# Abrir la escena nunca reemplaza el terreno guardado.
	_saved_mesh = mesh
	_saved_material = material_override
	_saved_snapshot = terrain_snapshot.duplicate(true)
	_saved_ground = ground_bytes.duplicate()
	for detail_name: String in ["AguaGenerada", "PuentesGenerados"]:
		var detail := get_node_or_null(detail_name) as MeshInstance3D
		if detail != null:
			_saved_details.append({"name": detail_name, "mesh": detail.mesh, "material": detail.material_override})
			_generated_details.append(detail)
	# El Inspector muestra la configuracion con la que se genero el terreno guardado.
	if not terrain_snapshot.is_empty():
		_apply_params(terrain_snapshot.get("params", {}))
	_configure_stub()
	if mesh == null:
		# La escena guarda solo la configuracion y el suelo: la malla se rehace al abrirla.
		if not auto_generate:
			pass
		elif not ground_bytes.is_empty() and not terrain_snapshot.is_empty():
			rebuild_saved_ground()
		else:
			generate_base()
	else:
		_apply_material()


# Ni la malla ni el material se guardan en el .tscn: se rehacen al abrir la escena desde
# terrain_snapshot + ground_bytes (unos 2 s). Asi la escena pesa ~6 MB en vez de >100 MB
# y no depende del cache de texturas (que no se sube a git).
var _mesh_on_save: Mesh
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_mesh_on_save = mesh
		mesh = null
		if material_override is ShaderMaterial:
			material_override = null
			_strip_material_on_save = true
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if _mesh_on_save != null:
			mesh = _mesh_on_save
			_mesh_on_save = null
		if _strip_material_on_save:
			_strip_material_on_save = false
			_apply_material()


# ---------------------------------------------------------------------------
# Botones del Inspector (calculo en otro hilo: el editor no se congela)
# ---------------------------------------------------------------------------

func _boton_t0() -> void:
	await generate_base_async()


func _boton_erosion() -> void:
	await apply_erosion_async(capture_enabled)


func _boton_figuras() -> void:
	if last_surface == null:
		push_warning("Primero genera o reconstruye el terreno (las figuras salen del ultimo calculo).")
		return
	var folder := ErosionCaptures.make_run_folder(capture_folder)
	var figures := ErosionCaptures.write_stage_figures(last_surface, folder.path_join("etapas"), _capture_options())
	print("Figuras de las etapas (%d) en: %s" % [figures.size(), folder])


func open_capture_folder() -> void:
	var base := capture_folder if not capture_folder.is_empty() else ErosionCaptures.default_base_folder()
	DirAccess.make_dir_recursive_absolute(base)
	OS.shell_open(base)


# ---------------------------------------------------------------------------
# API: version directa (bloquea) y version en hilo (corrutina, usar con await)
# ---------------------------------------------------------------------------

## 1. Terreno nuevo desde el ruido, sin erosion.
func generate_base() -> void:
	var job := _prepare("t0")
	if not job.is_empty():
		_finish(job, _job_callable(job).call())


## 2. Erosiona el terreno actual. Se acumula con cada clic.
func apply_erosion() -> void:
	var job := _prepare("erosion")
	if not job.is_empty() and _finish(job, _job_callable(job).call()) and capture_in_scripts and capture_enabled:
		_write_captures_sync(job)


## Semilla -> mapa completo en un solo calculo: T0 + erosion multiescala + retargeting + superficie.
func generate_full() -> bool:
	var job := _prepare("full")
	return not job.is_empty() and _finish(job, _job_callable(job).call())


## Rehace rios, caminos y malla sobre el suelo guardado (ground_bytes), sin erosionar de nuevo.
## Lo usa el juego para cargar el terreno de terrain_demo.tscn con sus propias opciones de vias.
func rebuild_saved_ground() -> bool:
	var job := _prepare("rebuild")
	return not job.is_empty() and _finish(job, _job_callable(job).call())


func generate_base_async() -> bool:
	return await _run_async("t0", false)


func apply_erosion_async(with_captures := true) -> bool:
	return await _run_async("erosion", with_captures)


func generate_full_async(with_captures := false) -> bool:
	return await _run_async("full", with_captures)


func rebuild_saved_ground_async() -> bool:
	return await _run_async("rebuild", false)


## 3. Vuelve a la malla guardada en la escena, con su configuracion y su suelo.
func restore_saved_mesh() -> void:
	if busy:
		push_warning("Hay un calculo en curso; espera a que termine.")
		return
	_clear_details()
	last_surface = null
	last_roads = null
	terrain_snapshot = _saved_snapshot.duplicate(true)
	ground_bytes = _saved_ground.duplicate()
	if not terrain_snapshot.is_empty():
		_apply_params(terrain_snapshot.get("params", {}))
	_configure_stub()
	if _saved_mesh == null and not ground_bytes.is_empty():
		rebuild_saved_ground()
	elif _saved_mesh != null:
		mesh = _saved_mesh
		_apply_material()
		for detail: Dictionary in _saved_details:
			_add_detail(detail.name, detail.mesh, Color.WHITE)
			_generated_details[-1].material_override = detail.material


## Vuelve a leer las texturas de res://textures/ (por ejemplo, despues de agregar o cambiar una).
func reload_textures() -> void:
	TerrainTextures.get_material(true)
	print(TerrainTextures.report())
	_apply_material()


## Compatibilidad: T0 y una erosion en un solo paso.
func generate() -> void:
	generate_base()
	apply_erosion()


# ---------------------------------------------------------------------------
# Trabajos de C++
# ---------------------------------------------------------------------------

## Prepara un calculo: kind = "t0", "erosion", "full" o "rebuild". {} si no se puede.
func _prepare(kind: String) -> Dictionary:
	if busy:
		push_warning("Hay un calculo en curso; espera a que termine.")
		return {}
	if kind == "erosion" or kind == "rebuild":
		if terrain_snapshot.is_empty() or ground_bytes.is_empty():
			if kind == "erosion":
				push_warning("Este terreno no tiene un suelo guardado para erosionar. Usa primero '1. Generar terreno nuevo (T0)'.")
			else:
				push_warning("No hay suelo guardado para reconstruir.")
			return {}
	if kind == "erosion":
		var params: Dictionary = terrain_snapshot.get("params", {})
		var changed := _changed_params(params)
		if not changed.is_empty():
			push_warning("La erosion se aplica al terreno actual con su configuracion. Se ignoran los cambios en: %s. Para usarlos, genera un terreno nuevo." % ", ".join(changed))
		_apply_params(params)
	if not _valid_grid():
		return {}
	var terrain := _configure_stub()
	var cfg := _build_cfg()
	if kind == "rebuild":
		cfg["erosion_enabled"] = not terrain_snapshot.get("erosions", []).is_empty()
	elif kind == "full":
		cfg["erosion_enabled"] = true
	var builder := TerrainMesh.new()
	if kind == "erosion" or kind == "rebuild":
		if not builder.set_ground_heights(ground_bytes.to_float32_array(), grid_size, cell_size):
			push_error("El suelo guardado no coincide con Grid Size y Cell Size.")
			return {}
	var capturing := (kind == "erosion" or kind == "full") and capture_enabled
	builder.set_capture_options({"count": capture_count if capturing else 0, "stage_ends": capture_stage_ends,
		"keep": capturing, "preview_size": preview_size})
	current_builder = builder
	return {"kind": kind, "terrain": terrain, "cfg": cfg, "roads": _make_roads(terrain, cfg), "builder": builder,
		"t0": Time.get_ticks_msec(), "params": _current_params()}


func _job_callable(job: Dictionary) -> Callable:
	var b: TerrainMesh = job["builder"]
	match job["kind"]:
		"erosion":
			return b.erode_ground.bind(job["terrain"], job["roads"], grid_size, cell_size, job["cfg"])
		"rebuild":
			return b.rebuild_surface.bind(job["terrain"], job["roads"], grid_size, cell_size, job["cfg"])
	return b.generate_mesh.bind(job["terrain"], job["roads"], grid_size, cell_size, job["cfg"])


## Corre el calculo en otro hilo y espera sin congelar la interfaz.
func _run_async(kind: String, with_captures: bool) -> bool:
	var job := _prepare(kind)
	if job.is_empty():
		return false
	busy = true
	var builder: TerrainMesh = job["builder"]
	if not with_captures:
		builder.set_capture_options({"count": 0, "keep": false})
	var thread := Thread.new()
	thread.start(_job_callable(job))
	var last_tenth := -1
	while thread.is_alive():
		await get_tree().process_frame
		var p := builder.get_progress()
		job_progress.emit(p["stage"], p["fraction"])
		var tenth := int(p["fraction"] * 10.0)
		if tenth != last_tenth and Engine.is_editor_hint():
			last_tenth = tenth
			print("  %3d%%  %s  (%.0f s)" % [int(p["fraction"] * 100.0), p["stage"], p["elapsed"]])
	var generated: ArrayMesh = thread.wait_to_finish()
	var ok := _finish(job, generated)
	busy = false
	if ok and with_captures and capture_enabled and builder.get_capture_count() > 0:
		await _write_captures_async(job)
	return ok


## Guarda el resultado del calculo en el nodo (malla, historial, suelo, texturas...).
func _finish(job: Dictionary, generated: ArrayMesh) -> bool:
	if generated == null:
		push_error("No se pudo calcular el terreno (%s)." % job["kind"])
		return false
	var label := "Terreno T0 generado"
	match job["kind"]:
		"t0":
			terrain_snapshot = {"params": job["params"], "erosions": []}
		"full":
			terrain_snapshot = {"params": job["params"], "erosions": [_erosion_entry(job["cfg"])]}
			label = "Mapa completo generado (T0 + erosion + retargeting)"
		"erosion":
			var erosions: Array = terrain_snapshot.get("erosions", [])
			erosions.append(_erosion_entry(job["cfg"]))
			terrain_snapshot["erosions"] = erosions
			label = "Erosion aplicada"
		"rebuild":
			label = "Terreno guardado reconstruido"
	last_terrain = job["terrain"]
	_show(job["builder"], job["roads"], generated, label, job["t0"])
	return true


func _erosion_entry(cfg: Dictionary) -> Dictionary:
	var applied := {"regional_maps": cfg["regional_erosion_maps"]}
	for param: String in EROSION_PARAMS:
		applied[param] = get(param)
	return applied


# ---------------------------------------------------------------------------
# Capturas (S14)
# ---------------------------------------------------------------------------

func _capture_options() -> Dictionary:
	var opts := {"map": capture_map, "perspective": capture_perspective, "difference": true, "size": capture_size,
		"map_size": 1024, "params": _current_params(), "sun": Vector2(sun_azimuth, sun_elevation)}
	return opts


func _write_captures_sync(job: Dictionary) -> void:
	var folder := ErosionCaptures.make_run_folder(capture_folder)
	var result := ErosionCaptures.write_software(job["builder"], folder, _capture_options())
	print("Capturas de la erosion: %d fotos en %.1f s -> %s" % [result["captures"], result["seconds"], folder])


func _write_captures_async(job: Dictionary) -> void:
	busy = true
	var builder: TerrainMesh = job["builder"]
	var folder := ErosionCaptures.make_run_folder(capture_folder)
	print("Guardando %d capturas de la evolucion en %s ..." % [builder.get_capture_count(), folder])
	var opts := _capture_options()
	# 1. Render real de Godot (necesita el hilo principal: espera frames).
	if capture_godot and DisplayServer.get_name() != "headless":
		var godot_opts := opts.duplicate()
		godot_opts["sun_direction"] = sun_direction()
		if material_override is ShaderMaterial:
			godot_opts["snow_start"] = material_override.get_shader_parameter("snow_start")
			godot_opts["snow_end"] = material_override.get_shader_parameter("snow_end")
		var cam := _editor_camera()
		if cam != null:
			# La camara del editor, pasada al espacio del terreno (la foto no mueve el terreno).
			godot_opts["camera_transform"] = global_transform.affine_inverse() * cam.global_transform
			godot_opts["camera_fov"] = cam.fov
		var shots: int = await ErosionCaptures.write_godot_views(self, builder, job["terrain"], folder, godot_opts)
		print("  vistas de Godot: %d" % shots)
	# 2. Mapas, perspectiva por software, figuras, CSV y resumen: en otro hilo.
	var t0 := Time.get_ticks_msec()
	var thread := Thread.new()
	thread.start(ErosionCaptures.write_software.bind(builder, folder, opts))
	while thread.is_alive():
		await get_tree().process_frame
	var result: Dictionary = thread.wait_to_finish()
	builder.clear_captures()  # libera la memoria de las fotos
	busy = false
	print("Capturas listas en %.1f s: %s (abre la carpeta con el boton 'Abrir carpeta de capturas')" % [(Time.get_ticks_msec() - t0) / 1000.0, result.get("folder", folder)])


func _editor_camera() -> Camera3D:
	if not Engine.is_editor_hint():
		return get_viewport().get_camera_3d() if is_inside_tree() else null
	var editor = Engine.get_singleton("EditorInterface")
	if editor == null:
		return null
	var viewport = editor.get_editor_viewport_3d(0)
	return viewport.get_camera_3d() if viewport != null else null


# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------

func _valid_grid() -> bool:
	if grid_size < 1 or grid_size > 4096 or not is_finite(cell_size) or cell_size <= 0.0:
		push_error("El terreno requiere entre 1 y 4096 celdas y un tamano de celda positivo y finito.")
		return false
	return true


func _current_params() -> Dictionary:
	var params := {}
	for param: String in BASE_PARAMS:
		params[param] = get(param)
	return params


func _apply_params(params: Dictionary) -> void:
	for param: String in params:
		if param in BASE_PARAMS:
			set(param, params[param])


## Nombres de los parametros del Inspector que difieren de 'params'.
func _changed_params(params: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	for param: String in params:
		if not param in BASE_PARAMS:
			continue
		var current = get(param)
		var saved = params[param]
		var same: bool = is_equal_approx(current, saved) if typeof(current) == TYPE_FLOAT else current == saved
		if not same:
			changed.append(param)
	return changed


func _region_config() -> Dictionary:
	return {
		"enabled": three_regions, "extent": grid_size * cell_size, "region_patches": region_patches,
		"transition_width": transition_width, "border_warp": border_warp,
		"coast_base": coast_base, "coast_amplitude": coast_amplitude, "coast_frequency": coast_frequency,
		"mountain_base": mountain_base, "mountain_amplitude": mountain_amplitude, "mountain_frequency": mountain_frequency,
		"jungle_base": jungle_base, "jungle_amplitude": jungle_amplitude, "jungle_frequency": jungle_frequency,
		"coast_hardness": coast_hardness, "mountain_hardness": mountain_hardness, "jungle_hardness": jungle_hardness,
		"coast_talus": coast_talus, "mountain_talus": mountain_talus, "jungle_talus": jungle_talus,
	}


func _configure_stub() -> TerrainNoise:
	var terrain := TerrainNoise.new()
	terrain.set_seed(noise_seed)
	terrain.configure_regions(_region_config())
	if terrain_world == null:
		terrain_world = TerrainStub.new()
		terrain_world.name = "TerrainWorld"
		add_child(terrain_world)
	terrain_world.configure(terrain, grid_size * cell_size)
	return terrain


func _build_cfg() -> Dictionary:
	return {
		"num_points": num_points if preview_roads else 0,
		"min_point_dist": min_point_dist,
		"k_neighbors": k_neighbors,
		"hierarchical_roads": hierarchical_roads,
		"town_count": town_count, "block_size": block_size,
		"highway_width": highway_width, "avenue_width": avenue_width, "street_width": street_width,
		"road_width": road_width,
		"road_fade": road_fade,
		"road_smooth": road_smooth,
		"road_max_grade": road_max_grade,
		"erosion_enabled": false,
		"hydrology_enabled": hydrology_enabled, "river_catchment": river_catchment,
		"breach_radius": breach_radius,
		"regional_erosion_maps": three_regions and use_regional_erosion_maps,
		"erosion_fluvial": erosion_fluvial,
		"erosion_thermal": erosion_thermal,
		"erosion_deposition": erosion_deposition,
		"erosion_levels": erosion_levels,
		"erosion_iteration_scale": erosion_iteration_scale,
		"erosion_upsampling": erosion_upsampling,
		"retarget_enabled": retarget_enabled,
		"retarget_threshold": retarget_threshold,
		"retarget_iterations": retarget_iterations,
		# Agua: rios en el shader (campo de distancia) y/o la malla de cintas anterior.
		"river_map_enabled": water_style != 1,
		"water_mesh_enabled": water_style != 0,
		"river_width": river_width,
		"keep_arrays": keep_surface_arrays,
	}


func _make_roads(terrain: TerrainNoise, cfg: Dictionary) -> RoadNetwork:
	var roads := RoadNetwork.new()
	# La red jerarquica se construye en C++ sobre el suelo final; la simple, aqui sobre T0.
	if not hierarchical_roads:
		roads.generate_roads(terrain, grid_size, cell_size, cfg)
	return roads


# ---------------------------------------------------------------------------
# Mostrar el resultado
# ---------------------------------------------------------------------------

func _show(builder: TerrainMesh, roads: RoadNetwork, generated: ArrayMesh, label: String, t0: int) -> void:
	mesh = generated
	ground_bytes = builder.get_ground_heights().to_byte_array()
	last_surface = builder
	last_roads = roads
	last_road_count = roads.get_road_count()
	terrain_world.set_surface(builder, roads)
	_clear_details()
	_add_detail("AguaGenerada", builder.get_water_mesh(), Color(0.08, 0.36, 0.53))
	_add_detail("PuentesGenerados", builder.get_bridge_mesh(), Color(0.20, 0.22, 0.24))
	_apply_material(builder.get_surface_heights())
	if vegetation_enabled:
		_build_vegetation()
	print("%s en %.1f s (erosiones acumuladas: %d)" % [label, (Time.get_ticks_msec() - t0) / 1000.0, terrain_snapshot.get("erosions", []).size()])


## Direccion HACIA el sol a partir de azimut y elevacion (coordenadas esfericas).
func sun_direction() -> Vector3:
	var az := deg_to_rad(sun_azimuth)
	var el := deg_to_rad(sun_elevation)
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()


func _update_sun(sun_moved := false) -> void:
	if not is_inside_tree():
		return
	var to_sun := sun_direction()
	var light := get_parent().get_node_or_null("Lighting") as DirectionalLight3D if get_parent() else null
	if light != null:
		# Una DirectionalLight3D ilumina hacia su -Z: se orienta mirando en contra del sol.
		light.global_basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.999 else Vector3.FORWARD)
	if material_override is ShaderMaterial:
		# El shader trabaja en el espacio del terreno: se quita la rotacion del nodo.
		material_override.set_shader_parameter("sun_direction", (global_basis.inverse() * to_sun).normalized())
		TerrainVegetation.sync_lighting(material_override, to_sun)
	# La sombra del terreno sobre cada planta se calcula en C++: se rehace cuando el sol se queda quieto.
	if sun_moved and vegetation != null and last_surface != null:
		_sun_timer = get_tree().create_timer(0.5)
		var timer := _sun_timer
		timer.timeout.connect(func():
			if timer == _sun_timer:
				_build_vegetation())


## Mapa de alturas de la malla final para el ray tracing de sombras del shader.
func _update_height_map(material: ShaderMaterial, heights: PackedFloat32Array) -> void:
	var n := grid_size + 1
	if heights.size() != n * n:
		heights = _heights_from_mesh(n)
	if heights.size() != n * n:
		material.set_shader_parameter("map_cells", 2.0)
		return
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	material.set_shader_parameter("height_map", ImageTexture.create_from_image(image))
	material.set_shader_parameter("map_cells", float(n))
	material.set_shader_parameter("map_cell_size", cell_size)
	var top := -INF
	for i in range(0, heights.size(), 3):
		top = maxf(top, heights[i])
	material.set_shader_parameter("map_max_height", top + 5.0)


## Rios en el shader: textura RGBA8 con distancia con signo a la orilla, semiancho y corriente.
func _update_river_map(material: ShaderMaterial) -> void:
	var data: Dictionary = last_surface.get_river_map() if last_surface != null else {}
	var size: int = data.get("size", 0)
	if size < 2 or water_style == 1:
		material.set_shader_parameter("rivers_enabled", false)
		return
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data["rgba"])
	material.set_shader_parameter("river_map", ImageTexture.create_from_image(image))
	var level_size: int = data.get("level_size", 0)
	if level_size > 1:
		var level := Image.create_from_data(level_size, level_size, false, Image.FORMAT_RF, (data["level"] as PackedFloat32Array).to_byte_array())
		material.set_shader_parameter("river_level_map", ImageTexture.create_from_image(level))
	material.set_shader_parameter("river_map_size", float(size))
	material.set_shader_parameter("river_extent", float(data["extent"]))
	material.set_shader_parameter("rivers_enabled", true)


## Al abrir una escena guardada no hay TerrainMesh: las alturas salen de los vertices.
func _heights_from_mesh(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != n * n:
		return out
	out.resize(n * n)
	for i in vertices.size():
		out[i] = vertices[i].y
	return out


## Texturas si la malla trae UV y pesos de region; si no, colores por vertice.
func _apply_material(heights := PackedFloat32Array()) -> void:
	if mesh == null:
		return
	var array_mesh := mesh as ArrayMesh
	var custom := Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1
	var has_data := array_mesh != null and array_mesh.get_surface_count() > 0 \
			and (array_mesh.surface_get_format(0) & custom) == custom
	if use_textures and has_data:
		var textured := TerrainTextures.get_material()
		_update_snow_line(textured)
		_update_height_map(textured, heights)
		_update_river_map(textured)
		textured.set_shader_parameter("canopy_enabled", false)
		material_override = textured
		_update_sun()
		return
	if use_textures:
		print("Esta malla es anterior a las texturas e iluminacion (no trae UV ni pesos de region). Usa '1. Generar terreno nuevo (T0)' para verla con texturas.")
	# Colores por vertice: se reutiliza el material guardado en la escena si lo hay.
	if _saved_material != null and not (_saved_material is ShaderMaterial):
		material_override = _saved_material
		return
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	material_override = plain


## Nieve solo en los picos: por percentil, no por rango. Con una sierra en meseta,
## "80% de la altura maxima" cubria casi toda la sierra; el percentil no depende de eso.
func _update_snow_line(material: ShaderMaterial) -> void:
	var heights := ground_bytes.to_float32_array()
	if heights.is_empty():
		return
	var sample := PackedFloat32Array()
	for i in range(0, heights.size(), 7):
		sample.append(heights[i])
	sample.sort()
	var start := sample[int((sample.size() - 1) * snow_percentile)]
	var top := sample[sample.size() - 1]
	material.set_shader_parameter("snow_start", start)
	material.set_shader_parameter("snow_end", start + 0.35 * maxf(top - start, 1.0))
	print("Nieve: desde %.1f m hasta %.1f m (suelo entre %.1f y %.1f m, percentil %.3f)" % [start, start + 0.35 * maxf(top - start, 1.0), sample[0], top, snow_percentile])


## Vegetacion con MultiMesh (S14). No se guarda en el .tscn: se rehace al abrir la escena.
func _build_vegetation() -> void:
	if vegetation != null and is_instance_valid(vegetation):
		vegetation.clear()
	if not vegetation_enabled or last_surface == null or last_terrain == null:
		if vegetation != null and is_instance_valid(vegetation):
			vegetation.queue_free()
			vegetation = null
		_set_canopy(null)
		return
	if vegetation == null or not is_instance_valid(vegetation):
		vegetation = TerrainVegetation.new()
		vegetation.name = "Vegetacion"
		add_child(vegetation)  # Sin owner: no se guarda en la escena.
	vegetation.density = vegetation_density
	var snow := INF
	if material_override is ShaderMaterial:
		var s = material_override.get_shader_parameter("snow_start")
		if s != null:
			snow = float(s)
	vegetation.build(last_surface, last_terrain, {"seed": noise_seed, "snow_height": snow,
		"sun_direction": (global_basis.inverse() * sun_direction()).normalized(), "chunk_cells": 128})
	_set_canopy(vegetation.canopy_texture)
	if material_override is ShaderMaterial:
		TerrainVegetation.sync_lighting(material_override, sun_direction())


## Sombra suave de las copas sobre el suelo (contacto), en el shader del terreno.
func _set_canopy(texture: Texture2D) -> void:
	if material_override is ShaderMaterial:
		material_override.set_shader_parameter("canopy_enabled", texture != null)
		if texture != null:
			material_override.set_shader_parameter("canopy_map", texture)


func _clear_details() -> void:
	for detail in _generated_details:
		if is_instance_valid(detail):
			remove_child(detail)
			detail.queue_free()
	_generated_details.clear()


func _add_detail(detail_name: String, detail_mesh: ArrayMesh, color: Color) -> void:
	if detail_mesh == null or detail_mesh.get_surface_count() == 0:
		return
	var detail := MeshInstance3D.new()
	detail.name = detail_name
	detail.mesh = detail_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 0.35 if detail_name == "AguaGenerada" else 0.9
	detail.material_override = material
	add_child(detail)  # Sin owner: no se guarda en el .tscn, se rehace al abrir la escena.
	_generated_details.append(detail)
