#!/usr/bin/env bash
# Prueba src/partidas.cpp (importar/exportar partidas desde el menú) sin la ROM ni compilar el
# juego: compila el módulo con un programa de prueba y comprueba cada caso en una carpeta temporal.
# Uso: bash tools/pruebas/probar_partidas_menu.sh      (necesita g++ y python3)
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/prueba.cpp" <<'CPP'
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include "partidas.h"

namespace fs = std::filesystem;
static int fallos = 0;
#define COMPROBAR(cond, texto) do { if (cond) std::printf("  ok  %s\n", texto); \
    else { std::printf("  FALLA  %s\n", texto); ++fallos; } } while (0)

static std::vector<unsigned char> leer(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    return std::vector<unsigned char>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}
static void escribir(const fs::path& p, const std::vector<unsigned char>& d) {
    std::ofstream f(p, std::ios::binary | std::ios::trunc);
    f.write(reinterpret_cast<const char*>(d.data()), (std::streamsize)d.size());
}
// Una partida de prueba reconocible: 32 KiB con un patrón que no es solo 0x00/0xFF.
static std::vector<unsigned char> partida(unsigned char semilla) {
    std::vector<unsigned char> d(32768);
    for (std::size_t i = 0; i < d.size(); ++i) d[i] = (unsigned char)((i * 7 + semilla) & 0xFE);
    d[0] = 'M'; d[1] = 'T'; d[2] = semilla;
    return d;
}

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    const fs::path base = argv[1];
    fs::remove_all(base);
    fs::create_directories(base / "juego" / "roms");
    fs::create_directories(base / "otros");
    setenv("MTP_CONFIG_INI", (base / "juego" / "config.ini").string().c_str(), 1);
    const std::string rom = (base / "juego" / "roms" / "mario_tennis_power_tour_eur.gba").string();
    const fs::path sav = base / "juego" / "roms" / "mario_tennis_power_tour_eur.sav";
    MtpPartidaResultado r;
    MtpPartidaInfo info;

    std::printf("Sin partida todavía\n");
    COMPROBAR(mtp_partida_info(rom.c_str(), &info) == 0 && !info.existe, "info: no existe");
    COMPROBAR(std::string(info.ruta) == sav.string(), "info: la ruta es el .sav junto a la ROM");
    mtp_partida_exportar(rom.c_str(), (base / "otros" / "x").string().c_str(), &r);
    COMPROBAR(r.codigo == MTP_PARTIDA_ERR_SIN_PARTIDA, "exportar sin partida avisa");
    mtp_partida_copia(rom.c_str(), &r);
    COMPROBAR(r.codigo == MTP_PARTIDA_ERR_SIN_PARTIDA, "copia sin partida avisa");
    mtp_partida_importar("", (base / "otros" / "a.sav").string().c_str(), &r);
    COMPROBAR(r.codigo == MTP_PARTIDA_ERR_SIN_ROM, "sin ROM elegida no se sabe dónde");
    mtp_partida_importar(rom.c_str(), (base / "otros" / "no-existe.sav").string().c_str(), &r);
    COMPROBAR(r.codigo == MTP_PARTIDA_ERR_NO_EXISTE, "importar un archivo que no existe");

    std::printf("Importar una partida normal (32 KiB)\n");
    escribir(base / "otros" / "mgba.sav", partida(1));
    mtp_partida_comprobar((base / "otros" / "mgba.sav").string().c_str(), &r);
    COMPROBAR(r.codigo == 0 && !r.recortado && !r.completado && !r.vacia, "comprobar: válida, sin notas");
    COMPROBAR(!fs::exists(sav), "comprobar no escribe nada");
    mtp_partida_importar(rom.c_str(), (base / "otros" / "mgba.sav").string().c_str(), &r);
    COMPROBAR(r.codigo == 0 && std::string(r.copia).empty(), "importar: bien y, sin partida previa, sin copia");
    COMPROBAR(leer(sav) == partida(1), "la partida queda igual que el archivo");
    COMPROBAR(!fs::exists(fs::path(sav).concat(".nueva")), "no queda el temporal");

    std::printf("Importar sobre una partida existente: guarda copia\n");
    escribir(base / "otros" / "vba.sav", partida(2));
    mtp_partida_importar(rom.c_str(), (base / "otros" / "vba.sav").string().c_str(), &r);
    COMPROBAR(r.codigo == 0 && std::string(r.copia).size() > 0, "importar: devuelve la copia hecha");
    COMPROBAR(leer(sav) == partida(2), "la partida nueva está puesta");
    COMPROBAR(leer(r.copia) == partida(1), "la copia es la partida anterior");
    COMPROBAR(std::string(r.copia).find("antes-de-importar") != std::string::npos, "el nombre de la copia dice por qué");

    std::printf("Archivos con relleno o repetidos\n");
    {
        auto d = partida(3); d.resize(131072, 0xFF);                       // 128 KiB con 0xFF
        escribir(base / "otros" / "ff.sav", d);
        mtp_partida_comprobar((base / "otros" / "ff.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.recortado && r.bytes_origen == 131072, "128 KiB con 0xFF: se recorta");
        auto z = partida(3); z.resize(65536, 0x00);                        // 64 KiB con ceros
        escribir(base / "otros" / "cero.sav", z);
        mtp_partida_comprobar((base / "otros" / "cero.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.recortado, "64 KiB con ceros: se recorta");
        auto e = partida(3);                                               // 128 KiB repitiendo los 32 KiB
        const auto p3 = partida(3);
        for (int i = 0; i < 3; ++i) e.insert(e.end(), p3.begin(), p3.end());
        escribir(base / "otros" / "espejo.sav", e);
        mtp_partida_comprobar((base / "otros" / "espejo.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.recortado, "128 KiB repetidos: se recorta");
        mtp_partida_importar(rom.c_str(), (base / "otros" / "ff.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && leer(sav).size() == 32768 && leer(sav) == partida(3), "importar recortado: 32 KiB exactos");
    }
    std::printf("Archivos que NO se aceptan (la partida no se toca)\n");
    {
        const auto antes = leer(sav);
        auto d = partida(4); d.resize(131072, 0x55); d[70000] = 0x12;      // lo que sobra son datos
        escribir(base / "otros" / "flash.sav", d);
        mtp_partida_importar(rom.c_str(), (base / "otros" / "flash.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_OTRO_FORMATO, "128 KiB con datos distintos: se rechaza");
        escribir(base / "otros" / "vacio.sav", {});
        mtp_partida_importar(rom.c_str(), (base / "otros" / "vacio.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_VACIO, "archivo vacío: se rechaza");
        escribir(base / "otros" / "mario.ss1", partida(5));
        mtp_partida_importar(rom.c_str(), (base / "otros" / "mario.ss1").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_ESTADO_RAPIDO, "extensión .ss1 (estado rápido): se rechaza");
        escribir(base / "otros" / "estado.state", partida(5));
        mtp_partida_importar(rom.c_str(), (base / "otros" / "estado.state").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_ESTADO_RAPIDO, "extensión .state: se rechaza");
        std::vector<unsigned char> zip(200000, 0x11); zip[0] = 'P'; zip[1] = 'K';
        escribir(base / "otros" / "estado.sav", zip);
        mtp_partida_importar(rom.c_str(), (base / "otros" / "estado.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_ESTADO_RAPIDO, "cabecera ZIP con nombre .sav: se rechaza");
        std::vector<unsigned char> gordo(9u * 1024 * 1024, 0xFF);
        escribir(base / "otros" / "gordo.sav", gordo);
        mtp_partida_importar(rom.c_str(), (base / "otros" / "gordo.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == MTP_PARTIDA_ERR_DEMASIADO_GRANDE, "9 MiB: no es una partida");
        COMPROBAR(leer(sav) == antes, "tras los rechazos la partida sigue igual");
    }
    std::printf("Archivos pequeños y partidas vacías\n");
    {
        std::vector<unsigned char> peq(8192, 0x42);
        escribir(base / "otros" / "peque.sav", peq);
        mtp_partida_comprobar((base / "otros" / "peque.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.completado && r.bytes_origen == 8192, "8 KiB: se completa hasta 32 KiB");
        mtp_partida_importar(rom.c_str(), (base / "otros" / "peque.sav").string().c_str(), &r);
        const auto d = leer(sav);
        COMPROBAR(d.size() == 32768 && d[0] == 0x42 && d[8191] == 0x42 && d[8192] == 0xFF && d[32767] == 0xFF,
                  "lo que falta se rellena con 0xFF");
        escribir(base / "otros" / "blanco.sav", std::vector<unsigned char>(32768, 0xFF));
        mtp_partida_comprobar((base / "otros" / "blanco.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.vacia, "una SRAM en blanco se marca como vacía");
        escribir(base / "otros" / "ceros.sav", std::vector<unsigned char>(32768, 0x00));
        mtp_partida_comprobar((base / "otros" / "ceros.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && r.vacia, "una SRAM de ceros se marca como vacía");
    }
    std::printf("Exportar\n");
    {
        escribir(sav, partida(6));
        const fs::path dest = base / "otros" / "Mario Tennis - Power Tour (Europe)";
        mtp_partida_exportar(rom.c_str(), dest.string().c_str(), &r);
        COMPROBAR(r.codigo == 0, "exportar: bien");
        COMPROBAR(fs::exists(fs::path(dest).concat(".sav")), "sin extensión se añade .sav");
        COMPROBAR(leer(fs::path(dest).concat(".sav")) == partida(6), "lo exportado es la partida");
        COMPROBAR(std::string(r.copia) == fs::path(dest).concat(".sav").string(), "dice dónde ha quedado");
        // El archivo del juego con relleno de más: se exporta recortado a 32 KiB.
        auto d = partida(7); d.resize(131072, 0xFF); escribir(sav, d);
        mtp_partida_exportar(rom.c_str(), (base / "otros" / "rec.srm").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && leer(base / "otros" / "rec.srm").size() == 32768, "con relleno de más se exportan 32 KiB (y se respeta .srm)");
        mtp_partida_exportar(rom.c_str(), (base / "no existe" / "sub" / "p.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && fs::exists(base / "no existe" / "sub" / "p.sav"), "crea las carpetas que falten");
    }
    std::printf("Copias de seguridad\n");
    {
        escribir(sav, partida(8));
        mtp_partida_copia(rom.c_str(), &r);
        COMPROBAR(r.codigo == 0 && leer(r.copia) == partida(8), "copia manual: igual que la partida");
        COMPROBAR(std::string(r.copia).find("manual") != std::string::npos, "el nombre dice «manual»");
        const std::string copia_manual = r.copia;
        std::vector<MtpCopia> lista(100);
        const int n = mtp_partida_copias(lista.data(), 100);
        COMPROBAR(n >= 3, "se listan las copias hechas");
        bool esta = false;
        for (int i = 0; i < n; ++i) if (copia_manual == lista[i].ruta) esta = true;
        COMPROBAR(esta, "la copia manual está en la lista");
        COMPROBAR(mtp_partida_copias(lista.data(), 1) == 1, "el máximo se respeta");
        escribir(sav, partida(9));
        mtp_partida_restaurar(rom.c_str(), copia_manual.c_str(), &r);
        COMPROBAR(r.codigo == 0 && leer(sav) == partida(8), "restaurar vuelve a la copia");
        COMPROBAR(std::string(r.copia).find("antes-de-restaurar") != std::string::npos && leer(r.copia) == partida(9),
                  "restaurar guarda antes la partida que había");
        COMPROBAR(std::string(mtp_partida_carpeta_copias()) == (base / "juego" / "copias-de-partidas").string(),
                  "la carpeta de copias está junto a config.ini");
    }
    std::printf("Rutas con acentos y espacios\n");
    {
        const fs::path raro = base / "Música y pelis ñ" / "roms";
        fs::create_directories(raro);
        const std::string rom2 = (raro / "mi rom.gba").string();
        escribir(base / "otros" / "acentos.sav", partida(10));
        mtp_partida_importar(rom2.c_str(), (base / "otros" / "acentos.sav").string().c_str(), &r);
        COMPROBAR(r.codigo == 0 && leer(raro / "mi rom.sav") == partida(10), "ruta con acentos y espacios");
    }
    std::printf(fallos ? "\n%d comprobaciones fallaron\n" : "\nTodo bien\n", fallos);
    return fallos ? 1 : 0;
}
CPP

for std in c++17 c++20; do
    echo "== compilando con -std=$std"
    g++ -std=$std -O1 -Wall -Wextra -Werror -I"$raiz/src" "$tmp/prueba.cpp" "$raiz/src/partidas.cpp" -o "$tmp/prueba_$std"
    "$tmp/prueba_$std" "$tmp/obra_$std"
done
echo "Pruebas de partidas del menú: todo bien"
