class_name TerrainHouses
extends Node3D
## Viviendas del mapa según la región (pendiente 10, fase 4): que se note que vive gente.
##   Pueblos: casas en fila a los dos lados de las calles (kind 3), frente a la vía.
##   Cerca del pueblo: casas más separadas en avenidas y carreteras.
##   Campo: alguna casa suelta junto a las carreteras y trochas, y la casa de la chacra al final de
##   cada trocha sin salida.
## Modelos importados (assets/houses, ver SOURCE.md), escalados a un tamaño real. Cada casa es sólida
## (una caja de colisión) y se apoya en el suelo: si el terreno baja, un zócalo de piedra la sostiene
## (no flota). Nunca sobre una vía, un río, una parada, un cartel u otra casa; quita los árboles de
## adentro (TerrainVegetation). Todo sale de la semilla del mundo: mismo mapa, mismas casas.

const DIR := "res://assets/houses/"
## file, region (0 costa, 1 sierra, 2 selva), height (alto real en m), yaw (giro para que la puerta
## mire hacia +Z).
const MODELS := [
	{"file": "costa_casa_1.glb", "region": 0, "height": 6.5, "yaw": 0.0},
	{"file": "costa_casa_2.glb", "region": 0, "height": 6.5, "yaw": 0.0},
	{"file": "costa_casa_3.glb", "region": 0, "height": 6.0, "yaw": PI},
	{"file": "sierra_casa_1.glb", "region": 1, "height": 6.0, "yaw": 0.0},
	{"file": "sierra_casa_2.glb", "region": 1, "height": 5.0, "yaw": 0.0},
	{"file": "sierra_casa_3.glb", "region": 1, "height": 7.0, "yaw": 0.0},
	{"file": "sierra_casa_4.glb", "region": 1, "height": 5.5, "yaw": 0.0},
	{"file": "selva_casa_1.glb", "region": 2, "height": 3.8, "yaw": 0.0},
	{"file": "selva_casa_2.glb", "region": 2, "height": 4.2, "yaw": 0.0},
	{"file": "selva_casa_3.glb", "region": 2, "height": 5.5, "yaw": 0.0},
	{"file": "selva_casa_4.glb", "region": 2, "height": 6.5, "yaw": 0.0},
]

const SETBACK := 1.5          ## Distancia (m) del borde de la vía al frente de la casa.
const MAX_STEP := 1.4         ## Desnivel máximo del suelo bajo una casa.
const STOP_CLEARANCE := 4.0   ## Distancia mínima a una parada (el pasajero espera ahí).
const SIGN_CLEARANCE := 2.5
const GRID := 32.0
const TILE := 256.0           ## Las casas se dibujan por baldosas (MultiMesh) para poder recortarlas.
const VIEW_DISTANCE := 900.0
const TOWN_RADIUS := 260.0    ## Radio alrededor de un pueblo con casas en avenidas y carreteras.

## [{ "model", "region", "position" (centro en el suelo), "yaw", "size" (ancho, alto, fondo), "zone" }]
## zone: "pueblo" (calles), "afueras" (cerca del pueblo), "campo", "chacra".
var houses: Array[Dictionary] = []
var counts := {}             ## región -> cantidad
var _grid := {}              # Vector2i -> índices de houses
var _rng := RandomNumberGenerator.new()
var _world: TerrainWorld
var _models: Array[Dictionary] = []
var _stops: Array[Vector3] = []
var _signs: Array[Vector3] = []
var _catchment := 60000.0

static var _cache := {}


