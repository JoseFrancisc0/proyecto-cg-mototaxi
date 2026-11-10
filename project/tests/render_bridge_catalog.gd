extends SceneTree
## Controlled displays of the actual bridge builder; the map has separate captures.
class DisplayWorld extends TerrainWorld:
	var region:=0
	var span_length:=20.0
	func get_roads() -> Array:
		var points:=PackedVector3Array()
		for i in range(41):points.append(Vector3(0,6,-span_length*.5+i*span_length/40))
		return [{"path":points,"width":6.4,"kind":1}]
	func get_biome(_x: float,_z: float) -> Vector3:
		return Vector3(1,0,0) if region==0 else Vector3(0,1,0) if region==1 else Vector3(0,0,1)
	func get_height(_x: float,_z: float) -> float:return 6.0
	func _sample_height(_x: float,z: float) -> float:return -1.5 if absf(z)<span_length*.35 else 6.0
	func is_water(_x: float,z: float) -> bool:return absf(z)<span_length*.35

func _initialize() -> void:_run.call_deferred()
func _box(parent: Node3D,p: Vector3,size: Vector3,color: Color) -> void:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=p
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.94;node.material_override=mat;parent.add_child(node)
func _run() -> void:
	root.size=Vector2i(1280,800);root.msaa_3d=Viewport.MSAA_4X
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();root.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b4c9d3");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.55
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.shadow_enabled=true;root.add_child(sun)
	var camera:=Camera3D.new();camera.current=true;camera.fov=55;root.add_child(camera)
	for spec: Array in [["vigas",0,10.0],["arco",1,30.0],["celosia",2,34.0],["atirantado",0,52.0]]:
		var stage:=Node3D.new();root.add_child(stage)
		var world:=DisplayWorld.new();world.generate_on_ready=false;world.region=spec[1];world.span_length=spec[2]
		var bridge:=PeruBridges.new();stage.add_child(bridge);bridge.build(world)
		for sign_value in [-1.0,1.0]:_box(stage,Vector3(0,2,sign_value*(float(spec[2])*.35+8)),Vector3(45,8,16),Color("8a9577"))
		_box(stage,Vector3(0,0,0),Vector3(65,.1,float(spec[2])*.70),Color("477377"))
		_box(stage,Vector3(0,6.04,0),Vector3(6.4,.08,float(spec[2])+16),Color("25282a"))
		for x in [-2.96,2.96]:_box(stage,Vector3(x,6.09,0),Vector3(.10,.01,float(spec[2])+16),Color("dedbd0"))
		for x in [-.09,.09]:_box(stage,Vector3(x,6.09,0),Vector3(.07,.01,float(spec[2])+16),Color("d7b651"))
		camera.position=Vector3(maxf(18,float(spec[2])*.7),maxf(13,float(spec[2])*.30),float(spec[2])*.72);camera.look_at(Vector3(0,5,0))
		for frame in 5:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/comparacion/juego/puente_%s.png"%spec[0])
		print("BRIDGE_CAPTURE ",spec[0]," ",bridge.spans.map(func(span):return span.style))
		stage.queue_free();world.free();await process_frame
	quit()
