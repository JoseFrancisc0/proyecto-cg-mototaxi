class_name PeruRoadLayout
extends Node3D
## Calzadas continuas, perfiles de carriles y grafo dirigido compartido por tráfico y peatones.
var world: TerrainWorld
var roads: Array = []
var nodes: Array[Vector3] = []
var links: Array[Array] = []
var pedestrian_links: Array[Array]=[]
var driveable:=PackedByteArray()
var _ids := {}
var ground_bodies: Array[RID] = []
var profiles := {}
var navigation_heights := PackedFloat32Array()
var _height_buckets := {}
var _cutout:=PackedFloat32Array()
var _cutout_n:=0
var _cutout_step:=1.0

func build(w: TerrainWorld, raw: Array) -> void:
	world=w;name="RedVialPeruana"
	_cutout_n=clampi(ceili(world.get_world_size()),64,1536)
	_cutout_step=world.get_world_size()/(_cutout_n-1)
	_cutout.resize(_cutout_n*_cutout_n*2);_cutout.fill(-1000)
	var avenue:=0
	for original: Dictionary in raw:
		var item:=original.duplicate();var path: PackedVector3Array=item.path
		if path.size()<2:continue
		var kind:=int(item.kind);var lanes:=2;var one_way:=false;var width:=maxf(5.8,float(item.width))
		if kind==0:lanes=1;width=maxf(3.8,float(item.width))
		elif kind==2:
			lanes=3 if avenue%3==0 else 4;avenue+=1;one_way=lanes==3;width=lanes*3.15
		elif kind==3:width=6.4;one_way=roads.size()%3==0
		item.merge({"id":roads.size(),"width":width,"lanes":lanes,"one_way":one_way},true)
		roads.append(item);profiles["%d_%s"%[lanes,str(one_way)]]=true
	_raise_water_crossings()
	_shape_ground()
	_shape_settlements()
	# All street metadata now refers to the final, shared ground instead of a second elevated skin.
	for item: Dictionary in roads:
		var path: PackedVector3Array=item.path
		for i in path.size():
			var p:=path[i]
			if not _bridge_at(p):p.y=world._sample_height(p.x,p.z)
			path[i]=p
		item.path=path
		for i in range(1,path.size()):_index_segment(path[i-1],path[i],float(item.width)*.5,int(item.kind)>=2,int(item.id),_bridge_at((path[i-1]+path[i])*.5))
	navigation_heights=world._heights.duplicate()
	for z in world._n:
		for x in world._n:
			var index:=z*world._n+x
			navigation_heights[index]=height_at(x*world.cell_size-world._half,z*world.cell_size-world._half,navigation_heights[index])
	var asphalt:=ShaderMaterial.new();asphalt.shader=preload("res://shaders/peru_asphalt.gdshader")
	var concrete:=StandardMaterial3D.new();concrete.albedo_color=Color("898a83");concrete.roughness=.93;concrete.cull_mode=BaseMaterial3D.CULL_DISABLED
	var white:=StandardMaterial3D.new();white.albedo_color=Color("c7c6b8");white.roughness=.94
	var yellow:=StandardMaterial3D.new();yellow.albedo_color=Color("cfb450");yellow.roughness=.94
	var decks:=SurfaceTool.new();decks.begin(Mesh.PRIMITIVE_TRIANGLES)
	decks.set_custom_format(1,SurfaceTool.CUSTOM_R_FLOAT)
	decks.set_custom(1,Color(.75,0,0,0))
	var walks:=SurfaceTool.new();walks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var whites:=SurfaceTool.new();whites.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yellows:=SurfaceTool.new();yellows.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item: Dictionary in roads:
		var path: PackedVector3Array=item.path;var width:=float(item.width);var kind:=int(item.kind);var distance:=0.0
		for j in range(1,path.size()):
			var a:=path[j-1];var b:=path[j]
			if a.distance_to(b)<.02:continue
			var count:=maxi(1,ceili(a.distance_to(b)/1.5));var previous:=_node(a)
			for k in count:
				var p:=a.lerp(b,float(k)/count);var q:=a.lerp(b,float(k+1)/count)
				var next:=_node(q);_link(previous,next,int(item.id),1)
				if not bool(item.one_way):_link(next,previous,int(item.id),-1)
				previous=next
				var sp:=_corner_side(path,j-1).lerp(_corner_side(path,j),float(k)/count)
				var sq:=_corner_side(path,j-1).lerp(_corner_side(path,j),float(k+1)/count)
				if _bridge_at((p+q)*.5):_quad(decks,_point(p,sp,-width*.5),_point(q,sq,-width*.5),_point(q,sq,width*.5),_point(p,sp,width*.5))
				if kind>=2:
					for sign: float in [-1,1]:
						var inner:=sign*(width*.5+.08);var outer:=sign*(width*.5+1.60)
						var poly:=PackedVector3Array([_point(p,sp,inner,.16),_point(q,sq,inner,.16),_point(q,sq,outer,.16),_point(p,sp,outer,.16)])
						_walk_polygon(walks,poly,int(item.id))
						if _asphalt_clearance(poly[0])>.05 and _asphalt_clearance(poly[1])>.05 and _asphalt_clearance((poly[0]+poly[1])*.5)>.05:
							_quad(walks,poly[0]-Vector3.UP*.16,poly[1]-Vector3.UP*.16,poly[1],poly[0])
				if kind>0 and not _crossing((p+q)*.5,int(item.id)):
					for edge in [-1,1]:_stripe(whites,p,q,sp,edge*(width*.5-.20),.10,sq)
					for lane in range(1,int(item.lanes)):
						var offset: float=-width*.5+width/int(item.lanes)*lane
						if not bool(item.one_way) and lane==int(item.lanes)/2:
							for shift in [-.09,.09]:_stripe(yellows,p,q,sp,offset+shift,.075,sq)
						elif fmod(distance,8)<3.2:_stripe(whites,p,q,sp,offset,.09,sq)
				distance+=p.distance_to(q)
	_find_driveable()
	# Terrain uses its own sun/occlusion lighting, rather than Godot's standard
	# lights. Share that exact material on the deck as well as the road colour.
	# Matching only ALBEDO still produced a grey patch against a dark road.
	var deck_finish: Material=world.generator.material_override if world.generator.material_override else asphalt
	_commit(decks,deck_finish,"Tableros",true);_commit(walks,concrete,"Veredas",true)
	_commit(whites,white,"MarcasBlancas");_commit(yellows,yellow,"MarcasAmarillas")
	var material:=world.generator.material_override as ShaderMaterial
	if material:
		var image:=Image.create_from_data(_cutout_n,_cutout_n,false,Image.FORMAT_RGF,_cutout.to_byte_array())
		material.set_shader_parameter("road_cutout",ImageTexture.create_from_image(image))
		material.set_shader_parameter("road_cutout_extent",world.get_world_size())
		material.set_shader_parameter("road_cutout_enabled",true)
		material.set_shader_parameter("rivers_enabled",false)
		material.set_shader_parameter("local_channels_enabled",false)
	_cutout.clear()
	print("Vías integradas: %d perfiles, %d nodos"%[profiles.size(),nodes.size()])

