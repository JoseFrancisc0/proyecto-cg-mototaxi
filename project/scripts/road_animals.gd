class_name RoadAnimals
extends Node3D
## Animales en las vías (pendiente 10 fase 5 / pendiente 13 fase B): obstáculos que se mueven,
## estilo Mario Kart. Hay que esquivarlos; no son enemigos.
##
## Por región (la de get_biome en ese punto), con modelos de Quaternius (CC0, ver
## res://assets/animals/SOURCE.md):
##   costa: perros, gallinas, algún burro;  sierra: alpacas, ovejas (en rebaño), burros, vacas;
##   selva: gallinas, chanchos, vacas, algún perro.
## Más en calles del pueblo y trochas; pocos en carreteras abiertas.
##
## Solo existen cerca de la mototaxi: aparecen adelante (55–150 m) y se quitan lejos, sacados de
## un pozo de modelos para no instanciar cada vez. Comportamiento de cada grupo:
##   - PASTA al borde de la vía y CRUZA cuando la mototaxi se acerca (a 22–48 m: hay tiempo de
##     verlos); o
##   - CAMINA por la vía (rebaños de la sierra, vacas): ocupa el carril hasta que la mototaxi se
##     acerca despacio (< 15 km/h) o toca la bocina; ahí se aparta.
##   - Si la mototaxi pasa rozando o los golpea, HUYEN corriendo y se van.
## La bocina (H / B del mando, Mototaxi.honked) aparta a los que estén a menos de 35 m.
##
## Golpe (por cercanía, sin física: una gallina no frena en seco a la mototaxi):
##   daño = (km/h − 6) × factor de la especie (gallina ≈ 2, vaca ≈ 15 a 30 km/h), con razón
##   "animal" (RaceManager baja el ánimo del pasajero); los grandes además frenan la mototaxi.
##   Cada animal golpea una vez y hay 1.2 s de gracia entre golpes.
## Nunca aparecen a menos de 35 m de la recogida o del destino, ni sobre un puente.

const SPECIES := {
	# length: largo del cuerpo (m); radius: para el golpe; walk/run: m/s; damage: por km/h;
	# slow: fracción de velocidad que le quita a la mototaxi; herd: tamaño del grupo [mín, máx].
	"alpaca": {"length": 1.6, "radius": 0.55, "walk": 1.1, "run": 4.5, "damage": 0.45, "slow": 0.22, "herd": [2, 5]},
	"sheep": {"length": 1.15, "radius": 0.45, "walk": 0.9, "run": 3.5, "damage": 0.32, "slow": 0.15, "herd": [3, 7]},
	"donkey": {"length": 1.8, "radius": 0.6, "walk": 1.0, "run": 4.0, "damage": 0.55, "slow": 0.28, "herd": [1, 2]},
	"cow": {"length": 2.2, "radius": 0.75, "walk": 0.8, "run": 3.0, "damage": 0.65, "slow": 0.35, "herd": [1, 3]},
	"dog": {"length": 0.9, "radius": 0.4, "walk": 1.4, "run": 6.0, "damage": 0.22, "slow": 0.08, "herd": [1, 3]},
	"chicken": {"length": 0.5, "radius": 0.3, "walk": 0.8, "run": 3.2, "damage": 0.08, "slow": 0.0, "herd": [2, 5]},
	"pig": {"length": 1.1, "radius": 0.45, "walk": 0.9, "run": 3.4, "damage": 0.35, "slow": 0.15, "herd": [1, 3]},
}
## [especie, peso] por región (costa, sierra, selva).
const REGION_SPECIES := [
	[["dog", 5.0], ["chicken", 3.0], ["donkey", 1.0]],
	[["alpaca", 4.0], ["sheep", 4.0], ["donkey", 1.5], ["cow", 1.5]],
	[["chicken", 4.0], ["pig", 3.0], ["cow", 1.5], ["dog", 1.0]],
]
## Especies que suelen ir caminando por la vía en vez de cruzarla.
const ALONG_CHANCE := {"sheep": 0.6, "alpaca": 0.5, "cow": 0.5, "donkey": 0.3}
## Peso por tipo de vía (0 trocha, 1 carretera, 2 avenida, 3 calle).
const ROAD_WEIGHT := {0: 1.6, 1: 0.35, 2: 0.7, 3: 1.4}
const ANIM_IDLE := ["Idle"]
const ANIM_EAT := ["Eating", "Idle_Eating", "Idle_Peck", "Idle_Headlow"]
const ANIM_WALK := ["Walk", "WalkSlow", "Run"]
const ANIM_RUN := ["Gallop", "Run"]

