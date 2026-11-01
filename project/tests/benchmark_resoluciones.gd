extends SceneTree
## Tabla de tiempos por resolucion (S14 CG-A).
##
## Para cada resolucion (129, 257, 513 y 1025 muestras por lado, siempre el mismo mapa de
## 1536 m) mide:
##   1. Milisegundos por iteracion de cada proceso del paper (fluvial, termica, deposicion),
##      como la Tabla 2 del paper (que mide en GPU).
##   2. El tiempo de las demas etapas del pipeline (T0, retargeting, breaching, drenaje,
##      rios, red vial, AO por ray tracing, malla, vegetacion, chunks).
##   3. La receta completa del paper estimada (iteraciones x ms/iteracion de cada nivel).
## Escribe docs/tiempos/tabla_tiempos.md, .csv y .json.
##
##   godot --headless --path project -s res://tests/benchmark_resoluciones.gd
##   ... -- --iter=40          iteraciones por medicion (por defecto 30)
##   ... -- --full             ademas corre la receta completa real a 513 (para comprobar la estimacion)
##   ... -- --max=513          resolucion maxima (para equipos lentos)

const EXTENT := 1536.0
const SEED := 2
const PAPER_TABLE2 := {129: [0.025, 0.006, 0.030], 257: [0.027, 0.007, 0.055], 513: [0.093, 0.018, 0.188], 1025: [0.33, 0.06, 0.69]}
# Receta de PredefinedErosion() (main.cpp del repo oficial) por nivel.
const RECIPE := [[3000, 600, 2000], [1500, 1000, 700], [700, 2000, 200], [400, 6000, 150]]

var rows: Array[Dictionary] = []


