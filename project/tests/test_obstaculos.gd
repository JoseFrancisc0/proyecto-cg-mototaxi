extends SceneTree
## Prueba sin ventana de los obstáculos de las vías (RoadObstacles, pendiente 6):
## tipos según la región, lejos de paradas, cruces y ríos, siempre con un carril libre,
## iguales con la misma semilla, y su efecto en la mototaxi (barro frena, bache y roca dañan).
##   Godot_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_obstaculos.gd -- [semilla] [costa|sierra|selva]
## Sin argumentos usa el terreno guardado (terrain_demo.tscn, casi todo selva).

var _fails := 0
var world: TerrainWorld


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	world = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	var args := OS.get_cmdline_user_args()
	world.use_editor_scene = args.is_empty()
	if args.size() > 0:
		world.world_seed = int(args[0])
	if args.size() > 1:
		var bias := Vector3(0.1, 0.1, 0.1)
		bias[StopNames.REGIONS.find(args[1])] = 0.8
		world.generator_overrides["biome_bias"] = bias
	world.obstacle_level = 2
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	world.generate()
	var obs := world.obstacles
	var list := obs.obstacles

	print("-- Reparto")
	var by_region := [{}, {}, {}]
	for o in list:
		var name: String = RoadObstacles.KIND_NAMES[o["kind"]]
		by_region[o["region"]][name] = by_region[o["region"]].get(name, 0) + 1
	print("  %d obstáculos: %s · descartados: %s" % [list.size(), obs.counts, obs.rejected])
	var length := [0.0, 0.0, 0.0, 0.0]
	for road in world.get_roads():
		length[road["kind"]] += TerrainWorld.route_length(road["path"])
	print("  vías (km): trocha %.1f, carretera %.1f, avenida %.1f, calle %.1f" % [length[0] / 1000, length[1] / 1000, length[2] / 1000, length[3] / 1000])
	var reg := [0, 0, 0]
	for lm in world.get_landmarks():
		reg[lm["region"]] += 1
	print("  paradas por región (costa, sierra, selva): %s" % [reg])
	for r in 3:
		print("    %s: %s" % [StopNames.REGIONS[r], by_region[r]])
	var km: float = (length[0] + length[1] + length[2] + length[3]) / 1000.0
	_check(list.size() >= 2.5 * km, "hay bastantes obstáculos (%d en %.1f km, %.1f por km)" % [list.size(), km, list.size() / km])
	_check(obs.counts.size() >= 4, "hay al menos 4 tipos (%d)" % obs.counts.size())
	_check(not by_region[0].has("tronco") and not by_region[0].has("charco"), "en la costa no hay troncos ni charcos")
	_check(not by_region[1].has("arena") and not by_region[2].has("arena"), "la arena solo está en la costa")

	print("-- Lugares")
	var near_stop := 0
	for o in list:
		for lm in world.get_landmarks():
			var d := Vector2(lm["position"].x - o["position"].x, lm["position"].z - o["position"].z).length()
			if d < RoadObstacles.STOP_CLEARANCE - 0.01:
				near_stop += 1
				break
	_check(near_stop == 0, "ninguno a menos de %.0f m de una parada (%d)" % [RoadObstacles.STOP_CLEARANCE, near_stop])
	var wet := list.filter(func(o): return world.get_drainage(o["position"].x, o["position"].z) >= 60000.0 * 0.3)
	_check(wet.is_empty(), "ninguno sobre un puente o cauce (%d)" % wet.size())
	_check(list.all(func(o): return world.get_reach_id(o["position"].x, o["position"].z) >= 0), "todos en zona transitable")

	print("-- Carril libre junto a los sólidos")
	var worst := INF
	var solids := list.filter(func(o): return not o["solids"].is_empty())
	for o in solids:
		worst = minf(worst, _free_lane(o))
	print("  %d sólidos; carril libre más angosto: %.2f m" % [solids.size(), worst])
	_check(solids.size() >= 0.5 * km, "hay obstáculos sólidos (%d)" % solids.size())
	_check(worst >= 2.4, "siempre queda un carril de ≥ 2.4 m para pasar (%.2f)" % worst)

	print("-- Misma semilla, mismos obstáculos")
	var before := list.map(func(o): return [o["kind"], o["position"]])
	world._build_obstacles()
	var after := world.obstacles.obstacles.map(func(o): return [o["kind"], o["position"]])
	_check(before == after, "se repiten al reconstruir (%d = %d)" % [before.size(), after.size()])
	print("  construir los obstáculos: %d ms (mapa entero %.1f s)" % [_time_build(), (Time.get_ticks_msec() - t0) / 1000.0])

	print("-- Efecto en la mototaxi")
	var moto: Mototaxi = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	await physics_frame
	var kinds := func(k: int) -> Array: return world.obstacles.obstacles.filter(func(o): return o["kind"] == k)
	var puddles: Array = kinds.call(RoadObstacles.Kind.CHARCO) + kinds.call(RoadObstacles.Kind.ARENA)
	if puddles.size() > 0:
		var o: Dictionary = puddles[0]
		var h: Array = o["hazards"][0]
		var target := Vector3(h[0], 0.0, h[1])
		var in_mud: float = await _coast(moto, target, o["dir"], 9.0)
		var saved := world.obstacles
		world.obstacles = null  # Mismo tramo sin barro.
		var clean: float = await _coast(moto, target, o["dir"], 9.0)
		world.obstacles = saved
		print("  velocidad 0.8 s después de entrar: con %s %.1f km/h, sin él %.1f km/h" % [RoadObstacles.KIND_NAMES[o["kind"]], in_mud, clean])
		_check(in_mud < clean - 4.0, "el barro o la arena frenan")
	var holes: Array = kinds.call(RoadObstacles.Kind.BACHE)
	if holes.size() > 0:
		var o: Dictionary = holes[0]
		var h: Array = o["hazards"][0]
		var reasons := []
		var on_damage := func(a: float, r: String): reasons.append("%s %.1f" % [r, a])
		moto.damaged.connect(on_damage)
		await _coast(moto, Vector3(h[0], 0.0, h[1]), o["dir"], 13.0)
		moto.damaged.disconnect(on_damage)
		_check(reasons.any(func(x): return x.begins_with("bache")), "un bache a 47 km/h hace daño (%s)" % [reasons])
	var rocks: Array = kinds.call(RoadObstacles.Kind.ROCAS) + kinds.call(RoadObstacles.Kind.TRONCO)
	if rocks.size() > 0:
		# La piedra o el tronco más grande del mapa.
		var o: Dictionary = rocks[0]
		var s: Array = o["solids"][0]
		for r in rocks:
			for part: Array in r["solids"]:
				if part[2] > s[2]:
					o = r
					s = part
		moto.repair()
		var speed_after: float = await _coast(moto, Vector3(s[0], 0.0, s[1]), o["dir"], 11.0)
		print("  %s de radio %.2f m: velocidad después %.1f km/h" % [RoadObstacles.KIND_NAMES[o["kind"]], s[2], speed_after])
		_check(moto.health < moto.max_health, "chocar %s a 40 km/h hace daño (vida %.0f)" % [RoadObstacles.KIND_NAMES[o["kind"]], moto.health])

	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(0 if _fails == 0 else 1)


