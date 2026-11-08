extends SceneTree
## Prueba sin ventana de las viviendas (TerrainHouses, pendiente 10 fase 4): modelos de su región,
## nunca sobre una vía, un río, una parada u otra casa; apoyadas en el suelo; sólidas; sin árboles
## adentro; iguales con la misma semilla.
##   Godot_console.exe --headless --fixed-fps 60 --path project -s res://tests/test_viviendas.gd -- [semilla] [costa|sierra|selva]

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
	root.add_child(world)
	world.generate()
	var hs := world.houses
	var list := hs.houses

	print("-- Reparto")
	var zones := {}
	for h in list:
		zones[h["zone"]] = zones.get(h["zone"], 0) + 1
	print("  %d viviendas · por región %s · por zona %s" % [list.size(), hs.counts, zones])
	_check(list.size() >= 40, "hay bastantes viviendas (%d)" % list.size())
	_check(zones.get("pueblo", 0) > zones.get("campo", 0), "la mayoría está en los pueblos")
	_check(list.all(func(h): return TerrainHouses.MODELS[h["model"]]["region"] == h["region"]), "cada casa usa un modelo de su región")
	_check(list.all(func(h): return world.get_biome(h["position"].x, h["position"].z).max_axis_index() == h["region"]), "y está en esa región")

	print("-- Lugares")
	var on_road := 0
	var wet := 0
	var catchment := float(world.generator.get("river_catchment")) if world.generator.get("river_catchment") != null else 60000.0
	var buried := 0
	var floating := 0
	for h in list:
		for c in TerrainHouses._corners(h["position"], h["yaw"], h["size"]):
			if world.get_offroad_amount(c.x, c.y) < 0.99:
				on_road += 1
			if world.get_drainage(c.x, c.y) >= catchment * 0.3:
				wet += 1
			var g := world.get_height(c.x, c.y)
			if g > h["position"].y + 0.05:
				buried += 1
			if h["position"].y - g > TerrainHouses.MAX_STEP + 0.15:
				floating += 1
	_check(on_road == 0, "ninguna esquina sobre una vía (%d)" % on_road)
	_check(wet == 0, "ninguna sobre un río (%d)" % wet)
	_check(buried == 0, "ninguna enterrada (%d esquinas bajo el suelo)" % buried)
	_check(floating == 0, "ninguna con más desnivel que el zócalo (%d)" % floating)
	var near_stop := 0
	for h in list:
		for lm in world.get_landmarks():
			if hs._rect_distance(h["position"], h["yaw"], h["size"], lm["position"]) < TerrainHouses.STOP_CLEARANCE - 0.01:
				near_stop += 1
	_check(near_stop == 0, "ninguna encima de una parada (%d)" % near_stop)
	var overlaps := 0
	for i in list.size():
		for j in hs._near(list[i]["position"], 30.0):
			if j > i and not Geometry2D.intersect_polygons(
					TerrainHouses._corners(list[i]["position"], list[i]["yaw"], list[i]["size"]),
					TerrainHouses._corners(list[j]["position"], list[j]["yaw"], list[j]["size"])).is_empty():
				overlaps += 1
	_check(overlaps == 0, "ninguna se cruza con otra (%d)" % overlaps)

	print("-- Sólidas y sin árboles adentro")
	var bodies := hs.get_node("Colision").get_child_count()
	_check(bodies == list.size(), "una colisión por casa (%d de %d)" % [bodies, list.size()])
	var trees_inside := 0
	var veg: TerrainVegetation = world.generator.vegetation
	if veg != null and veg.colliders != null:
		for arr: PackedFloat32Array in veg.colliders.trunk_cells():
			for i in range(0, arr.size(), 5):
				if hs.is_blocked(arr[i], arr[i + 2]):
					trees_inside += 1
	_check(trees_inside == 0, "ningún tronco dentro de una casa (%d)" % trees_inside)

	print("-- Misma semilla, mismas casas")
	var before := list.map(func(h): return [h["model"], h["position"]])
	var t := Time.get_ticks_msec()
	world._build_houses()
	print("  construir las viviendas: %d ms" % (Time.get_ticks_msec() - t))
	var after := world.houses.houses.map(func(h): return [h["model"], h["position"]])
	_check(before == after, "se repiten (%d = %d)" % [before.size(), after.size()])

	print("-- Chocar una casa")
	var moto: Mototaxi = load("res://scenes/mototaxi.tscn").instantiate()
	moto.use_input = false
	moto.terrain = world
	root.add_child(moto)
	await physics_frame
	var h: Dictionary = world.houses.houses[0]
	var front := Basis(Vector3.UP, h["yaw"]) * Vector3.BACK  # Hacia la vía.
	var start: Vector3 = h["position"] + front * (h["size"].z * 0.5 + 9.0)
	moto.place_at(Vector3(start.x, world.get_height(start.x, start.z), start.z), atan2(-front.x, -front.z))
	for k in 70:
		await physics_frame
	moto.linear_velocity = moto.global_basis.z * 10.0
	moto._prev_velocity = moto.linear_velocity
	moto.throttle = 0.4
	for k in 150:
		await physics_frame
	var inside := hs.is_blocked(moto.global_position.x, moto.global_position.z, -0.3)
	_check(not inside, "la mototaxi no atraviesa la casa")
	_check(moto.health < moto.max_health, "chocarla a 36 km/h hace daño (vida %.0f)" % moto.health)

	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallas" % _fails))
	quit(0 if _fails == 0 else 1)
