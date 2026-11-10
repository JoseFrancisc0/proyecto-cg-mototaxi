class_name PeruReferenceBlocks
extends Node3D
## Whole reference neighbourhoods, built from the same assets as the game.
## These controlled layouts are kept separate from procedural-map screenshots.
var camera_position:=Vector3.ZERO
var camera_target:=Vector3.ZERO
var camera_fov:=48.0
var _parts: Dictionary={}
var _lots: Array[Dictionary]=[]
var _lot_grid: Dictionary={}
var _flower_meshes: Dictionary={}
var _rng:=RandomNumberGenerator.new()

func build_house(model: Dictionary) -> void:
	var info:=TerrainHouses.load_model(model)
	_house(model,Vector3.ZERO)
	var size: Vector3=info.size
	_box(Vector3(0,-.10,0),Vector3(maxf(30,size.x*2),.20,maxf(30,size.z*2)),Color("737b77"))
	camera_target=Vector3(0,size.y*.44,0)
	camera_position=camera_target+Vector3(.95,.50,1.45)*maxf(size.x,maxf(size.z,size.y))
	camera_fov=42
	_flush()

func build(zone: String) -> void:
	_rng.seed=716
	if zone=="ladera":_hillside()
	elif zone=="moderna":_coastline()
	else:_quinta()
	_flush()

func build_reference(key: String) -> void:
	_rng.seed=716
	if key in ["0_ladera","0_residencial","0_moderna"]:
		build(key.get_slice("_",1));return
	match key:
		"1_residencial":_valley_house()
		"1_ladera":_adobe_street()
		"2_residencial":_garden_lane()
		"2_moderna":_tropical_plot()
		_:
			if key.left(1).is_valid_int():_generic_street(int(key.get_slice("_",0)),key.get_slice("_",1))
			else:_vehicle(key)
	_flush()

func _material(color: Color,texture: String="") -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color.srgb_to_linear();mat.roughness=.94
	if not texture.is_empty():
		mat.albedo_texture=load(texture);mat.uv1_triplanar=true;mat.uv1_world_triplanar=true;mat.uv1_scale=Vector3.ONE*.4
	return mat

func _box(p: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=p;node.material_override=_material(color);add_child(node);return node

func _house(model: Dictionary,p: Vector3,yaw:=0.0,scale_value:=1.0) -> Vector3:
	var info:=TerrainHouses.load_model(model)
	var placement:=Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale_value),p)
	for part: Array in info.parts:
		var mesh:=part[0] as Mesh;var key:=mesh.get_instance_id()
		if not _parts.has(key):_parts[key]={"mesh":mesh,"transforms":[]}
		_parts[key].transforms.append(placement*(part[1] as Transform3D))
	return info.size*scale_value

func _flush() -> void:
	for data: Dictionary in _parts.values():
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=data.mesh;multi.instance_count=data.transforms.size()
		for i in data.transforms.size():multi.set_instance_transform(i,data.transforms[i])
		var node:=MultiMeshInstance3D.new();node.multimesh=multi;add_child(node)

func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	for p in [a,b,c,a,c,d]:st.set_uv(Vector2(p.x,p.z)*.25);st.add_vertex(p)

func _surface(st: SurfaceTool,mat: Material,solid:=false) -> MeshInstance3D:
	st.generate_normals();var mesh:=st.commit();var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat;add_child(node)
	if solid:node.create_trimesh_collision()
	return node

func _hill_base(x: float,z: float) -> float:
	var radius:=Vector2(x+15,(z+80)*.85).length()
	return maxf(0,70-radius*.58)+sin(x*.071+z*.043)*.45

func _road_z(row: int,x: float) -> float:return 20.0-row*21+sin(x*.037+row*.43)*4.5-x*.075

func _register_lot(p: Vector3,size: Vector3) -> void:
	var lot:={"position":p,"size":size};_lots.append(lot)
	for z in range(floori((p.z-size.z*.5-2.5)/16),floori((p.z+size.z*.5+2.5)/16)+1):
		for x in range(floori((p.x-size.x*.5-2.5)/16),floori((p.x+size.x*.5+2.5)/16)+1):
			var key:=Vector2i(x,z)
			if not _lot_grid.has(key):_lot_grid[key]=[]
			_lot_grid[key].append(lot)

