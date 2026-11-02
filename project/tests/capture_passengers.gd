extends SceneTree
## Vista de los modelos de pasajero: altura real, animaciones y foto junto a la mototaxi.
##   Godot --path project -s res://tests/capture_passengers.gd   (necesita ventana para renderizar)
## Guarda output/passengers/lineup.png

const FILES := ["casual", "dress", "business", "woman", "worker", "casual_w"]


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)

	var moto: Node3D = load("res://scenes/mototaxi.tscn").instantiate()
	moto.set("use_input", false)
	moto.freeze = true
	world.add_child(moto)
	moto.global_position = Vector3(-3.5, 0.0, 0.0)
	moto.rotation_degrees.y = 90

	for i in FILES.size():
		var scene: PackedScene = load("res://assets/characters/passenger_%s.glb" % FILES[i])
		var c: Node3D = scene.instantiate()
		world.add_child(c)
		c.position = Vector3(i * 1.3, 0, 0)
		var aabb := _aabb(c)
		var ap := c.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("%s: alto %.2f m, ancho %.2f m, %d animaciones" % [FILES[i], aabb.size.y, aabb.size.x, ap.get_animation_list().size() if ap else 0])
		if ap:
			ap.play("CharacterArmature|Wave" if i % 2 == 0 else "CharacterArmature|Idle")

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(1.0, 1.8, 7.5), Vector3(0.8, 0.9, 0), Vector3.UP)
	cam.fov = 50
	for i in 40:
		await process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../output/passengers").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join("lineup.png"))
	print("Guardado en " + dir)
	quit()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
