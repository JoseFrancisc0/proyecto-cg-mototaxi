class_name PeruNeighborhoodDetails
extends Node3D
var _materials: Dictionary={}
var _rng:=RandomNumberGenerator.new()
var world: TerrainWorld
var litter_count:=0
var garden_count:=0
var mural_count:=0
var _graffiti: Dictionary={}

func add_graffiti(parent: Node3D,p: Vector3,size:=Vector2(2.1,1.65)) -> void:
	PeruWallPaint.add(parent,p,size,int(_rng.randi()%10000))
	mural_count+=1

func add_litter(parent: Node3D,p: Vector3,amount:=22) -> void:
	# One irregular accumulation point: bags, folded cartons, loose packaging,
	# flattened sheets and bottles have different silhouettes and materials.
	var palette: Array[Color]=[Color("252c29"),Color("e4ddc6"),Color("8ca55c"),Color("769eb0"),Color("ddd4ab")]
	for i in amount:
		var angle:=_rng.randf()*TAU;var radius:=sqrt(_rng.randf())*1.1
		var q:=p+Vector3(cos(angle)*radius,0,sin(angle)*radius*.62)
		if world:
			var point:=parent.to_global(q);q.y=world.get_height(point.x,point.z)-parent.global_position.y
		var kind:=i%5
		if kind==0 or kind==1:
			var bag:=SphereMesh.new();bag.radius=.19;bag.height=.43;bag.radial_segments=9;bag.rings=5
			var node:=_mesh(parent,bag,q+Vector3.UP*.18,palette[i%palette.size()]);node.scale=Vector3(_rng.randf_range(.8,1.5),_rng.randf_range(.65,1.25),_rng.randf_range(.7,1.3));node.rotation.y=angle
			_box(parent,q+Vector3.UP*.37,Vector3(.06,.10,.055),palette[i%palette.size()])
		elif kind==2:
			var carton:=_box(parent,q+Vector3.UP*.10,Vector3(.36,.20,.31),Color("9a7f55"));carton.rotation.y=angle
			for sign_value in [-1,1]:
				var flap:=_box(carton,Vector3(sign_value*.18,.13,0),Vector3(.18,.012,.30),Color("b39b72"));flap.rotation.z=sign_value*.5
		elif kind==3:
			var sheet:=_box(parent,q+Vector3.UP*.018,Vector3(.27,.012,.20),palette[i%palette.size()]);sheet.rotation=Vector3(_rng.randf_range(-.09,.09),angle,_rng.randf_range(-.10,.10))
		else:
			var bottle:=CylinderMesh.new();bottle.top_radius=.027;bottle.bottom_radius=.045;bottle.height=.21;bottle.radial_segments=8
			var node:=_mesh(parent,bottle,q+Vector3.UP*.05,Color("7a9b80"));node.rotation=Vector3(PI*.5,angle,.2)
		litter_count+=1

func _material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not _materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.9;_materials[key]=material
	return _materials[key]

func _mesh(parent: Node3D,shape: Mesh,p: Vector3,color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=shape;node.position=p;node.material_override=_material(color);node.visibility_range_end=140;parent.add_child(node);return node

func _box(parent: Node3D,p: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var box:=BoxMesh.new();box.size=size;return _mesh(parent,box,p,color)

func build(w: TerrainWorld) -> void:
	world=w;_rng.seed=w.world_seed+2349
	if world.houses==null:return
	for house: Dictionary in world.houses.houses:
		var district:=str(house.get("district","rural"))
		if district=="rural":continue
		var front:=Node3D.new();front.transform=Transform3D(Basis(Vector3.UP,float(house.yaw)),house.position);add_child(front)
		var size: Vector3=house.size
		if district in ["popular","ladera"]:
			if _rng.randf()<.22 and not bool(world.houses._models[int(house.model)].model.get("graffiti_wall",false)):
				# Painted boundary wall; avoid pasting art over house joinery.
				var side:=-1.0 if _rng.randf()<.5 else 1.0
				var info:=TerrainHouses.load_model(world.houses._models[int(house.model)].model)
				var wall:=Node3D.new();wall.position=(info.foundation_center as Vector3)+Vector3(side*((info.foundation_size as Vector2).x*.5+.012),0,0);wall.rotation.y=side*PI*.5;front.add_child(wall)
				add_graffiti(wall,Vector3(0,.52,0),Vector2(minf(3.8,(info.foundation_size as Vector2).y*.65),.70))
			# Local accumulation points, rather than evenly scattering litter at every door.
			if _rng.randf()<.09:
				var corner:=(-1.0 if _rng.randf()<.5 else 1.0)*size.x*.40
				add_litter(front,Vector3(corner,0,size.z*.5+.40),_rng.randi_range(18,30))
		elif district in ["residencial","moderna"]:
			# Boundary walls belong to the authored house. A generic front-only
			# wall floated over sloped streets and left both ends open.
			for side in [-1,1]:
				var p:=Vector3(side*size.x*.34,0,size.z*.5+.32);var global:=front.to_global(p);p.y=world.get_height(global.x,global.z)-front.position.y
				if world.get_offroad_amount(global.x,global.z)<.99 or world.is_water(global.x,global.z):continue
				var bottom:=p.y
				for corner in [Vector3(-1,0,-1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(1,0,1)]:
					var sample:=front.to_global(p+corner*Vector3(size.x*.125,0,.25))
					bottom=minf(bottom,world._sample_height(sample.x,sample.z)-front.position.y)
				bottom-=.03
				var top:=p.y+.44
				_box(front,Vector3(p.x,(top+bottom)*.5,p.z),Vector3(size.x*.25,top-bottom,.50),Color("777b70"))
				for i in 4:
					var bush:=SphereMesh.new();bush.radius=.21;bush.height=.45;bush.radial_segments=10;bush.rings=6
					_mesh(front,bush,p+Vector3((i-1.5)*size.x*.055,.55,0),Color("3b6541"))
				garden_count+=1
	print("Barrios: %d murales, %d residuos, %d jardineras"%[mural_count,litter_count,garden_count])
