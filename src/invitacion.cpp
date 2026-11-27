// invitacion.cpp — jugar online por código de invitación, SIN servidor (ver invitacion.h).
//
// Piezas:
//   · Códigos: 25 bytes (tipo, NAT, número de sala, marca de la versión, dirección pública y
//     local, CRC-32) escritos en base 32 (alfabeto de Crockford, sin I/L/O/U) en 40 caracteres,
//     agrupados de 4 en 4. Un cambio de un solo carácter siempre se detecta (CRC-32).
//   · STUN: una petición «Binding» (RFC 5389) desde EL MISMO puerto UDP que luego usará la
//     partida; con dos servidores que vean puertos distintos se detecta un NAT simétrico.
//   · Perforado: los dos equipos se mandan paquetes UDP a la vez a las direcciones del código
//     hasta que cada uno ha oído al otro; después se libera el puerto y main.cpp arranca el
//     juego en red por IP directa con ese mismo puerto.
//   · Nombres: cada jugador puede poner su nombre (se limpia, ≤ 24 bytes, va dentro de los paquetes
//     del perforado y se guarda en config.ini, [Online] Nombre) y un apodo para el amigo que solo vive
//     en la sesión; main.cpp los recibe con --mtp-nombre / --mtp-nombre-amigo (título y rótulo).
//   · Hilos: todo lo lento (DNS, STUN, perforado) va en un hilo propio; el menú solo consulta el
//     estado en cada fotograma (mtp_inv_estado) y nunca se bloquea.
// Sockets de Linux/macOS y de Windows (Winsock). Solo IPv4.
#include "invitacion.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#if defined(MTP_NETPLAY) && defined(__has_include)
#if __has_include("gba_netplay_build_identity.h")
#include "gba_netplay_build_identity.h"  // GBARECOMP_NETPLAY_BUILD_ID (lo genera CMake)
#endif
#endif

namespace {

#if defined(_WIN32)
using socket_t = SOCKET;
const socket_t kSocketNulo = INVALID_SOCKET;
void cerrar_socket(socket_t s) { if (s != INVALID_SOCKET) closesocket(s); }
#else
using socket_t = int;
const socket_t kSocketNulo = -1;
void cerrar_socket(socket_t s) { if (s >= 0) ::close(s); }
#endif

using Reloj = std::chrono::steady_clock;

long long ahora_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Reloj::now().time_since_epoch()).count();
}

std::string entorno(const char* nombre) {
    const char* v = std::getenv(nombre);
    return v ? std::string(v) : std::string();
}

bool traza_activa() {
    static const bool activa = !entorno("MTP_INV_DEBUG").empty();
    return activa;
}

void trazar(const std::string& texto) {
    if (traza_activa()) std::fprintf(stderr, "[online] %s\n", texto.c_str());
}

// Plazos de conexión en milisegundos. MTP_INV_PLAZO (segundos) los sustituye todos: solo para
// las pruebas, para no esperar minutos cuando se quiere comprobar un tiempo agotado.
int plazo(int segundos_por_defecto) {
    const std::string v = entorno("MTP_INV_PLAZO");
    if (!v.empty()) {
        const int s = std::atoi(v.c_str());
        if (s > 0) return s * 1000;
    }
    return segundos_por_defecto * 1000;
}

void iniciar_red() {
#if defined(_WIN32)
    static std::once_flag una_vez;
    std::call_once(una_vez, [] {
        WSADATA datos;
        WSAStartup(MAKEWORD(2, 2), &datos);
    });
#endif
}


// ── Identidad de la compilación ─────────────────────────────────────────────────────────────
// Los dos jugadores deben tener el mismo programa, la misma ROM y el mismo código generado; el
// juego en red lo exige al arrancar, y el código de invitación lo adelanta con esta marca.
std::uint32_t fnv1a32(const std::string& s) {
    std::uint32_t h = 2166136261u;
    for (unsigned char c : s) {
        h ^= c;
        h *= 16777619u;
    }
    return h;
}

std::string identidad_texto() {
    const std::string forzada = entorno("MTP_INV_IDENTIDAD");  // solo para las pruebas
    if (!forzada.empty()) return forzada;
    std::string t = "mtp";
#if defined(MTP_VERSION)
    t += "|";
    t += MTP_VERSION;
#endif
#if defined(GBARECOMP_NETPLAY_BUILD_ID)
    t += "|";
    t += std::string(GBARECOMP_NETPLAY_BUILD_ID);
#endif
    return t;
}

std::uint32_t etiqueta_version() { return fnv1a32(identidad_texto()); }

// ── Direcciones ─────────────────────────────────────────────────────────────────────────────
struct Extremo {
    std::uint32_t ip = 0;       // IPv4 en orden de máquina
    std::uint16_t puerto = 0;
    bool vacio() const { return ip == 0 || puerto == 0; }
    bool operator==(const Extremo& o) const { return ip == o.ip && puerto == o.puerto; }
    bool operator!=(const Extremo& o) const { return !(*this == o); }
};

std::string texto_extremo(const Extremo& e) {
    char b[48];
    std::snprintf(b, sizeof b, "%u.%u.%u.%u:%u", (e.ip >> 24) & 255u, (e.ip >> 16) & 255u, (e.ip >> 8) & 255u,
                  e.ip & 255u, static_cast<unsigned>(e.puerto));
    return b;
}

sockaddr_in a_sockaddr(const Extremo& e) {
    sockaddr_in sa;
    std::memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(e.ip);
    sa.sin_port = htons(e.puerto);
    return sa;
}

Extremo de_sockaddr(const sockaddr_in& sa) {
    Extremo e;
    e.ip = ntohl(sa.sin_addr.s_addr);
    e.puerto = ntohs(sa.sin_port);
    return e;
}

// ── Códigos ─────────────────────────────────────────────────────────────────────────────────
struct Carga {
    int tipo = 0;                 // 0 invitación, 1 respuesta
    bool nat_simetrico = false;
    bool sin_publica = false;     // no se pudo averiguar la dirección pública
    std::uint32_t nonce = 0;      // número de sala (también es la sesión de la partida)
    std::uint32_t etiqueta = 0;   // marca de la versión
    Extremo publico;
    Extremo local;
};

