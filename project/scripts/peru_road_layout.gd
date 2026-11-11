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
var trimmed_ends := {}
var _height_buckets := {}
var _cutout:=PackedFloat32Array()
var _cutout_n:=0
var _cutout_step:=1.0

func build(w: TerrainWorld, raw: Array) -> void:
	world=w;name="RedVialPeruana"
	_cutout_n=clampi(ceili(world.get_world_size()),64,1536)
	_cutout_step=world.get_world_size()/(_cutout_n-1)
	_cutout.resize(_cutout_n*_cutout_n*2);_cutout.fill(-1000)
	raw = _trim_access_spurs(raw)
	for original: Dictionary in raw:
		var item:=original.duplicate();var path: PackedVector3Array=item.path
		if path.size()<2:continue
		var kind:=int(item.kind);var lanes:=2;var one_way:=false;var width:=float(item.width)
		if kind==0:lanes=1
		elif kind==1:lanes=4 if width>=11.2 else 2
		elif kind==2:
			lanes=4 if width>=11.2 else 2
		elif kind==3:one_way=roads.size()%3==0
		item.merge({"id":roads.size(),"width":width,"lanes":lanes,"one_way":one_way},true)
		roads.append(item);profiles["%d_%s"%[lanes,str(one_way)]]=true
	_raise_water_crossings()
	_shape_settlements()
	# Keep the existing road profiles authoritative at the edges of town
	# terraces; levelling a lot must not create a hump under a passing bus.
	_shape_ground()
	world.native_road_surface.restore(world)
	# Native metadata remains untouched. Only added streets follow their local grading.
	for item: Dictionary in roads:
		var path: PackedVector3Array=item.path
		for i in path.size():
			var p:=path[i]
			if not bool(item.get("native",false)) and not _bridge_at(p):p.y=world._sample_height(p.x,p.z)
			path[i]=p
		item.path=path
		for i in range(1,path.size()):
			var end_cap: float=item.get("junction_cap",-1.0)
			var start_limit:=-1.0;var end_limit:=-1.0
			if end_cap>=0:
				# Clip every capsule to the same junction planes. A preceding
				# segment's round cap can otherwise protrude past the last one.
				start_limit=end_cap+Vector2(path[i-1].x-path[0].x,path[i-1].z-path[0].z).length()
				end_limit=end_cap+Vector2(path[-1].x-path[i].x,path[-1].z-path[i].z).length()
			_index_segment(path[i-1],path[i],float(item.width)*.5,int(item.kind)>=2,int(item.id),not bool(item.get("native",false)) and _bridge_span(path[i-1],path[i]),start_limit,end_limit)
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
		var native_profile: bool=item.get("native",false)
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
				if not bool(item.get("native",false)) and _bridge_span(p,q):_quad(decks,_point(p,sp,-width*.5),_point(q,sq,-width*.5),_point(q,sq,width*.5),_point(p,sp,width*.5))
				if kind>=2:
					for sign: float in [-1,1]:
						var inner:=sign*(width*.5+.08);var outer:=sign*(width*.5+1.60)
						var poly:=PackedVector3Array([_point(p,sp,inner,.16),_point(q,sq,inner,.16),_point(q,sq,outer,.16),_point(p,sp,outer,.16)])
						var supported:=true
						for corner in 4:
							var v:=poly[corner];var reference:=p.y if corner==0 or corner==3 else q.y
							if absf(world._sample_height(v.x,v.z)-reference)>.45:supported=false;break
						if not supported:continue
						_walk_polygon(walks,poly,int(item.id))
						if _asphalt_clearance(poly[0])>.05 and _asphalt_clearance(poly[1])>.05 and _asphalt_clearance((poly[0]+poly[1])*.5)>.05:
							_quad(walks,poly[0]-Vector3.UP*.16,poly[1]-Vector3.UP*.16,poly[1],poly[0])
				if kind>0 and not _crossing((p+q)*.5,int(item.id),q-p):
					for edge in [-1,1]:_stripe(whites,p,q,sp,edge*(width*.5-.20),.10,sq,native_profile)
					for lane in range(1,int(item.lanes)):
						var offset: float=-width*.5+width/int(item.lanes)*lane
						if not bool(item.one_way) and lane==int(item.lanes)/2:
							var incoming:=path[j-1]-path[maxi(0,j-2)];incoming.y=0
							var outgoing:=path[mini(path.size()-1,j+1)]-path[j];outgoing.y=0
							var straight:=incoming.length_squared()>.01 and outgoing.length_squared()>.01 and incoming.normalized().dot(outgoing.normalized())>.985
							if kind==1 and straight:_dashed_stripe(yellows,p,q,sp,sq,offset,.10,distance,native_profile)
							else:
								for shift in [-.09,.09]:_stripe(yellows,p,q,sp,offset+shift,.075,sq,native_profile)
						else:_dashed_stripe(whites,p,q,sp,sq,offset,.09,distance,native_profile)
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

