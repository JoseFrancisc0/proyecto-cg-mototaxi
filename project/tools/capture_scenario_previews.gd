extends SceneTree
## Fotos de vista previa del selector de escenario (pendiente 11): mixta, costa, sierra y selva,
## tomadas en el juego real con el terreno guardado. Con ventana (no --headless):
##   Godot --path project -s res://tools/capture_scenario_previews.gd
## Guarda res://ui/scenarios/<region>.jpg (640 x 360). Volver a correrlo si cambia el terreno.

const SIZE := Vector2i(640, 360)
const NAMES := ["mixta", "costa", "sierra", "selva"]


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var world: TerrainWorld = main.world
	main.race.stop()
	main.hud.visible = false
	main.moto.use_input = false
	main.moto.visible = false
	# Solo para la foto: bajo el horizonte, el color del cielo y algo de neblina, para que no
	# se note dónde termina el mapa.
	var env_node := main.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if env_node and env_node.environment:
		var env := env_node.environment
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
		if sky_mat:
			sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
			sky_mat.ground_bottom_color = sky_mat.sky_horizon_color
			env.fog_light_color = sky_mat.sky_horizon_color
		env.fog_enabled = true
		env.fog_density = 0.0004
		env.fog_sky_affect = 0.0
	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	var dir := "res://ui/scenarios"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var half := world.get_world_size() * 0.5

	var shots := {}
	for r in [1, 2, 3]:
		# Vista aérea de postal: algo de cielo arriba, mirando hacia el centro del mapa.
		var spot := _region_spot(world, r - 1, half)
		var forward := Vector3(-spot.x, 0, -spot.z).normalized()
		if forward == Vector3.ZERO:
			forward = Vector3.FORWARD
		var eye: Vector3
		var target: Vector3
		if r == 2:
			# Sierra: desde el pie, mirando la montaña.
			eye = spot - forward * 420.0
			eye.y = world.get_height(eye.x, eye.z) + 70.0
			target = spot + Vector3(0, -40, 0)
		else:
			var height := 75.0
			eye = spot - forward * height
			eye.y = world.get_height(eye.x, eye.z) + height
			var ahead := spot + forward * height * 2.5
			target = Vector3(ahead.x, world.get_height(ahead.x, ahead.z), ahead.z)
		cam.global_position = eye
		cam.look_at(target, Vector3.UP)
		main.moto.place_at(Vector3(eye.x, world.get_height(eye.x, eye.z), eye.z), 0.0)
		for i in 120:
			await process_frame
		var img := root.get_texture().get_image()
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_jpg(ProjectSettings.globalize_path(dir.path_join(NAMES[r] + ".jpg")), 0.88)
		shots[r] = img
		print("%s: cámara %s -> %s" % [NAMES[r], eye, target])
	# Mixta: las tres fotos en franjas diagonales (costa, sierra, selva) con un filo claro.
	var mixed := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	for y in SIZE.y:
		for x in SIZE.x:
			var t := (float(x) + (SIZE.y - y) * 0.45) / (SIZE.x + SIZE.y * 0.45) * 3.0
			var band := clampi(int(t), 0, 2)
			var edge := absf(t - roundf(t)) < 0.012 and roundf(t) > 0.0 and roundf(t) < 3.0
			mixed.set_pixel(x, y, Color(1, 1, 1) if edge else (shots[band + 1] as Image).get_pixel(x, y))
	mixed.save_jpg(ProjectSettings.globalize_path(dir.path_join("mixta.jpg")), 0.88)
	quit()


## Punto donde la región domina con más fuerza (en una grilla del mapa, lejos del borde).
static func _region_spot(world: TerrainWorld, region: int, half: float) -> Vector3:
	var best := Vector3.ZERO
	var best_w := -1.0
	for iz in 24:
		for ix in 24:
			var x := -half * 0.8 + ix * half * 1.6 / 23.0
			var z := -half * 0.8 + iz * half * 1.6 / 23.0
			var w: float = world.get_biome(x, z)[region]
			if w > best_w + 0.001:
				best_w = w
				best = Vector3(x, world.get_height(x, z), z)
	return best
