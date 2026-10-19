extends SceneTree
## Diagnóstico: pendientes del terreno de CG en todo el mapa y sobre las vías.
##   Godot_console.exe --headless --path project -s res://tests/diag_terrain.gd -- [preset]
## preset: game (por defecto, erosión al 10%) | demo (valores de terrain_demo.tscn) | noerosion | full (erosión completa) | nograde

func _pct(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	return arr[clampi(int((arr.size() - 1) * p), 0, arr.size() - 1)]

func _initialize() -> void:
	var preset := "game"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		preset = args[0]
	var w: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	w.generate_on_ready = false
	if preset == "demo":
		w.erosion_scale = 1.0
	w.build_collision = false
	match preset:
		"demo":
			w.grid_size = 512
			w.cell_size = 6.0  # mismo tamaño de mapa que la escena (3072 m) a media resolución
			w.world_seed = 2
			w.erosion_levels = 2
			w.generator_overrides = {"num_points": 20, "min_point_dist": 15.0, "k_neighbors": 5,
				"river_catchment": 84000.0, "breach_radius": 59.0, "region_patches": 8,
				"transition_width": 0.18, "border_warp": 0.2,
				"coast_base": 5.0, "coast_amplitude": 25.0, "coast_frequency": 0.002,
				"mountain_base": 250.0, "mountain_amplitude": 700.0, "mountain_frequency": 0.001,
				"jungle_base": 40.0, "jungle_amplitude": 60.0, "jungle_frequency": 0.002,
				"mountain_hardness": 0.5}
		"noerosion":
			w.erosion_enabled = false
		"full":
			w.erosion_scale = 1.0
		"nograde":
			w.road_max_grade = 0.0
	root.add_child(w)
	var t0 := Time.get_ticks_msec()
	w.generate(w.world_seed)
	print("preset=%s  mapa %.0f m  generado en %.1f s" % [preset, w.get_world_size(), (Time.get_ticks_msec() - t0) / 1000.0])

	var hmin := INF
	var hmax := -INF
	var slopes := []
	var step := w.get_world_size() / 128.0
	var half := w.get_world_size() * 0.5
	for iz in 129:
		for ix in 129:
			var x := -half + ix * step
			var z := -half + iz * step
			var h := w.get_height(x, z)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			slopes.append(w.get_slope(x, z))
	slopes.sort()
	print("alturas %.0f .. %.0f m" % [hmin, hmax])
	print("pendiente mapa  p50 %.2f  p75 %.2f  p90 %.2f  p99 %.2f   (>0.35: %.0f%%)" % [
		_pct(slopes, 0.5), _pct(slopes, 0.75), _pct(slopes, 0.9), _pct(slopes, 0.99),
		100.0 * slopes.filter(func(s): return s > 0.35).size() / slopes.size()])

	# Pendiente a lo largo de las vías (cada 3 m).
	var roads := w.get_roads()
	var grades := []
	var kinds := {}
	for r in roads:
		var path: PackedVector3Array = r["path"]
		kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
		for i in range(1, path.size()):
			var a := path[i - 1]
			var b := path[i]
			var d := Vector2(b.x - a.x, b.z - a.z).length()
			var nseg := maxi(1, int(d / 3.0))
			for k in nseg:
				var p := a.lerp(b, float(k) / nseg)
				var q := a.lerp(b, float(k + 1) / nseg)
				var hd := Vector2(q.x - p.x, q.z - p.z).length()
				if hd > 0.01:
					grades.append(absf(w.get_height(q.x, q.z) - w.get_height(p.x, p.z)) / hd)
	grades.sort()
	print("vías: %d (por tipo %s)" % [roads.size(), kinds])
	print("pendiente vías  p50 %.2f  p90 %.2f  p99 %.2f  max %.2f   (>0.25: %.1f%%  >0.35: %.1f%%  >0.55: %.1f%%)" % [
		_pct(grades, 0.5), _pct(grades, 0.9), _pct(grades, 0.99), _pct(grades, 1.0),
		100.0 * grades.filter(func(s): return s > 0.25).size() / maxf(grades.size(), 1),
		100.0 * grades.filter(func(s): return s > 0.35).size() / maxf(grades.size(), 1),
		100.0 * grades.filter(func(s): return s > 0.55).size() / maxf(grades.size(), 1)])

	var lms := w.get_landmarks()
	# Pendiente de las rutas recomendadas (A*) entre landmarks consecutivos.
	var rg := []
	for i in range(0, mini(lms.size() - 1, 25)):
		var r := w.find_route(lms[i]["position"], lms[i + 1]["position"])
		for k in range(1, r.size()):
			var dd := Vector2(r[k].x - r[k - 1].x, r[k].z - r[k - 1].z).length()
			if dd > 0.01:
				rg.append(absf(r[k].y - r[k - 1].y) / dd)
	rg.sort()
	print("pendiente rutas A*  p50 %.2f  p90 %.2f  p99 %.2f  max %.2f   (>0.35: %.1f%%)" % [
		_pct(rg, 0.5), _pct(rg, 0.9), _pct(rg, 0.99), _pct(rg, 1.0),
		100.0 * rg.filter(func(s): return s > 0.35).size() / maxf(rg.size(), 1)])
	var comp := {}
	for lm in lms:
		comp[lm["reach"]] = comp.get(lm["reach"], 0) + 1
	var best := 0
	for k in comp:
		if k >= 0:
			best = maxi(best, comp[k])
	print("landmarks: %d  en la mayor zona transitable (pendiente <= %.2f): %d  zonas: %s" % [lms.size(), w.max_drive_slope, best, comp])
	quit()
