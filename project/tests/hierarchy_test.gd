extends SceneTree
func _initialize() -> void:
 var terrain := TerrainNoise.new()
 terrain.set_seed(147)
 terrain.configure_regions({"extent":1536.0})
 var config := {"hierarchical_roads":true,"num_points":8,"k_neighbors":2,"town_count":4}
 var roads := RoadNetwork.new()
 roads.generate_roads(terrain,1024,1.5,config)
 var paths: Array = roads.get_road_paths()
 var metadata: Array = roads.get_road_metadata()
 var towns: PackedVector3Array = roads.get_town_centers()
 var errors := 0
 if towns.size()!=4 or paths.size()<52: errors+=1
 var counts := [0,0,0,0]
 var reached: Array[Vector2] = [Vector2(towns[0].x,towns[0].z)]
 for road: Dictionary in metadata:
  counts[road.kind]+=1
  if road.width != [0.0,14.0,10.0,6.0][road.kind]: errors+=1
 for iteration in range(paths.size()):
  for path: PackedVector3Array in paths:
   var a := Vector2(path[0].x,path[0].z)
   var b := Vector2(path[-1].x,path[-1].z)
   if reached.has(a) and not reached.has(b): reached.append(b)
   if reached.has(b) and not reached.has(a): reached.append(a)
 for path: PackedVector3Array in paths:
  if not reached.has(Vector2(path[0].x,path[0].z)): errors+=1
  for point in path:
   if not point.is_finite() or absf(point.x)>768 or absf(point.z)>768: errors+=1
 var duplicate := RoadNetwork.new()
 duplicate.generate_roads(terrain,1024,1.5,config)
 if paths != duplicate.get_road_paths(): errors+=1
 var export_paths: Array = []
 for road: Dictionary in metadata:
  var points: Array = []
  for point: Vector3 in road.path: points.append([point.x,point.z])
  export_paths.append({"kind":road.kind,"points":points})
 var file := FileAccess.open("res://../output/s11_cgb/streets.json",FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(export_paths))
 print("Jerarquia: %d errores; carreteras/avenidas/calles: %s" % [errors,str(counts)])
 quit(0 if errors==0 else 1)
