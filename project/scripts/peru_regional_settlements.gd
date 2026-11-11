class_name PeruRegionalSettlements
extends RefCounted
## Add connected settlements on buildable Andean/Amazonian ground, not only coastal flats.
static func extend(world: TerrainWorld,raw: Array) -> Array:
	var output:=raw.duplicate();var all_points:=PackedVector3Array()
	var access_nodes:={}
	for road: Dictionary in raw:
		for p: Vector3 in road.path:all_points.append(p)
	if all_points.is_empty():return output
	var supported_joins:=PackedVector3Array()
	for j in range(0,all_points.size(),4):
		var p:=all_points[j]
		if absf(p.y-world._sample_height(p.x,p.z))<=.35:supported_joins.append(p)
	# Grade native towns as well as the added towns. Otherwise their lots still
	# inherit the steep road cuts and only the coastal/Amazonian additions fit.
	for center: Vector3 in world.generator.last_roads.get_town_centers():
		if world.is_water(center.x,center.z):continue
		var height:=world._sample_height(center.x,center.z)
		var dx: float=clampf((world._sample_height(center.x+12,center.z)-world._sample_height(center.x-12,center.z))/24,-.025,.025)
		var dz: float=clampf((world._sample_height(center.x,center.z+12)-world._sample_height(center.x,center.z-12))/24,-.025,.025)
		world._settlement_grades.append({"center":Vector3(center.x,height,center.z),"dx":dx,"dz":dz})
	for region in [0,1,2]:
		var candidates: Array[Dictionary]=[]
		var step:=maxf(12,world.get_world_size()/40)
		var margin:=minf(65,world._half*.20)
		for zi in range(ceili((-world._half+margin)/step),floori((world._half-margin)/step)):
			for xi in range(ceili((-world._half+margin)/step),floori((world._half-margin)/step)):
				var x:=xi*step;var z:=zi*step;var biome:=world.get_biome(x,z)
				if biome.max_axis_index()!=region or biome[region]<.65 or world.is_water(x,z):continue
				var h:=world._sample_height(x,z)
				var dx: float=(world._sample_height(x+12,z)-world._sample_height(x-12,z))/24
				var dz: float=(world._sample_height(x,z+12)-world._sample_height(x,z-12))/24
				if Vector2(dx,dz).length()>(.60 if region==1 else .23):continue
				var error:=0.0;var valid:=true
				for offset in [Vector2(-30,-30),Vector2(-30,30),Vector2(30,-30),Vector2(30,30)]:
					var q: Vector2=Vector2(x,z)+offset
					if world.get_biome(q.x,q.y).max_axis_index()!=region or world.is_water(q.x,q.y):valid=false;break
					error=maxf(error,absf(world._sample_height(q.x,q.y)-(h+dx*offset.x+dz*offset.y)))
				if not valid or error>(14.0 if region==1 else 6.0):continue
				var distance:=INF;var nearest:=Vector3.ZERO
				for p in supported_joins:
					var d:=Vector2(p.x-x,p.z-z).length()
					if d<distance:distance=d;nearest=p
				if distance<(35.0 if region==1 else 65.0) or distance>(240.0 if region==1 else 180.0):continue
				var foothill_penalty:=0.0
				if region==0:
					var rise:=0.0
					for offset in [Vector2(-70,0),Vector2(70,0),Vector2(0,-70),Vector2(0,70)]:rise=maxf(rise,world._sample_height(x+offset.x,z+offset.y)-h)
					if rise<5:foothill_penalty=20.0
				# Urban lots need modest crossfall in every biome. Mountain relief
				# remains around the town instead of becoming three-metre plinths.
				var town_grade:=.035
				candidates.append({"center":Vector3(x,h,z),"dx":clampf(dx,-town_grade,town_grade),"dz":clampf(dz,-town_grade,town_grade),"near":nearest,"score":error+Vector2(dx,dz).length()*15+distance*.02+foothill_penalty})
		candidates.sort_custom(func(a,b):return a.score<b.score)
		for candidate in candidates.slice(0,32):
			var center: Vector3=candidate.center
			var streets:=town_streets(center,float(candidate.dx),float(candidate.dz))
			if not _fits_existing_roads(world,streets):continue
			var connector:=_connect(world,center,candidate.near)
			if connector.is_empty():
				# Keep the same native network and try another nearby attachment,
				# rather than cutting the original shoulder to force a bad join.
				var joins: Array[Dictionary]=[]
				for p in supported_joins:
					if p.distance_to(candidate.near)<12 or p.distance_to(center)>260:continue
					var toward:=Vector2(center.x-p.x,center.z-p.z).normalized()
					var score:=p.distance_to(center)
					for offset in [4.0,8.0,12.0]:
						var h:=world._sample_height(p.x+toward.x*offset,p.z+toward.y*offset)
						score+=maxf(0,absf(h-p.y)-offset*world.road_max_grade)*18
					joins.append({"point":p,"score":score})
				joins.sort_custom(func(a,b):return a.score<b.score)
				var tried: Array[Vector3]=[]
				for entry in joins:
					var join: Vector3=entry.point
					var nearby:=false
					for previous in tried:
						if join.distance_to(previous)<12:nearby=true;break
					if nearby:continue
					tried.append(join);connector=_connect(world,center,join)
					if not connector.is_empty() or tried.size()>=8:break
			if connector.is_empty():continue
			connector=_start_at_street_edge(world,connector,candidate)
			if connector.is_empty():continue
			connector=_reuse_access(world,connector,access_nodes)
			if connector.is_empty():continue
			output.append({"path":connector,"kind":1,"width":6.4})
			for point in connector:
				var key:=Vector2i(roundi(point.x/world.cell_size),roundi(point.z/world.cell_size))
				access_nodes[key]=point
			world._regional_towns.append(center)
			world._settlement_grades.append(candidate)
			var zones: Array=["popular","tradicional","residencial","moderna"]
			for k in 4:
				var offset:=Vector3(-20 if k%2==0 else 20,0,-20 if k<2 else 20)
				world._district_patches.append({"center":center+offset,"region":region,"zone":zones[k],"radius":80.0})
			output.append_array(streets)
			print("Poblado regional conectado ",region," en ",center)
			break
	return output

