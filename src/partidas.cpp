// partidas.cpp — importar y exportar partidas de emulador desde el menú de arranque.
// Ver partidas.h. Las mismas reglas que tools/PARTIDAS.ps1 (la herramienta de Windows), para que
// las copias de seguridad de una sirvan en la otra.
#include "partidas.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr std::size_t kTamanoSram = 32768;                 // 32 KiB: la SRAM de la GBA
constexpr std::uintmax_t kMaximoLeido = 8u * 1024u * 1024u;  // más que esto no es una partida
const char* const kCarpetaCopias = "copias-de-partidas";

// ── Rutas en UTF-8 (en Windows std::string no sirve para abrir archivos con acentos) ─────────
std::string a_utf8(const fs::path& p) {
#if defined(__cpp_char8_t)
    const std::u8string u = p.u8string();
    return std::string(u.begin(), u.end());
#else
    return p.u8string();
#endif
}

fs::path de_utf8(const std::string& s) {
#if defined(__cpp_char8_t)
    return fs::path(std::u8string(s.begin(), s.end()));
#else
    return fs::u8path(s);
#endif
}

void copiar_texto(char* destino, std::size_t n, const std::string& s) {
    if (!destino || n == 0) return;
    std::snprintf(destino, n, "%s", s.c_str());
}

// Carpeta del juego: la de config.ini (la misma que usa el menú para sus ajustes).
fs::path carpeta_juego() {
    const char* ini = std::getenv("MTP_CONFIG_INI");
    fs::path base = (ini && ini[0]) ? de_utf8(ini).parent_path() : fs::path();
    if (base.empty()) base = ".";
    return base;
}

fs::path carpeta_copias() { return carpeta_juego() / kCarpetaCopias; }

// La partida es el .sav junto a la ROM (igual que hace el programa al arrancar).
fs::path ruta_sav(const char* rom) {
    if (!rom || !rom[0]) return fs::path();
    fs::path p = de_utf8(rom);
    p.replace_extension(".sav");
    return p;
}

long long a_segundos_unix(const fs::file_time_type& t) {
    using namespace std::chrono;
    const auto ahora_arch = fs::file_time_type::clock::now();
    const auto ahora_sis = system_clock::now();
    const auto sis = ahora_sis + duration_cast<system_clock::duration>(t - ahora_arch);
    return (long long)duration_cast<seconds>(sis.time_since_epoch()).count();
}

bool leer_archivo(const fs::path& p, std::vector<std::uint8_t>* datos) {
    std::ifstream f(p, std::ios::binary);
    if (!f) return false;
    datos->assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
    return !f.bad();
}

// Escritura «atómica»: se escribe a un archivo temporal y se renombra, para no dejar una
// partida a medias si algo falla (disco lleno, corte de luz).
bool escribir_archivo(const fs::path& destino, const std::vector<std::uint8_t>& datos) {
    std::error_code ec;
    const fs::path padre = destino.parent_path();
    if (!padre.empty()) fs::create_directories(padre, ec);
    fs::path tmp = destino;
    tmp += ".nueva";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f) return false;
        f.write(reinterpret_cast<const char*>(datos.data()), (std::streamsize)datos.size());
        f.flush();
        if (!f) {
            f.close();
            fs::remove(tmp, ec);
            return false;
        }
    }
    ec.clear();
    if (fs::exists(destino, ec)) fs::remove(destino, ec);
    ec.clear();
    fs::rename(tmp, destino, ec);
    if (ec) {
        fs::remove(tmp, ec);
        return false;
    }
    return true;
}

bool es_vacia(const std::vector<std::uint8_t>& d) {
    for (std::uint8_t b : d)
        if (b != 0x00 && b != 0xFF) return false;
    return true;
}

std::string en_minusculas(std::string s) {
    for (char& c : s) c = (char)std::tolower((unsigned char)c);
    return s;
}

