#ifndef RETARGET_H
#define RETARGET_H

#include <vector>

// Paper, seccion 5.1 "Height retargeting" (Schott et al. 2024, p. 7).
//
// La erosion baja un poco las crestas y los picos. El retargeting les devuelve la
// altura del terreno de entrada T0 sin romper los detalles de la erosion:
//   1. C = puntos de control = celdas con area de drenaje a(c) < a0 (crestas y picos:
//      les llega muy poca agua). a se calcula con el flow routing de la seccion 4.1.
//   2. delta(c) = h0(c) - hA(c): cuanto bajo cada punto de control.
//   3. Mapa de error E por difusion con restricciones (Dirichlet en C):
//        E_{i+1}(p) = m(p) E_0(p) + (1 - m(p)) (E_i - Laplaciano(E_i))(p)
//      con el Laplaciano normalizado L(E)(p) = E(p) - promedio de sus 4 vecinos,
//      o sea E - L(E) = promedio de los 4 vecinos (un paso de Jacobi).
//      El paper usa n = 500 iteraciones, sin dejar que converja en todo el dominio.
//   4. hR = hA + E.

struct RetargetStats {
	int constrained = 0; // cantidad de puntos de control
	double mean_delta = 0.0; // promedio de delta en los puntos de control (m)
	double max_delta = 0.0; // mayor |delta| (m)
	double max_constraint_error = 0.0; // |hR - h0| maximo en C (deberia ser ~0)
	double mean_abs_correction = 0.0; // promedio de |E| en todo el mapa (m)
	double seconds = 0.0;
};

// Area de drenaje en celdas (cada celda aporta 1), flujo a los 8 vecinos mas bajos
// con pesos pendiente^1.3 (paper 4.1). Devuelve solo lo que LLEGA de otras celdas.
std::vector<double> incoming_drainage_cells(const std::vector<double> &h, int n, double cell);

// h: terreno amplificado A(T0) (se modifica). h0: terreno de entrada T0, misma grilla.
// a0: umbral de area de drenaje en celdas. iterations: pasos de difusion (paper: 500).
// mask (opcional): 1 en los puntos de control. error (opcional): mapa E aplicado.
RetargetStats retarget_heights(std::vector<double> &h, const std::vector<double> &h0, int n, double cell,
		double a0, int iterations, std::vector<unsigned char> *mask = nullptr, std::vector<double> *error = nullptr);

#endif // RETARGET_H
