#include "drainage.h"
#include <algorithm>
#include <cmath>
#include <numeric>
#include <queue>
namespace {
const int DX[8] = { 1, 1, 0, -1, -1, -1, 0, 1 };
const int DZ[8] = { 0, 1, 1, 1, 0, -1, -1, -1 };
// A full breach B: priority-flood finds spill paths; lower barriers along them.
// This is a CPU alternative to Barnes' B, not a verbatim port of that algorithm.
std::vector<double> full_breach(const std::vector<double> &h, int n, double cell) {
	using Item = std::pair<double, int>;
	std::priority_queue<Item, std::vector<Item>, std::greater<Item>> queue;
	std::vector<unsigned char> seen(h.size(), 0);
	std::vector<int> parent(h.size(), -1), order;
	auto seed = [&](int i) {if(!seen[i]){seen[i]=1;queue.push({h[i],i});} };
	for (int k = 0; k < n; k++) {
		seed(k);
		seed((n - 1) * n + k);
		seed(k * n);
		seed(k * n + n - 1);
	}
	while (!queue.empty()) {
		auto [level, i] = queue.top();
		queue.pop();
		order.push_back(i);
		for (int d = 0; d < 8; d++) {
			int x = i % n + DX[d], z = i / n + DZ[d];
			if (x < 0 || z < 0 || x >= n || z >= n)
				continue;
			int j = z * n + x;
			if (seen[j])
				continue;
			seen[j] = 1;
			parent[j] = i;
			queue.push({ std::max(level, h[j]), j });
		}
	}
	std::vector<double> result = h;
	double epsilon = std::max(0.00001, cell * .00001);
	for (auto it = order.rbegin(); it != order.rend(); ++it) {
		int i = *it, j = parent[i];
		if (j >= 0)
			result[j] = std::min(result[j], result[i] - epsilon);
	}
	return result;
}
// Normalized separable compact box kernel, supported within r cells per axis.
// Prefix sums keep the multiscale convolution linear in the sample count.
std::vector<double> smooth(const std::vector<double> &input, int n, int radius) {
	std::vector<double> temp(input.size()), output(input.size()), prefix(n + 1);
	for (int z = 0; z < n; z++) {
		prefix[0] = 0;
		for (int x = 0; x < n; x++)
			prefix[x + 1] = prefix[x] + input[z * n + x];
		for (int x = 0; x < n; x++) {
			int a = std::max(0, x - radius), b = std::min(n - 1, x + radius);
			temp[z * n + x] = (prefix[b + 1] - prefix[a]) / (b - a + 1);
		}
	}
	for (int x = 0; x < n; x++) {
		prefix[0] = 0;
		for (int z = 0; z < n; z++)
			prefix[z + 1] = prefix[z] + temp[z * n + x];
		for (int z = 0; z < n; z++) {
			int a = std::max(0, z - radius), b = std::min(n - 1, z + radius);
			output[z * n + x] = (prefix[b + 1] - prefix[a]) / (b - a + 1);
		}
	}
	return output;
}
} //namespace
void DrainageField::breach_multiscale(std::vector<double> &h, int samples, double spacing, double radius) {
	if (samples < 2 || h.size() != size_t(samples) * samples)
		return;
	const auto initial = h;
	// Paper section 5.2, p.8: T_next=T-(T-B(T))*g_r, r_next=r/2.
	int r = std::clamp(int(std::round(radius / spacing)), 1, std::max(1, (samples - 1) / 8));
	for (; r >= 2; r /= 2) {
		auto target = full_breach(h, samples, spacing);
		std::vector<double> cut(h.size());
		for (size_t i = 0; i < h.size(); i++)
			cut[i] = h[i] - target[i];
		auto spread = smooth(cut, samples, r);
		for (size_t i = 0; i < h.size(); i++)
			h[i] -= std::max(0.0, spread[i]);
	}
	// Last scale is the full B, as required for an actually draining heightfield.
	h = full_breach(h, samples, spacing);
	breach_max_depth = 0;
	breach_volume = 0;
	for (size_t i = 0; i < h.size(); i++) {
		double cut = initial[i] - h[i];
		breach_max_depth = std::max(breach_max_depth, cut);
		breach_volume += cut * spacing * spacing;
	}
}
void DrainageField::compute(const std::vector<double> &h, int samples, double spacing, double threshold) {
	n = samples;
	cell = spacing;
	int count = n * n;
	receiver.assign(count, -1);
	order.resize(count);
	std::iota(order.begin(), order.end(), 0);
	std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return h[a] < h[b]; });
	level = h;
	accumulation.assign(count, cell * cell);
	weights.assign(size_t(count) * 8, 0);
	channel.assign(count, 0);
	lake.assign(count, 0);
	protected_water.assign(count, 0);
	// Same downhill 8-neighbor weights and p=1.3 as paper 4.1 / CG-A flow_weights.
	for (int i = 0; i < count; i++) {
		// Boundary cells are open outlets, not additional sources routed back inland.
		if (i % n == 0 || i % n == n - 1 || i / n == 0 || i / n == n - 1)
			continue;
		double sum = 0, best = 0;
		for (int d = 0; d < 8; d++) {
			int j = (i / n + DZ[d]) * n + i % n + DX[d];
			double slope = (h[i] - h[j]) / (cell * ((DX[d] && DZ[d]) ? std::sqrt(2.0) : 1.0));
			if (slope > 0) {
				weights[size_t(i) * 8 + d] = std::pow(slope, 1.3);
				sum += weights[size_t(i) * 8 + d];
				if (slope > best) {
					best = slope;
					receiver[i] = j;
				}
			}
		}
		if (sum > 0)
			for (int d = 0; d < 8; d++)
				weights[size_t(i) * 8 + d] /= sum;
	}
	for (auto it = order.rbegin(); it != order.rend(); ++it) {
		int i = *it;
		for (int d = 0; d < 8; d++)
			if (weights[size_t(i) * 8 + d] > 0) {
				int j = (i / n + DZ[d]) * n + i % n + DX[d];
				accumulation[j] += accumulation[i] * weights[size_t(i) * 8 + d];
			}
	}
	for (int i = 0; i < count; i++)
		channel[i] = accumulation[i] >= threshold;
	// Complete visible main channels downstream; an MFD split may reduce area locally.
	for (auto it = order.rbegin(); it != order.rend(); ++it)
		if (channel[*it] && receiver[*it] >= 0)
			channel[receiver[*it]] = 1;
	for (int i = 0; i < count; i++)
		if (channel[i]) {
			int radius = std::max(1, int(std::ceil(5.0 / cell)));
			for (int dz = -radius; dz <= radius; dz++)
				for (int dx = -radius; dx <= radius; dx++) {
					int x = i % n + dx, z = i / n + dz;
					if (x >= 0 && z >= 0 && x < n && z < n && dx * dx + dz * dz <= radius * radius)
						protected_water[z * n + x] = 1;
				}
		}
}
