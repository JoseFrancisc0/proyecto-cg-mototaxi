class_name PeruWaterSystem
extends Node3D
## Cauces mayores con ajuste local de lecho; el resto del relieve se conserva exactamente.
var world: TerrainWorld
var reaches: Array[Dictionary]=[]
var _buckets: Dictionary={}
var changed_cells:=0
var sea_level:=0.0
var original_heights:=PackedFloat32Array()
var _levels:=PackedFloat32Array()
var _channel_distance:=PackedFloat32Array()
var _shore_bed:=PackedFloat32Array()
var _bank_weights:=PackedFloat32Array()
var _wet_cells: Dictionary={}
const CELL:=64.0

func build(w: TerrainWorld) -> void:
	world=w
	name="RiosYMar"
	original_heights=world._heights.duplicate()
	_levels.resize(original_heights.size());_levels.fill(-INF)
	_channel_distance.resize(original_heights.size());_channel_distance.fill(INF)
	_bank_weights.resize(original_heights.size());_bank_weights.fill(0)
	var data:=world._surface.get_hydrology_data()
	var n:=int(data.get("samples",0))
	if n>1:
		var channels: PackedInt32Array=data.channels
		var accumulation: PackedFloat64Array=data.accumulation
		var receivers: PackedInt32Array=data.receivers
		var levels: PackedFloat64Array=data.water_levels
		var threshold:=maxf(float(world.generator.river_catchment),world.get_world_size()*world.get_world_size()*.01)
		var candidates:Array[int]=[]
		for i in channels.size():
			if int(data.lakes[i])!=0:
				var lx: float=(i%n)*world.cell_size-world._half;var lz: float=(i/n)*world.cell_size-world._half
				_levels[i]=minf(levels[i]+.025,world.native_road_surface.water_ceiling(lx,lz))
				_channel_distance[i]=0
				_bank_weights[i]=1
				var x:=i%n;var z:=i/n
				for dz in [-1,0]:
					for dx in [-1,0]:
						if x+dx>=0 and x+dx<n-1 and z+dz>=0 and z+dz<n-1:_wet_cells[Vector2i(x+dx,z+dz)]=true
			if channels[i]!=0 and receivers[i]>=0:candidates.append(i)
		candidates.sort_custom(func(a,b):return accumulation[a]>accumulation[b])
		var half:=world.get_world_size()*.5
		var visited:={}
		var upstream:={}
		var centres:={}
		for index in candidates:
			var receiver:=receivers[index]
			if not upstream.has(receiver) or accumulation[index]>accumulation[int(upstream[receiver])]:upstream[receiver]=index
		for index in candidates:
			var p:=_hydro_point(index,n,levels,half)
			var down:=_hydro_point(receivers[index],n,levels,half)
			var up:=_hydro_point(int(upstream.get(index,index)),n,levels,half)
			centres[index]=p*.5+(up+down)*.25
		for i in candidates:
			var j:=receivers[i]
			var a: Vector3=centres[i]
			var b: Vector3=centres.get(j,_hydro_point(j,n,levels,half))
			var flat:=Vector2(b.x-a.x,b.z-a.z).length()
			if flat<.1 or absf(a.y-b.y)/flat>.16:continue
			var biome:=world.get_biome(a.x,a.z).max_axis_index()
			var maximum:=42.0 if biome==2 else (13.0 if biome==0 else 10.0)
			var width:=clampf((5.5 if biome==2 else 3.2)*sqrt(accumulation[i]/threshold),minf(maximum,maxf(3.0,world.cell_size*.8)),maximum)
			var key:=Vector2i(roundi(a.x/4),roundi(a.z/4))
			if visited.has(key):continue
			visited[key]=true
			var reach:={"a":a,"b":b,"half_width":width,"region":biome}
			reaches.append(reach)
			_index(reach)
			_carve(a,b,width,n)
	_prepare_shore()
	print("Hidrografía: %d tramos, %d muestras ajustadas localmente"%[reaches.size(),changed_cells])

func _hydro_point(index: int,n: int,levels: PackedFloat64Array,half: float) -> Vector3:
	var x: float=(index%n)*world.cell_size-half;var z: float=(index/n)*world.cell_size-half
	return Vector3(x,minf(levels[index]+.10,world.native_road_surface.water_ceiling(x,z)),z)

