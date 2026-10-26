@tool
class_name ErosionCaptures
extends RefCounted
## Capturas de la evolucion del terreno durante la erosion (S14: figuras del pipeline y
## tabla de tiempos).
##
## Cada vez que se aplica la erosion se crea una carpeta con la fecha y hora, por ejemplo
## output/capturas_erosion/2026-10-25_19-45-12/, con:
##   mapa/          vista desde arriba (sombreado + color por region y altura)
##   perspectiva/   vista 3D oblicua (ray tracing por software del heightfield)
##   diferencia/    cuanto bajo (azul) o subio (rojo) cada punto respecto a T0
##   godot/         render real de Godot con texturas e iluminacion (solo con ventana)
##   etapas/        una figura por etapa del pipeline (regiones, dureza, drenaje, ...)
##   mosaico_*.png  todas las capturas en una sola imagen
##   capturas.csv   una fila por captura: iteraciones, tiempo, volumenes, pendientes
##   tiempos.csv    tiempo de cada proceso por resolucion (ms por iteracion)
##   resumen.md     parametros, tabla de tiempos y lista de archivos
##
## Nombre de cada captura: numero de orden, iteraciones acumuladas de erosion fluvial,
## termica y deposicion, y la resolucion. Por ejemplo
##   07_erosion03750_termica00600_deposicion02000_513px.png
## significa: 7a foto, despues de 3750 pasos de erosion fluvial, 600 de termica y 2000
## de deposicion (sumando todas las resoluciones), en una grilla de 513 x 513.

const STAGE_LAYERS := [
	["t0", "01_T0_terreno_inicial", "T0: ruido Perlin/fBm + regiones"],
	["regiones", "02_regiones", "Regiones: costa (arena), sierra (cafe), selva (verde)"],
	["dureza", "03_dureza_rho", "Dureza rho(p) (paper 4.2)"],
	["talud", "04_talud_s0", "Pendiente critica s0(p) (paper 4.3)"],
	["cambio_erosion", "05_cambio_por_erosion", "Cambio por erosion: azul baja, rojo sube"],
	["retarget_puntos", "06_retargeting_puntos_control", "Retargeting: puntos de control C (crestas)"],
	["retarget_error", "07_retargeting_error_E", "Retargeting: mapa de error E difundido"],
	["antes_breach", "08_antes_del_breaching", "Terreno erosionado antes del breaching"],
	["breach_cut", "09_breaching_material_retirado", "Breaching multiescala: material retirado"],
	["drenaje", "10_drenaje_log10", "Area de drenaje log10 (paper 4.1)"],
	["rios", "11_rios", "Rios (campo de distancia del shader)"],
	["ao", "12_iluminacion_global_AO", "Visibilidad del cielo (AO por ray tracing)"],
	["vegetacion", "13_vegetacion_sombra_copas", "Vegetacion: sombra de las copas"],
	["superficie", "14_superficie_final", "Superficie final con caminos"],
]


## Carpeta base por defecto: <repo>/output/capturas_erosion (fuera de res://, Godot no la importa).
static func default_base_folder() -> String:
	var project := ProjectSettings.globalize_path("res://")
	if project.is_empty() or OS.has_feature("template"):
		return ProjectSettings.globalize_path("user://capturas_erosion")
	return project.path_join("..").path_join("output").path_join("capturas_erosion").simplify_path()


## Crea base/<fecha>_<hora>/ y devuelve su ruta. Si ya existe (dos en el mismo segundo), agrega _2, _3...
static func make_run_folder(base: String) -> String:
	if base.is_empty():
		base = default_base_folder()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var folder := base.path_join(stamp)
	var k := 2
	while DirAccess.dir_exists_absolute(folder):
		folder = base.path_join("%s_%d" % [stamp, k])
		k += 1
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