constexpr int kFormato = 1;
constexpr int kBytesCodigo = 25;   // 21 de datos + 4 de CRC-32
constexpr int kCaracteres = 40;    // 25 bytes = 200 bits = 40 caracteres de 5 bits
const char kAlfabeto[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

std::uint32_t crc32(const unsigned char* d, int n) {
    std::uint32_t c = 0xFFFFFFFFu;
    for (int i = 0; i < n; ++i) {
        c ^= d[i];
        for (int k = 0; k < 8; ++k) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
    }
    return ~c;
}

void poner32(unsigned char* p, std::uint32_t v) {
    p[0] = static_cast<unsigned char>(v >> 24);
    p[1] = static_cast<unsigned char>(v >> 16);
    p[2] = static_cast<unsigned char>(v >> 8);
    p[3] = static_cast<unsigned char>(v);
}
void poner16(unsigned char* p, std::uint16_t v) {
    p[0] = static_cast<unsigned char>(v >> 8);
    p[1] = static_cast<unsigned char>(v);
}
std::uint32_t leer32(const unsigned char* p) {
    return (std::uint32_t(p[0]) << 24) | (std::uint32_t(p[1]) << 16) | (std::uint32_t(p[2]) << 8) | p[3];
}
std::uint16_t leer16(const unsigned char* p) { return static_cast<std::uint16_t>((p[0] << 8) | p[1]); }

std::string codificar(const Carga& c) {
    unsigned char b[kBytesCodigo];
    std::memset(b, 0, sizeof b);
    b[0] = static_cast<unsigned char>(((c.tipo & 1) << 7) | ((c.nat_simetrico ? 1 : 0) << 6) |
                                      ((c.sin_publica ? 1 : 0) << 5) | kFormato);
    poner32(b + 1, c.nonce);
    poner32(b + 5, c.etiqueta);
    poner32(b + 9, c.publico.ip);
    poner16(b + 13, c.publico.puerto);
    poner32(b + 15, c.local.ip);
    poner16(b + 19, c.local.puerto);
    poner32(b + 21, crc32(b, 21));
    std::string res;
    unsigned acumulado = 0;
    int bits = 0;
    int escritos = 0;
    for (int i = 0; i < kBytesCodigo; ++i) {
        acumulado = (acumulado << 8) | b[i];
        bits += 8;
        while (bits >= 5) {
            if (escritos > 0 && escritos % 4 == 0) res.push_back('-');
            res.push_back(kAlfabeto[(acumulado >> (bits - 5)) & 31u]);
            bits -= 5;
            ++escritos;
        }
        acumulado &= (1u << bits) - 1u;
    }
    return res;
}

// Devuelve MTP_INV_OK, MTP_INV_ERR_CODIGO, MTP_INV_ERR_TIPO o MTP_INV_ERR_VERSION.
int decodificar(const char* texto, int tipo_esperado, Carga* fuera) {
    if (!texto) return MTP_INV_ERR_CODIGO;
    int valores[kCaracteres + 1];
    int n = 0;
    for (const char* p = texto; *p; ++p) {
        char c = *p;
        if (c == ' ' || c == '-' || c == '_' || c == '\t' || c == '\r' || c == '\n') continue;
        if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
        if (c == 'O') c = '0';
        if (c == 'I' || c == 'L') c = '1';
        const char* pos = c ? std::strchr(kAlfabeto, c) : nullptr;
        if (!pos) return MTP_INV_ERR_CODIGO;
        if (n >= kCaracteres) return MTP_INV_ERR_CODIGO;
        valores[n++] = static_cast<int>(pos - kAlfabeto);
    }
    if (n != kCaracteres) return MTP_INV_ERR_CODIGO;
    unsigned char b[kBytesCodigo];
    unsigned acumulado = 0;
    int bits = 0;
    int k = 0;
    for (int i = 0; i < kCaracteres; ++i) {
        acumulado = (acumulado << 5) | static_cast<unsigned>(valores[i]);
        bits += 5;
        if (bits >= 8) {
            b[k++] = static_cast<unsigned char>((acumulado >> (bits - 8)) & 255u);
            bits -= 8;
            acumulado &= (1u << bits) - 1u;
        }
    }
    if (k != kBytesCodigo) return MTP_INV_ERR_CODIGO;
    if (crc32(b, 21) != leer32(b + 21)) return MTP_INV_ERR_CODIGO;
    if ((b[0] & 31) != kFormato) return MTP_INV_ERR_CODIGO;
    Carga c;
    c.tipo = (b[0] >> 7) & 1;
    c.nat_simetrico = ((b[0] >> 6) & 1) != 0;
    c.sin_publica = ((b[0] >> 5) & 1) != 0;
    c.nonce = leer32(b + 1);
    c.etiqueta = leer32(b + 5);
    c.publico.ip = leer32(b + 9);
    c.publico.puerto = leer16(b + 13);
    c.local.ip = leer32(b + 15);
    c.local.puerto = leer16(b + 19);
    if (c.tipo != tipo_esperado) return MTP_INV_ERR_TIPO;
    if (c.etiqueta != etiqueta_version()) return MTP_INV_ERR_VERSION;
    if (c.nonce == 0 || c.local.vacio()) return MTP_INV_ERR_CODIGO;
    if (fuera) *fuera = c;
    return MTP_INV_OK;
}

// ── config.ini ([Online] StunServers) ───────────────────────────────────────────────────────
std::string leer_ini_online(const char* clave, bool quitar_comentarios = true) {
    const std::string ruta = entorno("MTP_CONFIG_INI");
    if (ruta.empty()) return std::string();
    std::ifstream f(ruta);
    if (!f) return std::string();
    std::string linea;
    bool en_seccion = false;
    while (std::getline(f, linea)) {
        while (!linea.empty() && (linea.back() == '\r' || linea.back() == ' ' || linea.back() == '\t')) linea.pop_back();
        std::size_t i = 0;
        while (i < linea.size() && (linea[i] == ' ' || linea[i] == '\t')) ++i;
        linea = linea.substr(i);
        if (linea.empty() || linea[0] == ';' || linea[0] == '#') continue;
        if (linea[0] == '[') {
            en_seccion = linea.rfind("[Online]", 0) == 0;
            continue;
        }
        if (!en_seccion) continue;
        const std::size_t ig = linea.find('=');
        if (ig == std::string::npos) continue;
        std::string k = linea.substr(0, ig);
        while (!k.empty() && (k.back() == ' ' || k.back() == '\t')) k.pop_back();
        if (k != clave) continue;
        std::string v = linea.substr(ig + 1);
        const std::size_t pc = v.find(';');
        if (quitar_comentarios && pc != std::string::npos) v = v.substr(0, pc);
        std::size_t a = 0;
        while (a < v.size() && (v[a] == ' ' || v[a] == '\t')) ++a;
        v = v.substr(a);
        while (!v.empty() && (v.back() == ' ' || v.back() == '\t')) v.pop_back();
        return v;
    }
    return std::string();
}

// Escribe «clave = valor» en la sección [Online] de config.ini sin tocar el resto del archivo
// (lo comparten el menú y otras partes). Si no hay ruta o no se puede escribir, no hace nada.
void escribir_ini_online(const char* clave, const std::string& valor) {
    const std::string ruta = entorno("MTP_CONFIG_INI");
    if (ruta.empty()) return;
    std::vector<std::string> lineas;
    {
        std::ifstream f(ruta, std::ios::binary);
        std::string linea;
        while (f && std::getline(f, linea)) {
            if (!linea.empty() && linea.back() == '\r') linea.pop_back();
            lineas.push_back(linea);
        }
    }
    const std::string nueva = std::string(clave) + " = " + valor;
    int ini_sec = -1, fin_sec = static_cast<int>(lineas.size()), ya = -1;
    for (int i = 0; i < static_cast<int>(lineas.size()); ++i) {
        std::string t = lineas[i];
        std::size_t a = 0;
        while (a < t.size() && (t[a] == ' ' || t[a] == '\t')) ++a;
        t = t.substr(a);
        if (!t.empty() && t[0] == '[') {
            if (ini_sec >= 0 && fin_sec == static_cast<int>(lineas.size())) fin_sec = i;
            if (t.rfind("[Online]", 0) == 0) ini_sec = i;
            continue;
        }
        if (ini_sec >= 0 && fin_sec == static_cast<int>(lineas.size())) {
            const std::size_t ig = t.find('=');
            if (ig != std::string::npos) {
                std::string k = t.substr(0, ig);
                while (!k.empty() && (k.back() == ' ' || k.back() == '\t')) k.pop_back();
                if (k == clave) ya = i;
            }
        }
    }
    if (ya >= 0) {
        lineas[ya] = nueva;
    } else if (ini_sec >= 0) {
        int donde = fin_sec;
        while (donde > ini_sec + 1 && lineas[donde - 1].empty()) --donde;  // antes de las líneas en blanco finales
        lineas.insert(lineas.begin() + donde, nueva);
    } else {
        if (!lineas.empty() && !lineas.back().empty()) lineas.push_back("");
        lineas.push_back("[Online]");
        lineas.push_back(nueva);
    }
    const std::string tmp = ruta + ".tmp";
    {
        std::ofstream o(tmp, std::ios::binary | std::ios::trunc);
        if (!o) return;
        for (const std::string& l : lineas) o << l << "\n";
        if (!o) return;
    }
    std::remove(ruta.c_str());  // en Windows rename no sustituye un archivo que ya existe
    if (std::rename(tmp.c_str(), ruta.c_str()) != 0) std::remove(tmp.c_str());
}

// ── Nombres para reconocerse (no el del personaje del juego) ────────────────────────────────
// Cada persona escribe el suyo en el menú; viaja en los paquetes de perforado y el otro lo ve al
// conectar. Es texto que llega por la red: se limpia (UTF-8 válido, sin caracteres de control ni
// invisibles que sirvan para suplantar, máximo 24 bytes) antes de enseñarlo o ponerlo en el título.
constexpr std::size_t kMaxNombre = 24;

std::string limpiar_nombre(const std::string& crudo) {
    std::string res;
    std::size_t i = 0;
    while (i < crudo.size()) {
        const unsigned char c = static_cast<unsigned char>(crudo[i]);
        std::size_t n = 1;
        std::uint32_t cp = c;
        if (c < 0x80) {
            n = 1;
        } else if (c >= 0xC2 && c <= 0xDF) {
            n = 2;
            cp = c & 0x1Fu;
        } else if (c >= 0xE0 && c <= 0xEF) {
            n = 3;
            cp = c & 0x0Fu;
        } else if (c >= 0xF0 && c <= 0xF4) {
            n = 4;
            cp = c & 0x07u;
        } else {
            return std::string();  // UTF-8 mal formado
        }
        if (i + n > crudo.size()) return std::string();
        for (std::size_t k = 1; k < n; ++k) {
            const unsigned char cc = static_cast<unsigned char>(crudo[i + k]);
            if ((cc & 0xC0) != 0x80) return std::string();
            cp = (cp << 6) | (cc & 0x3Fu);
        }
        if ((n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10FFFF)) || (cp >= 0xD800 && cp <= 0xDFFF))
            return std::string();
        const bool control = cp < 0x20 || cp == 0x7F || (cp >= 0x80 && cp < 0xA0);
        const bool invisible = (cp >= 0x200B && cp <= 0x200F) || (cp >= 0x202A && cp <= 0x202E) ||
                               (cp >= 0x2060 && cp <= 0x2064) || (cp >= 0x2066 && cp <= 0x2069) || cp == 0xFEFF ||
                               cp == 0x061C || cp == 0x2028 || cp == 0x2029;
        if (!control && !invisible) {
            if (res.size() + n > kMaxNombre) break;
            res.append(crudo, i, n);
        }
        i += n;
    }
    std::size_t a = 0;
    while (a < res.size() && res[a] == ' ') ++a;
    res = res.substr(a);
    while (!res.empty() && res.back() == ' ') res.pop_back();
    return res;
}

