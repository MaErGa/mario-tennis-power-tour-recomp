cmake_minimum_required(VERSION 3.20)
project(MarioTennisPowerTourRecomp VERSION 0.0.1 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ─────────────────────────────────────────────────────────────────────
# Recompilación estática de Mario Tennis: Power Tour (GBA, Europa) con
# el framework gbarecomp. Este proyecto solo aporta la configuración del
# juego (game.toml) y un anfitrión mínimo (src/main.cpp).
#
# Dos objetivos útiles:
#   gba_recompile                 -> el recompilador (ROM -> C++)
#   MarioTennisPowerTourRecomp    -> el juego; solo existe si ya has
#                                    generado el código (tools/construir.sh)
# ─────────────────────────────────────────────────────────────────────

set(GBARECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/externo/gbarecomp"
    CACHE PATH "Ruta al checkout de gbarecomp (el framework)")

set(MTP_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated"
    CACHE PATH "Carpeta con el C++ generado por gba_recompile")

set(MTP_SHARD_OPT "-O1;-foptimize-sibling-calls"
    CACHE STRING "Optimización de los trozos recompilados (p. ej. -O0 para compilar rápido al probar)")

set(MTP_DEBUG_PORT 19900
    CACHE STRING "Puerto TCP del servidor de depuración del runtime")

# Menú de configuración (Dear ImGui, vía recomp-ui): menú previo al arranque
# (elegir y verificar ROM/BIOS, mando, teclado, vídeo, audio) y menú dentro del
# juego. Necesita SDL2 y OpenGL. Se puede apagar con -DMTP_MENU=OFF.
option(MTP_MENU "Compilar el menú de configuración (recomp-ui)" ON)
# Idioma de los textos del menú por defecto: "es" (español) o "en". Las
# traducciones están en parches/recomp-ui-0001-*.patch. La persona lo cambia
# desde los ajustes ("Idioma del menú", parche recomp-ui-0002) y se guarda en
# config.ini, [Menu] Language; eso manda sobre este valor. Para forzarlo sin
# recompilar (pruebas): variable de entorno MTP_IDIOMA_MENU=en (o es).
set(MTP_IDIOMA_MENU "es" CACHE STRING "Idioma del menú de configuración: es o en")
# Versión instalada (la del archivo VERSION): el menú de arranque la compara con la del
# repositorio para avisar de que hay una nueva (src/aviso_actualizacion.cpp).
set(MTP_VERSION_TXT "")
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" MTP_VERSION_TXT)
    string(STRIP "${MTP_VERSION_TXT}" MTP_VERSION_TXT)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
endif()
# Dirección del archivo VERSION del repositorio, de donde el menú saca la versión más reciente.
# Si tu repositorio se llama de otra manera, cámbiala aquí (-DMTP_URL_VERSION=...) o, ya
# instalado, con «UpdateUrl = ...» en la sección [Menu] de config.ini. Para no comprobar
# nada: «CheckUpdates = 0» en [Menu], o -DMTP_URL_VERSION= (vacío).
set(MTP_URL_VERSION "https://raw.githubusercontent.com/MaErGa/MarioTennisPowerTourRecomp/main/VERSION"
    CACHE STRING "Dirección (https) del archivo VERSION para el aviso de versión nueva")
set(RECOMP_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/externo/recomp-ui"
    CACHE PATH "Ruta al checkout de recomp-ui (el menú)")

# Juego en red: el cable link de la GBA por red (por IP directa), con rollback. Lo trae el
# framework con recomp-net y rbengine (submódulos que descarga tools/construir.sh). Se maneja con
# la pantalla «En línea» del menú de arranque (código de invitación, SIN servidor: src/invitacion.cpp)
# o con --netplay-bind/-peer/-seat/-session. A propósito NO se enlaza la pestaña «Netplay» del
# framework (gbarecomp_target_netplay_launcher): usa un servidor de salas de terceros.
# Necesita el menú. Si falta algo se desactiva solo y el juego se compila como antes.
# Apagar: -DMTP_NETPLAY=OFF.
option(MTP_NETPLAY "Compilar el juego en red (cable link por red; experimental, necesita el parche gbarecomp-0009)" ON)
if(MTP_NETPLAY)
    if(NOT MTP_MENU OR
       NOT EXISTS "${GBARECOMP_ROOT}/external/recomp-net/CMakeLists.txt" OR
       NOT EXISTS "${GBARECOMP_ROOT}/external/rbengine/CMakeLists.txt")
        message(STATUS "MTP: falta el menú, recomp-net o rbengine: se compila SIN juego en red.")
        set(MTP_NETPLAY OFF)
    else()
        set(GBARECOMP_NETPLAY ON CACHE BOOL "Juego en red del framework" FORCE)
    endif()
endif()

# La BIOS libre recompilada (tools/construir.sh) se queda aquí, fuera del
# checkout del framework.
# Hay que fijarla ANTES de add_subdirectory para que gbarecomp la enlace.
set(GBARECOMP_GENERATED_BIOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated_bios"
    CACHE PATH "Carpeta con la BIOS recompilada localmente")

if(NOT EXISTS "${GBARECOMP_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "GBARECOMP_ROOT no apunta a un checkout de gbarecomp:\n"
        "  ${GBARECOMP_ROOT}\n"
        "Ejecuta tools/construir.sh (o CONSTRUIR.bat), que lo descarga,\n"
        "o pásale -DGBARECOMP_ROOT=<ruta> a CMake.")
endif()

if(MTP_MENU)
    if(NOT EXISTS "${RECOMP_UI_ROOT}/recomp_ui.cmake")
        message(FATAL_ERROR
            "MTP_MENU está activado pero no hay recomp-ui en:\n"
            "  ${RECOMP_UI_ROOT}\n"
            "Ejecuta tools/construir.sh (lo descarga), pásale -DRECOMP_UI_ROOT=<ruta>\n"
            "o desactiva el menú con -DMTP_MENU=OFF.")
    endif()
    # Le dice al runtime de gbarecomp dónde está recomp-ui para compilar el
    # menú que se abre DENTRO del juego. Ha de fijarse antes de add_subdirectory.
    set(GBARECOMP_RUNTIME_UI_ROOT "${RECOMP_UI_ROOT}"
        CACHE PATH "recomp-ui usado por el menú en juego del runtime")
endif()

# Reserva de pila del anfitrión en Windows: 256 MiB. El corpus recompilado es
# grande y la tabla de desenrollado SEH crece con el número de funciones. Hay que
# fijarla ANTES de add_subdirectory: el framework añade su propio --stack (16 MiB
# por defecto) y, al haber dos, gana el último.
set(GBARECOMP_HOST_STACK_RESERVE_BYTES "268435456" CACHE STRING
    "Reserva de pila del ejecutable en Windows (bytes)")

add_subdirectory("${GBARECOMP_ROOT}" gbarecomp_build EXCLUDE_FROM_ALL)

if(NOT EXISTS "${GBARECOMP_GENERATED_BIOS_DIR}/bios_recompiled.cpp")
    message(WARNING
        "MTP: no hay BIOS recompilada en ${GBARECOMP_GENERATED_BIOS_DIR}. "
        "El juego compilará, pero se detendrá en la primera interrupción. "
        "Ejecuta tools/construir.sh, que la genera a partir de bios_libre/.")
endif()

# ── El juego (solo si ya existe el código generado) ──────────────────
file(GLOB MTP_GENERATED CONFIGURE_DEPENDS
    "${MTP_GENERATED_DIR}/*.c"
    "${MTP_GENERATED_DIR}/*.cpp")

if(NOT MTP_GENERATED)
    message(STATUS
        "MTP: no hay código generado en ${MTP_GENERATED_DIR}. "
        "Solo se puede construir el objetivo gba_recompile; "
        "ejecuta tools/construir.sh y vuelve a configurar.")
    return()
endif()

if(EXISTS "${MTP_GENERATED_DIR}/recompiled.cpp")
    message(FATAL_ERROR
        "Hay un recompiled.cpp monolítico obsoleto en ${MTP_GENERATED_DIR}. "
        "Vuelve a generar con el gba_recompile actual.")
endif()

add_executable(MarioTennisPowerTourRecomp
    src/main.cpp
    ${MTP_GENERATED})

if(MTP_MENU)
    target_sources(MarioTennisPowerTourRecomp PRIVATE src/aviso_actualizacion.cpp src/partidas.cpp
                   src/invitacion.cpp)
    target_compile_definitions(MarioTennisPowerTourRecomp PRIVATE
        "MTP_VERSION=\"${MTP_VERSION_TXT}\""
        "MTP_URL_VERSION_DEFECTO=\"${MTP_URL_VERSION}\"")
    if(WIN32)
        target_link_libraries(MarioTennisPowerTourRecomp PRIVATE winhttp ws2_32)
    endif()
endif()

# Los trozos recompilados son enormes: limitamos optimización y depuración.
set(MTP_RECOMPILED ${MTP_GENERATED})
list(FILTER MTP_RECOMPILED INCLUDE REGEX "/recompiled_[0-9]+\\.cpp$")
if(MTP_RECOMPILED AND NOT MSVC)
    set_source_files_properties(${MTP_RECOMPILED} PROPERTIES
        COMPILE_OPTIONS "${MTP_SHARD_OPT};-g0")
endif()

target_include_directories(MarioTennisPowerTourRecomp PRIVATE
    "${GBARECOMP_ROOT}/src/armv4t"
    "${GBARECOMP_ROOT}/src/gba"
    "${GBARECOMP_ROOT}/src/runtime"
    "${GBARECOMP_ROOT}/src/debug"
    "${MTP_GENERATED_DIR}"
    src)

# La identidad del cartucho (nombre, SHA-1, CRC32, región) está en src/main.cpp.
target_compile_definitions(MarioTennisPowerTourRecomp PRIVATE
    "GBARECOMP_DEFAULT_DEBUG_PORT=${MTP_DEBUG_PORT}"
    "GBARECOMP_WINDOW_TITLE=\"Mario Tennis: Power Tour (recomp)\""
    "GBARECOMP_DEFAULT_GAME_CONFIG=\"game.toml\"")

# ── Menú de configuración (recomp-ui) ────────────────────────────────
# Va en su propia biblioteca estática para que las fuentes de recomp-ui y la
# definición RECOMP_LAUNCHER no toquen nunca las banderas del código generado.
# Solo main.cpp (con GBAGAME_RECOMP_UI) y game_launcher_boot.cpp saben que existe.
set(MTP_MENU_LIBS "")
if(MTP_MENU)
    include("${RECOMP_UI_ROOT}/recomp_ui.cmake")
    add_library(game_launcher_ui STATIC src/game_launcher_boot.cpp)
    target_include_directories(game_launcher_ui PRIVATE
        "${GBARECOMP_ROOT}/src/runtime"   # launcher_seam.h y runtime.h
        "${GBARECOMP_ROOT}/src/gba"
        src)
    # CONSOLE gba: solo se incluyen los recursos (mando, fuentes) de GBA.
    recomp_target_launcher_ui(game_launcher_ui CONSOLE gba)
    recomp_target_launcher_language(game_launcher_ui "${MTP_IDIOMA_MENU}")
    # El menú muestra el aviso de versión nueva que da src/aviso_actualizacion.cpp.
    target_compile_definitions(game_launcher_ui PRIVATE MTP_EXTRAS_MENU=1)
    set_target_properties(game_launcher_ui PROPERTIES POSITION_INDEPENDENT_CODE ON)
    if(NOT TARGET SDL2::SDL2)
        find_package(SDL2 REQUIRED)
    endif()
    target_link_libraries(game_launcher_ui PUBLIC SDL2::SDL2)
    if(WIN32)
        target_link_libraries(game_launcher_ui PUBLIC opengl32)
    endif()
    set_property(SOURCE src/main.cpp APPEND PROPERTY
        COMPILE_DEFINITIONS GBAGAME_RECOMP_UI)
    set(MTP_MENU_LIBS game_launcher_ui)
    if(MTP_NETPLAY)
        list(APPEND MTP_MENU_LIBS gbarecomp_netplay)
        # Identidad exacta de esta compilación (fuentes del framework, de este proyecto, del
        # código generado y de la red): dos jugadores solo se conectan si es la misma.
        gbarecomp_target_netplay_identity(MarioTennisPowerTourRecomp
            "${CMAKE_CURRENT_SOURCE_DIR}" "${MTP_GENERATED_DIR}")
        target_compile_definitions(MarioTennisPowerTourRecomp PRIVATE MTP_NETPLAY=1)
    endif()
endif()

# Las bibliotecas del runtime se necesitan unas a otras: el enlazador GNU
# requiere un grupo explícito; la función del framework ya lo resuelve y
# admite bibliotecas extra dentro del grupo (aquí, el menú).
if(COMMAND target_link_gbarecomp_runtime_stack)
    target_link_gbarecomp_runtime_stack(MarioTennisPowerTourRecomp ${MTP_MENU_LIBS})
else()
    target_link_libraries(MarioTennisPowerTourRecomp PRIVATE
        "-Wl,--start-group"
        ${MTP_MENU_LIBS}
        gbarecomp_runtime gbarecomp_debug gbarecomp_gba gbarecomp_armv4t
        "-Wl,--end-group")
endif()

# En Windows (MSYS2) copia junto al .exe las DLL que necesita (SDL2 y runtime).
if(COMMAND gbarecomp_stage_mingw_runtime)
    gbarecomp_stage_mingw_runtime(MarioTennisPowerTourRecomp)
endif()

# (La reserva de pila de 256 MiB en Windows se fija arriba, con la variable del
# framework GBARECOMP_HOST_STACK_RESERVE_BYTES.)
