class_name RoadTraffic
extends Node3D
## Tráfico en las vías (pendiente 13 fase C): pocos vehículos, pero cada uno es un obstáculo
## que se mueve. En el campo pasan pocos vehículos; no se simula un flujo, sino "encuentros"
## cerca de la mototaxi (como los animales).
##
## Dos papeles:
##   - EN TU SENTIDO, más lento que tú: hace perder tiempo; hay que ir detrás o adelantar.
##   - DE FRENTE: hace peligroso adelantar (sin ellos adelantar no costaría nada).
## Cantidad según el tipo de vía (más en calles del pueblo y avenidas, poco en carreteras, casi
## nada en trochas) y según la dificultad (Difficulty "traffic" y "oncoming").
##
## Tipos: otras mototaxis (modelos del garaje), combi (hecha aquí; para en los paraderos),
## camioneta y camión (Quaternius, CC0; ver res://assets/traffic/SOURCE.md). El camión sube
## despacio las cuestas y abunda en la sierra.
##
## Cada vehículo es un AnimatableBody3D que sigue el trazo de la vía por su carril derecho
## (cinemático: barato y no se vuelca). Frena si hay algo delante (la mototaxi, otro vehículo,
## animales), esquiva los obstáculos fijos por el lado libre y en los empalmes sigue por otra vía.
## Chocarlo resta vida y ánimo del pasajero (razón "vehiculo"), con gracia entre golpes.
## Nunca aparecen a menos de 40 m de la recogida o del destino.

const TYPES := {
	# length/width/height: medidas reales (m); kmh: velocidad de crucero [mín, máx];
	# damage: daño por km/h de diferencia; climb: cuánto lo frena una subida.
	"mototaxi": {"length": 2.7, "width": 1.4, "height": 1.8, "kmh": [20.0, 28.0], "damage": 0.45, "climb": 2.0},
	"combi": {"length": 4.8, "width": 1.9, "height": 2.15, "kmh": [24.0, 34.0], "damage": 0.8, "climb": 3.0},
	"camioneta": {"length": 5.2, "width": 2.0, "height": 1.8, "kmh": [28.0, 38.0], "damage": 0.7, "climb": 2.0, "model": "pickup"},
	"camion": {"length": 6.2, "width": 2.2, "height": 2.9, "kmh": [16.0, 24.0], "damage": 1.0, "climb": 5.0, "model": "truck"},
}
## Tipos por tipo de vía (0 trocha, 1 carretera, 2 avenida, 3 calle): [tipo, peso].
const KIND_TYPES := {
	0: [["mototaxi", 3.0], ["camioneta", 2.0], ["camion", 0.4]],
	1: [["mototaxi", 1.5], ["camioneta", 2.0], ["combi", 3.0], ["camion", 2.0]],
	2: [["mototaxi", 4.0], ["camioneta", 1.5], ["combi", 3.0], ["camion", 0.6]],
	3: [["mototaxi", 6.0], ["camioneta", 1.0], ["combi", 1.0]],
}
## Multiplicador del peso por región (costa, sierra, selva).
const REGION_BIAS := [{}, {"camion": 1.8, "combi": 0.8}, {"mototaxi": 1.4}]
## Cuánto tráfico hay en cada tipo de vía.
const ROAD_WEIGHT := {0: 0.35, 1: 0.8, 2: 1.6, 3: 1.4}

const SITE_STEP := 25.0
const CELL := 50.0
const SPAWN_MIN := 90.0
const SPAWN_MAX := 220.0
const DESPAWN := 270.0
const BEHIND_DESPAWN := 110.0
const STOP_CLEARANCE := 40.0
const VEHICLE_GAP := 50.0        ## Distancia mínima entre un vehículo nuevo y otro.
const BASE_VEHICLES := 3.0       ## Vehículos a la vez con densidad 1.
const LOOK_AHEAD := 32.0         ## Hasta dónde mira para frenar.
const HEADWAY := 1.1             ## Segundos de distancia con lo que tiene delante.
const ACCEL := 1.8
const BRAKE := 6.0
const HIT_GRACE := 1.2
const AVOID_AHEAD := 30.0        ## Hasta dónde mira los obstáculos fijos.
const LATERAL_SPEED := 2.0       ## m/s para cambiar de lado en la vía.
const PARADERO_STOP := [3.0, 6.0]