const SITE_STEP := 20.0          ## Un lugar posible cada SITE_STEP m de vía.
const CELL := 40.0               ## Rejilla para buscar lugares cerca de la mototaxi.
const SPAWN_MIN := 55.0
const SPAWN_MAX := 150.0
const DESPAWN := 210.0
const BEHIND_DESPAWN := 90.0     ## Detrás de la mototaxi se quitan antes.
const STOP_CLEARANCE := 35.0     ## Distancia mínima a la recogida o el destino.
const GROUP_GAP := 45.0          ## Distancia mínima entre grupos.
const HORN_RADIUS := 35.0
const HIT_GRACE := 1.2
const BASE_GROUPS := 6.0         ## Grupos a la vez con densidad 1.

enum Mode { GRAZE, CROSS, ALONG, ASIDE, FLEE }

## Cantidad relativa (Difficulty "animals"): 0 = ninguno.
var density := 1.0
var world: TerrainWorld
var moto: Mototaxi
var race: RaceManager
## Golpes dados en la partida (diagnóstico y pruebas).
var hits := 0
var groups: Array[Dictionary] = []

var _sites: Array[Dictionary] = []          # {p: Vector3, dir: Vector3, width, kind, region, r, i}
var _paths: Array[PackedVector3Array] = []  # Trazo de cada vía (los que caminan por ella lo siguen).
var _cells := {}                            # Vector2i -> Array[int] (índices de _sites)
var _scenes := {}                           # especie -> PackedScene
var _scale := {}                            # especie -> escala del modelo
var _pool := {}                             # especie -> Array[Node3D] ocultos
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0
var _grace := 0.0


## Prepara los lugares posibles sobre las vías de w. Sale de la semilla del mundo.
func setup(w: TerrainWorld, m: Mototaxi, r: RaceManager, amount: float, world_seed: int) -> void:
	world = w
	moto = m
	race = r
	density = maxf(amount, 0.0)
	_rng.seed = hash("animales-%d" % world_seed)
	clear_all()
	_sites.clear()
	_cells.clear()
	_paths.clear()
	if density <= 0.0 or world == null:
		return
	var catchment := 60000.0
	if world.generator != null and world.generator.get("river_catchment") != null:
		catchment = float(world.generator.get("river_catchment"))
	for road in world.get_roads():
		var path: PackedVector3Array = road["path"]
		_paths.append(path)
		var acc := SITE_STEP * 0.5
		for i in range(1, path.size()):
			acc += path[i - 1].distance_to(path[i])
			if acc < SITE_STEP:
				continue
			acc = 0.0
			var p := path[i]
			if world.get_drainage(p.x, p.z) >= catchment * 0.3:  # Puente o cauce.
				continue
			var j := mini(i + 1, path.size() - 1)
			var dir := path[j] - path[i - 1]
			dir.y = 0.0
			if dir.length() < 0.01:
				continue
			_add_site({"p": p, "dir": dir.normalized(), "width": float(road["width"]), "kind": int(road["kind"]),
				"region": world.get_biome(p.x, p.z).max_axis_index(), "r": _paths.size() - 1, "i": i})
	if moto and not moto.honked.is_connected(_on_honk):
		moto.honked.connect(_on_honk)


func _add_site(site: Dictionary) -> void:
	_sites.append(site)
	var c := Vector2i(floori(site["p"].x / CELL), floori(site["p"].z / CELL))
	if not _cells.has(c):
		_cells[c] = []
	_cells[c].append(_sites.size() - 1)


## Quita todos los animales (reinicio, día nuevo, reaparecer).
func clear_all() -> void:
	for g in groups:
		for a: Dictionary in g["animals"]:
			_release(a)
	groups.clear()
	_spawn_timer = 1.0
	_grace = 0.0


func get_animal_count() -> int:
	var n := 0
	for g in groups:
		n += g["animals"].size()
	return n