func _initialize() -> void:
	var iterations := 30
	var full := false
	var max_n := 1025
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--iter="):
			iterations = maxi(1, int(arg.get_slice("=", 1)))
		elif arg == "--full":
			full = true
		elif arg.begins_with("--max="):
			max_n = int(arg.get_slice("=", 1))
	var cores := OS.get_processor_count()
	print("CPU: %s, %d hilos (la erosion usa hasta %d)" % [OS.get_processor_name(), cores, mini(8, cores)])
	var sizes := [129, 257, 513, 1025].filter(func(n): return n <= max_n)
	var per_iteration := {}
	for n: int in sizes:
		var grid: int = n - 1
		var cell := EXTENT / grid
		var row := {"samples": n, "cell_m": cell}
		# 1. ms por iteracion de cada proceso (una sola resolucion, sin multiescala), con los mapas
		#    regionales de dureza y talud como en el juego (la termica no evalua ruido por celda).
		var noise := _noise()
		var t0 := _t0(noise, n, cell)
		var maps := _regional_maps(noise, n, cell)
		for p in [["fluvial", 0], ["thermal", 1], ["deposition", 2]]:
			var cfg := {"fluvial": 0, "thermal": 0, "deposition": 0, "levels": 0, "hardness": maps[0], "talus": maps[1]}
			cfg[p[0]] = iterations
			var b := TerrainMesh.new()
			b.erode_heightfield(t0, n, cell, cfg)
			var level: Dictionary = b.get_timings()["erosion_levels"][0]
			row[p[0] + "_ms"] = level[p[0] + "_seconds"] * 1000.0 / iterations
		# Termica sin mapas regionales (como el repo oficial: angulo de talud con ruido simplex por celda).
		var b_noise := TerrainMesh.new()
		b_noise.erode_heightfield(t0, n, cell, {"fluvial": 0, "thermal": iterations, "deposition": 0, "levels": 0})
		row["thermal_noise_ms"] = b_noise.get_timings()["erosion_levels"][0]["thermal_seconds"] * 1000.0 / iterations
		per_iteration[n] = [row["fluvial_ms"], row["thermal_ms"], row["deposition_ms"]]
		# 2. Resto del pipeline: T0 + erosion corta + retargeting + superficie, con los tiempos de C++.
		var b2 := TerrainMesh.new()
		var cfg2 := {"erosion_enabled": true, "erosion_fluvial": 30, "erosion_thermal": 30, "erosion_deposition": 30, "erosion_levels": 0,
			"regional_erosion_maps": true, "retarget_enabled": true, "retarget_iterations": 500, "hydrology_enabled": true, "river_catchment": 60000.0,
			"hierarchical_roads": true, "town_count": 4, "num_points": 6, "keep_arrays": true}
		var tw := Time.get_ticks_msec()
		b2.generate_mesh(noise, RoadNetwork.new(), grid, cell, cfg2)
		var wall := (Time.get_ticks_msec() - tw) / 1000.0
		var tm: Dictionary = b2.get_timings()
		for key in ["t0", "retarget", "breach", "drainage", "rivers", "roads", "road_raster", "ao", "mesh"]:
			row[key + "_s"] = tm.get(key, 0.0)
		var tv := Time.get_ticks_msec()
		var veg: Dictionary = b2.scatter_vegetation(noise, TerrainVegetation.SPECIES, {"seed": SEED, "chunk_cells": 128})
		row["vegetation_s"] = (Time.get_ticks_msec() - tv) / 1000.0
		row["vegetation_count"] = veg.get("total", 0)
		var tc := Time.get_ticks_msec()
		var chunks := b2.build_chunks(128, 2, 6.0)
		row["chunks_s"] = (Time.get_ticks_msec() - tc) / 1000.0
		row["chunks"] = chunks.size()
		row["surface_wall_s"] = wall
		rows.append(row)
		print("%4d: E %.3f ms  T %.3f ms  D %.3f ms | T0 %.2f s, retarget %.2f s, breach %.2f s, drenaje %.2f s, vias %.2f s, AO %.2f s, malla %.2f s, vegetacion %.2f s (%d), chunks %.2f s" % [
			n, row["fluvial_ms"], row["thermal_ms"], row["deposition_ms"], row["t0_s"], row["retarget_s"], row["breach_s"], row["drainage_s"],
			row["roads_s"], row["ao_s"], row["mesh_s"], row["vegetation_s"], row["vegetation_count"], row["chunks_s"]])
	# 3. Receta completa estimada para cada mapa (base 129, mismos niveles que el editor).
	var estimates := []
	for n: int in sizes:
		var levels := 0
		var nb := n
		while nb > 129:
			nb = (nb - 1) / 2 + 1
			levels += 1
		var total := 0.0
		var detail := PackedStringArray()
		var nl := nb
		for level in levels + 1:
			if level > 0:
				nl = 2 * (nl - 1) + 1
			var ms: Array = per_iteration.get(nl, [0.0, 0.0, 0.0])
			var s: float = (RECIPE[level][0] * ms[0] + RECIPE[level][1] * ms[1] + RECIPE[level][2] * ms[2]) / 1000.0
			total += s
			detail.append("%d: %.1f s" % [nl, s])
		estimates.append({"samples": n, "levels": levels, "seconds": total, "detail": ", ".join(detail)})
	var measured := {}
	if full and 513 in sizes:
		var noise := _noise()
		var cell := EXTENT / 512
		var b := TerrainMesh.new()
		var t := Time.get_ticks_msec()
		var maps := _regional_maps(noise, 513, cell)
		b.erode_heightfield(_t0(noise, 513, cell), 513, cell, {"fluvial": 3000, "thermal": 600, "deposition": 2000, "levels": 2, "hardness": maps[0], "talus": maps[1]})
		measured = {"samples": 513, "levels": 2, "seconds": (Time.get_ticks_msec() - t) / 1000.0, "timings": b.get_timings()}
		print("Receta completa real a 513: %.1f s" % measured["seconds"])
	_write(rows, estimates, measured, iterations)
	quit(0)


func _noise() -> TerrainNoise:
	var noise := TerrainNoise.new()
	noise.set_seed(SEED)
	noise.configure_regions({"enabled": true, "extent": EXTENT, "region_patches": 32})
	return noise


func _regional_maps(noise: TerrainNoise, n: int, cell: float) -> Array:
	var hardness := PackedFloat32Array()
	var talus := PackedFloat32Array()
	hardness.resize(n * n)
	talus.resize(n * n)
	for z in n:
		for x in n:
			var wx := x * cell - EXTENT * 0.5
			var wz := z * cell - EXTENT * 0.5
			hardness[z * n + x] = noise.get_hardness(wx, wz)
			talus[z * n + x] = noise.get_critical_slope(wx, wz)
	return [hardness, talus]


func _t0(noise: TerrainNoise, n: int, cell: float) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n * n)
	for z in n:
		for x in n:
			h[z * n + x] = noise.get_height(x * cell - EXTENT * 0.5, z * cell - EXTENT * 0.5)
	return h