## Cantidad relativa (Difficulty "traffic"): 0 = ninguno.
var density := 1.0
## Probabilidad de que un vehículo nuevo venga de frente (Difficulty "oncoming").
var oncoming := 0.35
var world: TerrainWorld
var moto: Mototaxi
var race: RaceManager
## Para frenar ante los animales (opcional).
var animals: RoadAnimals
## Golpes dados en la partida (diagnóstico y pruebas).
var hits := 0
var vehicles: Array[Dictionary] = []

var _paths: Array[PackedVector3Array] = []
var _roads: Array[Dictionary] = []          # {kind, width}
var _sites: Array[Dictionary] = []          # {p, dir, r, i, kind, region}
var _cells := {}                            # Vector2i -> Array[int]
var _joints := {}                           # vértice cuantizado -> Array[[r, i]]
var _paraderos: Array[Vector3] = []
var _scenes := {}
var _pool := {}                             # tipo -> Array[AnimatableBody3D]
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0
var _serial := 0
var _grace := 0.0


func setup(w: TerrainWorld, m: Mototaxi, r: RaceManager, amount: float, oncoming_chance: float, world_seed: int) -> void:
	world = w
	moto = m
	race = r
	density = maxf(amount, 0.0)
	oncoming = clampf(oncoming_chance, 0.0, 1.0)
	_rng.seed = hash("trafico-%d" % world_seed)
	clear_all()
	_paths.clear()
	_roads.clear()
	_sites.clear()
	_cells.clear()
	_joints.clear()
	_paraderos.clear()
	if density <= 0.0 or world == null:
		return
	for road in world.get_roads():
		var path: PackedVector3Array = road["path"]
		if path.size() < 2:
			continue
		var ri := _paths.size()
		_paths.append(path)
		_roads.append({"kind": int(road["kind"]), "width": float(road["width"])})
		for i in path.size():
			var key := _key(path[i])
			if not _joints.has(key):
				_joints[key] = []
			_joints[key].append([ri, i])
		var acc := SITE_STEP * 0.5
		for i in range(1, path.size() - 1):
			acc += path[i - 1].distance_to(path[i])
			if acc < SITE_STEP:
				continue
			acc = 0.0
			var dir := path[i + 1] - path[i - 1]
			dir.y = 0.0
			if dir.length() < 0.01:
				continue
			_sites.append({"p": path[i], "dir": dir.normalized(), "r": ri, "i": i, "kind": int(road["kind"]),
				"region": world.get_biome(path[i].x, path[i].z).max_axis_index()})
			var c := Vector2i(floori(path[i].x / CELL), floori(path[i].z / CELL))
			if not _cells.has(c):
				_cells[c] = []
			_cells[c].append(_sites.size() - 1)
	for lm in world.get_landmarks():
		if lm.get("kind", "") == "paradero":
			_paraderos.append(lm["position"])


## Quita todos los vehículos (reinicio, día nuevo, reaparecer).
func clear_all() -> void:
	for v in vehicles:
		_release(v)
	vehicles.clear()
	_spawn_timer = 1.5
	_grace = 0.0


func get_vehicle_count() -> int:
	return vehicles.size()