func _carve(a: Vector3,b: Vector3,width: float,n: int) -> void:
	var half:=world.get_world_size()*.5
	var radius:=width+minf(10,width*.5)
	var x0:=maxi(0,floori((minf(a.x,b.x)-radius+half)/world.cell_size))
	var x1:=mini(n-1,ceili((maxf(a.x,b.x)+radius+half)/world.cell_size))
	var z0:=maxi(0,floori((minf(a.z,b.z)-radius+half)/world.cell_size))
	var z1:=mini(n-1,ceili((maxf(a.z,b.z)+radius+half)/world.cell_size))
	var aa:=Vector2(a.x,a.z);var bb:=Vector2(b.x,b.z)
	for z in range(z0,z1+1):
		for x in range(x0,x1+1):
			var p:=Vector2(x*world.cell_size-half,z*world.cell_size-half)
			var nearest:=Geometry2D.get_closest_point_to_segment(p,aa,bb)
			var distance:=p.distance_to(nearest)
			if distance>radius:continue
			var t:=clampf((nearest-aa).dot(bb-aa)/maxf((bb-aa).length_squared(),.001),0,1)
			var level:=lerpf(a.y,b.y,t)
			var index:=z*n+x
			var bank:=smoothstep(width,radius,distance)
			_bank_weights[index]=maxf(_bank_weights[index],1-bank)
			# Cut the bank without extending the water onto it. At overlapping
			# reaches the nearest axis owns the sample; lakes keep their level.
			if distance<=width:
				if distance<_channel_distance[index]:
					_channel_distance[index]=distance;_levels[index]=level
				for oz in [-1,0]:
					for ox in [-1,0]:
						if x+ox>=0 and x+ox<n-1 and z+oz>=0 and z+oz<n-1:_wet_cells[Vector2i(x+ox,z+oz)]=true
			var original:=original_heights[index]
			# Se dejan intactos altos paredones: el ensanche se limita al fondo del valle.
			var bank_limit:=maxf(18,width*.95)
			if original-level>bank_limit:continue
			var depth:=clampf(width*.10,1.0,4.5)
			var bed:=level-depth*clampf(1-pow(distance/width,2),.10,1)
			# Fade the excavation before the high-bank limit, instead of a vertical cut.
			var bank_weight:=1.0-smoothstep(bank_limit*.70,bank_limit,maxf(0,original-level))
			var height:=lerpf(original,lerpf(bed,original,bank),bank_weight)
			if height<world._heights[index]:
				if is_equal_approx(world._heights[index],original):changed_cells+=1
				world._heights[index]=height

func _apply_displacement() -> void:
	# The terrain mesh and physics use the actual height array; no vertex-only deformation.
	var material:=world.generator.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("local_channels_enabled",false)
		material.set_shader_parameter("rivers_enabled",false)
	for name in ["AguaGenerada"]:
		var native:=world.generator.get_node_or_null(name)
		if native:native.visible=false
	_rebuild_surface()
	_build_ocean()
	_build_bank_stones()

func _water_level(index: int) -> float:
	return _levels[index]

func bank_weight(index: int) -> float:
	return _bank_weights[index]

func _prepare_shore() -> void:
	_shore_bed=world._heights.duplicate()
	for cell: Vector2i in _wet_cells:
		var i:=cell.y*world._n+cell.x
		var corners: Array[int]=[i,i+1,i+world._n,i+world._n+1]
		var nearby:=INF
		for index in corners:
			if is_finite(_levels[index]):nearby=minf(nearby,_levels[index])
		for index in corners:
			# A high dry bank must not pull the interpolated river uphill.
			if not is_finite(_levels[index]):_shore_bed[index]=minf(_shore_bed[index],nearby)

func _shore_level(index: int) -> float:
	var level:=_water_level(index)
	if is_finite(level):return level
	# A dry corner clips the shoreline. Raising a later road or town here
	# must not also lift the river in the wet part of the triangle.
	return minf(_shore_bed[index],world._heights[index])-.1

