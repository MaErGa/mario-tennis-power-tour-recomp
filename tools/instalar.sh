#!/usr/bin/env bash
# instalar.sh — instala Mario Tennis: Power Tour (versión nativa para PC) en Linux.
#
#   bash tools/instalar.sh                       # te pregunta lo que haga falta
#   bash tools/instalar.sh --rom ~/roms/mtpt.gba --destino ~/Juegos/MarioTennis --silencioso
#
# Hace, por orden:
#   1. comprueba que tienes las herramientas de compilación (y, si faltan, te ofrece instalarlas);
#   2. busca y verifica tu ROM (la europea de Mario Tennis: Power Tour; no se incluye en el proyecto);
#   3. compila el juego en una carpeta temporal (tools/construir.sh: BIOS libre + tu ROM recompilada);
#   4. lo copia a la carpeta que elijas (por defecto ~/.local/share/MarioTennisPowerTour);
#   5. crea la entrada del menú de aplicaciones (y, si quieres, un acceso en el escritorio) y un
#      desinstalar.sh junto al juego;
#   6. borra lo temporal (salvo --conservar-obra, que hace las actualizaciones mucho más rápidas).
#
# Opciones:
#   --rom RUTA              tu ROM (si no, se busca sola o te la pide)
#   --destino CARPETA       dónde instalar (si ya hay una instalación, se actualiza conservando tus partidas)
#   --escritorio            crea además un acceso en el Escritorio
#   --sin-accesos           no crea ninguna entrada de menú ni acceso directo
#   --conservar-obra        no borra los archivos de compilación (≈ 700 MB) para actualizar más rápido
#   --instalar-dependencias instala sin preguntar los paquetes que falten (usa sudo)
#   --silencioso, -y        no hace preguntas (usa los valores por defecto o los que pases)
#   --obra CARPETA          carpeta temporal de compilación (por defecto ~/.cache/MarioTennisPowerTour-obra)
#   --juego-prueba CARPETA  solo para pruebas: no compila, usa esa carpeta «juego» ya hecha
#   --ayuda, -h             esta ayuda
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=comun.sh
source "$RAIZ/tools/comun.sh"

# Espacio que hace falta (MiB): la obra (fuentes, código generado, objetos) y la instalación.
ESPACIO_OBRA_MIB=2048
ESPACIO_DESTINO_MIB=300

# ── Dependencias ───────────────────────────────────────────────────────────
herramientas_que_faltan() {
    local h
    FALTAN=()
    for h in git cmake python3 ninja; do
        tiene_herramienta "$h" || FALTAN+=("$h")
    done
    if ! tiene_herramienta g++ && ! tiene_herramienta clang++; then FALTAN+=("compilador de C++"); fi
    if ! { { tiene_herramienta pkg-config && pkg-config --exists sdl2 2>/dev/null; } \
           || tiene_herramienta sdl2-config \
           || compgen -G '/usr/lib*/cmake/SDL2/sdl2-config.cmake' >/dev/null \
           || compgen -G '/usr/lib/*/cmake/SDL2/sdl2-config.cmake' >/dev/null \
           || compgen -G '/usr/local/lib*/cmake/SDL2/sdl2-config.cmake' >/dev/null; } \
       || case " ${MTP_PRUEBA_SIN:-} " in *" sdl2 "*) true ;; *) false ;; esac; then
        FALTAN+=("SDL2 (cabeceras de desarrollo)")
    fi
}

gestor_de_paquetes() {
    local g
    for g in apt-get dnf pacman zypper; do
        if command -v "$g" >/dev/null 2>&1; then printf '%s' "$g"; return 0; fi
    done
    return 1
}

paquetes_para() {
    case "$1" in
        apt-get) printf '%s' "build-essential cmake git ninja-build libsdl2-dev python3 pkg-config" ;;
        dnf)     printf '%s' "gcc-c++ make cmake git ninja-build SDL2-devel python3 pkgconf-pkg-config" ;;
        pacman)  printf '%s' "base-devel cmake git ninja sdl2 python" ;;
        zypper)  printf '%s' "gcc-c++ make cmake git ninja SDL2-devel python3 pkg-config" ;;
    esac
}