func _trim_access_spurs(raw: Array) -> Array:
	# A regional access can meet a highway just before its old end. Remove
	# the leftover tip only when no other road or water crossing uses it.
	var joins := {}
	var uses := {}
	for road_index in raw.size():
		var road: Dictionary = raw[road_index]
		var path: PackedVector3Array = road.path
		if path.size() < 2:continue
		if int(road.kind) == 1 and not road.get("native",false):
			joins[Vector2(path[-1].x,path[-1].z)] = road_index
		for p in path:
			var key := Vector2(p.x,p.z)
			uses[key] = int(uses.get(key,0)) + 1
	var result := raw.duplicate()
	for i in raw.size():
		var road: Dictionary = raw[i]
		if int(road.kind) != 1 or not road.get("native",false):continue
		var path: PackedVector3Array = road.path
		if path.size() < 3:continue
		for reverse in [false,true]:
			var start := path.size()-1 if reverse else 0
			var direction := -1 if reverse else 1
			var end := path[start]
			if uses[Vector2(end.x,end.z)] != 1 or world.is_water(end.x,end.z):continue
			var length := 0.0
			for j in range(1,path.size()-1):
				var index: int = start + j * direction
				var point := path[index]
				var ground := world._sample_height(point.x,point.z)
				length += Vector2(point.x-path[index-direction].x,point.z-path[index-direction].z).length()
				if length > float(road.width)*2.0 or world.is_water(point.x,point.z) or world.native_road_surface.height_at(point.x,point.z,ground)>ground+.65:break
				var key := Vector2(point.x,point.z)
				if uses[key] == 1:continue
				if joins.has(key) and uses[key] == 2:
					var access_index: int = joins[key]
					var access: Dictionary = result[access_index]
					var next_index := index + direction
					while next_index > 0 and next_index < path.size()-1:
						var next := path[next_index]
						var next_ground := world._sample_height(next.x,next.z)
						length += Vector2(next.x-path[next_index-direction].x,next.z-path[next_index-direction].z).length()
						if length > float(road.width)*2.0 or uses[Vector2(next.x,next.z)] != 1 or world.is_water(next.x,next.z):break
						if world.native_road_surface.height_at(next.x,next.z,next_ground)>next_ground+.65:break
						var aligned := _align_access(access.path,next,path[next_index+direction])
						if not aligned.is_empty():
							index = next_index
							result[access_index] = access.duplicate()
							result[access_index].path = aligned
						next_index += direction
					trimmed_ends[Vector2(end.x,end.z)] = path[index]
					path = path.slice(0,index+1) if reverse else path.slice(index)
					result[i] = road.duplicate()
					result[i].path = path
				break
	return result

