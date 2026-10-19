extends SceneTree

func _initialize() -> void:
	var repeated_coasts := false
	var coast_jungle_contact := false
	var unequal_areas := false
	var records := []
	const SIDE := 97
	for seed_value in [68, 2026, 1337, 42]:
		var source := TerrainNoise.new()
		source.set_seed(seed_value)
		source.configure_regions({"extent": 768.0})
		var labels := PackedInt32Array()
		var counts := Vector3.ZERO
		var contacts := 0
		for z in range(SIDE):
			for x in range(SIDE):
				var w: Vector3 = source.get_biome_weights(x * 8.0 - 384, z * 8.0 - 384)
				var dominant := 0 if w.x > w.y and w.x > w.z else (1 if w.y > w.z else 2)
				labels.append(dominant)
				counts[dominant] += 1
				if w.x > 0.15 and w.z > 0.15 and w.y < 0.05: contacts += 1
		var visited := PackedByteArray()
		visited.resize(labels.size())
		var coasts := 0
		for start in range(labels.size()):
			if visited[start] or labels[start] != 0: continue
			var stack: Array[int] = [start]
			visited[start] = 1
			var size := 0
			while not stack.is_empty():
				var i: int = stack.pop_back()
				size += 1
				for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var x := i % SIDE + offset.x
					var z := i / SIDE + offset.y
					if x < 0 or z < 0 or x >= SIDE or z >= SIDE: continue
					var next := z * SIDE + x
					if not visited[next] and labels[next] == 0:
						visited[next] = 1
						stack.append(next)
			if size >= 6: coasts += 1
		var fractions := counts / float(SIDE * SIDE)
		repeated_coasts = repeated_coasts or coasts >= 2
		coast_jungle_contact = coast_jungle_contact or contacts > 0
		unequal_areas = unequal_areas or maxf(fractions.x, maxf(fractions.y, fractions.z)) - minf(fractions.x, minf(fractions.y, fractions.z)) > 0.10
		var record := {"seed": seed_value, "coast_components": coasts, "coast_jungle_transition_samples": contacts, "fractions": [fractions.x, fractions.y, fractions.z]}
		records.append(record)
		print(record)
	var success := repeated_coasts and coast_jungle_contact and unequal_areas
	if not success: push_error("Faltan costas separadas, contacto costa-selva o areas desiguales")
	var folder := ProjectSettings.globalize_path("res://../output/s11_cgb")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/layout_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": success, "samples_per_side": SIDE, "cases": records}, "\t"))
	print("Distribucion irregular: ", "correcta" if success else "fallida")
	quit(0 if success else 1)
