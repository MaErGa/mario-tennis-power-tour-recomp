// game_launcher_boot.cpp — único sitio donde se incluye el «seam» del menú.
//
// Se compila dentro de la biblioteca game_launcher_ui, que recibe las
// definiciones y cabeceras de recomp-ui (RECOMP_LAUNCHER, ImGui, SDL).
#include "game_launcher_boot.h"

#include "launcher_seam.h"

int game_launcher_preboot(std::vector<std::string>& args,
                          const gbarecomp::RunOptions& opts) {
    return gbarecomp_launcher_preboot(args, opts);
}