func _align_access(path: PackedVector3Array,join: Vector3,next: Vector3) -> PackedVector3Array:
	var start := path.size()-2
	while start > 1 and path[start].distance_to(path[-1]) < 13.0:
		start -= 1
	var a := path[start]
	var incoming := Vector2(a.x-path[start-1].x,a.z-path[start-1].z).normalized()
	var outgoing := Vector2(next.x-join.x,next.z-join.z).normalized()
	var delta := Vector2(join.x-a.x,join.z-a.z)
	var length := delta.length()
	if length < 6.0 or incoming.dot(delta.normalized()) < .8 or outgoing.dot(delta.normalized()) < .8:
		return PackedVector3Array()
	var handle := length*.28
	var b := a+Vector3(incoming.x,0,incoming.y)*handle
	var c := join-Vector3(outgoing.x,0,outgoing.y)*handle
	var result := path.slice(0,start+1)
	var count := ceili(length/minf(1.5,world.cell_size))
	for i in range(1,count):
		var t := float(i)/count
		var p := a.bezier_interpolate(b,c,join,t)
		p.y = world._sample_height(p.x,p.z)
		if world.is_water(p.x,p.z) or absf(p.y-lerpf(a.y,join.y,t))>2.0:
			return PackedVector3Array()
		result.append(p)
	result.append(join)
	return PeruRegionalSettlements._grade_connector(world,result)

func _bridge_at(p: Vector3) -> bool:
	var ground:=world._sample_height(p.x,p.z)
	# Native decks have their own exact mesh/query. They must not trigger a
	# second deck on an unrelated added street crossing their footprint.
	return world.is_water(p.x,p.z) and p.y-ground>.65

func _bridge_span(a: Vector3,b: Vector3) -> bool:
	# Checking only the midpoint missed a wet endpoint at the shoreline.
	return _bridge_at(a) or _bridge_at(b) or _bridge_at((a+b)*.5)

func _raise_water_crossings() -> void:
	for item: Dictionary in roads:
		if bool(item.get("native",false)):continue
		var source: PackedVector3Array=item.path
		var path:=PackedVector3Array([source[0]])
		for j in range(1,source.size()):
			var steps:=maxi(1,ceili(Vector2(source[j].x-source[j-1].x,source[j].z-source[j-1].z).length()/1.5))
			for k in range(1,steps+1):path.append(source[j-1].lerp(source[j],float(k)/steps))
		for i in path.size():
			var point:=path[i];var side:=_corner_side(path,i)
			for offset in [-float(item.width)*.5,0.0,float(item.width)*.5]:
				var sample: Vector3=point+side*offset
				var water:=world.water_system.surface_level_at(sample.x,sample.z)
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
	for item: Dictionary in roads:
		if bool(item.get("native",false)):continue
		var path: PackedVector3Array=item.path;var half:=float(item.width)*.5
		var apron:=12.0 if int(item.kind)>=2 else world.cell_size*1.4
		for j in range(1,path.size()):
			var a:=path[j-1];var b:=path[j]
			if _bridge_span(a,b):continue
			var midpoint: Vector3=(a+b)*.5
			var excavation:=absf(world._sample_height(midpoint.x,midpoint.z)-midpoint.y)
			var radius:=half+maxf(apron+4,clampf(excavation*1.6+8,10,75))
			var d:=Vector2(b.x-a.x,b.z-a.z)
			for z in range(maxi(0,floori((minf(a.z,b.z)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.z,b.z)+radius+world._half)/world.cell_size)+1)):
				for x in range(maxi(0,floori((minf(a.x,b.x)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.x,b.x)+radius+world._half)/world.cell_size)+1)):
					var point:=Vector2(x*world.cell_size-world._half,z*world.cell_size-world._half)
					var t:=clampf((point-Vector2(a.x,a.z)).dot(d)/maxf(.001,d.length_squared()),0,1)
					var distance:=point.distance_to(Vector2(a.x,a.z)+d*t)
					# A continuous weight avoids the old hard step at the apron edge.
					var blend:=1.0-smoothstep(half+apron,radius,distance)
					if blend<=0:continue
					var index:=z*world._n+x;var level:=lerpf(a.y,b.y,t)
					if is_finite(world.water_system.surface_level_at(point.x,point.y)):continue
					# Preserve the riverbank beyond the actual pavement footprint.
					blend*=1-world.water_system.bank_weight(index)*smoothstep(half,half+world.cell_size*2,distance)
					if blend<=0:continue
					var weight:=blend/maxf(1,distance*distance)
					target[index]+=level*weight;weights[index]+=weight;influence[index]=maxf(influence[index],blend)
	for i in target.size():
		if weights[i]>0:
			var level:=target[i]/weights[i]
			var water:=world.water_system._water_level(i)
			if is_finite(water):level=maxf(level,water+1.6)
			world._heights[i]=lerpf(world._heights[i],level,influence[i])

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
				blend*=1-world.water_system.bank_weight(index)
				world._heights[index]=lerpf(world._heights[index],level,blend)