std::mutex& g_mn = *new std::mutex;                        // protege los tres nombres (se filtran a propósito, como g_m)
std::string& g_mi_nombre = *new std::string;               // el de esta persona
std::string& g_apodo_amigo = *new std::string;             // apodo local para el amigo (solo esta sala)
bool g_nombre_cargado = false;

void cargar_nombre_si_hace_falta() {  // con g_mn tomado
    if (g_nombre_cargado) return;
    g_nombre_cargado = true;
    g_mi_nombre = limpiar_nombre(leer_ini_online("Nombre", false));
}

std::string mi_nombre() {
    std::lock_guard<std::mutex> b(g_mn);
    cargar_nombre_si_hace_falta();
    return g_mi_nombre;
}

// ── STUN ────────────────────────────────────────────────────────────────────────────────────
struct Servidor {
    std::string anfitrion;
    int puerto = 3478;
};

std::vector<Servidor> servidores_stun() {
    std::string lista = entorno("MTP_STUN_SERVERS");
    if (lista.empty()) lista = leer_ini_online("StunServers");
    if (lista.empty()) lista = "stun.l.google.com:19302 stun.cloudflare.com:3478 stun1.l.google.com:19302";
    std::vector<Servidor> res;
    std::string pieza;
    auto cerrar_pieza = [&] {
        if (pieza.empty()) return;
        Servidor sv;
        const std::size_t dp = pieza.rfind(':');
        if (dp != std::string::npos) {
            sv.anfitrion = pieza.substr(0, dp);
            sv.puerto = std::atoi(pieza.c_str() + dp + 1);
        } else {
            sv.anfitrion = pieza;
        }
        if (!sv.anfitrion.empty() && sv.puerto > 0 && sv.puerto < 65536) res.push_back(sv);
        pieza.clear();
    };
    for (char c : lista) {
        if (c == ' ' || c == ',' || c == ';' || c == '\t') cerrar_pieza();
        else pieza.push_back(c);
    }
    cerrar_pieza();
    if (res.size() > 4) res.resize(4);
    return res;
}