func _physics_process(delta: float) -> void:
	if density <= 0.0 or moto == null or _sites.is_empty():
		return
	_grace = maxf(_grace - delta, 0.0)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = _rng.randf_range(0.8, 1.6) / density
		if groups.size() < ceili(BASE_GROUPS * density):
			_try_spawn()
	var mp := moto.global_position
	var fwd := _moto_forward()
	var kmh := moto.linear_velocity.length() * 3.6
	for gi in range(groups.size() - 1, -1, -1):
		var g: Dictionary = groups[gi]
		var center := _group_center(g)
		var to := center - mp
		to.y = 0.0
		var dist := to.length()
		if dist > DESPAWN or (dist > BEHIND_DESPAWN and to.dot(fwd) < 0.0):
			for a: Dictionary in g["animals"]:
				_release(a)
			groups.remove_at(gi)
			continue
		_update_group(g, dist, kmh, delta)
		for a: Dictionary in g["animals"]:
			_update_animal(a, delta)
			_check_hit(g, a, kmh)


## Grupo nuevo en un lugar adelante de la mototaxi.
func _try_spawn() -> void:
	var mp := moto.global_position
	var fwd := _moto_forward()
	var avoid := _stop_positions()
	var candidates: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	var c0 := Vector2i(floori(mp.x / CELL), floori(mp.z / CELL))
	var r := ceili(SPAWN_MAX / CELL)
	for cx in range(c0.x - r, c0.x + r + 1):
		for cz in range(c0.y - r, c0.y + r + 1):
			for idx: int in _cells.get(Vector2i(cx, cz), []):
				var s: Dictionary = _sites[idx]
				var to: Vector3 = s["p"] - mp
				to.y = 0.0
				var d := to.length()
				if d < SPAWN_MIN or d > SPAWN_MAX or to.dot(fwd) < d * 0.25:
					continue
				if _near_any(s["p"], avoid, STOP_CLEARANCE) or _near_group(s["p"], GROUP_GAP):
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
		if pick <= 0.0:
			_spawn_group(_sites[candidates[k]])
			return
	_spawn_group(_sites[candidates[-1]])


## Grupo en site; species "" = al azar según la región.
func _spawn_group(site: Dictionary, species := "") -> void:
	if species == "":
		species = _pick_species(int(site["region"]))
	var info: Dictionary = SPECIES[species]
	var herd: Array = info["herd"]
	var count := _rng.randi_range(herd[0], herd[1])
	var dir: Vector3 = site["dir"]
	var side := Vector3(dir.z, 0.0, -dir.x)  # Perpendicular a la vía.
	var half: float = site["width"] * 0.5
	var along := _rng.randf() < float(ALONG_CHANCE.get(species, 0.0))
	# Solo pastan a un costado con suelo parejo (no en la ladera de una vía cortada en el cerro).
	var ok := {1.0: _side_ok(site, 1.0), -1.0: _side_ok(site, -1.0)}
	var s := 1.0 if _rng.randf() < 0.5 else -1.0
	if not ok[s]:
		s = -s
	if not ok[s]:
		along = true  # Ningún costado sirve: van por la vía.
	var g := {"species": species, "mode": Mode.ALONG if along else Mode.GRAZE, "site": site, "side": s, "ok": ok,
		"back": false, "trigger": _rng.randf_range(22.0, 48.0), "animals": [], "dir": dir if _rng.randf() < 0.5 else -dir}
	for k in count:
		var a := _acquire(species)
		if a.is_empty():
			break
		var spread := _rng.randf_range(-4.0, 4.0) if count > 1 else 0.0
		var lateral: float
		if along:
			lateral = _rng.randf_range(-half * 0.7, half * 0.7)
		else:
			lateral = s * (half + _rng.randf_range(1.5, 4.5))
		var p: Vector3 = site["p"] + dir * spread + side * lateral
		a["node"].global_position = _ground(p)
		a["target"] = Vector3.INF
		a["delay"] = _rng.randf_range(0.0, 0.9)
		a["hit"] = false
		if along:
			_face(a, g["dir"])
			a["speed"] = float(info["walk"]) * _rng.randf_range(0.8, 1.1)
			# Siguen el trazo de la vía (en las curvas no se salen).
			a["follow"] = site.has("r")
			if site.has("r"):
				a["site_r"] = int(site["r"])
			a["lat"] = lateral
			a["pi"] = int(site.get("i", 0))
			a["ps"] = 1 if g["dir"].dot(dir) > 0.0 else -1
			a["walked"] = 0.0
			a["target"] = _next_on_path(a) if a["follow"] else p + g["dir"] * 40.0
			_play(a, ANIM_WALK, a["speed"] / float(info["walk"]))
		else:
			_face(a, side * -s)
			_play(a, ANIM_EAT if _rng.randf() < 0.6 else ANIM_IDLE)
		g["animals"].append(a)
	if not g["animals"].is_empty():
		groups.append(g)