func _rebuild_surface() -> void:
	var previous:=get_node_or_null("CaucesMayores")
	if previous:remove_child(previous);previous.queue_free()
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices:=0
	for cell: Vector2i in _wet_cells:
		var i:=cell.y*world._n+cell.x
		# Match the terrain's clockwise winding so back-face lighting cannot blacken water.
		for triangle in [[i,i+1,i+world._n],[i+1,i+world._n+1,i+world._n]]:
			if not is_finite(_levels[triangle[0]]) and not is_finite(_levels[triangle[1]]) and not is_finite(_levels[triangle[2]]):continue
			var polygon: Array[Vector3]=[];var depths: Array[float]=[]
			for index: int in triangle:
				var level:=_shore_level(index)
				polygon.append(Vector3((index%world._n)*world.cell_size-world._half,level,(index/world._n)*world.cell_size-world._half))
				depths.append(level-world._heights[index]-.025)
			var clipped: Array[Vector3]=[]
			for j in 3:
				var k:=(j+1)%3
				if depths[j]>=0:clipped.append(polygon[j])
				if (depths[j]>=0)!=(depths[k]>=0):clipped.append(polygon[j].lerp(polygon[k],depths[j]/(depths[j]-depths[k])))
			if clipped.size()<3:continue
			for j in range(1,clipped.size()-1):
				for point: Vector3 in [clipped[0],clipped[j],clipped[j+1]]:
					var biome:=world.get_biome(point.x,point.z)
					var color:=Color("416a6d").lerp(Color("655340"),smoothstep(.25,.8,biome.z))
					color.a=clampf((point.y-world._sample_height(point.x,point.z))/.9,0,1)
					st.set_color(color)
					st.set_normal(Vector3.UP);st.set_uv(Vector2(point.x,point.z));st.add_vertex(point);vertices+=1
	if vertices==0:return
	var visual:=MeshInstance3D.new();visual.name="CaucesMayores";visual.mesh=st.commit()
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/peru_water.gdshader");visual.material_override=material;add_child(visual)

func _build_bank_stones() -> void:
	var transforms: Array[Transform3D]=[]
	var rng:=RandomNumberGenerator.new();rng.seed=world.world_seed+574
	for reach: Dictionary in reaches:
		if int(reach.region)==2:continue
		var a: Vector3=reach.a;var b: Vector3=reach.b
		var side:=(b-a).cross(Vector3.UP).normalized()
		for j in range(maxi(1,ceili(a.distance_to(b)/5.0))):
			for sign_value in [-1.0,1.0]:
				var p: Vector3=a.lerp(b,rng.randf())+side*sign_value*float(reach.half_width)*rng.randf_range(.70,1.13)
				var level:=surface_level_at(p.x,p.z,true)
				p.y=world.get_height(p.x,p.z)
				if not is_finite(level) or absf(p.y-level)>1.2 or world.get_offroad_amount(p.x,p.z)<.98:continue
				var radius:=rng.randf_range(.12,.48)
				transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(radius*1.3,radius*.75,radius)),p+Vector3.UP*radius*.20))
	if transforms.is_empty():return
	var sphere:=SphereMesh.new();sphere.radius=1;sphere.height=2;sphere.radial_segments=9;sphere.rings=5
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("77776a");mat.roughness=.96;sphere.material=mat
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=sphere;multi.instance_count=transforms.size()
	for i in transforms.size():multi.set_instance_transform(i,transforms[i])
	var node:=MultiMeshInstance3D.new();node.name="PiedrasDeRibera";node.multimesh=multi;node.visibility_range_end=220;add_child(node)

func _index(reach: Dictionary) -> void:
	var width:float=reach.half_width+2
	for z in range(floori((minf(reach.a.z,reach.b.z)-width)/CELL),ceili((maxf(reach.a.z,reach.b.z)+width)/CELL)+1):
		for x in range(floori((minf(reach.a.x,reach.b.x)-width)/CELL),ceili((maxf(reach.a.x,reach.b.x)+width)/CELL)+1):
			var key:=Vector2i(x,z)
			if not _buckets.has(key):_buckets[key]=[]
			_buckets[key].append(reach)

