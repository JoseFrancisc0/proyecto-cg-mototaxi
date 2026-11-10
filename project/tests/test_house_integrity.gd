extends SceneTree
var failures:=0
func _initialize() -> void:_run.call_deferred()
func check(ok: bool,message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok:failures+=1
class FlatWorld extends TerrainWorld:
	func get_height(_x: float,_z: float) -> float:return 0.0
	func is_water(_x: float,_z: float) -> bool:return false
func _run() -> void:
	var flat:=FlatWorld.new()
	var short:=PeruHouseAccess.plan(flat,Vector3.ZERO,Vector3(0,.40,2.8))
	check(not short.is_empty() and float(short.riser)<=.18,"Acceso corto con contrahuellas limitadas")
	check(PeruHouseAccess.plan(flat,Vector3.ZERO,Vector3(0,12,5)).is_empty(),"Se rechaza una escalera imposible en vez de dibujar una pared escalonada")
	check(PeruHouseAccess.plan(flat,Vector3.ZERO,Vector3(0,2.5,3)).is_empty(),"Se rechaza un acceso sin espacio para huellas y descansos")
	check(PeruHouseAccess.plan(flat,Vector3.ZERO,Vector3(0,.4,25)).is_empty(),"No se crean escaleras individuales de decenas de metros")
	flat.free()
	var world:=TerrainWorld.new();world.generate_on_ready=false;world.use_editor_scene=false;world.grid_size=192;world.cell_size=6;world.erosion_enabled=false;world.vegetation_enabled=false;root.add_child(world);world.generate(42)
	var valid:=true;var accepted:=0;var maximum:=0.0;var unsupported:=0
	for house: Dictionary in world.houses.houses:
		if not house.has("access") or house.access.is_empty():valid=false;continue
		accepted+=1
		maximum=maxf(maximum,float(house.access.rise))
		if float(house.access.riser)>.1801 or float(house.access.run)>9.001:valid=false
		var entry: Vector3=Transform3D(Basis(Vector3.UP,float(house.yaw)),house.position)*TerrainHouses.load_model(world.houses._models[int(house.model)].model).entrance
		if entry.distance_to(house.access.entrance)>.02:valid=false
		for block: Transform3D in house.access.blocks:
			var top:=block.origin.y+block.basis.y.length()*.5
			var ground:=world.get_height(block.origin.x,block.origin.z)
			if top-ground>.851 or top<ground-.121:unsupported+=1
	print("HOUSE_ACCESS_COUNT ",accepted," maximum_rise=",maximum," unsupported=",unsupported)
	check(accepted>20,"El mapa mantiene viviendas con accesos válidos")
	check(valid,"Los accesos llegan al punto de entrada de su modelo y conservan proporciones caminables")
	check(unsupported==0,"No aparecen accesos suspendidos sobre muros altos")
	var viewer: Control=load("res://scenes/house_study_viewer.tscn").instantiate();root.add_child(viewer)
	await process_frame
	check(viewer._entries.size()==TerrainHouses.MODELS.size(),"El visor individual incluye todos los modelos activos")
	viewer.queue_free();world.queue_free()
	print("HOUSE_INTEGRITY_RESULT ",failures);quit(failures)
