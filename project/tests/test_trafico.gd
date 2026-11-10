extends SceneTree
## Prueba sin ventana del tráfico (RoadTraffic, pendiente 13 fase C): aparecen adelante, van por
## su carril derecho sobre la vía, siguen por otra vía en los empalmes, frenan detrás de la
## mototaxi sin chocarla, esquivan los obstáculos fijos, chocarlos resta vida y ánimo (con
## gracia), se quitan al alejarse y con densidad 0 no hay ninguno.
##   Godot_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_trafico.gd -- [semilla]
## Sin argumentos usa el terreno guardado (terrain_demo.tscn).

var _fails := 0
var world: TerrainWorld
var moto: Mototaxi
var race: RaceManager
var traffic: RoadTraffic


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Distancia lateral (con signo, + = derecha del sentido de marcha) del vehículo a su vía.
func _lateral(v: Dictionary) -> float:
	var s := traffic._sample(v, 0.0)
	var f: Vector3 = v["fwd"]
	var rel: Vector3 = v["pos"] - s["p"]
	rel.y = 0.0
	return rel.dot(Vector3(-f.z, 0.0, f.x))


func _run() -> void:
	world = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	var args := OS.get_cmdline_user_args()
	world.use_editor_scene = args.is_empty()
	if args.size() > 0:
		world.world_seed = int(args[0])
	world.obstacle_level = 2
	root.add_child(world)
	world.generate()

	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	race = RaceManager.new()
	race.world = world
	race.moto = moto
	root.add_child(race)
	traffic = RoadTraffic.new()
	root.add_child(traffic)
	traffic.setup(world, moto, race, 1.7, 0.5, world.world_seed)
	await _frames(2)
	race.start(1)
	print("  %d lugares, %d paraderos, %d obstáculos fijos" % [traffic._sites.size(), traffic._paraderos.size(), world.obstacles.obstacles.size()])
	_check(traffic._sites.size() > 30, "hay lugares sobre las vías")

	print("-- Recorrido (la mototaxi salta por las vías más largas)")
	var roads := world.get_roads()
	roads.sort_custom(func(a, b): return TerrainWorld.route_length(a["path"]) > TerrainWorld.route_length(b["path"]))
	var seen := {}
	var counted := {}
	var toward := 0
	var max_n := 0
	var off_road := 0
	var wrong_side := 0
	var floating := 0
	var transfers := 0
	var last_r := {}
	var t0 := Time.get_ticks_usec()
	var frames := 0
	for road in roads.slice(0, 6):
		var path: PackedVector3Array = road["path"]
		var acc := 0.0
		for i in range(1, path.size()):
			acc += path[i - 1].distance_to(path[i])
			if acc < 15.0:
				continue
			acc = 0.0
			var d := path[mini(i + 1, path.size() - 1)] - path[i - 1]
			moto.place_at(path[i], atan2(d.x, d.z))
			await _frames(20)
			frames += 20
			max_n = maxi(max_n, traffic.get_vehicle_count())
			for v in traffic.vehicles:
				var id: int = v["id"]
				if not counted.has(id):
					counted[id] = true
					seen[v["kind"]] = seen.get(v["kind"], 0) + 1
					if v["toward"]:
						toward += 1
				if last_r.has(id) and last_r[id] != v["r"]:
					transfers += 1
				last_r[id] = v["r"]
				var half_road: float = traffic._roads[v["r"]]["width"] * 0.5
				var lat := _lateral(v)
				if absf(lat) > half_road + 0.5:
					off_road += 1
				if v["speed"] > 2.0 and lat < -0.2 and absf(float(v["lat"]) - float(v["lane"])) < 0.05:
					wrong_side += 1
				var p: Vector3 = v["pos"]
				if absf(p.y - world.get_height(p.x, p.z)) > 0.6:
					floating += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1)
	print("  tipos vistos: %s · %d de frente · máx. %d a la vez (tope %d) · %d cambios de vía" % [seen, toward, max_n, traffic.max_vehicles(), transfers])
	_check(counted.size() >= 4, "aparecen vehículos al recorrer (%d)" % counted.size())
	_check(toward > 0 and toward < counted.size(), "hay de frente y en el mismo sentido (%d de %d)" % [toward, counted.size()])
	_check(max_n <= traffic.max_vehicles(), "no pasan del tope (%d)" % max_n)
	_check(off_road == 0, "siempre sobre la vía (%d fuera)" % off_road)
	_check(wrong_side == 0, "van por su carril derecho (%d en el izquierdo)" % wrong_side)
	_check(floating == 0, "pegados al suelo (%d flotando o enterrados)" % floating)
	print("  %.2f ms por paso de física con el tráfico (incluye la física de la mototaxi)" % ms)

	# Mototaxi lejos de todo para las pruebas de un solo vehículo.
	var road0: PackedVector3Array = roads[0]["path"]
	var r0 := -1
	for k in traffic._paths.size():
		if traffic._paths[k] == road0:
			r0 = k
	var mid := road0.size() / 2

	print("-- Avanza y sigue por otras vías")
	traffic.clear_all()
	traffic.density = 0.0001  # Que no aparezcan otros (el tope queda en 1 y el que ponemos lo ocupa).
	var site := {"p": road0[mid], "dir": (road0[mid + 1] - road0[mid - 1]).normalized(), "r": r0, "i": mid, "kind": 1, "region": 0}
	moto.place_at(road0[mid] + Vector3(0, 0, 0), 0.0)
	await _frames(3)
	traffic.density = 1.0
	var v := traffic.spawn(site, "combi", 1)
	traffic._spawn_timer = 1e9
	# La mototaxi se aparta del camino para no frenarlo.
	moto.place_at(road0[mid] + Vector3(60, 0, 60), 0.0)
	var start: Vector3 = v["pos"]
	var start_r: int = v["r"]
	var travelled := 0.0
	var prev := start
	for f in 600:
		await physics_frame
		if v not in traffic.vehicles:
			break
		travelled += traffic._flat_dist(prev, v["pos"])
		prev = v["pos"]
		# Que no lo quite por estar lejos.
		if moto.global_position.distance_to(v["pos"]) > 150.0:
			moto.place_at(v["pos"] + Vector3(60, 0, 0), 0.0)
	print("  la combi recorrió %.0f m en 10 s (crucero %.0f km/h), vía %d -> %d" % [travelled, v["cruise"] * 3.6, start_r, v["r"]])
	_check(travelled > 30.0, "avanza por la vía (%.0f m)" % travelled)

	print("-- Frena detrás de la mototaxi")
	traffic.clear_all()
	traffic._spawn_timer = 1e9
	var ia := mid - 1
	var dist_back := 0.0
	while ia > 1 and dist_back < 45.0:
		dist_back += road0[ia].distance_to(road0[ia - 1])
		ia -= 1
	site = {"p": road0[ia], "dir": (road0[ia + 1] - road0[ia - 1]).normalized(), "r": r0, "i": ia, "kind": 1, "region": 0}
	v = traffic.spawn(site, "camioneta", 1)
	# La mototaxi parada en el carril del vehículo, 45 m adelante.
	var ahead := traffic._sample(v, dist_back)
	var right := Vector3(-ahead["dir"].z, 0.0, ahead["dir"].x)
	var mp: Vector3 = ahead["p"] + right * float(v["lane"])
	moto.place_at(mp, atan2(ahead["dir"].x, ahead["dir"].z))
	moto.repair()
	var hp := moto.health
	var hits0 := traffic.hits
	await _frames(600)
	var gap := traffic._flat_dist(v["pos"], moto.global_position) - float(v["half_l"]) - 1.3
	print("  se detuvo a %.1f m de la mototaxi (velocidad %.1f km/h)" % [gap, float(v["speed"]) * 3.6])
	_check(float(v["speed"]) < 0.5 and gap > 0.5 and gap < 8.0, "se detiene detrás, sin chocar")
	_check(traffic.hits == hits0 and is_equal_approx(moto.health, hp), "no le hace daño")

	print("-- Golpe")
	var said: Array = []
	race.passenger_said.connect(func(t): said.append(t))
	race.state = RaceManager.State.CON_PASAJERO
	var comfort: float = race._comfort
	traffic._grace = 0.0
	v["body"].global_position = moto.global_position
	moto.linear_velocity = moto.global_basis.z * (35.0 / 3.6)
	traffic._check_hit(v)
	_check(moto.health < hp, "chocar una camioneta a 35 km/h quita %.1f de vida" % (hp - moto.health))
	_check(race._comfort < comfort and not said.is_empty(), "el pasajero se enoja: \"%s\"" % (said[0] if said else ""))
	var hp2 := moto.health
	traffic._check_hit(v)
	_check(is_equal_approx(moto.health, hp2), "tiempo de gracia entre golpes")
	race.state = RaceManager.State.LIBRE
	moto.linear_velocity = Vector3.ZERO

	print("-- Esquiva los obstáculos fijos")
	var tested := 0
	var crashed := 0
	var passed := 0
	for o in world.obstacles.obstacles:
		if o["solids"].is_empty() or tested >= 5:
			continue
		# Vía y vértice del obstáculo.
		var best_r := -1
		var best_i := -1
		var best_d := 3.0
		for k in traffic._paths.size():
			var path: PackedVector3Array = traffic._paths[k]
			for i in range(2, path.size() - 2):
				var dd := traffic._flat_dist(path[i], o["position"])
				if dd < best_d and absf(float(traffic._roads[k]["width"]) - float(o["width"])) < 0.5:
					best_d = dd
					best_r = k
					best_i = i
		if best_r < 0:
			continue
		var path: PackedVector3Array = traffic._paths[best_r]
		var j := best_i
		var back := 0.0
		while j > 1 and back < 35.0:
			back += path[j].distance_to(path[j - 1])
			j -= 1
		if back < 25.0:
			continue
		tested += 1
		traffic.clear_all()
		traffic._spawn_timer = 1e9
		site = {"p": path[j], "dir": (path[j + 1] - path[j - 1]).normalized(), "r": best_r, "i": j, "kind": traffic._roads[best_r]["kind"], "region": 0}
		v = traffic.spawn(site, "mototaxi", 1)
		moto.place_at(path[j] + Vector3(70, 0, 70), 0.0)
		var min_clear := INF
		for f in 900:
			await physics_frame
			if v not in traffic.vehicles:
				break
			# La mototaxi lo acompaña de lejos, a un costado (que no lo quite ni lo frene).
			if f % 30 == 0:
				var side: Vector3 = Vector3(-v["fwd"].z, 0.0, v["fwd"].x) * 45.0
				moto.place_at(v["pos"] + side, 0.0)
			for s: Array in o["solids"]:
				var c := traffic._flat_dist(v["pos"], Vector3(s[0], 0, s[1])) - float(s[2]) - float(v["half_w"])
				min_clear = minf(min_clear, c)
			if OS.get_environment("DEBUG_TRAFICO") != "" and f % 15 == 0:
				var blk := traffic._avoid_solids(v)
				print("      f%d d=%.1f lat=%.2f lane=%.2f goal=%s spd=%.1f solids=%s" % [f, traffic._flat_dist(v["pos"], o["position"]), v["lat"], v["lane"], blk, v["speed"], o["solids"]])
			if traffic._flat_dist(v["pos"], o["position"]) > 20.0 and (v["pos"] - o["position"]).dot(v["fwd"]) > 0.0:
				passed += 1
				break
		if min_clear < -0.3:
			crashed += 1
		print("    %s en vía de %.1f m: margen mínimo %.2f m" % [RoadObstacles.Kind.keys()[o["kind"]], traffic._roads[best_r]["width"], min_clear])
	_check(tested > 0, "hay obstáculos para probar (%d)" % tested)
	_check(crashed == 0, "no los atraviesa (%d)" % crashed)
	_check(passed >= tested - 1, "los pasa por el lado libre (%d de %d)" % [passed, tested])

	print("-- Se quitan lejos y sin tráfico no hay ninguno")
	traffic.setup(world, moto, race, 1.0, 0.35, world.world_seed)
	moto.place_at(road0[mid], 0.0)
	await _frames(400)
	var n_before := traffic.get_vehicle_count()
	moto.place_at(road0[0] if road0[mid].distance_to(road0[0]) > 400.0 else road0[-1], 0.0)
	await _frames(3)
	_check(n_before == 0 or traffic.vehicles.all(func(x): return traffic._flat_dist(x["pos"], moto.global_position) <= RoadTraffic.DESPAWN), "los lejanos se quitan (%d antes)" % n_before)
	traffic.setup(world, moto, race, 0.0, 0.35, world.world_seed)
	await _frames(300)
	_check(traffic.get_vehicle_count() == 0, "densidad 0: ninguno")

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
