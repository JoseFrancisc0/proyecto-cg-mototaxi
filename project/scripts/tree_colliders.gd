class_name TreeColliders
extends Node3D
## Troncos sólidos cerca de la mototaxi (S14): chocar un árbol, palmera o cactus la detiene
## y le hace daño (Mototaxi._check_crash detecta el frenazo brusco; no hace falta otra lógica).
##
## Hay cientos de miles de plantas: no se crea un cuerpo por planta. Se guardan las posiciones
## de los troncos en una grilla y un grupo fijo de StaticBody3D (pool_size) se mueve a los
## troncos más cercanos al objetivo (la mototaxi) cada refresh_time segundos.
## Arbustos y pasto no tienen tronco (trunk = 0 en VegetationModels): se atraviesan.

@export var radius := 40.0          ## Distancia (m) a la que los troncos se vuelven sólidos.
@export var pool_size := 96
@export var refresh_time := 0.15
@export var cell_size := 32.0

## Nodo a seguir; si es null, el primero del grupo "mototaxi" o la cámara activa.
var target: Node3D

var _grid := {}              # Vector2i -> PackedFloat32Array [x, y, z, radio, alto, ...]
var _bodies: Array[StaticBody3D] = []
var _shapes: Array[CylinderShape3D] = []
var _timer := 0.0
var trunk_count := 0


## Agrega los troncos de un chunk desde el buffer de MultiMesh (20 floats por planta).
func add_trunks(buffer: PackedFloat32Array, trunk_radius: float, model_height: float) -> void:
	for i in range(0, buffer.size(), 20):
		var x := buffer[i + 3]
		var y := buffer[i + 7]
		var z := buffer[i + 11]
		var sc := Vector3(buffer[i], buffer[i + 4], buffer[i + 8]).length()
		var cell := Vector2i(floori(x / cell_size), floori(z / cell_size))
		var arr: PackedFloat32Array = _grid.get(cell, PackedFloat32Array())
		arr.append_array([x, y, z, trunk_radius * sc, minf(model_height * sc, 6.0)])
		_grid[cell] = arr
		trunk_count += 1


## Troncos por celda: cada PackedFloat32Array trae [x, y, z, radio, alto] por tronco.
func trunk_cells() -> Array:
	return _grid.values()


func clear() -> void:
	_grid.clear()
	trunk_count = 0
	for b in _bodies:
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.visible = false


func _ready() -> void:
	for i in pool_size:
		var body := StaticBody3D.new()
		body.name = "Trunk%d" % i
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		shape.shape = cyl
		body.add_child(shape)
		body.process_mode = Node.PROCESS_MODE_DISABLED  # sin colisión hasta que se use
		add_child(body)
		_bodies.append(body)
		_shapes.append(cyl)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _grid.is_empty():
		return
	_timer = refresh_time
	var t := _target()
	if t == null:
		return
	refresh(t.global_position)


## Pone los cuerpos en los troncos más cercanos a p. Devuelve cuántos quedaron activos.
func refresh(p: Vector3) -> int:
	var near: Array = []  # [distancia², índice en la celda, celda]
	var r_cells := ceili(radius / cell_size)
	var c0 := Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))
	var r2 := radius * radius
	for dz in range(-r_cells, r_cells + 1):
		for dx in range(-r_cells, r_cells + 1):
			var cell := c0 + Vector2i(dx, dz)
			if not _grid.has(cell):
				continue
			var arr: PackedFloat32Array = _grid[cell]
			for i in range(0, arr.size(), 5):
				var d2 := Vector2(arr[i] - p.x, arr[i + 2] - p.z).length_squared()
				if d2 < r2:
					near.append([d2, i, cell])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var used := mini(near.size(), _bodies.size())
	for k in _bodies.size():
		var body := _bodies[k]
		if k >= used:
			body.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		var arr: PackedFloat32Array = _grid[near[k][2]]
		var i: int = near[k][1]
		var h := arr[i + 4]
		_shapes[k].radius = maxf(arr[i + 3], 0.08)
		_shapes[k].height = h
		body.global_position = Vector3(arr[i], arr[i + 1] + h * 0.5, arr[i + 2])
		body.process_mode = Node.PROCESS_MODE_INHERIT
	return used


func _target() -> Node3D:
	if is_instance_valid(target):
		return target
	var m := get_tree().get_first_node_in_group("mototaxi") as Node3D
	if m:
		return m
	return get_viewport().get_camera_3d()