func _bridge_at(p: Vector3) -> bool:
	return world.is_water(p.x,p.z) and p.y-world._sample_height(p.x,p.z)>.65

func _raise_water_crossings() -> void:
	for item: Dictionary in roads:
		var source: PackedVector3Array=item.path
		var path:=PackedVector3Array([source[0]])
		for j in range(1,source.size()):
			var steps:=maxi(1,ceili(Vector2(source[j].x-source[j-1].x,source[j].z-source[j-1].z).length()/1.5))
			for k in range(1,steps+1):path.append(source[j-1].lerp(source[j],float(k)/steps))
		for i in path.size():
			var point:=path[i];var side:=_corner_side(path,i)
			for offset in [-float(item.width)*.5,0.0,float(item.width)*.5]:
				var sample: Vector3=point+side*offset
				var water:=world.water_system.surface_level_at(sample.x,sample.z,true)
				if is_finite(water):point.y=maxf(point.y,water+1.6)
			path[i]=point
		# Carry the deck rise into both approaches, without a step at the bank.
		for pass_index in 2:
			for i in range(1,path.size()):
				var point:=path[i];point.y=maxf(point.y,path[i-1].y-Vector2(point.x-path[i-1].x,point.z-path[i-1].z).length()*.16);path[i]=point
			path.reverse()
		item.path=path

