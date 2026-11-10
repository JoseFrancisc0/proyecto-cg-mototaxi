extends SceneTree
## Prueba sin ventana de los animales en las vías (RoadAnimals, pendiente 10 fase 5):
## aparecen adelante y según la región, junto a la vía, lejos del destino; golpearlos resta vida y
## ánimo (una vez por animal, con gracia); la bocina los aparta; se quitan al alejarse; con
## densidad 0 no hay ninguno.
##   Godot_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_animales.gd -- [semilla] [costa|sierra|selva]
## Sin argumentos usa el terreno guardado (terrain_demo.tscn, casi todo selva).

var _fails := 0
var world: TerrainWorld
var moto: Mototaxi
var animals: RoadAnimals


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
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
	root.add_child(world)
	world.generate()

	moto = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	var race := RaceManager.new()
	race.world = world
	race.moto = moto
	root.add_child(race)
	animals = RoadAnimals.new()
	root.add_child(animals)
	animals.setup(world, moto, race, 1.8, world.world_seed)
	await _frames(2)
	race.start(1)
	print("  %d lugares posibles para animales" % animals._sites.size())
	_check(animals._sites.size() > 50, "hay lugares sobre las vías")

	print("-- Recorrido (la mototaxi avanza por las vías más largas)")
	var roads := world.get_roads()
	roads.sort_custom(func(a, b): return TerrainWorld.route_length(a["path"]) > TerrainWorld.route_length(b["path"]))
	var seen := {}            # especie -> cantidad
	var wrong_region := 0
	var off_road := 0
	var steep := 0
	var near_target := 0
	var behind := 0
	var max_groups := 0
	var max_animals := 0
	var counted := {}
	var t0 := Time.get_ticks_usec()
	var frames := 0
	for road in roads.slice(0, 6):
		var path: PackedVector3Array = road["path"]
		var acc := 0.0
		for i in range(1, path.size()):
			acc += path[i - 1].distance_to(path[i])
			if acc < 12.0:
				continue
			acc = 0.0
			var d := path[mini(i + 1, path.size() - 1)] - path[i - 1]
			moto.place_at(path[i], atan2(d.x, d.z))
			await _frames(20)
			frames += 20
			max_groups = maxi(max_groups, animals.groups.size())
			max_animals = maxi(max_animals, animals.get_animal_count())
			for g in animals.groups:
				var id: int = hash(g["site"]["p"])
				if counted.has(id):
					continue
				counted[id] = true
				var site: Dictionary = g["site"]
				seen[g["species"]] = seen.get(g["species"], 0) + 1
				var allowed: Array = RoadAnimals.REGION_SPECIES[site["region"]].map(func(o): return o[0])
				if not allowed.has(g["species"]):
					wrong_region += 1
				var target := race.get_target()
				if target != Vector3.INF and Vector2(site["p"].x - target.x, site["p"].z - target.z).length() < RoadAnimals.STOP_CLEARANCE:
					near_target += 1
				var to: Vector3 = site["p"] - moto.global_position
				if to.dot(moto.global_basis.z) < -5.0 and to.length() < RoadAnimals.SPAWN_MIN:
					behind += 1
				for a: Dictionary in g["animals"]:
					var p: Vector3 = a["node"].global_position
					if Vector2(p.x - site["p"].x, p.z - site["p"].z).length() > site["width"] * 0.5 + 9.0:
						off_road += 1
					# Fuera de la calzada (bajo la vía el relieve puede quedar inclinado en un corte).
					if world.get_offroad_amount(p.x, p.z) > 0.5 and world.get_normal(p.x, p.z).y < 0.8:
						steep += 1
						if OS.get_environment("DEBUG_ANIMALES") != "":
							var sd := Vector3(site["dir"].z, 0, -site["dir"].x)
							print("    empinado: %s modo %d lat %.1f (media vía %.1f) n.y %.2f vía tipo %d off %.2f" % [g["species"], g["mode"], (p - site["p"]).dot(sd), site["width"] * 0.5, world.get_normal(p.x, p.z).y, site["kind"], world.get_offroad_amount(p.x, p.z)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1)
	print("  especies vistas: %s · máx. %d grupos, %d animales a la vez" % [seen, max_groups, max_animals])
	_check(counted.size() >= 4, "aparecen grupos al recorrer (%d)" % counted.size())
	_check(wrong_region == 0, "cada especie en su región (%d fuera)" % wrong_region)
	_check(off_road == 0, "aparecen junto a la vía (%d lejos)" % off_road)
	_check(steep == 0, "ninguno parado en una ladera empinada fuera de la vía (%d)" % steep)
	_check(near_target == 0, "no aparecen junto al pasajero o el destino (%d)" % near_target)
	_check(max_groups <= ceili(RoadAnimals.BASE_GROUPS * 1.8), "no pasan del máximo de grupos (%d)" % max_groups)
	print("  %.2f ms por paso de física con los animales (incluye la física de la mototaxi)" % ms)

	print("-- Golpe")
	var road0: PackedVector3Array = roads[0]["path"]
	var k := road0.size() / 2
	var fwd := (road0[k + 1] - road0[k - 1]).normalized()
	moto.place_at(road0[k], atan2(fwd.x, fwd.z))
	await _frames(5)
	animals.clear_all()
	var site := {"p": road0[k] + fwd * 3.0, "dir": Vector3(fwd.x, 0, fwd.z).normalized(), "width": 6.0, "kind": 1, "region": 1}
	animals._spawn_group(site)
	var g: Dictionary = animals.groups[0]
	var a: Dictionary = g["animals"][0]
	a["node"].global_position = moto.global_position
	moto.repair()
	var hp := moto.health
	var said: Array = []
	race.passenger_said.connect(func(t): said.append(t))
	race.state = RaceManager.State.CON_PASAJERO
	var comfort: float = race._comfort
	moto.linear_velocity = moto.global_basis.z * (30.0 / 3.6)
	animals._check_hit(g, a, 30.0)
	_check(moto.health < hp, "golpear un(a) %s a 30 km/h quita %.1f de vida" % [g["species"], hp - moto.health])
	_check(race._comfort < comfort and not said.is_empty(), "el pasajero se enoja: \"%s\"" % (said[0] if said else ""))
	_check(a["fleeing"], "el animal huye")
	var hp2 := moto.health
	animals._check_hit(g, a, 30.0)
	_check(is_equal_approx(moto.health, hp2), "el mismo animal no golpea dos veces")
	if g["animals"].size() > 1:
		var b: Dictionary = g["animals"][1]
		b["node"].global_position = moto.global_position
		animals._check_hit(g, b, 30.0)
		_check(is_equal_approx(moto.health, hp2), "tiempo de gracia entre golpes")
	race.state = RaceManager.State.LIBRE

	print("-- Bocina")
	animals.clear_all()
	site["p"] = road0[k] + fwd * 14.0
	var tries := 0
	while tries < 30:
		animals.clear_all()
		animals._spawn_group(site)
		if animals.groups[0]["mode"] == RoadAnimals.Mode.ALONG:
			break
		tries += 1
	g = animals.groups[0]
	_check(g["mode"] == RoadAnimals.Mode.ALONG, "hay un grupo caminando por la vía")
	moto.honk()
	_check(g["mode"] == RoadAnimals.Mode.ASIDE, "la bocina los aparta")
	await _frames(240)
	var on_road := 0
	for an: Dictionary in g["animals"]:
		var p: Vector3 = an["node"].global_position
		var lat := absf((p - site["p"]).dot(Vector3(site["dir"].z, 0, -site["dir"].x)))
		if lat < site["width"] * 0.5 - 0.6:  # En la berma vale (si los dos costados son ladera).
			on_road += 1
			print("    en el carril: %s lat %.2f media %.2f ok %s blanco %s hit %s huye %s" % [an["species"], lat, site["width"] * 0.5, g["ok"], an["target"], an["hit"], an["fleeing"]])
	_check(on_road == 0, "a los 4 s ya no están en el carril (%d siguen)" % on_road)

	print("-- Se quitan lejos y se reusan")
	var pooled_before := 0
	for s in animals._pool:
		pooled_before += animals._pool[s].size()
	var far: Vector3 = roads[0]["path"][0] if road0[k].distance_to(roads[0]["path"][0]) > 400.0 else roads[0]["path"][-1]
	moto.place_at(far, 0.0)
	await _frames(3)
	_check(animals.groups.filter(func(gr): return gr["site"]["p"].distance_to(site["p"]) < 1.0).is_empty(), "el grupo lejano se quitó")
	var pooled := 0
	for s in animals._pool:
		pooled += animals._pool[s].size()
	_check(pooled >= pooled_before, "los modelos vuelven al pozo (%d)" % pooled)

	print("-- Sin animales")
	animals.setup(world, moto, race, 0.0, world.world_seed)
	await _frames(120)
	_check(animals.get_animal_count() == 0, "densidad 0: ninguno")

	print("RESULTADO: ", "OK" if _fails == 0 else "%d fallos" % _fails)
	quit(_fails)