bool resolver(const Servidor& sv, Extremo& fuera) {
    addrinfo pistas;
    std::memset(&pistas, 0, sizeof pistas);
    pistas.ai_family = AF_INET;
    pistas.ai_socktype = SOCK_DGRAM;
    addrinfo* lista = nullptr;
    const std::string puerto = std::to_string(sv.puerto);
    if (getaddrinfo(sv.anfitrion.c_str(), puerto.c_str(), &pistas, &lista) != 0 || !lista) return false;
    bool ok = false;
    for (addrinfo* a = lista; a; a = a->ai_next) {
        if (a->ai_family == AF_INET && a->ai_addrlen >= sizeof(sockaddr_in)) {
            fuera = de_sockaddr(*reinterpret_cast<sockaddr_in*>(a->ai_addr));
            ok = true;
            break;
        }
    }
    freeaddrinfo(lista);
    return ok;
}

// Espera hasta `ms` a que el socket tenga datos. true si los hay.
bool esperar_lectura(socket_t s, int ms) {
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(s, &fds);
    timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    const int r = select(static_cast<int>(s) + 1, &fds, nullptr, nullptr, &tv);
    return r > 0;
}

socket_t abrir_udp(std::uint16_t& puerto_fuera) {
    iniciar_red();
    socket_t s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == kSocketNulo) return kSocketNulo;
#if defined(_WIN32)
    // Sin esto, un aviso ICMP de «puerto cerrado» hace fallar el siguiente recvfrom (WSAECONNRESET).
    BOOL no = FALSE;
    DWORD devueltos = 0;
    WSAIoctl(s, _WSAIOW(IOC_VENDOR, 12), &no, sizeof no, nullptr, 0, &devueltos, nullptr, nullptr);
#endif
    sockaddr_in sa;
    std::memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_ANY);
    sa.sin_port = 0;
    if (bind(s, reinterpret_cast<sockaddr*>(&sa), sizeof sa) != 0) {
        cerrar_socket(s);
        return kSocketNulo;
    }
    sockaddr_in real;
    socklen_t largo = sizeof real;
    if (getsockname(s, reinterpret_cast<sockaddr*>(&real), &largo) != 0) {
        cerrar_socket(s);
        return kSocketNulo;
    }
    puerto_fuera = ntohs(real.sin_port);
    return s;
}

void enviar(socket_t s, const Extremo& a, const void* datos, int n) {
    const sockaddr_in sa = a_sockaddr(a);
    sendto(s, static_cast<const char*>(datos), n, 0, reinterpret_cast<const sockaddr*>(&sa), sizeof sa);
}

// Lee un datagrama sin bloquear (tras esperar_lectura). Devuelve su tamaño o -1.
int leer_datagrama(socket_t s, unsigned char* buf, int tam, Extremo& origen) {
    sockaddr_in de;
    socklen_t largo = sizeof de;
    const int n = recvfrom(s, reinterpret_cast<char*>(buf), tam, 0, reinterpret_cast<sockaddr*>(&de), &largo);
    if (n < 0) return -1;
    origen = de_sockaddr(de);
    return n;
}

struct ResultadoStun {
    bool ok = false;
    Extremo publico;
    bool simetrico = false;
};

// Busca la dirección que el servidor ha visto en la respuesta (XOR-MAPPED-ADDRESS o MAPPED-ADDRESS).
bool leer_respuesta_stun(const unsigned char* d, int n, const unsigned char* tid, Extremo& visto) {
    if (n < 20 || d[0] != 0x01 || d[1] != 0x01) return false;
    if (leer32(d + 4) != 0x2112A442u) return false;
    if (std::memcmp(d + 8, tid, 12) != 0) return false;
    const int largo = leer16(d + 2);
    if (largo + 20 > n) return false;
    int pos = 20;
    bool hallada = false;
    Extremo xor_visto, claro;
    while (pos + 4 <= 20 + largo) {
        const int tipo = leer16(d + pos);
        const int len = leer16(d + pos + 2);
        const unsigned char* v = d + pos + 4;
        if (pos + 4 + len > 20 + largo) break;
        if ((tipo == 0x0020 || tipo == 0x0001) && len >= 8 && v[1] == 0x01) {
            std::uint16_t puerto = leer16(v + 2);
            std::uint32_t ip = leer32(v + 4);
            if (tipo == 0x0020) {
                puerto = static_cast<std::uint16_t>(puerto ^ 0x2112u);
                ip ^= 0x2112A442u;
                xor_visto.ip = ip;
                xor_visto.puerto = puerto;
                hallada = true;
            } else {
                claro.ip = ip;
                claro.puerto = puerto;
                if (xor_visto.vacio()) hallada = true;
            }
        }
        pos += 4 + ((len + 3) & ~3);
    }
    if (!hallada) return false;
    visto = xor_visto.vacio() ? claro : xor_visto;
    return !visto.vacio();
}