// Extensiones que usan los emuladores para sus estados rápidos (save states).
bool extension_de_estado(const std::string& nombre) {
    const std::string e = en_minusculas(a_utf8(de_utf8(nombre).extension()));
    if (e == ".state" || e == ".sgm" || e == ".sps" || e == ".oops" || e == ".gqs") return true;
    // .ss0…ss9, .st0…st9
    return e.size() == 4 && e[0] == '.' && e[1] == 's' && (e[2] == 's' || e[2] == 't') &&
           std::isdigit((unsigned char)e[3]);
}

// Comprueba los bytes de un archivo y los deja como los 32 KiB que se usarían.
// Devuelve MTP_PARTIDA_OK o el código de error; rellena las marcas de `r`.
int normalizar(const std::vector<std::uint8_t>& datos, const std::string& nombre,
               std::vector<std::uint8_t>* salida, MtpPartidaResultado* r) {
    r->bytes_origen = datos.size();
    if (extension_de_estado(nombre)) return MTP_PARTIDA_ERR_ESTADO_RAPIDO;
    if (datos.empty()) return MTP_PARTIDA_ERR_VACIO;
    if (datos.size() >= 8 && datos.size() != kTamanoSram) {
        // (Un archivo de exactamente 32 KiB es una partida en bruto: no se mira su cabecera.)
        const bool zip = datos[0] == 'P' && datos[1] == 'K';
        const bool gzip = datos[0] == 0x1F && datos[1] == 0x8B;
        const bool rastate = std::memcmp(datos.data(), "RASTATE", 7) == 0;
        const bool png = datos[0] == 0x89 && std::memcmp(datos.data() + 1, "PNG", 3) == 0;
        if (zip || gzip || rastate || png) return MTP_PARTIDA_ERR_ESTADO_RAPIDO;
    }
    if (datos.size() > kTamanoSram) {
        // ¿Lo que sobra es relleno (todo 0x00 o todo 0xFF) o una copia repetida de los primeros 32 KiB?
        const std::uint8_t primero = datos[kTamanoSram];
        bool relleno = (primero == 0x00 || primero == 0xFF);
        bool espejo = (datos.size() % kTamanoSram) == 0;
        for (std::size_t i = kTamanoSram; i < datos.size() && (relleno || espejo); ++i) {
            if (relleno && datos[i] != primero) relleno = false;
            if (espejo && datos[i] != datos[i % kTamanoSram]) espejo = false;
        }
        if (!relleno && !espejo) return MTP_PARTIDA_ERR_OTRO_FORMATO;
        salida->assign(datos.begin(), datos.begin() + (std::ptrdiff_t)kTamanoSram);
        r->recortado = 1;
    } else if (datos.size() < kTamanoSram) {
        // Una SRAM sin escribir vale 0xFF en cualquier emulador: se completa así hasta 32 KiB.
        salida->assign(kTamanoSram, 0xFF);
        std::copy(datos.begin(), datos.end(), salida->begin());
        r->completado = 1;
    } else {
        *salida = datos;
    }
    r->vacia = es_vacia(*salida) ? 1 : 0;
    return MTP_PARTIDA_OK;
}

void limpiar(MtpPartidaResultado* r) {
    if (r) std::memset(r, 0, sizeof(*r));
}

// Lee `origen` y lo normaliza. No escribe nada.
int leer_y_normalizar(const char* origen, std::vector<std::uint8_t>* salida, MtpPartidaResultado* r) {
    if (!origen || !origen[0]) return MTP_PARTIDA_ERR_NO_EXISTE;
    const fs::path p = de_utf8(origen);
    std::error_code ec;
    if (!fs::is_regular_file(p, ec)) return MTP_PARTIDA_ERR_NO_EXISTE;
    const std::uintmax_t tam = fs::file_size(p, ec);
    if (ec) return MTP_PARTIDA_ERR_NO_EXISTE;
    if (tam > kMaximoLeido) {
        r->bytes_origen = tam;
        return MTP_PARTIDA_ERR_DEMASIADO_GRANDE;
    }
    std::vector<std::uint8_t> datos;
    if (!leer_archivo(p, &datos)) return MTP_PARTIDA_ERR_NO_EXISTE;
    return normalizar(datos, a_utf8(p.filename()), salida, r);
}

