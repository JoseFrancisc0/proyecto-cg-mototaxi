extends SceneTree
func _initialize() -> void:
	var failures:=0
	var box:=BoxMesh.new();box.size=Vector3(1,2,1)
	var arrays:=box.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():vertices[i]+=Vector3(8,0,0)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var buffer:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0,1,1,1,1,0,0,0,0])
	var grid:=TerrainVegetation._blocker_grid([[8.0,0.0,1.5]])
	if TerrainVegetation._remove_blocked(buffer,grid).size()!=20:failures+=1
	if not TerrainVegetation._remove_blocked(buffer,grid,mesh).is_empty():failures+=1
	var bridge:=PeruBridges.new();var beams: Array[Transform3D]=[]
	var a:=Vector3(1,2,3);var b:=Vector3(4,6,9)
	bridge._beam(a,b,.2,.3,beams)
	var basis:=beams[0].basis
	if absf(basis.z.length()-a.distance_to(b))>.001:failures+=1
	if absf(basis.x.normalized().dot(basis.z.normalized()))>.001:failures+=1
	bridge.free()
	print("PERU_GEOMETRY_RESULT ",failures)
	quit(failures)
