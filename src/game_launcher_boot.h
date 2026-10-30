// game_launcher_boot.h — puente entre main.cpp y el menú previo al arranque.
//
// El menú (recomp-ui + Dear ImGui) vive en una biblioteca estática aparte para
// que sus fuentes y sus definiciones no toquen nunca las banderas de
// compilación del código recompilado. main.cpp solo conoce esta función.
#pragma once

#include <string>
#include <vector>

#include "runtime.h"

// Abre el menú de arranque (verificar ROM, mando, teclado, vídeo, audio).
// Devuelve 1 si la persona ha salido sin jugar (main debe terminar con 0) y 0
// para continuar con run_game(); en ese caso `args` ya lleva los ajustes
// elegidos como argumentos de línea de órdenes normales.
int game_launcher_preboot(std::vector<std::string>& args,
                          const gbarecomp::RunOptions& opts);
