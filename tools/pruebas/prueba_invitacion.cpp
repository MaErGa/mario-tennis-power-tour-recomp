// prueba_invitacion.cpp — pruebas de src/invitacion.cpp sin el juego ni el menú.
// Lo compila y lo orquesta tools/pruebas/probar_invitacion.sh (ver ahí cada escenario).
//
//   prueba_invitacion codigos
//   prueba_invitacion rechazos
//   prueba_invitacion cancelar
//   prueba_invitacion anfitrion ARCHIVO_INVITACION ARCHIVO_RESPUESTA
//   prueba_invitacion invitado  ARCHIVO_INVITACION ARCHIVO_RESPUESTA
//   prueba_invitacion fantasma  ARCHIVO_INVITACION     (anfitrión cuya respuesta no existe)
//   prueba_invitacion nombres   ARCHIVO_INI            (limpieza y guardado de los nombres)
//   prueba_invitacion nombre_guardado                  (lee el nombre guardado en MTP_CONFIG_INI)
// Con MTP_PRUEBA_NOMBRE / MTP_PRUEBA_APODO, «anfitrion» e «invitado» ponen su nombre y el apodo de su amigo.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>

#include "invitacion.h"

namespace {

int g_fallos = 0;

void comprobar(bool ok, const char* texto) {
    std::printf("  %s  %s\n", ok ? "ok" : "FALLO", texto);
    if (!ok) ++g_fallos;
}

void dormir(int ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }

std::string leer_archivo(const std::string& ruta) {
    std::ifstream f(ruta);
    std::string s, l;
    while (std::getline(f, l)) s += l;
    return s;
}

void escribir_archivo(const std::string& ruta, const std::string& texto) {
    const std::string tmp = ruta + ".tmp";
    {
        std::ofstream f(tmp);
        f << texto << "\n";
    }
    std::rename(tmp.c_str(), ruta.c_str());
}

// Espera (hasta `max_ms`) a que `ruta` tenga contenido.
std::string esperar_archivo(const std::string& ruta, int max_ms) {
    for (int t = 0; t < max_ms; t += 50) {
        const std::string s = leer_archivo(ruta);
        if (!s.empty()) return s;
        dormir(50);
    }
    return std::string();
}

// Espera a que el estado deje de ser uno de los transitorios y llegue a `meta` o a un error.
bool esperar_estado(int meta, int max_ms, MtpInvInfo& info) {
    for (int t = 0; t < max_ms; t += 50) {
        mtp_inv_estado(&info);
        if (info.estado == meta || info.estado == MTP_INV_ERROR) return info.estado == meta;
        dormir(50);
    }
    mtp_inv_estado(&info);
    return info.estado == meta;
}

void informe_final(const MtpInvInfo& info) {
    std::printf("FINAL estado=%d error=%d sin_internet=%d nat=%d amigo_nat=%d par=%s\n", info.estado, info.error,
                info.sin_internet, info.nat_simetrico, info.amigo_nat_simetrico, info.par);
    std::printf("AMIGO [%s]\n", info.nombre_amigo);
    char args[512];
    const int n = mtp_inv_argumentos(args, sizeof args);
    if (n > 0) {
        // Una línea por palabra → se imprimen en una sola línea separadas por espacios.
        std::string a(args);
        for (char& c : a)
            if (c == '\n') c = ' ';
        std::printf("ARGS %s\n", a.c_str());
    }
}

int prueba_codigos() {
    std::printf("Códigos\n");
    char c[128];
    comprobar(mtp_inv_prueba_codigo(0, 781890605u, 0x5DB8D822u, 47948, 0xC0A80164u, 47948, 0, c, sizeof c) == 0,
              "se genera un código de invitación");
    std::printf("      %s\n", c);
    comprobar(std::strlen(c) == 49, "mide 49 caracteres (40 + 9 guiones)");
    comprobar(mtp_inv_comprobar(c, 0) == MTP_INV_OK, "se acepta como invitación");
    comprobar(mtp_inv_comprobar(c, 1) == MTP_INV_ERR_TIPO, "como respuesta se rechaza por el tipo");
    std::string minus(c);
    for (char& ch : minus)
        if (ch >= 'A' && ch <= 'Z') ch = static_cast<char>(ch - 'A' + 'a');
    comprobar(mtp_inv_comprobar(minus.c_str(), 0) == MTP_INV_OK, "en minúsculas también");
    std::string raro = std::string("  ") + c + "\n";
    for (char& ch : raro)
        if (ch == '-') ch = ' ';
    comprobar(mtp_inv_comprobar(raro.c_str(), 0) == MTP_INV_OK, "con espacios en vez de guiones y de más");
    std::string confusion(c);
    for (char& ch : confusion) {
        if (ch == '0') ch = 'O';
        else if (ch == '1') ch = 'l';
    }
    comprobar(mtp_inv_comprobar(confusion.c_str(), 0) == MTP_INV_OK, "O por 0 y l por 1 se corrigen");
    comprobar(mtp_inv_comprobar("", 0) == MTP_INV_ERR_CODIGO, "vacío: código mal");
    comprobar(mtp_inv_comprobar(nullptr, 0) == MTP_INV_ERR_CODIGO, "NULL: código mal");
    comprobar(mtp_inv_comprobar("hola", 0) == MTP_INV_ERR_CODIGO, "texto cualquiera: código mal");
    comprobar(mtp_inv_comprobar(std::string(c, 40).c_str(), 0) == MTP_INV_ERR_CODIGO, "incompleto: código mal");
    comprobar(mtp_inv_comprobar((std::string(c) + "A").c_str(), 0) == MTP_INV_ERR_CODIGO, "con un carácter de más: código mal");
    comprobar(mtp_inv_comprobar("U" "UUU-UUUU", 0) == MTP_INV_ERR_CODIGO, "con letras que no existen (U): código mal");

    // Cualquier cambio de un solo carácter debe detectarse.
    const char alfabeto[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    const std::string base(c);
    int cambios = 0, detectados = 0;
    for (std::size_t i = 0; i < base.size(); ++i) {
        if (base[i] == '-') continue;
        for (const char* a = alfabeto; *a; ++a) {
            if (*a == base[i]) continue;
            std::string t = base;
            t[i] = *a;
            ++cambios;
            if (mtp_inv_comprobar(t.c_str(), 0) != MTP_INV_OK) ++detectados;
        }
    }
    std::printf("      (%d de %d cambios de un carácter detectados)\n", detectados, cambios);
    comprobar(cambios == 40 * 31 && detectados == cambios, "todos los cambios de un carácter se detectan");

    // Otra versión del programa.
    setenv("MTP_INV_IDENTIDAD", "otra-version", 1);
    comprobar(mtp_inv_comprobar(c, 0) == MTP_INV_ERR_VERSION, "con otra identidad de compilación: versión distinta");
    unsetenv("MTP_INV_IDENTIDAD");
    comprobar(mtp_inv_comprobar(c, 0) == MTP_INV_OK, "y con la misma, bien");

    // Respuesta.
    char r[128];
    mtp_inv_prueba_codigo(1, 781890605u, 0x5DB8D822u, 1234, 0xC0A80165u, 1234, 1, r, sizeof r);
    comprobar(mtp_inv_comprobar(r, 1) == MTP_INV_OK, "un código de respuesta se acepta como respuesta");
    comprobar(mtp_inv_comprobar(r, 0) == MTP_INV_ERR_TIPO, "y no como invitación");
    return g_fallos ? 1 : 0;
}

int prueba_rechazos() {
    std::printf("Rechazos y cancelar\n");
    char resp[128], inv[128];
    mtp_inv_prueba_codigo(1, 777u, 0x7F000001u, 1000, 0x7F000001u, 1000, 0, resp, sizeof resp);
    mtp_inv_prueba_codigo(0, 777u, 0x7F000001u, 1000, 0x7F000001u, 1000, 0, inv, sizeof inv);
    comprobar(mtp_inv_disponible() == 1, "el juego en red está en esta compilación");
    comprobar(mtp_inv_responder(resp) == MTP_INV_ERR_OCUPADO, "sin sala abierta, responder se rechaza");
    comprobar(mtp_inv_unirse(resp) == MTP_INV_ERR_TIPO, "unirse con un código de respuesta: tipo");
    comprobar(mtp_inv_unirse("1234") == MTP_INV_ERR_CODIGO, "unirse con basura: código mal");
    MtpInvInfo info;
    mtp_inv_estado(&info);
    comprobar(info.estado == MTP_INV_REPOSO, "tras los rechazos no hay nada en marcha");
    comprobar(mtp_inv_crear() == MTP_INV_OK, "se crea una sala");
    comprobar(mtp_inv_crear() == MTP_INV_ERR_OCUPADO, "una segunda sala se rechaza (ocupado)");
    comprobar(mtp_inv_unirse(inv) == MTP_INV_ERR_OCUPADO, "unirse con una sala abierta: ocupado");
    comprobar(esperar_estado(MTP_INV_ESPERANDO_RESPUESTA, 8000, info), "el código de invitación queda listo");
    comprobar(std::strlen(info.codigo) == 49, "el código tiene el tamaño esperado");
    comprobar(mtp_inv_responder(inv) == MTP_INV_ERR_TIPO, "responder con una invitación: tipo");
    comprobar(mtp_inv_responder(resp) == MTP_INV_ERR_OTRA_SALA, "responder con la respuesta de otra sala: otra sala");
    mtp_inv_cancelar();
    mtp_inv_estado(&info);
    comprobar(info.estado == MTP_INV_REPOSO, "cancelar deja todo en reposo");
    comprobar(mtp_inv_crear() == MTP_INV_OK, "se puede volver a abrir sala");
    mtp_inv_cancelar();
    char args[128];
    comprobar(mtp_inv_argumentos(args, sizeof args) == 0, "sin conexión no hay argumentos");
    return g_fallos ? 1 : 0;
}

// Nombre y apodo de la prueba (variables de entorno), como los pondría la persona en el menú.
void poner_nombres_de_prueba() {
    if (const char* n = std::getenv("MTP_PRUEBA_NOMBRE")) mtp_inv_fijar_nombre_propio(n, 0);
    if (const char* a = std::getenv("MTP_PRUEBA_APODO")) mtp_inv_fijar_apodo_amigo(a);
}

int anfitrion(const std::string& f_inv, const std::string& f_resp) {
    poner_nombres_de_prueba();
    if (mtp_inv_crear() != MTP_INV_OK) return 3;
    MtpInvInfo info;
    if (!esperar_estado(MTP_INV_ESPERANDO_RESPUESTA, 15000, info)) {
        informe_final(info);
        return 4;
    }
    escribir_archivo(f_inv, info.codigo);
    const std::string resp = esperar_archivo(f_resp, 60000);
    if (resp.empty()) return 5;
    const int r = mtp_inv_responder(resp.c_str());
    if (r != MTP_INV_OK) {
        std::printf("RESPONDER %d\n", r);
        return 6;
    }
    esperar_estado(MTP_INV_CONECTADO, 60000, info);
    informe_final(info);
    return info.estado == MTP_INV_CONECTADO ? 0 : 1;
}

int invitado(const std::string& f_inv, const std::string& f_resp) {
    poner_nombres_de_prueba();
    const std::string inv = esperar_archivo(f_inv, 60000);
    if (inv.empty()) return 5;
    const int r = mtp_inv_unirse(inv.c_str());
    if (r != MTP_INV_OK) {
        std::printf("UNIRSE %d\n", r);
        return 6;
    }
    MtpInvInfo info;
    if (!esperar_estado(MTP_INV_ESPERANDO_AMIGO, 15000, info)) {
        informe_final(info);
        return 4;
    }
    escribir_archivo(f_resp, info.codigo);
    esperar_estado(MTP_INV_CONECTADO, 120000, info);
    informe_final(info);
    return info.estado == MTP_INV_CONECTADO ? 0 : 1;
}

// Anfitrión al que contesta un «invitado» que no existe: debe acabar con error de tiempo.
int fantasma(const std::string& f_inv) {
    if (mtp_inv_crear() != MTP_INV_OK) return 3;
    MtpInvInfo info;
    if (!esperar_estado(MTP_INV_ESPERANDO_RESPUESTA, 15000, info)) return 4;
    const unsigned nonce = static_cast<unsigned>(std::strtoul(std::getenv("MTP_INV_NONCE"), nullptr, 10));
    char resp[128];
    mtp_inv_prueba_codigo(1, nonce, 0x7F000001u, 9, 0x7F000001u, 9, 0, resp, sizeof resp);
    escribir_archivo(f_inv, info.codigo);
    if (mtp_inv_responder(resp) != MTP_INV_OK) return 6;
    esperar_estado(MTP_INV_CONECTADO, 60000, info);
    informe_final(info);
    return info.estado == MTP_INV_CONECTADO ? 0 : 1;
}

std::string nombre_propio() {
    char b[64];
    mtp_inv_nombre_propio(b, sizeof b);
    return b;
}

std::string contenido(const std::string& ruta) {
    std::ifstream f(ruta, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

std::string limpio(const std::string& crudo) {
    mtp_inv_fijar_nombre_propio(crudo.c_str(), 0);
    return nombre_propio();
}

int prueba_nombres(const std::string& ini) {
    std::printf("Nombres\n");
    setenv("MTP_CONFIG_INI", ini.c_str(), 1);  // el módulo lee y escribe el nombre en este config.ini
    comprobar(limpio("Matías") == "Matías", "un nombre con tilde se conserva");
    comprobar(limpio("  Ana María  ") == "Ana María", "se quitan los espacios de los extremos");
    comprobar(limpio(std::string("Mar\ta\nlo\x7f")) == "Maralo", "se quitan los caracteres de control");
    comprobar(limpio(std::string(40, 'A')) == std::string(24, 'A'), "se acorta a 24 bytes");
    std::string ene;
    for (int i = 0; i < 13; ++i) ene += "ñ";
    std::string doce;
    for (int i = 0; i < 12; ++i) doce += "ñ";
    comprobar(limpio(ene) == doce, "al acortar no se parte un carácter de dos bytes");
    comprobar(limpio("\xC3(") == "", "UTF-8 mal formado: se descarta");
    comprobar(limpio("\xC0\x80") == "", "UTF-8 sobrelargo: se descarta");
    comprobar(limpio("\xED\xA0\x80") == "", "sustituto UTF-16 en UTF-8: se descarta");
    comprobar(limpio("\xE2\x80\xAE" "abc") == "abc", "se quita el carácter que invierte el texto (U+202E)");
    comprobar(limpio("a\xE2\x80\x8B" "b") == "ab", "se quita el espacio de ancho cero (U+200B)");
    comprobar(limpio("   ") == "", "solo espacios: vacío");
    mtp_inv_fijar_nombre_propio(nullptr, 0);
    comprobar(nombre_propio().empty(), "NULL: vacío");
    mtp_inv_fijar_apodo_amigo("\xFF\xFE");
    MtpInvInfo info;
    mtp_inv_estado(&info);
    comprobar(info.nombre_amigo[0] == 0, "un apodo inválido queda vacío");
    mtp_inv_fijar_apodo_amigo("");

    // Guardado en config.ini sin tocar el resto.
    {
        std::ofstream f(ini, std::ios::binary | std::ios::trunc);
        f << "[Menu]\nLanguage = es\n\n[Online]\nStunServers = a:1 b:2\n\n[KeyMap]\nx = 1\n";
    }
    mtp_inv_fijar_nombre_propio("Matías", 1);
    std::string t = contenido(ini);
    comprobar(t.find("Nombre = Matías\n") != std::string::npos, "el nombre se guarda en [Online]");
    comprobar(t.find("StunServers = a:1 b:2\n") != std::string::npos && t.find("[KeyMap]\nx = 1\n") != std::string::npos &&
                  t.find("[Menu]\nLanguage = es\n") != std::string::npos,
              "el resto de config.ini queda igual");
    comprobar(t.find("Nombre") > t.find("[Online]") && t.find("Nombre") < t.find("[KeyMap]"), "dentro de su sección");
    mtp_inv_fijar_nombre_propio("Marta; la buena", 1);
    t = contenido(ini);
    comprobar(t.find("Nombre = Marta; la buena\n") != std::string::npos && t.find("Matías") == std::string::npos,
              "al cambiarlo se sustituye (y admite «;»)");
    std::size_t veces = 0;
    for (std::size_t i = t.find("Nombre"); i != std::string::npos; i = t.find("Nombre", i + 1)) ++veces;
    comprobar(veces == 1, "solo hay una línea Nombre");
    // Sin archivo previo se crea con su sección.
    std::remove(ini.c_str());
    mtp_inv_fijar_nombre_propio("Ana", 1);
    t = contenido(ini);
    comprobar(t == "[Online]\nNombre = Ana\n", "sin config.ini previo se crea");
    // Sin guardar, no se escribe.
    mtp_inv_fijar_nombre_propio("Otra", 0);
    comprobar(contenido(ini).find("Otra") == std::string::npos, "sin «guardar» no se escribe nada");
    return g_fallos ? 1 : 0;
}

int nombre_guardado() {
    std::printf("NOMBRE_GUARDADO [%s]\n", nombre_propio().c_str());
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    const std::string modo = argv[1];
    if (modo == "codigos") return prueba_codigos();
    if (modo == "rechazos") return prueba_rechazos();
    if (modo == "anfitrion" && argc >= 4) return anfitrion(argv[2], argv[3]);
    if (modo == "invitado" && argc >= 4) return invitado(argv[2], argv[3]);
    if (modo == "fantasma" && argc >= 3) return fantasma(argv[2]);
    if (modo == "nombres" && argc >= 3) return prueba_nombres(argv[2]);
    if (modo == "nombre_guardado") return nombre_guardado();
    return 2;
}