orden_de_instalacion() { # gestor → la orden (sin sudo)
    case "$1" in
        apt-get) printf '%s' "apt-get install -y $(paquetes_para apt-get)" ;;
        dnf)     printf '%s' "dnf install -y $(paquetes_para dnf)" ;;
        pacman)  printf '%s' "pacman -S --needed --noconfirm $(paquetes_para pacman)" ;;
        zypper)  printf '%s' "zypper install -y $(paquetes_para zypper)" ;;
    esac
}

asegurar_herramientas() {
    herramientas_que_faltan
    [ "${#FALTAN[@]}" -eq 0 ] && return 0

    aviso "Faltan herramientas para compilar: ${FALTAN[*]}"
    local gestor orden con_sudo=""
    if ! gestor="$(gestor_de_paquetes)"; then
        fallo "No reconozco el gestor de paquetes de tu sistema. Instala a mano: git, cmake, ninja, python3,
   un compilador de C++ (g++ o clang++) y las cabeceras de SDL2 (libsdl2-dev / SDL2-devel), y vuelve a ejecutar esto."
    fi
    orden="$(orden_de_instalacion "$gestor")"
    if [ "$(id -u)" != 0 ]; then
        if command -v sudo >/dev/null 2>&1; then con_sudo="sudo "
        else fallo "Instala esos paquetes como administrador y vuelve a ejecutar esto:
   $orden"; fi
    fi
    info "Puedo instalarlas con:  ${con_sudo}${orden}"
    if [ "${INSTALAR_DEPENDENCIAS:-0}" != 1 ]; then
        if es_interactivo; then
            preguntar_sn "¿Las instalo ahora? (te pedirá tu contraseña)" s || fallo "Sin esas herramientas no se puede compilar. Instálalas y vuelve a ejecutar esto."
        else
            fallo "Faltan herramientas. Instálalas con:
   ${con_sudo}${orden}
   (o ejecuta esto con --instalar-dependencias)"
        fi
    fi
    paso "Instalando las herramientas de compilación"
    # shellcheck disable=SC2086
    if ! ${con_sudo}${orden}; then
        if [ "$gestor" = apt-get ]; then
            info "Actualizo la lista de paquetes y lo intento otra vez..."
            ${con_sudo}apt-get update
            # shellcheck disable=SC2086
            ${con_sudo}${orden} || fallo "No se pudieron instalar los paquetes."
        else
            fallo "No se pudieron instalar los paquetes."
        fi
    fi
    herramientas_que_faltan
    [ "${#FALTAN[@]}" -eq 0 ] || fallo "Siguen faltando: ${FALTAN[*]}"
    ok "Herramientas instaladas."
}

# ── Carpeta de trabajo (obra) ──────────────────────────────────────────────
listar_proyecto() { # carpeta → rutas relativas (./…) de los archivos del proyecto, ordenadas
    (cd "$1" && find . -type f \
        -not -path './generated/*' -not -path './generated_bios/*' -not -path './juego/*' \
        -not -path './build/*' -not -path './externo/*' -not -path './.git/*' \
        -not -path './herramientas/*' -not -path './descargas/*' -not -path './cache-zig/*' \
        -not -path '*/__pycache__/*' -not -path './roms/*' -not -name '.mtp-obra' \
        -not -name '*.gba' -not -name '*.sav' | LC_ALL=C sort)
}

