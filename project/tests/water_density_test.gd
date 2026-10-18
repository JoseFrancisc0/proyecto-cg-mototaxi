extends SceneTree
func _initialize() -> void:
 var terrain := TerrainNoise.new()
 terrain.set_seed(117)
 terrain.configure_regions({"extent":1536.0})
 var cfg := {"hydrology_enabled":true,"num_points":0,"erosion_enabled":false,"river_catchment":12000.0}
 var before := TerrainMesh.new()
 var before_mesh := before.generate_mesh(terrain,RoadNetwork.new(),256,6.0,cfg)
 var old: Dictionary = before.get_hydrology_data()
 cfg.river_catchment=60000.0
 var after := TerrainMesh.new()
 var after_mesh := after.generate_mesh(terrain,RoadNetwork.new(),256,6.0,cfg)
 var field: Dictionary = after.get_hydrology_data()
 var errors := 0
 var old_count := 0
 var new_count := 0
 for i in field.channels.size():
  old_count+=old.channels[i]
  new_count+=field.channels[i]
 if new_count>=old_count: errors+=1
 if field.receivers != old.receivers or field.accumulation != old.accumulation: errors+=1
 var components := 0
 # No arbitrary flooding or quotas: all closed pits must now have an outlet.
 for value in field.lakes:
  if value!=0: errors+=1
 if before_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != after_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: errors+=1
 for i in field.receivers.size():
  if i%257!=0 and i%257!=256 and i/257!=0 and i/257!=256:
   if field.receivers[i]<0: errors+=1
 print("Densidad de agua: %d errores; cauce %d -> %d celdas; %d lagunas" % [errors,old_count,new_count,components])
 quit(0 if errors==0 else 1)
