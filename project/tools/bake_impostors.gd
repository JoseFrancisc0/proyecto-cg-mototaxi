extends SceneTree
## Hornea los impostores octaédricos de los árboles (ver VegetationImpostors).
##   Godot --path project -s res://tools/bake_impostors.gd [-- especie ...]   (con ventana)
##
## Por cada especie con LOD y cada variante: pone el modelo real en un SubViewport y lo
## dibuja con una cámara ortográfica desde las FRAMES x FRAMES direcciones hemi-octaédricas,
## dos veces por vista (color y normal, shaders/impostor_bake.gdshader). Las vistas se pegan
## en dos atlas, se rellena el color bajo los bordes transparentes (para que los mipmaps no
## oscurezcan el contorno) y se reducen a la mitad (antialiasing).

const BAKE_SHADER := "res://shaders/impostor_bake.gdshader"

var _vp: SubViewport
var _cam: Camera3D
var _mi: MeshInstance3D


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_vp = SubViewport.new()
	_vp.size = Vector2i.ONE * VegetationImpostors.BAKE_PX
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_mi = MeshInstance3D.new()
	_vp.add_child(_mi)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VegetationImpostors.DIR))

	var only := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var count := 0
	for species: String in VegetationModels.SPECIES:
		if not VegetationModels.uses_lod(species) or (not only.is_empty() and not species in only):
			continue
		var info: Dictionary = VegetationModels.SPECIES[species]
		for file: String in info["files"]:
			var built := VegetationModels._build(species, file, info, false)
			if built.is_empty():
				continue
			await _bake(species, file, built["near"])
			count += 1
	print("Impostores: %d horneados en %.1f s en %s" % [count, (Time.get_ticks_msec() - t0) / 1000.0, VegetationImpostors.DIR])
	quit()


func _bake(species: String, file: String, mesh: Mesh) -> void:
	var b := VegetationImpostors.bounds(mesh)
	var center: Vector3 = b["center"]
	var radius: float = b["radius"]
	# Material de horneado por superficie, con los mismos datos que el material del juego.
	var mats: Array[ShaderMaterial] = []
	_mi.mesh = mesh
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as ShaderMaterial
		var m := ShaderMaterial.new()
		m.shader = load(BAKE_SHADER)
		for p in ["albedo_tex", "normal_tex", "use_normal_map", "tint", "alpha_cut", "leafiness", "model_height"]:
			m.set_shader_parameter(p, src.get_shader_parameter(p))
		_mi.set_surface_override_material(s, m)
		mats.append(m)

	var n := VegetationImpostors.FRAMES
	var px := VegetationImpostors.BAKE_PX
	var atlases: Array[Image] = [
		Image.create_empty(n * px, n * px, false, Image.FORMAT_RGBA8),
		Image.create_empty(n * px, n * px, false, Image.FORMAT_RGBA8)]
	_cam.size = radius * 2.0
	_cam.near = 0.01
	_cam.far = radius * 6.0
	for j in n:
		for i in n:
			var d := VegetationImpostors.frame_direction(i, j)
			_cam.global_transform = Transform3D(VegetationImpostors.frame_basis(d), center + d * radius * 3.0)
			for pass_mode in 2:
				for m in mats:
					m.set_shader_parameter("pass_mode", pass_mode)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := _vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				atlases[pass_mode].blit_rect(img, Rect2i(0, 0, px, px), Vector2i(i * px, j * px))

	var k := VegetationImpostors.key(species, file)
	var out := ProjectSettings.globalize_path(VegetationImpostors.DIR)
	var size := n * VegetationImpostors.FRAME_PX
	for p in 2:
		var atlas := atlases[p]
		atlas.fix_alpha_edges()
		atlas.resize(size, size, Image.INTERPOLATE_BILINEAR)
		atlas.fix_alpha_edges()
		atlas.save_png(out.path_join(k + ("_albedo.png" if p == 0 else "_normal.png")))
	var info := {"center": [center.x, center.y, center.z], "radius": radius, "frames": n,
		"frame_px": VegetationImpostors.FRAME_PX, "source": file}
	var f := FileAccess.open(out.path_join(k + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	print("  %s: radio %.1f m" % [k, radius])

