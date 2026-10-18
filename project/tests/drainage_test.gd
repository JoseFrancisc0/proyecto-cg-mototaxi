extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
 if not ok:
  failures += 1
  push_error(message)
func _initialize() -> void:
 var terrain := TerrainNoise.new()
 terrain.set_seed(147)
 terrain.configure_regions({"extent":512.0})
 var config := {"hydrology_enabled":true,"river_catchment":2000.0,"hierarchical_roads":true,"num_points":8,"k_neighbors":2,"town_count":3,"max_lakes":100,"max_lake_area":1000000.0,"erosion_enabled":true,"erosion_levels":0,"erosion_fluvial":4,"erosion_thermal":2,"erosion_deposition":2}
 var builder := TerrainMesh.new()
 var roads := RoadNetwork.new()
 var mesh := builder.generate_mesh(terrain,roads,128,4.0,config)
 var field: Dictionary = builder.get_hydrology_data()
 var n: int = field.samples
 var receiver: PackedInt32Array = field.receivers
 var levels: PackedFloat64Array = field.water_levels
 var accumulation: PackedFloat64Array = field.accumulation
 var channels: PackedInt32Array = field.channels
 var protected_water: PackedInt32Array = field.protected_water
 # Regression: water/bridges must face up using Godot clockwise fronts.
 for surface: ArrayMesh in [builder.get_water_mesh(), builder.get_bridge_mesh()]:
  if surface == null or surface.get_surface_count() == 0: continue
  var geometry := surface.surface_get_arrays(0)
  var points: PackedVector3Array = geometry[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array = geometry[Mesh.ARRAY_NORMAL]
  for t in range(0, points.size(), 3):
   var cross := (points[t+1]-points[t]).cross(points[t+2]-points[t])
   check(cross.y < 0.0, "Agua y puentes deben usar caras superiores horarias")
   check(normals[t].y > 0.0, "Normales de agua y puentes hacia arriba")
   if surface == builder.get_water_mesh(): check(normals[t].y > 0.97, "El agua no debe formar cortinas verticales sobre laderas")
 var outgoing := 0.0
 var channel_count := 0
 for i in receiver.size():
  if receiver[i] < 0:
   outgoing += accumulation[i]
   check(i % n == 0 or i % n == n-1 or i/n == 0 or i/n == n-1,"La salida debe estar en el borde")
  else:
   var j := receiver[i]
   check(levels[j] < levels[i],"El agua debe bajar: sin ciclos ni cauces ascendentes")
   check(accumulation[j] > 0.0,"El receptor tiene aporte; el flujo puede repartirse entre varios vecinos")
   if channels[i] != 0: check(channels[j] != 0,"Continuidad de cauce hasta la salida")
  if channels[i] != 0: channel_count += 1
 check(absf(outgoing - n*n*16.0)<0.01,"Conservacion de toda el area aportante")
 check(channel_count>0,"Hay cauces")
 check(builder.get_water_mesh().get_surface_count()>0,"Superficie visible de agua")
 var control := config.duplicate()
 control.num_points=0
 var bare_builder := TerrainMesh.new()
 var bare := bare_builder.generate_mesh(terrain,RoadNetwork.new(),128,4.0,control)
 var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var bare_vertices: PackedVector3Array = bare.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 for i in vertices.size():
  if protected_water[i] != 0:
   check(vertices[i].is_equal_approx(bare_vertices[i]),"Los caminos no rellenan cauces ni lagos")
  check(vertices[i].is_finite(),"Geometria finita")
 check(builder.get_bridge_mesh().get_surface_count()>0,"Cruces elevados presentes")
 if builder.get_bridge_mesh().get_surface_count()>0:
  var decks: PackedVector3Array = builder.get_bridge_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  for p in decks: check(p.is_finite(),"Puente finito")
 check(roads.get_road_count()>0,"Red vial generada tras la erosion")
 var junctions := {}
 for path: PackedVector3Array in roads.get_road_paths():
  for p: Vector3 in [path[0],path[-1]]:
   var key := Vector2i(roundi(p.x*100),roundi(p.z*100))
   if junctions.has(key): check(absf(junctions[key]-p.y)<0.001,"Cruces viales a la misma altura")
   else: junctions[key]=p.y
 check(builder.get_drainage(0,0)>0,"API publica drenaje real")
 print("Drenaje integrado: %d errores, %d celdas de cauce" % [failures,channel_count])
 quit(0 if failures==0 else 1)
