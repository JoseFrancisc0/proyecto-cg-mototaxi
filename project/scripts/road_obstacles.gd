class_name RoadObstacles
extends Node3D
## Obstáculos fijos sobre las vías (pendiente 6), según la región y el tipo de vía:
##   rocas  — piedras de un derrumbe o huaico (sierra; algo en la costa). Sólidas.
##   tronco — árbol caído (selva; eucalipto en la sierra). Sólido.
##   obra   — barriles de una obra en la vía, con conos de aviso antes (los conos se tumban).
##   charco — charco o barro (sierra y selva): frena y resbala.
##   arena  — arena que el viento metió a la pista (costa): frena y resbala.
##   bache  — hueco en la pista: sacudón, y algo de daño si se pasa rápido.
## Los sólidos tapan solo un lado de la vía (siempre queda un carril libre de FREE_LANE m) y van
## en tramos rectos y sin mucha pendiente, para verlos venir. Ninguno va sobre una parada, un
## cruce o un puente. Todo sale de la semilla del mundo: mismo mapa, mismos obstáculos.
## Chocar un sólido lo detecta Mototaxi._check_crash (frenazo brusco); los charcos, la arena y
## los baches los consulta la mototaxi por rueda con TerrainWorld.get_hazard().

enum Kind { ROCAS, TRONCO, OBRA, CHARCO, ARENA, BACHE }
const KIND_NAMES := ["rocas", "tronco", "obra", "charco", "arena", "bache"]

const HAZARD_NONE := 0
const HAZARD_SLOW := 1   ## Barro o arena.
const HAZARD_BUMP := 2   ## Bache.

## Niveles de Opciones: nombre y multiplicador de cantidad.
const LEVELS := [["Ninguno", 0.0], ["Pocos", 0.5], ["Normal", 1.0], ["Muchos", 1.8]]

## Distancia media (m) entre obstáculos con densidad 1, por tipo de vía
## (0 trocha, 1 carretera, 2 avenida, 3 calle).
const SPACING := {0: 120.0, 1: 150.0, 2: 170.0, 3: 140.0}

## Pesos [rocas, tronco, obra, charco, arena, bache] por región (costa, sierra, selva) ...
const REGION_WEIGHTS := [
	[18.0, 0.0, 15.0, 0.0, 37.0, 30.0],
	[40.0, 10.0, 10.0, 20.0, 0.0, 20.0],
	[5.0, 35.0, 10.0, 35.0, 0.0, 15.0],
]
## ... y multiplicador por tipo de vía: en el pueblo casi todo son baches y obras.
const ROAD_FACTORS := {
	0: [1.0, 1.3, 0.0, 1.5, 1.0, 1.2],
	1: [1.2, 1.0, 1.0, 0.8, 1.2, 0.8],
	2: [0.8, 0.8, 1.3, 1.0, 1.0, 1.0],
	3: [0.15, 0.2, 2.0, 1.0, 0.5, 2.5],
}
const SOLID_KINDS := [Kind.ROCAS, Kind.TRONCO, Kind.OBRA]

const FREE_LANE := 2.8          ## Ancho libre mínimo (m) junto a un obstáculo sólido (la mototaxi mide 1.3 m).
const MIN_GAP := 45.0           ## Distancia mínima entre obstáculos.
const STOP_CLEARANCE := 16.0    ## Distancia mínima a una parada (recogida, destino, inicio).
const CROSS_CLEARANCE := 14.0   ## Distancia mínima a un cruce.
const GRID := 16.0
const TILE := 192.0             ## Las mallas se juntan por baldosas de TILE m (pocas llamadas de dibujo).
const VIEW_DISTANCE := 280.0

## { kind, position, dir, region, road_kind, width, solids: [[x, z, r]], hazards: [[x, z, r, efecto]] }
var obstacles: Array[Dictionary] = []
var counts := {}                       ## nombre -> cantidad
var rejected := {}                     ## motivo -> candidatos descartados (diagnóstico)
var _hazards := {}                     # Vector2i -> Array de [x, z, radio, efecto]
var _solids := {}                      # Vector2i -> Array de [x, z, radio]
var _rng := RandomNumberGenerator.new()
var _world: TerrainWorld
var _tiles := {}                       # Vector2i -> [geometría sólida, geometría mojada]
var _cone_mesh: ArrayMesh
var _current: Dictionary  # Obstáculo que se está armando.