func _physics_process(delta: float) -> void:
	if density <= 0.0 or moto == null or _sites.is_empty():
		return
	_grace = maxf(_grace - delta, 0.0)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = _rng.randf_range(2.5, 5.0) / density
		if vehicles.size() < max_vehicles():
			_try_spawn()
	var mp := moto.global_position
	var fwd := _moto_forward()
	for vi in range(vehicles.size() - 1, -1, -1):
		var v: Dictionary = vehicles[vi]
		var to: Vector3 = v["pos"] - mp
		to.y = 0.0
		var dist := to.length()
		var stuck: bool = v["stuck"] > 25.0 and dist > 60.0
		if dist > DESPAWN or (dist > BEHIND_DESPAWN and to.dot(fwd) < 0.0) or stuck:
			_release(v)
			vehicles.remove_at(vi)
			continue
		_drive(v, delta)
		_check_hit(v)


func max_vehicles() -> int:
	return maxi(1, roundi(BASE_VEHICLES * density))


# --- Aparecer -----------------------------------------------------------------

func _try_spawn() -> void:
	var mp := moto.global_position
	var fwd := _moto_forward()
	var target := race.get_target() if race else Vector3.INF
	var candidates: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	var c0 := Vector2i(floori(mp.x / CELL), floori(mp.z / CELL))
	var rc := ceili(SPAWN_MAX / CELL)
	for cx in range(c0.x - rc, c0.x + rc + 1):
		for cz in range(c0.y - rc, c0.y + rc + 1):
			for idx: int in _cells.get(Vector2i(cx, cz), []):
				var s: Dictionary = _sites[idx]
				var to: Vector3 = s["p"] - mp
				to.y = 0.0
				var d := to.length()
				if d < SPAWN_MIN or d > SPAWN_MAX or to.dot(fwd) < d * 0.3:
					continue
				if target != Vector3.INF and _flat_dist(s["p"], target) < STOP_CLEARANCE:
					continue
				if _near_vehicle(s["p"], VEHICLE_GAP):
					continue
				var w: float = ROAD_WEIGHT.get(s["kind"], 0.5)
				candidates.append(idx)
				weights.append(w)
				total += w
	if candidates.is_empty():
		return
	var pick := _rng.randf() * total
	for k in candidates.size():
		pick -= weights[k]
		if pick <= 0.0 or k == candidates.size() - 1:
			var site: Dictionary = _sites[candidates[k]]
			# De frente: viene hacia la mototaxi; si no, va en su mismo sentido.
			var toward := _rng.randf() < oncoming
			var along: float = site["dir"].dot(fwd)
			var ps := 1 if along >= 0.0 else -1
			if toward:
				ps = -ps
			spawn(site, _pick_type(int(site["kind"]), int(site["region"])), ps, toward)
			return


## Vehículo de tipo kind en site, avanzando hacia ps (+1 / -1 en el trazo).
func spawn(site: Dictionary, kind: String, ps: int, toward := false) -> Dictionary:
	var info: Dictionary = TYPES[kind]
	var body := _acquire(kind)
	if body == null:
		return {}
	var road: Dictionary = _roads[site["r"]]
	var half_w: float = body.get_meta("half_w")
	var lane := clampf(minf(road["width"] * 0.25, road["width"] * 0.5 - half_w - 0.15), 0.3, 3.0)
	var kmh: Array = info["kmh"]
	var dir: Vector3 = site["dir"] * float(ps)
	_serial += 1
	var v := {"id": _serial, "kind": kind, "body": body, "r": int(site["r"]), "i": int(site["i"]), "ps": ps, "t": 0.0,
		"speed": 0.0, "cruise": _rng.randf_range(kmh[0], kmh[1]) / 3.6, "lane": lane, "lat": lane,
		"half_w": half_w, "half_l": float(body.get_meta("half_l")), "wait": 0.0, "stuck": 0.0,
		"visited": {}, "toward": toward, "yaw": atan2(dir.x, dir.z), "pos": site["p"], "fwd": dir}
	v["speed"] = v["cruise"]
	_place(v, 1.0)
	vehicles.append(v)
	return v