func _pick_species(region: int) -> String:
	var options: Array = REGION_SPECIES[clampi(region, 0, 2)]
	var total := 0.0
	for o in options:
		total += o[1]
	var pick := _rng.randf() * total
	for o in options:
		pick -= o[1]
		if pick <= 0.0:
			return o[0]
	return options[0][0]


## Cambios de modo del grupo según la mototaxi.
func _update_group(g: Dictionary, dist: float, kmh: float, _delta: float) -> void:
	var site: Dictionary = g["site"]
	var dir: Vector3 = site["dir"]
	var side := Vector3(dir.z, 0.0, -dir.x)
	var half: float = site["width"] * 0.5
	var info: Dictionary = SPECIES[g["species"]]
	match g["mode"]:
		Mode.GRAZE:
			if dist < g["trigger"]:
				g["mode"] = Mode.CROSS
				var s: float = g["side"]
				# Si el otro lado es ladera, se meten a la vía y después vuelven a su lado.
				g["back"] = not g["ok"][-s]
				for a: Dictionary in g["animals"]:
					var p: Vector3 = a["node"].global_position
					var lat: float = (p - site["p"]).dot(side)
					var goal: float = -s * half * _rng.randf_range(0.1, 0.5) if g["back"] else -s * (half + _rng.randf_range(1.5, 4.0))
					a["target"] = p + side * (goal - lat)
					a["home"] = lat
					a["speed"] = float(info["run"] if g["species"] in ["dog", "chicken"] else info["walk"] * 1.6) * _rng.randf_range(0.85, 1.15)
		Mode.CROSS:
			if g["back"] and g["animals"].all(func(a): return a["target"] == Vector3.INF):
				g["mode"] = Mode.ASIDE
				for a: Dictionary in g["animals"]:
					if a["hit"]:
						continue
					var p: Vector3 = a["node"].global_position
					var lat: float = (p - site["p"]).dot(side)
					a["target"] = p + side * (float(a["home"]) - lat)
					a["delay"] = _rng.randf_range(0.5, 2.0)
		Mode.ALONG:
			# Se apartan si la mototaxi se acerca despacio.
			if dist < 16.0 and kmh < 15.0:
				_step_aside(g)


## Los que van por la vía se van al borde más cercano.
func _step_aside(g: Dictionary) -> void:
	var site: Dictionary = g["site"]
	var dir: Vector3 = site["dir"]
	var side := Vector3(dir.z, 0.0, -dir.x)
	var half: float = site["width"] * 0.5
	var info: Dictionary = SPECIES[g["species"]]
	g["mode"] = Mode.ASIDE
	for a: Dictionary in g["animals"]:
		if a["hit"]:
			continue
		var here := _local_site(g, a)
		side = Vector3(here["dir"].z, 0.0, -here["dir"].x)
		var p: Vector3 = a["node"].global_position
		var lat: float = (p - here["p"]).dot(side)
		var s := 1.0 if lat >= 0.0 else -1.0
		if not here["ok"][s] and here["ok"][-s]:
			s = -s
		# Sin costado parejo, se quedan en la berma.
		var goal: float = s * (half + _rng.randf_range(1.5, 3.5)) if here["ok"][s] else s * maxf(half - 0.3, 0.5)
		a["follow"] = false
		a["target"] = p + side * (goal - lat)
		a["speed"] = float(info["walk"]) * 1.8
		a["delay"] = _rng.randf_range(0.0, 0.4)


func _update_animal(a: Dictionary, delta: float) -> void:
	var node: Node3D = a["node"]
	var target: Vector3 = a["target"]
	if target == Vector3.INF:
		return
	if a["delay"] > 0.0:
		a["delay"] -= delta
		return
	var p := node.global_position
	var to := target - p
	to.y = 0.0
	var d := to.length()
	var info: Dictionary = SPECIES[a["species"]]
	if d < 0.2:
		a["target"] = _next_on_path(a) if a["follow"] else Vector3.INF
		if a["target"] == Vector3.INF:
			_play(a, ANIM_EAT if _rng.randf() < 0.5 else ANIM_IDLE)
		return
	var step := minf(float(a["speed"]) * delta, d)
	node.global_position = _ground(p + to / d * step)
	_face(a, to / d, 8.0 * delta)
	var runs := float(a["speed"]) > float(info["walk"]) * 1.9
	_play(a, ANIM_RUN if runs else ANIM_WALK, float(a["speed"]) / (float(info["run"]) if runs else float(info["walk"])))