func _shape_ground() -> void:
	var target:=PackedFloat32Array();var weights:=PackedFloat32Array();var influence:=PackedFloat32Array()
	target.resize(world._heights.size());weights.resize(target.size());influence.resize(target.size())
	var cores:=PackedFloat32Array();var core_weights:=PackedFloat32Array();cores.resize(target.size());core_weights.resize(target.size())
	for item: Dictionary in roads:
		var path: PackedVector3Array=item.path;var half:=float(item.width)*.5
		for j in range(1,path.size()):
			var a:=path[j-1];var b:=path[j]
			if _bridge_at((a+b)*.5):continue
			var midpoint: Vector3=(a+b)*.5
			var excavation:=absf(world._sample_height(midpoint.x,midpoint.z)-midpoint.y)
			var radius:=half+maxf(world.cell_size*2,clampf(excavation*1.6+8,10,75))
			var d:=Vector2(b.x-a.x,b.z-a.z)
			for z in range(maxi(0,floori((minf(a.z,b.z)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.z,b.z)+radius+world._half)/world.cell_size)+1)):
				for x in range(maxi(0,floori((minf(a.x,b.x)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.x,b.x)+radius+world._half)/world.cell_size)+1)):
					var point:=Vector2(x*world.cell_size-world._half,z*world.cell_size-world._half)
					var t:=clampf((point-Vector2(a.x,a.z)).dot(d)/maxf(.001,d.length_squared()),0,1)
					var distance:=point.distance_to(Vector2(a.x,a.z)+d*t)
					var blend:=1.0-smoothstep(half+.5,radius,distance)
					if blend<=0:continue
					var index:=z*world._n+x;var level:=lerpf(a.y,b.y,t)
					if is_finite(world.water_system.surface_level_at(point.x,point.y)):continue
					var weight:=blend/maxf(1,distance)
					target[index]+=level*weight;weights[index]+=weight;influence[index]=maxf(influence[index],blend)
					if distance<half+world.cell_size*1.4:cores[index]+=level*weight;core_weights[index]+=weight
	for i in target.size():
		if core_weights[i]>0:
			var level:=cores[i]/core_weights[i]
			var water:=world.water_system.surface_level_at((i%world._n)*world.cell_size-world._half,(i/world._n)*world.cell_size-world._half,true)
			world._heights[i]=maxf(level,water+1.6) if is_finite(water) else level
		elif weights[i]>0:world._heights[i]=lerpf(world._heights[i],target[i]/weights[i],influence[i])

func _shape_settlements() -> void:
	for settlement: Dictionary in world._settlement_grades:
		var center: Vector3=settlement.center
		for z in range(maxi(0,floori((center.z-58+world._half)/world.cell_size)),mini(world._n,ceili((center.z+58+world._half)/world.cell_size))):
			for x in range(maxi(0,floori((center.x-58+world._half)/world.cell_size)),mini(world._n,ceili((center.x+58+world._half)/world.cell_size))):
				var wx:=x*world.cell_size-world._half;var wz:=z*world.cell_size-world._half
				if is_finite(world.water_system.surface_level_at(wx,wz)):continue
				var blend:=1-smoothstep(42,58,maxf(absf(wx-center.x),absf(wz-center.z)))
				var level:=center.y+float(settlement.dx)*(wx-center.x)+float(settlement.dz)*(wz-center.z)
				var water:=world.water_system.surface_level_at(wx,wz,true)
				if is_finite(water):level=maxf(level,water+1.6)
				var index:=z*world._n+x
				world._heights[index]=lerpf(world._heights[index],level,blend)

