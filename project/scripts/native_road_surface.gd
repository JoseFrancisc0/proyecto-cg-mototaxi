class_name NativeRoadSurface
extends RefCounted
## Preserve the CG generator's graded terrain through later town/water passes.
var heights:=PackedFloat32Array()
var protected_heights:=PackedFloat32Array()
var _bridge_bed:=PackedByteArray()
var influence:=PackedFloat32Array()
var roads: Array=[]
var _water_buckets:={}
var _decks:={}
var _n:=0
var _cell:=1.0
var _half:=0.0

func capture(world: TerrainWorld) -> void:
	_n=world._n;_cell=world.cell_size;_half=world._half
	heights=world._heights.duplicate()
	protected_heights=heights.duplicate()
	_bridge_bed.resize(heights.size());_bridge_bed.fill(0)
	influence.resize(heights.size());influence.fill(0)
	roads=world.generator.last_roads.get_road_metadata().duplicate(true)
	var mesh:=world._surface.get_bridge_mesh()
	if mesh:
		for surface in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices=arrays[Mesh.ARRAY_INDEX]
			var indexed: bool=indices!=null and indices.size()>0
			var count: int=(indices.size() if indexed else vertices.size())/3
			for i in count:
				var triangle: Array[Vector3]=[]
				for j in 3:triangle.append(vertices[indices[i*3+j] if indexed else i*3+j])
				var a:=triangle[0];var b:=triangle[1];var c:=triangle[2]
				for z in range(floori(minf(a.z,minf(b.z,c.z))/8),floori(maxf(a.z,maxf(b.z,c.z))/8)+1):
					for x in range(floori(minf(a.x,minf(b.x,c.x))/8),floori(maxf(a.x,maxf(b.x,c.x))/8)+1):
						var key:=Vector2i(x,z)
						if not _decks.has(key):_decks[key]=[]
						_decks[key].append(triangle)
	for road: Dictionary in roads:
		road["native"]=true
		var path: PackedVector3Array=road.path
		var core:=float(road.width)*.5+world.cell_size*1.5
		var radius:=core+maxf(6,world.generator.road_fade)
		for j in range(1,path.size()):
			var a:=Vector2(path[j-1].x,path[j-1].z);var b:=Vector2(path[j].x,path[j].z)
			for bz in range(floori((minf(a.y,b.y)-96)/64),floori((maxf(a.y,b.y)+96)/64)+1):
				for bx in range(floori((minf(a.x,b.x)-96)/64),floori((maxf(a.x,b.x)+96)/64)+1):
					var key:=Vector2i(bx,bz)
					if not _water_buckets.has(key):_water_buckets[key]=[]
					_water_buckets[key].append([path[j-1],path[j],float(road.width)*.5])
			for z in range(maxi(0,floori((minf(a.y,b.y)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.y,b.y)+radius+world._half)/world.cell_size)+1)):
				for x in range(maxi(0,floori((minf(a.x,b.x)-radius+world._half)/world.cell_size)),mini(world._n,ceili((maxf(a.x,b.x)+radius+world._half)/world.cell_size)+1)):
					var p:=Vector2(x*world.cell_size-world._half,z*world.cell_size-world._half)
					var distance:=p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))
					var index:=z*world._n+x
					influence[index]=maxf(influence[index],1-smoothstep(core,radius,distance))
	# A bridge preserves its deck, not the river bed beneath it. Protecting that
	# bed as if it were asphalt would dam a widened channel at the crossing.
	for i in influence.size():
		if influence[i]<=0:continue
		var x: float=(i%_n)*_cell-_half;var z: float=(i/_n)*_cell-_half
		if height_at(x,z,heights[i])>heights[i]+.65:_bridge_bed[i]=1

func restore(world: TerrainWorld) -> void:
	for i in heights.size():
		if influence[i]>0:world._heights[i]=lerpf(world._heights[i],protected_heights[i],influence[i])

func restore_after_water(world: TerrainWorld) -> void:
	for i in heights.size():
		if influence[i]>0 and _bridge_bed[i]==0:world._heights[i]=lerpf(world._heights[i],heights[i],influence[i])
	# Town earthworks must preserve the resulting bed too; otherwise a town
	# can push isolated vertices up through a protected native bridge.
	protected_heights=world._heights.duplicate()

