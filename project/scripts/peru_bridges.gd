class_name PeruBridges
extends Node3D
## Estructuras de paso adaptadas al ancho del cauce y a la calzada existente.
var count:=0
var spans: Array[Dictionary]=[]
var _beams: Array[Transform3D]=[]
var _stone: Array[Transform3D]=[]
var _cables: Array[Transform3D]=[]
var _blockers: Array=[]

func vegetation_blockers() -> Array:return _blockers

func build(world: TerrainWorld) -> void:
	for road: Dictionary in world.get_roads():
		var points: PackedVector3Array=road.path
		var start:=-1
		var last_wet:=-1
		var dry_run:=0.0
		var width:=float(road.width)+(3.5 if int(road.kind)>=2 else 0.0)
		for i in range(1,points.size()):
			var middle: Vector3=(points[i-1]+points[i])*.5
			if world.is_water(middle.x,middle.z) or world.is_water(points[i].x,points[i].z) or world.is_water(points[i-1].x,points[i-1].z):
				if start<0:start=maxi(0,i-2)
				last_wet=i
				dry_run=0.0
			elif start>=0:
				dry_run+=points[i].distance_to(points[i-1])
				if dry_run>6.0:
					_finish_span(world,points,start,last_wet,width)
					start=-1
		if start>=0:_finish_span(world,points,start,last_wet,width)
	var steel:=StandardMaterial3D.new();steel.albedo_color=Color("655953").srgb_to_linear();steel.metallic=.65;steel.roughness=.63
	var stone:=StandardMaterial3D.new();stone.albedo_color=Color("82786b").srgb_to_linear();stone.roughness=.94
	_instances(_beams,steel,"CelosiasYBarandas")
	_instances(_stone,stone,"TablerosYPilares")
	var cable:=StandardMaterial3D.new();cable.albedo_color=Color("474e50").srgb_to_linear();cable.metallic=.7;cable.roughness=.5
	_instances(_cables,cable,"Tirantes")
	print("Puentes regionales: ",count)

func _finish_span(world: TerrainWorld,points: PackedVector3Array,start: int,last_wet: int,width: float) -> void:
	var end:=mini(points.size()-1,last_wet+1)
	if points[start].distance_to(points[end])>5:_span(world,points,start,end,width)

func _beam(a: Vector3,b: Vector3,width: float,depth: float,out: Array[Transform3D]) -> void:
	var direction:=b-a
	if direction.length()<.02:return
	var basis:=Basis.looking_at(direction.normalized(),Vector3.UP if absf(direction.normalized().y)<.98 else Vector3.FORWARD)
	out.append(Transform3D(basis*Basis.from_scale(Vector3(width,depth,direction.length())),(a+b)*.5))