ResultadoStun consultar_stun(socket_t sock, const std::atomic<bool>& cancelar, int plazo_ms) {
    ResultadoStun res;
    std::vector<Extremo> destinos;
    for (const Servidor& sv : servidores_stun()) {
        if (cancelar.load()) return res;
        Extremo e;
        if (resolver(sv, e)) destinos.push_back(e);
        else trazar("STUN: no se pudo resolver " + sv.anfitrion);
    }
    if (destinos.empty()) return res;

    unsigned char peticion[20];
    std::memset(peticion, 0, sizeof peticion);
    peticion[0] = 0x00;
    peticion[1] = 0x01;  // Binding Request
    poner32(peticion + 4, 0x2112A442u);
    {
        std::random_device rd;
        for (int i = 8; i < 20; ++i) peticion[i] = static_cast<unsigned char>(rd());
    }
    std::vector<Extremo> servidores_que_contestaron;
    std::vector<Extremo> vistos;
    const long long t0 = ahora_ms();
    long long ultimo_envio = -100000;
    while (ahora_ms() - t0 < plazo_ms && !cancelar.load()) {
        if (ahora_ms() - ultimo_envio >= 400) {
            for (const Extremo& d : destinos) enviar(sock, d, peticion, sizeof peticion);
            ultimo_envio = ahora_ms();
        }
        if (esperar_lectura(sock, 50)) {
            unsigned char buf[600];
            Extremo origen, visto;
            while (esperar_lectura(sock, 0)) {
                const int n = leer_datagrama(sock, buf, sizeof buf, origen);
                if (n < 0) break;
                if (!leer_respuesta_stun(buf, n, peticion + 8, visto)) continue;
                if (std::find(servidores_que_contestaron.begin(), servidores_que_contestaron.end(), origen) ==
                    servidores_que_contestaron.end()) {
                    servidores_que_contestaron.push_back(origen);
                    vistos.push_back(visto);
                }
            }
        }
        if (vistos.size() >= 2) break;
        if (!vistos.empty() && ahora_ms() - t0 > 1500) break;
    }
    if (vistos.empty()) return res;
    res.ok = true;
    res.publico = vistos[0];
    for (std::size_t i = 1; i < vistos.size(); ++i)
        if (vistos[i] != vistos[0]) res.simetrico = true;
    return res;
}

// Dirección de esta máquina en su red local (la que usaría para salir a internet).
std::uint32_t ip_local_de_esta_maquina() {
    const std::string forzada = entorno("MTP_INV_IP_LOCAL");  // solo para las pruebas
    if (!forzada.empty()) {
        in_addr a;
        if (inet_pton(AF_INET, forzada.c_str(), &a) == 1) return ntohl(a.s_addr);
    }
    iniciar_red();
    socket_t s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s != kSocketNulo) {
        // «Conectar» un socket UDP no envía nada: solo hace que el sistema elija la interfaz de salida.
        Extremo lejano;
        lejano.ip = (8u << 24) | (8u << 16) | (8u << 8) | 8u;
        lejano.puerto = 53;
        const sockaddr_in sa = a_sockaddr(lejano);
        if (connect(s, reinterpret_cast<const sockaddr*>(&sa), sizeof sa) == 0) {
            sockaddr_in yo;
            socklen_t largo = sizeof yo;
            if (getsockname(s, reinterpret_cast<sockaddr*>(&yo), &largo) == 0) {
                const std::uint32_t ip = ntohl(yo.sin_addr.s_addr);
                if (ip != 0) {
                    cerrar_socket(s);
                    return ip;
                }
            }
        }
        cerrar_socket(s);
    }
#if !defined(_WIN32)
    ifaddrs* lista = nullptr;
    if (getifaddrs(&lista) == 0) {
        std::uint32_t hallada = 0;
        for (ifaddrs* a = lista; a; a = a->ifa_next) {
            if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
            if (!(a->ifa_flags & IFF_UP) || (a->ifa_flags & IFF_LOOPBACK)) continue;
            hallada = ntohl(reinterpret_cast<sockaddr_in*>(a->ifa_addr)->sin_addr.s_addr);
            break;
        }
        freeifaddrs(lista);
        if (hallada) return hallada;
    }
#else
    char nombre[256];
    if (gethostname(nombre, sizeof nombre) == 0) {
        addrinfo pistas;
        std::memset(&pistas, 0, sizeof pistas);
        pistas.ai_family = AF_INET;
        addrinfo* lista = nullptr;
        if (getaddrinfo(nombre, nullptr, &pistas, &lista) == 0 && lista) {
            std::uint32_t hallada = 0;
            for (addrinfo* a = lista; a; a = a->ai_next) {
                const std::uint32_t ip = ntohl(reinterpret_cast<sockaddr_in*>(a->ai_addr)->sin_addr.s_addr);
                if ((ip >> 24) != 127) {
                    hallada = ip;
                    break;
                }
            }
            freeaddrinfo(lista);
            if (hallada) return hallada;
        }
    }
#endif
    return 0x7F000001u;  // 127.0.0.1
}

// ── La sala ─────────────────────────────────────────────────────────────────────────────────
struct Sala {
    std::mutex m;
    std::condition_variable cv;
    MtpInvInfo info;
    std::atomic<bool> cancelar{false};
    std::thread hilo;
    std::uint32_t nonce = 0;
    int rol = MTP_INV_NINGUNO;
    long long desde_ms = 0;  // cuándo empezó el estado actual
    // Anfitrión: la respuesta del invitado.
    bool respuesta_lista = false;
    Carga respuesta;
    // Resultado.
    Extremo par_final;
    int puerto_local = 0;
    std::string nombre_amigo;  // el que anunció el otro equipo (ya limpio); "" si no lo oímos o no puso
};

// Se crean con «new» y no se destruyen nunca: si el programa termina con una sala en marcha (la
// persona cierra la ventana mientras espera), un std::thread todavía «joinable» en un objeto
// estático haría abortar el proceso al salir.
std::mutex& g_m = *new std::mutex;
std::shared_ptr<Sala>& g_sala = *new std::shared_ptr<Sala>;