## Ancho libre contiguo más grande de la vía en la sección del obstáculo.
func _free_lane(o: Dictionary) -> float:
	var dir: Vector3 = o["dir"]
	var right := Vector3(-dir.z, 0.0, dir.x)
	var half: float = o["width"] * 0.5
	var best := INF
	for along in [-1.5, -0.75, 0.0, 0.75, 1.5]:
		var run := 0.0
		var widest := 0.0
		var lat := -half
		while lat <= half:
			var q: Vector3 = o["position"] + right * lat + dir * along
			var free := true
			for s: Array in o["solids"]:
				if Vector2(q.x - s[0], q.z - s[1]).length() < s[2]:
					free = false
					break
			run = run + 0.05 if free else 0.0
			widest = maxf(widest, run)
			lat += 0.05
		best = minf(best, widest)
	return best


func _time_build() -> int:
	var t := Time.get_ticks_msec()
	world._build_obstacles()
	return Time.get_ticks_msec() - t


## Pone la mototaxi 12 m antes de target, mirando hacia él, la lanza a speed m/s sin acelerar
## y devuelve la velocidad (km/h) 0.8 s después de llegar a target.
func _coast(moto: Mototaxi, target: Vector3, dir: Vector3, speed: float) -> float:
	var start := target - dir * 12.0
	moto.place_at(Vector3(start.x, world.get_height(start.x, start.z), start.z), atan2(dir.x, dir.z))
	for k in 70:  # Se asienta y pasa la gracia de daño del inicio.
		await physics_frame
	moto.linear_velocity = moto.global_basis.z * speed
	moto._prev_velocity = moto.linear_velocity  # Lanzarla no cuenta como choque.
	moto.throttle = 0.25
	var t := 0.0
	var reached := -1.0
	while t < 4.0:
		await physics_frame
		t += 1.0 / 60.0
		var p := moto.global_position
		if reached < 0.0 and Vector2(p.x - target.x, p.z - target.z).length() < 1.5:
			reached = t
		if reached >= 0.0 and t - reached >= 0.8:
			break
	moto.throttle = 0.0
	return moto.get_speed_kmh()