func _crossing(p: Vector3,own: int) -> bool:
	for segment: Array in _height_buckets.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		if int(segment[4])==own:continue
		var a: Vector3=segment[0];var b: Vector3=segment[1]
		var closest:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		var own_half:=float(roads[own].width)*.5 if own>=0 and own<roads.size() else 0.0
		if closest.distance_to(Vector2(p.x,p.z))<float(segment[2])+own_half+1.5 and absf((a.y+b.y)*.5-p.y)<3:return true
	return false

func _walk_polygon(st: SurfaceTool,points: PackedVector3Array,own: int) -> void:
	var initial:=PackedVector2Array()
	for p in points:initial.append(Vector2(p.x,p.z))
	var polygons: Array[PackedVector2Array]=[initial];var seen:={}
	for p in points:
		for segment: Array in _height_buckets.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
			if int(segment[4])==own or absf((segment[0].y+segment[1].y)*.5-p.y)>3:continue
			var key: String=str(segment[0])+str(segment[1])
			if seen.has(key):continue
			seen[key]=true
			var a: Vector3=segment[0];var b: Vector3=segment[1];var side:=(b-a).cross(Vector3.UP).normalized()*(float(segment[2])+.18)
			var clip:=PackedVector2Array([Vector2(a.x-side.x,a.z-side.z),Vector2(b.x-side.x,b.z-side.z),Vector2(b.x+side.x,b.z+side.z),Vector2(a.x+side.x,a.z+side.z)])
			var remaining: Array[PackedVector2Array]=[]
			for polygon in polygons:remaining.append_array(Geometry2D.clip_polygons(polygon,clip))
			polygons=remaining
	for polygon in polygons:
		var indices:=Geometry2D.triangulate_polygon(polygon)
		for i in range(0,indices.size(),3):
			var triangle_points: Array[Vector3]=[]
			for j in 3:
				var p: Vector2=polygon[indices[i+j]]
				triangle_points.append(Vector3(p.x,world._sample_height(p.x,p.y)+.16,p.y))
			_walk_triangle(st,triangle_points,0)

func _asphalt_clearance(p: Vector3) -> float:
	var distance:=INF
	for segment: Array in _height_buckets.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		var a: Vector3=segment[0];var b: Vector3=segment[1]
		if absf((a.y+b.y)*.5-p.y)>3:continue
		var nearest:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		distance=minf(distance,nearest.distance_to(Vector2(p.x,p.z))-float(segment[2]))
	return distance

func _walk_triangle(st: SurfaceTool,points: Array[Vector3],depth: int) -> void:
	var distances: Array[float]=[]
	for p in points:distances.append(_asphalt_clearance(p)-.06)
	var mid0: Vector3=(points[0]+points[1])*.5;var mid1: Vector3=(points[1]+points[2])*.5;var mid2: Vector3=(points[2]+points[0])*.5
	var clear:=distances[0]>=0 and distances[1]>=0 and distances[2]>=0
	for p: Vector3 in [mid0,mid1,mid2,(points[0]+points[1]+points[2])/3.0]:clear=clear and _asphalt_clearance(p)>=.06
	if clear:
		for p in points:st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
		return
	if distances[0]<0 and distances[1]<0 and distances[2]<0:return
	if depth<2:
		_walk_triangle(st,[points[0],mid0,mid2],depth+1);_walk_triangle(st,[mid0,points[1],mid1],depth+1)
		_walk_triangle(st,[mid2,mid1,points[2]],depth+1);_walk_triangle(st,[mid0,mid1,mid2],depth+1);return
	var clipped: Array[Vector3]=[]
	for i in 3:
		var j:=(i+1)%3
		if distances[i]>=0:clipped.append(points[i])
		if (distances[i]>=0)!=(distances[j]>=0):clipped.append(points[i].lerp(points[j],distances[i]/(distances[i]-distances[j])))
	for i in range(1,clipped.size()-1):
		for p: Vector3 in [clipped[0],clipped[i],clipped[i+1]]:st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)

func _node(p: Vector3) -> int:
	var key:=Vector2i(roundi(p.x*5),roundi(p.z*5))
	if _ids.has(key):return int(_ids[key])
	var index:=nodes.size();nodes.append(p);links.append([]);pedestrian_links.append([]);_ids[key]=index
	return index

