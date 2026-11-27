#!/usr/bin/env bash
# actualizar.sh — actualiza Mario Tennis: Power Tour (Linux) sin instalarlo todo desde cero.
#
# Úsalo cuando te llegue una versión nueva del proyecto (un zip nuevo): descomprímelo y, dentro de
# esa carpeta, ejecuta  bash tools/actualizar.sh . Hace por ti lo que en una instalación tendrías que elegir:
#   1. encuentra solo dónde está instalado el juego (la entrada del menú de aplicaciones o la carpeta
#      por defecto; si no lo encuentra, usa --destino);
#   2. mira si la versión nueva trae algo distinto de la que tienes (si no, no hace nada);
#   3. reutiliza la ROM que ya está en la carpeta del juego (no te la vuelve a pedir);
#   4. lo vuelve a compilar y lo copia encima conservando tus partidas, ajustes, capturas y accesos.
# Si al instalar elegiste conservar los archivos de compilación, solo recompila lo que ha cambiado.
#
# Opciones:
#   --destino CARPETA       carpeta donde está instalado el juego (si no, se busca sola)
#   --rom RUTA              ROM europea, solo si no está ya en la carpeta del juego
#   --forzar                actualiza aunque la versión nueva sea idéntica a la instalada (para reparar)
#   --conservar-obra        conserva los archivos de compilación al terminar
#   --instalar-dependencias instala sin preguntar los paquetes que falten (usa sudo)
#   --silencioso, -y        no hace preguntas
#   --juego-prueba CARPETA  solo para pruebas: no compila, usa esa carpeta «juego» ya hecha
#   --ayuda, -h             esta ayuda
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=comun.sh
source "$RAIZ/tools/comun.sh"

principal() {
    local DESTINO="" ROM="" FORZAR=0 CONSERVAR=0 JUEGO_PRUEBA="" extra=()
    SILENCIOSO=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --destino)                DESTINO="${2:?Falta la carpeta}"; shift ;;
            --rom)                    ROM="${2:?Falta la ruta de la ROM}"; shift ;;
            --forzar)                 FORZAR=1 ;;
            --conservar-obra)         CONSERVAR=1 ;;
            --instalar-dependencias)  extra+=(--instalar-dependencias) ;;
            --silencioso|-y)          SILENCIOSO=1; extra+=(--silencioso) ;;
            --juego-prueba)           JUEGO_PRUEBA="${2:?Falta la carpeta}"; shift ;;
            --ayuda|-h|--help)        sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; return 0 ;;
            *) fallo "Opción desconocida: $1 (mira --ayuda)" ;;
        esac
        shift
    done

    printf '\n  %s - actualizador para Linux\n' "$NOMBRE_JUEGO"

    paso "Buscando tu instalación"
    if [ -z "$DESTINO" ]; then
        DESTINO="$(buscar_instalacion)" || fallo "No encuentro dónde está instalado el juego.
   Si lo instalaste en otra carpeta, dímela:  bash tools/actualizar.sh --destino /ruta/al/juego
   Si aún no lo has instalado, usa:           bash tools/instalar.sh"
    else
        DESTINO="${DESTINO/#\~/$HOME}"
        es_instalacion "$DESTINO" || fallo "No hay ninguna instalación en $DESTINO (falta $EXE_JUEGO)."
        DESTINO="$(cd "$DESTINO" && pwd)"
    fi
    ok "Instalado en: $DESTINO"

    leer_manifiesto "$DESTINO" || true
    local v_inst="${MF[version]:-desconocida}" h_inst="${MF[huella]:-}"
    local v_nueva h_nueva
    v_nueva="$(leer_version "$RAIZ")"
    h_nueva="$(huella_proyecto "$RAIZ")"
    info "Versión instalada: $v_inst   ·   versión de este proyecto: $v_nueva"

    if [ "$FORZAR" != 1 ] && [ -n "$h_inst" ] && [ "$h_inst" = "$h_nueva" ]; then
        ok "Ya tienes esta versión instalada: no hay nada que actualizar. (Con --forzar se reinstala igualmente.)"
        return 0
    fi
    if [ "$v_inst" != "desconocida" ] && [ "$v_inst" != "$v_nueva" ] \
       && [ "$(printf '%s\n%s\n' "$v_inst" "$v_nueva" | sort -V | head -1)" = "$v_nueva" ]; then
        aviso "Este proyecto ($v_nueva) es más antiguo que lo instalado ($v_inst)."
        preguntar_sn "¿Quieres instalarlo igualmente?" n || { info "Cancelado."; return 0; }
    fi

    local args=(--destino "$DESTINO" --actualizando)
    if [ -z "$JUEGO_PRUEBA" ]; then
        if [ -z "$ROM" ] && [ -f "$DESTINO/roms/$ROM_NOMBRE" ] && probar_rom "$DESTINO/roms/$ROM_NOMBRE"; then
            ROM="$DESTINO/roms/$ROM_NOMBRE"
            ok "Se reutiliza la ROM de la carpeta del juego."
        fi
        [ -n "$ROM" ] && args+=(--rom "$ROM")
    else
        args+=(--juego-prueba "$JUEGO_PRUEBA")
    fi
    # Se mantiene lo que se eligió al instalar (accesos y archivos de compilación).
    if [ "$CONSERVAR" = 1 ] || [ "${MF[conservar_obra]:-0}" = 1 ]; then args+=(--conservar-obra); fi
    if [ "${MF[conservar_obra]:-0}" = 1 ] && [ -n "${MF[obra]:-}" ] && [ -d "${MF[obra]}" ]; then args+=(--obra "${MF[obra]}"); fi
    if [ -n "${MF[acceso_escritorio]:-}" ]; then args+=(--escritorio); fi
    if [ -z "${MF[acceso_menu]:-}" ] && [ -n "${MF[version]:-}" ]; then args+=(--sin-accesos); fi

    exec bash "$RAIZ/tools/instalar.sh" "${args[@]}" ${extra[@]+"${extra[@]}"}
}

principal "$@"