static func _start_at_street_edge(world: TerrainWorld,path: PackedVector3Array,town: Dictionary) -> PackedVector3Array:
	# The grid already takes traffic from its boundary to its centre. Reuse
	# those streets, with an exact shared node on the perimeter.
	var center: Vector3=town.center
	var inside:=-1
	for i in path.size():
		if maxf(absf(path[i].x-center.x),absf(path[i].z-center.z))<=32.0:
			inside=i
	if inside<0 or inside>=path.size()-2:return PackedVector3Array()
	var outside:=path[inside+1]-center
	var offset:=Vector2(clampf(roundf(outside.x*.5)*2,-32,32),clampf(roundf(outside.z*.5)*2,-32,32))
	var portal:=center+Vector3(offset.x,float(town.dx)*offset.x+float(town.dz)*offset.y,offset.y)
	var section:=path.slice(inside+1)
	if Vector2(section[0].x-portal.x,section[0].z-portal.z).length()<.35:section[0]=portal
	else:section.insert(0,portal)
	return _grade_connector(world,section)

static func _fits_existing_roads(world: TerrainWorld,streets: Array) -> bool:
	# A street through a protected slope or deck would keep its asphalt
	# footprint while the existing road restores a different elevation.
	var native:=world.native_road_surface
	for street: Dictionary in streets:
		var path: PackedVector3Array=street.path
		var side:=PeruRoadLayout._corner_side(path,0)
		for p in path:
			for lateral in [-float(street.width)*.5,0.0,float(street.width)*.5]:
				var q: Vector3=p+side*lateral
				var ix:=clampi(roundi((q.x+world._half)/world.cell_size),0,world._n-1)
				var iz:=clampi(roundi((q.z+world._half)/world.cell_size),0,world._n-1)
				var influence:=native.influence[iz*world._n+ix]
				var ground:=world._sample_height(q.x,q.z)
				if absf(ground-p.y)*influence>.65 or native.height_at(q.x,q.z,ground)>ground+.35:
					return false
	return true