std::string sello_de_hora() {
    const std::time_t t = std::time(nullptr);
    std::tm local{};
#if defined(_WIN32)
    localtime_s(&local, &t);
#else
    localtime_r(&t, &local);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d_%H-%M-%S", &local);
    return buf;
}

// Copia la partida actual (si hay) en «copias-de-partidas». Devuelve la ruta, o "" si no había partida.
// Si no se puede copiar, pone ok=false.
std::string hacer_copia(const fs::path& partida, const char* motivo, bool* ok) {
    *ok = true;
    std::error_code ec;
    if (!fs::is_regular_file(partida, ec)) return "";
    const fs::path dir = carpeta_copias();
    fs::create_directories(dir, ec);
    const std::string sello = sello_de_hora();
    fs::path destino = dir / ("partida_" + sello + "_" + motivo + ".sav");
    for (int n = 2; fs::exists(destino, ec) && n < 1000; ++n)
        destino = dir / ("partida_" + sello + "_" + motivo + "_" + std::to_string(n) + ".sav");
    ec.clear();
    fs::copy_file(partida, destino, fs::copy_options::none, ec);
    if (ec) {
        *ok = false;
        return "";
    }
    return a_utf8(destino);
}

// Importación común a «importar» y «restaurar».
void poner_partida(const char* rom, const char* origen, const char* motivo, MtpPartidaResultado* r) {
    limpiar(r);
    if (!rom || !rom[0]) {
        r->codigo = MTP_PARTIDA_ERR_SIN_ROM;
        return;
    }
    std::vector<std::uint8_t> datos;
    r->codigo = leer_y_normalizar(origen, &datos, r);
    if (r->codigo != MTP_PARTIDA_OK) return;
    const fs::path partida = ruta_sav(rom);
    bool copia_ok = true;
    const std::string copia = hacer_copia(partida, motivo, &copia_ok);
    if (!copia_ok) {   // sin copia no se toca la partida actual
        r->codigo = MTP_PARTIDA_ERR_ESCRIBIR;
        return;
    }
    copiar_texto(r->copia, sizeof(r->copia), copia);
    if (!escribir_archivo(partida, datos)) r->codigo = MTP_PARTIDA_ERR_ESCRIBIR;
}

}  // namespace