## Carga un modelo: { "parts": [[Mesh, Transform3D], ...] escaladas al alto real, centradas y
## apoyadas en y = 0, "size": Vector3 }.
static func load_model(model: Dictionary) -> Dictionary:
	if _cache.has(model["file"]):
		return _cache[model["file"]]
	var scene: PackedScene = load(DIR + model["file"])
	var root := scene.instantiate()
	var raw: Array = []
	_collect(root, Transform3D.IDENTITY, raw)
	root.free()
	var box := AABB()
	var first := true
	for part: Array in raw:
		var b: AABB = part[1] * (part[0] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s: float = model["height"] / maxf(box.size.y, 0.001)
	var center := box.get_center()
	var fix := Transform3D(Basis(Vector3.UP, model["yaw"]).scaled(Vector3.ONE * s), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -Vector3(center.x, box.position.y, center.z))
	var parts: Array = []
	for part: Array in raw:
		parts.append([part[0], fix * part[1]])
	var size := (Basis(Vector3.UP, model["yaw"]).get_rotation_quaternion() * (box.size * s)).abs()
	var info := {"parts": parts, "size": Vector3(size.x, model["height"], size.z)}
	_cache[model["file"]] = info
	return info


static func _collect(node: Node, xf: Transform3D, out: Array) -> void:
	var t := xf * (node as Node3D).transform if node is Node3D else xf
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([(node as MeshInstance3D).mesh, t])
	for c in node.get_children():
		_collect(c, t, out)


func clear() -> void:
	houses.clear()
	counts.clear()
	_grid.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()  # Diferido: puede haber cuerpos en medio de un paso de física.


## Reparte las casas sobre el mapa de world.
func build(world: TerrainWorld, world_seed: int, density := 1.0) -> void:
	clear()
	if density <= 0.0:
		return
	_world = world
	_rng.seed = hash("casas-%d" % world_seed)
	_models.clear()
	for m in MODELS:
		var info := load_model(m)
		_models.append({"model": m, "size": info["size"]})
	_stops.clear()
	for lm in world.get_landmarks():
		_stops.append(lm["position"])
	_signs = world.get_sign_positions()
	if world.generator != null and world.generator.get("river_catchment") != null:
		_catchment = float(world.generator.get("river_catchment"))
	var towns := world.get_town_centers()
	var near_town := func(p: Vector3) -> bool:
		for t in towns:
			if Vector2(p.x - t.x, p.z - t.z).length() < TOWN_RADIUS:
				return true
		return false
	var roads := world.get_roads()
	# Primero las calles del pueblo (fila continua), luego afueras y campo.
	for road in roads:
		if road["kind"] == 3:
			_line(road, "pueblo", Vector2(0.4, 2.5) / density, near_town)
	for road in roads:
		if road["kind"] == 1 or road["kind"] == 2:
			_line(road, "afueras", Vector2(6.0, 22.0) / density, near_town)
			_line(road, "campo", Vector2(140.0, 420.0) / density, near_town)
		elif road["kind"] == 0:
			_line(road, "campo", Vector2(90.0, 260.0) / density, near_town)
			_farm(road)
	_commit()


## Casas a los dos lados de una vía, separadas por gap (m, rango al azar).
func _line(road: Dictionary, zone: String, gap: Vector2, near_town: Callable) -> void:
	var path: PackedVector3Array = road["path"]
	var half: float = road["width"] * 0.5
	for side in [-1.0, 1.0]:
		var next := _rng.randf_range(0.0, gap.y) if zone != "pueblo" else _rng.randf_range(0.0, 3.0)
		var acc := 0.0
		for i in range(1, path.size()):
			acc += path[i - 1].distance_to(path[i])
			if acc < next:
				continue
			var p := path[i]
			var in_town: bool = near_town.call(p)
			if (zone == "afueras" and not in_town) or (zone == "campo" and in_town):
				continue
			var placed := _try_house(path, i, side, half, zone)
			if placed.is_empty():
				next = acc + 3.0  # Prueba un poco más allá.
				continue
			acc = 0.0
			var along: float = placed["size"].x
			next = along * 0.5 + _rng.randf_range(gap.x, gap.y) + along * 0.5


## La casa de la chacra al final de una trocha sin salida.
func _farm(road: Dictionary) -> void:
	var path: PackedVector3Array = road["path"]
	if path.size() < 4:
		return
	for i in [path.size() - 2, 1]:
		if _world.get_offroad_amount(path[i].x, path[i].z) < 0.5 and not _try_house(path, i, 1.0 if _rng.randf() < 0.5 else -1.0, road["width"] * 0.5, "chacra").is_empty():
			return


func _try_house(path: PackedVector3Array, i: int, side: float, half: float, zone: String) -> Dictionary:
	var p := path[i]
	var a := path[maxi(i - 2, 0)]
	var b := path[mini(i + 2, path.size() - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < 0.5:
		return {}
	dir = dir.normalized()
	var out := Vector3(-dir.z, 0.0, dir.x) * side  # Hacia afuera de la vía.
	var region := _world.get_biome(p.x, p.z).max_axis_index()
	var choices := _models.filter(func(m): return m["model"]["region"] == region)
	if choices.is_empty():
		return {}
	var m: Dictionary = choices[_rng.randi() % choices.size()]
	var size: Vector3 = m["size"]
	# El frente (+Z del modelo) mira a la vía: el ancho va a lo largo de la vía.
	var center := p + out * (half + SETBACK + size.z * 0.5 + _rng.randf_range(0.0, 1.0 if zone == "pueblo" else 4.0))
	var yaw := atan2(-out.x, -out.z)
	if _world.get_biome(center.x, center.z).max_axis_index() != region:
		return {}  # En el borde entre regiones.
	var ground := _fits(center, yaw, size)
	if is_nan(ground):
		return {}
	var h := {"model": _models.find(m), "region": region, "position": Vector3(center.x, ground, center.z),
		"yaw": yaw, "size": size, "zone": zone, "radius": Vector2(size.x, size.z).length() * 0.5}
	_add(h)
	return h


## Altura del piso de la casa (lo más alto del suelo bajo ella: nada queda enterrado; el zócalo
## cubre el desnivel) o NAN si no cabe ahí.
func _fits(center: Vector3, yaw: float, size: Vector3) -> float:
	if not _world.is_inside(center.x, center.z):
		return NAN
	var basis := Basis(Vector3.UP, yaw)
	# Descarte rápido: centro y esquinas libres.
	for c: Vector3 in [Vector3.ZERO, Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		var q := center + basis * (c * Vector3(size.x, 0.0, size.z))
		if not _world.is_inside(q.x, q.z) or _world.get_offroad_amount(q.x, q.z) < 0.99 or _world.get_reach_id(q.x, q.z) < 0:
			return NAN
	var radius := Vector2(size.x, size.z).length() * 0.5
	var mine := _corners(center, yaw, size, 0.5)
	for k in _near(center, radius + 12.0):
		var o: Dictionary = houses[k]
		var reach: float = radius + o["radius"] + 1.0
		if Vector2(o["position"].x - center.x, o["position"].z - center.z).length_squared() > reach * reach:
			continue
		if not Geometry2D.intersect_polygons(mine, _corners(o["position"], o["yaw"], o["size"], 0.5)).is_empty():
			return NAN
	var lo := INF
	var hi := -INF
	var margin := 0.6
	for ix in 4:
		for iz in 4:
			var local := Vector3((ix / 3.0 - 0.5) * (size.x + margin), 0.0, (iz / 3.0 - 0.5) * (size.z + margin))
			var q := center + basis * local
			if not _world.is_inside(q.x, q.z) or _world.get_offroad_amount(q.x, q.z) < 0.99:
				return NAN
			if _world.get_reach_id(q.x, q.z) < 0:
				return NAN
			var y := _world.get_height(q.x, q.z)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo > MAX_STEP:
		return NAN
	# Lejos del agua: los cauces son angostos, se revisa más tupido y con 3 m de margen.
	for ix in 5:
		for iz in 5:
			var q := center + basis * Vector3((ix / 4.0 - 0.5) * (size.x + 6.0), 0.0, (iz / 4.0 - 0.5) * (size.z + 6.0))
			if _world.get_drainage(q.x, q.z) >= _catchment * 0.3:
				return NAN
	lo = hi
	for s in _stops:
		if Vector2(s.x - center.x, s.z - center.z).length() < radius + STOP_CLEARANCE:
			# Solo si la parada cae de verdad cerca del rectángulo (no de su círculo).
			if _rect_distance(center, yaw, size, s) < STOP_CLEARANCE:
				return NAN
	for s in _signs:
		if _rect_distance(center, yaw, size, s) < SIGN_CLEARANCE:
			return NAN
	return lo + 0.08


func _rect_distance(center: Vector3, yaw: float, size: Vector3, q: Vector3) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * Vector3(q.x - center.x, 0.0, q.z - center.z)
	var dx := maxf(absf(local.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - size.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


static func _corners(center: Vector3, yaw: float, size: Vector3, grow := 0.0) -> PackedVector2Array:
	var basis := Basis(Vector3.UP, yaw)
	var out := PackedVector2Array()
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := center + basis * Vector3(c.x * (size.x * 0.5 + grow), 0.0, c.y * (size.z * 0.5 + grow))
		out.append(Vector2(q.x, q.z))
	return out


func _add(h: Dictionary) -> void:
	var k := houses.size()
	houses.append(h)
	counts[StopNames.REGIONS[h["region"]]] = counts.get(StopNames.REGIONS[h["region"]], 0) + 1
	var key := Vector2i(floori(h["position"].x / GRID), floori(h["position"].z / GRID))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(k)


## Índices de casas con centro a menos de r de p (aprox., por celdas).
func _near(p: Vector3, r: float) -> Array:
	var out := []
	var n := ceili(r / GRID)
	var c0 := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			out.append_array(_grid.get(c0 + Vector2i(dx, dz), []))
	return out


## true si el punto (x, z) cae dentro de una casa (agrandada en grow m).
func is_blocked(x: float, z: float, grow := 0.0) -> bool:
	var q := Vector3(x, 0.0, z)
	for k in _near(q, 20.0):
		var h: Dictionary = houses[k]
		if _rect_distance(h["position"], h["yaw"], h["size"], q) <= grow:
			return true
	return false


## Círculos [x, z, radio] que cubren cada casa (para quitar los árboles de adentro).
func blockers() -> Array:
	var out := []
	for h in houses:
		out.append([h["position"].x, h["position"].z, Vector2(h["size"].x, h["size"].z).length() * 0.5 + 1.0])
	return out


# --- Dibujo y colisión ----------------------------------------------------------------

const PLINTH_COLOR := Color(0.46, 0.43, 0.39)

func _commit() -> void:
	# Por baldosa y por pieza de modelo: un MultiMesh con todas las casas de ese modelo.
	var tiles := {}  # Vector2i -> { [modelo, pieza]: Array[Transform3D] }
	var plinths := {}  # Vector2i -> Array[Transform3D] (cajas unitarias)
	var bodies := Node3D.new()
	bodies.name = "Colision"
	add_child(bodies)
	for h in houses:
		var key := Vector2i(floori(h["position"].x / TILE), floori(h["position"].z / TILE))
		if not tiles.has(key):
			tiles[key] = {}
			plinths[key] = []
		var xf := Transform3D(Basis(Vector3.UP, h["yaw"]), h["position"])
		var info := load_model(_models[h["model"]]["model"])
		for k in info["parts"].size():
			var id := Vector2i(h["model"], k)
			if not tiles[key].has(id):
				tiles[key][id] = []
			tiles[key][id].append(xf * (info["parts"][k][1] as Transform3D))
		var size: Vector3 = h["size"]
		# Zócalo de piedra desde 0.3 m bajo el punto más bajo hasta el piso de la casa.
		var drop: float = h["position"].y - _lowest_under(h) + 0.3
		var plinth_h := maxf(drop, 0.0) + 0.25
		plinths[key].append(Transform3D(Basis(Vector3.UP, h["yaw"]) * Basis.from_scale(Vector3(size.x + 0.2, plinth_h, size.z + 0.2)),
			h["position"] + Vector3.UP * (0.12 - plinth_h * 0.5)))
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x * 0.92, size.y, size.z * 0.92)
		shape.shape = box
		body.transform = xf
		shape.position.y = size.y * 0.5
		body.add_child(shape)
		bodies.add_child(body)
	var plinth_mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLINTH_COLOR
	mat.roughness = 0.95
	plinth_mesh.material = mat
	for key: Vector2i in tiles:
		for id: Vector2i in tiles[key]:
			var part: Array = load_model(_models[id.x]["model"])["parts"][id.y]
			_multimesh("Casas_%d_%d_%d_%d" % [key.x, key.y, id.x, id.y], part[0], tiles[key][id])
		_multimesh("Zocalos_%d_%d" % [key.x, key.y], plinth_mesh, plinths[key])


## Altura más baja del suelo bajo una casa (esquinas y centro).
func _lowest_under(h: Dictionary) -> float:
	var lo: float = h["position"].y
	for c in _corners(h["position"], h["yaw"], h["size"], 0.1):
		lo = minf(lo, _world.get_height(c.x, c.y))
	return lo


func _multimesh(node_name: String, mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_end = VIEW_DISTANCE
	mmi.visibility_range_end_margin = 40.0
	add_child(mmi)