func _crossing(p: Vector3,own: int,direction:=Vector3.ZERO) -> bool:
	for segment: Array in _height_buckets.get(Vector2i(floori(p.x/32),floori(p.z/32)),[]):
		if int(segment[4])==own:continue
		var a: Vector3=segment[0];var b: Vector3=segment[1]
		var other:=b-a;other.y=0
		var tangent:=direction;tangent.y=0
		var closest:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		var own_half:=float(roads[own].width)*.5 if own>=0 and own<roads.size() else 0.0
		var distance:=closest.distance_to(Vector2(p.x,p.z))
		if absf((a.y+b.y)*.5-p.y)>.75:continue
		if tangent.length_squared()>.001 and absf(tangent.normalized().dot(other.normalized()))>.85:
			# Shared trunks produced by the native network are one carriageway,
			# not two sets of paint. Prefer its wider profile, then stable road id.
			var other_half:=float(segment[2])
			var preferred:=other_half>own_half+.05 or (absf(other_half-own_half)<=.05 and int(segment[4])<own)
			if preferred and distance<minf(other_half,own_half)*.8:return true
			continue
		if distance<float(segment[2])+own_half+1.5:return true
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
	if not points[0].is_finite() or not points[1].is_finite() or not points[2].is_finite():return
	if (points[1]-points[0]).cross(points[2]-points[0]).length_squared()<.00000001:return
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
		var area: Vector3=(clipped[i]-clipped[0]).cross(clipped[i+1]-clipped[0])
		if not area.is_finite() or area.length_squared()<.00000001:continue
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
	var ground:=world._sample_height(q.x,q.z)
	var native:=world.native_road_surface.height_at(q.x,q.z,ground)
	q.y=(p.y if native<=ground+.001 and _bridge_at(p) else native)+.045+extra
	return q

func _mark_point(p: Vector3,side: Vector3,lateral: float,native_profile: bool) -> Vector3:
	if not native_profile:return _point(p,side,lateral,.012)
	var q:=p+side*lateral
	var ground:=world._sample_height(q.x,q.z)
	var surface:=world.native_road_surface.height_at(q.x,q.z,ground)
	q.y=surface+.035
	return q

func _stripe(st: SurfaceTool,a: Vector3,b: Vector3,side: Vector3,offset: float,width: float,other_side: Vector3,native_profile:=false) -> void:
	_quad(st,_mark_point(a,side,offset-width*.5,native_profile),_mark_point(b,other_side,offset-width*.5,native_profile),_mark_point(b,other_side,offset+width*.5,native_profile),_mark_point(a,side,offset+width*.5,native_profile))

func _dashed_stripe(st: SurfaceTool,a: Vector3,b: Vector3,side: Vector3,other: Vector3,offset: float,width: float,chainage: float,native_profile:=false) -> void:
	var length:=a.distance_to(b)
	var position:=0.0
	while position<length-.0001:
		var phase:=fposmod(chainage+position,8.0)
		var painted:=phase<3.2
		var end:=minf(length,position+maxf(.0001,(3.2 if painted else 8.0)-phase))
		if painted:
			var t:=position/length;var u:=end/length
			_stripe(st,a.lerp(b,t),a.lerp(b,u),side.lerp(other,t),offset,width,side.lerp(other,u),native_profile)
		position=end

static func _corner_side(path: PackedVector3Array,index: int) -> Vector3:
	# Match RoadNetwork/TerrainMesh's ribbon frame exactly. A miter expansion
	# sent markings outside the native deck on tight bends.
	var tangent:=path[mini(path.size()-1,index+1)]-path[maxi(0,index-1)]
	tangent.y=0
	return tangent.normalized().cross(Vector3.UP)