## Golpe por cercanía con la mototaxi; también huyen si pasa rozando.
func _check_hit(g: Dictionary, a: Dictionary, kmh: float) -> void:
	if a["hit"]:
		return
	var info: Dictionary = SPECIES[a["species"]]
	var d: Vector3 = a["node"].global_position - moto.global_position
	d.y = 0.0
	var dist := d.length()
	var reach := float(info["radius"]) + 0.85
	if dist < reach + 2.5 and kmh > 20.0:
		_flee(a, d)  # Susto: se va corriendo, pero puede no alcanzar a salir.
	if dist > reach or kmh < 4.0 or _grace > 0.0:
		return
	a["hit"] = true
	hits += 1
	_grace = HIT_GRACE
	_flee(a, d)
	var dmg := maxf(kmh - 6.0, 0.0) * float(info["damage"])
	if dmg > 0.0:
		moto.apply_damage(dmg, "animal")
	var slow := float(info["slow"])
	if slow > 0.0:
		moto.linear_velocity *= 1.0 - slow


func _flee(a: Dictionary, away: Vector3) -> void:
	if a.get("fleeing", false):
		return
	a["fleeing"] = true
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	var info: Dictionary = SPECIES[a["species"]]
	var g := _group_of(a)
	if not g.is_empty():
		# No suben la ladera: corren por la vía hacia el lado que sea parejo.
		var here := _local_site(g, a)
		var dir: Vector3 = here["dir"]
		var side := Vector3(dir.z, 0.0, -dir.x)
		var lat := away.dot(side)
		var s := 1.0 if lat >= 0.0 else -1.0
		if not here["ok"][s]:
			away -= side * lat
			if away.length() < 0.1:
				away = dir
	a["follow"] = false
	a["target"] = a["node"].global_position + away.normalized() * 30.0
	a["speed"] = float(info["run"])
	a["delay"] = 0.0


func _on_honk() -> void:
	if moto == null:
		return
	for g in groups:
		if _group_center(g).distance_to(moto.global_position) > HORN_RADIUS:
			continue
		if g["mode"] == Mode.ALONG:
			_step_aside(g)
		elif g["mode"] == Mode.GRAZE:
			g["mode"] = Mode.ASIDE  # Se quedan a un lado: ya no cruzan.
			for a: Dictionary in g["animals"]:
				_play(a, ANIM_IDLE)


## Siguiente punto (≥ 3 m) sobre el trazo de la vía, con el mismo corrimiento lateral; INF si
## se acabó la vía o ya caminó 50 m.
func _next_on_path(a: Dictionary) -> Vector3:
	var path: PackedVector3Array = _paths[a["site_r"]] if a.has("site_r") else PackedVector3Array()
	if path.is_empty() or float(a["walked"]) > 50.0:
		a["follow"] = false
		return Vector3.INF
	var i: int = a["pi"]
	var start := path[clampi(i, 0, path.size() - 1)]
	while true:
		i += int(a["ps"])
		if i <= 0 or i >= path.size() - 1:
			a["follow"] = false
			return Vector3.INF
		if path[i].distance_to(start) >= 3.0:
			break
	a["walked"] = float(a["walked"]) + path[i].distance_to(start)
	a["pi"] = i
	var t := path[i + 1] - path[i - 1]
	t.y = 0.0
	t = t.normalized()
	return path[i] + Vector3(t.z, 0.0, -t.x) * float(a["lat"])


## El tramo de vía donde está el animal ahora (los que caminan por la vía se alejan de donde
## aparecieron), con sus costados parejos ("ok").
func _local_site(g: Dictionary, a: Dictionary) -> Dictionary:
	var site: Dictionary = g["site"]
	if not a.has("site_r") or int(a["pi"]) == int(site.get("i", -1)):
		return {"p": site["p"], "dir": site["dir"], "width": site["width"], "ok": g["ok"]}
	var path: PackedVector3Array = _paths[a["site_r"]]
	var i := clampi(int(a["pi"]), 1, path.size() - 2)
	var t := path[i + 1] - path[i - 1]
	t.y = 0.0
	var here := {"p": path[i], "dir": t.normalized(), "width": site["width"]}
	here["ok"] = {1.0: _side_ok(here, 1.0), -1.0: _side_ok(here, -1.0)}
	return here