func _pick_type(road_kind: int, region: int) -> String:
	var options: Array = KIND_TYPES.get(road_kind, KIND_TYPES[1])
	var bias: Dictionary = REGION_BIAS[clampi(region, 0, 2)]
	var total := 0.0
	for o in options:
		total += float(o[1]) * float(bias.get(o[0], 1.0))
	var pick := _rng.randf() * total
	for o in options:
		pick -= float(o[1]) * float(bias.get(o[0], 1.0))
		if pick <= 0.0:
			return o[0]
	return options[0][0]


# --- Manejo -------------------------------------------------------------------

func _drive(v: Dictionary, delta: float) -> void:
	var info: Dictionary = TYPES[v["kind"]]
	var desired: float = v["cruise"]
	# Subidas: los pesados van más lento.
	var grade: float = v.get("grade", 0.0)
	if grade > 0.0:
		desired *= clampf(1.0 - grade * float(info["climb"]), 0.4, 1.0)
	# Paradero: la combi se detiene un rato.
	if v["kind"] == "combi" and v["wait"] <= 0.0:
		for k in _paraderos.size():
			if not v["visited"].has(k) and _flat_dist(v["pos"], _paraderos[k]) < 7.0:
				v["visited"][k] = true
				v["wait"] = _rng.randf_range(PARADERO_STOP[0], PARADERO_STOP[1])
	if v["wait"] > 0.0:
		v["wait"] -= delta
		desired = 0.0
	# Obstáculos fijos: elige el lado libre; si no hay, frena antes.
	var block := _avoid_solids(v)
	var lat_goal: float = block[0]
	if block[1] != INF:
		desired = minf(desired, maxf(float(block[1]) - 1.5, 0.0) / HEADWAY)
	# Lo que hay delante (mototaxi, vehículos, animales).
	var gap := _gap_ahead(v)
	if gap < INF:
		desired = minf(desired, maxf(gap - 2.5, 0.0) / HEADWAY)
	var speed: float = v["speed"]
	speed = move_toward(speed, desired, (ACCEL if desired > speed else BRAKE) * delta)
	v["speed"] = speed
	v["stuck"] = v["stuck"] + delta if speed < 0.3 else 0.0
	v["lat"] = move_toward(float(v["lat"]), lat_goal, LATERAL_SPEED * delta)
	_advance(v, speed * delta)
	_place(v, delta)


## Avanza dist m por el trazo; en el final de la vía sigue por otra (o da la vuelta).
func _advance(v: Dictionary, dist: float) -> void:
	var guard := 0
	while dist > 0.0 and guard < 64:
		guard += 1
		var path := _paths[v["r"]]
		var j: int = v["i"] + v["ps"]
		if j < 0 or j >= path.size():
			_transfer(v)
			continue
		var seg := _flat_dist(path[v["i"]], path[j])
		var remain: float = seg - float(v["t"])
		if dist < remain:
			v["t"] = float(v["t"]) + dist
			return
		dist -= maxf(remain, 0.0)
		v["i"] = j
		v["t"] = 0.0


## Al final de la vía: otra vía que pase por ese punto (no la misma), o media vuelta.
func _transfer(v: Dictionary) -> void:
	var path := _paths[v["r"]]
	var here := path[v["i"]]
	var options: Array = []
	var weights: Array[float] = []
	var total := 0.0
	for o: Array in _joints.get(_key(here), []):
		var r2: int = o[0]
		var i2: int = o[1]
		if r2 == v["r"]:
			continue
		var n := _paths[r2].size()
		var w: float = 1.0 if v["kind"] in ["mototaxi", "camioneta"] or _roads[r2]["kind"] != 0 else 0.15
		if i2 < n - 1:
			options.append([r2, i2, 1])
			weights.append(w)
			total += w
		if i2 > 0:
			options.append([r2, i2, -1])
			weights.append(w)
			total += w
	if options.is_empty():
		v["ps"] = -int(v["ps"])
		v["t"] = 0.0
		return
	var pick := _rng.randf() * total
	var chosen: Array = options[-1]
	for k in options.size():
		pick -= weights[k]
		if pick <= 0.0:
			chosen = options[k]
			break
	v["r"] = chosen[0]
	v["i"] = chosen[1]
	v["ps"] = chosen[2]
	v["t"] = 0.0
	var road: Dictionary = _roads[v["r"]]
	v["lane"] = clampf(minf(road["width"] * 0.25, road["width"] * 0.5 - float(v["half_w"]) - 0.15), 0.3, 3.0)


