extends SceneTree
## Vegetación con modelos reales en el juego (terreno del editor):
## LOD por planta, troncos sólidos cerca de la mototaxi y daño al chocar un árbol.
##   Godot --headless --fixed-fps 60 --path project -s res://tests/test_vegetation.gd

var errors := 0


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		errors += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var moto: Mototaxi = main.moto
	var world: TerrainWorld = main.world
	moto.use_input = false
	main.race.stop()
	await _frames(20)

	print("-- Modelos")
	var veg := root.find_children("Vegetacion", "TerrainVegetation", true, false)
	_check(not veg.is_empty(), "hay vegetación")
	var tv: TerrainVegetation = veg[0]
	for sp in ["arbol_selva", "huarango", "palmera", "cactus", "arbusto", "ichu"]:
		_check(not VegetationModels.get_variants(sp).is_empty(), "%s usa modelo real (%d variantes)" % [sp, VegetationModels.get_variants(sp).size()])
	_check(VegetationModels.get_far_variants("arbusto").is_empty(), "arbustos sin versión lejana (se ven solo de cerca)")
	var far_tris: int = VegetationModels.get_far_variants("arbol_selva")[0].surface_get_array_index_len(0)
	var near_tris: int = VegetationModels.get_variants("arbol_selva")[0].surface_get_array_index_len(0)
	_check(far_tris < near_tris / 3, "la versión lejana tiene menos triángulos (%d vs %d índices)" % [far_tris, near_tris])
	_check(tv.near != null and tv.near.visible_count > 0, "árboles con modelo completo cerca de la cámara (%d)" % (tv.near.visible_count if tv.near else 0))
	var faded := 0
	for n in tv.find_children("*", "MultiMeshInstance3D", true, false):
		if (n as GeometryInstance3D).visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
			faded += 1
	_check(faded == 0, "sin desvanecido transparente (efecto fantasma)")

	print("-- Choque contra un árbol")
	var col := tv.colliders
	_check(col != null and col.trunk_count > 0, "troncos registrados para colisión (%d)" % (col.trunk_count if col else 0))
	# Tronco más cercano a la mototaxi que tenga terreno plano y despejado delante.
	var target := Vector3.INF
	var best := INF
	for cell in col._grid:
		var arr: PackedFloat32Array = col._grid[cell]
		for i in range(0, arr.size(), 5):
			var p := Vector3(arr[i], arr[i + 1], arr[i + 2])
			var d := p.distance_to(moto.global_position)
			if d < best and d > 30.0 and arr[i + 3] > 0.3:
				var back := p + (moto.global_position - p).normalized() * 14.0
				if absf(world.get_height(back.x, back.z) - p.y) < 1.0:
					best = d
					target = p
	_check(target != Vector3.INF, "hay un árbol de prueba a %.0f m" % best)
	var dir := (target - moto.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var start := target - dir * 14.0
	moto.place_at(Vector3(start.x, world.get_height(start.x, start.z), start.z), atan2(dir.x, dir.z))
	await _frames(40)  # se asienta y los troncos cercanos se vuelven sólidos
	var active := col.refresh(moto.global_position)
	_check(active > 0, "troncos sólidos alrededor (%d)" % active)
	var hp := moto.health
	moto.linear_velocity = dir * 12.0  # ~43 km/h
	await _frames(90)
	var hit := hp - moto.health
	var past := (moto.global_position - target).dot(dir)
	_check(hit > 3.0, "chocar el árbol a ~43 km/h hace daño (%.0f de vida)" % hit)
	_check(past < 0.5, "el tronco la detiene (no lo atraviesa: %.1f m)" % past)

	print("RESULTADO: " + ("OK" if errors == 0 else "%d fallas" % errors))
	quit(1 if errors else 0)
