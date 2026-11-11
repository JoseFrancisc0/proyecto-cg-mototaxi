extends SceneTree
var failures:=0
func check(value: bool,message: String) -> void:
	print("OK " if value else "FAIL ",message)
	if not value:failures+=1
func _initialize() -> void:
	var world:=TerrainWorld.new();world.generate_on_ready=false
	world.grid_size=16;world.cell_size=1;world._n=17;world._half=8
	world._heights.resize(289);world._heights.fill(.4)
	for x in 17:world._heights[11*17+x]=8
	var river:=PeruWaterSystem.new();river.world=world
	river.original_heights=world._heights.duplicate()
	river._levels.resize(289);river._levels.fill(-INF)
	river._channel_distance.resize(289);river._channel_distance.fill(INF)
	river._bank_weights.resize(289);river._bank_weights.fill(0)
	river._carve(Vector3(-5,1,0),Vector3(5,1,0),2,17)
	river._prepare_shore()
	check(is_equal_approx(river.surface_level_at(0,0),1),"El eje conserva el nivel del cauce")
	check(not is_finite(river.surface_level_at(0,-3)),"La banquina baja queda seca fuera del cauce")
	var edge:=river.surface_level_at(0,2.25,true)
	check(is_finite(edge) and edge<=1,"La orilla alta no levanta la superficie del río")
	for x in 17:world._heights[11*17+x]=12
	check(is_equal_approx(river.surface_level_at(0,2.25,true),edge),"Nivelar una orilla no cambia la altura del agua")
	river.free();world.free()
	print("RIVER_SHORE_RESULT ",failures)
	quit(failures)
