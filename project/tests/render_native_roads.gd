extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _capture(camera: Camera3D,p: Vector3,target: Vector3,label: String) -> void:
	camera.position=p;camera.look_at(target)
	for frame in 6:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../output/road_review/"+label+".png")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../output/road_review"))
	root.size=Vector2i(1440,900);root.msaa_3d=Viewport.MSAA_4X
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();stage.add_child(env)
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("a5bbc8")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-30,0);stage.add_child(sun)
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.use_editor_scene=false
	world.grid_size=512;world.cell_size=1.5;world.erosion_enabled=true;world.houses_enabled=false;world.vegetation_enabled=false
	stage.add_child(world);await world.generate_async(67)
	world.generator.sun_elevation=70
	var camera:=Camera3D.new();camera.current=true;camera.far=3000;camera.fov=65;stage.add_child(camera)
	# Keep the plan positions of the reported loop and parallel carriageways.
	var loop_site := Vector2(-107.74,-243.14)
	var split_site := Vector2(-85.0,-375.82)
	var wide: Array=[]
	var maximum_grade:=0.0
	for road: Dictionary in world.get_roads():
		if int(road.lanes)==4 and wide.is_empty():
			var avenue: PackedVector3Array=road.path
			wide=[avenue[avenue.size()/2],(avenue[-1]-avenue[0]).normalized()]
		if not bool(road.get("native",false)) or int(road.kind)!=1:continue
		var path: PackedVector3Array=road.path
		for j in range(1,path.size()):
			var delta:=path[j]-path[j-1]
			maximum_grade=maxf(maximum_grade,absf(delta.y)/maxf(.001,Vector2(delta.x,delta.z).length()))
	for entry in [[loop_site,Vector3(22,68,-30),"curvas"],[split_site,Vector3(14,60,34),"cambios_altura"]]:
		var site: Vector2=entry[0]
		var p:=Vector3(site.x,world.get_height(site.x,site.y),site.y)
		var eye: Vector3=p+entry[1]
		eye.y=maxf(eye.y,world.get_height(eye.x,eye.z)+18)
		await _capture(camera,eye,p,entry[2])
	if not wide.is_empty():
		var p: Vector3=wide[0];p.y=world.get_height(p.x,p.z)
		var direction: Vector3=wide[1];direction.y=0;direction=direction.normalized()
		var eye:=p-direction*36+direction.cross(Vector3.UP)*24+Vector3.UP*24
		eye.y=maxf(eye.y,world.get_height(eye.x,eye.z)+10)
		await _capture(camera,eye,p+Vector3.UP,"cuatro_carriles")
	var river_view: Array=[];var river_score:=-1.0
	for reach: Dictionary in world.water_system.reaches:
		var p: Vector3=(reach.a+reach.b)*.5
		p.y=world.water_system.surface_level_at(p.x,p.z)
		if not is_finite(p.y):continue
		var direction: Vector3=reach.b-reach.a;direction.y=0;direction=direction.normalized()
		var wet:=0
		for distance: float in [-16,-8,0,8,16]:
			var q:=p+direction*distance
			if is_finite(world.water_system.surface_level_at(q.x,q.z)):wet+=1
		var score:=wet*10+float(reach.half_width)
		if score>river_score:river_score=score;river_view=[p,direction]
	if not river_view.is_empty():
		var p: Vector3=river_view[0];var direction: Vector3=river_view[1]
		var water:=world.water_system.get_node_or_null("CaucesMayores") as MeshInstance3D
		var nearest:=INF;var focus:=p
		if water:
			var vertices: PackedVector3Array=water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0,vertices.size()-2,3):
				var centre: Vector3=(vertices[i]+vertices[i+1]+vertices[i+2])/3.0
				if centre.y-world._sample_height(centre.x,centre.z)<.25:continue
				var distance:=centre.distance_squared_to(p)
				if distance<nearest:nearest=distance;focus=centre
		p=focus
		var eye:=p-direction*5+direction.cross(Vector3.UP)*5+Vector3.UP*29
		eye.y=maxf(eye.y,world.get_height(eye.x,eye.z)+12)
		print("RIVER_REVIEW ",p," depth=",p.y-world._sample_height(p.x,p.z))
		await _capture(camera,eye,p,"rio_cauce")
	print("NATIVE_PROFILE_MAX_GRADE ",maximum_grade)
	print("NATIVE_ROADS_RENDER_RESULT 0")
	quit()