static func capture_name(info: Dictionary) -> String:
	var name := "%02d_erosion%05d_termica%05d_deposicion%05d_%dpx" % [info["index"], info["fluvial"], info["thermal"], info["deposition"], info["samples"]]
	if info["stage"] == "T0":
		name += "_T0"
	elif info["stage"] == "retarget":
		name += "_retargeting"
	return name


static func capture_label(info: Dictionary) -> String:
	var stage: String = info["stage_es"]
	if info["stage"] == "T0" or info["stage"] == "retarget":
		return "%02d  %s  %dpx" % [info["index"], stage.to_upper(), info["samples"]]
	return "%02d  %s %d/%d  %dpx  nivel %d/%d" % [info["index"], stage.to_upper(), info["iteration"], info["stage_total"], info["samples"], info["level"] + 1, info["levels"] + 1]


static func capture_sublabel(info: Dictionary) -> String:
	return "E %d  T %d  D %d   %.1f s" % [info["fluvial"], info["thermal"], info["deposition"], info["seconds"]]


## Escribe todo lo que no necesita la GPU (se puede llamar desde un hilo).
## options: map, perspective, difference, size (Vector2i), map_size, params (Dictionary), sun (Vector2 azimut/elevacion).
static func write_software(builder: TerrainMesh, folder: String, options: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var size: Vector2i = options.get("size", Vector2i(1280, 720))
	var map_size: int = options.get("map_size", 1024)
	var sun: Vector2 = options.get("sun", Vector2(135.0, 28.0))
	var count := builder.get_capture_count()
	var rows := []
	var tiles_map: Array[Image] = []
	var tiles_persp: Array[Image] = []
	for sub in ["mapa", "perspectiva", "diferencia", "etapas"]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(sub))
	for i in count:
		var info := builder.get_capture_info(i)
		var stats := builder.get_capture_stats(i)
		var name := capture_name(info)
		var label := {"label": capture_label(info), "sublabel": capture_sublabel(info), "sun_azimuth": sun.x, "sun_elevation": sun.y}
		if options.get("map", true):
			var img := _image(builder.render_capture(i, "mapa", map_size, map_size, label), map_size, map_size)
			img.save_png(folder.path_join("mapa").path_join(name + ".png"))
			tiles_map.append(img)
		if options.get("perspective", true):
			var img := _image(builder.render_capture(i, "perspectiva", size.x, size.y, label), size.x, size.y)
			img.save_png(folder.path_join("perspectiva").path_join(name + ".png"))
			tiles_persp.append(img)
		if options.get("difference", true) and i > 0:
			var img := _image(builder.render_capture(i, "diferencia", map_size, map_size, label), map_size, map_size)
			img.save_png(folder.path_join("diferencia").path_join(name + ".png"))
		var row := info.duplicate()
		row.merge(stats)
		row["file"] = name + ".png"
		rows.append(row)
	if not tiles_map.is_empty():
		_mosaic(tiles_map, 480).save_png(folder.path_join("mosaico_mapa.png"))
	if not tiles_persp.is_empty():
		_mosaic(tiles_persp, 640).save_png(folder.path_join("mosaico_perspectiva.png"))
	var figures := write_stage_figures(builder, folder.path_join("etapas"), options)
	_write_captures_csv(folder.path_join("capturas.csv"), rows)
	_write_timings(folder, builder, options)
	_write_summary(folder, builder, rows, figures, options)
	return {"captures": count, "figures": figures.size(), "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "folder": folder}


## Una figura por etapa del pipeline (capas que dejo la ultima corrida de C++).
static func write_stage_figures(builder: TerrainMesh, folder: String, options: Dictionary) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(folder)
	var size: int = options.get("map_size", 1024)
	var names := builder.get_layer_names()
	var written := PackedStringArray()
	for entry in STAGE_LAYERS:
		if not names.has(entry[0]):
			continue
		var bytes := builder.render_layer(entry[0], size, {"label": entry[2]})
		if bytes.is_empty():
			continue
		_image(bytes, size, size).save_png(folder.path_join(entry[1] + ".png"))
		written.append(entry[1] + ".png")
	# Vista final en perspectiva con rios (para la portada del informe).
	var sun: Vector2 = options.get("sun", Vector2(135.0, 28.0))
	var big: Vector2i = options.get("size", Vector2i(1280, 720))
	var final_view := builder.render_surface("perspectiva", big.x, big.y, {"label": "Superficie final (erosion + retargeting + breaching + rios + caminos)", "sun_azimuth": sun.x, "sun_elevation": sun.y})
	if not final_view.is_empty():
		_image(final_view, big.x, big.y).save_png(folder.path_join("15_final_perspectiva.png"))
		written.append("15_final_perspectiva.png")
	return written


## Render real de Godot de cada captura (texturas, sombras por ray tracing, AO). Necesita
## ventana (no funciona con --headless). Es una corrutina: usar con await.
static func write_godot_views(host: Node, builder: TerrainMesh, terrain: TerrainNoise, folder: String, options: Dictionary) -> int:
	if DisplayServer.get_name() == "headless" or not host.is_inside_tree():
		return 0
	var size: Vector2i = options.get("size", Vector2i(1280, 720))
	var sub := folder.path_join("godot")
	DirAccess.make_dir_recursive_absolute(sub)
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp, false, Node.INTERNAL_MODE_BACK)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	env.environment = environment
	vp.add_child(env)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	var base := TerrainTextures.get_material()
	var material := base.duplicate() as ShaderMaterial
	var sun_dir: Vector3 = options.get("sun_direction", Vector3(0.5, 0.6, 0.4))
	material.set_shader_parameter("sun_direction", sun_dir)
	for param in ["snow_start", "snow_end"]:
		if options.has(param):
			material.set_shader_parameter(param, options[param])
	material.set_shader_parameter("rivers_enabled", false)
	mi.material_override = material
	var written := 0
	for i in builder.get_capture_count():
		var info := builder.get_capture_info(i)
		var n: int = info["samples"]
		var cell: float = info["cell"]
		mi.mesh = builder.build_capture_mesh(i, terrain, {"ao_directions": 8})
		var heights := builder.get_capture_heights(i)
		var image := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
		material.set_shader_parameter("height_map", ImageTexture.create_from_image(image))
		material.set_shader_parameter("map_cells", float(n))
		material.set_shader_parameter("map_cell_size", cell)
		var top := -INF
		for k in range(0, heights.size(), 3):
			top = maxf(top, heights[k])
		material.set_shader_parameter("map_max_height", top + 5.0)
		_place_camera(cam, options, (n - 1) * cell, top)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := vp.get_texture().get_image()
		if shot != null and not shot.is_empty():
			shot.convert(Image.FORMAT_RGB8)
			shot.save_png(sub.path_join(capture_name(info) + ".png"))
			written += 1
	vp.queue_free()
	return written


