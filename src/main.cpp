// main.cpp — anfitrión de Mario Tennis: Power Tour (GBA, Europa) para PC.
//
// Todo el trabajo pesado lo hace el framework gbarecomp: el código ARM/Thumb de
// la ROM se tradujo a C++ por adelantado y el runtime reproduce el hardware de
// la GBA. Este fichero solo aporta lo que es propio de este cartucho:
//   - su identidad (nombre, SHA-1, CRC32, región) para verificar la ROM;
//   - dos ganchos para el código que el juego ejecuta desde RAM;
//   - la conexión con el menú de configuración;
//   - los modos de pantalla (3:2 nativo, 16:9 estirado, 16:9 con barras difuminadas).
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

#include "runtime.h"
#include "runtime_arm.h"

#if defined(GBAGAME_RECOMP_UI)
#include "game_launcher_boot.h"
#endif

namespace {

// ── Código que el juego copia de la ROM a IWRAM (debe coincidir con game.toml)
struct TramoIwram {
    std::uint32_t ram;
    std::uint32_t rom;
    std::uint32_t tam;
};
constexpr TramoIwram kTramos[] = {
    {0x03000100u, 0x0800070Cu, 0x00E8u},  // IntrMain
    {0x03000220u, 0x0800082Cu, 0x0FE0u},  // rutinas del juego
    {0x03001400u, 0x080129E4u, 0x02C8u},  // descompresor
    {0x03006000u, 0x0825142Cu, 0x0400u},  // rutina en 0x03006000
};

// ¿Coinciden con la ROM los 16 bytes de RAM que empiezan en la palabra de `pc`?
// Si el juego sobrescribe ese código con otro, el despacho estático
// (recompilado de la imagen original) ya no vale y hay que interpretar.
bool ram_coincide_con_rom(const TramoIwram& t, std::uint32_t pc) {
    std::uint32_t desde = pc & ~3u;
    if (desde + 16u > t.ram + t.tam) desde = t.ram + t.tam - 16u;
    const std::uint32_t rom = t.rom + (desde - t.ram);
    for (std::uint32_t i = 0; i < 16u; i += 4u)
        if (bus_read_u32(desde + i) != bus_read_u32(rom + i)) return false;
    return true;
}

// Gancho 1 — PC desalineado en código ARM de IWRAM.
// IntrMain devuelve a veces a 0x030001C6 en modo ARM (media palabra más allá de
// la instrucción). La CPU real ignora los 2 bits bajos; aquí lo hacemos nosotros.
int despacho_ram(std::uint32_t pc, int thumb) {
    if (!thumb && (pc & 3u) != 0u && pc >= 0x03000000u && pc < 0x03008000u) {
        runtime_dispatch(pc & ~3u);
        return 1;
    }
    return 0;
}

// Gancho 2 — qué código no puede ejecutarse como código recompilado.
//   0  despacho nativo normal
//   1  intérprete: se ejecuta paso a paso el subárbol de llamadas
//   2  intérprete: se desenrolla hasta el bucle principal y sigue desde allí
int forzar_interprete(std::uint32_t pc, int thumb) {
    if (pc < 0x02000000u || pc >= 0x08000000u) return 0;

    // EWRAM: módulos de código descomprimidos al vuelo (overlays). Cambian
    // según la pantalla; el bucle principal los interpreta.
    if (pc < 0x02040000u) return 2;

    if (pc >= 0x03000000u && pc < 0x03008000u) {
        for (const TramoIwram& t : kTramos) {
            if (pc >= t.ram && pc < t.ram + t.tam)
                return ram_coincide_con_rom(t, pc) ? 0 : 1;
        }
        // Resto de IWRAM (p. ej. la zona de pila 0x03007C00..0x03007F00, donde
        // el juego copia una rutina cada fotograma): intérprete.
        return 1;
    }
    (void)thumb;
    return 0;
}

// ── Opciones de pantalla del menú («relación de aspecto») ──────────────────────
// La GBA saca 240x160 (3:2). En un monitor 16:9 hay tres maneras de presentarla:
//   0  3:2 nativo         imagen original con barras negras a los lados.
//   1  16:9 estirado      la imagen se estira a toda la ventana (se deforma un
//                         poco, pero ocupa todo el monitor).
//   2  16:9 barras        imagen 3:2 sin deformar y las barras laterales
//      difuminadas        rellenas con una copia difuminada y oscura de la propia
//                         imagen, en vez de negro.
// No se ofrece una «vista ampliada» real (dibujar más escenario a los lados): el
// juego no tiene contenido fuera de los 240 px y los márgenes salen negros.
//
// El menú del framework solo sabe pasar un «ancho de vista» por opción: los
// modos 1 y 2 los señalamos con anchos centinela (no son anchos reales) que
// main() traduce a GBARECOMP_STRETCH (ver parches/ y tools/aplicar_parches.py).
constexpr std::uint16_t kAnchoNativo    = 240;
constexpr std::uint16_t kAnchoEstirado  = 241;  // centinela -> modo 1
constexpr std::uint16_t kAnchoDifuminado = 242;  // centinela -> modo 2

const char* const kEtiquetasAspecto[] = {
    "3:2 (Native)", "16:9 (Stretched)", "16:9 (Blurred sides)"};
const std::uint16_t kAnchosAspecto[] = {
    kAnchoNativo, kAnchoEstirado, kAnchoDifuminado};

void fijar_entorno(const char* nombre, const char* valor) {
#if defined(_WIN32)
    _putenv_s(nombre, valor);
#else
    setenv(nombre, valor, 1);
#endif
}

// Traduce a ajustes del runtime lo que el menú o la línea de órdenes pidieron:
//   --view-width 241 / --stretch   ->  modo estirado   (GBARECOMP_STRETCH=1)
//   --view-width 242 / --blur-bars ->  barras difuminadas (GBARECOMP_STRETCH=2)
// y los quita de la lista para que run_game() no los vea.
void aplicar_modo_pantalla(std::vector<std::string>& args) {
    std::vector<std::string> salida;
    salida.reserve(args.size());
    for (std::size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "--view-width" && i + 1 < args.size()) {
            if (args[i + 1] == std::to_string(kAnchoEstirado)) {
                fijar_entorno("GBARECOMP_STRETCH", "1");
                ++i;  // salta también el valor
                continue;
            }
            if (args[i + 1] == std::to_string(kAnchoDifuminado)) {
                fijar_entorno("GBARECOMP_STRETCH", "2");
                ++i;
                continue;
            }
        }
        if (args[i] == "--stretch") {
            fijar_entorno("GBARECOMP_STRETCH", "1");
            continue;
        }
        if (args[i] == "--blur-bars") {
            fijar_entorno("GBARECOMP_STRETCH", "2");
            continue;
        }
        salida.push_back(args[i]);
    }
    args.swap(salida);
}

