#ifndef TERRAIN_RENDER_H
#define TERRAIN_RENDER_H

#include <cstdint>
#include <string>
#include <vector>

// Render por software de un heightfield (S14: figuras del pipeline y pantalla de carga).
// No usa la GPU ni Godot: funciona tambien sin ventana (--headless) y siempre da la
// misma imagen para el mismo terreno. Devuelve RGB de 8 bits, fila por fila.
namespace terrain_render {

struct Image {
	int width = 0, height = 0;
	std::vector<uint8_t> rgb;
	void resize(int w, int h) {
		width = w;
		height = h;
		rgb.assign(size_t(w) * h * 3, 0);
	}
};

struct Field {
	const float *h = nullptr; // n x n alturas en metros
	int n = 0;
	double cell = 1.0; // metros entre muestras
	// Opcionales, a la MISMA resolucion n x n:
	const float *biome = nullptr; // 3 floats por muestra: costa, sierra, selva
	const float *water = nullptr; // 0..1 por muestra (rios)
	double h_lo = 0.0, h_hi = 1.0; // rango de alturas para los colores (fijo entre fotos)
};

struct ReliefOptions {
	double sun_azimuth = 315.0; // convencion cartografica: luz desde el noroeste
	double sun_elevation = 45.0;
	double z_factor = 2.0; // exageracion vertical del sombreado
	bool contours = false;
	double contour_step = 25.0;
};

struct PerspectiveOptions {
	double azimuth = 225.0; // desde donde mira la camara (grados, 0 = +z)
	double elevation = 32.0; // angulo de la camara sobre el horizonte
	double distance = 1.0; // 1 = el mapa entero justo dentro de la imagen; menos = mas cerca
	double fov = 40.0; // apertura vertical
	double exaggeration = 1.0;
	double sun_azimuth = 135.0;
	double sun_elevation = 28.0;
	bool shadows = true;
};

// Color de un punto: mezcla de paletas por region + altura.
void base_color(const Field &f, int i, double height, double out[3]);

// Vista desde arriba: sombreado de colinas (hillshade) + tinte hipsometrico.
Image relief(const Field &f, int size, const ReliefOptions &opt);

// Vista 3D oblicua por ray tracing del heightfield (como el visor del repo oficial).
Image perspective(const Field &f, int width, int height, const PerspectiveOptions &opt);

// Mapa de una magnitud escalar con una paleta: 0 = gris, 1 = azul (agua), 2 = divergente
// (azul negativo, rojo positivo), 3 = magma (calor), 4 = RGB directo (3 floats).
Image scalar(const float *values, int n, int size, double lo, double hi, int palette);

// Texto con una fuente de mapa de bits de 5 x 7 (ASCII; minusculas como mayusculas).
void text(Image &img, int x, int y, const std::string &s, int scale, const uint8_t color[3], bool box);
int text_width(const std::string &s, int scale);

// Reduce una imagen a un tamano dado (promedio de pixeles).
Image resize(const Image &src, int width, int height);

} // namespace terrain_render

#endif // TERRAIN_RENDER_H