static func _reuse_access(world: TerrainWorld,path: PackedVector3Array,nodes: Dictionary) -> PackedVector3Array:
	# A second town can share the first access as soon as the routes meet.
	# Keep one physical corridor, even when both searches picked the same native road.
	if nodes.is_empty():return path
	var shared:=0
	for i in range(1,path.size()-1):
		var p:=path[i]
		var key:=Vector2i(roundi(p.x/world.cell_size),roundi(p.z/world.cell_size))
		if not nodes.has(key):continue
		var join: Vector3=nodes[key]
		if Vector2(p.x-join.x,p.z-join.z).length()>world.cell_size or world.is_water(join.x,join.z):continue
		if Vector2(p.x-join.x,p.z-join.z).length()<.05:shared+=1
		var section:=path.slice(0,i+1)
		section[-1]=join
		var graded:=_grade_connector(world,section)
		if not graded.is_empty():return graded
	return PackedVector3Array() if shared>=3 else path

static func _connect(world: TerrainWorld,center: Vector3,join: Vector3) -> PackedVector3Array:
	join.y=world._sample_height(join.x,join.z)
	var path:=_direct_access(world,center,join)
	if path.is_empty():
		path=world.generator.last_roads.find_drivable_path(world._heights,world._n,world.cell_size,Vector2(center.x,center.z),Vector2(join.x,join.z),world.road_max_grade)
	if path.size()<2:return PackedVector3Array()
	path[0]=center;path[-1]=join
	var attempted: Array[Vector3]=[]
	for i in range(1,path.size()-2):
		var p:=path[i]
		var x:=clampi(roundi((p.x+world._half)/world.cell_size),0,world._n-1)
		var z:=clampi(roundi((p.z+world._half)/world.cell_size),0,world._n-1)
		if world.native_road_surface.influence[z*world._n+x]<.9:continue
		var earlier:=world.native_road_surface.nearby_attachment(p)
		if not earlier.is_finite() or world.is_water(earlier.x,earlier.z):continue
		var repeated:=false
		for previous in attempted:
			if earlier.distance_to(previous)<3:repeated=true;break
		if repeated:continue
		attempted.append(earlier)
		earlier.y=world._sample_height(earlier.x,earlier.z)
		var section:=path.slice(0,i+1)
		if Vector2(earlier.x-p.x,earlier.z-p.z).length()<.35:section[-1]=earlier
		else:section.append(earlier)
		var connected:=_finish_connector(world,section)
		if not connected.is_empty():return connected
		if attempted.size()>=6:break
	return _finish_connector(world,path)

static func _direct_access(world: TerrainWorld,start: Vector3,end: Vector3) -> PackedVector3Array:
	var length:=Vector2(end.x-start.x,end.z-start.z).length()
	if length<2.0 or absf(end.y-start.y)>world.road_max_grade*length:
		return PackedVector3Array()
	var path:=PackedVector3Array()
	var count:=ceili(length/minf(world.cell_size,1.5))
	for i in range(count+1):
		var p:=start.lerp(end,float(i)/count)
		var ground:=world._sample_height(p.x,p.z)
		if absf(ground-p.y)>1.5 or world.is_water(p.x,p.z) or world.native_road_surface.height_at(p.x,p.z,ground)>ground+.35:
			return PackedVector3Array()
		path.append(p)
	return path

static func _finish_connector(world: TerrainWorld,path: PackedVector3Array) -> PackedVector3Array:
	var graded:=_grade_connector(world,_round_connector(world,path.duplicate()))
	return graded if not graded.is_empty() else _grade_connector(world,path)

