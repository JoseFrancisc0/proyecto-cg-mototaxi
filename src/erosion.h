#ifndef EROSION_H
#define EROSION_H

#include <vector>

// Caja negra de la erosion del paper "Terrain Amplification using Multi-scale Erosion"
// (Schott et al. 2024). Port en CPU de los shaders oficiales:
//   data/shaders/erosion.glsl     -> erosion fluvial (stream power)
//   data/shaders/thermal.glsl     -> estabilizacion termica
//   data/shaders/deposition.glsl  -> deposicion de sedimentos
//
// Entrada : H, grilla de n x n alturas (indice = iz * n + ix), y el tamano de celda en metros.
// Salida  : la misma H, ya erosionada.
// Los pasos por defecto son los de PredefinedErosion() del repo oficial para 256 x 256.
// Con levels > 0 se hace el multiescala: erosion -> upsampling x2 -> erosion -> ...

struct ErosionTiming {
    int samples;
    double fluvial_seconds, thermal_seconds, deposition_seconds;
};
struct ErosionSteps {
    // pasos de la primera resolucion (la mas gruesa)
    int fluvial = 3000;
    int thermal = 600;
    int deposition = 2000;
    // cuantas veces se sube la resolucion x2 (0 = una sola resolucion).
    // La resolucion base es grid_size / 2^levels; los pasos de las rondas
    // siguientes son los de PredefinedErosion() del repo oficial.
    int levels = 0;
    // Optional regional maps at the final sample resolution, row-major.
    std::vector<float> hardness;
    std::vector<float> talus;
    // Scale the original iteration recipe for interactive previews.
    double iteration_scale = 1.0;
    std::vector<ErosionTiming> *timings = nullptr;
};

void erode_terrain(std::vector<double> &H, int n, double cell_size, const ErosionSteps &steps);

#endif // EROSION_H