func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	# Up-facing winding, stable across short curves and grades.
	for triangle in [[a,b,c],[a,c,d]]:
		if not triangle[0].is_finite() or not triangle[1].is_finite() or not triangle[2].is_finite():continue
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).length_squared()<.00000001:continue
		for p: Vector3 in triangle:st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)

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

func _index_segment(a: Vector3,b: Vector3,half: float,urban: bool,id: int,bridge: bool,cap_start:=-1.0,cap_end:=-1.0) -> void:
	var extent:=half+2.0
	var segment:=[a,b,half,urban,id,bridge]
	_raster_cutout(a,b,half,false,cap_start,cap_end)
	for z in range(floori((minf(a.z,b.z)-extent)/32),floori((maxf(a.z,b.z)+extent)/32)+1):
		for x in range(floori((minf(a.x,b.x)-extent)/32),floori((maxf(a.x,b.x)+extent)/32)+1):
			var key:=Vector2i(x,z)
			if not _height_buckets.has(key):_height_buckets[key]=[]
			_height_buckets[key].append(segment)

func _raster_cutout(a: Vector3,b: Vector3,half: float,urban: bool,cap_start:=-1.0,cap_end:=-1.0) -> void:
	var delta:=Vector2(b.x-a.x,b.z-a.z)
	var length:=delta.length()
	if length<.001:return
	var extent:=half+(1.75 if urban else 0.0)
	var radius:=extent+_cutout_step
	var origin:=world.get_world_size()*.5
	for z in range(maxi(0,floori((minf(a.z,b.z)-radius+origin)/_cutout_step)),mini(_cutout_n,ceili((maxf(a.z,b.z)+radius+origin)/_cutout_step)+1)):
		for x in range(maxi(0,floori((minf(a.x,b.x)-radius+origin)/_cutout_step)),mini(_cutout_n,ceili((maxf(a.x,b.x)+radius+origin)/_cutout_step)+1)):
			var p:=Vector2(x*_cutout_step-origin,z*_cutout_step-origin)
			var t:=clampf((p-Vector2(a.x,a.z)).dot(delta)/maxf(delta.length_squared(),.001),0,1)
			var from_center:=p.distance_to(Vector2(a.x,a.z)+delta*t)
			var distance:=extent-from_center
			var along: float=(p-Vector2(a.x,a.z)).dot(delta)/length
			if cap_start>=0:distance=minf(distance,along+cap_start)
			if cap_end>=0:distance=minf(distance,length-along+cap_end)
			var index:=(z*_cutout_n+x)*2
			if distance>_cutout[index]:_cutout[index]=distance;_cutout[index+1]=lerpf(a.y,b.y,t)+(.18 if urban and from_center>half else 0.0)

func _segment_height(x: float,z: float,ground: float,segment: Array) -> float:
	var a: Vector3=segment[0];var b: Vector3=segment[1];var delta:=Vector2(b.x-a.x,b.z-a.z)
	var t:=clampf(Vector2(x-a.x,z-a.z).dot(delta)/maxf(delta.length_squared(),.001),0,1)
	var distance:=Vector2(x,z).distance_to(Vector2(a.x,a.z)+delta*t)
	var half:=float(segment[2])
	if bool(segment[5]) and distance<half:return maxf(ground,lerpf(a.y,b.y,t)+.045)
	if bool(segment[3]) and distance>half+.1 and distance<half+1.6 and absf(ground-lerpf(a.y,b.y,t))<.45 and _asphalt_clearance(Vector3(x,ground,z))>.06:return ground+.16
	return ground

func height_at(x: float,z: float,ground: float) -> float:
	var height:=world.native_road_surface.height_at(x,z,ground)
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
			if absf(a.y-b.y)/maxf(.01,delta.length())<.38 and absf(world._sample_height(x,z)-lerpf(a.y,b.y,t))<.45:return true
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
