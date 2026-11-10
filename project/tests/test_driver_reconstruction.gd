extends SceneTree
var failures:=0
func check(value: bool,message: String) -> void:
	print("OK " if value else "FAIL ",message)
	if not value:failures+=1
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var model:=DriverAvatar.load_avatar(DriverAvatar.DEFAULT_PATH)
	check(model!=null,"La reconstrucción predeterminada se puede abrir")
	if model==null:
		quit(1)
		return
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	var triangles:=0
	var texture_size:=0
	for instance: MeshInstance3D in meshes:
		for surface in instance.mesh.get_surface_count():
			triangles+=instance.mesh.surface_get_array_index_len(surface)/3
			var mat:=instance.get_active_material(surface) as StandardMaterial3D
			if mat and mat.albedo_texture:texture_size=maxi(texture_size,mat.albedo_texture.get_width())
	check(meshes.size()==1 and triangles>80000 and triangles<=96000,"Malla continua reconstruida dentro del presupuesto de juego")
	check(texture_size==4096,"Atlas 4K importado")
	model.free()
	for index in 6:
		var avatar:=DriverAvatar.new()
		root.add_child(avatar)
		check(avatar.setup(index,DriverAvatar.load_avatar(DriverAvatar.DEFAULT_PATH),true),"Se adapta a la mototaxi %d"%index)
		var hips:=avatar._bone(["Hips"])
		check(avatar._joint_position(hips).distance_to(avatar.seat)<.005,"Pelvis alineada al asiento %d"%index)
		for side in ["Left","Right"]:
			var hand:=avatar._bone([side+"Hand"])
			var target: Vector3=DriverAvatar.GRIPS[index]*VehicleCatalog.MODEL_SCALE
			if side=="Right":target.x*=-1
			var error:=avatar._joint_position(hand).distance_to(target)
			check(error<.025,"Mano %s cerca del manillar %d (%.3f m)"%[side,index,error])
		avatar.queue_free()
		await process_frame
	print("Reconstrucción del conductor: %d errores"%failures)
	quit(0 if failures==0 else 1)