static func town_streets(center: Vector3,dx: float,dz: float) -> Array:
	var streets: Array=[]
	for axis in 2:
		for lane in [-1,0,1]:
			var path:=PackedVector3Array()
			# The outer crossing is at 32 m. Continuing to 40 m created an
			# eight-metre dead stub beyond every perimeter junction.
			for k in range(-16,17):
				var local:=Vector2(k*2,lane*32) if axis==0 else Vector2(lane*32,k*2)
				path.append(Vector3(center.x+local.x,center.y+dx*local.x+dz*local.y,center.z+local.y))
			var avenue: bool=axis==0 and lane==0
			# End paint within the transverse street's half-width, including
			# the wide avenue whose round cap otherwise sticks out past it.
			streets.append({"path":path,"kind":2 if avenue else 3,"width":12.6 if avenue else 6.4,"junction_cap":3.2})
	return streets

static func _grade_connector(world: TerrainWorld,path: PackedVector3Array) -> PackedVector3Array:
	# Use the existing carriageway as fixed levels through the overlap, not
	# just at the endpoint. Grade each free interval with CG's own limiter.
	var native:=world.native_road_surface
	var fixed: Array[int]=[0]
	for i in range(1,path.size()-1):
		var p:=path[i]
		var x:=clampi(roundi((p.x+world._half)/world.cell_size),0,world._n-1)
		var z:=clampi(roundi((p.z+world._half)/world.cell_size),0,world._n-1)
		if native.influence[z*world._n+x]<.98:continue
		p.y=native.height_at(p.x,p.z,world._sample_height(p.x,p.z));path[i]=p;fixed.append(i)
	fixed.append(path.size()-1)
	for k in range(1,fixed.size()):
		var first:=fixed[k-1];var last:=fixed[k];var length:=0.0
		for i in range(first+1,last+1):length+=Vector2(path[i].x-path[i-1].x,path[i].z-path[i-1].z).length()
		var limit:=world.road_max_grade
		if last==first+1 and first>0:limit=maxf(limit,.35)
		if absf(path[last].y-path[first].y)>length*limit+.04:return PackedVector3Array()
		if last>first+1:
			var interval:=world._surface.grade_road_profile(path.slice(first,last+1),limit)
			for i in range(1,interval.size()-1):path[first+i]=interval[i]
	return path

static func _round_connector(world: TerrainWorld,path: PackedVector3Array) -> PackedVector3Array:
	# Same bounded Laplacian rounding used by RoadNetwork::_round_path. This
	# applies only to new connectors; native through-routes are never rewritten.
	var original:=path.duplicate()
	var limit:=maxf(8,world.cell_size*1.6)
	var passes:=clampi(ceili(2*pow(8/maxf(1,world.cell_size),2)),9,48)
	var fixed:=PackedByteArray();fixed.resize(path.size())
	var wet:=PackedByteArray();wet.resize(path.size())
	for i in path.size():
		var p:=path[i]
		var x:=clampi(roundi((p.x+world._half)/world.cell_size),0,world._n-1)
		var z:=clampi(roundi((p.z+world._half)/world.cell_size),0,world._n-1)
		fixed[i]=1 if world.native_road_surface.influence[z*world._n+x]>=.98 else 0
		wet[i]=1 if world.is_water(p.x,p.z) else 0
	for pass_index in passes:
		var previous:=path.duplicate()
		for i in range(1,path.size()-1):
			if fixed[i]!=0:continue
			var p:=previous[i]*.5+(previous[i-1]+previous[i+1])*.25
			if Vector2(p.x-original[i].x,p.z-original[i].z).length()>limit:continue
			if world.is_water(p.x,p.z)!=(wet[i]!=0):continue
			# Round the plan first. Rejecting a corner on its temporary terrain
			# height kept the grid staircase; CG grades the final rounded path next.
			path[i]=p
	for i in range(1,path.size()-1):
		var p:=path[i];p.y=world._sample_height(p.x,p.z);path[i]=p
	return path
