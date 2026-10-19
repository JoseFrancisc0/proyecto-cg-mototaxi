#include "erosion.h"
#include <cmath>
#include <algorithm>
#include <thread>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>

// ============================================================================
// Port en CPU de los 3 shaders del paper (repo oficial H-Schott/MultiScaleErosion).
// En la GPU, main() corre una vez por celda en paralelo. Aqui lo mismo se hace
// con un doble for (iy, ix) que lee las grillas "in" y escribe en las "out";
// al final de cada paso se intercambian (std::swap), igual que el doble buffer.
// ============================================================================

namespace {

// Valores por defecto de los uniform de los shaders (el C++ del paper no los cambia).
const float FLOW_P = 1.3f;              // exponente del flow routing
// erosion.glsl
const float K_EROSION = 0.0005f;
const float P_SA = 0.8f;                // exponente del area de drenaje
const float P_SL = 2.0f;                // exponente de la pendiente
const float DT = 1.0f;
const float MAX_SPE = 10000.0f;
// thermal.glsl
const float EPS_THERMAL = 0.00005f;
const float NOISE_MIN = 0.9f;           // tangente del angulo de talud minima
const float NOISE_MAX = 1.4f;           // tangente del angulo de talud maxima
const float NOISE_WAVELENGTH = 0.0023f;
// deposition.glsl
const float DEPOSITION_STRENGTH = 1.0f;
const float RAIN = 2.6f;

// Escala del paper: caja de 20 km x 20 km (Box2(Vector2::Null, 10 * 1000) en main.cpp).
const double PAPER_SIZE = 20000.0;

// Vecinos en el mismo orden que next8[] de los shaders.
const int DX[8] = {0, 1, 1, 1, 0, -1, -1, -1};
const int DY[8] = {1, 1, 0, -1, -1, -1, 0, 1};

struct Grid {
    int n;          // celdas por lado
    float cell;     // tamano de celda (cellDiag.x == cellDiag.y)
    float dist[8];  // distancia a cada vecino
    const std::vector<float> *hardness = nullptr;
    const std::vector<float> *talus = nullptr;
};

// Reparte las filas y = 0..n-1 entre los nucleos del procesador.
// Cada fila de un paso solo lee las grillas "in" y escribe su propia parte de las "out",
// asi que el resultado es identico al de un solo hilo.
class RowExecutor {
    std::vector<std::thread> workers;
    std::mutex mutex;
    std::condition_variable start, finished;
    std::function<void(int)> job;
    int rows = 0, pending = 0;
    unsigned revision = 0;
    bool stopping = false;
public:
    RowExecutor() {
        int count = std::max(1, std::min(8, int(std::thread::hardware_concurrency())));
        for (int id = 0; id < count; id++) workers.emplace_back([this, id, count]() {
            unsigned seen = 0;
            std::unique_lock<std::mutex> lock(mutex);
            while (true) {
                start.wait(lock, [&]() { return stopping || revision != seen; });
                if (stopping) return;
                seen = revision;
                auto current_job = job;
                int begin = rows * id / count, end = rows * (id + 1) / count;
                lock.unlock();
                for (int y = begin; y < end; y++) current_job(y);
                lock.lock();
                if (--pending == 0) finished.notify_one();
            }
        });
    }
    ~RowExecutor() {
        { std::lock_guard<std::mutex> lock(mutex); stopping = true; }
        start.notify_all();
        for (auto &worker : workers) worker.join();
    }
    void run(int n, std::function<void(int)> row) {
        std::unique_lock<std::mutex> lock(mutex);
        job = std::move(row); rows = n; pending = int(workers.size()); revision++;
        start.notify_all();
        finished.wait(lock, [&]() { return pending == 0; });
        job = {};
    }
};
thread_local RowExecutor *active_executor = nullptr;
template <typename RowFunc>
void parallel_rows(int n, RowFunc row) {
    if (n < 64 || !active_executor) { for (int y = 0; y < n; y++) row(y); }
    else active_executor->run(n, row);
}

inline bool inside(const Grid &g, int x, int y) {
    return x >= 0 && x < g.n && y >= 0 && y < g.n;
}

// Slope(p + next8[i], p) de los shaders: positiva si el vecino esta mas abajo.
inline float slope_to(const Grid &g, const std::vector<float> &h, int x, int y, int i) {
    int qx = x + DX[i], qy = y + DY[i];
    if (!inside(g, qx, qy)) return 0.0f;
    return (h[y * g.n + x] - h[qy * g.n + qx]) / g.dist[i];
}

// GetFlowSteepest(): indice del vecino con la mayor bajada (-1 si no hay ninguno).
int steepest_neighbor(const Grid &g, const std::vector<float> &h, int x, int y) {
    int best = -1;
    float max_slope = 0.0f;
    for (int i = 0; i < 8; i++) {
        float s = slope_to(g, h, x, y, i);
        if (s > max_slope) { max_slope = s; best = i; }
    }
    return best;
}

// GetFlowWeighted() para todas las celdas: W[c * 8 + i] = fraccion del agua de la celda c
// que se va hacia su vecino i. Se calcula una vez por iteracion y se reutiliza
// (en la GPU se recalculaba 8 veces por celda; el resultado es el mismo).
// min_sum: 0.00001 en erosion.glsl, 0 en deposition.glsl.
void flow_weights(const Grid &g, const std::vector<float> &h, std::vector<float> &W, float min_sum) {
    parallel_rows(g.n, [&](int y) {
        for (int x = 0; x < g.n; x++) {
            float *w = &W[(y * g.n + x) * 8];
            float sum = 0.0f;
            for (int i = 0; i < 8; i++) {
                float s = slope_to(g, h, x, y, i);
                if (s > 0.0f) { w[i] = std::pow(s, FLOW_P); sum += w[i]; }
                else w[i] = 0.0f;
            }
            if (sum <= min_sum) sum = 1.0f;
            for (int i = 0; i < 8; i++) w[i] /= sum;
        }
    });
}

// ComputeIncomingFlowWeighted() / SedIncomingWeighted(): lo que le llega a (x, y)
// desde sus vecinos. El vecino q = p + next8[i] manda hacia p por su direccion (i + 4) % 8.
inline float incoming(const Grid &g, const std::vector<float> &W, const std::vector<float> &field, int x, int y) {
    float total = 0.0f;
    for (int i = 0; i < 8; i++) {
        int qx = x + DX[i], qy = y + DY[i];
        if (!inside(g, qx, qy)) continue;
        int q = qy * g.n + qx;
        float w = W[q * 8 + (i + 4) % 8];
        if (w > 0.0f) total += w * field[q];
    }
    return total;
}

// ---------------------------------------------------------------------------
// 1. Erosion fluvial (erosion.glsl)
// ---------------------------------------------------------------------------
void fluvial_erosion(const Grid &g, std::vector<float> &h, int steps) {
    int count = g.n * g.n;
    std::vector<float> h_out(count), stream(count, 0.0f), stream_out(count), W(count * 8);
    float rain = std::sqrt(2.0f) * g.cell;  // 1.0f * length(cellDiag)

    for (int s = 0; s < steps; s++) {
        flow_weights(g, h, W, 0.00001f);
        parallel_rows(g.n, [&](int y) {
            for (int x = 0; x < g.n; x++) {
                int id = y * g.n + x;

                // acumulacion del agua en p
                float st = rain + incoming(g, W, stream, x, y);

                // pendiente mas empinada y celda receptora
                int d = steepest_neighbor(g, h, x, y);
                float receiver_h = h[id];
                float steepest = 0.0f;
                if (d >= 0) {
                    receiver_h = h[(y + DY[d]) * g.n + (x + DX[d])];
                    steepest = std::fabs(slope_to(g, h, x, y, d));
                }

                // stream power
                float spe = std::pow(st, P_SA) * std::min(std::max(std::pow(steepest, P_SL), 0.0f), 1.0f);
                spe = std::min(std::max(spe, 0.0f), MAX_SPE);
                spe *= K_EROSION;
                if (g.hardness) spe *= 1.0f - (*g.hardness)[id];

                // nueva altura: nunca por debajo de la celda receptora
                h_out[id] = std::max(h[id] - DT * spe, receiver_h);
                stream_out[id] = st;
            }
        });
        std::swap(h, h_out);
        std::swap(stream, stream_out);
    }
}

// ---------------------------------------------------------------------------
// Ruido simplex 3D de thermal.glsl (snoise), copiado tal cual.
// ---------------------------------------------------------------------------
struct V3 { float x, y, z; };
struct V4 { float x, y, z, w; };

inline float mod289(float v) { return v - std::floor(v * (1.0f / 289.0f)) * 289.0f; }
inline float permute(float v) { return mod289(((v * 34.0f) + 1.0f) * v); }
inline float step_f(float edge, float v) { return v < edge ? 0.0f : 1.0f; }
inline float dot3(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

float snoise(V3 v) {
    const float Cx = 1.0f / 6.0f, Cy = 1.0f / 3.0f;
    float s = (v.x + v.y + v.z) * Cy;
    V3 i = {std::floor(v.x + s), std::floor(v.y + s), std::floor(v.z + s)};
    float t = (i.x + i.y + i.z) * Cx;
    V3 x0 = {v.x - i.x + t, v.y - i.y + t, v.z - i.z + t};

    V3 g = {step_f(x0.y, x0.x), step_f(x0.z, x0.y), step_f(x0.x, x0.z)};
    V3 l = {1.0f - g.x, 1.0f - g.y, 1.0f - g.z};
    V3 i1 = {std::min(g.x, l.z), std::min(g.y, l.x), std::min(g.z, l.y)};
    V3 i2 = {std::max(g.x, l.z), std::max(g.y, l.x), std::max(g.z, l.y)};

    V3 x1 = {x0.x - i1.x + Cx, x0.y - i1.y + Cx, x0.z - i1.z + Cx};
    V3 x2 = {x0.x - i2.x + Cy, x0.y - i2.y + Cy, x0.z - i2.z + Cy};
    V3 x3 = {x0.x - 0.5f, x0.y - 0.5f, x0.z - 0.5f};

    i = {mod289(i.x), mod289(i.y), mod289(i.z)};
    float p[4];
    float zs[4] = {0.0f, i1.z, i2.z, 1.0f};
    float ys[4] = {0.0f, i1.y, i2.y, 1.0f};
    float xs[4] = {0.0f, i1.x, i2.x, 1.0f};
    for (int k = 0; k < 4; k++)
        p[k] = permute(permute(permute(i.z + zs[k]) + i.y + ys[k]) + i.x + xs[k]);

    const float n_ = 0.142857142857f;
    V3 ns = {n_ * 2.0f - 0.0f, n_ * 0.5f - 1.0f, n_ * 1.0f - 0.0f};  // n_ * D.wyz - D.xzx

    float gx[4], gy[4], h[4];
    for (int k = 0; k < 4; k++) {
        float j = p[k] - 49.0f * std::floor(p[k] * ns.z * ns.z);
        float x_ = std::floor(j * ns.z);
        float y_ = std::floor(j - 7.0f * x_);
        gx[k] = x_ * ns.x + ns.y;
        gy[k] = y_ * ns.x + ns.y;
        h[k] = 1.0f - std::fabs(gx[k]) - std::fabs(gy[k]);
    }

    V4 b0 = {gx[0], gx[1], gy[0], gy[1]};
    V4 b1 = {gx[2], gx[3], gy[2], gy[3]};
    V4 s0 = {std::floor(b0.x) * 2.0f + 1.0f, std::floor(b0.y) * 2.0f + 1.0f, std::floor(b0.z) * 2.0f + 1.0f, std::floor(b0.w) * 2.0f + 1.0f};
    V4 s1 = {std::floor(b1.x) * 2.0f + 1.0f, std::floor(b1.y) * 2.0f + 1.0f, std::floor(b1.z) * 2.0f + 1.0f, std::floor(b1.w) * 2.0f + 1.0f};
    V4 sh = {-step_f(h[0], 0.0f), -step_f(h[1], 0.0f), -step_f(h[2], 0.0f), -step_f(h[3], 0.0f)};

    // a0 = b0.xzyw + s0.xzyw * sh.xxyy ; a1 = b1.xzyw + s1.xzyw * sh.zzww
    V4 a0 = {b0.x + s0.x * sh.x, b0.z + s0.z * sh.x, b0.y + s0.y * sh.y, b0.w + s0.w * sh.y};
    V4 a1 = {b1.x + s1.x * sh.z, b1.z + s1.z * sh.z, b1.y + s1.y * sh.w, b1.w + s1.w * sh.w};

    V3 p0 = {a0.x, a0.y, h[0]};
    V3 p1 = {a0.z, a0.w, h[1]};
    V3 p2 = {a1.x, a1.y, h[2]};
    V3 p3 = {a1.z, a1.w, h[3]};

    float norm[4] = {dot3(p0, p0), dot3(p1, p1), dot3(p2, p2), dot3(p3, p3)};
    for (int k = 0; k < 4; k++) norm[k] = 1.79284291400159f - 0.85373472095314f * norm[k];
    p0 = {p0.x * norm[0], p0.y * norm[0], p0.z * norm[0]};
    p1 = {p1.x * norm[1], p1.y * norm[1], p1.z * norm[1]};
    p2 = {p2.x * norm[2], p2.y * norm[2], p2.z * norm[2]};
    p3 = {p3.x * norm[3], p3.y * norm[3], p3.z * norm[3]};

    float m[4] = {dot3(x0, x0), dot3(x1, x1), dot3(x2, x2), dot3(x3, x3)};
    for (int k = 0; k < 4; k++) { m[k] = std::max(0.6f - m[k], 0.0f); m[k] = m[k] * m[k]; m[k] = m[k] * m[k]; }

    return 42.0f * (m[0] * dot3(p0, x0) + m[1] * dot3(p1, x1) + m[2] * dot3(p2, x2) + m[3] * dot3(p3, x3));
}

// ---------------------------------------------------------------------------
// 2. Estabilizacion termica (thermal.glsl)
// ---------------------------------------------------------------------------
void thermal_erosion(const Grid &g, std::vector<float> &h, int steps) {
    int count = g.n * g.n;
    std::vector<float> h_out(count);
    float matter = EPS_THERMAL * g.cell * g.cell;

    for (int s = 0; s < steps; s++) {
        parallel_rows(g.n, [&](int y) {
            for (int x = 0; x < g.n; x++) {
                int id = y * g.n + x;
                float z = h[id];

                float tan_angle;
                if (g.talus) {
                    // s0 is already a spatially varying regional map. Avoid
                    // evaluating 3D simplex noise again in every iteration.
                    tan_angle = (*g.talus)[id];
                } else {
                    V3 pt = {x * g.cell * NOISE_WAVELENGTH, y * g.cell * NOISE_WAVELENGTH, z * NOISE_WAVELENGTH};
                    float t = snoise(pt) * 0.5f + 0.5f;
                    tan_angle = NOISE_MIN + (NOISE_MAX - NOISE_MIN) * t;
                }

                // vecinos 3x3 con borde periodico, como el shader
                float receive = 0.0f, distribute = 0.0f;
                for (int i = 0; i < 3; i++) {
                    for (int j = 0; j < 3; j++) {
                        if (i == 1 && j == 1) continue;
                        int tx = (x + i - 1 + g.n) % g.n;
                        int ty = (y + j - 1 + g.n) % g.n;
                        float ddx = float(x - tx) * g.cell, ddy = float(y - ty) * g.cell;
                        float d = std::sqrt(ddx * ddx + ddy * ddy);
                        float sample = h[ty * g.n + tx];
                        if ((sample - z) / d > tan_angle) receive += 1.0f;
                        if ((z - sample) / d > tan_angle) distribute += 1.0f;
                    }
                }
                h_out[id] = z + matter * (receive - distribute);
            }
        });
        std::swap(h, h_out);
    }
}

// ---------------------------------------------------------------------------
// 3. Deposicion de sedimentos (deposition.glsl)
// ---------------------------------------------------------------------------
void deposition(const Grid &g, std::vector<float> &h, int steps) {
    int count = g.n * g.n;
    std::vector<float> h_out(count), stream(count, 0.0f), stream_out(count);
    std::vector<float> sed(count, 0.0f), sed_out(count), W(count * 8);
    float cell_area = g.cell * g.cell * 0.00001f;

    for (int s = 0; s < steps; s++) {
        flow_weights(g, h, W, 0.0f);
        parallel_rows(g.n, [&](int y) {
            for (int x = 0; x < g.n; x++) {
                int id = y * g.n + x;
                float height = h[id];
                float sd = sed[id];

                int d = steepest_neighbor(g, h, x, y);
                float steepest = (d >= 0) ? slope_to(g, h, x, y, d) : 0.0f;

                // CheckPit(): si el agua puede bajar a algun vecino, no se acumula sedimento aqui
                if (d >= 0) sd = 0.0f;

                // agua y sedimento que llegan
                float st = RAIN * cell_area + incoming(g, W, stream, x, y);
                sd += incoming(g, W, sed, x, y);

                float speed = std::min(std::max(steepest * steepest, 0.0f), 1.0f);
                float stream_power = std::pow(st, 0.3f) * speed;

                // depositar
                if (DEPOSITION_STRENGTH * sd > stream_power) {
                    float deposit = std::min(sd, (DEPOSITION_STRENGTH * sd - stream_power) * 0.1f);
                    height += deposit;
                    sd = std::max(0.0f, sd - deposit);
                }
                sd += 0.1f * stream_power;

                h_out[id] = height;
                stream_out[id] = st;
                sed_out[id] = sd;
            }
        });
        std::swap(h, h_out);
        std::swap(stream, stream_out);
        std::swap(sed, sed_out);
    }
}

// ---------------------------------------------------------------------------
// 4. Upsampling x2 bicubico (U_k en el paper)
// El paper describe un upsampling bicubico. Ojo: en el repo oficial,
// SetResolution(x, y, true) termina usando Value(), que es bilineal
// (las dos ramas del if son iguales). Aqui se usa bicubica de verdad
// (Catmull-Rom), para que la pendiente sea continua entre celdas.
// Pasa de nc x nc a (2 * (nc - 1) + 1) x (2 * (nc - 1) + 1): los puntos
// viejos se conservan y se agrega uno nuevo entre cada par.
// ---------------------------------------------------------------------------
inline float cubic(float p0, float p1, float p2, float p3, float t) {
    return p1 + 0.5f * t * (p2 - p0 + t * (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3 + t * (3.0f * (p1 - p2) + p3 - p0)));
}

std::vector<float> upsample_x2(const std::vector<float> &h, int nc) {
    int nf = 2 * (nc - 1) + 1;

    // valor de la grilla gruesa sin salirse del borde
    auto at = [&](int x, int y) {
        x = std::min(std::max(x, 0), nc - 1);
        y = std::min(std::max(y, 0), nc - 1);
        return h[y * nc + x];
    };

    // 1) interpolar en x: grilla de nf columnas x nc filas
    std::vector<float> tmp(nf * nc);
    for (int y = 0; y < nc; y++) {
        for (int i = 0; i < nf; i++) {
            int x = i / 2;
            if (i % 2 == 0) tmp[y * nf + i] = at(x, y);
            else tmp[y * nf + i] = cubic(at(x - 1, y), at(x, y), at(x + 1, y), at(x + 2, y), 0.5f);
        }
    }

    // 2) interpolar en y: grilla final nf x nf
    std::vector<float> out(nf * nf);
    for (int j = 0; j < nf; j++) {
        int y = j / 2;
        for (int i = 0; i < nf; i++) {
            if (j % 2 == 0) {
                out[j * nf + i] = tmp[y * nf + i];
            } else {
                int y0 = std::max(y - 1, 0), y2 = std::min(y + 1, nc - 1), y3 = std::min(y + 2, nc - 1);
                out[j * nf + i] = cubic(tmp[y0 * nf + i], tmp[y * nf + i], tmp[y2 * nf + i], tmp[y3 * nf + i], 0.5f);
            }
        }
    }
    return out;
}

// Pasos de cada ronda en PredefinedErosion() (main.cpp): 256 -> 512 -> 1024 -> 2048
const int LEVEL_FLUVIAL[4]    = {3000, 1500, 700, 400};
const int LEVEL_THERMAL[4]    = {600, 1000, 2000, 6000};
const int LEVEL_DEPOSITION[4] = {2000, 700, 200, 150};

} // namespace

// ============================================================================
// Caja negra: H entra con nuestras unidades y sale erosionada en las mismas unidades.
// ============================================================================
void erode_terrain(std::vector<double> &H, int n, double cell_size, const ErosionSteps &steps) {
    if (n < 3 || H.size() != size_t(n) * size_t(n) ||
        !std::isfinite(cell_size) || cell_size <= 0.0) return;
    for (double height : H) {
        if (!std::isfinite(height)) return;
    }

    // Lifetime is scoped to this call: joining threads in a Windows TLS destructor
    // can deadlock under the loader lock when a Godot worker exits.
    RowExecutor executor;
    active_executor = &executor;

    // Cuantas rondas de upsampling: la grilla base debe quedar entera y no muy chica
    int levels = std::min(std::max(steps.levels, 0), 3);
    while (levels > 0 && (((n - 1) % (1 << levels)) != 0 || (n - 1) / (1 << levels) < 32)) levels--;

    // 1. Pasar a la escala del paper (20 km de lado). La escala es la misma en
    //    horizontal y en vertical, asi las pendientes no cambian.
    double h_min = *std::min_element(H.begin(), H.end());
    double scale = PAPER_SIZE / ((n - 1) * cell_size);

    // 2. Bajar a la resolucion base: tomar 1 de cada 2^levels puntos
    int step = 1 << levels;
    int nb = (n - 1) / step + 1;
    std::vector<float> h(nb * nb);
    for (int y = 0; y < nb; y++)
        for (int x = 0; x < nb; x++)
            h[y * nb + x] = float((H[(y * step) * n + (x * step)] - h_min) * scale);

    // 3. Multiescala: en cada ronda, subir x2 (menos en la primera) y erosionar
    int nl = nb;
    for (int level = 0; level <= levels; level++) {
        if (level > 0) {
            h = upsample_x2(h, nl);
            nl = 2 * (nl - 1) + 1;
        }

        std::vector<float> hardness(nl * nl), talus(nl * nl);
        bool regional = steps.hardness.size() == H.size() && steps.talus.size() == H.size();
        if (regional) {
            int stride = (n - 1) / (nl - 1);
            for (int y = 0; y < nl; y++) for (int x = 0; x < nl; x++) {
                hardness[y * nl + x] = steps.hardness[y * stride * n + x * stride];
                talus[y * nl + x] = steps.talus[y * stride * n + x * stride];
            }
        }
        Grid g;
        g.n = nl;
        if (regional) { g.hardness = &hardness; g.talus = &talus; }
        g.cell = float(PAPER_SIZE / (nl - 1));
        for (int i = 0; i < 8; i++)
            g.dist[i] = g.cell * std::sqrt(float(DX[i] * DX[i] + DY[i] * DY[i]));

        // primera ronda: pasos del Inspector; siguientes: receta del paper
        int fl = (level == 0) ? steps.fluvial : LEVEL_FLUVIAL[level];
        int th = (level == 0) ? steps.thermal : LEVEL_THERMAL[level];
        int de = (level == 0) ? steps.deposition : LEVEL_DEPOSITION[level];
        fl = std::max(0, int(fl * steps.iteration_scale));
        th = std::max(0, int(th * steps.iteration_scale));
        de = std::max(0, int(de * steps.iteration_scale));

        auto begin = std::chrono::steady_clock::now();
        fluvial_erosion(g, h, fl);
        auto after_fluvial = std::chrono::steady_clock::now();
        thermal_erosion(g, h, th);
        auto after_thermal = std::chrono::steady_clock::now();
        deposition(g, h, de);
        auto end = std::chrono::steady_clock::now();
        if (steps.timings) steps.timings->push_back({nl,
            std::chrono::duration<double>(after_fluvial-begin).count(),
            std::chrono::duration<double>(after_thermal-after_fluvial).count(),
            std::chrono::duration<double>(end-after_thermal).count()});
    }

    // 4. Volver a nuestra escala (nl ya es igual a n)
    for (int i = 0; i < n * n; i++) H[i] = double(h[i]) / scale + h_min;
    active_executor = nullptr;
}