func _hill_height(x: float,z: float) -> float:
	var height:=_hill_base(x,z)
	for row in 7:
		var road_z:=_road_z(row,x)
		var influence:=1-smoothstep(2.1,4.8,absf(z-road_z))
		height=lerpf(height,_hill_base(x,road_z),influence)
	for lot: Dictionary in _lot_grid.get(Vector2i(floori(x/16),floori(z/16)),[]):
		var p: Vector3=lot.position;var size: Vector3=lot.size
		var delta:=Vector2(maxf(0,absf(x-p.x)-size.x*.5),maxf(0,absf(z-p.z)-size.z*.5))
		if delta.length()>2.5:continue
		height=lerpf(height,p.y-.03,1-smoothstep(.1,2.5,delta.length()))
	return height

func _hillside() -> void:
	var models:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==0 and "ladera" in m.zones)
	var finished:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==0 and "popular" in m.zones)
	for row in 7:
		for side_value in [-1.0,1.0]:
			var x:=-58.0+_rng.randf_range(-4,4)
			for column in 16:
				var item: Dictionary=models[_rng.randi()%models.size()]
				if row<2 and column%7==4:item=finished[(row+column)%finished.size()]
				var scale_value:=_rng.randf_range(.82,1.05)
				var size: Vector3=TerrainHouses.load_model(item).size*scale_value
				x+=size.x*.5
				var p:=Vector3(x,0,_road_z(row,x)+side_value*(size.z*.5+2.9));p.y=_hill_base(p.x,p.z)
				_house(item,p,PI if side_value>0 else 0.0,scale_value)
				_register_lot(p,size)
				x+=size.x*.5+_rng.randf_range(.12,.7)
	var ground:=SurfaceTool.new();ground.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-300,201,4):
		for x in range(-300,301,4):
			_quad(ground,Vector3(x,_hill_height(x,z),z),Vector3(x+4,_hill_height(x+4,z),z),Vector3(x+4,_hill_height(x+4,z+4),z+4),Vector3(x,_hill_height(x,z+4),z+4))
	var mat:=_material(Color("b6aa93"),"res://textures/Ground054_2K-JPG/Ground054_2K-JPG_Color.jpg")
	_surface(ground,mat,true)
	var dirt:=SurfaceTool.new();dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 7:
		for x in range(-68,69,2):
			var z:=_road_z(row,x);var next:=_road_z(row,x+2)
			_quad(dirt,Vector3(x,_hill_base(x,z)+.06,z-2),Vector3(x+2,_hill_base(x+2,next)+.06,next-2),Vector3(x+2,_hill_base(x+2,next)+.06,next+2),Vector3(x,_hill_base(x,z)+.06,z+2))
	_surface(dirt,_material(Color("c9bda7"),"res://textures/Ground054_2K-JPG/Ground054_2K-JPG_Color.jpg"))
	# Continuous pedestrian stairs between terraces, with a clear route.
	for x in [-56.0,47.0]:
		for j in range(220):
			var z:=25-j*.6;var height:=_hill_height(x,z)
			_box(Vector3(x,height+.02,z),Vector3(1.2,.16,.62),Color("a69c83"))
	camera_position=Vector3(100,66,102);camera_target=Vector3(-3,30,-51);camera_fov=53

func _palm(p: Vector3,scale_value:=.60) -> void:
	add_palm(self,p,scale_value)

static func add_palm(parent: Node3D,p: Vector3,scale_value:=.60,species: String="palmera") -> void:
	var variants:=VegetationModels.get_variants(species)
	if variants.is_empty():return
	var mesh:=variants[0].duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var mat:=mesh.surface_get_material(surface).duplicate() as ShaderMaterial
		mat.set_shader_parameter("hide_outside",1.0e9);mat.set_shader_parameter("hide_inside",0)
		mesh.surface_set_material(surface,mat)
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_colors=true;multi.use_custom_data=true;multi.mesh=mesh;multi.instance_count=1
	multi.set_instance_transform(0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_value),p));multi.set_instance_color(0,Color.WHITE);multi.set_instance_custom_data(0,Color(.3,1,1,1))
	var node:=MultiMeshInstance3D.new();node.multimesh=multi;parent.add_child(node)

func _road_x(z: float,y: float,length: float,width: float) -> void:
	_box(Vector3(0,y-.10,z),Vector3(length,.20,width),Color("35393b"))
	for side in [-1,1]:_box(Vector3(0,y+.012,z+side*(width*.5-.18)),Vector3(length,.012,.09),Color("e1dfd0"))
	for lane in range(1,4):
		for x in range(-floori(length*.5),floori(length*.5),7):_box(Vector3(x,y+.012,z-width*.5+width*lane/4),Vector3(3,.014,.075),Color("c8c6bb"))

