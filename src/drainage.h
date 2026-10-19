#ifndef DRAINAGE_H
#define DRAINAGE_H
#include <vector>
// Paper 5.2 multiscale breaching with a priority-flood-guided full breach operator.
// Final routing uses the weighted 8-neighbor model from paper 4.1.
// This is NOT a replacement for the paper stream-power erosion.
struct DrainageField {
	int n = 0;
	double cell = 1;
	std::vector<int> receiver, order;
	std::vector<double> weights;
	double breach_max_depth = 0, breach_volume = 0;
	void breach_multiscale(std::vector<double> &height, int samples, double spacing, double radius);
	std::vector<double> accumulation, level;
	std::vector<unsigned char> channel, lake, protected_water;
	void compute(const std::vector<double> &height, int samples, double spacing, double threshold);
};
#endif
