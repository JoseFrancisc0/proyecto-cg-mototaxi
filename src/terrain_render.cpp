#include "terrain_render.h"
#include <algorithm>
#include <cmath>
#include <thread>

namespace terrain_render {
namespace {

const double PI = 3.14159265358979323846;

template <typename F>
void parallel_rows(int rows, F row) {
	int threads = std::max(1, std::min(8, (int)std::thread::hardware_concurrency()));
	if (rows < 64 || threads == 1) {
		for (int y = 0; y < rows; y++)
			row(y);
		return;
	}
	std::vector<std::thread> pool;
	for (int t = 0; t < threads; t++) {
		int a = rows * t / threads, b = rows * (t + 1) / threads;
		pool.emplace_back([=]() {
			for (int y = a; y < b; y++)
				row(y);
		});
	}
	for (auto &th : pool)
		th.join();
}

inline double clamp01(double v) { return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v); }
inline double smooth(double a, double b, double x) {
	double t = clamp01((x - a) / (b - a));
	return t * t * (3.0 - 2.0 * t);
}
inline uint8_t to_byte(double v) { return (uint8_t)std::lround(clamp01(v) * 255.0); }

// Rampa de colores por tramos (t en 0..1).
void ramp(const double (*stops)[4], int count, double t, double out[3]) {
	t = clamp01(t);
	for (int i = 0; i < count - 1; i++) {
		if (t <= stops[i + 1][0]) {
			double u = (t - stops[i][0]) / std::max(1e-9, stops[i + 1][0] - stops[i][0]);
			for (int c = 0; c < 3; c++)
				out[c] = stops[i][c + 1] + (stops[i + 1][c + 1] - stops[i][c + 1]) * u;
			return;
		}
	}
	for (int c = 0; c < 3; c++)
		out[c] = stops[count - 1][c + 1];
}

// Paletas por region (alturas normalizadas 0..1 en todo el mapa).
// Costa: arena y desierto. Sierra: puna (pasto amarillento), roca parda, roca gris y nieve.
// Selva: verdes. Los valores son reflectancias aproximadas (albedo) en 0..1.
const double COAST[][4] = { { 0.00, 0.78, 0.69, 0.52 }, { 0.20, 0.84, 0.74, 0.55 }, { 0.50, 0.74, 0.62, 0.45 }, { 1.00, 0.60, 0.50, 0.40 } };
const double SIERRA[][4] = { { 0.00, 0.58, 0.55, 0.33 }, { 0.35, 0.55, 0.47, 0.30 }, { 0.65, 0.47, 0.40, 0.33 }, { 0.86, 0.50, 0.48, 0.46 }, { 0.94, 0.86, 0.87, 0.89 }, { 1.00, 0.96, 0.97, 0.99 } };
const double JUNGLE[][4] = { { 0.00, 0.17, 0.36, 0.12 }, { 0.40, 0.15, 0.32, 0.11 }, { 0.75, 0.24, 0.34, 0.17 }, { 1.00, 0.40, 0.42, 0.33 } };
const double HYPSO[][4] = { { 0.00, 0.30, 0.50, 0.28 }, { 0.25, 0.55, 0.62, 0.36 }, { 0.50, 0.70, 0.62, 0.42 }, { 0.75, 0.55, 0.45, 0.36 }, { 0.92, 0.80, 0.78, 0.76 }, { 1.00, 0.98, 0.98, 1.00 } };
const double WATER_COLOR[3] = { 0.10, 0.34, 0.52 };

inline float at(const Field &f, int x, int z) {
	x = std::clamp(x, 0, f.n - 1);
	z = std::clamp(z, 0, f.n - 1);
	return f.h[size_t(z) * f.n + x];
}

double bilinear(const Field &f, double gx, double gz) {
	gx = std::clamp(gx, 0.0, double(f.n - 1));
	gz = std::clamp(gz, 0.0, double(f.n - 1));
	int x = std::min(int(gx), f.n - 2), z = std::min(int(gz), f.n - 2);
	double tx = gx - x, tz = gz - z;
	const float *r0 = f.h + size_t(z) * f.n + x, *r1 = r0 + f.n;
	return (r0[0] * (1 - tx) + r0[1] * tx) * (1 - tz) + (r1[0] * (1 - tx) + r1[1] * tx) * tz;
}

// Normal del heightfield en la muestra (x, z), con exageracion vertical.
void normal_at(const Field &f, int x, int z, double zf, double n[3]) {
	double dx = (at(f, x + 1, z) - at(f, x - 1, z)) / (2.0 * f.cell) * zf;
	double dz = (at(f, x, z + 1) - at(f, x, z - 1)) / (2.0 * f.cell) * zf;
	double len = std::sqrt(dx * dx + 1.0 + dz * dz);
	n[0] = -dx / len;
	n[1] = 1.0 / len;
	n[2] = -dz / len;
}

void sun_vector(double azimuth, double elevation, double L[3]) {
	double az = azimuth * PI / 180.0, el = elevation * PI / 180.0;
	L[0] = std::cos(el) * std::sin(az);
	L[1] = std::sin(el);
	L[2] = std::cos(el) * std::cos(az);
}

// Fuente 5 x 7. Cada glifo son 7 filas de 5 columnas ('#' = pixel encendido).
struct Glyph {
	char c;
	const char *rows[7];
};
const Glyph FONT[] = {
	{ '0', { ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###." } },
	{ '1', { "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###." } },
	{ '2', { ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####" } },
	{ '3', { "#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###." } },
	{ '4', { "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#." } },
	{ '5', { "#####", "#....", "####.", "....#", "....#", "#...#", ".###." } },
	{ '6', { "..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###." } },
	{ '7', { "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..." } },
	{ '8', { ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###." } },
	{ '9', { ".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.." } },
	{ 'A', { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" } },
	{ 'B', { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." } },
	{ 'C', { ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###." } },
	{ 'D', { "###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.." } },
	{ 'E', { "#####", "#....", "#....", "####.", "#....", "#....", "#####" } },
	{ 'F', { "#####", "#....", "#....", "####.", "#....", "#....", "#...." } },
	{ 'G', { ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####" } },
	{ 'H', { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" } },
	{ 'I', { ".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###." } },
	{ 'J', { "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.." } },
	{ 'K', { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" } },
	{ 'L', { "#....", "#....", "#....", "#....", "#....", "#....", "#####" } },
	{ 'M', { "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#" } },
	{ 'N', { "#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#" } },
	{ 'O', { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." } },
	{ 'P', { "####.", "#...#", "#...#", "####.", "#....", "#....", "#...." } },
	{ 'Q', { ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#" } },
	{ 'R', { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" } },
	{ 'S', { ".####", "#....", "#....", ".###.", "....#", "....#", "####." } },
	{ 'T', { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." } },
	{ 'U', { "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." } },
	{ 'V', { "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.." } },
	{ 'W', { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#." } },
	{ 'X', { "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#" } },
	{ 'Y', { "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.." } },
	{ 'Z', { "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####" } },
	{ '.', { ".....", ".....", ".....", ".....", ".....", ".##..", ".##.." } },
	{ ',', { ".....", ".....", ".....", ".....", ".##..", "..#..", ".#..." } },
	{ ':', { ".....", ".##..", ".##..", ".....", ".##..", ".##..", "....." } },
	{ '-', { ".....", ".....", ".....", "#####", ".....", ".....", "....." } },
	{ '_', { ".....", ".....", ".....", ".....", ".....", ".....", "#####" } },
	{ '(', { "...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#." } },
	{ ')', { ".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..." } },
	{ '/', { ".....", "....#", "...#.", "..#..", ".#...", "#....", "....." } },
	{ '%', { "##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##" } },
	{ '+', { ".....", "..#..", "..#..", "#####", "..#..", "..#..", "....." } },
	{ '=', { ".....", ".....", "#####", ".....", "#####", ".....", "....." } },
	{ '|', { "..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." } },
	{ '>', { ".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..." } },
	{ '<', { "...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#." } },
};

const Glyph *find_glyph(char c) {
	if (c >= 'a' && c <= 'z')
		c = char(c - 'a' + 'A');
	for (const Glyph &g : FONT)
		if (g.c == c)
			return &g;
	return nullptr;
}

} // namespace

void base_color(const Field &f, int i, double height, double out[3]) {
	double t = (height - f.h_lo) / std::max(1e-6, f.h_hi - f.h_lo);
	if (f.biome) {
		double w[3] = { f.biome[size_t(i) * 3], f.biome[size_t(i) * 3 + 1], f.biome[size_t(i) * 3 + 2] };
		double s = std::max(1e-6, w[0] + w[1] + w[2]);
		double a[3], b[3], c[3];
		ramp(COAST, 4, t, a);
		ramp(SIERRA, 6, t, b);
		ramp(JUNGLE, 4, t, c);
		for (int k = 0; k < 3; k++)
			out[k] = (a[k] * w[0] + b[k] * w[1] + c[k] * w[2]) / s;
	} else {
		ramp(HYPSO, 6, t, out);
	}
	if (f.water) {
		double wv = clamp01(f.water[i]);
		for (int k = 0; k < 3; k++)
			out[k] = out[k] * (1.0 - wv) + WATER_COLOR[k] * wv;
	}
}

Image relief(const Field &f, int size, const ReliefOptions &opt) {
	Image img;
	img.resize(size, size);
	if (f.n < 2 || !f.h)
		return img;
	double L[3];
	sun_vector(opt.sun_azimuth, opt.sun_elevation, L);
	// La imagen se mira con el norte (-z) arriba: fila 0 = z minimo.
	parallel_rows(size, [&](int py) {
		for (int px = 0; px < size; px++) {
			double gx = (px + 0.5) / size * (f.n - 1), gz = (py + 0.5) / size * (f.n - 1);
			int x = std::clamp(int(std::lround(gx)), 0, f.n - 1), z = std::clamp(int(std::lround(gz)), 0, f.n - 1);
			double h = bilinear(f, gx, gz);
			double nrm[3];
			normal_at(f, x, z, opt.z_factor, nrm);
			double lambert = std::max(0.0, nrm[0] * L[0] + nrm[1] * L[1] + nrm[2] * L[2]);
			// Sombreado de colinas suave: 0.45 de luz ambiente + 0.75 de luz directa.
			double shade = 0.45 + 0.75 * lambert;
			double col[3];
			base_color(f, z * f.n + x, h, col);
			if (opt.contours && opt.contour_step > 0.0) {
				double a = std::fmod(h - f.h_lo, opt.contour_step);
				double px_m = (f.n - 1) * f.cell / size; // metros por pixel
				double grad = std::sqrt(std::max(0.0, 1.0 / (nrm[1] * nrm[1]) - 1.0)) / opt.z_factor;
				double width = std::max(1e-6, grad * px_m * 0.8);
				if (a < width || opt.contour_step - a < width)
					shade *= 0.72;
			}
			uint8_t *p = &img.rgb[(size_t(py) * size + px) * 3];
			for (int k = 0; k < 3; k++)
				p[k] = to_byte(std::pow(clamp01(col[k] * shade), 1.0 / 1.1));
		}
	});
	return img;
}

Image perspective(const Field &f, int width, int height, const PerspectiveOptions &opt) {
	Image img;
	img.resize(width, height);
	if (f.n < 2 || !f.h)
		return img;
	const double extent = (f.n - 1) * f.cell;
	const double half = extent * 0.5;
	const double ex = opt.exaggeration;
	// Camara orbitando el centro del mapa, a la distancia justa para ver toda la caja
	// del terreno (esfera que la envuelve dentro del cono de vision).
	double mid = 0.5 * (f.h_lo + f.h_hi) * ex;
	double az = opt.azimuth * PI / 180.0, el = opt.elevation * PI / 180.0;
	double box_r = std::sqrt(2.0 * half * half + std::pow(0.5 * (f.h_hi - f.h_lo) * ex, 2.0));
	double aspect_fit = std::min(1.0, double(width) / height);
	double fit = box_r / std::sin(opt.fov * PI / 360.0 * aspect_fit);
	double dist = opt.distance * fit * 0.62;
	double cam[3] = { std::cos(el) * std::sin(az) * dist, mid + std::sin(el) * dist, std::cos(el) * std::cos(az) * dist };
	double target[3] = { 0.0, mid, 0.0 };
	double fwd[3] = { target[0] - cam[0], target[1] - cam[1], target[2] - cam[2] };
	double fl = std::sqrt(fwd[0] * fwd[0] + fwd[1] * fwd[1] + fwd[2] * fwd[2]);
	for (double &v : fwd)
		v /= fl;
	double right[3] = { -fwd[2], 0.0, fwd[0] }; // fwd x up(0,1,0) con signo para que +x vaya a la derecha
	double rl = std::sqrt(right[0] * right[0] + right[2] * right[2]);
	right[0] /= rl;
	right[2] /= rl;
	double up[3] = { right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0] };
	double tan_half = std::tan(opt.fov * PI / 360.0);
	double aspect = double(width) / height;
	double L[3];
	sun_vector(opt.sun_azimuth, opt.sun_elevation, L);
	const double top = f.h_hi * ex + 1.0;
	const double bottom = f.h_lo * ex - 1.0;
	auto height_at = [&](double wx, double wz) { return bilinear(f, (wx + half) / f.cell, (wz + half) / f.cell) * ex; };
	const double max_t = dist * 3.0 + extent;

	parallel_rows(height, [&](int py) {
		for (int px = 0; px < width; px++) {
			double sx = ((px + 0.5) / width * 2.0 - 1.0) * tan_half * aspect;
			double sy = (1.0 - (py + 0.5) / height * 2.0) * tan_half;
			double d[3] = { fwd[0] + right[0] * sx + up[0] * sy, fwd[1] + right[1] * sx + up[1] * sy, fwd[2] + right[2] * sx + up[2] * sy };
			double dl = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
			for (double &v : d)
				v /= dl;
			// Cielo: degradado segun la altura del rayo.
			double sky_t = clamp01(d[1] * 2.0 + 0.3);
			double col[3] = { 0.78 - 0.30 * sky_t, 0.84 - 0.22 * sky_t, 0.92 - 0.06 * sky_t };
			// Entrar a la caja del terreno.
			double t0 = 0.0, t1 = max_t;
			bool inside = true;
			for (int a = 0; a < 3 && inside; a++) {
				double lo = a == 1 ? bottom : -half, hi = a == 1 ? top : half;
				if (std::fabs(d[a]) < 1e-9) {
					if (cam[a] < lo || cam[a] > hi)
						inside = false;
					continue;
				}
				double ta = (lo - cam[a]) / d[a], tb = (hi - cam[a]) / d[a];
				if (ta > tb)
					std::swap(ta, tb);
				t0 = std::max(t0, ta);
				t1 = std::min(t1, tb);
			}
			bool hit = false;
			double t = t0;
			if (inside && t0 < t1) {
				// Marcha del rayo con paso proporcional a la altura sobre el terreno.
				double prev_t = t;
				double prev_gap = 0.0;
				bool first = true;
				for (int s = 0; s < 600 && t <= t1; s++) {
					double p[3] = { cam[0] + d[0] * t, cam[1] + d[1] * t, cam[2] + d[2] * t };
					double gap = p[1] - height_at(p[0], p[2]);
					if (gap < 0.0) {
						// Biseccion entre el ultimo punto arriba y este punto abajo.
						double a = first ? t : prev_t, b = t;
						for (int k = 0; k < 8; k++) {
							double m = 0.5 * (a + b);
							double q[3] = { cam[0] + d[0] * m, cam[1] + d[1] * m, cam[2] + d[2] * m };
							if (q[1] - height_at(q[0], q[2]) < 0.0)
								b = m;
							else
								a = m;
						}
						t = 0.5 * (a + b);
						hit = true;
						break;
					}
					prev_t = t;
					prev_gap = gap;
					first = false;
					double min_step = std::max(f.cell * 0.4, t * 0.0015);
					t += std::max(min_step, gap * 0.45);
				}
				(void)prev_gap;
			}
			if (hit) {
				double p[3] = { cam[0] + d[0] * t, cam[1] + d[1] * t, cam[2] + d[2] * t };
				double gx = (p[0] + half) / f.cell, gz = (p[2] + half) / f.cell;
				int x = std::clamp(int(std::lround(gx)), 0, f.n - 1), z = std::clamp(int(std::lround(gz)), 0, f.n - 1);
				double nrm[3];
				normal_at(f, x, z, ex, nrm);
				double lambert = std::max(0.0, nrm[0] * L[0] + nrm[1] * L[1] + nrm[2] * L[2]);
				double shadow = 1.0;
				if (opt.shadows && L[1] > 0.0 && lambert > 0.0) {
					// Rayo de sombra hacia el sol (mismo heightfield).
					double st = f.cell * 1.5;
					for (int s = 0; s < 160; s++) {
						double q[3] = { p[0] + L[0] * st, p[1] + 0.2 + L[1] * st, p[2] + L[2] * st };
						if (std::fabs(q[0]) > half || std::fabs(q[2]) > half || q[1] > top)
							break;
						double g = q[1] - height_at(q[0], q[2]);
						if (g < 0.0) {
							shadow = 0.0;
							break;
						}
						shadow = std::min(shadow, 12.0 * g / st);
						st += std::max(f.cell * 0.5, g * 0.5);
					}
					shadow = clamp01(shadow);
				}
				double base[3];
				base_color(f, z * f.n + x, p[1] / ex, base);
				double sky = 0.30 + 0.18 * nrm[1];
				double light = sky + 1.10 * lambert * shadow;
				double fog = 1.0 - std::exp(-std::max(0.0, t - dist * 0.6) / (extent * 6.0));
				double haze[3] = { 0.74, 0.80, 0.88 };
				for (int k = 0; k < 3; k++)
					col[k] = base[k] * light * (1.0 - fog) + haze[k] * fog;
			}
			uint8_t *o = &img.rgb[(size_t(py) * width + px) * 3];
			for (int k = 0; k < 3; k++)
				o[k] = to_byte(std::pow(clamp01(col[k]), 1.0 / 1.15));
		}
	});
	return img;
}

Image scalar(const float *values, int n, int size, double lo, double hi, int palette) {
	Image img;
	img.resize(size, size);
	if (!values || n < 1)
		return img;
	static const double GRAY[][4] = { { 0, 0.05, 0.05, 0.05 }, { 1, 0.97, 0.97, 0.97 } };
	static const double BLUE[][4] = { { 0, 0.96, 0.95, 0.90 }, { 0.35, 0.62, 0.80, 0.90 }, { 0.7, 0.18, 0.45, 0.75 }, { 1, 0.03, 0.15, 0.40 } };
	static const double DIVERGING[][4] = { { 0, 0.15, 0.30, 0.70 }, { 0.5, 0.96, 0.96, 0.96 }, { 1, 0.75, 0.15, 0.12 } };
	static const double MAGMA[][4] = { { 0, 0.02, 0.02, 0.08 }, { 0.3, 0.38, 0.08, 0.50 }, { 0.6, 0.85, 0.25, 0.35 }, { 0.85, 0.99, 0.62, 0.30 }, { 1, 0.99, 0.95, 0.70 } };
	parallel_rows(size, [&](int py) {
		for (int px = 0; px < size; px++) {
			int x = std::clamp(int((px + 0.5) / size * n), 0, n - 1), z = std::clamp(int((py + 0.5) / size * n), 0, n - 1);
			size_t i = size_t(z) * n + x;
			double col[3];
			if (palette == 4) {
				for (int k = 0; k < 3; k++)
					col[k] = values[i * 3 + k];
			} else {
				double t = (values[i] - lo) / std::max(1e-12, hi - lo);
				if (palette == 1)
					ramp(BLUE, 4, t, col);
				else if (palette == 2)
					ramp(DIVERGING, 3, t, col);
				else if (palette == 3)
					ramp(MAGMA, 5, t, col);
				else
					ramp(GRAY, 2, t, col);
			}
			uint8_t *o = &img.rgb[(size_t(py) * size + px) * 3];
			for (int k = 0; k < 3; k++)
				o[k] = to_byte(col[k]);
		}
	});
	return img;
}

int text_width(const std::string &s, int scale) {
	return int(s.size()) * 6 * scale;
}

void text(Image &img, int x, int y, const std::string &s, int scale, const uint8_t color[3], bool box) {
	scale = std::max(1, scale);
	if (box) {
		int w = text_width(s, scale) + 4 * scale, h = 11 * scale;
		for (int py = std::max(0, y - 2 * scale); py < std::min(img.height, y - 2 * scale + h); py++)
			for (int px = std::max(0, x - 2 * scale); px < std::min(img.width, x - 2 * scale + w); px++) {
				uint8_t *p = &img.rgb[(size_t(py) * img.width + px) * 3];
				for (int k = 0; k < 3; k++)
					p[k] = uint8_t(p[k] * 0.35);
			}
	}
	int cx = x;
	for (char ch : s) {
		const Glyph *g = find_glyph(ch);
		if (g) {
			for (int r = 0; r < 7; r++)
				for (int c = 0; c < 5; c++)
					if (g->rows[r][c] == '#')
						for (int dy = 0; dy < scale; dy++)
							for (int dx = 0; dx < scale; dx++) {
								int px = cx + c * scale + dx, py = y + r * scale + dy;
								if (px < 0 || py < 0 || px >= img.width || py >= img.height)
									continue;
								uint8_t *p = &img.rgb[(size_t(py) * img.width + px) * 3];
								p[0] = color[0];
								p[1] = color[1];
								p[2] = color[2];
							}
		}
		cx += 6 * scale;
	}
}

Image resize(const Image &src, int width, int height) {
	Image out;
	out.resize(width, height);
	if (src.width <= 0 || src.height <= 0)
		return out;
	for (int y = 0; y < height; y++) {
		int y0 = y * src.height / height, y1 = std::max(y0 + 1, (y + 1) * src.height / height);
		for (int x = 0; x < width; x++) {
			int x0 = x * src.width / width, x1 = std::max(x0 + 1, (x + 1) * src.width / width);
			double sum[3] = { 0, 0, 0 };
			int count = 0;
			for (int sy = y0; sy < y1 && sy < src.height; sy++)
				for (int sx = x0; sx < x1 && sx < src.width; sx++) {
					const uint8_t *p = &src.rgb[(size_t(sy) * src.width + sx) * 3];
					sum[0] += p[0];
					sum[1] += p[1];
					sum[2] += p[2];
					count++;
				}
			uint8_t *o = &out.rgb[(size_t(y) * width + x) * 3];
			for (int k = 0; k < 3; k++)
				o[k] = uint8_t(sum[k] / std::max(1, count));
		}
	}
	return out;
}

} // namespace terrain_render