// Por defecto no se crea la carpeta de diagnósticos junto al ejecutable.
void entorno_por_defecto(const char* nombre, const char* valor) {
    if (std::getenv(nombre)) return;
#if defined(_WIN32)
    _putenv_s(nombre, valor);
#else
    setenv(nombre, valor, 0);
#endif
}

}  // namespace

int main(int argc, char** argv) {
    entorno_por_defecto("GBARECOMP_DIAGNOSTICS", "0");

    g_runtime_ram_dispatch_hook  = despacho_ram;
    g_runtime_force_interp_hook  = forzar_interprete;

    gbarecomp::RunOptions opts;
    opts.builtin_game_name = "Mario Tennis: Power Tour (Europa)";
    opts.builtin_rom_sha1  = "d61990974040d405b5bf8436ac8e1e0beb0f7964";
    opts.builtin_rom_crc32 = 0xC8DB4F60u;

    // Menú previo al arranque.
    opts.launcher_region      = "EUR";
    opts.launcher_game_config = "game.toml";
    opts.launcher_expose_sharp_filter  = true;
    opts.launcher_default_sharp_filter = false;

    // Pantalla: 3:2 nativo, 16:9 estirado y 16:9 con barras difuminadas (ver
    // arriba). Se ofrecen como un selector «aspect» en el menú de arranque.
    opts.launcher_expose_widescreen  = true;
    opts.launcher_aspect_labels      = kEtiquetasAspecto;
    opts.launcher_aspect_view_widths = kAnchosAspecto;
    opts.launcher_num_aspects        = 3;

#if defined(GBAGAME_RECOMP_UI)
    std::vector<std::string> args(argv, argv + argc);
    if (game_launcher_preboot(args, opts)) return 0;  // la persona salió del menú
    aplicar_modo_pantalla(args);
    std::vector<char*> av;
    av.reserve(args.size() + 1);
    for (std::string& s : args) av.push_back(s.data());
    av.push_back(nullptr);
    return gbarecomp::run_game(static_cast<int>(args.size()), av.data(), opts);
#else
    std::vector<std::string> args(argv, argv + argc);
    aplicar_modo_pantalla(args);
    std::vector<char*> av;
    av.reserve(args.size() + 1);
    for (std::string& s : args) av.push_back(s.data());
    av.push_back(nullptr);
    return gbarecomp::run_game(static_cast<int>(args.size()), av.data(), opts);
#endif
}