func _span(world: TerrainWorld,points: PackedVector3Array,start: int,end: int,width: float) -> void:
	count+=1
	var deck_max: float=points[start].y
	for i in range(start,end+1):deck_max=maxf(deck_max,world.get_height(points[i].x,points[i].z))
	var region:=world.get_biome(points[start].x,points[start].z).max_axis_index()
	var length:=points[start].distance_to(points[end])
	var style:="vigas" if length<12 else "arco" if region==1 else "celosia" if region==2 else "atirantado" if length>25 else "vigas"
	spans.append({"a":points[start],"b":points[end],"middle":points[(start+end)/2],"deck_max":deck_max,"width":width,"style":style})
	var rail_height:=2.2 if style=="celosia" else 1.12
	for sign: float in [-1,1]:
		var edge:=PackedVector3Array()
		for i in range(start,end+1):
			var p:=points[i]
			p.y=world.get_height(p.x,p.z)
			edge.append(p+PeruRoadLayout._corner_side(points,i)*sign*(width*.5-.12))
		_railing(edge,rail_height,style=="celosia")
	for i in range(start,end):
		var a:=points[i];var b:=points[i+1]
		var clear_steps:=maxi(1,ceili(a.distance_to(b)/3))
		for k in range(clear_steps+1):
			var p:=a.lerp(b,float(k)/clear_steps)
			_blockers.append([p.x,p.z,width*.5+8])
		a.y=world.get_height(a.x,a.z);b.y=world.get_height(b.x,b.z)
		# Structure stays under the wearing course, even at slope changes.
		# No light concrete slabs or transverse braces on the drivable surface.
		_beam(a-Vector3.UP*.44,b-Vector3.UP*.44,width+.08,.38,_stone)
	# Abutments reach the actual bed, avoiding unsupported floating slabs.
	for index in [start,end]:
		var p:=points[index];p.y=world.get_height(p.x,p.z)
		var bed:=world._sample_height(p.x,p.z)
		p.y-=.48
		_beam(Vector3(p.x,minf(bed-.6,p.y-.6),p.z),p,width+.10,.65,_stone)
	if style=="arco":
		var a:=points[start];var b:=points[end];a.y=world.get_height(a.x,a.z);b.y=world.get_height(b.x,b.z)
		var side:=(b-a).cross(Vector3.UP).normalized()
		for sign: float in [-1,1]:
			for k in 20:
				var t:=float(k)/20;var u:=float(k+1)/20
				var p:=a.lerp(b,t)+side*sign*(width*.5-.15)-Vector3.UP*(.60+(1-sin(t*PI))*2.6)
				var q:=a.lerp(b,u)+side*sign*(width*.5-.15)-Vector3.UP*(.60+(1-sin(u*PI))*2.6)
				_beam(p,q,.55,.55,_stone)
				if k%4==0:_beam(p,a.lerp(b,t)+side*sign*(width*.5-.15)-Vector3.UP*.45,.22,.24,_stone)
	elif style=="atirantado":
		var a:=points[start];var b:=points[end];a.y=world.get_height(a.x,a.z);b.y=world.get_height(b.x,b.z)
		var side:=(b-a).cross(Vector3.UP).normalized()
		var middle:=a.lerp(b,.52)
		for sign: float in [-1,1]:
			var foot:=middle+side*sign*(width*.5+.35);var crown:=foot+Vector3.UP*minf(12,length*.30)
			_beam(foot-Vector3.UP*.7,crown,.38,.45,_stone)
			for t in [.08,.22,.36,.68,.82,.94]:
				var anchor:=a.lerp(b,t)+side*sign*(width*.5+.10)+Vector3.UP*.2
				_beam(crown,anchor,.035,.035,_cables)

func _railing(edge: PackedVector3Array,height: float,truss: bool) -> void:
	var levels: Array[float]=[.55,height]
	if truss:levels.insert(1,1.05)
	var post:=edge[0]
	_beam(post,post+Vector3.UP*height,.10,.10,_beams)
	var remaining:=2.6
	for i in range(1,edge.size()):
		var a:=edge[i-1]
		var b:=edge[i]
		var length:=a.distance_to(b)
		if length<.02:continue
		var overlap:=(b-a).normalized()*.045
		for level in levels:
			_beam(a+Vector3.UP*level-overlap,b+Vector3.UP*level+overlap,.09,.10,_beams)
		while remaining<length:
			var base:=a.lerp(b,remaining/length)
			_beam(base,base+Vector3.UP*height,.10,.10,_beams)
			if truss:_brace(post,base,height)
			post=base
			remaining+=2.6
		remaining-=length
	var end:=edge[-1]
	if post.distance_to(end)>.10:
		_beam(end,end+Vector3.UP*height,.10,.10,_beams)
		if truss:_brace(post,end,height)

func _brace(a: Vector3,b: Vector3,height: float) -> void:
	_beam(a+Vector3.UP*height,b,.08,.08,_beams)
	_beam(a,b+Vector3.UP*height,.08,.08,_beams)

func _instances(transforms: Array[Transform3D],material: Material,label: String) -> void:
	if transforms.is_empty():return
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE;mesh.material=material
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=transforms.size()
	for i in transforms.size():multi.set_instance_transform(i,transforms[i])
	var instance:=MultiMeshInstance3D.new();instance.name=label;instance.multimesh=multi;add_child(instance)
