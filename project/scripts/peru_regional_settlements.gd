class_name PeruRegionalSettlements
extends RefCounted
## Add connected settlements on buildable Andean/Amazonian ground, not only coastal flats.
static func extend(world: TerrainWorld,raw: Array) -> Array:
	var output:=raw.duplicate();var all_points:=PackedVector3Array()
	for road: Dictionary in raw:
		for p: Vector3 in road.path:all_points.append(p)
	if all_points.is_empty():return output
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
				if Vector2(dx,dz).length()>.23:continue
				var error:=0.0;var valid:=true
				for offset in [Vector2(-30,-30),Vector2(-30,30),Vector2(30,-30),Vector2(30,30)]:
					var q: Vector2=Vector2(x,z)+offset
					if world.get_biome(q.x,q.y).max_axis_index()!=region or world.is_water(q.x,q.y):valid=false;break
					error=maxf(error,absf(world._sample_height(q.x,q.y)-(h+dx*offset.x+dz*offset.y)))
				if not valid or error>6:continue
				var distance:=INF;var nearest:=Vector3.ZERO
				for j in range(0,all_points.size(),4):
					var p:=all_points[j];var d:=Vector2(p.x-x,p.z-z).length()
					if d<distance:distance=d;nearest=p
				if distance<65 or distance>180:continue
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
		for candidate in candidates.slice(0,16):
			var center: Vector3=candidate.center;var nearest: Vector3=candidate.near
			var connector: PackedVector3Array=world.generator.last_roads.find_drivable_path(world._heights,world._n,world.cell_size,Vector2(center.x,center.z),Vector2(nearest.x,nearest.z),.44)
			if connector.size()<2:continue
			connector[0]=center;connector[connector.size()-1]=nearest
			output.append({"path":connector,"kind":1,"width":6.4})
			world._regional_towns.append(center)
			world._settlement_grades.append(candidate)
			var zones: Array=["popular","tradicional","residencial","moderna"]
			for k in 4:
				var offset:=Vector3(-20 if k%2==0 else 20,0,-20 if k<2 else 20)
				world._district_patches.append({"center":center+offset,"region":region,"zone":zones[k],"radius":80.0})
			for axis in 2:
				for lane in [-1,0,1]:
					var path:=PackedVector3Array()
					for k in range(-20,21):
						var local:=Vector2(k*2,lane*32) if axis==0 else Vector2(lane*32,k*2)
						path.append(Vector3(center.x+local.x,center.y+float(candidate.dx)*local.x+float(candidate.dz)*local.y,center.z+local.y))
					output.append({"path":path,"kind":3,"width":6.4})
			print("Poblado regional conectado ",region," en ",center)
			break
	return output