func clear() -> void:
	obstacles.clear()
	counts.clear()
	rejected.clear()
	_hazards.clear()
	_solids.clear()
	_tiles.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()  # Diferido: puede haber cuerpos en medio de un paso de física.


## Reparte los obstáculos sobre las vías de world. density 0 = ninguno.
func build(world: TerrainWorld, density: float, world_seed: int) -> void:
	clear()
	if density <= 0.0:
		return
	_world = world
	_rng.seed = hash("obstaculos-%d" % world_seed)
	var roads := world.get_roads()
	var uses := {}  # Puntos compartidos entre vías (cruces), a 10 cm como RoadRouter.
	for road in roads:
		var seen := {}
		for p: Vector3 in road["path"]:
			var k := Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))
			if not seen.has(k):
				seen[k] = true
				uses[k] = uses.get(k, 0) + 1
	var stops: Array[Vector3] = []
	for lm in world.get_landmarks():
		stops.append(lm["position"])
	var catchment := 60000.0
	if world.generator != null and world.generator.get("river_catchment") != null:
		catchment = float(world.generator.get("river_catchment"))
	for road in roads:
		var kind: int = road["kind"]
		var path: PackedVector3Array = road["path"]
		var spacing: float = SPACING.get(kind, 220.0) / density
		var next := _rng.randf_range(0.3, 1.3) * spacing
		var acc := 0.0
		for i in range(1, path.size() - 1):
			acc += path[i - 1].distance_to(path[i])
			# Si el punto no sirve (parada, cruce, ...), se prueba unos metros más allá.
			if acc < next or not _try_place(road, i, uses, stops, catchment):
				continue
			acc = 0.0
			next = _rng.randf_range(0.5, 1.5) * spacing
	_commit_tiles()


## Efecto del suelo en (x, z): HAZARD_NONE, HAZARD_SLOW o HAZARD_BUMP.
func hazard_at(x: float, z: float) -> int:
	var cell: Array = _hazards.get(Vector2i(floori(x / GRID), floori(z / GRID)), [])
	var found := HAZARD_NONE
	for h: Array in cell:
		if Vector2(x - h[0], z - h[1]).length_squared() < h[2] * h[2]:
			if h[3] == HAZARD_BUMP:
				return HAZARD_BUMP
			found = h[3]
	return found


## Partes sólidas a menos de radius de p: [[x, z, radio], ...] (para el piloto automático).
func solids_near(p: Vector3, radius: float) -> Array:
	var out := []
	var r := ceili(radius / GRID)
	var c0 := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	var seen := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for s: Array in _solids.get(c0 + Vector2i(dx, dz), []):
				if seen.has(s):
					continue
				seen[s] = true
				if Vector2(s[0] - p.x, s[1] - p.z).length() < radius + s[2]:
					out.append(s)
	return out


# --- Colocación -----------------------------------------------------------------