func _coastline() -> void:
	var modern:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==0 and "moderna" in m.zones)
	var lower:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==0 and "popular" in m.zones)
	var top:=66.0
	_box(Vector3(0,top-2,-320),Vector3(1200,4,650),Color("8b8d7d"))
	var cliff:=SurfaceTool.new();cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(-600,601,3):
		for band in 8:
			var points: Array[Vector3]=[]
			for pair: Vector2 in [Vector2(x,band/8.0),Vector2(x+3,band/8.0),Vector2(x+3,(band+1)/8.0),Vector2(x,(band+1)/8.0)]:
				var xx:=pair.x;var t:=pair.y
				var zz:=6+sin(xx*.045)*2.5+t*4+pow(t,5)*9+sin(xx*.17+2)*sin(t*PI)*1.7
				points.append(Vector3(xx,lerpf(top,2,t),zz))
			for index in [0,1,2,0,2,3]:
				var p: Vector3=points[index];cliff.set_uv(Vector2(p.x,p.y)*.16);cliff.add_vertex(p)
	_surface(cliff,_material(Color("b7a07a"),"res://textures/Rock059_2K-JPG/Rock059_2K-JPG_Color.jpg"),true)
	_box(Vector3(0,1.1,31),Vector3(1200,2,27),Color("b6ac98"))
	_road_x(25,2.2,1200,13.6)
	_box(Vector3(0,2.3,25),Vector3(1200,.22,.65),Color("8d9672"))
	var sea:=PlaneMesh.new();sea.size=Vector2(4000,4000)
	var arrays:=sea.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors:=PackedColorArray();colors.resize(vertices.size());colors.fill(Color("286d7b"));arrays[Mesh.ARRAY_COLOR]=colors
	var sea_mesh:=ArrayMesh.new();sea_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var sea_node:=MeshInstance3D.new();sea_node.mesh=sea_mesh;sea_node.position=Vector3(0,0,2036)
	var water:=ShaderMaterial.new();water.shader=preload("res://shaders/peru_water.gdshader");sea_node.material_override=water;add_child(sea_node)
	for x in range(-600,601,5):_box(Vector3(x,.015,38+sin(x*.15)),Vector3(4,.025,.7),Color("bbd6d2"))
	# The bluff-top park and promenade separate buildings from the cliff edge.
	_box(Vector3(0,top+.025,1),Vector3(1190,.05,7),Color("739149"))
	_box(Vector3(0,top+.06,-2.5),Vector3(1190,.06,2.0),Color("c1b99b"))
	_road_x(-8,top+.1,1190,7.0)
	var cursor:=-88.0
	for index in 11:
		var item: Dictionary=modern[[0,1,0,2,3,3,1,2,0,1,2][index]]
		var w:=float(item.frontage);cursor+=w*.5
		_house(item,Vector3(cursor,top+.12,-21),0,.95 if index%4==0 else 1)
		cursor+=w*.5+1.7
	for row in range(1,13):
		var x:=-290.0
		for column in 64:
			var variant:=(column+row)%3
			var item: Dictionary=modern[variant] if column%5==0 else lower[(column+row)%4]
			var w:=float(item.frontage);x+=w*.5
			_house(item,Vector3(x,top+.12,-28-row*25),0,_rng.randf_range(.80,1.05))
			x+=w*.5+1.5
	for x in range(-186,187,15):_palm(Vector3(x,top+.10,2),.62)
	camera_position=Vector3(132,216,128);camera_target=Vector3(0,78,-36);camera_fov=48

func _quinta() -> void:
	var models:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==0 and "residencial" in m.zones)
	_box(Vector3(0,-.15,0),Vector3(92,.3,55),Color("769066"))
	_box(Vector3(0,.02,10),Vector3(84,.06,4),Color("8c897e"))
	_box(Vector3(0,.07,6.7),Vector3(84,.14,2.0),Color("c1b7a3"))
	var x:=-24.0
	for index in 7:
		var item: Dictionary=models[index%4];var info:=TerrainHouses.load_model(item)
		x+=float(item.frontage)*.5
		_house(item,Vector3(x,.10,-info.size.z*.5+5.4))
		if index%2==1:_palm(Vector3(x+float(item.frontage)*.51,.10,1.2),.70)
		for j in range(4):add_palm(self,Vector3(x-float(item.frontage)*.35+j*.65,.12,2.1),.30,"arbusto")
		x+=float(item.frontage)*.5+1.3
	camera_position=Vector3(-30,3.4,16);camera_target=Vector3(-15,3.6,0);camera_fov=50