## Punto del trazo d m adelante (sin cambiar de vía): {p, dir}.
func _sample(v: Dictionary, d: float) -> Dictionary:
	var path := _paths[v["r"]]
	var i: int = v["i"]
	var ps: int = v["ps"]
	var t: float = v["t"]
	while true:
		var j := i + ps
		if j < 0 or j >= path.size():
			var k := clampi(i - ps, 0, path.size() - 1)
			var dir := path[i] - path[k]
			return {"p": path[i], "dir": _flat(dir) if k != i else Vector3(v["fwd"])}
		var seg := _flat_dist(path[i], path[j])
		if t + d <= seg or seg <= 0.0001:
			var p := path[i].lerp(path[j], clampf((t + d) / maxf(seg, 0.0001), 0.0, 1.0))
			return {"p": p, "dir": _flat(path[j] - path[i])}
		d -= seg - t
		t = 0.0
		i = j
	return {}


## Pone el cuerpo en su lugar: sobre el terreno, en su carril, inclinado con la pendiente.
func _place(v: Dictionary, delta: float) -> void:
	var here := _sample(v, 0.0)
	var ahead := _sample(v, 3.0)
	var dir: Vector3 = _flat(ahead["p"] - here["p"])
	if dir.length() < 0.01:
		dir = here["dir"]
	v["yaw"] = lerp_angle(float(v["yaw"]), atan2(dir.x, dir.z), clampf(7.0 * delta, 0.0, 1.0))
	var f := Vector3(sin(v["yaw"]), 0.0, cos(v["yaw"]))
	var right := Vector3(-f.z, 0.0, f.x)
	var p: Vector3 = here["p"] + right * float(v["lat"])
	var hl: float = v["half_l"]
	var front := p + f * hl
	var back := p - f * hl
	var hf := world.get_height(front.x, front.z)
	var hb := world.get_height(back.x, back.z)
	p.y = maxf(world.get_height(p.x, p.z), (hf + hb) * 0.5)
	v["grade"] = (hf - hb) / (2.0 * hl)
	var f3 := Vector3(f.x * 2.0 * hl, hf - hb, f.z * 2.0 * hl).normalized()
	v["pos"] = p
	v["fwd"] = f
	var body: AnimatableBody3D = v["body"]
	body.global_transform = Transform3D(Basis.looking_at(f3, Vector3.UP, true), p)


## Distancia libre adelante, en su carril, hasta la mototaxi, otro vehículo o un animal.
func _gap_ahead(v: Dictionary) -> float:
	var p: Vector3 = v["pos"]
	var f: Vector3 = v["fwd"]
	var right := Vector3(-f.z, 0.0, f.x)
	var hw: float = v["half_w"]
	var hl: float = v["half_l"]
	var best := INF
	var things: Array = [[moto.global_position, 0.75, 1.3]]
	for o in vehicles:
		if o != v:
			things.append([o["pos"], o["half_w"], o["half_l"]])
	if animals:
		for g in animals.groups:
			for a: Dictionary in g["animals"]:
				if not a["hit"]:
					things.append([a["node"].global_position, 0.5, 0.5])
	for t: Array in things:
		var rel: Vector3 = t[0] - p
		rel.y = 0.0
		var along := rel.dot(f)
		if along <= 0.0 or along > LOOK_AHEAD + hl:
			continue
		# El corredor se abre un poco con la distancia (las curvas).
		if absf(rel.dot(right)) > hw + float(t[1]) + 0.3 + along * 0.04:
			continue
		best = minf(best, along - hl - float(t[2]))
	return best


