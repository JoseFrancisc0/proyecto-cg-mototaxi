extends SceneTree
## Prueba de punta a punta: un piloto automático sigue la ruta recomendada entre pares
## de landmarks (como los elige RaceManager) con la física real de la mototaxi y
## comprueba que llega dentro del tiempo límite del juego.
##   Godot_console.exe --headless --path project -s res://tests/test_drive_routes.gd -- [rides] [seed] [obstaculos]
## Con "obstaculos" el mapa trae los obstáculos de las vías (nivel normal) y el piloto los esquiva
## como un jugador: pasa por el carril libre, más despacio.

const LOOKAHEAD := 7.0
const CRUISE_KMH := 38.0

var moto: Mototaxi
var world: TerrainWorld
var dodge := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rides := int(args[0]) if args.size() > 0 else 6
	# Semilla "editor" = el terreno guardado en terrain_demo.tscn (como main.tscn).
	var use_editor := args.size() > 1 and args[1] == "editor"
	var world_seed := int(args[1]) if args.size() > 1 and not use_editor else 67

	world = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	world.use_editor_scene = use_editor
	dodge = args.size() > 2 and args[2] == "obstaculos"
	world.obstacle_level = 2 if dodge else 0
	root.add_child(world)
	await process_frame
	world.generate(-1 if use_editor else world_seed)

	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	var race := RaceManager.new()  # Solo para usar su fórmula de tiempo límite.
	root.add_child(race)
	await physics_frame

	var lms := world.get_landmarks()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var ok := 0
	var done := 0
	var attempts := 0
	var damage_total := 0.0
	while done < rides and attempts < 200:
		attempts += 1
		var a: Vector3 = lms[rng.randi_range(0, lms.size() - 1)]["position"]
		var b: Vector3 = lms[rng.randi_range(0, lms.size() - 1)]["position"]
		var d := Vector2(b.x - a.x, b.z - a.z).length()
		if d < race.ride_min_dist or d > race.ride_max_dist or not world.is_reachable(a, b):
			continue
		var route := world.find_road_route(a, b)  # La ruta que el juego dibuja.
		if route.size() < 2:
			continue
		done += 1
		var limit := race.compute_route_time(route)
		moto.repair()
		var res: Dictionary = await _drive(route, b, limit)
		damage_total += moto.max_health - moto.health
		if res["ok"]:
			ok += 1
		print("  %s viaje %d: %.0f m de ruta, %.0f s de %.0f s límite, %d reinicios, daño %.0f, pendiente máx. en ruta %.2f%s" % [
			"OK  " if res["ok"] else "FAIL", done, TerrainWorld.route_length(route), res["time"], limit,
			res["resets"], moto.max_health - moto.health, _max_grade(route), "" if res["ok"] else "  (" + res["why"] + ")"])
	print("Daño total del piloto automático: %.0f en %d viajes" % [damage_total, done])
	print("RESULTADO: %d/%d viajes completados a tiempo" % [ok, done])
	quit(0 if ok == done and done > 0 else 1)


