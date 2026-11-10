extends SceneTree
var stage: Node3D
var camera: Camera3D
var details: PeruNeighborhoodDetails
func _initialize() -> void:_run.call_deferred()
func _box(parent: Node3D,p: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=p
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.9;node.material_override=material;parent.add_child(node);return node
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../output/comparacion/juego"))
	root.size=Vector2i(1440,900)
	root.msaa_3d=Viewport.MSAA_4X
	stage=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();stage.add_child(environment)
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b3c8cf")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("bdc6cb");environment.environment.ambient_light_energy=.30
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,155,0);sun.light_energy=.72;sun.shadow_enabled=true;stage.add_child(sun)
	camera=Camera3D.new();camera.current=true;camera.fov=63;camera.far=1000;stage.add_child(camera)
	details=PeruNeighborhoodDetails.new();stage.add_child(details)
	for region in 3:
		var zones: Array=["ladera","popular","tradicional","residencial","moderna","rural"] if region==0 else ["popular","tradicional","residencial","moderna","rural","ladera"] if region==1 else ["popular","tradicional","residencial","moderna","rural","ribereno"]
		for zone in zones:
			if (region==1 and zone in ["residencial","ladera"]) or (region==2 and zone in ["residencial","moderna"]):
				sun.rotation_degrees.y=-25
				var block:=PeruReferenceBlocks.new();stage.add_child(block);block.build_reference("%d_%s"%[region,zone])
				camera.fov=block.camera_fov;camera.position=block.camera_position;camera.look_at(block.camera_target)
				for frame in 7:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../output/comparacion/juego/%d_%s.png"%[region,zone])
				print("REFERENCE_BLOCK_CAPTURE ",region," ",zone)
				block.queue_free();await process_frame;sun.rotation_degrees.y=155
				continue
			if region==0 and zone in ["ladera","moderna","residencial"]:
				sun.rotation_degrees.y=-25
				var block:=PeruReferenceBlocks.new();stage.add_child(block);block.build(zone)
				camera.fov=block.camera_fov;camera.position=block.camera_position;camera.look_at(block.camera_target)
				for frame in 7:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../output/comparacion/juego/0_%s.png"%zone)
				print("REFERENCE_BLOCK_CAPTURE ",zone)
				block.queue_free();await process_frame;sun.rotation_degrees.y=155
				continue
			var group:=Node3D.new();stage.add_child(group)
			var models:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==region and zone in m.zones)
			var width:=0.0;var highest:=0.0
			var first_facade:=Vector3.ZERO
			for item in models:width+=float(item.frontage)+(.10 if zone in ["popular","tradicional"] else 1.5)
			var cursor:=-width*.5
			var ground:=Color("a1957a") if region==0 else Color("8f926b") if region==1 else Color("64794e")
			_box(group,Vector3(0,-.40,-3),Vector3(100,.5,110),ground)
			var alley: bool=region==1 and zone=="tradicional"
			if alley:
				for step in range(80):
					var zz:=-width*.5+step*width/80
					var stair:=_box(group,Vector3(0,step*.075-.06,zz),Vector3(2.8,.16,width/80+.02),Color("8c8578"))
					var finish:=stair.material_override as StandardMaterial3D;finish.albedo_texture=load("res://assets/houses/peru/materials/sierra/stone_block_wall.jpg")
			elif zone!="ladera":
				_box(group,Vector3(0,-.04,0),Vector3(7,.08,width+35),Color("36383a"))
				for x in [-3.35,3.35]:_box(group,Vector3(x,.025,0),Vector3(.09,.01,width+35),Color("d8d3bd"))
				for x in [-.07,.07]:_box(group,Vector3(x,.025,0),Vector3(.045,.01,width+35),Color("dfc360"))
				for x in [-4.60,4.60]:_box(group,Vector3(x,.08,0),Vector3(2.2,.16,width+30),Color("aaa596"))
			var index:=0
			for item: Dictionary in models:
				var info:=TerrainHouses.load_model(item);var house:=Node3D.new();group.add_child(house)
				var size: Vector3=info.size
				var hillside: bool=zone=="ladera";var y:=float(index)*1.1 if hillside else 0.0
				house.position=Vector3(cursor+float(item.frontage)*.5,y,-size.z*.5) if hillside else Vector3(-5.7-size.z*.5,0,cursor+float(item.frontage)*.5)
				if region==0 and zone=="popular":house.position.z=-house.position.z
				if alley:
					house.position.x=-1.35-size.z*.5;house.position.y=(cursor+float(item.frontage)*.5+width*.5)/width*6.0
					var base_wall:=_box(house,Vector3(0,-.65,0),Vector3(size.x,1.3,size.z),Color("8c8170"))
					var finish:=base_wall.material_override as StandardMaterial3D;finish.albedo_texture=load("res://assets/houses/peru/materials/sierra/rustic_stone_wall.jpg")
				if not hillside:house.rotation.y=PI*.5
				if index==0:first_facade=house.position+Vector3(size.z*.5,0,0)
				for part: Array in info.parts:
					var node:=MeshInstance3D.new();node.mesh=part[0];node.transform=part[1];house.add_child(node)
				if hillside:
					_box(group,house.position+Vector3(0,-y*.5-.25,-3),Vector3(size.x+2.5,y+.20,size.z+10),ground)
					for step in int(y/.18)+1:
						_box(group,Vector3(house.position.x,y-step*.18-.09,1+step*.24),Vector3(1.2,.18,.30),Color("afa178"))
				if zone in ["popular","ladera"] and index==0 and region!=0:
					# Show paint on a real boundary wall, never over a window or door.
					var wall:=_box(house,Vector3(-size.x*.27,.62,size.z*.5+.45),Vector3(size.x*.42,1.24,.15),Color("c5bca3"))
					details.add_graffiti(wall,Vector3(0,.05,.085),Vector2(size.x*.36,.80))
					if zone=="popular":details.add_litter(house,Vector3(-size.x*.30,0,size.z*.5+.90),20)
				if zone in ["moderna","residencial"]:
					for side in [-1,1]:
						_box(house,Vector3(side*size.x*.34,.42,size.z*.5+.65),Vector3(size.x*.26,.84,.18),Color("bcb7a9"))
						for j in 3:
							var shrub:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.32;sphere.height=.72;shrub.mesh=sphere;shrub.position=Vector3(side*size.x*.34+(j-1)*.42,.42,size.z*.5+.34);var green:=StandardMaterial3D.new();green.albedo_color=Color("355d3e");shrub.material_override=green;house.add_child(shrub)
				if not hillside and not (region==0 and zone=="popular") and not (region==2 and zone=="tradicional"):
					var opposite:=house.duplicate() as Node3D;group.add_child(opposite);opposite.position.x=-house.position.x;opposite.position.z=-house.position.z;opposite.rotation.y=-PI*.5
					if alley:opposite.position.y=(-house.position.z+width*.5)/width*6.0
				if region==2 and zone!="tradicional":
					PeruReferenceBlocks.add_palm(group,Vector3(house.position.x-5,0,house.position.z-size.z-4),.65)
				highest=maxf(highest,float(item.height)+y)
				cursor+=float(item.frontage)+(.10 if zone in ["popular","tradicional"] else 1.5);index+=1
			camera.fov=52
			if zone=="ladera":
				camera.fov=42;camera.position=Vector3(width*.16,maxf(5.0,highest*.55),maxf(width*.60,highest*1.25));camera.look_at(Vector3(0,highest*.40,-2))
			else:
				camera.position=Vector3(.6,maxf(2.8,highest*.18),width*.5+9)
				camera.look_at(Vector3(0,maxf(2.0,highest*.20),-width*.12))
			if region==0 and zone=="popular":
				camera.fov=50;camera.position=Vector3(6,3.0,width*.5+5);camera.look_at(Vector3(-5.7,2.9,0))
			if region==2 and zone=="tradicional":
				camera.fov=40;camera.position=first_facade+Vector3(17,3.6,.3);camera.look_at(first_facade+Vector3.UP*3.6)
			if alley:
				camera.fov=73;camera.position=Vector3(.15,7.5,width*.5+.5);camera.look_at(Vector3(0,1.5,-width*.5))
			for frame in 5:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../output/comparacion/juego/%d_%s.png"%[region,zone])
			print("DISTRICT_CAPTURE ",region," ",zone)
			group.queue_free();await process_frame
	for kind in PeruTraffic.FLEET.size():
		var group:=Node3D.new();stage.add_child(group)
		var actor:=PeruTrafficVehicle.new();group.add_child(actor)
		var model: Node3D=load("res://assets/traffic/%s.glb"%PeruTraffic.FLEET[kind]).instantiate();actor.add_child(model);actor.configure(kind)
		var bounds:=Passenger.HeadModel.bounds(model);var center:=bounds.get_center()
		_box(group,Vector3(0,-.06,0),Vector3(20,.12,20),Color("56595a"))
		camera.fov=38;camera.position=center+Vector3(3.5,1.25,3.8)*maxf(bounds.size.z,2)*.26;camera.look_at(center)
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/comparacion/juego/%s.png"%PeruTraffic.FLEET[kind])
		for view: String in ["rear","opposite"]:
			var direction:=Vector3(-3.5,1.25,-3.8) if view=="rear" else Vector3(-3.5,1.25,3.8)
			camera.position=center+direction*maxf(bounds.size.z,2)*.26;camera.look_at(center)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../output/comparacion/juego/%s_%s.png"%[PeruTraffic.FLEET[kind],view])
		group.queue_free();await process_frame
	quit()
