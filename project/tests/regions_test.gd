extends SceneTree

var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var source := TerrainNoise.new()
	source.set_seed(68)
	var legacy: float = source.get_height(123.0, -72.0)
	source.configure_regions({"enabled": true, "extent": 768.0})
	var heights := PackedFloat32Array()
	var weights: Array[Vector3] = []
	var counts := Vector3.ZERO
	var side := 97
	for z in range(side):
		for x in range(side):
			var wx := x * 8.0 - 384.0
			var wz := z * 8.0 - 384.0
			var w: Vector3 = source.get_biome_weights(wx, wz)
			var h: float = source.get_height(wx, wz)
			check(w.is_finite() and minf(w.x, minf(w.y, w.z)) >= -0.00001 and is_equal_approx(w.x + w.y + w.z, 1.0), "Pesos regionales validos")
			check(is_finite(h), "Alturas finitas")
			check(source.get_hardness(wx, wz) >= 0 and source.get_hardness(wx, wz) <= 1, "Dureza en [0,1]")
			check(source.get_critical_slope(wx, wz) > 0, "Pendiente critica positiva")
			check(absf(h - source.get_height(wx + 0.0001, wz)) < 0.1, "Sin saltos en las transiciones")
			if w.x > 0.8: counts.x += 1
			if w.y > 0.8: counts.y += 1
			if w.z > 0.8: counts.z += 1
			heights.append(h)
			weights.append(w)
	check(counts.x > 50 and counts.y > 50 and counts.z > 50, "Las tres regiones deben estar presentes")
	var peaks := 0
	for z in range(1, side - 1):
		for x in range(1, side - 1):
			var i := z * side + x
			if weights[i].y < 0.7: continue
			var peak := true
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if (dx != 0 or dz != 0) and heights[i] <= heights[i + dz * side + dx]: peak = false
			if peak: peaks += 1
	check(peaks > 1, "La sierra debe conservar multiples picos, no una montana impuesta")
	var sample: float = source.get_height(123.0, -72.0)
	var layout: Array[Vector3] = []
	for z in range(-384, 385, 48):
		for x in range(-384, 385, 48): layout.append(source.get_biome_weights(x, z))
	source.set_seed(2026)
	var differences := 0
	var index := 0
	for z in range(-384, 385, 48):
		for x in range(-384, 385, 48):
			if source.get_biome_weights(x, z).distance_to(layout[index]) > 0.01: differences += 1
			index += 1
	check(differences > 40, "La semilla cambia la distribucion regional del mapa")
	source.set_seed(68)
	check(is_equal_approx(source.get_height(123.0, -72.0), sample), "La misma semilla reproduce el terreno")
	source.configure_regions({"enabled": false})
	check(is_equal_approx(source.get_height(123.0, -72.0), legacy), "Desactivar regiones conserva el generador anterior")
	# Independent parameter check: zero amplitudes must give weighted base heights.
	source.configure_regions({"enabled": true, "extent": 768.0, "coast_amplitude": 0.0, "mountain_amplitude": 0.0, "jungle_amplitude": 0.0})
	var w: Vector3 = source.get_biome_weights(25.0, 87.0)
	check(is_equal_approx(source.get_height(25.0, 87.0), w.dot(Vector3(4, 130, 28))), "Se mezclan parametros, no una forma de montana nueva")
	for seed_value: int in [1, 42, 68, 1337, 2026, -1, 2147483647, -2147483648]:
		source.set_seed(seed_value)
		source.configure_regions({"enabled": true, "extent": 768.0})
		var present := Vector3.ZERO
		for z in range(-384, 385, 24):
			for x in range(-384, 385, 24):
				var region: Vector3 = source.get_biome_weights(x, z)
				if region.x > 0.8: present.x += 1
				if region.y > 0.8: present.y += 1
				if region.z > 0.8: present.z += 1
		check(present.x > 0 and present.y > 0 and present.z > 0, "Las tres regiones aparecen con semillas diferentes")
	print("Regiones S11 CG-B: %d errores; %d picos de sierra en la semilla 68" % [failures, peaks])
	quit(0 if failures == 0 else 1)
