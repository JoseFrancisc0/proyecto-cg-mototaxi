@tool
extends MeshInstance3D

@export var grid_size: int = 128
@export var cell_size: float = 1.0
@export var noise_seed: int = 1337

@export_group("Red de caminos")
@export var num_points := 6
@export var min_point_dist := 25.0
@export var k_neighbors := 2
@export var road_width := 4.0
@export var road_fade := 3.0
@export var road_smooth := 3

func _ready() -> void:
	# 1. Configurar ruido y biomas
	var terrain := TerrainNoise.new()
	terrain.set_seed(noise_seed)

	# 2. Generar caminos sobre el terreno
	var cfg := {
		"num_points": num_points,
		"min_point_dist": min_point_dist,
		"k_neighbors": k_neighbors,
		"road_width": road_width,
		"road_fade": road_fade,
		"road_smooth": road_smooth,
	}
	var roads := RoadNetwork.new()
	roads.generate_roads(terrain, grid_size, cell_size, cfg)

	# 3. Ensamblar la geometría final
	var mesh_builder := TerrainMesh.new()
	mesh = mesh_builder.generate_mesh(terrain, roads, grid_size, cell_size, cfg)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	material_override = mat
