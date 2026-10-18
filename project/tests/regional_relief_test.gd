extends SceneTree
func _initialize() -> void:
 var errors := 0
 for seed_value in [68,117,147]:
  var terrain := TerrainNoise.new()
  terrain.set_seed(seed_value)
  terrain.configure_regions({"extent":1536.0})
  var minimum := [INF,INF,INF]
  var maximum := [-INF,-INF,-INF]
  var sums := [0.0,0.0,0.0]
  var counts := [0,0,0]
  for z in range(-756,757,12):
   for x in range(-756,757,12):
    var w: Vector3 = terrain.get_biome_weights(x,z)
    var kind := w.max_axis_index()
    if w[kind]<0.9999: continue
    var height: float = terrain.get_height(x,z)
    minimum[kind]=minf(minimum[kind],height)
    maximum[kind]=maxf(maximum[kind],height)
    # Exclude transition slopes when comparing intrinsic relief.
    var pure := true
    for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
     if terrain.get_biome_weights(x+offset.x,z+offset.y)[kind]<0.9999: pure=false
    if not pure: continue
    var dx: float = (terrain.get_height(x+1,z)-terrain.get_height(x-1,z))*.5
    var dz: float = (terrain.get_height(x,z+1)-terrain.get_height(x,z-1))*.5
    sums[kind]+=Vector2(dx,dz).length()
    counts[kind]+=1
  if counts.min()<=0: errors+=1
  if not (maximum[0]<minimum[2] and maximum[2]<minimum[1]): errors+=1
  var slopes := [sums[0]/maxi(1,counts[0]),sums[1]/maxi(1,counts[1]),sums[2]/maxi(1,counts[2])]
  if not (slopes[1]>slopes[2] and slopes[2]>slopes[0]): errors+=1
  print("Relieve semilla %d: alturas min/max %s/%s; pendientes costa/sierra/selva %s" % [seed_value,str(minimum),str(maximum),str(slopes)])
 print("Jerarquia de relieve: %d errores" % errors)
 quit(0 if errors==0 else 1)
