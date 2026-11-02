extends SceneTree
## Capturas de la vegetación en costa, sierra y selva (juego real, terreno del editor).
##   Godot --path project -s res://tests/capture_vegetation.gd -- --editor   (con ventana)
## Guarda output/vegetation/<region>.png


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	main.show_menu = false
	root.add_child(main)
	await process_frame
	await process_frame
	while is_instance_valid(main.loading):
		await process_frame
	var world: TerrainWorld = main.world
	var moto: Mototaxi = main.moto
	moto.use_input = false
	main.race.stop()
	main.hud.visible = false
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/vegetation").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var names := ["costa", "sierra", "selva"]
	for r in 3:
		# Landmark con más peso de la región (están sobre las vías).
		var best: Vector3 = Vector3.ZERO
		var best_w := -1.0
		for lm in world.get_landmarks():
			var p: Vector3 = lm["position"]
			var w: float = world.get_biome(p.x, p.z)[r]
			if w > best_w:
				best_w = w
				best = p
		moto.place_at(best, randf() * TAU)
		for i in 90:
			await process_frame
		root.get_texture().get_image().save_png(dir.path_join(names[r] + ".png"))
		print("%s: peso %.2f en %s" % [names[r], best_w, best])
	quit()
