#ifndef EROSION_H
#define EROSION_H

#include <functional>
#include <string>
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
	int fluvial_iterations = 0, thermal_iterations = 0, deposition_iterations = 0;
};

// Una "foto" del terreno durante la erosion (S14: figuras de la evolucion).
// Las alturas ya estan en las unidades del mundo (metros), a la resolucion del nivel.
struct ErosionFrame {
	int index = 0; // orden de captura
	int level = 0, levels = 0; // nivel actual (0 = el mas grueso) y total de upsamplings
	int samples = 0; // muestras por lado en este nivel
	double cell = 1.0; // metros entre muestras en este nivel
	std::string stage = "T0"; // "T0", "fluvial", "thermal", "deposition"
	int iteration = 0, stage_total = 0; // iteracion dentro de la etapa actual
	// Iteraciones acumuladas de cada proceso (todas las resoluciones hasta ahora).
	int fluvial = 0, thermal = 0, deposition = 0;
	// Iteraciones de cada proceso dentro del nivel actual.
	int level_fluvial = 0, level_thermal = 0, level_deposition = 0;
	long long global_iteration = 0, total_iterations = 0;
	double seconds = 0.0; // tiempo desde el inicio de la erosion
	std::vector<float> heights; // float: con 20 fotos de 1025 x 1025 la memoria se reduce a la mitad
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
	// 1 = bicubica (Catmull-Rom, lo que describe el paper), 0 = lineal (lo que hace
	// ScalarField2::SetResolution del repo oficial: las dos ramas usan Value() bilineal).
	int upsampling = 1;
	std::vector<ErosionTiming> *timings = nullptr;

	// --- Capturas de la evolucion (S14) ---
	// capture_count fotos repartidas de forma pareja entre todas las iteraciones,
	// incluyendo T0 (iteracion 0) y el final. 0 = sin capturas.
	int capture_count = 0;
	// Ademas, una foto al terminar cada proceso de cada nivel (E, T y D).
	bool capture_stage_ends = false;
	std::vector<ErosionFrame> *frames = nullptr;
	// Avance de 0 a 1 y nombre de la etapa. Se llama desde el hilo que erosiona.
	std::function<void(double, const std::string &)> progress;
	// Se llama con cada foto apenas se toma (por ejemplo, para la pantalla de carga).
	std::function<void(const ErosionFrame &)> on_frame;
};

// Plan de iteraciones de cada nivel (sirve para mostrar la receta y para las capturas).
struct ErosionLevelPlan {
	int samples = 0;
	int fluvial = 0, thermal = 0, deposition = 0;
};
std::vector<ErosionLevelPlan> erosion_plan(int n, const ErosionSteps &steps);

void erode_terrain(std::vector<double> &H, int n, double cell_size, const ErosionSteps &steps);

// Upsampling x2 de una grilla n x n a (2n - 1) x (2n - 1), conservando los puntos viejos.
std::vector<double> upsample_heights_x2(const std::vector<double> &h, int n, bool bicubic);

#endif // EROSION_H