func _generic_street(region: int,zone: String) -> void:
	var models:=TerrainHouses.MODELS.filter(func(m):return int(m.region)==region and zone in m.zones)
	var width:=0.0
	for item: Dictionary in models:width+=float(item.frontage)+.25
	_box(Vector3(0,-.15,0),Vector3(width+60,.3,80),Color("a99b7f") if region==0 else Color("8f926d") if region==1 else Color("68824c"))
	_box(Vector3(0,.015,0),Vector3(width+50,.04,6.4),Color("373b3c"))
	for z in [-3.8,3.8]:_box(Vector3(0,.08,z),Vector3(width+50,.16,1.2),Color("aca797"))
	var cursor:=-width*.5
	for item: Dictionary in models:
		var info:=TerrainHouses.load_model(item);cursor+=float(item.frontage)*.5
		_house(item,Vector3(cursor,.12,-4.6-info.size.z*.5))
		_house(item,Vector3(-cursor,.12,4.6+info.size.z*.5),PI)
		cursor+=float(item.frontage)*.5+.25
	camera_position=Vector3(-width*.53,5.3,19);camera_target=Vector3(0,3,-4);camera_fov=54

func _vehicle(key: String) -> void:
	_box(Vector3(0,-.08,0),Vector3(28,.16,28),Color("565a5b"))
	var actor:=PeruTrafficVehicle.new();add_child(actor)
	var model: Node3D=load("res://assets/traffic/%s.glb"%key).instantiate();actor.add_child(model);actor.configure(PeruTraffic.FLEET.find(key))
	var box:=Passenger.HeadModel.bounds(model)
	camera_target=box.get_center();camera_position=camera_target+Vector3(3.5,1.5,4.2)*maxf(box.size.z,2)*.30;camera_fov=38

func _trees_behind(z: float,count: int=16) -> void:
	for j in count:
		var x:=(j-count*.5)*3.4
		add_palm(self,Vector3(x,0,z+_rng.randf_range(-3,3)),_rng.randf_range(.6,1.0),"arbol_selva")

func _valley_house() -> void:
	var item: Dictionary=TerrainHouses.MODELS.filter(func(m):return str(m.style)=="valle_sagrado")[0]
	_house(item,Vector3.ZERO)
	var grass:=_box(Vector3(0,-.12,0),Vector3(800,.24,800),Color("68824a"));grass.material_override=_material(Color("8b9470"),"res://textures/Ground037_2K-JPG/Ground037_2K-JPG_Color.jpg")
	for j in 12:add_palm(self,Vector3(-24+j*4.0,0,-14-_rng.randf_range(0,6)),_rng.randf_range(.4,.8),"huarango")
	var mountain:=SurfaceTool.new();mountain.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-180,-24,4):
		for x in range(-160,161,4):
			var points: Array[Vector3]=[]
			for q: Vector2 in [Vector2(x,z),Vector2(x+4,z),Vector2(x+4,z+4),Vector2(x,z+4)]:
				var y:=maxf(0,-q.y-30)*.5+sin(q.x*.04)*8+cos(q.x*.083+q.y*.03)*5
				points.append(Vector3(q.x,maxf(0,y),q.y))
			_quad(mountain,points[0],points[1],points[2],points[3])
	_surface(mountain,_material(Color("7c8566"),"res://textures/Rock059_2K-JPG/Rock059_2K-JPG_Color.jpg"))
	camera_position=Vector3(10.5,4.1,16);camera_target=Vector3(0,2.8,0);camera_fov=45

func _street_pole(p: Vector3) -> void:
	var cylinder:=CylinderMesh.new();cylinder.top_radius=.065;cylinder.bottom_radius=.09;cylinder.height=6;cylinder.radial_segments=10
	var node:=MeshInstance3D.new();node.mesh=cylinder;node.material_override=_material(Color("8e8d7f"));node.position=p+Vector3.UP*3;add_child(node)
	_box(p+Vector3(-.55,5.8,0),Vector3(1.2,.07,.07),Color("777a73"))
	_box(p+Vector3(-1.02,5.73,0),Vector3(.52,.10,.20),Color("a9aaa3"))

