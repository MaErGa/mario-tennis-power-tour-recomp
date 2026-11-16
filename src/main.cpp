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
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "gba_bus.h"
#include "runtime.h"
#include "runtime_arm.h"
#include "runtime_bus_bridge.h"

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
//
// Esta comprobación se hace en CADA despacho de código de IWRAM, y leer 8 palabras
// por el puente del bus (con sus contadores y comprobaciones) llegaba a ser más de
// la mitad del tiempo de CPU de un partido. La vía rápida compara los 16 bytes
// directamente en memoria (IWRAM y ROM no tienen efectos al leerse); el puente
// queda para el caso raro de que haya una sustitución de lecturas de ROM activa.
bool ram_coincide_con_rom(const TramoIwram& t, std::uint32_t pc) {
    std::uint32_t desde = pc & ~3u;
    if (desde + 16u > t.ram + t.tam) desde = t.ram + t.tam - 16u;
    const std::uint32_t rom = t.rom + (desde - t.ram);
    const gba::GbaBus* bus = gbarecomp::active_bus();
    if (bus && gba::g_rom_read32_override == nullptr && bus->rom_ptr() != nullptr &&
        desde >= 0x03000000u && desde + 16u <= 0x03008000u &&
        rom >= 0x08000000u && (rom - 0x08000000u) + 16u <= bus->rom_size()) {
        return std::memcmp(bus->iwram_ptr() + (desde & 0x7FFFu),
                           bus->rom_ptr() + (rom - 0x08000000u), 16u) == 0;
    }
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

// ── Filtro de imagen («Texture filtering» del menú) ────────────────────────────
// Un solo selector con lo que antes eran dos filas (Nearest/Linear/Sharp) más los
// filtros de escalado y de pantalla que añade el parche 0004:
//   0 Nearest            píxeles cuadrados, sin suavizar (el original).
//   1 Linear             suavizado de la tarjeta gráfica (borroso, pero sin cuadrículas).
//   2 Sharp fractional   amplía por un número entero y suaviza solo el último ajuste:
//                        nítido incluso con tamaños de ventana no enteros.
//   3 Scale2x  4 Scale3x  5 Scale4x
//                        escaladores de pixel art (AdvMAME): redondean diagonales y
//                        curvas de sprites, fondos y TEXTO sin emborronar.
//   6 HD smooth          Scale4x con un suavizado ligero: aspecto «remasterizado».
//   7 LCD grid (GBA)     la rejilla de píxeles de la pantalla de la consola.
//   8 CRT scanlines      líneas de barrido de un monitor de tubo.
// Se combinan con «Screen» (modelo de color de la pantalla de la GBA).
const char* const kEtiquetasFiltro[] = {
    "Nearest", "Linear", "Sharp fractional", "Scale2x", "Scale3x", "Scale4x",
    "HD smooth", "LCD grid (GBA)", "CRT scanlines"};
const int kValoresFiltro[] = {0, 1, 2, 3, 4, 5, 6, 7, 8};
constexpr int kNumFiltros = static_cast<int>(sizeof(kValoresFiltro) / sizeof(kValoresFiltro[0]));

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
//   --image-filter N                ->  filtro de imagen   (GBARECOMP_FILTRO=N, 0..8)
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
        if (args[i] == "--image-filter" && i + 1 < args.size()) {
            fijar_entorno("GBARECOMP_FILTRO", args[i + 1].c_str());
            ++i;  // salta también el valor
            continue;
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
    // Imagen nítida con el escalado de Windows (125 %, 150 %...): el proceso se declara
    // consciente del DPI por monitor (SDL lo lee al iniciar el vídeo). Sin esto Windows
    // estira la ventana y difumina las líneas de 1 píxel de los filtros. Para volver al
    // comportamiento anterior: variable de entorno SDL_WINDOWS_DPI_AWARENESS=unaware.
    entorno_por_defecto("SDL_WINDOWS_DPI_AWARENESS", "permonitorv2");
    // Ruta de config.ini, la misma que usa el menú de arranque (junto al ejecutable): los
    // menús la leen y la escriben para recordar el idioma elegido ([Menu] Language).
    {
        const std::filesystem::path exe(argc > 0 && argv[0] ? argv[0] : "");
        const std::filesystem::path ini =
            exe.has_parent_path() ? exe.parent_path() / "config.ini" : std::filesystem::path("config.ini");
        entorno_por_defecto("MTP_CONFIG_INI", ini.string().c_str());
    }

    g_runtime_ram_dispatch_hook  = despacho_ram;
    g_runtime_force_interp_hook  = forzar_interprete;

    gbarecomp::RunOptions opts;
    opts.builtin_game_name = "Mario Tennis: Power Tour (Europa)";
    opts.builtin_rom_sha1  = "d61990974040d405b5bf8436ac8e1e0beb0f7964";
    opts.builtin_rom_crc32 = 0xC8DB4F60u;

    // Menú previo al arranque.
    opts.launcher_region      = "EUR";
    opts.launcher_game_config = "game.toml";
    // El selector «Filtro de imagen» (ver arriba) sustituye a la fila «Scaling filter».
    opts.launcher_expose_sharp_filter  = false;
    opts.launcher_default_sharp_filter = false;
    opts.launcher_filter_labels = kEtiquetasFiltro;
    opts.launcher_filter_values = kValoresFiltro;
    opts.launcher_num_filters   = kNumFiltros;

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