func _find_driveable() -> void:
	driveable.resize(nodes.size());driveable.fill(1)
	var parents: Array[Array]=[];var degree:=PackedInt32Array();degree.resize(nodes.size())
	for i in nodes.size():parents.append([])
	for i in nodes.size():
		degree[i]=links[i].size()
		for edge: Dictionary in links[i]:parents[int(edge.to)].append(i)
	var pending: Array[int]=[]
	for i in nodes.size():
		if degree[i]==0:pending.append(i)
	while not pending.is_empty():
		var index:=pending.pop_back() as int;driveable[index]=0
		for parent: int in parents[index]:
			degree[parent]-=1
			if degree[parent]==0:pending.append(parent)

func _link(a: int,b: int,road: int,direction: int) -> void:
	if a==b:return
	for edge: Dictionary in links[a]:
		if edge.to==b:return
	links[a].append({"to":b,"road":road,"direction":direction})
	var found:=false
	for edge: Dictionary in pedestrian_links[a]:
		if edge.to==b:found=true
	if not found:
		pedestrian_links[a].append({"to":b,"road":road,"direction":direction})
		pedestrian_links[b].append({"to":a,"road":road,"direction":-direction})

func _point(p: Vector3,side: Vector3,lateral: float,extra:=0.0) -> Vector3:
	var q:=p+side*lateral
	q.y=(p.y if _bridge_at(p) else world._sample_height(q.x,q.z))+.045+extra
	return q

func _stripe(st: SurfaceTool,a: Vector3,b: Vector3,side: Vector3,offset: float,width: float,other_side: Vector3) -> void:
	_quad(st,_point(a,side,offset-width*.5,.012),_point(b,other_side,offset-width*.5,.012),_point(b,other_side,offset+width*.5,.012),_point(a,side,offset+width*.5,.012))

func _corner_side(path: PackedVector3Array,index: int) -> Vector3:
	var a:=path[index]-path[maxi(0,index-1)];var b:=path[mini(path.size()-1,index+1)]-path[index]
	a.y=0;b.y=0
	if a.length_squared()<.001:a=b
	if b.length_squared()<.001:b=a
	var outgoing:=b.normalized().cross(Vector3.UP)
	var side:=(a.normalized().cross(Vector3.UP)+outgoing).normalized()
	return side/maxf(.6,side.dot(outgoing))

func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	# Up-facing winding, stable across short curves and grades.
	for p in [a,b,c,a,c,d]:st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)

func _commit(st: SurfaceTool,mat: Material,label: String,solid:=false) -> void:
	st.generate_normals()
	var mesh:=st.commit()
	if mesh==null:return
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=mat;visual.name=label;add_child(visual)
	if solid:
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new()
		collision.shape=mesh.create_trimesh_shape();body.add_child(collision);add_child(body);ground_bodies.append(body.get_rid())

func lane_offset(road_id: int,direction: int,lane:=0) -> float:
	var road: Dictionary=roads[road_id]
	var width:=float(road.width);var count:=int(road.lanes)
	if count==1:return 0.0
	if bool(road.one_way):return -width*.5+width/count*(clampi(lane,0,count-1)+.5)
	var per_direction:=maxi(1,count/2)
	return width/count*(clampi(lane,0,per_direction-1)+.5)

func point_on_lane(from: int,to: int,road: int,direction: int,lane:=0,sidewalk:=false) -> Vector3:
	var a:=nodes[from];var b:=nodes[to]
	var side: Vector3=(b-a).normalized().cross(Vector3.UP).normalized()
	var offset:=float(roads[road].width)*.5+.85 if sidewalk else lane_offset(road,direction,lane)
	if sidewalk:offset*=direction
	return _point(b,side,offset,.18 if sidewalk and int(roads[road].kind)>=2 else (.03 if sidewalk else 0.0))

