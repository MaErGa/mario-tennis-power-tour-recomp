// aviso_actualizacion.cpp — aviso de «hay una versión nueva» para el menú de arranque.
//
// El menú llama a mtp_aviso_actualizacion() en cada fotograma. La primera vez lanza la
// comprobación en un hilo aparte (una sola petición de unos pocos bytes: el archivo VERSION
// del repositorio) y devuelve "" mientras no haya respuesta. Si la versión de allí es mayor que
// la instalada, devuelve ese número. NUNCA descarga ni ejecuta nada: solo informa; para
// actualizar se usa ACTUALIZAR.bat (Windows) o tools/actualizar.sh (Linux). Si no hay internet, la dirección no existe o la
// respuesta no parece un número de versión, simplemente no sale ningún aviso.
//
// Ajustes (config.ini, sección [Menu]):
//   CheckUpdates = 0          desactiva la comprobación (por defecto 1).
//   UpdateUrl    = https://…  dirección del archivo VERSION (por defecto la de CMake).
// La variable de entorno MTP_URL_VERSION tiene prioridad sobre config.ini (para pruebas).
//
// Solo se aceptan direcciones https://; http:// únicamente hacia esta misma máquina
// (127.0.0.1 o localhost), para poder probarlo sin internet.
#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#include <winhttp.h>
#else
#include <thread>
#endif

#ifndef MTP_VERSION
#define MTP_VERSION ""
#endif
#ifndef MTP_URL_VERSION_DEFECTO
#define MTP_URL_VERSION_DEFECTO ""
#endif