func _drive(route: PackedVector3Array, goal: Vector3, limit: float) -> Dictionary:
	var dir := route[mini(4, route.size() - 1)] - route[0]
	moto.place_at(route[0], atan2(dir.x, dir.z))
	var resets := [0]
	var on_reset := func(): resets[0] += 1
	moto.was_reset.connect(on_reset)
	var t := 0.0
	var idx := 0
	var last_pos := moto.global_position
	var stall := 0.0
	var reverse_time := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var result := {"ok": false, "time": 0.0, "resets": 0, "why": "tiempo"}
	while t < limit * 1.5:
		var p := moto.global_position
		if Vector2(goal.x - p.x, goal.z - p.z).length() < 4.0:
			result["ok"] = t <= limit
			if not result["ok"]:
				result["why"] = "llegó tarde"
			break
		# Avanza el índice al punto de la ruta más cercano por delante y mira LOOKAHEAD más allá.
		while idx < route.size() - 1 and Vector2(route[idx].x - p.x, route[idx].z - p.z).length() < LOOKAHEAD:
			idx += 1
		var to := route[idx] - p
		var fwd := moto.global_basis.z
		to.y = 0.0
		fwd.y = 0.0
		var dodging := false
		if dodge:
			var avoid := _avoid(p, route, idx)
			if avoid != Vector3.INF:
				to = avoid - p
				to.y = 0.0
				dodging = true
		var ang := atan2(fwd.cross(to).y, fwd.dot(to))
		# Curva muy cerrada y casi detenida: maniobra de tres puntos (retrocede con el
		# volante al revés), como haría un jugador.
		if reverse_time <= 0.0 and absf(ang) > 1.7 and moto.get_speed_kmh() < 8.0:
			reverse_time = 1.8
		if reverse_time > 0.0:
			reverse_time -= dt
			moto.steer_input = -signf(ang)
			moto.throttle = -1.0 if moto.get_forward_speed() > -2.5 else 0.0
		else:
			moto.steer_input = clampf(ang * 2.5, -1.0, 1.0)
			var target_kmh := CRUISE_KMH * (0.5 if absf(ang) > 0.6 else 1.0) * (0.7 if dodging else 1.0)
			moto.throttle = clampf((target_kmh - moto.get_speed_kmh()) * 0.25, -1.0, 1.0)
		# El piloto usa el mismo turbo de subida que tiene disponible el jugador.
		moto.turbo_requested = moto.throttle > 0.1 and moto.global_basis.z.y > 0.08 and moto.get_speed_kmh() < 35.0
		await physics_frame
		t += dt
		# Atascada: casi no se mueve en 6 s.
		stall += dt
		if stall > 6.0:
			if moto.global_position.distance_to(last_pos) < 2.0:
				var contacts := 0
				for w in moto.get_children():
					if w is VehicleWheel3D and w.is_in_contact():
						contacts += 1
				result["why"] = "atascada en (%.0f, %.0f): ruedas %d/3, inclinación %.0f°, ángulo al objetivo %.0f°, pendiente suelo %.2f, idx %d/%d" % [
					p.x, p.z, contacts, rad_to_deg(acos(clampf(moto.global_basis.y.y, -1, 1))), rad_to_deg(ang),
					world.get_slope(p.x, p.z), idx, route.size()]
				break
			last_pos = moto.global_position
			stall = 0.0
	moto.was_reset.disconnect(on_reset)
	moto.throttle = 0.0
	moto.turbo_requested = false
	moto.steer_input = 0.0
	result["time"] = t
	result["resets"] = resets[0]
	return result


## Punto al que apuntar para pasar al lado de un obstáculo sólido de adelante, o INF si no hay.
func _avoid(p: Vector3, route: PackedVector3Array, idx: int) -> Vector3:
	var j := mini(idx + 3, route.size() - 1)
	var rd := route[j] - p
	rd.y = 0.0
	if rd.length() < 0.5:
		return Vector3.INF
	rd = rd.normalized()
	var right := Vector3(-rd.z, 0.0, rd.x)
	var shift := 0.0
	var ahead := INF
	for s: Array in world.obstacles.solids_near(p, 24.0):
		var rel := Vector3(s[0] - p.x, 0.0, s[1] - p.z)
		var a := rel.dot(rd)
		var lat := rel.dot(right)
		var clear: float = s[2] + 1.2
		if a < -1.0 or a > 24.0 or absf(lat - shift) >= clear:
			continue
		# Se pasa por el lado contrario al obstáculo.
		shift = lat - signf(lat if absf(lat) > 0.05 else 1.0) * clear
		ahead = minf(ahead, maxf(a, 5.0))
	if ahead == INF:
		return Vector3.INF
	return p + rd * ahead + right * shift


func _max_grade(route: PackedVector3Array) -> float:
	var g := 0.0
	for i in range(1, route.size()):
		var d := Vector2(route[i].x - route[i - 1].x, route[i].z - route[i - 1].z).length()
		if d > 0.5:
			g = maxf(g, absf(route[i].y - route[i - 1].y) / d)
	return g