extern "C" {

int mtp_partida_info(const char* rom, MtpPartidaInfo* out) {
    if (!out) return MTP_PARTIDA_ERR_SIN_ROM;
    std::memset(out, 0, sizeof(*out));
    const fs::path p = ruta_sav(rom);
    if (p.empty()) return MTP_PARTIDA_ERR_SIN_ROM;
    copiar_texto(out->ruta, sizeof(out->ruta), a_utf8(p));
    std::error_code ec;
    if (!fs::is_regular_file(p, ec)) return MTP_PARTIDA_OK;
    out->existe = 1;
    const std::uintmax_t tam = fs::file_size(p, ec);
    out->bytes = ec ? 0 : (unsigned long long)tam;
    ec.clear();
    const fs::file_time_type t = fs::last_write_time(p, ec);
    out->modificada = ec ? 0 : a_segundos_unix(t);
    if (tam <= kMaximoLeido) {
        std::vector<std::uint8_t> datos;
        if (leer_archivo(p, &datos)) out->vacia = es_vacia(datos) ? 1 : 0;
    }
    return MTP_PARTIDA_OK;
}

void mtp_partida_comprobar(const char* origen, MtpPartidaResultado* out) {
    if (!out) return;
    limpiar(out);
    std::vector<std::uint8_t> datos;
    out->codigo = leer_y_normalizar(origen, &datos, out);
}

void mtp_partida_importar(const char* rom, const char* origen, MtpPartidaResultado* out) {
    if (!out) return;
    poner_partida(rom, origen, "antes-de-importar", out);
}

void mtp_partida_restaurar(const char* rom, const char* copia, MtpPartidaResultado* out) {
    if (!out) return;
    poner_partida(rom, copia, "antes-de-restaurar", out);
}

void mtp_partida_exportar(const char* rom, const char* destino, MtpPartidaResultado* out) {
    if (!out) return;
    limpiar(out);
    if (!rom || !rom[0]) {
        out->codigo = MTP_PARTIDA_ERR_SIN_ROM;
        return;
    }
    if (!destino || !destino[0]) {
        out->codigo = MTP_PARTIDA_ERR_ESCRIBIR;
        return;
    }
    const std::string origen = a_utf8(ruta_sav(rom));
    std::error_code ec;
    if (!fs::is_regular_file(ruta_sav(rom), ec)) {
        out->codigo = MTP_PARTIDA_ERR_SIN_PARTIDA;
        return;
    }
    // Siempre se exportan los 32 KiB estándar (aunque el archivo del juego traiga relleno de más).
    std::vector<std::uint8_t> datos;
    out->codigo = leer_y_normalizar(origen.c_str(), &datos, out);
    if (out->codigo != MTP_PARTIDA_OK) return;
    fs::path dest = de_utf8(destino);
    if (!dest.has_extension()) dest += ".sav";
    if (!escribir_archivo(dest, datos)) {
        out->codigo = MTP_PARTIDA_ERR_ESCRIBIR;
        return;
    }
    copiar_texto(out->copia, sizeof(out->copia), a_utf8(dest));   // aquí: dónde ha quedado
}

void mtp_partida_copia(const char* rom, MtpPartidaResultado* out) {
    if (!out) return;
    limpiar(out);
    if (!rom || !rom[0]) {
        out->codigo = MTP_PARTIDA_ERR_SIN_ROM;
        return;
    }
    const fs::path partida = ruta_sav(rom);
    std::error_code ec;
    if (!fs::is_regular_file(partida, ec)) {
        out->codigo = MTP_PARTIDA_ERR_SIN_PARTIDA;
        return;
    }
    bool ok = true;
    const std::string copia = hacer_copia(partida, "manual", &ok);
    if (!ok) {
        out->codigo = MTP_PARTIDA_ERR_ESCRIBIR;
        return;
    }
    copiar_texto(out->copia, sizeof(out->copia), copia);
}

int mtp_partida_copias(MtpCopia* out, int max) {
    if (!out || max <= 0) return 0;
    struct Fila {
        fs::path ruta;
        fs::file_time_type tiempo;
        std::uintmax_t bytes;
    };
    std::vector<Fila> filas;
    std::error_code ec;
    for (fs::directory_iterator it(carpeta_copias(), ec), fin; !ec && it != fin; it.increment(ec)) {
        std::error_code e2;
        if (!it->is_regular_file(e2)) continue;
        if (en_minusculas(a_utf8(it->path().extension())) != ".sav") continue;
        Fila f;
        f.ruta = it->path();
        f.tiempo = it->last_write_time(e2);
        f.bytes = it->file_size(e2);
        filas.push_back(std::move(f));
    }
    // Las más recientes primero (en empate, por nombre, que lleva la fecha y la hora).
    std::sort(filas.begin(), filas.end(), [](const Fila& a, const Fila& b) {
        if (a.tiempo != b.tiempo) return a.tiempo > b.tiempo;
        return a.ruta.filename() > b.ruta.filename();
    });
    int n = 0;
    for (const Fila& f : filas) {
        if (n >= max) break;
        std::memset(&out[n], 0, sizeof(out[n]));
        copiar_texto(out[n].ruta, sizeof(out[n].ruta), a_utf8(f.ruta));
        out[n].bytes = (unsigned long long)f.bytes;
        out[n].modificada = a_segundos_unix(f.tiempo);
        ++n;
    }
    return n;
}

const char* mtp_partida_carpeta_copias(void) {
    static std::string s;
    s = a_utf8(carpeta_copias());
    return s.c_str();
}

}  // extern "C"