func height_at(x: float,z: float,ground: float) -> float:
	var height:=ground
	for triangle: Array in _decks.get(Vector2i(floori(x/8),floori(z/8)),[]):
		var a: Vector3=triangle[0];var b: Vector3=triangle[1];var c: Vector3=triangle[2]
		var denominator: float=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(denominator)<.000001:continue
		var u: float=((b.z-c.z)*(x-c.x)+(c.x-b.x)*(z-c.z))/denominator
		var v: float=((c.z-a.z)*(x-c.x)+(a.x-c.x)*(z-c.z))/denominator
		var w:=1-u-v
		if minf(u,minf(v,w))>=-.00001:height=maxf(height,u*a.y+v*b.y+w*c.y)
	return height

func nearby_attachment(point: Vector3) -> Vector3:
	# Return an original road vertex so the access shares a navigation node
	# with the existing road. Do not attach to a bed under an elevated deck.
	var best:=Vector3(INF,INF,INF);var distance:=INF
	var p:=Vector2(point.x,point.z)
	for segment: Array in _water_buckets.get(Vector2i(floori(p.x/64),floori(p.y/64)),[]):
		for node: Vector3 in [segment[0],segment[1]]:
			var d:=p.distance_to(Vector2(node.x,node.z))
			if d>=distance or d>float(segment[2])+_cell:continue
			var ground:=_ground_height(node.x,node.z)
			if absf(ground-node.y)>.35 or height_at(node.x,node.z,ground)-ground>.35:continue
			best=node;distance=d
	return best

func water_ceiling(x: float,z: float) -> float:
	# Adapt widened rivers to existing roads, never raise the road to fit the water.
	var ceiling:=INF;var p:=Vector2(x,z)
	for segment: Array in _water_buckets.get(Vector2i(floori(x/64),floori(z/64)),[]):
		var a: Vector3=segment[0];var b: Vector3=segment[1]
		var delta:=Vector2(b.x-a.x,b.z-a.z)
		var t:=clampf((p-Vector2(a.x,a.z)).dot(delta)/maxf(.001,delta.length_squared()),0,1)
		var distance:=p.distance_to(Vector2(a.x,a.z)+delta*t)
		if distance>90:continue
		# The flat cap covers even the widest Amazonian reach. Its approaches
		# blend over distance rather than introducing a vertical water step.
		var q:=Vector2(a.x,a.z)+delta*t
		var road_height:=height_at(q.x,q.y,_ground_height(q.x,q.y))
		ceiling=minf(ceiling,road_height-2.4+maxf(0,distance-float(segment[2])-44)*.08)
	return ceiling

func _ground_height(x: float,z: float) -> float:
	var fx:=clampf((x+_half)/_cell,0,_n-1);var fz:=clampf((z+_half)/_cell,0,_n-1)
	var ix:=mini(int(fx),_n-2);var iz:=mini(int(fz),_n-2)
	var tx:=fx-ix;var tz:=fz-iz;var i:=iz*_n+ix
	if tx+tz<=1:return heights[i]+tx*(heights[i+1]-heights[i])+tz*(heights[i+_n]-heights[i])
	return heights[i+_n+1]+(1-tx)*(heights[i+_n]-heights[i+_n+1])+(1-tz)*(heights[i+1]-heights[i+_n+1])

func lit_deck_mesh(source: Mesh,terrain: Mesh,world: TerrainWorld) -> ArrayMesh:
	# Keep every native triangle; supply the same sky-visibility attribute used
	# by the terrain material, which the original plain-colour decks lacked.
	var sky=terrain.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(1,SurfaceTool.CUSTOM_R_FLOAT)
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices=arrays[Mesh.ARRAY_INDEX]
		var count: int=indices.size() if indices!=null and indices.size()>0 else vertices.size()
		for i in count:
			var index: int=indices[i] if indices!=null and indices.size()>0 else i
			var p:=vertices[index]
			var x:=clampi(roundi((p.x+world._half)/world.cell_size),0,world._n-1)
			var z:=clampi(roundi((p.z+world._half)/world.cell_size),0,world._n-1)
			var offset: int=(z*world._n+x)*4
			var visibility:=.75
			if sky is PackedFloat32Array and z*world._n+x<sky.size():visibility=sky[z*world._n+x]
			elif sky is PackedByteArray and offset+4<=sky.size():visibility=sky.decode_float(offset)
			st.set_custom(1,Color(visibility,0,0,0))
			st.set_normal(normals[index]);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	return st.commit()
