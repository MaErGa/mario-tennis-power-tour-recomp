// Pruebas de los filtros de imagen del parche 0004 (parches/gbarecomp-0004-*.patch).
// No dependen de SDL ni de la ROM: usan imágenes inventadas. Las lanza probar_filtros.sh,
// que extrae el bloque de filtros del host_window.cpp ya parcheado y lo incluye aquí.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include "filtros_extraido.inc"

static int g_fallos = 0;
#define COMPROBAR(cond, ...)                                              \
    do {                                                                  \
        if (!(cond)) {                                                    \
            ++g_fallos;                                                   \
            std::printf("FALLO (línea %d): %s\n  ", __LINE__, #cond);     \
            std::printf(__VA_ARGS__);                                     \
            std::printf("\n");                                            \
        }                                                                 \
    } while (0)

using namespace mtp_filtros;

// Generador pseudoaleatorio sencillo (siempre la misma secuencia).
static uint32_t g_semilla = 12345u;
static uint32_t azar() { g_semilla = g_semilla * 1664525u + 1013904223u; return g_semilla >> 8; }

// Imagen con pocos colores distintos: así hay muchas igualdades entre vecinos.
static std::vector<uint32_t> imagen_azar(int w, int h, int colores) {
    static const uint32_t paleta[] = {0xFF000000u, 0xFFFF0000u, 0xFF00FF00u, 0xFF0000FFu,
                                      0xFFFFFF00u, 0xFFFFFFFFu};
    std::vector<uint32_t> v(static_cast<std::size_t>(w) * h);
    for (auto& p : v) p = paleta[azar() % static_cast<uint32_t>(colores)];
    return v;
}

static uint32_t px(const std::vector<uint32_t>& v, int w, int h, int x, int y) {
    x = x < 0 ? 0 : (x >= w ? w - 1 : x);
    y = y < 0 ? 0 : (y >= h ? h - 1 : y);
    return v[static_cast<std::size_t>(y) * w + x];
}

int main() {
    // ── factor() y factor_nitido() ────────────────────────────────────────────
    COMPROBAR(factor(kNearest) == 0 && factor(kLinear) == 0 && factor(kNitido) == 0, "sin factor propio");
    COMPROBAR(factor(kScale2x) == 2 && factor(kScale3x) == 3 && factor(kScale4x) == 4, "Scale2x/3x/4x");
    COMPROBAR(factor(kHdSuave) == 4, "HD smooth");
    COMPROBAR(factor(kRejillaLcd) == 0 && factor(kCrt) == 0, "LCD y CRT no tienen factor propio (base nítida + máscara)");
    COMPROBAR(es_nitido(kNitido) && es_nitido(kRejillaLcd) && es_nitido(kCrt) && !es_nitido(kScale2x) && !es_nitido(kHdSuave), "es_nitido");
    COMPROBAR(usa_mascara(kRejillaLcd) && usa_mascara(kCrt) && !usa_mascara(kNitido) && !usa_mascara(kScale4x), "usa_mascara");
    COMPROBAR(factor_post(1280, 480) == 2 && factor_post(1620, 480) == 3 && factor_post(720, 960) == 1 &&
              factor_post(5000, 480) == 4 && factor_post(1920, 960) == 2 && factor_post(0, 480) == 1 && factor_post(1000, 0) == 1,
              "factor_post");
    COMPROBAR(factor_post(1920, 700) == 2 && factor_post(4000, 600) == 3, "factor_post respeta el tope de 2048 de ancho");
    COMPROBAR(escala_total(kScale2x, 5, 3) == 6 && escala_total(kScale4x, 5, 1) == 4 && escala_total(kCrt, 5, 3) == 5 &&
              escala_total(kNitido, 4, 1) == 4, "escala_total");
    COMPROBAR(factor_nitido(1080, 240) == 4, "1080/240 = 4");
    COMPROBAR(factor_nitido(1280, 240) == 5, "1280/240 = 5 (tamaño fraccionario)");
    COMPROBAR(factor_nitido(300, 240) == 0, "ventana pequeña: no se amplía");
    COMPROBAR(factor_nitido(5000, 240) == 6, "tope en 6");
    COMPROBAR(factor_nitido(1000, 0) == 0, "ancho base 0");

    // ── Scale2x frente a la definición de la especificación ───────────────────
    {
        const int w = 17, h = 11;
        const auto s = imagen_azar(w, h, 3);
        std::vector<uint32_t> d; Buffers b;
        COMPROBAR(aplicar(kScale2x, 0, s.data(), w, h, d, b), "aplicar Scale2x");
        COMPROBAR(d.size() == static_cast<std::size_t>(w) * h * 4, "tamaño Scale2x");
        int malos = 0;
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            const uint32_t E = px(s, w, h, x, y), B = px(s, w, h, x, y - 1), D = px(s, w, h, x - 1, y),
                           F = px(s, w, h, x + 1, y), H = px(s, w, h, x, y + 1);
            // Forma alternativa de la especificación (con las desigualdades explícitas).
            const uint32_t e0 = (D == B && B != F && D != H) ? D : E;
            const uint32_t e1 = (B == F && B != D && F != H) ? F : E;
            const uint32_t e2 = (D == H && D != B && H != F) ? D : E;
            const uint32_t e3 = (H == F && D != H && B != F) ? F : E;
            const std::size_t dw = static_cast<std::size_t>(w) * 2;
            if (d[(2 * y) * dw + 2 * x] != e0 || d[(2 * y) * dw + 2 * x + 1] != e1 ||
                d[(2 * y + 1) * dw + 2 * x] != e2 || d[(2 * y + 1) * dw + 2 * x + 1] != e3) ++malos;
        }
        COMPROBAR(malos == 0, "%d píxeles de Scale2x no coinciden con la especificación", malos);
    }

    // ── Scale3x frente a la especificación ────────────────────────────────────
    {
        const int w = 19, h = 13;
        const auto s = imagen_azar(w, h, 3);
        std::vector<uint32_t> d; Buffers b;
        COMPROBAR(aplicar(kScale3x, 0, s.data(), w, h, d, b), "aplicar Scale3x");
        COMPROBAR(d.size() == static_cast<std::size_t>(w) * h * 9, "tamaño Scale3x");
        int malos = 0;
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            const uint32_t A = px(s, w, h, x - 1, y - 1), B = px(s, w, h, x, y - 1), C = px(s, w, h, x + 1, y - 1),
                           D = px(s, w, h, x - 1, y),     E = px(s, w, h, x, y),     F = px(s, w, h, x + 1, y),
                           G = px(s, w, h, x - 1, y + 1), H = px(s, w, h, x, y + 1), I = px(s, w, h, x + 1, y + 1);
            const uint32_t e[9] = {
                (D == B && B != F && D != H) ? D : E,
                ((D == B && B != F && D != H && E != C) || (B == F && B != D && F != H && E != A)) ? B : E,
                (B == F && B != D && F != H) ? F : E,
                ((D == B && B != F && D != H && E != G) || (D == H && D != B && H != F && E != A)) ? D : E,
                E,
                ((B == F && B != D && F != H && E != I) || (H == F && D != H && B != F && E != C)) ? F : E,
                (D == H && D != B && H != F) ? D : E,
                ((D == H && D != B && H != F && E != I) || (H == F && D != H && B != F && E != G)) ? H : E,
                (H == F && D != H && B != F) ? F : E};
            const std::size_t dw = static_cast<std::size_t>(w) * 3;
            for (int j = 0; j < 3; ++j) for (int i = 0; i < 3; ++i)
                if (d[(3 * y + j) * dw + 3 * x + i] != e[j * 3 + i]) ++malos;
        }
        COMPROBAR(malos == 0, "%d píxeles de Scale3x no coinciden con la especificación", malos);
    }

    // ── Una imagen de un solo color sale de un solo color con todos los filtros ─
    for (int f = kNitido; f < kTotal; ++f) {
        const int w = 8, h = 6;
        std::vector<uint32_t> s(static_cast<std::size_t>(w) * h, 0xFF336699u), d; Buffers b;
        const int n = es_nitido(f) ? 3 : factor(f);
        COMPROBAR(aplicar(f, 3, s.data(), w, h, d, b), "aplicar filtro %d", f);
        COMPROBAR(d.size() == static_cast<std::size_t>(w) * h * n * n, "tamaño del filtro %d", f);
        bool igual = true;
        for (uint32_t p : d) igual = igual && (p == 0xFF336699u);
        COMPROBAR(igual, "el filtro %d cambia una imagen plana", f);
        bool opaco = true;
        for (uint32_t p : d) opaco = opaco && ((p >> 24) == 0xFFu);
        COMPROBAR(opaco, "el filtro %d deja píxeles con transparencia", f);
    }

    // ── Nítido: cada píxel se convierte en un bloque n x n ────────────────────
    {
        const int w = 7, h = 5, n = 4;
        const auto s = imagen_azar(w, h, 6);
        std::vector<uint32_t> d; Buffers b;
        COMPROBAR(aplicar(kNitido, n, s.data(), w, h, d, b), "aplicar nítido");
        int malos = 0;
        for (int y = 0; y < h * n; ++y) for (int x = 0; x < w * n; ++x)
            if (d[static_cast<std::size_t>(y) * w * n + x] != s[static_cast<std::size_t>(y / n) * w + x / n]) ++malos;
        COMPROBAR(malos == 0, "%d píxeles del filtro nítido mal replicados", malos);
        COMPROBAR(!aplicar(kNitido, 1, s.data(), w, h, d, b), "factor 1 no debe generar imagen");
    }

    // ── Suavizado [1 6 1]/8 ───────────────────────────────────────────────────
    COMPROBAR(detalle::mezcla161(0xFF000000u, 0xFFFFFFFFu, 0xFF000000u) == 0xFFBFBFBFu, "mezcla161 (0,255,0) = 191");
    COMPROBAR(detalle::mezcla161(0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu) == 0xFFFFFFFFu, "mezcla161 conserva el blanco");
    COMPROBAR(detalle::mezcla161(0xFF000000u, 0xFF000000u, 0xFF000000u) == 0xFF000000u, "mezcla161 conserva el negro");
    COMPROBAR(detalle::mezcla161(0xFFFF0000u, 0xFF00FF00u, 0xFF0000FFu) == 0xFF20BF20u, "mezcla161 por canales");

    // ── Replicación final de los ampliadores (k_post) ─────────────────────────
    for (int f : {kScale2x, kScale3x, kScale4x, kHdSuave}) {
        const int w = 9, h = 7, n = factor(f), k = 3;
        const auto s = imagen_azar(w, h, 4);
        std::vector<uint32_t> d1, dk; Buffers b1, bk;
        COMPROBAR(aplicar(f, 0, s.data(), w, h, d1, b1) && aplicar(f, 0, s.data(), w, h, dk, bk, k), "aplicar %d con k_post", f);
        COMPROBAR(dk.size() == static_cast<std::size_t>(w) * h * n * n * k * k, "tamaño con k_post del filtro %d", f);
        int malos = 0;
        const int W1 = w * n, Wk = w * n * k;
        for (int y = 0; y < h * n * k; ++y) for (int x = 0; x < Wk; ++x)
            if (dk[static_cast<std::size_t>(y) * Wk + x] != d1[static_cast<std::size_t>(y / k) * W1 + x / k]) ++malos;
        COMPROBAR(malos == 0, "el filtro %d con k_post no es la réplica exacta (%d píxeles)", f, malos);
    }

    // ── Cobertura de las rayas (área exacta) ──────────────────────────────────
    {
        // Celda entera de 3 píxeles con raya de 1: cae justo en el último píxel de cada celda.
        COMPROBAR(detalle::cobertura(0, 3.0, 1.0) == 0.0 && detalle::cobertura(1, 3.0, 1.0) == 0.0 &&
                  detalle::cobertura(2, 3.0, 1.0) == 1.0 && detalle::cobertura(5, 3.0, 1.0) == 1.0, "cobertura con celda entera");
        double suma = 0.0;
        for (int x = 0; x < 1280; ++x) suma += detalle::cobertura(x, 1280.0 / 240.0, 1.0);
        COMPROBAR(suma > 239.99 && suma < 240.01, "240 rayas de 1 píxel en 1280 píxeles: %.4f", suma);
        double max = 0.0, min = 1.0;
        for (int x = 0; x < 1280; ++x) { const double c = detalle::cobertura(x, 1280.0 / 240.0, 1.0); max = c > max ? c : max; min = c < min ? c : min; }
        COMPROBAR(min >= 0.0 && max <= 1.0, "cobertura fuera de [0,1]");
    }

    // ── Máscara de la rejilla LCD ─────────────────────────────────────────────
    {
        std::vector<uint32_t> m;
        const double media = mascara_lcd(720, 480, 240, 160, m);
        COMPROBAR(m.size() == 720u * 480u, "tamaño de la máscara LCD");
        COMPROBAR(media > 0.80 && media < 0.82, "media de la máscara LCD a 3x: %.4f", media);
        const auto en = [&](int x, int y) { return m[static_cast<std::size_t>(y) * 720 + x]; };
        COMPROBAR(en(0, 0) == 0xFFFFFFFFu && en(1, 1) == 0xFFFFFFFFu, "el interior de la celda no se oscurece");
        COMPROBAR(en(2, 0) == 0xFFB3B3B3u && en(0, 2) == 0xFFB3B3B3u, "raya simple al 70 %% (%08X)", en(2, 0));
        COMPROBAR(en(2, 2) == detalle::gris(0.7 * 0.7), "cruce de rayas");
        bool periodica = true, valida = true;
        for (int y = 0; y < 480; ++y) for (int x = 0; x < 717; ++x) periodica = periodica && (en(x, y) == en(x + 3, y));
        for (uint32_t v : m) valida = valida && ((v >> 24) == 0xFFu) && ((v & 0xFF) >= 124);
        COMPROBAR(periodica, "la rejilla de 3 en 3 no es periódica");
        COMPROBAR(valida, "píxeles de la máscara LCD fuera de rango o con transparencia");
        COMPROBAR(mascara_lcd(400, 480, 240, 160, m) < 0.0, "ventana de menos de 2x: sin máscara");
        COMPROBAR(mascara_lcd(5000, 3000, 240, 160, m) < 0.0, "ventana enorme: sin máscara");
        const double media_f = mascara_lcd(1280, 720, 240, 160, m);
        COMPROBAR(m.size() == 1280u * 720u && media_f > 0.80 && media_f < 0.95, "máscara LCD fraccionaria: %.4f", media_f);
    }

    // ── Máscara de las líneas CRT ─────────────────────────────────────────────
    {
        std::vector<uint32_t> m;
        const double media = mascara_crt(720, 480, 240, 160, m);
        COMPROBAR(m.size() == 720u * 480u && media > 0.80 && media < 0.86, "media de la máscara CRT: %.4f", media);
        const auto en = [&](int x, int y) { return static_cast<int>(m[static_cast<std::size_t>(y) * 720 + x] & 0xFF); };
        COMPROBAR(en(0, 1) > en(0, 0) && en(0, 1) >= 250, "centro del haz %d y borde %d", en(0, 1), en(0, 0));
        COMPROBAR(en(0, 0) == en(0, 2), "simetría de las filas de la línea");
        bool columnas = true, periodica = true;
        for (int y = 0; y < 480; ++y) for (int x = 1; x < 720; ++x) columnas = columnas && (en(x, y) == en(0, y));
        for (int y = 0; y < 477; ++y) periodica = periodica && (en(5, y) == en(5, y + 3));
        COMPROBAR(columnas, "la máscara CRT cambia a lo largo de una fila");
        COMPROBAR(periodica, "las líneas CRT no son periódicas");
        COMPROBAR(mascara_crt(720, 200, 240, 160, m) < 0.0, "menos de 2 filas por línea: sin máscara");
    }

    // ── Compensación de brillo ────────────────────────────────────────────────
    {
        COMPROBAR(ganancia_mascara(1.0) == 1.0 && ganancia_mascara(0.0) == 1.0 && ganancia_mascara(1.2) == 1.0, "ganancia sin efecto");
        const double g = ganancia_mascara(0.8);
        COMPROBAR(g > 1.149 && g < 1.151, "ganancia con media 0,8: %.4f", g);
        COMPROBAR(ganancia_mascara(0.3) == 1.4, "ganancia con tope en 1,4");
        std::vector<uint32_t> img = {0xFF646464u, 0xFFFFFFFFu, 0xFF000000u};
        aplicar_ganancia(img, 1.15);
        COMPROBAR(img[0] == 0xFF737373u && img[1] == 0xFFFFFFFFu && img[2] == 0xFF000000u, "aplicar_ganancia: %08X", img[0]);
        std::vector<uint32_t> igual = {0xFF646464u};
        aplicar_ganancia(igual, 1.0);
        COMPROBAR(igual[0] == 0xFF646464u, "ganancia 1,0 no cambia nada");
    }

    // ── Reducción de la máscara y composición por CPU ──────────────────────────
    {
        COMPROBAR(reduccion_mascara(720, 480) == 1 && reduccion_mascara(1920, 1080) == 1, "sin reducción hasta 1920x1080");
        COMPROBAR(reduccion_mascara(2560, 1440) == 2, "1440p se compone a la mitad: k=%d", reduccion_mascara(2560, 1440));
        COMPROBAR(reduccion_mascara(3840, 2160) == 2, "4K se compone a la mitad: k=%d", reduccion_mascara(3840, 2160));
        COMPROBAR(mascara_cabe(3840 / reduccion_mascara(3840, 2160), 2160 / reduccion_mascara(3840, 2160)), "4K reducido cabe");
        COMPROBAR(std::strcmp(nombre(kRejillaLcd), "LCD grid (GBA)") == 0 && std::strcmp(nombre(kNearest), "Nearest") == 0 &&
                  std::strcmp(nombre(99), "?") == 0, "nombres de filtro");

        // Máscara toda a 255: la imagen sale igual; a 0: negro; gris medio: mitad.
        const int bw = 4, bh = 3, dw = 12, dh = 9;
        std::vector<uint32_t> origen(static_cast<std::size_t>(bw) * bh), m(static_cast<std::size_t>(dw) * dh), sal;
        std::vector<int> cols;
        for (int i = 0; i < bw * bh; ++i)
            origen[static_cast<std::size_t>(i)] = 0xFF000000u | (static_cast<uint32_t>(10 + 20 * i) << 16) |
                                                   (static_cast<uint32_t>(200 - 10 * i) << 8) | static_cast<uint32_t>(255 - i);
        for (auto& v : m) v = 0xFFFFFFFFu;
        componer(origen.data(), bw, bh, m.data(), dw, dh, sal, cols);
        bool igual = sal.size() == m.size();
        for (int y = 0; y < dh && igual; ++y)
            for (int x = 0; x < dw; ++x)
                igual = igual && sal[static_cast<std::size_t>(y) * dw + x] == origen[static_cast<std::size_t>(y / 3) * bw + x / 3];
        COMPROBAR(igual, "componer con máscara blanca = ampliación x3 exacta");
        for (auto& v : m) v = 0xFF000000u;
        componer(origen.data(), bw, bh, m.data(), dw, dh, sal, cols);
        bool negro = true;
        for (uint32_t p : sal) negro = negro && p == 0xFF000000u;
        COMPROBAR(negro, "componer con máscara negra = negro opaco");
        for (auto& v : m) v = detalle::gris(0.5);
        componer(origen.data(), bw, bh, m.data(), dw, dh, sal, cols);
        const uint32_t o = origen[6], r = sal[static_cast<std::size_t>(4) * dw + 6];   // origen (2,1) -> pantalla (6..8, 3..5)
        const int rr = static_cast<int>((o >> 16) & 0xFF), gg = static_cast<int>((o >> 8) & 0xFF), bb = static_cast<int>(o & 0xFF);
        const int sr = static_cast<int>((r >> 16) & 0xFF), sg = static_cast<int>((r >> 8) & 0xFF), sb = static_cast<int>(r & 0xFF);
        COMPROBAR(std::abs(sr - rr / 2) <= 1 && std::abs(sg - gg / 2) <= 1 && std::abs(sb - bb / 2) <= 1 && (r >> 24) == 0xFF,
                  "componer con gris 0,5: %08X desde %08X", r, o);

        // 'filas_repetidas' no cambia el resultado, solo evita recalcular.
        {
            std::vector<uint32_t> ml2, a, b2;
            std::vector<uint8_t> rep;
            std::vector<int> c2;
            mascara_lcd(960, 640, 240, 160, ml2);
            filas_repetidas(ml2.data(), 960, 640, rep);
            std::vector<uint32_t> im(240u * 160u);
            for (std::size_t i = 0; i < im.size(); ++i)
                im[i] = 0xFF000000u | static_cast<uint32_t>((i * 2654435761u) & 0xFFFFFFu);
            componer(im.data(), 240, 160, ml2.data(), 960, 640, a, c2);
            componer(im.data(), 240, 160, ml2.data(), 960, 640, b2, c2, &rep);
            int repetidas = 0;
            for (uint8_t v : rep) repetidas += v;
            COMPROBAR(a == b2 && repetidas >= 640 / 2, "filas repetidas: salida igual y %d de 640 filas copiadas", repetidas);
        }

        // Con una máscara LCD real: los píxeles de la rejilla son más oscuros que los del centro de la celda,
        // y una imagen blanca (con la ganancia aplicada) no baja del 60 % en las rayas.
        std::vector<uint32_t> ml;
        const double media = mascara_lcd(720, 480, 240, 160, ml);
        std::vector<uint32_t> blanca(240u * 160u, 0xFFFFFFFFu), res;
        componer(blanca.data(), 240, 160, ml.data(), 720, 480, res, cols);
        const int centro = static_cast<int>(res[static_cast<std::size_t>(1) * 720 + 1] & 0xFF);
        const int raya = static_cast<int>(res[static_cast<std::size_t>(1) * 720 + 2] & 0xFF);
        COMPROBAR(media > 0.5 && media < 1.0 && centro == 255 && raya < centro && raya >= 150,
                  "rejilla LCD: centro %d raya %d media %.3f", centro, raya, media);
    }

    std::printf(g_fallos == 0 ? "Pruebas de filtros: todo correcto.\n" : "Pruebas de filtros: %d fallo(s).\n", g_fallos);
    return g_fallos == 0 ? 0 : 1;
}