void fijar_estado(Sala& s, int estado, int error = 0) {
    std::lock_guard<std::mutex> b(s.m);
    s.info.estado = estado;
    s.info.error = error;
    s.desde_ms = ahora_ms();
    if (estado == MTP_INV_ERROR) trazar("error " + std::to_string(error));
}

void rellenar_codigo(Sala& s, const Carga& c) {
    const std::string texto = codificar(c);
    std::lock_guard<std::mutex> b(s.m);
    if (texto != s.info.codigo) {
        std::snprintf(s.info.codigo, sizeof s.info.codigo, "%s", texto.c_str());
        s.info.codigo_nuevo++;
    }
    s.info.sin_internet = c.sin_publica ? 1 : 0;
    s.info.nat_simetrico = c.nat_simetrico ? 1 : 0;
}

bool preparar_local(Sala& s, socket_t& sock, Carga& mia) {
    std::uint16_t puerto = 0;
    sock = abrir_udp(puerto);
    if (sock == kSocketNulo) return false;
    {
        std::lock_guard<std::mutex> b(s.m);
        s.puerto_local = puerto;
    }
    fijar_estado(s, MTP_INV_PREPARANDO);
    const ResultadoStun st = consultar_stun(sock, s.cancelar, 2800);
    mia.etiqueta = etiqueta_version();
    mia.local.ip = ip_local_de_esta_maquina();
    mia.local.puerto = puerto;
    if (st.ok) {
        mia.publico = st.publico;
        mia.nat_simetrico = st.simetrico;
        mia.sin_publica = false;
        trazar("dirección pública averiguada");
        if (st.simetrico) trazar("NAT simétrico detectado");
    } else {
        mia.publico = Extremo();
        mia.nat_simetrico = false;
        mia.sin_publica = true;
        trazar("sin dirección pública (sin internet o sin STUN): el código solo vale en la red local");
    }
    return true;
}

// ── Perforado ───────────────────────────────────────────────────────────────────────────────
// Paquete: «MTPI», marca de la sala (4 bytes), clase (1 = hola, 2 = enterado), rol (1 anfitrión,
// 2 invitado), longitud del nombre (1 byte) y el nombre en UTF-8 (hasta kMaxNombre bytes).
constexpr int kCabeceraPaquete = 11;
constexpr int kTamPaqueteMax = kCabeceraPaquete + static_cast<int>(kMaxNombre);

int armar_paquete(unsigned char* p, std::uint32_t marca, int clase, int rol, const std::string& nombre) {
    p[0] = 'M';
    p[1] = 'T';
    p[2] = 'P';
    p[3] = 'I';
    poner32(p + 4, marca);
    p[8] = static_cast<unsigned char>(clase);
    p[9] = static_cast<unsigned char>(rol);
    const std::size_t n = std::min(nombre.size(), kMaxNombre);
    p[10] = static_cast<unsigned char>(n);
    std::memcpy(p + kCabeceraPaquete, nombre.data(), n);
    return kCabeceraPaquete + static_cast<int>(n);
}

std::uint32_t marca_de(std::uint32_t nonce) { return nonce ^ 0x4D545049u; }

bool perforar(Sala& s, socket_t sock, std::uint32_t marca, int mi_rol, const std::vector<Extremo>& objetivos_in,
              int plazo_ms, int intervalo_ms, Extremo& par_fuera) {
    std::vector<Extremo> objetivos;
    for (const Extremo& e : objetivos_in) {
        if (e.vacio()) continue;
        if (std::find(objetivos.begin(), objetivos.end(), e) == objetivos.end()) objetivos.push_back(e);
    }
    if (objetivos.empty()) return false;
    const long long t0 = ahora_ms();
    long long ultimo = -100000;
    bool oido = false, confirmado = false;
    Extremo origen;
    const std::string yo = mi_nombre();

    auto enviar_paquete = [&](const Extremo& a, int clase) {
        unsigned char p[kTamPaqueteMax];
        const int n = armar_paquete(p, marca, clase, mi_rol, yo);
        enviar(sock, a, p, n);
    };

    auto drenar = [&]() {
        unsigned char buf[128];
        while (esperar_lectura(sock, 0)) {
            Extremo de;
            const int n = leer_datagrama(sock, buf, sizeof buf, de);
            if (n < 0) break;
            if (n < kCabeceraPaquete || std::memcmp(buf, "MTPI", 4) != 0) continue;
            if (buf[10] > kMaxNombre || n != kCabeceraPaquete + buf[10]) continue;
            if (leer32(buf + 4) != marca) continue;
            if (buf[9] == mi_rol || (buf[9] != 1 && buf[9] != 2)) continue;
            if (!oido) trazar("se ha oído al otro equipo desde " + texto_extremo(de));
            oido = true;
            origen = de;
            if (buf[8] == 2) confirmado = true;
            {
                // El nombre llega por la red: se limpia antes de guardarlo (y de enseñarlo).
                const std::string nombre = limpiar_nombre(std::string(reinterpret_cast<char*>(buf) + kCabeceraPaquete, buf[10]));
                std::lock_guard<std::mutex> b(s.m);
                s.nombre_amigo = nombre;
            }
            enviar_paquete(de, 2);
        }
    };

    while (ahora_ms() - t0 < plazo_ms && !confirmado) {
        if (s.cancelar.load()) return false;
        if (ahora_ms() - ultimo >= intervalo_ms) {
            for (const Extremo& o : objetivos) enviar_paquete(o, oido ? 2 : 1);
            if (oido) enviar_paquete(origen, oido ? 2 : 1);
            ultimo = ahora_ms();
        }
        if (esperar_lectura(sock, 50)) drenar();
    }
    if (!confirmado) return false;
    // El otro equipo puede no haber oído aún nuestro último «enterado»: se sigue contestando un rato.
    for (int i = 0; i < 12 && !s.cancelar.load(); ++i) {
        enviar_paquete(origen, 2);
        if (esperar_lectura(sock, 100)) drenar();
    }
    par_fuera = origen;
    return true;
}