func _write(rows: Array[Dictionary], estimates: Array, measured: Dictionary, iterations: int) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../docs/tiempos").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var md := PackedStringArray()
	md.append("# Tabla de tiempos por resolucion")
	md.append("")
	md.append("Medido con `tests/benchmark_resoluciones.gd` el %s. CPU: %s, %d hilos (la erosion reparte las filas en hasta 8 hilos). Mapa de 1536 m, semilla %d, %d iteraciones por medicion." % [
		Time.get_datetime_string_from_system(false, true), OS.get_processor_name(), OS.get_processor_count(), SEED, iterations])
	md.append("")
	md.append("## Milisegundos por iteracion (comparar con la Tabla 2 del paper)")
	md.append("")
	md.append("| Resolucion | Fluvial | Termica (mapa s0) | Termica (ruido, como el repo) | Deposicion | Paper GPU: fluvial / termica / deposicion |")
	md.append("|---|---|---|---|---|---|")
	for r in rows:
		var p: Array = PAPER_TABLE2.get(r["samples"], [0, 0, 0])
		md.append("| %d x %d | %.3f | %.3f | %.3f | %.3f | %.3f / %.3f / %.3f |" % [r["samples"], r["samples"], r["fluvial_ms"], r["thermal_ms"], r["thermal_noise_ms"], r["deposition_ms"], p[0], p[1], p[2]])
	md.append("")
	md.append("La termica del juego usa el mapa regional s0(p) (paper 4.3); sin el, el repo oficial evalua ruido simplex 3D en cada celda y cada iteracion, que cuesta mas.")
	md.append("")
	md.append("El paper corre en una GPU (GTX 3080) con compute shaders; aqui es el port en CPU con hilos. El costo por iteracion crece con el numero de celdas (x4 al duplicar la resolucion), igual que en el paper.")
	md.append("")
	md.append("## Otras etapas (segundos)")
	md.append("")
	md.append("| Resolucion | T0 | Retargeting | Breaching | Drenaje | Rios (SDF) | Red vial | Caminos en malla | AO (ray tracing) | Malla | Vegetacion | Chunks |")
	md.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		md.append("| %d | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f (%d plantas) | %.2f (%d) |" % [r["samples"], r["t0_s"], r["retarget_s"], r["breach_s"], r["drainage_s"],
			r["rivers_s"], r["roads_s"], r["road_raster_s"], r["ao_s"], r["mesh_s"], r["vegetation_s"], r["vegetation_count"], r["chunks_s"], r["chunks"]])
	md.append("")
	md.append("## Receta completa del paper (estimada)")
	md.append("")
	md.append("Base 129 y la receta de `PredefinedErosion()` por nivel: 3000/600/2000, 1500/1000/700, 700/2000/200, 400/6000/150.")
	md.append("")
	md.append("| Mapa final | Niveles | Tiempo estimado | Detalle por nivel |")
	md.append("|---|---|---|---|")
	for e in estimates:
		md.append("| %d x %d | %d | %.0f s (%.1f min) | %s |" % [e["samples"], e["samples"], e["levels"], e["seconds"], e["seconds"] / 60.0, e["detail"]])
	if not measured.is_empty():
		md.append("")
		md.append("Comprobacion: la receta completa real a %d tardo %.1f s." % [measured["samples"], measured["seconds"]])
	var f := FileAccess.open(dir.path_join("tabla_tiempos.md"), FileAccess.WRITE)
	f.store_string("\n".join(md) + "\n")
	var csv := FileAccess.open(dir.path_join("tabla_tiempos.csv"), FileAccess.WRITE)
	var keys := ["samples", "cell_m", "fluvial_ms", "thermal_ms", "thermal_noise_ms", "deposition_ms", "t0_s", "retarget_s", "breach_s", "drainage_s", "rivers_s", "roads_s",
		"road_raster_s", "ao_s", "mesh_s", "vegetation_s", "vegetation_count", "chunks_s", "chunks"]
	csv.store_line(",".join(keys))
	for r in rows:
		var vals := PackedStringArray()
		for k in keys:
			vals.append(str(r[k]))
		csv.store_line(",".join(vals))
	var js := FileAccess.open(dir.path_join("tabla_tiempos.json"), FileAccess.WRITE)
	js.store_string(JSON.stringify({"rows": rows, "estimates": estimates, "measured_full": measured}, "\t"))
	print("\n".join(md))
