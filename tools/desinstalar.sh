#!/usr/bin/env bash
# desinstalar.sh — quita Mario Tennis: Power Tour de este equipo (Linux).
#
#   ./desinstalar.sh                    # te pregunta si conservar tus partidas y ajustes
#   ./desinstalar.sh --silencioso       # sin preguntas: conserva tus partidas y ajustes
#   ./desinstalar.sh --borrar-todo      # sin conservar nada (con --silencioso, sin preguntar)
#
# Se instala junto al juego y funciona aunque ya no tengas el proyecto. Quita la entrada del menú de
# aplicaciones y el acceso del Escritorio, la carpeta de trabajo que se hubiera conservado, y el juego.
# Tu ROM original no se toca (solo se borra la copia que hay dentro de la carpeta del juego).
# «Conservar» deja en la carpeta del juego: config.ini, keybinds.ini, launcher-window.ini, rom.cfg,
# bios.cfg, las partidas (.sav), los estados (.state1…9 y sus nombres .info), las capturas y las copias de partidas.
set -euo pipefail

principal() {
    local EXE="MarioTennisPowerTourRecomp" destino="" silencioso=0 modo="" r
    while [ $# -gt 0 ]; do
        case "$1" in
            --destino)             destino="${2:?Falta la carpeta del juego}"; shift ;;
            --silencioso|-y)       silencioso=1 ;;
            --conservar-partidas)  modo="conservar" ;;
            --borrar-todo)         modo="borrar" ;;
            --ayuda|-h|--help)     sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; return 0 ;;
            *) echo "Opción desconocida: $1" >&2; return 1 ;;
        esac
        shift
    done
    if [ -z "$destino" ]; then destino="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"; fi
    destino="$(cd "$destino" 2>/dev/null && pwd)" || { echo "ERROR: no existe la carpeta $destino" >&2; return 1; }

    # Seguridad: solo se borra una carpeta que sea de verdad una instalación de este juego.
    local cfg="$destino/instalacion.cfg"
    if [ ! -f "$destino/$EXE" ] || [ ! -f "$cfg" ] || ! grep -qx "producto=$EXE" "$cfg"; then
        echo "ERROR: $destino no parece una instalación de Mario Tennis: Power Tour (falta el juego o instalacion.cfg). No borro nada." >&2
        return 1
    fi
    case "$destino" in /|"$HOME"|/usr|/etc|/bin|/home|/opt|/var|/tmp) echo "ERROR: ruta no permitida: $destino" >&2; return 1 ;; esac

    local acceso_menu acceso_escritorio obra
    acceso_menu="$(sed -n 's/^acceso_menu=//p' "$cfg" | head -1)"
    acceso_escritorio="$(sed -n 's/^acceso_escritorio=//p' "$cfg" | head -1)"
    obra="$(sed -n 's/^obra=//p' "$cfg" | head -1)"

    echo
    echo "  Mario Tennis: Power Tour - desinstalador"
    echo "  Carpeta del juego: $destino"
    if [ "$silencioso" != 1 ] && [ -t 0 ]; then
        read -r -p "   ¿Desinstalar? [s/N] " r || r=""
        case "${r,,}" in s|si|sí|y|yes) ;; *) echo "   Cancelado."; return 0 ;; esac
        if [ -z "$modo" ]; then
            read -r -p "   ¿Conservo tus partidas, estados, capturas y ajustes? [S/n] " r || r=""
            case "${r,,}" in n|no) modo="borrar" ;; *) modo="conservar" ;; esac
        fi
    fi
    [ -n "$modo" ] || modo="conservar"

    # Accesos (solo los que apuntan a esta instalación).
    local a
    for a in "$acceso_menu" "$acceso_escritorio"; do
        [ -n "$a" ] && [ -f "$a" ] || continue
        if grep -qxF "Path=$destino" "$a"; then rm -f "$a"; echo "   [OK] Quitado: $a"; fi
    done
    if command -v update-desktop-database >/dev/null 2>&1 && [ -n "$acceso_menu" ]; then
        update-desktop-database "$(dirname "$acceso_menu")" >/dev/null 2>&1 || true
    fi

    # Carpeta de trabajo conservada (solo si la creó el instalador).
    if [ -n "$obra" ] && [ -f "$obra/.mtp-obra" ]; then
        rm -rf "${obra:?}"; echo "   [OK] Borrada la carpeta de trabajo: $obra"
    fi

    # El juego.
    if [ "$modo" = "borrar" ]; then
        rm -rf "${destino:?}"
        echo "   [OK] Borrado todo: $destino"
    else
        find "$destino" -mindepth 1 \
            \( -path "$destino/capturas" -o -path "$destino/capturas/*" \
               -o -path "$destino/copias-de-partidas" -o -path "$destino/copias-de-partidas/*" \
               -o -path "$destino/config.ini" -o -path "$destino/keybinds.ini" -o -path "$destino/launcher-window.ini" \
               -o -path "$destino/rom.cfg" -o -path "$destino/bios.cfg" \
               -o -path "$destino/roms/*.sav" -o -path "$destino/roms/*.state[0-9]" \
               -o -path "$destino/roms/*.state[0-9].info" \) -prune \
            -o \( -type f -o -type l \) -exec rm -f {} +
        find "$destino" -mindepth 1 -depth -type d -empty -delete 2>/dev/null || true
        echo "   [OK] Juego borrado. Se han conservado tus partidas, estados, capturas y ajustes en $destino"
        echo "        (bórralos a mano si ya no los quieres)."
    fi
    echo "   Hecho. Tu ROM original no se ha tocado."
}

principal "$@"
exit $?