func _index_segment(a: Vector3,b: Vector3,half: float,urban: bool,id: int,bridge: bool) -> void:
	var extent:=half+2.0
	var segment:=[a,b,half,urban,id,bridge]
	_raster_cutout(a,b,half,false)
	for z in range(floori((minf(a.z,b.z)-extent)/32),floori((maxf(a.z,b.z)+extent)/32)+1):
		for x in range(floori((minf(a.x,b.x)-extent)/32),floori((maxf(a.x,b.x)+extent)/32)+1):
			var key:=Vector2i(x,z)
			if not _height_buckets.has(key):_height_buckets[key]=[]
			_height_buckets[key].append(segment)

func _raster_cutout(a: Vector3,b: Vector3,half: float,urban: bool) -> void:
	var delta:=Vector2(b.x-a.x,b.z-a.z)
	var extent:=half+(1.75 if urban else 0.0)
	var radius:=extent+_cutout_step
	var origin:=world.get_world_size()*.5
	for z in range(maxi(0,floori((minf(a.z,b.z)-radius+origin)/_cutout_step)),mini(_cutout_n,ceili((maxf(a.z,b.z)+radius+origin)/_cutout_step)+1)):
		for x in range(maxi(0,floori((minf(a.x,b.x)-radius+origin)/_cutout_step)),mini(_cutout_n,ceili((maxf(a.x,b.x)+radius+origin)/_cutout_step)+1)):
			var p:=Vector2(x*_cutout_step-origin,z*_cutout_step-origin)
			var t:=clampf((p-Vector2(a.x,a.z)).dot(delta)/maxf(delta.length_squared(),.001),0,1)
			var from_center:=p.distance_to(Vector2(a.x,a.z)+delta*t)
			var distance:=extent-from_center
			var index:=(z*_cutout_n+x)*2
			if distance>_cutout[index]:_cutout[index]=distance;_cutout[index+1]=lerpf(a.y,b.y,t)+(.18 if urban and from_center>half else 0.0)

func _segment_height(x: float,z: float,ground: float,segment: Array) -> float:
	var a: Vector3=segment[0];var b: Vector3=segment[1];var delta:=Vector2(b.x-a.x,b.z-a.z)
	var t:=clampf(Vector2(x-a.x,z-a.z).dot(delta)/maxf(delta.length_squared(),.001),0,1)
	var distance:=Vector2(x,z).distance_to(Vector2(a.x,a.z)+delta*t)
	var half:=float(segment[2])
	if bool(segment[5]) and distance<half:return maxf(ground,lerpf(a.y,b.y,t)+.045)
	if bool(segment[3]) and distance>half+.1 and distance<half+1.6 and _asphalt_clearance(Vector3(x,ground,z))>.06:return ground+.16
	return ground

func height_at(x: float,z: float,ground: float) -> float:
	var height:=ground
	for segment: Array in _height_buckets.get(Vector2i(floori(x/32),floori(z/32)),[]):height=maxf(height,_segment_height(x,z,ground,segment))
	return height

func has_walkway(x: float,z: float) -> bool:
	for segment: Array in _height_buckets.get(Vector2i(floori(x/32),floori(z/32)),[]):
		if not bool(segment[3]):continue
		var a: Vector3=segment[0];var b: Vector3=segment[1]
		var delta:=Vector2(b.x-a.x,b.z-a.z)
		var t:=clampf(Vector2(x-a.x,z-a.z).dot(delta)/maxf(.001,delta.length_squared()),0,1)
		var distance:=Vector2(x,z).distance_to(Vector2(a.x,a.z)+delta*t)
		if distance>float(segment[2])+.1 and distance<float(segment[2])+1.60 and _asphalt_clearance(Vector3(x,a.y,z))>.06:
			if absf(a.y-b.y)/maxf(.01,delta.length())<.38 and world._sample_height(x,z)<lerpf(a.y,b.y,t)+.4:return true
	return false

func vegetation_blockers() -> Array:
	var circles:=[]
	for road: Dictionary in roads:
		var path: PackedVector3Array=road.path
		var radius:=float(road.width)*.5+3.5
		for i in range(1,path.size()):
			var steps:=maxi(1,ceili(path[i-1].distance_to(path[i])/3.0))
			for k in steps:
				var p:=path[i-1].lerp(path[i],float(k)/steps)
				circles.append([p.x,p.z,radius])
	return circles