void hilo_anfitrion(std::shared_ptr<Sala> s) {
    socket_t sock = kSocketNulo;
    Carga mia;
    mia.tipo = 0;
    mia.nonce = s->nonce;
    if (!preparar_local(*s, sock, mia)) {
        fijar_estado(*s, MTP_INV_ERROR, MTP_INV_ERR_SIN_RED);
        return;
    }
    if (s->cancelar.load()) {
        cerrar_socket(sock);
        return;
    }
    rellenar_codigo(*s, mia);
    fijar_estado(*s, MTP_INV_ESPERANDO_RESPUESTA);

    // Mientras espera la respuesta, repite la consulta STUN de vez en cuando: así el router no cierra
    // el hueco del puerto y, si la dirección pública cambiara, el código se renueva.
    Carga resp;
    for (;;) {
        std::unique_lock<std::mutex> b(s->m);
        s->cv.wait_for(b, std::chrono::seconds(8), [&] { return s->respuesta_lista || s->cancelar.load(); });
        if (s->cancelar.load()) {
            b.unlock();
            cerrar_socket(sock);
            return;
        }
        if (s->respuesta_lista) {
            resp = s->respuesta;
            break;
        }
        b.unlock();
        if (!mia.sin_publica) {
            const ResultadoStun st = consultar_stun(sock, s->cancelar, 1500);
            if (st.ok && st.publico != mia.publico) {
                mia.publico = st.publico;
                mia.nat_simetrico = st.simetrico;
                rellenar_codigo(*s, mia);
                trazar("la dirección pública ha cambiado: código nuevo");
            }
        }
    }
    {
        std::lock_guard<std::mutex> b(s->m);
        s->info.amigo_nat_simetrico = resp.nat_simetrico ? 1 : 0;
    }
    fijar_estado(*s, MTP_INV_CONECTANDO);
    Extremo par;
    const bool ok = perforar(*s, sock, marca_de(s->nonce), MTP_INV_ANFITRION, {resp.publico, resp.local},
                             plazo(45), 400, par);
    cerrar_socket(sock);
    if (s->cancelar.load()) return;
    if (!ok) {
        fijar_estado(*s, MTP_INV_ERROR, MTP_INV_ERR_TIEMPO);
        return;
    }
    {
        std::lock_guard<std::mutex> b(s->m);
        s->par_final = par;
        std::snprintf(s->info.par, sizeof s->info.par, "%s", texto_extremo(par).c_str());
    }
    fijar_estado(*s, MTP_INV_CONECTADO);
}

void hilo_invitado(std::shared_ptr<Sala> s, Carga anfitrion) {
    socket_t sock = kSocketNulo;
    Carga mia;
    mia.tipo = 1;
    mia.nonce = anfitrion.nonce;
    if (!preparar_local(*s, sock, mia)) {
        fijar_estado(*s, MTP_INV_ERROR, MTP_INV_ERR_SIN_RED);
        return;
    }
    if (s->cancelar.load()) {
        cerrar_socket(sock);
        return;
    }
    rellenar_codigo(*s, mia);
    {
        std::lock_guard<std::mutex> b(s->m);
        s->info.amigo_nat_simetrico = anfitrion.nat_simetrico ? 1 : 0;
    }
    fijar_estado(*s, MTP_INV_ESPERANDO_AMIGO);

    // El invitado empieza a perforar ya: sus paquetes abren el hueco de su router hacia el anfitrión,
    // que empezará a contestar en cuanto pegue el código de respuesta. Espera hasta 4 minutos (lo
    // que tarde el anfitrión en pegarlo).
    Extremo par;
    const bool ok = perforar(*s, sock, marca_de(anfitrion.nonce), MTP_INV_INVITADO,
                             {anfitrion.publico, anfitrion.local}, plazo(240), 500, par);
    cerrar_socket(sock);
    if (s->cancelar.load()) return;
    if (!ok) {
        fijar_estado(*s, MTP_INV_ERROR, MTP_INV_ERR_TIEMPO);
        return;
    }
    {
        std::lock_guard<std::mutex> b(s->m);
        s->par_final = par;
        std::snprintf(s->info.par, sizeof s->info.par, "%s", texto_extremo(par).c_str());
    }
    fijar_estado(*s, MTP_INV_CONECTADO);
}

std::uint32_t nonce_aleatorio() {
    const std::string forzado = entorno("MTP_INV_NONCE");  // solo para las pruebas
    if (!forzado.empty()) {
        const std::uint32_t n = static_cast<std::uint32_t>(std::strtoul(forzado.c_str(), nullptr, 10));
        if (n != 0) return n;
    }
    std::random_device rd;
    std::mt19937_64 gen((static_cast<std::uint64_t>(rd()) << 32) ^ rd() ^ static_cast<std::uint64_t>(ahora_ms()));
    return static_cast<std::uint32_t>(gen() % 0x7FFFFFFEull) + 1u;  // 1 .. 0x7FFFFFFE
}

void parar_sala(std::shared_ptr<Sala>& s) {
    if (!s) return;
    s->cancelar.store(true);
    s->cv.notify_all();
    if (s->hilo.joinable()) s->hilo.join();
    s.reset();
}

std::shared_ptr<Sala> nueva_sala(int rol) {
    auto s = std::make_shared<Sala>();
    std::memset(&s->info, 0, sizeof s->info);
    s->info.rol = rol;
    s->info.estado = MTP_INV_PREPARANDO;
    s->rol = rol;
    s->nonce = nonce_aleatorio();
    s->desde_ms = ahora_ms();
    return s;
}

}  // namespace

