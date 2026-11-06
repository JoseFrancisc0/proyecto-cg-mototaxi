extends SceneTree
## Prueba sin ventana de los nombres de las paradas (StopNames): por región, sin repetir,
## iguales con la misma semilla y con su cartel:
##   Godot_console.exe --headless --path project -s res://tests/test_paradas.gd

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("  ", "OK   " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


## El nombre corresponde a la plantilla de su tipo y a un nombre propio de su región.
func _matches_region(lm: Dictionary) -> bool:
	var template: String = StopNames.TEMPLATES[lm["kind"]][lm["region"]]
	var prefix := template.trim_suffix("%s")
	var label: String = lm["label"]
	if not label.begins_with(prefix):
		return false
	return label.substr(prefix.length()) in StopNames.NAMES[lm["region"]]


func _initialize() -> void:
	var world: TerrainWorld = load("res://scripts/terrain_world.gd").new()
	world.generate_on_ready = false
	world.use_editor_scene = true
	root.add_child(world)
	world.generate()
	var lms := world.get_landmarks()

	print("-- Paradas con nombre")
	var named := lms.filter(func(lm): return not str(lm.get("label", "")).is_empty())
	var labels := {}
	var kinds := {}
	var regions := {}
	for lm in named:
		labels[lm["label"]] = true
		kinds[lm["kind"]] = kinds.get(lm["kind"], 0) + 1
		regions[StopNames.REGIONS[lm["region"]]] = regions.get(StopNames.REGIONS[lm["region"]], 0) + 1
	print("  %d de %d paradas con nombre · tipos %s · regiones %s" % [named.size(), lms.size(), kinds, regions])
	for lm in named.slice(0, 12):
		print("    ", lm["label"], "  (", lm["kind"], ", ", StopNames.REGIONS[lm["region"]], ")")
	_check(named.size() >= 12, "hay bastantes paradas con nombre (%d)" % named.size())
	_check(labels.size() == named.size(), "ningún nombre se repite")
	_check(lms.all(func(lm): return lm.has("kind") and lm.has("region")), "todas las paradas tienen tipo y región")
	_check(lms.filter(func(lm): return lm["type"] == "pueblo").all(func(lm): return lm["kind"] in ["plaza", "mercado"]),
		"los pueblos son plaza o mercado")
	_check(named.all(_matches_region), "cada nombre es de la región donde está")
	var spaced := true
	var roadside := named.filter(func(lm): return lm["type"] == "via")
	for a in roadside:
		for b in named:
			if a != b and Vector2(a["position"].x - b["position"].x, a["position"].z - b["position"].z).length() < 220.0:
				spaced = false
	_check(spaced and roadside.size() > 0, "las paradas de vía con nombre están separadas (%d)" % roadside.size())

	print("-- Misma semilla, mismos nombres; otra semilla, otros")
	var copy: Array[Dictionary] = []
	for lm in lms:
		var c: Dictionary = lm.duplicate()
		c.erase("label")
		copy.append(c)
	var region_of := func(q: Vector3) -> int: return world.get_biome(q.x, q.z).max_axis_index()
	StopNames.assign(copy, world.world_seed, region_of)
	var same := true
	for i in lms.size():
		if str(lms[i].get("label", "")) != str(copy[i].get("label", "")):
			same = false
	_check(same, "con la semilla %d salen los mismos nombres" % world.world_seed)
	StopNames.assign(copy, world.world_seed + 1, region_of)
	var differ := 0
	for i in lms.size():
		if str(lms[i].get("label", "")) != str(copy[i].get("label", "")):
			differ += 1
	_check(differ > named.size() / 2, "con otra semilla cambian (%d diferentes)" % differ)

	print("-- Carteles")
	var signs := world.get_node_or_null("Carteles")
	var count := signs.get_child_count() if signs else 0
	_check(count >= named.size() - 2, "%d carteles para %d paradas con nombre" % [count, named.size()])
	var on_road := 0
	if signs:
		for s: Node3D in signs.get_children():
			if world.get_offroad_amount(s.position.x, s.position.z) < 0.5:
				on_road += 1
	_check(on_road == 0, "ningún cartel sobre la calzada (%d)" % on_road)

	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d fallos" % _fails))
	quit(0 if _fails == 0 else 1)
