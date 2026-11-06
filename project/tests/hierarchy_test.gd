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
 if towns.size()!=4 or paths.size()<towns.size()-1: errors+=1
 if towns.is_empty():
  push_error("La red no tiene poblados")
  quit(1)
  return
 var low := Vector2(towns[0].x, towns[0].z)
 var high := low
 for town: Vector3 in towns:
  var point := Vector2(town.x, town.z)
  low = low.min(point)
  high = high.max(point)
 var span := high - low
 if span.x < 1536.0 * 0.55 or span.y < 1536.0 * 0.55: errors+=1
 var counts := [0,0,0,0]
 var router := RoadRouter.new()
 router.build(metadata)
 # Cuantas vias usan cada punto (a 10 cm, como RoadRouter): un cruce es un punto compartido.
 var uses := {}
 for road: Dictionary in metadata:
  counts[road.kind]+=1
  if road.width != [4.5,9.5,7.5,5.5][road.kind]: errors+=1
  for point: Vector3 in road.path:
   var key := Vector2i(roundi(point.x * 10), roundi(point.z * 10))
   uses[key] = uses.get(key, 0) + 1
 for road: Dictionary in metadata:
  var path: PackedVector3Array = road.path
  for point in path:
   if not point.is_finite() or absf(point.x)>768 or absf(point.z)>768: errors+=1
  # Fase 2: toda via que no es carretera sale de un punto de otra via (cruce exacto).
  if road.kind != 1:
   var joined := 0
   for point: Vector3 in [path[0], path[-1]]:
    if uses.get(Vector2i(roundi(point.x * 10), roundi(point.z * 10)), 0) > 1: joined += 1
   if joined == 0: errors+=1
  # Y el GPS llega a ella desde el primer pueblo.
  if router.road_path(towns[0], path[path.size() / 2]).is_empty(): errors+=1
 for town: Vector3 in towns:
  if router.road_path(towns[0], town).is_empty(): errors+=1
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
 print("Jerarquia: %d errores; vias por tipo: %s; cobertura X/Z: %s m" % [errors, str(counts), span])
 quit(0 if errors==0 else 1)
