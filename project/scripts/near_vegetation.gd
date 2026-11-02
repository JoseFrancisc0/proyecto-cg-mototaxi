class_name NearVegetation
extends Node3D
## Árboles con el modelo completo alrededor de la cámara (LOD por planta, ver VegetationModels).
##
## Guarda las plantas de cada especie/variante en una grilla y, cuando la cámara se mueve más
## de refresh_distance, vuelve a llenar un MultiMesh por variante solo con las que están a
## menos de radius. El shader oculta las que pasan de LOD_DISTANCE (las dibuja la versión
## lejana), así que radius puede ser algo mayor sin dibujar dos veces el mismo árbol.

@export var radius := VegetationModels.LOD_DISTANCE + 40.0
@export var cell_size := 32.0
@export var refresh_distance := 12.0

var _groups := {}            # Mesh -> {"mmi": MultiMeshInstance3D, "grid": {Vector2i: PackedFloat32Array}}
var _last := Vector3.INF
var visible_count := 0       # árboles en los MultiMesh cercanos tras el último refresco


## Agrega plantas (buffer de MultiMesh, 20 floats por planta) que se dibujan con mesh de cerca.
func add(mesh: Mesh, buffer: PackedFloat32Array) -> void:
	if not _groups.has(mesh):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cerca%d" % _groups.size()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_groups[mesh] = {"mmi": mmi, "grid": {}}
	var grid: Dictionary = _groups[mesh]["grid"]
	for i in range(0, buffer.size(), 20):
		var cell := Vector2i(floori(buffer[i + 3] / cell_size), floori(buffer[i + 11] / cell_size))
		var arr: PackedFloat32Array = grid.get(cell, PackedFloat32Array())
		arr.append_array(buffer.slice(i, i + 20))
		grid[cell] = arr
	_last = Vector3.INF


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	if p.distance_to(_last) > refresh_distance:
		refresh(p)


## Llena los MultiMesh cercanos con las plantas a menos de radius de p.
func refresh(p: Vector3) -> void:
	_last = p
	visible_count = 0
	var r_cells := ceili(radius / cell_size)
	var c0 := Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))
	var r2 := radius * radius
	for mesh in _groups:
		var g: Dictionary = _groups[mesh]
		var grid: Dictionary = g["grid"]
		var out := PackedFloat32Array()
		for dz in range(-r_cells, r_cells + 1):
			for dx in range(-r_cells, r_cells + 1):
				var arr: PackedFloat32Array = grid.get(c0 + Vector2i(dx, dz), PackedFloat32Array())
				for i in range(0, arr.size(), 20):
					var ddx := arr[i + 3] - p.x
					var ddz := arr[i + 11] - p.z
					if ddx * ddx + ddz * ddz < r2:
						out.append_array(arr.slice(i, i + 20))
		var mm: MultiMesh = (g["mmi"] as MultiMeshInstance3D).multimesh
		mm.instance_count = out.size() / 20
		if mm.instance_count > 0:
			mm.buffer = out
		visible_count += mm.instance_count
