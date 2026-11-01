#include "retarget.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <numeric>
#include <thread>

namespace {
const int DX8[8] = { 1, 1, 0, -1, -1, -1, 0, 1 };
const int DZ8[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };

// Reparte filas entre hilos. Cada fila solo lee "in" y escribe su parte de "out".
template <typename F>
void parallel_rows(int n, F row) {
	int threads = std::max(1, std::min(8, (int)std::thread::hardware_concurrency()));
	if (n < 64 || threads == 1) {
		for (int z = 0; z < n; z++)
			row(z);
		return;
	}
	std::vector<std::thread> pool;
	for (int t = 0; t < threads; t++) {
		int a = n * t / threads, b = n * (t + 1) / threads;
		pool.emplace_back([=]() {
			for (int z = a; z < b; z++)
				row(z);
		});
	}
	for (auto &th : pool)
		th.join();
}
} // namespace

std::vector<double> incoming_drainage_cells(const std::vector<double> &h, int n, double cell) {
	const int count = n * n;
	std::vector<double> area(count, 1.0);
	std::vector<int> order(count);
	std::iota(order.begin(), order.end(), 0);
	// De la celda mas alta a la mas baja: cuando se procesa una celda, ya le llego todo.
	std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return h[a] > h[b]; });
	const double diag = std::sqrt(2.0);
	for (int i : order) {
		int x = i % n, z = i / n;
		double w[8] = {}, sum = 0.0;
		for (int d = 0; d < 8; d++) {
			int qx = x + DX8[d], qz = z + DZ8[d];
			if (qx < 0 || qz < 0 || qx >= n || qz >= n)
				continue;
			double dist = cell * ((DX8[d] && DZ8[d]) ? diag : 1.0);
			double s = (h[i] - h[qz * n + qx]) / dist;
			if (s > 0.0) {
				w[d] = std::pow(s, 1.3);
				sum += w[d];
			}
		}
		if (sum <= 0.0)
			continue;
		for (int d = 0; d < 8; d++)
			if (w[d] > 0.0)
				area[(z + DZ8[d]) * n + x + DX8[d]] += area[i] * w[d] / sum;
	}
	for (double &a : area)
		a -= 1.0; // solo lo que llega de otras celdas
	return area;
}

RetargetStats retarget_heights(std::vector<double> &h, const std::vector<double> &h0, int n, double cell,
		double a0, int iterations, std::vector<unsigned char> *mask_out, std::vector<double> *error_out) {
	RetargetStats stats;
	const auto begin = std::chrono::steady_clock::now();
	if (n < 3 || h.size() != size_t(n) * n || h0.size() != h.size())
		return stats;
	const int count = n * n;

	// 1. Puntos de control: poca agua = cresta o pico.
	std::vector<double> area = incoming_drainage_cells(h, n, cell);
	std::vector<unsigned char> fixed(count, 0);
	std::vector<double> E(count, 0.0), next(count, 0.0);
	double sum_delta = 0.0;
	// Agregados propios (el paper solo pide a < a0), para que C sean crestas de verdad:
	//  - convexo: mas alto que el promedio de sus 8 vecinos. Descarta las zonas planas
	//    que deja la deposicion, que tampoco reciben agua pero no son crestas;
	//  - delta > 0: la erosion lo bajo. El retargeting compensa el material que se llevo
	//    la erosion ("bedrock detachment", seccion 7); no deshace los rellenos de sedimento.
	auto convex = [&](int i) {
		int x = i % n, z = i / n;
		double sum = 0.0;
		int k = 0;
		for (int d = 0; d < 8; d++) {
			int qx = x + DX8[d], qz = z + DZ8[d];
			if (qx < 0 || qz < 0 || qx >= n || qz >= n)
				continue;
			sum += h[qz * n + qx];
			k++;
		}
		return k > 0 && h[i] > sum / k + 1e-6;
	};
	for (int i = 0; i < count; i++)
		if (area[i] < a0 && h0[i] > h[i] && convex(i)) {
			fixed[i] = 1;
			E[i] = h0[i] - h[i]; // E0 = delta en C, 0 fuera
			sum_delta += E[i];
			stats.max_delta = std::max(stats.max_delta, std::fabs(E[i]));
			stats.constrained++;
		}
	stats.mean_delta = stats.constrained > 0 ? sum_delta / stats.constrained : 0.0;

	// 2. Difusion de Jacobi con restricciones fijas (bordes de Neumann).
	for (int it = 0; it < iterations && stats.constrained > 0; it++) {
		parallel_rows(n, [&](int z) {
			for (int x = 0; x < n; x++) {
				int i = z * n + x;
				if (fixed[i]) {
					next[i] = E[i];
					continue;
				}
				double s = 0.0;
				int k = 0;
				if (x > 0) { s += E[i - 1]; k++; }
				if (x < n - 1) { s += E[i + 1]; k++; }
				if (z > 0) { s += E[i - n]; k++; }
				if (z < n - 1) { s += E[i + n]; k++; }
				next[i] = s / k;
			}
		});
		E.swap(next);
	}

	// 3. hR = hA + E.
	double abs_sum = 0.0;
	for (int i = 0; i < count; i++) {
		h[i] += E[i];
		abs_sum += std::fabs(E[i]);
		if (fixed[i])
			stats.max_constraint_error = std::max(stats.max_constraint_error, std::fabs(h[i] - h0[i]));
	}
	stats.mean_abs_correction = abs_sum / count;
	if (mask_out)
		*mask_out = std::move(fixed);
	if (error_out)
		*error_out = std::move(E);
	stats.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - begin).count();
	return stats;
}