func _try_place(road: Dictionary, i: int, uses: Dictionary, stops: Array[Vector3], catchment: float) -> bool:
	var path: PackedVector3Array = road["path"]
	var p := path[i]
	var w := _world
	if not w.is_inside(p.x, p.z) or w.get_reach_id(p.x, p.z) < 0:
		return _reject("fuera")
	if w.get_drainage(p.x, p.z) >= catchment * 0.3:  # Puente o cauce.
		return _reject("rio")
	for s in stops:
		if Vector2(s.x - p.x, s.z - p.z).length() < STOP_CLEARANCE:
			return _reject("parada")
	for o in obstacles:
		if Vector2(o["position"].x - p.x, o["position"].z - p.z).length() < MIN_GAP:
			return _reject("otro")
	var i0 := _walk(path, i, -CROSS_CLEARANCE)
	var i1 := _walk(path, i, CROSS_CLEARANCE)
	for j in range(i0, i1 + 1):
		if uses.get(Vector2i(roundi(path[j].x * 10.0), roundi(path[j].z * 10.0)), 0) > 1:
			return _reject("cruce")
	var a := path[_walk(path, i, -4.0)]
	var b := path[_walk(path, i, 4.0)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < 0.5:
		return false
	dir = dir.normalized()
	var region := w.get_biome(p.x, p.z).max_axis_index()
	var kind_road: int = road["kind"]
	var weights: Array = REGION_WEIGHTS[region].duplicate()
	var factors: Array = ROAD_FACTORS.get(kind_road, ROAD_FACTORS[1])
	var width: float = road["width"]
	var solid_ok := width >= FREE_LANE + 1.4 and _straight_and_flat(path, i)
	for k in weights.size():
		weights[k] *= factors[k]
		if k in SOLID_KINDS and not solid_ok:
			weights[k] = 0.0
	var kind := _pick(weights)
	if kind < 0:
		return _reject("sin tipo")
	var ground := Vector3(p.x, w.get_height(p.x, p.z), p.z)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var o := {"kind": kind, "position": ground, "dir": dir, "region": region, "road_kind": kind_road, "width": width,
		"solids": [], "hazards": []}
	_current = o
	match kind:
		Kind.ROCAS: _make_rocks(o, side)
		Kind.TRONCO: _make_log(o, side)
		Kind.OBRA: _make_works(o, side)
		Kind.CHARCO: _make_puddle(o)
		Kind.ARENA: _make_sand(o, side)
		Kind.BACHE: _make_potholes(o)
	obstacles.append(o)
	counts[KIND_NAMES[kind]] = counts.get(KIND_NAMES[kind], 0) + 1
	return true


func _reject(reason: String) -> bool:
	rejected[reason] = rejected.get(reason, 0) + 1
	return false


## Índice del punto de path a unos d metros de i (d < 0 = hacia atrás).
static func _walk(path: PackedVector3Array, i: int, d: float) -> int:
	var step := 1 if d > 0.0 else -1
	var acc := 0.0
	var j := i
	while acc < absf(d) and j + step >= 0 and j + step < path.size():
		acc += path[j].distance_to(path[j + step])
		j += step
	return j


## Tramo casi recto (se ve venir el obstáculo desde ~20 m) y sin mucha pendiente.
func _straight_and_flat(path: PackedVector3Array, i: int) -> bool:
	var back := path[i] - path[_walk(path, i, -20.0)]
	var fwd := path[_walk(path, i, 20.0)] - path[i]
	back.y = 0.0
	fwd.y = 0.0
	if back.length() < 14.0 or fwd.length() < 14.0 or back.angle_to(fwd) > 0.6:
		return false
	var a := path[_walk(path, i, -10.0)]
	var b := path[_walk(path, i, 10.0)]
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	return run > 5.0 and absf(b.y - a.y) / run < 0.14


func _pick(weights: Array) -> int:
	var total := 0.0
	for x in weights:
		total += x
	if total <= 0.0:
		return -1
	var r := _rng.randf() * total
	for k in weights.size():
		r -= weights[k]
		if r < 0.0:
			return k
	return weights.size() - 1


## Punto del obstáculo: lat metros al costado (+ = lado derecho de dir) y along metros a lo largo.
func _at(o: Dictionary, lat: float, along: float) -> Vector3:
	var dir: Vector3 = o["dir"]
	var right := Vector3(-dir.z, 0.0, dir.x)
	var q: Vector3 = o["position"] + right * lat + dir * along
	q.y = _world.get_height(q.x, q.z)
	return q


## Cuánto puede ocupar un sólido desde el borde sin quitar el carril libre.
## Cuánto tapa un sólido desde el borde: alrededor de media vía (en la carretera llega a la línea
## del centro), sin quitar nunca el carril libre.
func _reach(o: Dictionary) -> float:
	var w: float = o["width"]
	return clampf(w * _rng.randf_range(0.45, 0.62), 1.4, w - FREE_LANE)


func _add_hazard(x: float, z: float, r: float, effect: int) -> void:
	_current["hazards"].append([x, z, r, effect])
	_add_to_grid(_hazards, [x, z, r, effect], x, z, r)


func _add_solid(x: float, z: float, r: float) -> void:
	_current["solids"].append([x, z, r])
	_add_to_grid(_solids, [x, z, r], x, z, r)


static func _add_to_grid(grid: Dictionary, entry: Array, x: float, z: float, r: float) -> void:
	for cz in range(floori((z - r) / GRID), floori((z + r) / GRID) + 1):
		for cx in range(floori((x - r) / GRID), floori((x + r) / GRID) + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(entry)


enum Layer { SOLID, WET, FLAT }  # Opaco; agua brillante con borde transparente; mancha mate con borde transparente.

func _geo(p: Vector3, layer := Layer.SOLID) -> _Geo:
	var key := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	if not _tiles.has(key):
		_tiles[key] = [_Geo.new(), _Geo.new(), _Geo.new()]
	return _tiles[key][layer]


func _body(o: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [KIND_NAMES[o["kind"]], obstacles.size()]
	add_child(body)
	return body


func _cylinder(body: StaticBody3D, base: Vector3, radius: float, height: float, axis := Vector3.UP) -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	shape.transform = Transform3D(Basis(x, y, x.cross(y)), base + y * height * 0.5 if axis == Vector3.UP else base)
	body.add_child(shape)


# --- Tipos de obstáculo -------------------------------------------------------------

const ROCK_COLORS := [Color(0.50, 0.44, 0.36), Color(0.47, 0.46, 0.44), Color(0.36, 0.34, 0.29)]
const ROCK_TOPS := [Color(0.60, 0.53, 0.42), Color(0.60, 0.58, 0.54), Color(0.30, 0.40, 0.22)]

func _make_rocks(o: Dictionary, side: float) -> void:
	var half: float = o["width"] * 0.5
	var reach := _reach(o)
	var body := _body(o)
	var region: int = o["region"]
	var n := 2 + int(reach / 1.1) + _rng.randi_range(0, 1)
	for k in n:
		var r := _rng.randf_range(0.55, 0.95) if k % 2 == 0 else _rng.randf_range(0.35, 0.6)
		# Repartidas a lo ancho de lo que tapan: entre ellas no pasa la mototaxi.
		var lat := side * (lerpf(half + 0.2, half - reach + r * 0.8, float(k) / (n - 1)) + _rng.randf_range(-0.2, 0.2))
		var c := _at(o, lat, _rng.randf_range(-1.0, 1.0))
		var color: Color = ROCK_COLORS[region].lerp(Color(0.5, 0.48, 0.45), _rng.randf() * 0.3)
		_geo(c).rock(c + Vector3.UP * r * 0.3, Vector3(r, r * 0.75, r * _rng.randf_range(0.8, 1.2)), color, ROCK_TOPS[region], _rng)
		_cylinder(body, c - Vector3.UP * 0.2, r * 0.85, r * 1.1 + 0.2)
		_add_solid(c.x, c.z, r * 0.85)
	# Piedritas sueltas del derrumbe (solo se ven).
	for k in _rng.randi_range(4, 8):
		var c := _at(o, side * _rng.randf_range(half - reach - 1.0, half + 0.5), _rng.randf_range(-3.0, 3.0))
		var r := _rng.randf_range(0.08, 0.2)
		_geo(c).rock(c + Vector3.UP * r * 0.2, Vector3(r, r * 0.7, r), ROCK_COLORS[region], ROCK_TOPS[region], _rng)


func _make_log(o: Dictionary, side: float) -> void:
	var half: float = o["width"] * 0.5
	var reach := _reach(o)
	var region: int = o["region"]
	var r := _rng.randf_range(0.3, 0.42)
	var skew := _rng.randf_range(-1.2, 1.2)
	var outer := _at(o, side * (half + 1.6), skew)
	if _world.houses != null and _world.houses.is_blocked(outer.x, outer.z, 0.6):
		outer = _at(o, side * (half + 0.4), skew)
	var inner := _at(o, side * (half - reach), -skew * 0.3)
	var y := maxf(outer.y, inner.y)
	outer.y = y + r * 0.85
	inner.y = y + r * 0.85
	var bark := Color(0.30, 0.22, 0.15) if region == 2 else Color(0.52, 0.47, 0.40)
	var g := _geo(inner)
	g.tube(outer, inner, r * 1.08, r, 9, bark, Color(0.78, 0.64, 0.45))
	# Ramas rotas.
	for k in 2:
		var t := _rng.randf_range(0.2, 0.6)
		var root := outer.lerp(inner, t)
		var tip := root + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.3, 0.7), _rng.randf_range(-0.6, 0.6))
		g.tube(root, tip, r * 0.32, r * 0.18, 5, bark, bark.lightened(0.3))
	var crown := _at(o, side * (half + 3.2), skew * 1.6)
	if region == 2 and (_world.houses == null or not _world.houses.is_blocked(crown.x, crown.z, 2.0)):
		# La copa del árbol caído queda al costado, fuera de la vía.
		for k in 3:
			var c := crown + Vector3(_rng.randf_range(-1.0, 1.0), 0.6 + _rng.randf() * 0.5, _rng.randf_range(-1.0, 1.0))
			g.rock(c, Vector3(1.3, 0.7, 1.3) * _rng.randf_range(0.8, 1.2), Color(0.20, 0.36, 0.13), Color(0.36, 0.55, 0.20), _rng)
	var body := _body(o)
	var axis := inner - outer
	_cylinder(body, (outer + inner) * 0.5, r, axis.length(), axis)
	for k in 6:
		var q := outer.lerp(inner, (k + 0.5) / 6.0)
		_add_solid(q.x, q.z, r + 0.2)


func _make_works(o: Dictionary, side: float) -> void:
	var half: float = o["width"] * 0.5
	var reach := _reach(o)
	var body := _body(o)
	var n := maxi(2, int(reach / 0.75))
	for k in n:
		var lat := side * lerpf(half - 0.3, half - reach + 0.35, float(k) / maxf(n - 1, 1))
		var c := _at(o, lat, _rng.randf_range(-0.25, 0.25))
		_geo(c).barrel(c, 0.3, 0.9)
		_cylinder(body, c, 0.3, 0.9)
		_add_solid(c.x, c.z, 0.35)
	# Conos de aviso a ambos lados (la vía es de doble sentido); se pueden tumbar.
	for along in [-9.0, 9.0]:
		for k in 2:
			var c := _at(o, side * lerpf(half - 0.4, half - reach + 0.3, k), along * (1.0 + 0.15 * k))
			_add_cone(c)


func _make_puddle(o: Dictionary) -> void:
	var half: float = o["width"] * 0.5
	var region: int = o["region"]
	var water := Color(0.22, 0.17, 0.11) if region == 2 else Color(0.20, 0.22, 0.24)
	var mud := Color(0.36, 0.27, 0.17) if region == 2 else Color(0.40, 0.35, 0.29)
	var n := _rng.randi_range(1, 3)
	for k in n:
		var r := _rng.randf_range(1.1, 2.0)
		var c := _at(o, _rng.randf_range(-half + r * 0.5, half - r * 0.5), _rng.randf_range(-1.5, 1.5) * k)
		_geo(c, Layer.FLAT).flat_blob(_world, c, r * 1.3, 0.03, mud, Color(mud, 0.0), 0.0, _rng)
		_geo(c, Layer.WET).flat_blob(_world, c, r, 0.045, Color(water, 0.92), Color(water.lightened(0.1), 0.0), 0.0, _rng)
		_add_hazard(c.x, c.z, r * 1.05, HAZARD_SLOW)


func _make_sand(o: Dictionary, side: float) -> void:
	var half: float = o["width"] * 0.5
	var sand := Color(0.76, 0.66, 0.49)
	var cover: float = _rng.randf_range(0.55, 1.0) * float(o["width"])
	var n := maxi(2, int(cover / 1.6))
	var drift := _rng.randf_range(-0.5, 0.5)  # La lengua de arena cruza en diagonal.
	for k in n:
		var t := float(k) / maxf(n - 1, 1)
		var r := lerpf(2.4, 1.5, t) * _rng.randf_range(0.85, 1.15)
		var c := _at(o, side * lerpf(half + 0.8, half + 0.8 - cover, t), drift * t * cover)
		_geo(c, Layer.FLAT).flat_blob(_world, c, r, 0.02, sand.lightened(0.04), Color(sand, 0.0), lerpf(0.09, 0.05, t), _rng)
		_add_hazard(c.x, c.z, r * 0.9, HAZARD_SLOW)


func _make_potholes(o: Dictionary) -> void:
	var half: float = o["width"] * 0.5
	var n := _rng.randi_range(1, 3)
	for k in n:
		var r := _rng.randf_range(0.55, 0.95)
		var c := _at(o, _rng.randf_range(-half + 0.9, half - 0.9), _rng.randf_range(-2.0, 2.0) * k)
		_geo(c).pothole(_world, c, r, _rng)
		_add_hazard(c.x, c.z, r * 0.9, HAZARD_BUMP)


func _add_cone(c: Vector3) -> void:
	if _cone_mesh == null:
		var g := _Geo.new()
		g.cone()
		_cone_mesh = g.commit()
		_cone_mesh.surface_set_material(0, _material(Layer.SOLID))
	var body := RigidBody3D.new()
	body.name = "Cono%d" % get_child_count()
	body.mass = 3.0
	body.can_sleep = true
	body.sleeping = true
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.16
	cyl.height = 0.7
	shape.shape = cyl
	shape.position.y = 0.35
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh
	mi.visibility_range_end = VIEW_DISTANCE
	body.add_child(mi)
	body.position = c + Vector3.UP * 0.01
	body.rotation.y = _rng.randf() * TAU
	add_child(body)


# --- Mallas -------------------------------------------------------------------------

static var _materials := {}

static func _material(layer: int) -> StandardMaterial3D:
	if not _materials.has(layer):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.05 if layer == Layer.WET else 0.92
		m.metallic_specular = 0.9 if layer == Layer.WET else 0.3
		if layer != Layer.SOLID:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.render_priority = 1 if layer == Layer.WET else 0  # El agua encima del barro.
		_materials[layer] = m
	return _materials[layer]


func _commit_tiles() -> void:
	for key: Vector2i in _tiles:
		for layer in [Layer.SOLID, Layer.WET, Layer.FLAT]:
			var g: _Geo = _tiles[key][layer]
			if g.verts.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Malla_%d_%d_%s" % [key.x, key.y, ["solido", "agua", "suelo"][layer]]
			mi.mesh = g.commit()
			mi.mesh.surface_set_material(0, _material(layer))
			mi.visibility_range_end = VIEW_DISTANCE + TILE
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if layer == Layer.SOLID else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	_tiles.clear()


## Geometría con color por vértice (coordenadas del mundo).
class _Geo:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		verts.append_array([a, b, c])
		norms.append_array([na, nb, nc])
		cols.append_array([ca, cb, cc])

	func flat_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		if n.dot(outward) < 0.0:
			n = -n
		tri(a, b, c, n, n, n, color, color, color)

	## Piedra: esfera deformada, con normales suaves y la parte de arriba más clara.
	func rock(center: Vector3, radius: Vector3, color: Color, top: Color, rng: RandomNumberGenerator) -> void:
		var rings := 5
		var segs := 8
		var pts := []
		for i in rings + 1:
			var row := []
			var phi := PI * i / rings
			for j in segs:
				var theta := TAU * j / segs + (0.4 if i % 2 == 1 else 0.0)
				var jitter := rng.randf_range(0.78, 1.15) if i > 0 and i < rings else 1.0
				row.append(Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * jitter)
			pts.append(row)
		for i in rings:
			for j in segs:
				var j1 := (j + 1) % segs
				var q := [pts[i][j], pts[i + 1][j], pts[i][j1], pts[i][j1], pts[i + 1][j], pts[i + 1][j1]]
				for t in 2:
					var v: Array[Vector3] = []
					var n: Array[Vector3] = []
					var c: Array[Color] = []
					for s in 3:
						var d: Vector3 = q[t * 3 + s]
						v.append(center + d * radius)
						n.append((d / radius).normalized())
						c.append(color.darkened(0.25 * clampf(-d.y, 0.0, 1.0)).lerp(top, clampf(d.y, 0.0, 1.0) * 0.6))
					tri(v[0], v[1], v[2], n[0], n[1], n[2], c[0], c[1], c[2])

	## Cilindro de a hasta b con tapas de otro color (tronco: corteza y madera).
	func tube(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, color: Color, cap_color: Color) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var other := axis.cross(side)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := side * cos(a0) + other * sin(a0)
			var d1 := side * cos(a1) + other * sin(a1)
			var c := color if k % 2 == 0 else color.darkened(0.12)
			tri(a + d0 * r0, b + d0 * r1, a + d1 * r0, d0, d0, d1, c, c, c)
			tri(a + d1 * r0, b + d0 * r1, b + d1 * r1, d1, d0, d1, c, c, c)
			tri(a, a + d0 * r0, a + d1 * r0, -axis, -axis, -axis, cap_color.darkened(0.15), cap_color, cap_color)
			tri(b, b + d1 * r1, b + d0 * r1, axis, axis, axis, cap_color.darkened(0.15), cap_color, cap_color)

	## Barril de obra: franjas naranja y blanco.
	func barrel(base: Vector3, r: float, h: float) -> void:
		var bands := 5
		for k in bands:
			var c := Color(0.95, 0.42, 0.08) if k % 2 == 0 else Color(0.93, 0.93, 0.90)
			var a := base + Vector3.UP * h * k / bands
			var b := base + Vector3.UP * h * (k + 1) / bands
			tube(a, b, r, r, 12, c, Color(0.2, 0.2, 0.2) if k == bands - 1 else c)

	## Cono de tránsito en el origen (malla propia: los conos se mueven).
	func cone() -> void:
		var orange := Color(0.98, 0.38, 0.05)
		var white := Color(0.95, 0.95, 0.92)
		var dark := Color(0.12, 0.12, 0.12)
		var y := [0.04, 0.3, 0.42, 0.7]
		var r := [0.15, 0.1, 0.075, 0.02]
		for k in 3:
			tube(Vector3(0, y[k], 0), Vector3(0, y[k + 1], 0), r[k], r[k + 1], 10, white if k == 1 else orange, orange)
		var corners := [Vector3(-0.2, 0.0, -0.2), Vector3(0.2, 0.0, -0.2), Vector3(0.2, 0.0, 0.2), Vector3(-0.2, 0.0, 0.2)]
		for k in 4:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 4]
			flat_tri(a + Vector3.UP * 0.04, b + Vector3.UP * 0.04, Vector3.UP * 0.04, dark, Vector3.UP)
			flat_tri(a, b, b + Vector3.UP * 0.04, dark, (a + b).normalized())
			flat_tri(a, b + Vector3.UP * 0.04, a + Vector3.UP * 0.04, dark, (a + b).normalized())

	## Mancha que sigue el suelo (charco, barro, arena). dome > 0 la abomba en el centro.
	func flat_blob(world: TerrainWorld, center: Vector3, radius: float, lift: float, inner: Color, edge: Color, dome: float, rng: RandomNumberGenerator) -> void:
		var segs := 18
		var ring: Array[Vector3] = []
		var mid: Array[Vector3] = []
		for k in segs:
			var ang := TAU * k / segs
			var rr := radius * rng.randf_range(0.75, 1.1)
			var d := Vector3(cos(ang), 0.0, sin(ang))
			var p := center + d * rr
			var m := center + d * rr * 0.55
			ring.append(Vector3(p.x, world.get_height(p.x, p.z) + lift, p.z))
			mid.append(Vector3(m.x, world.get_height(m.x, m.z) + lift + dome * 0.7, m.z))
		var c := Vector3(center.x, world.get_height(center.x, center.z) + lift + dome, center.z)
		var up := world.get_normal(center.x, center.z)
		var mid_color := inner.lerp(edge, 0.5)
		for k in segs:
			var k1 := (k + 1) % segs
			if dome > 0.0:
				flat_tri(c, mid[k], mid[k1], inner, up)
				flat_tri(mid[k], ring[k], ring[k1], mid_color, up)
				flat_tri(mid[k], ring[k1], mid[k1], mid_color, up)
			else:
				tri(c, mid[k], mid[k1], up, up, up, inner, inner, inner)
				tri(mid[k], ring[k], ring[k1], up, up, up, inner, edge, edge)
				tri(mid[k], ring[k1], mid[k1], up, up, up, inner, edge, inner)

	## Bache: borde de asfalto roto y fondo oscuro que baja hacia el centro.
	func pothole(world: TerrainWorld, center: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
		var segs := 14
		var outer: Array[Vector3] = []
		var inner: Array[Vector3] = []
		var g := world.get_height(center.x, center.z)
		for k in segs:
			var ang := TAU * k / segs
			var rr := radius * rng.randf_range(0.8, 1.15)
			var d := Vector3(cos(ang), 0.0, sin(ang))
			var p := center + d * rr
			var q := center + d * rr * 0.7
			outer.append(Vector3(p.x, world.get_height(p.x, p.z) + 0.035, p.z))
			inner.append(Vector3(q.x, world.get_height(q.x, q.z) + 0.022, q.z))
		var c := Vector3(center.x, g + 0.012, center.z)
		var up := world.get_normal(center.x, center.z)
		var rim := Color(0.30, 0.29, 0.27)
		var wall := Color(0.13, 0.12, 0.11)
		var floor_color := Color(0.07, 0.065, 0.06)
		for k in segs:
			var k1 := (k + 1) % segs
			tri(outer[k], outer[k1], inner[k1], up, up, up, rim, rim, wall)
			tri(outer[k], inner[k1], inner[k], up, up, up, rim, wall, wall)
			tri(inner[k], inner[k1], c, up, up, up, wall, wall, floor_color)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