namespace {

std::atomic<int> g_estado{0};  // 0 sin empezar · 1 comprobando · 2 terminado
char g_version_nueva[40] = "";  // se escribe antes de pasar g_estado a 2

// ── config.ini ─────────────────────────────────────────────────────────────────
std::string recortar(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}

bool iguales_sin_mayusculas(const std::string& a, const char* b) {
    if (a.size() != std::strlen(b)) return false;
    for (std::size_t i = 0; i < a.size(); ++i)
        if (std::tolower(static_cast<unsigned char>(a[i])) != std::tolower(static_cast<unsigned char>(b[i])))
            return false;
    return true;
}

// Valor de «clave» dentro de la sección [Menu] de config.ini ("" si no está).
std::string leer_ajuste_menu(const char* clave) {
    const char* ruta = std::getenv("MTP_CONFIG_INI");
    if (!ruta || !ruta[0]) return "";
    std::ifstream f(ruta);
    if (!f) return "";
    std::string linea;
    bool en_menu = false;
    while (std::getline(f, linea)) {
        linea = recortar(linea);
        if (linea.empty() || linea[0] == ';' || linea[0] == '#') continue;
        if (linea[0] == '[') {
            en_menu = iguales_sin_mayusculas(linea, "[Menu]");
            continue;
        }
        if (!en_menu) continue;
        const std::size_t igual = linea.find('=');
        if (igual == std::string::npos) continue;
        if (iguales_sin_mayusculas(recortar(linea.substr(0, igual)), clave))
            return recortar(linea.substr(igual + 1));
    }
    return "";
}

// ── Dirección ──────────────────────────────────────────────────────────────────
// Solo caracteres «seguros» (la dirección acaba en una orden de curl en Linux) y solo https,
// salvo http hacia la propia máquina.
bool url_valida(const std::string& u) {
    if (u.size() < 12 || u.size() > 300) return false;
    for (char c : u) {
        const bool ok = std::isalnum(static_cast<unsigned char>(c)) || std::strchr("-._~:/%+", c) != nullptr;
        if (!ok) return false;
    }
    if (u.compare(0, 8, "https://") == 0) return true;
    return u.compare(0, 17, "http://127.0.0.1:") == 0 || u.compare(0, 17, "http://127.0.0.1/") == 0 ||
           u.compare(0, 17, "http://localhost:") == 0 || u.compare(0, 17, "http://localhost/") == 0;
}

// ── Descarga (como mucho 256 bytes) ────────────────────────────────────────────
#if defined(_WIN32)
std::string descargar(const std::string& url) {
    std::string texto;
    const std::wstring w(url.begin(), url.end());  // la dirección es ASCII (ya validada)
    wchar_t host[256] = {0};
    wchar_t ruta[1024] = {0};
    URL_COMPONENTS uc;
    std::memset(&uc, 0, sizeof(uc));
    uc.dwStructSize = sizeof(uc);
    uc.lpszHostName = host;
    uc.dwHostNameLength = 255;
    uc.lpszUrlPath = ruta;
    uc.dwUrlPathLength = 1023;
    if (!WinHttpCrackUrl(w.c_str(), 0, 0, &uc)) return texto;

    HINTERNET sesion = WinHttpOpen(L"MarioTennisPowerTourRecomp", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                   WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!sesion) return texto;
    WinHttpSetTimeouts(sesion, 4000, 4000, 4000, 6000);
    HINTERNET conexion = WinHttpConnect(sesion, host, uc.nPort, 0);
    if (conexion) {
        const DWORD flags = (uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
        HINTERNET peticion = WinHttpOpenRequest(conexion, L"GET", ruta, nullptr, WINHTTP_NO_REFERER,
                                                WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
        if (peticion) {
            if (WinHttpSendRequest(peticion, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
                WinHttpReceiveResponse(peticion, nullptr)) {
                DWORD estado = 0, tam = sizeof(estado);
                WinHttpQueryHeaders(peticion, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                    WINHTTP_HEADER_NAME_BY_INDEX, &estado, &tam, WINHTTP_NO_HEADER_INDEX);
                if (estado == 200) {
                    char buf[128];
                    DWORD leidos = 0;
                    while (texto.size() < 256 && WinHttpReadData(peticion, buf, sizeof(buf), &leidos) && leidos > 0)
                        texto.append(buf, leidos);
                }
            }
            WinHttpCloseHandle(peticion);
        }
        WinHttpCloseHandle(conexion);
    }
    WinHttpCloseHandle(sesion);
    return texto;
}
#else
std::string descargar(const std::string& url) {
    std::string texto;
    // La dirección solo lleva caracteres seguros (url_valida), así que no hay nada que escapar.
    const std::string orden = "curl -fsS --max-time 6 --proto '=https,http' '" + url + "' 2>/dev/null";
    FILE* p = popen(orden.c_str(), "r");
    if (!p) return texto;
    char buf[128];
    std::size_t n;
    while (texto.size() < 256 && (n = std::fread(buf, 1, sizeof(buf), p)) > 0) texto.append(buf, n);
    pclose(p);
    return texto;
}
#endif

// ── Versiones ──────────────────────────────────────────────────────────────────
// «0.4.10» → {0, 4, 10, 0}. Devuelve false si no es un número de versión (solo cifras y
// puntos, de 2 a 4 partes).
bool leer_version(const std::string& texto, int v[4]) {
    const std::string t = recortar(texto);
    if (t.empty() || t.size() > 32) return false;
    int partes = 0;
    long actual = 0;
    bool hay_cifra = false;
    for (std::size_t i = 0; i <= t.size(); ++i) {
        const char c = i < t.size() ? t[i] : '.';
        if (c >= '0' && c <= '9') {
            actual = actual * 10 + (c - '0');
            if (actual > 100000) return false;
            hay_cifra = true;
        } else if (c == '.') {
            if (!hay_cifra || partes >= 4) return false;
            v[partes++] = static_cast<int>(actual);
            actual = 0;
            hay_cifra = false;
        } else {
            return false;
        }
    }
    if (partes < 2) return false;
    for (int i = partes; i < 4; ++i) v[i] = 0;
    return true;
}

bool es_mas_nueva(const int a[4], const int b[4]) {
    for (int i = 0; i < 4; ++i)
        if (a[i] != b[i]) return a[i] > b[i];
    return false;
}

// ── Comprobación ───────────────────────────────────────────────────────────────
void comprobar() {
    g_version_nueva[0] = '\0';
    const std::string activo = leer_ajuste_menu("CheckUpdates");
    if (!(activo == "0" || iguales_sin_mayusculas(activo, "false") || iguales_sin_mayusculas(activo, "no"))) {
        std::string url;
        if (const char* e = std::getenv("MTP_URL_VERSION")) url = e;
        if (url.empty()) url = leer_ajuste_menu("UpdateUrl");
        if (url.empty()) url = MTP_URL_VERSION_DEFECTO;
        int instalada[4], remota[4];
        if (url_valida(url) && leer_version(MTP_VERSION, instalada)) {
            const std::string respuesta = descargar(url);
            if (leer_version(respuesta, remota) && es_mas_nueva(remota, instalada)) {
                const std::string limpia = recortar(respuesta);
                std::snprintf(g_version_nueva, sizeof(g_version_nueva), "%s", limpia.c_str());
            }
        }
    }
    g_estado.store(2, std::memory_order_release);
}

#if defined(_WIN32)
DWORD WINAPI hilo_comprobar(LPVOID) {
    comprobar();
    return 0;
}
#endif

}  // namespace

// Devuelve la versión nueva («0.4.4») si la hay, o "" si no hay nada que avisar (todavía o nunca).
extern "C" const char* mtp_aviso_actualizacion(void) {
    int esperado = 0;
    if (g_estado.compare_exchange_strong(esperado, 1)) {
#if defined(_WIN32)
        HANDLE h = CreateThread(nullptr, 0, hilo_comprobar, nullptr, 0, nullptr);
        if (h) CloseHandle(h);
        else g_estado.store(2, std::memory_order_release);
#else
        try {
            std::thread(comprobar).detach();
        } catch (...) {
            g_estado.store(2, std::memory_order_release);
        }
#endif
    }
    return g_estado.load(std::memory_order_acquire) == 2 ? g_version_nueva : "";
}

// Versión con la que se compiló este programa (la del archivo VERSION).
extern "C" const char* mtp_version_instalada(void) { return MTP_VERSION; }