## Obstáculos fijos adelante: [carril al que correrse, distancia a la que frenar (INF = no
## hace falta)]. Elige el corrimiento más chico que deja pasar; si no hay paso, frena antes.
## Mientras todavía no se corrió lo suficiente, también frena (para no atravesarlo).
func _avoid_solids(v: Dictionary) -> Array:
	var obs: RoadObstacles = world.obstacles if world else null
	var lane: float = v["lane"]
	if obs == null or obs.obstacles.is_empty():
		return [lane, INF]
	var hw: float = v["half_w"]
	var hl: float = v["half_l"]
	var solids := obs.solids_near(v["pos"], AVOID_AHEAD + 4.0)
	if solids.is_empty():
		return [lane, INF]
	# Tramo de adelante muestreado cada 2 m (desde la cola del vehículo).
	var samples: Array = []
	var d := -hl - 1.0
	while d <= AVOID_AHEAD:
		var smp := _sample(v, maxf(d, 0.0))
		smp["d"] = d
		if d < 0.0:
			smp["p"] = smp["p"] + smp["dir"] * d
		samples.append(smp)
		d += 2.0
	var intervals: Array = []   # [lat mín, lat máx, distancia]
	for solid: Array in solids:
		var sp := Vector3(solid[0], 0.0, solid[1])
		var best: Dictionary = {}
		var best_d := INF
		for smp: Dictionary in samples:
			var dd := _flat_dist(smp["p"], sp)
			if dd < best_d:
				best_d = dd
				best = smp
		var rel := sp - Vector3(best["p"].x, 0.0, best["p"].z)
		var along := rel.dot(best["dir"])
		if absf(along) > 1.2 + float(solid[2]):
			continue  # Más allá del tramo muestreado.
		var lat := rel.dot(Vector3(-best["dir"].z, 0.0, best["dir"].x))
		var r: float = solid[2]
		intervals.append([lat - r - hw - 0.35, lat + r + hw + 0.35, float(best["d"]) + along])
	if intervals.is_empty():
		return [lane, INF]
	var half_road: float = _roads[v["r"]]["width"] * 0.5
	var limit := maxf(half_road - hw - 0.1, 0.0)
	var goal := INF
	var cand := lane
	while cand >= -limit - 0.001 and goal == INF:
		if not _inside_any(cand, intervals):
			goal = cand
		cand -= 0.25
	cand = lane + 0.25
	while cand <= limit + 0.001 and goal == INF:
		if _inside_any(cand, intervals) == false:
			goal = cand
		cand += 0.25
	# Frena ante lo que todavía tapa su posición lateral actual (o todo, si no hay paso).
	var lat_now: float = v["lat"]
	var brake := INF
	for it: Array in intervals:
		if goal == INF or (lat_now > it[0] and lat_now < it[1]):
			brake = minf(brake, float(it[2]) - hl)
	return [goal if goal != INF else lane, brake]


static func _inside_any(x: float, intervals: Array) -> bool:
	for it: Array in intervals:
		if x > it[0] and x < it[1]:
			return true
	return false


# --- Golpes -------------------------------------------------------------------

func _check_hit(v: Dictionary) -> void:
	var body: AnimatableBody3D = v["body"]
	var local := body.global_transform.affine_inverse() * moto.global_position
	if absf(local.x) > float(v["half_w"]) + 0.8 or absf(local.z) > float(v["half_l"]) + 1.2 or absf(local.y) > 3.0:
		return
	if _grace > 0.0:
		return
	var vel: Vector3 = v["fwd"] * float(v["speed"])
	var rel_kmh := (moto.linear_velocity - vel).length() * 3.6
	if rel_kmh < 8.0:
		return
	_grace = HIT_GRACE
	hits += 1
	moto._hit_grace = 0.8  # El golpe ya cuenta aquí: que no se sume otro "choque".
	moto.apply_damage((rel_kmh - 8.0) * float(TYPES[v["kind"]]["damage"]), "vehiculo")
	v["wait"] = maxf(float(v["wait"]), 2.5)  # El chofer se detiene a reclamar.
	v["speed"] = 0.0