func water_at(x: float,z: float) -> Dictionary:
	var p:=Vector2(x,z)
	var level:=surface_level_at(x,z)
	if not is_finite(level):return {}
	for reach: Dictionary in _buckets.get(Vector2i(floori(x/CELL),floori(z/CELL)),[]):
		var a:=Vector2(reach.a.x,reach.a.z);var b:=Vector2(reach.b.x,reach.b.z)
		var nearest:=Geometry2D.get_closest_point_to_segment(p,a,b)
		if p.distance_to(nearest)<=float(reach.half_width):return reach
	return {"a":Vector3(x,level,z),"b":Vector3(x+world.cell_size,level,z),"half_width":world.cell_size,"region":world.get_biome(x,z).max_axis_index()}

func surface_level_at(x: float,z: float,include_dry_banks:=false) -> float:
	var fx:=clampf((x+world._half)/world.cell_size,0,world._n-1.001)
	var fz:=clampf((z+world._half)/world.cell_size,0,world._n-1.001)
	var ix:=int(fx);var iz:=int(fz);var tx:=fx-ix;var tz:=fz-iz
	if not _wet_cells.has(Vector2i(ix,iz)):return -INF
	var i:=iz*world._n+ix
	var a:=_water_level(i);var b:=_water_level(i+1);var c:=_water_level(i+world._n);var d:=_water_level(i+world._n+1)
	# Use the same triangle and dry-corner clipping as the visible water mesh.
	if not is_finite(b) and not is_finite(c) and not is_finite(a if tx+tz<=1 else d):return -INF
	if not is_finite(a):a=_shore_level(i)
	if not is_finite(b):b=_shore_level(i+1)
	if not is_finite(c):c=_shore_level(i+world._n)
	if not is_finite(d):d=_shore_level(i+world._n+1)
	var level:=a+tx*(b-a)+tz*(c-a) if tx+tz<=1 else d+(1-tx)*(c-d)+(1-tz)*(b-d)
	return level if include_dry_banks or level>world._sample_height(x,z)+.025 else -INF

func blockers() -> Array:
	var out:=[]
	for reach in reaches:out.append([reach.a.x,reach.a.z,reach.half_width+3])
	return out

func _build_ocean() -> void:
	var half:=world.get_world_size()*.5
	sea_level=INF
	for height in original_heights:sea_level=minf(sea_level,height-1.0)
	var extent:=maxf(2000,world.get_world_size())
	var sea:=SurfaceTool.new();sea.begin(Mesh.PRIMITIVE_TRIANGLES);sea.set_color(Color("205b71"))
	for side in 4:
		var basis:=Basis(Vector3.UP,side*PI*.5)
		_quad(sea,basis*Vector3(-half,sea_level,half),basis*Vector3(half,sea_level,half),basis*Vector3(half+extent,sea_level,half+extent),basis*Vector3(-half-extent,sea_level,half+extent))
	var mesh:=MeshInstance3D.new();mesh.name="OceanoEnElHorizonte";mesh.mesh=sea.commit()
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/peru_water.gdshader");mesh.material_override=material;add_child(mesh)
	# Talud exterior y playa al pie; no se cambia ninguna montaña del mapa para cerrar sus bordes.
	var cliffs:=SurfaceTool.new();cliffs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in 4:
		var basis:=Basis(Vector3.UP,side*PI*.5)
		for k in range(0,ceili(half*2),8):
			var a:=basis*Vector3(-half+k,0,half);var b:=basis*Vector3(minf(half,-half+k+8),0,half)
			a.y=world.get_height(a.x,a.z);b.y=world.get_height(b.x,b.z)
			var out:=basis*Vector3(0,0,8)
			var c:=b+out;c.y=sea_level-.5
			var d:=a+out;d.y=sea_level-.5
			_quad(cliffs,a,b,c,d)
	var rock:=MeshInstance3D.new();rock.mesh=cliffs.commit();rock.name="AcantiladosDelBorde"
	var sand:=StandardMaterial3D.new();sand.albedo_color=Color("9a8d73");sand.roughness=.98;sand.cull_mode=BaseMaterial3D.CULL_DISABLED
	rock.material_override=sand;add_child(rock)

func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	for p in [a,c,b,a,d,c]:st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