# Copia el proyecto a la obra y coloca la ROM. Si la obra ya existe (de una instalación anterior que se
# conservó), solo se tocan los archivos que han cambiado y se les pone la fecha de ahora: Ninja decide
# qué recompilar comparando fechas, y un archivo nuevo con la fecha antigua del zip se ignoraría.
preparar_obra() { # obra rom
    local obra="$1" rom="$2" f lista obra_abs
    mkdir -p "$obra"
    obra_abs="$(cd "$obra" && pwd)"
    if [ "$obra_abs" != "$RAIZ" ]; then
        case "$obra_abs/" in "$RAIZ"/*|/) fallo "La carpeta de trabajo no puede estar dentro del proyecto ni ser la raíz: $obra" ;; esac
        case "$RAIZ/" in "$obra_abs"/*) fallo "La carpeta de trabajo no puede contener al proyecto: $obra" ;; esac
        # Solo se usa (y luego se borra) una carpeta vacía o que ya fue una obra de este instalador.
        if [ -n "$(ls -A "$obra" 2>/dev/null | grep -v '^\.mtp-obra$' || true)" ] && [ ! -f "$obra/.mtp-obra" ]; then
            fallo "La carpeta de trabajo $obra ya existe y no está vacía. Usa otra con --obra."
        fi
        : > "$obra/.mtp-obra"
        lista="$(mktemp)"
        listar_proyecto "$RAIZ" > "$lista"
        while IFS= read -r f; do
            if [ ! -f "$obra/$f" ] || ! cmp -s "$RAIZ/$f" "$obra/$f"; then
                mkdir -p "$(dirname "$obra/$f")"
                cp --remove-destination "$RAIZ/$f" "$obra/$f"
            fi
        done < "$lista"
        # Lo que ya no está en el proyecto (un parche retirado, por ejemplo) no se queda en la obra.
        listar_proyecto "$obra" | comm -13 "$lista" - | while IFS= read -r f; do rm -f "$obra/$f"; done
        rm -f "$lista"
    fi
    mkdir -p "$obra/roms"
    if [ ! -f "$obra/roms/$ROM_NOMBRE" ] || [ "$(tam_de "$obra/roms/$ROM_NOMBRE")" != "$ROM_TAM" ]; then
        cp --remove-destination "$rom" "$obra/roms/$ROM_NOMBRE"
        chmod u+w "$obra/roms/$ROM_NOMBRE"
    fi
}

# ── Instalación ────────────────────────────────────────────────────────────
# Copia la carpeta «juego» recién compilada a la carpeta de instalación. Solo sustituye lo que trae la
# compilación; nunca borra otras cosas, y no toca tus ajustes, partidas ni estados si ya existen.
copiar_juego() { # origen destino
    local src="$1" dst="$2" d f rel t
    mkdir -p "$dst"
    for d in assets bios_libre; do
        if [ -d "$src/$d" ]; then rm -rf "${dst:?}/$d"; cp -a "$src/$d" "$dst/$d"; fi
    done
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        case "$rel" in assets/*|bios_libre/*) continue ;; esac
        t="$dst/$rel"
        case "$rel" in
            config.ini|keybinds.ini|launcher-window.ini|rom.cfg|bios.cfg|*.sav|*.state[0-9]|roms/*.gba)
                [ -e "$t" ] && continue ;;
        esac
        mkdir -p "$(dirname "$t")"
        # --remove-destination: también se puede actualizar el ejecutable aunque esté en marcha.
        cp --remove-destination "$f" "$t"
    done < <(find "$src" -type f -print0)
    chmod +x "$dst/$EXE_JUEGO" 2>/dev/null || true
}

# El texto de Exec= de un .desktop: entre comillas y con % doblado.
texto_exec() { local t="${1//%/%%}"; printf '"%s"' "$t"; }

contenido_acceso() { # destino
    local d="$1"
    cat <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$NOMBRE_JUEGO
Comment=Native PC version (not an emulator). Unofficial project.
Comment[es]=Versión nativa para PC (no es un emulador). Proyecto no oficial.
Exec=$(texto_exec "$d/jugar.sh")
Path=$d
Terminal=false
Categories=Game;
Icon=applications-games
Keywords=mario;tennis;power tour;gba;
EOF
}

carpeta_del_escritorio() {
    local d=""
    if command -v xdg-user-dir >/dev/null 2>&1; then d="$(xdg-user-dir DESKTOP 2>/dev/null || true)"; fi
    if [ -z "$d" ] || [ "$d" = "$HOME" ]; then
        if [ -d "$HOME/Escritorio" ]; then d="$HOME/Escritorio"; else d="$HOME/Desktop"; fi
    fi
    printf '%s' "$d"
}

validar_destino() { # ruta (absoluta)
    local d="$1"
    case "$d" in *[\"\`\$\\]*|*$'\n'*|*$'\t'*)
        fallo "La carpeta no puede contener comillas, \$, \\ ni acentos graves: $d" ;; esac
    case "$d" in /|"$HOME"|"$HOME/"|/usr|/etc|/bin|/home|/opt|/var|/tmp)
        fallo "Elige una carpeta propia para el juego (no $d)." ;; esac
    local dr; dr="$(cd "$d" 2>/dev/null && pwd || printf '%s' "$d")"
    if [ "$dr" = "$RAIZ" ] || [[ "$RAIZ/" == "$dr/"* ]] || [[ "$dr/" == "$RAIZ/"* ]]; then
        fallo "La carpeta de instalación no puede ser la del proyecto, ni contenerla, ni estar dentro ($d)."
    fi
    if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ] && ! es_instalacion "$d" && ! solo_datos_de_usuario "$d"; then
        fallo "La carpeta $d ya existe, no está vacía y no es una instalación de este juego.
   Elige una carpeta nueva o vacía (al desinstalar se borra todo lo que haya dentro)."
    fi
}

escribir_manifiesto() { # destino version huella obra conservar menu escritorio
    {
        printf 'producto=%s\n' "$EXE_JUEGO"
        printf 'version=%s\n' "$2"
        printf 'huella=%s\n' "$3"
        printf 'fecha=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)"
        printf 'destino=%s\n' "$1"
        printf 'obra=%s\n' "$4"
        printf 'conservar_obra=%s\n' "$5"
        printf 'acceso_menu=%s\n' "$6"
        printf 'acceso_escritorio=%s\n' "$7"
    } > "$1/instalacion.cfg"
}

ayuda() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

principal() {
    local ROM="" DESTINO="" OBRA="" SIN_ACCESOS=0 ESCRITORIO=0 CONSERVAR=0 JUEGO_PRUEBA="" ACTUALIZANDO=0
    SILENCIOSO=0; INSTALAR_DEPENDENCIAS=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --rom)                    ROM="${2:?Falta la ruta de la ROM}"; shift ;;
            --destino)                DESTINO="${2:?Falta la carpeta de destino}"; shift ;;
            --obra)                   OBRA="${2:?Falta la carpeta de trabajo}"; shift ;;
            --escritorio)             ESCRITORIO=1 ;;
            --sin-accesos)            SIN_ACCESOS=1 ;;
            --conservar-obra)         CONSERVAR=1 ;;
            --instalar-dependencias)  INSTALAR_DEPENDENCIAS=1 ;;
            --silencioso|-y)          SILENCIOSO=1 ;;
            --juego-prueba)           JUEGO_PRUEBA="${2:?Falta la carpeta del juego de prueba}"; shift ;;
            --actualizando)           ACTUALIZANDO=1 ;;
            --ayuda|-h|--help)        ayuda; return 0 ;;
            *) fallo "Opción desconocida: $1 (mira --ayuda)" ;;
        esac
        shift
    done

    printf '\n  %s - instalador para Linux\n' "$NOMBRE_JUEGO"
    printf '  Versión nativa para PC (no es un emulador). Proyecto no oficial.\n'

    # 1. Herramientas
    if [ -z "$JUEGO_PRUEBA" ]; then
        paso "Comprobando las herramientas de compilación"
        asegurar_herramientas
        ok "git, cmake, ninja, python3, compilador de C++ y SDL2."
    fi

    # 2. La ROM
    if [ -z "$JUEGO_PRUEBA" ]; then
        paso "Tu ROM"
        if [ -z "$ROM" ]; then
            if ROM="$(buscar_rom "$RAIZ/roms")"; then
                ok "Encontrada: $ROM"
            elif es_interactivo; then
                while :; do
                    read -r -p "   Ruta de tu ROM europea de Mario Tennis: Power Tour (.gba): " ROM || ROM=""
                    ROM="${ROM/#\~/$HOME}"
                    [ -n "$ROM" ] || fallo "Hace falta la ROM para instalar."
                    probar_rom "$ROM" && break
                    aviso "$MENSAJE_ROM"
                done
            else
                fallo "No encuentro tu ROM. Pásala con --rom /ruta/a/tu_rom.gba"
            fi
        else
            ROM="${ROM/#\~/$HOME}"
            probar_rom "$ROM" || fallo "$MENSAJE_ROM"
        fi
        ROM="$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")"
        ok "ROM correcta (SHA-1 $ROM_SHA1)."
    fi

    # 3. Dónde se instala
    if [ -z "$DESTINO" ]; then
        DESTINO="$DESTINO_POR_DEFECTO"
        if es_interactivo && [ "$ACTUALIZANDO" != 1 ]; then
            local r
            read -r -p "   ¿En qué carpeta lo instalo? [$DESTINO] " r || r=""
            [ -n "$r" ] && DESTINO="${r/#\~/$HOME}"
        fi
    fi
    DESTINO="${DESTINO/#\~/$HOME}"
    case "$DESTINO" in /*) ;; *) DESTINO="$PWD/$DESTINO" ;; esac
    DESTINO="${DESTINO%/}"
    validar_destino "$DESTINO"
    local ya_instalado=0
    es_instalacion "$DESTINO" && ya_instalado=1
    if [ "$ya_instalado" = 1 ]; then
        info "Ya hay una instalación en $DESTINO: se actualizará (se conservan tus partidas y ajustes)."
    fi

    # 4. Accesos y obra: preguntas
    if [ "$ACTUALIZANDO" != 1 ] && [ "$SIN_ACCESOS" != 1 ] && [ "$ESCRITORIO" != 1 ]; then
        preguntar_sn "¿Creo también un acceso directo en el Escritorio? (en el menú de aplicaciones se crea siempre)" n && ESCRITORIO=1
    fi
    if [ "$ACTUALIZANDO" != 1 ] && [ "$CONSERVAR" != 1 ] && [ -z "$JUEGO_PRUEBA" ]; then
        preguntar_sn "¿Conservo los archivos de compilación (≈ 700 MB) para que actualizar sea mucho más rápido?" n && CONSERVAR=1
    fi

    # 5. Compilar (o usar el juego de prueba)
    local CARPETA_JUEGO OBRA_USADA=""
    if [ -n "$JUEGO_PRUEBA" ]; then
        es_instalacion "$JUEGO_PRUEBA" || fallo "La carpeta de prueba no tiene $EXE_JUEGO: $JUEGO_PRUEBA"
        CARPETA_JUEGO="$(cd "$JUEGO_PRUEBA" && pwd)"
        paso "Usando el juego ya compilado (prueba): $CARPETA_JUEGO"
    else
        [ -n "$OBRA" ] || OBRA="$OBRA_POR_DEFECTO"
        OBRA="${OBRA/#\~/$HOME}"
        case "$OBRA" in *" "*) OBRA="/var/tmp/MarioTennisPowerTour-obra-$(id -u)" ;; esac
        local libre_obra libre_dest
        libre_obra="$(espacio_libre_mib "$OBRA")"; libre_dest="$(espacio_libre_mib "$DESTINO")"
        if [ -n "$libre_obra" ] && [ "$libre_obra" -lt "$ESPACIO_OBRA_MIB" ]; then
            fallo "Hace falta espacio para compilar: unos $ESPACIO_OBRA_MIB MB libres en $(dirname "$OBRA") y solo hay $libre_obra MB.
   Libera espacio o usa --obra OTRA_CARPETA."
        fi
        if [ -n "$libre_dest" ] && [ "$libre_dest" -lt "$ESPACIO_DESTINO_MIB" ]; then
            fallo "Hace falta espacio para instalar: unos $ESPACIO_DESTINO_MIB MB libres en $(dirname "$DESTINO") y solo hay $libre_dest MB."
        fi
        local nucleos; nucleos="$(calcular_nucleos)"
        paso "Preparando la carpeta de trabajo ($OBRA)"
        preparar_obra "$OBRA" "$ROM"
        OBRA_USADA="$OBRA"
        paso "Compilando el juego (la primera vez tarda unos minutos; $nucleos procesos en paralelo)"
        local registro="$CACHE_BASE/MarioTennisPowerTour-instalador.log"
        mkdir -p "$CACHE_BASE"
        if ! MTP_NUCLEOS="$nucleos" bash "$OBRA/tools/construir.sh" "$OBRA/roms/$ROM_NOMBRE" 2>&1 | tee "$registro"; then
            fallo "La compilación ha fallado. El registro completo está en $registro
   (si te falta memoria, prueba con MTP_NUCLEOS=1). La carpeta de trabajo se conserva en $OBRA."
        fi
        CARPETA_JUEGO="$OBRA/juego"
        es_instalacion "$CARPETA_JUEGO" || fallo "La compilación terminó sin generar $EXE_JUEGO."
    fi

    # 6. Instalar
    paso "Instalando en $DESTINO"
    copiar_juego "$CARPETA_JUEGO" "$DESTINO"
    cp --remove-destination "$RAIZ/tools/desinstalar.sh" "$DESTINO/desinstalar.sh"
    chmod +x "$DESTINO/desinstalar.sh" "$DESTINO/jugar.sh" 2>/dev/null || true
    ok "Juego copiado."
    if command -v ldd >/dev/null 2>&1 && ldd "$DESTINO/$EXE_JUEGO" 2>/dev/null | grep -q 'not found'; then
        aviso "Al ejecutable le faltan bibliotecas del sistema:"
        ldd "$DESTINO/$EXE_JUEGO" | grep 'not found' | sed 's/^/      /'
    fi

    local acceso_menu="" acceso_escritorio=""
    if [ "$SIN_ACCESOS" != 1 ]; then
        mkdir -p "$CARPETA_ACCESOS"
        contenido_acceso "$DESTINO" > "$ARCHIVO_ACCESO"
        chmod 644 "$ARCHIVO_ACCESO"
        acceso_menu="$ARCHIVO_ACCESO"
        ok "Entrada del menú de aplicaciones: $ARCHIVO_ACCESO"
        if [ "$ESCRITORIO" = 1 ]; then
            local esc; esc="$(carpeta_del_escritorio)"
            if [ -d "$esc" ] || mkdir -p "$esc" 2>/dev/null; then
                acceso_escritorio="$esc/$NOMBRE_JUEGO.desktop"
                contenido_acceso "$DESTINO" > "$acceso_escritorio"
                chmod +x "$acceso_escritorio"
                gio set "$acceso_escritorio" metadata::trusted true >/dev/null 2>&1 || true
                ok "Acceso en el Escritorio: $acceso_escritorio"
                info "(si tu escritorio lo muestra con un candado, clic derecho → «Permitir ejecutar»)"
            else
                aviso "No pude crear el acceso del Escritorio en $esc."
            fi
        fi
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$CARPETA_ACCESOS" >/dev/null 2>&1 || true
        fi
    fi

    local conservada=0
    [ -n "$OBRA_USADA" ] && [ "$CONSERVAR" = 1 ] && conservada=1
    escribir_manifiesto "$DESTINO" "$(leer_version "$RAIZ")" "$(huella_proyecto "$RAIZ")" \
        "$OBRA_USADA" "$conservada" "$acceso_menu" "$acceso_escritorio"

    # 7. Limpiar lo temporal
    if [ -n "$OBRA_USADA" ]; then
        if [ "$CONSERVAR" = 1 ]; then
            info "Se conservan los archivos de compilación en $OBRA_USADA para actualizar más rápido."
        elif [ -f "$OBRA_USADA/.mtp-obra" ] && [ "$(cd "$OBRA_USADA" && pwd)" != "$RAIZ" ]; then
            rm -rf "${OBRA_USADA:?}"
            ok "Archivos temporales borrados."
        fi
    fi

    paso "Listo"
    info "Juego instalado en: $DESTINO"
    info "Para jugar: búscalo como «$NOMBRE_JUEGO» en el menú de aplicaciones, o ejecuta $DESTINO/jugar.sh"
    info "Para actualizar: descomprime la versión nueva y ejecuta  bash tools/actualizar.sh"
    info "Para desinstalar: $DESTINO/desinstalar.sh"
    if ! command -v zenity >/dev/null 2>&1 && ! command -v kdialog >/dev/null 2>&1; then
        info "Opcional: instala «zenity» (o «kdialog») para que el menú pueda abrir el selector de archivos"
        info "(importar/exportar partidas de emuladores)."
    fi
}

# Se puede cargar con «source» para probar las funciones sin ejecutar nada.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    principal "$@"
fi