func _adobe_street() -> void:
	var models:=TerrainHouses.MODELS.filter(func(m):return str(m.style)=="andina_ladera")
	_box(Vector3(0,-.2,0),Vector3(60,.4,100),Color("b6a58c"))
	_box(Vector3(0,.015,0),Vector3(4.5,.05,94),Color("b5b0a1"))
	for sign_value in [-1.0,1.0]:
		var cursor:=-34.0
		for j in 10:
			var item: Dictionary=models[j%models.size()];var info:=TerrainHouses.load_model(item);cursor+=float(item.frontage)*.5
			_house(item,Vector3(sign_value*(2.8+info.size.z*.5),.06,cursor),-PI*.5 if sign_value>0 else PI*.5)
			cursor+=float(item.frontage)*.5+.08
		for z in [-28.0,-8.0,12.0,32.0]:_street_pole(Vector3(sign_value*2.65,0,z))
	# Thin sagging overhead lines, kept clear of the road and pedestrian height.
	var lines:=ImmediateMesh.new();lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for side in [-1.0,1.0]:
		for z in [-28.0,-8.0,12.0]:
			for wire in 3:
				for k in 12:
					for t in [k/12.0,(k+1)/12.0]:lines.surface_add_vertex(Vector3(side*(2.65+wire*.08),5.75-sin(t*PI)*.32,z+t*20))
	lines.surface_end()
	var wires:=MeshInstance3D.new();wires.mesh=lines;wires.material_override=_material(Color("444844"));add_child(wires)
	camera_position=Vector3(-.35,1.9,30);camera_target=Vector3(0,2.2,-14);camera_fov=58

func _flowers(p: Vector3) -> void:
	for j in 12:
		var variant:=j%2
		if not _flower_meshes.has(variant):
			var sphere:=SphereMesh.new();sphere.radius=.025;sphere.height=.035;sphere.radial_segments=7;sphere.rings=4;sphere.material=_material(Color("d84282") if variant else Color("c84d6d"));_flower_meshes[variant]=sphere
		var mesh: Mesh=_flower_meshes[variant];var key:=mesh.get_instance_id()
		if not _parts.has(key):_parts[key]={"mesh":mesh,"transforms":[]}
		var center:=p+Vector3(_rng.randf_range(-.55,.55),_rng.randf_range(.8,1.45),_rng.randf_range(-.35,.35))
		for petal in 5:
			var a:=petal*TAU/5;_parts[key].transforms.append(Transform3D(Basis.IDENTITY,center+Vector3(cos(a)*.035,0,sin(a)*.035)))

func _garden_lane() -> void:
	var models:=TerrainHouses.MODELS.filter(func(m):return str(m.style)=="tarapoto")
	_box(Vector3(0,-.14,0),Vector3(100,.28,70),Color("6b8752"))
	var path:=_box(Vector3(0,.04,3.4),Vector3(65,.08,2.0),Color("b09a80"));path.material_override=_material(Color("bbaa99"),"res://assets/houses/peru/materials/costa/red_bricks_02.jpg")
	var x:=-24.0
	for j in 13:
		var item: Dictionary=models[j%4];var info:=TerrainHouses.load_model(item);x+=float(item.frontage)*.5
		_house(item,Vector3(x,.06,-info.size.z*.5+2.2))
		add_palm(self,Vector3(x,.06,5.5),1.1,"arbusto");_flowers(Vector3(x,0,5.5))
		x+=float(item.frontage)*.5+.035
	_trees_behind(-10,20)
	camera_position=Vector3(-23,2.2,5.8);camera_target=Vector3(3,1.6,2.2);camera_fov=62

func _tropical_plot() -> void:
	var item: Dictionary=TerrainHouses.MODELS.filter(func(m):return str(m.style)=="tropical_actual")[0]
	_house(item,Vector3.ZERO)
	_box(Vector3(0,-.12,0),Vector3(100,.24,80),Color("a69376"))
	_box(Vector3(0,.025,9),Vector3(80,.05,4.5),Color("b0a186"))
	_trees_behind(-10,14)
	for p in [Vector3(-8,0,-1),Vector3(7,0,1),Vector3(-10,0,5),Vector3(9,0,-4)]:add_palm(self,p,.7,"arbol_selva")
	camera_position=Vector3(11,3.8,17);camera_target=Vector3(0,3.0,0);camera_fov=52
