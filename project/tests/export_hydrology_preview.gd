extends SceneTree
func _initialize() -> void:
 var terrain := TerrainNoise.new()
 terrain.set_seed(147)
 terrain.configure_regions({"extent":1536.0})
 var cfg := {"hydrology_enabled":true,"river_catchment":60000.0,"hierarchical_roads":true,"num_points":8,"k_neighbors":2,"town_count":4,"erosion_enabled":false}
 var roads := RoadNetwork.new()
 var builder := TerrainMesh.new()
 var start := Time.get_ticks_msec()
 var mesh := builder.generate_mesh(terrain,roads,1024,1.5,cfg)
 var data := {"side":257,"extent":1536,"heights":[],"colors":[],"water":[],"roads":[],"seconds":(Time.get_ticks_msec()-start)/1000.0}
 var arrays := mesh.surface_get_arrays(0)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
 var field: Dictionary = builder.get_hydrology_data()
 for z in range(0,1025,4):
  for x in range(0,1025,4):
   var i := z*1025+x
   data.heights.append(vertices[i].y)
   data.colors.append([colors[i].r,colors[i].g,colors[i].b])
   data.water.append(field.protected_water[i])
 for road: Dictionary in roads.get_road_metadata():
  var path := []
  for p: Vector3 in road.path: path.append([p.x,p.y,p.z])
  data.roads.append({"kind":road.kind,"path":path})
 var file := FileAccess.open("res://../output/s11_cgb/hydrology_preview.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(data))
 print("Apertura: profundidad maxima %.2f, volumen %.2f" % [field.breach_max_depth,field.breach_volume])
 print("Mapa completo T0 y drenaje: %.2f s; %d tramos" % [data.seconds,roads.get_road_count()])
 quit()