# --- Modelos ------------------------------------------------------------------

func _acquire(kind: String) -> AnimatableBody3D:
	var free: Array = _pool.get(kind, [])
	var body: AnimatableBody3D
	if not free.is_empty():
		body = free.pop_back()
	else:
		var model := _make_model(kind)
		if model == null:
			return null
		body = AnimatableBody3D.new()
		body.name = kind
		body.sync_to_physics = false
		add_child(body)
		body.add_child(model)
		var info: Dictionary = TYPES[kind]
		var box := RoadAnimals._model_aabb(model)
		var size := box.size
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(size.x, 0.5), maxf(size.y, 0.5) * 0.85, maxf(size.z, 0.5))
		shape.shape = bs
		shape.position = Vector3(0.0, bs.size.y * 0.5 + 0.1, 0.0)
		body.add_child(shape)
		body.set_meta("half_w", maxf(size.x, float(info["width"]) * 0.8) * 0.5)
		body.set_meta("half_l", maxf(size.z, float(info["length"]) * 0.8) * 0.5)
	body.visible = true
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.collision_layer = 1
	return body


func _release(v: Dictionary) -> void:
	var body: AnimatableBody3D = v["body"]
	if not is_instance_valid(body):
		return
	body.visible = false
	body.collision_layer = 0
	body.global_position = Vector3(0.0, -500.0, 0.0)
	if not _pool.has(v["kind"]):
		_pool[v["kind"]] = []
	_pool[v["kind"]].append(body)


## Modelo mirando a +Z, con el suelo en y = 0 y centrado.
func _make_model(kind: String) -> Node3D:
	var info: Dictionary = TYPES[kind]
	var inner: Node3D
	if kind == "mototaxi":
		var choices: Array[int] = []
		for k in VehicleCatalog.VEHICLES.size():
			if moto == null or k != moto.vehicle_index:
				choices.append(k)
		inner = VehicleCatalog.create_model(choices[_rng.randi() % choices.size()])
	elif kind == "combi":
		inner = make_combi(_rng)
	else:
		var file: String = info["model"]
		if not _scenes.has(file):
			_scenes[file] = load("res://assets/traffic/%s.glb" % file)
		var scene: PackedScene = _scenes[file]
		if scene == null:
			return null
		inner = scene.instantiate()
	if inner == null:
		return null
	var root := Node3D.new()
	root.add_child(inner)
	var box := RoadAnimals._model_aabb(inner)
	if box.size.x > box.size.z * 1.2:
		inner.rotation.y = PI * 0.5  # Modelo largo en X: se gira para que el largo quede en Z.
	inner.rotation.y += float(TRAFFIC_MODEL_YAW.get(kind, 0.0))
	box = RoadAnimals._model_aabb(root)
	var s := float(info["length"]) / maxf(box.size.z, 0.01) if kind != "mototaxi" else 1.0
	inner.scale *= s
	box = RoadAnimals._model_aabb(root)
	inner.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return root


## Giro extra (rad) para que el frente de los modelos importados quede en +Z.
const TRAFFIC_MODEL_YAW := {"camion": 0.0, "camioneta": 0.0}