## true si a ese costado de la vía (s = ±1) hay suelo parejo para pararse.
func _side_ok(site: Dictionary, s: float) -> bool:
	var dir: Vector3 = site["dir"]
	var side := Vector3(dir.z, 0.0, -dir.x) * s
	var half: float = site["width"] * 0.5
	for along: float in [-4.0, 0.0, 4.0]:
		var base: Vector3 = site["p"] + dir * along
		var edge := base + side * (half + 0.3)
		var he := world.get_height(edge.x, edge.z)
		for lateral: float in [half + 2.0, half + 4.5]:
			var p := base + side * lateral
			if absf(world.get_height(p.x, p.z) - he) > 0.35 * (lateral - half - 0.3) + 0.3:
				return false
			if world.get_normal(p.x, p.z).y < 0.85:
				return false
	return true


func _group_of(a: Dictionary) -> Dictionary:
	for g in groups:
		if g["animals"].has(a):
			return g
	return {}


# --- Modelos ----------------------------------------------------------------

func _acquire(species: String) -> Dictionary:
	var free: Array = _pool.get(species, [])
	var node: Node3D
	if not free.is_empty():
		node = free.pop_back()
		node.visible = true
	else:
		if not _scenes.has(species):
			_scenes[species] = load("res://assets/animals/%s.glb" % species)
		var scene: PackedScene = _scenes[species]
		if scene == null:
			return {}
		var model: Node3D = scene.instantiate()
		node = Node3D.new()
		node.name = species
		node.add_child(model)
		if not _scale.has(species):
			var box := _model_aabb(model)
			_scale[species] = float(SPECIES[species]["length"]) / maxf(box.size.z, 0.01)
		model.scale = Vector3.ONE * float(_scale[species])
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			for n in anim.get_animation_list():
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		node.set_meta("anim", anim)
		add_child(node)
	return {"species": species, "node": node, "anim": node.get_meta("anim"), "target": Vector3.INF,
		"speed": 0.0, "delay": 0.0, "hit": false, "fleeing": false, "playing": "", "home": 0.0,
		"follow": false, "lat": 0.0, "pi": 0, "ps": 1, "walked": 0.0}


func _release(a: Dictionary) -> void:
	var node: Node3D = a["node"]
	if not is_instance_valid(node):
		return
	node.visible = false
	var anim: AnimationPlayer = a["anim"]
	if anim:
		anim.stop()
	if not _pool.has(a["species"]):
		_pool[a["species"]] = []
	_pool[a["species"]].append(node)


func _play(a: Dictionary, names: Array, speed := 1.0) -> void:
	var anim: AnimationPlayer = a["anim"]
	if anim == null:
		return
	anim.speed_scale = clampf(speed, 0.4, 2.5)
	for n: String in names:
		var full := _find_anim(anim, n)
		if full != "":
			if a["playing"] != full:
				a["playing"] = full
				anim.play(full, 0.25)
				anim.seek(_rng.randf() * anim.current_animation_length)
			return


## Nombre completo de la animación que termina en "|name" (o se llama name).
static func _find_anim(anim: AnimationPlayer, n: String) -> String:
	if anim.has_animation(n):
		return n
	for full in anim.get_animation_list():
		if full.ends_with("|" + n):
			return full
	return ""


static func _model_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is Node3D and n != root:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var b: AABB = xf * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	return box


# --- Utilidades -------------------------------------------------------------

func _face(a: Dictionary, dir: Vector3, weight := 1.0) -> void:
	if dir.length() < 0.01:
		return
	var node: Node3D = a["node"]
	node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.z), clampf(weight, 0.0, 1.0))


func _ground(p: Vector3) -> Vector3:
	p.y = world.get_height(p.x, p.z) if world else p.y
	return p


func _group_center(g: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	for a: Dictionary in g["animals"]:
		c += a["node"].global_position
	return c / maxf(g["animals"].size(), 1)


func _moto_forward() -> Vector3:
	var v := moto.linear_velocity
	v.y = 0.0
	if v.length() > 2.0:
		return v.normalized()
	var f := moto.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


## Recogida o destino actual.
func _stop_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if race:
		var t := race.get_target()
		if t != Vector3.INF:
			out.append(t)
	return out


static func _near_any(p: Vector3, list: Array[Vector3], r: float) -> bool:
	for q in list:
		if Vector2(p.x - q.x, p.z - q.z).length() < r:
			return true
	return false


func _near_group(p: Vector3, r: float) -> bool:
	for g in groups:
		var c := _group_center(g)
		if Vector2(p.x - c.x, p.z - c.z).length() < r:
			return true
	return false
