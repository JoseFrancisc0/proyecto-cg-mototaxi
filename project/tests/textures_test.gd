extends SceneTree
## Revisa la capa de texturas (S10): la malla trae UV + pesos de region,
## el material usa los 3 Texture2DArray y la escena guardada no incrusta el material.
## Con pantalla (no --headless) guarda capturas en user://textures_*.png.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var root: Node3D = (load("res://terrain_demo.tscn") as PackedScene).instantiate()
	var terrain = root.get_node("Terrain")
	get_root().add_child(root)
	await process_frame
	terrain.grid_size = 256
	terrain.cell_size = 6.0
	terrain.noise_seed = 96
	terrain.preview_roads = true
	terrain.hydrology_enabled = true
	terrain.generate_base()

	var arrays: Array = terrain.mesh.surface_get_arrays(0)
	var n: int = (terrain.grid_size + 1) * (terrain.grid_size + 1)
	check((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == n, "La malla debe traer una UV por vertice")
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	check(custom.size() == n * 4, "CUSTOM0 debe traer 4 valores por vertice")
	var max_err := 0.0
	for i in range(0, n, 97):
		max_err = maxf(max_err, absf(custom[i * 4] + custom[i * 4 + 1] + custom[i * 4 + 2] - 1.0))
	check(max_err < 1e-3, "Los pesos de region deben sumar 1 (error %f)" % max_err)
	var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][n - 1]
	var v: Vector3 = arrays[Mesh.ARRAY_VERTEX][n - 1]
	check(uv.is_equal_approx(Vector2(v.x, v.z)), "UV = (x, z) en metros")

	var mat := terrain.material_override as ShaderMaterial
	check(mat != null, "Con use_textures el material debe ser el shader de texturas")
	if mat != null:
		for map_name in ["albedo", "normal", "roughness"]:
			var arr := mat.get_shader_parameter(map_name + "_maps") as Texture2DArray
			check(arr != null and arr.get_layers() == 7, "%s_maps debe tener 7 capas" % map_name)
		check(float(mat.get_shader_parameter("snow_end")) > float(mat.get_shader_parameter("snow_start")), "Linea de nieve calculada")
	print(TerrainTextures.report())

	# Guardar: el material de texturas no debe quedar incrustado en el .tscn
	terrain.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	check(terrain.material_override == null, "Antes de guardar se quita el material")
	terrain.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	check(terrain.material_override is ShaderMaterial, "Despues de guardar vuelve el material")

	# Sin texturas: colores por vertice
	terrain.use_textures = false
	check(terrain.material_override is StandardMaterial3D, "use_textures=false usa colores por vertice")
	terrain.use_textures = true

	if DisplayServer.get_name() != "headless":
		var cam: Camera3D = root.get_node("Camera")
		var size: float = terrain.grid_size * terrain.cell_size
		var shots := [
			["vista", Vector3(-size * 0.45, size * 0.30, size * 0.45), Vector3(0, 0, 0)],
			["cerca", Vector3(-80, 120, 80), Vector3(60, 40, -60)],
		]
		for shot in shots:
			cam.global_position = shot[1]
			cam.look_at(shot[2])
			cam.far = size * 4
			for dv in [0, 1]:
				mat.set_shader_parameter("debug_view", dv)
				for k in 4:
					await process_frame
				get_root().get_texture().get_image().save_png("user://textures_%s_%d.png" % [shot[0], dv])
		mat.set_shader_parameter("debug_view", 0)

	print("Texturas: %d errores" % failures)
	quit(0 if failures == 0 else 1)
