extends SceneTree
func _initialize() -> void:
 _capture.call_deferred()
func _capture() -> void:
 root.size=Vector2i(1280,900)
 var scene: Node3D = load("res://terrain_demo.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 var terrain=scene.get_node("Terrain")
 terrain.river_catchment=60000.0
 terrain.generate_base()
 var camera := Camera3D.new()
 scene.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=1850
 camera.far=4000
 camera.position=Vector3(1000,900,1150)
 camera.look_at(Vector3(0,35,0))
 camera.make_current()
 var environment := WorldEnvironment.new()
 var settings := Environment.new()
 settings.background_mode=Environment.BG_COLOR
 settings.background_color=Color(0.15,0.18,0.22)
 settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color=Color.WHITE
 settings.ambient_light_energy=.7
 environment.environment=settings
 scene.add_child(environment)
 for frame in range(5): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://../output/s11_cgb/water_fix_godot.png")
 print("Captura real Godot: semilla %d, regiones %d, umbral %.0f" % [terrain.noise_seed,terrain.region_patches,terrain.river_catchment])
 quit()

