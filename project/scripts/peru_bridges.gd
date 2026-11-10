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
		for i in points.size():
			var wet:=world.is_water(points[i].x,points[i].z)
			if wet and start<0:start=maxi(0,i-1)
			if start>=0 and (not wet or i==points.size()-1):
				var end:=mini(points.size()-1,i+1)
				if points[start].distance_to(points[end])>5:_span(world,points,start,end,float(road.width)+(3.5 if int(road.kind)>=2 else 0.0))
				start=-1
	var steel:=StandardMaterial3D.new();steel.albedo_color=Color("655953").srgb_to_linear();steel.metallic=.65;steel.roughness=.63
	var stone:=StandardMaterial3D.new();stone.albedo_color=Color("82786b").srgb_to_linear();stone.roughness=.94
	_instances(_beams,steel,"CelosiasYBarandas")
	_instances(_stone,stone,"TablerosYPilares")
	var cable:=StandardMaterial3D.new();cable.albedo_color=Color("474e50").srgb_to_linear();cable.metallic=.7;cable.roughness=.5
	_instances(_cables,cable,"Tirantes")
	print("Puentes regionales: ",count)

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
	for i in range(start,end):
		var a:=points[i];var b:=points[i+1]
		var clear_steps:=maxi(1,ceili(a.distance_to(b)/3))
		for k in range(clear_steps+1):
			var p:=a.lerp(b,float(k)/clear_steps)
			_blockers.append([p.x,p.z,width*.5+8])
		a.y=world.get_height(a.x,a.z);b.y=world.get_height(b.x,b.z)
		var side:=(b-a).cross(Vector3.UP).normalized()
		# Structure stays under the wearing course, even at slope changes.
		# No light concrete slabs or transverse braces on the drivable surface.
		_beam(a-Vector3.UP*.44,b-Vector3.UP*.44,width+.08,.38,_stone)
		for sign: float in [-1,1]:
			var p:=a+side*sign*(width*.5+.12);var q:=b+side*sign*(width*.5+.12)
			for height in [.55,1.05]:_beam(p+Vector3.UP*height,q+Vector3.UP*height,.09,.10,_beams)
			var rail_height:=2.2 if style=="celosia" else 1.12
			if style=="celosia":_beam(p+Vector3.UP*rail_height,q+Vector3.UP*rail_height,.13,.13,_beams)
			var steps:=maxi(1,ceili(p.distance_to(q)/3))
			for k in range(steps+1):
				var base:=p.lerp(q,float(k)/steps)
				_beam(base,base+Vector3.UP*rail_height,.10,.10,_beams)
				if style=="celosia" and k<steps:
					var next:=p.lerp(q,float(k+1)/steps)
					_beam(base+Vector3.UP*rail_height,next,.08,.08,_beams)
					_beam(base,next+Vector3.UP*rail_height,.08,.08,_beams)
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

func _instances(transforms: Array[Transform3D],material: Material,label: String) -> void:
	if transforms.is_empty():return
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE;mesh.material=material
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=transforms.size()
	for i in transforms.size():multi.set_instance_transform(i,transforms[i])
	var instance:=MultiMeshInstance3D.new();instance.name=label;instance.multimesh=multi;add_child(instance)