## Combi peruana (minivan blanca con franjas de color, ventanas corridas y parrilla en el techo).
## Hecha con cajas y cilindros; mira a +Z.
static func make_combi(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stripes := [Color("d32f2f"), Color("1565c0"), Color("2e7d32"), Color("f9a825"), Color("6a1b9a")]
	var stripe: Color = stripes[rng.randi() % stripes.size()]
	var white := Color(0.93, 0.93, 0.9)
	var glass := Color(0.12, 0.15, 0.2)
	var dark := Color(0.08, 0.08, 0.08)
	var L := 4.6
	var W := 1.85
	_box(root, Vector3(W, 1.55, L), Vector3(0, 0.5 + 0.775, 0), white)                        # Carrocería.
	_box(root, Vector3(W + 0.02, 0.18, L + 0.02), Vector3(0, 0.82, 0), stripe)                  # Franja baja.
	_box(root, Vector3(W + 0.02, 0.08, L + 0.02), Vector3(0, 1.02, 0), stripe.lightened(0.3))   # Franja fina.
	_box(root, Vector3(W + 0.03, 0.5, L - 1.4), Vector3(0, 1.55, -0.35), glass)                # Ventanas de los lados.
	_box(root, Vector3(W - 0.2, 0.62, 0.05), Vector3(0, 1.6, L * 0.5 + 0.01), glass)            # Parabrisas.
	_box(root, Vector3(W - 0.3, 0.45, 0.05), Vector3(0, 1.62, -L * 0.5 - 0.01), glass)          # Luna de atrás.
	_box(root, Vector3(W, 0.22, 0.12), Vector3(0, 0.62, L * 0.5 + 0.04), dark)                  # Parachoques.
	_box(root, Vector3(W, 0.22, 0.12), Vector3(0, 0.62, -L * 0.5 - 0.04), dark)
	_box(root, Vector3(0.3, 0.14, 0.04), Vector3(-0.6, 0.98, L * 0.5 + 0.02), Color(1, 0.95, 0.75))  # Faros.
	_box(root, Vector3(0.3, 0.14, 0.04), Vector3(0.6, 0.98, L * 0.5 + 0.02), Color(1, 0.95, 0.75))
	_box(root, Vector3(0.25, 0.14, 0.04), Vector3(-0.65, 0.98, -L * 0.5 - 0.02), Color(0.8, 0.1, 0.1))
	_box(root, Vector3(0.25, 0.14, 0.04), Vector3(0.65, 0.98, -L * 0.5 - 0.02), Color(0.8, 0.1, 0.1))
	# Letrero de ruta sobre el parabrisas y parrilla en el techo.
	_box(root, Vector3(1.1, 0.2, 0.05), Vector3(0, 2.0, L * 0.5 + 0.02), Color(1.0, 0.85, 0.2))
	for x: float in [-0.75, 0.75]:
		_box(root, Vector3(0.05, 0.08, L - 1.2), Vector3(x, 2.12, -0.2), dark)
	for z: float in [-1.6, -0.6, 0.4, 1.2]:
		_box(root, Vector3(1.55, 0.05, 0.05), Vector3(0, 2.15, z), dark)
	# Ruedas.
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.33
	wheel.bottom_radius = 0.33
	wheel.height = 0.24
	wheel.radial_segments = 12
	var wm := StandardMaterial3D.new()
	wm.albedo_color = dark
	for x: float in [-W * 0.5 + 0.1, W * 0.5 - 0.1]:
		for z: float in [L * 0.5 - 0.85, -L * 0.5 + 0.8]:
			var mi := MeshInstance3D.new()
			mi.mesh = wheel
			mi.material_override = wm
			mi.rotation.z = PI * 0.5
			mi.position = Vector3(x, 0.33, z)
			root.add_child(mi)
	return root


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35 if color.v < 0.25 else 0.6
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# --- Utilidades ---------------------------------------------------------------

static func _key(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))


static func _flat(d: Vector3) -> Vector3:
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3.FORWARD


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _near_vehicle(p: Vector3, r: float) -> bool:
	for v in vehicles:
		if _flat_dist(p, v["pos"]) < r:
			return true
	return false


func _moto_forward() -> Vector3:
	var vel := moto.linear_velocity
	vel.y = 0.0
	if vel.length() > 2.0:
		return vel.normalized()
	var f := moto.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
