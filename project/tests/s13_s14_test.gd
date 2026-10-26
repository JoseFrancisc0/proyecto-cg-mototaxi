extends SceneTree
## Pruebas de lo agregado en S12-S14 (CG):
##   - capturas de la evolucion de la erosion (orden, nombres, contadores, archivos);
##   - retargeting (paper 5.1): los puntos de control vuelven exactamente a T0;
##   - upsampling lineal/bicubico y receta por nivel;
##   - rios en el shader (campo de distancia) y nivel del agua;
##   - vegetacion (nunca en el agua, en caminos ni en pendientes prohibidas);
##   - landmarks por tipo (picos, confluencias, costa);
##   - chunks con LOD y colision por chunk;
##   - avance para la pantalla de carga y generacion en otro hilo.
##   godot --headless --path project -s res://tests/s13_s14_test.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var noise := TerrainNoise.new()
	noise.set_seed(7)
	noise.configure_regions({"enabled": true, "extent": 512.0, "region_patches": 16})
	var builder := TerrainMesh.new()
	builder.set_capture_options({"count": 6, "stage_ends": true, "keep": true, "preview_size": 160})
	var cfg := {"erosion_enabled": true, "erosion_fluvial": 120, "erosion_thermal": 40, "erosion_deposition": 80, "erosion_levels": 2,
		"regional_erosion_maps": true, "retarget_enabled": true, "retarget_threshold": 1.0, "retarget_iterations": 200,
		"hydrology_enabled": true, "river_catchment": 4000.0, "hierarchical_roads": true, "town_count": 3, "num_points": 4, "keep_arrays": true}
	var mesh := builder.generate_mesh(noise, RoadNetwork.new(), 256, 2.0, cfg)
	check(mesh != null, "generate_mesh con erosion, retargeting y rios")

	# --- Capturas ---
	var count := builder.get_capture_count()
	check(count >= 6, "capturas guardadas: %d" % count)
	var first := builder.get_capture_info(0)
	check(first["stage"] == "T0" and first["samples"] == 257 and first["fluvial"] == 0, "la primera captura es T0 a resolucion completa")
	var last_counts := [-1, -1, -1]
	var monotonic := true
	var seen_levels := {}
	for i in count:
		var info := builder.get_capture_info(i)
		var c := [info["fluvial"], info["thermal"], info["deposition"]]
		for k in 3:
			if c[k] < last_counts[k]:
				monotonic = false
		last_counts = c
		seen_levels[info["samples"]] = true
		var name := ErosionCaptures.capture_name(info)
		check(name.begins_with("%02d_erosion%05d_termica%05d_deposicion%05d_%dpx" % [i, c[0], c[1], c[2], info["samples"]]), "nombre %s" % name)
	check(monotonic, "los contadores de epocas nunca bajan")
	check(seen_levels.has(65) and seen_levels.has(129) and seen_levels.has(257), "hay capturas de las 3 resoluciones %s" % [seen_levels.keys()])
	var plan := TerrainMesh.get_erosion_plan(257, cfg)
	var total := [0, 0, 0]
	for p in plan:
		total[0] += p["fluvial"]
		total[1] += p["thermal"]
		total[2] += p["deposition"]
	check(last_counts == total, "la ultima captura suma toda la receta %s = %s" % [last_counts, total])
	check(builder.get_capture_info(count - 1)["stage"] == "retarget", "la ultima captura es despues del retargeting")
	var pv := builder.get_preview()
	check(pv["serial"] > 0 and (pv["rgb"] as PackedByteArray).size() == pv["width"] * pv["height"] * 3, "vista previa para la pantalla de carga")
	var progress := builder.get_progress()
	check(is_equal_approx(progress["fraction"], 1.0), "avance al 100%% al terminar (%s)" % progress["stage"])

	# Archivos de las capturas (sin GPU: mapa, perspectiva, diferencia, etapas, CSV y resumen).
	var folder := ErosionCaptures.make_run_folder(OS.get_user_data_dir().path_join("test_capturas"))
	var res := ErosionCaptures.write_software(builder, folder, {"size": Vector2i(320, 180), "map_size": 256, "params": {"grid_size": 256, "cell_size": 2.0}})
	check(res["captures"] == count, "se escribieron %d capturas en %s" % [res["captures"], folder])
	check(folder.get_file().length() >= 19 and folder.get_file()[4] == "-", "la carpeta se llama con la fecha: %s" % folder.get_file())
	check(DirAccess.get_files_at(folder.path_join("mapa")).size() == count, "mapa/ tiene una imagen por captura")
	check(DirAccess.get_files_at(folder.path_join("perspectiva")).size() == count, "perspectiva/ tiene una imagen por captura")
	check(DirAccess.get_files_at(folder.path_join("etapas")).size() >= 10, "etapas/ tiene las figuras del pipeline (%d)" % DirAccess.get_files_at(folder.path_join("etapas")).size())
	for f in ["capturas.csv", "tiempos.csv", "resumen.md", "mosaico_mapa.png", "mosaico_perspectiva.png"]:
		check(FileAccess.file_exists(folder.path_join(f)), "existe %s" % f)
	var csv := FileAccess.get_file_as_string(folder.path_join("capturas.csv")).split("\n", false)
	check(csv.size() == count + 1, "capturas.csv: encabezado + %d filas" % count)

	# --- Retargeting ---
	var rt := builder.get_retarget_info()
	check(rt["constrained_points"] > 0, "retargeting: %d puntos de control (%.1f%%)" % [rt["constrained_points"], rt["constrained_fraction"] * 100.0])
	check(rt["max_constraint_error"] < 1e-6, "los puntos de control vuelven exactamente a T0 (error %.8f m)" % rt["max_constraint_error"])
	check(rt["mean_delta"] > 0.0, "la erosion habia bajado las crestas (%.2f m en promedio)" % rt["mean_delta"])

	# --- Upsampling ---
	var tiny := PackedFloat32Array([0, 0, 0, 0, 9, 0, 0, 0, 0])
	var lin := TerrainMesh.upsample_heightfield(tiny, 3, false)
	var cub := TerrainMesh.upsample_heightfield(tiny, 3, true)
	check(lin.size() == 25 and is_equal_approx(lin[12], 9.0) and is_equal_approx(lin[7], 4.5), "upsampling lineal conserva los puntos y promedia en el medio")
	check(is_equal_approx(cub[12], 9.0) and cub[7] > 4.5, "upsampling bicubico conserva los puntos y es mas curvo (%.3f)" % cub[7])

	# --- Rios ---
	var rm := builder.get_river_map()
	var rsize: int = rm["size"]
	check(rsize == 513 and (rm["rgba"] as PackedByteArray).size() == rsize * rsize * 4, "mapa de rios %dx%d (2 texels por celda)" % [rsize, rsize])
	var rgba: PackedByteArray = rm["rgba"]
	var inside := 0
	for k in range(0, rgba.size(), 4):
		if rgba[k] < 127:
			inside += 1
	check(inside > 0, "hay texels dentro del agua: %d" % inside)
	var hyd := builder.get_hydrology_data()
	var channels: PackedInt32Array = hyd["channels"]
	var n := 257
	var bad := 0
	var checked := 0
	for i in range(0, channels.size(), 3):
		if channels[i] == 1 and hyd["receivers"][i] >= 0:
			var x := i % n
			var z := i / n
			var s: float = (rgba[(z * 2 * rsize + x * 2) * 4] / 255.0 - 0.5) * 16.0
			checked += 1
			if s > 0.0:
				bad += 1
	check(checked > 0 and bad == 0, "todo cauce queda dentro del agua del mapa (%d revisados)" % checked)
	check((rm["level"] as PackedFloat32Array).size() == n * n, "nivel del agua por muestra")

	# --- Vegetacion ---
	var veg := builder.scatter_vegetation(noise, TerrainVegetation.SPECIES, {"seed": 3})
	check(veg["total"] > 100, "vegetacion: %d plantas" % veg["total"])
	var heights := builder.get_surface_heights()
	var in_water := 0
	var steep := 0
	var species: Dictionary = veg["species"]
	for name: String in species:
		var rule: Dictionary = {}
		for r in TerrainVegetation.SPECIES:
			if r["name"] == name:
				rule = r
		for buffer: PackedFloat32Array in (species[name]["chunks"] as Dictionary).values():
			for k in range(0, buffer.size(), 20):
				var x: float = buffer[k + 3]
				var z: float = buffer[k + 11]
				var ix := clampi(roundi((x + 256.0) / 2.0), 0, 256)
				var iz := clampi(roundi((z + 256.0) / 2.0), 0, 256)
				var s: float = (rgba[(iz * 2 * rsize + ix * 2) * 4] / 255.0 - 0.5) * 16.0
				if s < 0.0:
					in_water += 1
				var hx := (heights[iz * n + mini(ix + 1, 256)] - heights[iz * n + maxi(ix - 1, 0)]) / 4.0
				var hz := (heights[mini(iz + 1, 256) * n + ix] - heights[maxi(iz - 1, 0) * n + ix]) / 4.0
				var slope := 1.0 - 1.0 / sqrt(1.0 + hx * hx + hz * hz)
				if slope > float(rule.get("slope_max", 1.0)) + 0.15:
					steep += 1
	check(in_water == 0, "ninguna planta dentro de un rio")
	check(steep * 100 <= veg["total"], "plantas sobre su pendiente maxima: %d de %d" % [steep, veg["total"]])
	check((veg["canopy"] as PackedByteArray).size() == n * n, "mapa de sombra de copas %dx%d" % [n, n])

	# --- Landmarks por tipo ---
	var feats := builder.find_landmark_features(noise, {"min_spacing": 60.0, "peak_radius": 40.0, "edge_margin": 10.0})
	var types := {}
	for f: Dictionary in feats:
		types[f["type"]] = types.get(f["type"], 0) + 1
	check(types.has("pico"), "landmarks por tipo: %s" % types)
	check(feats.all(func(f): return f.has("label") and f.has("position")), "cada landmark trae nombre y posicion")

	# --- Chunks ---
	var chunks := builder.build_chunks(128, 2, 4.0)
	check(chunks.size() == 4, "256 celdas / 128 = 2 x 2 chunks")
	var c0: Dictionary = chunks[0]
	var cmesh: ArrayMesh = c0["mesh"]
	var samples: Vector2i = c0["samples"]
	check(samples == Vector2i(129, 129) and (c0["heights"] as PackedFloat32Array).size() == 129 * 129, "chunk de 129 x 129 muestras (bordes compartidos)")
	check(cmesh.get_surface_count() == 1 and cmesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "el chunk conserva UV, regiones y AO para el shader")
	check((c0["lod_errors"] as Array).size() == 2, "LOD con paso 2 y 4: errores %s" % [c0["lod_errors"]])

	# --- TerrainWorld en otro hilo (pantalla de carga) ---
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.grid_size = 256
	world.cell_size = 1.0
	world.generate_on_ready = false
	world.erosion_scale = 0.05
	world.vegetation_density = 0.3
	root.add_child(world)
	var fractions: Array[float] = []
	world.progress.connect(func(_s, f): fractions.append(f))
	var ok: bool = await world.generate_async(11)
	check(ok and world.is_generated(), "generate_async termina")
	var increasing := true
	for k in range(1, fractions.size()):
		if fractions[k] + 1e-6 < fractions[k - 1]:
			increasing = false
	check(fractions.size() > 3 and increasing and is_equal_approx(fractions[-1], 1.0), "el avance sube hasta 100%% (%d avisos)" % fractions.size())
	check(world.get_chunk_count() == 4, "TerrainWorld con 4 chunks")
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var max_err := 0.0
	var misses := 0
	for p in [Vector2(0.5, 0.5), Vector2(-100.2, 77.7), Vector2(120.3, -3.1), Vector2(-0.4, -127.0), Vector2(64.0, 64.0)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.y), Vector3(p.x, -500, p.y)))
		if hit.is_empty():
			misses += 1
		else:
			max_err = maxf(max_err, absf(hit.position.y - world.get_height(p.x, p.y)))
	check(misses == 0 and max_err < 0.5, "colision por chunk coincide con get_height (error %.3f m)" % max_err)

	print("Pruebas S12-S14: %d fallas" % failures)
	quit(0 if failures == 0 else 1)
