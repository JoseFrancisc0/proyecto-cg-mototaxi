#ifndef TERRAIN_INTERNAL_H
#define TERRAIN_INTERNAL_H
#include <vector>
// Funciones compartidas entre los .cpp de TerrainMesh (no se exponen a Godot).
// Visibilidad del cielo por muestra (AO por ray tracing sobre el heightfield).
std::vector<float> terrain_sky_visibility(const std::vector<double> &H, int n, double cell, double radius, int dirs);
// Altura bilineal en coordenadas del mundo (origen en el centro del mapa).
double terrain_grid_sample(const std::vector<double> &h, int n, double cell, double x, double z);
#endif