static func _place_camera(cam: Camera3D, options: Dictionary, extent: float, top: float) -> void:
	if options.has("camera_transform"):
		cam.global_transform = options["camera_transform"]
		cam.fov = options.get("camera_fov", 60.0)
		cam.far = maxf(cam.far, extent * 4.0)
		return
	# Camara de reporte: mira el centro del mapa desde el suroeste, a 35 grados.
	var az := deg_to_rad(225.0)
	var el := deg_to_rad(35.0)
	var dist := extent * 1.05
	var target := Vector3(0, top * 0.4, 0)
	cam.position = target + Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)) * dist
	cam.look_at(target)
	cam.fov = 50.0
	cam.far = extent * 5.0


static func _image(bytes: PackedByteArray, w: int, h: int) -> Image:
	if bytes.size() != w * h * 3:
		return Image.create(w, h, false, Image.FORMAT_RGB8)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes)


## Junta las imagenes en una grilla (4 columnas) con el ancho de cada mosaico dado.
static func _mosaic(images: Array[Image], tile_w: int) -> Image:
	var cols := mini(4, images.size())
	var rows := ceili(images.size() / float(cols))
	var src := images[0]
	var tile_h := int(round(tile_w * float(src.get_height()) / src.get_width()))
	var out := Image.create(cols * tile_w, rows * tile_h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.1, 0.1, 0.1))
	for k in images.size():
		var tile := images[k].duplicate() as Image
		tile.resize(tile_w, tile_h, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(tile, Rect2i(0, 0, tile_w, tile_h), Vector2i((k % cols) * tile_w, (k / cols) * tile_h))
	return out


static func _write_captures_csv(path: String, rows: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var columns := ["index", "file", "stage", "level", "samples", "cell", "iteration", "stage_total", "fluvial", "thermal", "deposition",
		"level_fluvial", "level_thermal", "level_deposition", "global_iteration", "total_iterations", "seconds",
		"min_height", "max_height", "mean_height", "relief", "eroded_volume_m3", "deposited_volume_m3", "rms_change_m", "mean_slope"]
	var header := ["indice", "archivo", "etapa", "nivel", "resolucion", "celda_m", "iter_etapa", "total_etapa", "erosion_acum", "termica_acum", "deposicion_acum",
		"erosion_nivel", "termica_nivel", "deposicion_nivel", "iter_global", "iter_total", "segundos",
		"h_min_m", "h_max_m", "h_media_m", "relieve_m", "vol_erosionado_m3", "vol_depositado_m3", "cambio_rms_m", "pendiente_media"]
	f.store_line(",".join(header))
	for row: Dictionary in rows:
		var values := PackedStringArray()
		for c in columns:
			var v = row.get(c, "")
			values.append(("%.4f" % v) if typeof(v) == TYPE_FLOAT else str(v))
		f.store_line(",".join(values))


## Tiempos por resolucion y proceso (ms por iteracion, para comparar con la Tabla 2 del paper).
static func _write_timings(folder: String, builder: TerrainMesh, options: Dictionary) -> void:
	var t := builder.get_timings()
	var f := FileAccess.open(folder.path_join("tiempos.csv"), FileAccess.WRITE)
	if f == null:
		return
	f.store_line("etapa,resolucion,iteraciones,segundos,ms_por_iteracion")
	for level: Dictionary in t.get("erosion_levels", []):
		for p in [["fluvial", "erosion_fluvial"], ["thermal", "termica"], ["deposition", "deposicion"]]:
			var it: int = level[p[0] + "_iterations"]
			var s: float = level[p[0] + "_seconds"]
			f.store_line("%s,%d,%d,%.4f,%.4f" % [p[1], level["samples"], it, s, (s * 1000.0 / it) if it > 0 else 0.0])
	for key in ["t0", "retarget", "breach", "drainage", "rivers", "roads", "road_raster", "ao", "mesh", "total"]:
		if t.has(key):
			f.store_line("%s,%d,,%.4f," % [key, int(options.get("params", {}).get("grid_size", 0)) + 1, t[key]])
	if options.has("captures_seconds"):
		f.store_line("capturas,,,%.4f," % options["captures_seconds"])


static func _write_summary(folder: String, builder: TerrainMesh, rows: Array, figures: PackedStringArray, options: Dictionary) -> void:
	var f := FileAccess.open(folder.path_join("resumen.md"), FileAccess.WRITE)
	if f == null:
		return
	var params: Dictionary = options.get("params", {})
	var t := builder.get_timings()
	f.store_line("# Evolucion de la erosion (%s)" % folder.get_file())
	f.store_line("")
	f.store_line("Terreno: semilla %s, %s celdas x %s m = %s m. Niveles de upsampling: %s." % [params.get("noise_seed", "?"), params.get("grid_size", "?"),
		params.get("cell_size", "?"), str(float(params.get("grid_size", 0)) * float(params.get("cell_size", 0))), params.get("erosion_levels", "?")])
	f.store_line("")
	f.store_line("## Receta de iteraciones por resolucion")
	f.store_line("")
	f.store_line("| Resolucion | Fluvial | Termica | Deposicion | Tiempo fluvial (s) | Tiempo termica (s) | Tiempo deposicion (s) | ms/iter E | ms/iter T | ms/iter D |")
	f.store_line("|---|---|---|---|---|---|---|---|---|---|")
	for level: Dictionary in t.get("erosion_levels", []):
		var cells := []
		for p in ["fluvial", "thermal", "deposition"]:
			var it: int = level[p + "_iterations"]
			cells.append((level[p + "_seconds"] * 1000.0 / it) if it > 0 else 0.0)
		f.store_line("| %d x %d | %d | %d | %d | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f |" % [level["samples"], level["samples"], level["fluvial_iterations"],
			level["thermal_iterations"], level["deposition_iterations"], level["fluvial_seconds"], level["thermal_seconds"], level["deposition_seconds"],
			cells[0], cells[1], cells[2]])
	f.store_line("")
	f.store_line("Paper (Tabla 2, GPU GTX 3080, ms por iteracion): 256 -> E 0.027, T 0.007, D 0.055; 512 -> E 0.093, T 0.018, D 0.188; 1024 -> E 0.33, T 0.06, D 0.69.")
	f.store_line("")
	f.store_line("## Otras etapas")
	f.store_line("")
	f.store_line("| Etapa | Segundos |")
	f.store_line("|---|---|")
	var names := {"t0": "T0 (ruido)", "erosion": "Erosion multiescala (total)", "retarget": "Retargeting (paper 5.1)", "breach": "Breaching multiescala (paper 5.2)",
		"drainage": "Drenaje", "rivers": "Mapa de rios", "roads": "Red vial", "road_raster": "Caminos sobre la malla", "ao": "AO (ray tracing)", "mesh": "Malla", "total": "Total"}
	for key in names:
		if t.has(key):
			f.store_line("| %s | %.2f |" % [names[key], t[key]])
	if options.has("captures_seconds"):
		f.store_line("| Capturas (render por software) | %.2f |" % options["captures_seconds"])
	var rt := builder.get_retarget_info()
	if not rt.is_empty():
		f.store_line("")
		f.store_line("## Retargeting (paper 5.1)")
		f.store_line("")
		f.store_line("- Puntos de control: %d (%.1f%% del mapa), umbral a0 = %s celdas, %d iteraciones de difusion." % [rt["constrained_points"], rt["constrained_fraction"] * 100.0, rt["threshold_cells"], rt["iterations"]])
		f.store_line("- Cuanto habia bajado la erosion en esos puntos: promedio %.2f m, maximo %.2f m." % [rt["mean_delta"], rt["max_delta"]])
		f.store_line("- Error en los puntos de control despues del retargeting: %.6f m (deberia ser ~0)." % rt["max_constraint_error"])
	f.store_line("")
	f.store_line("## Capturas")
	f.store_line("")
	f.store_line("| # | Archivo | Etapa | Resolucion | E | T | D | s | Relieve (m) | Vol. erosionado (m3) | Vol. depositado (m3) | Pendiente media |")
	f.store_line("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r: Dictionary in rows:
		f.store_line("| %d | %s | %s | %d | %d | %d | %d | %.1f | %.1f | %.0f | %.0f | %.3f |" % [r["index"], r["file"], r["stage_es"], r["samples"], r["fluvial"],
			r["thermal"], r["deposition"], r["seconds"], r["relief"], r["eroded_volume_m3"], r["deposited_volume_m3"], r["mean_slope"]])
	f.store_line("")
	f.store_line("## Figuras por etapa (carpeta etapas/)")
	f.store_line("")
	for fig in figures:
		f.store_line("- %s" % fig)