// ── API en C ────────────────────────────────────────────────────────────────────────────────
extern "C" {

int mtp_inv_disponible(void) {
#if defined(MTP_NETPLAY)
    return 1;
#else
    return 0;
#endif
}

int mtp_inv_crear(void) {
    if (!mtp_inv_disponible()) return MTP_INV_ERR_NO_DISPONIBLE;
    std::lock_guard<std::mutex> g(g_m);
    if (g_sala) return MTP_INV_ERR_OCUPADO;
    g_sala = nueva_sala(MTP_INV_ANFITRION);
    std::shared_ptr<Sala> s = g_sala;
    s->hilo = std::thread([s] { hilo_anfitrion(s); });
    return MTP_INV_OK;
}

int mtp_inv_comprobar(const char* codigo, int tipo) {
    return decodificar(codigo, tipo, nullptr);
}

int mtp_inv_unirse(const char* codigo_invitacion) {
    if (!mtp_inv_disponible()) return MTP_INV_ERR_NO_DISPONIBLE;
    Carga c;
    const int r = decodificar(codigo_invitacion, 0, &c);
    if (r != MTP_INV_OK) return r;
    std::lock_guard<std::mutex> g(g_m);
    if (g_sala) return MTP_INV_ERR_OCUPADO;
    g_sala = nueva_sala(MTP_INV_INVITADO);
    g_sala->nonce = c.nonce;
    std::shared_ptr<Sala> s = g_sala;
    s->hilo = std::thread([s, c] { hilo_invitado(s, c); });
    return MTP_INV_OK;
}

int mtp_inv_responder(const char* codigo_respuesta) {
    Carga c;
    const int r = decodificar(codigo_respuesta, 1, &c);
    if (r != MTP_INV_OK) return r;
    std::shared_ptr<Sala> s;
    {
        std::lock_guard<std::mutex> g(g_m);
        s = g_sala;
    }
    if (!s || s->rol != MTP_INV_ANFITRION) return MTP_INV_ERR_OCUPADO;
    if (c.nonce != s->nonce) return MTP_INV_ERR_OTRA_SALA;
    {
        std::lock_guard<std::mutex> b(s->m);
        if (s->info.estado != MTP_INV_ESPERANDO_RESPUESTA) return MTP_INV_ERR_OCUPADO;
        s->respuesta = c;
        s->respuesta_lista = true;
    }
    s->cv.notify_all();
    return MTP_INV_OK;
}

void mtp_inv_estado(MtpInvInfo* out) {
    if (!out) return;
    std::shared_ptr<Sala> s;
    {
        std::lock_guard<std::mutex> g(g_m);
        s = g_sala;
    }
    if (!s) {
        std::memset(out, 0, sizeof *out);
        return;
    }
    std::string apodo;
    {
        std::lock_guard<std::mutex> n(g_mn);
        apodo = g_apodo_amigo;
    }
    std::lock_guard<std::mutex> b(s->m);
    *out = s->info;
    out->segundos = static_cast<int>((ahora_ms() - s->desde_ms) / 1000);
    const std::string& visto = apodo.empty() ? s->nombre_amigo : apodo;  // el apodo local manda sobre el anunciado
    std::snprintf(out->nombre_amigo, sizeof out->nombre_amigo, "%s", visto.c_str());
}

void mtp_inv_cancelar(void) {
    std::shared_ptr<Sala> s;
    {
        std::lock_guard<std::mutex> g(g_m);
        s = g_sala;
        g_sala.reset();
    }
    parar_sala(s);
}

int mtp_inv_argumentos(char* out, int tam) {
    if (!out || tam <= 0) return 0;
    std::shared_ptr<Sala> s;
    {
        std::lock_guard<std::mutex> g(g_m);
        s = g_sala;
    }
    if (!s) return 0;
    std::string texto;
    std::string apodo;
    {
        std::lock_guard<std::mutex> n(g_mn);
        apodo = g_apodo_amigo;
    }
    const std::string yo = mi_nombre();
    {
        std::lock_guard<std::mutex> b(s->m);
        if (s->info.estado != MTP_INV_CONECTADO) return 0;
        texto += "--netplay-bind\n0.0.0.0:" + std::to_string(s->puerto_local) + "\n";
        texto += "--netplay-peer\n" + texto_extremo(s->par_final) + "\n";
        texto += "--netplay-seat\n" + std::string(s->rol == MTP_INV_ANFITRION ? "0" : "1") + "\n";
        texto += "--netplay-session\n" + std::to_string(s->nonce) + "\n";
        // Nombres para reconocerse en la partida (no son opciones del juego en red: main.cpp los recoge antes).
        const std::string amigo = apodo.empty() ? s->nombre_amigo : apodo;
        if (!yo.empty()) texto += "--mtp-nombre\n" + yo + "\n";
        if (!amigo.empty()) texto += "--mtp-nombre-amigo\n" + amigo + "\n";
    }
    if (static_cast<int>(texto.size()) + 1 > tam) return 0;
    std::memcpy(out, texto.c_str(), texto.size() + 1);
    // El juego en red usa ya el puerto: la sala vuelve a reposo.
    {
        std::lock_guard<std::mutex> g(g_m);
        if (g_sala == s) g_sala.reset();
    }
    parar_sala(s);
    return static_cast<int>(texto.size());
}

void mtp_inv_nombre_propio(char* out, int tam) {
    if (!out || tam <= 0) return;
    const std::string n = mi_nombre();
    std::snprintf(out, static_cast<std::size_t>(tam), "%s", n.c_str());
}

void mtp_inv_fijar_nombre_propio(const char* nombre, int guardar) {
    const std::string limpio = limpiar_nombre(nombre ? nombre : "");
    {
        std::lock_guard<std::mutex> b(g_mn);
        g_nombre_cargado = true;
        g_mi_nombre = limpio;
    }
    if (guardar) escribir_ini_online("Nombre", limpio);
}

void mtp_inv_fijar_apodo_amigo(const char* apodo) {
    const std::string limpio = limpiar_nombre(apodo ? apodo : "");
    std::lock_guard<std::mutex> b(g_mn);
    g_apodo_amigo = limpio;
}

int mtp_inv_prueba_codigo(int tipo, unsigned int nonce, unsigned int ip_publica, int puerto_publico,
                          unsigned int ip_local, int puerto_local, int nat_simetrico, char* out, int tam) {
    Carga c;
    c.tipo = tipo;
    c.nonce = nonce;
    c.etiqueta = etiqueta_version();
    c.publico.ip = ip_publica;
    c.publico.puerto = static_cast<std::uint16_t>(puerto_publico);
    c.local.ip = ip_local;
    c.local.puerto = static_cast<std::uint16_t>(puerto_local);
    c.nat_simetrico = nat_simetrico != 0;
    c.sin_publica = ip_publica == 0;
    const std::string t = codificar(c);
    if (!out || static_cast<int>(t.size()) + 1 > tam) return 1;
    std::memcpy(out, t.c_str(), t.size() + 1);
    return 0;
}

}  // extern "C"
