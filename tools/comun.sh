#!/usr/bin/env bash
# comun.sh — funciones y datos que comparten instalar.sh y actualizar.sh (Linux).
# No se ejecuta solo: los otros scripts lo cargan con «source».
# (desinstalar.sh es independiente a propósito: se copia a la carpeta del juego y tiene que
# funcionar aunque ya no esté el proyecto.)

NOMBRE_JUEGO="Mario Tennis Power Tour"
ID_ESCRITORIO="mario-tennis-power-tour"
EXE_JUEGO="MarioTennisPowerTourRecomp"
ROM_NOMBRE="mario_tennis_power_tour_eur.gba"
ROM_SHA1="d61990974040d405b5bf8436ac8e1e0beb0f7964"
ROM_TAM=16777216

DATOS_BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}"
DESTINO_POR_DEFECTO="$DATOS_BASE/MarioTennisPowerTour"
OBRA_POR_DEFECTO="$CACHE_BASE/MarioTennisPowerTour-obra"
CARPETA_ACCESOS="$DATOS_BASE/applications"
ARCHIVO_ACCESO="$CARPETA_ACCESOS/$ID_ESCRITORIO.desktop"

# ── Mensajes ───────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_PASO=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_AVISO=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_FIN=$'\033[0m'
else
    C_PASO=""; C_OK=""; C_AVISO=""; C_ERR=""; C_FIN=""
fi
paso()  { printf '\n%s== %s%s\n' "$C_PASO" "$*" "$C_FIN"; }
info()  { printf '   %s\n' "$*"; }
ok()    { printf '   %s[OK]%s %s\n' "$C_OK" "$C_FIN" "$*"; }
aviso() { printf '   %s[!]%s %s\n' "$C_AVISO" "$C_FIN" "$*"; }
fallo() { printf '\n%sERROR:%s %s\n' "$C_ERR" "$C_FIN" "$*" >&2; exit 1; }

# ¿Se puede preguntar al usuario? Solo con una terminal y sin --silencioso.
es_interactivo() { [ "${SILENCIOSO:-0}" != 1 ] && [ -t 0 ]; }

# preguntar_sn "texto" [s|n]: devuelve 0 (sí) o 1 (no). Sin terminal o en silencio, responde el valor por defecto.
preguntar_sn() {
    local texto="$1" defecto="${2:-n}" r sufijo
    if ! es_interactivo; then [ "$defecto" = s ]; return; fi
    if [ "$defecto" = s ]; then sufijo="[S/n]"; else sufijo="[s/N]"; fi
    read -r -p "   $texto $sufijo " r || r=""
    r="${r,,}"
    case "$r" in
        s|si|sí|y|yes) return 0 ;;
        n|no)          return 1 ;;
        *)             [ "$defecto" = s ] ;;
    esac
}

# ── Herramientas ───────────────────────────────────────────────────────────
# MTP_PRUEBA_SIN="cmake ninja" hace como si faltaran (solo para las pruebas).
tiene_herramienta() {
    case " ${MTP_PRUEBA_SIN:-} " in *" $1 "*) return 1 ;; esac
    command -v "$1" >/dev/null 2>&1
}

sha1_de() {
    if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -d' ' -f1
    else shasum -a 1 "$1" | cut -d' ' -f1; fi
}
tam_de() { wc -c < "$1" | tr -d ' '; }

# probar_rom ruta: 0 si es la ROM europea correcta; si no, deja el motivo en $MENSAJE_ROM.
probar_rom() {
    local r="$1" s
    MENSAJE_ROM=""
    if [ ! -f "$r" ]; then MENSAJE_ROM="No existe el archivo: $r"; return 1; fi
    if [ "$(tam_de "$r")" != "$ROM_TAM" ]; then
        MENSAJE_ROM="La ROM debe medir 16 MiB (16777216 bytes); esta mide $(tam_de "$r")."; return 1
    fi
    s="$(sha1_de "$r")"
    if [ "$s" != "${MTP_PRUEBA_ROM_SHA1:-$ROM_SHA1}" ]; then
        MENSAJE_ROM="Esta ROM no es la versión europea (BTMP, rev. 0).
   SHA-1 de tu archivo: $s
   SHA-1 esperado:      $ROM_SHA1"
        return 1
    fi
    return 0
}

# buscar_rom [carpetas…]: imprime la primera ROM correcta que encuentre (hasta 2 niveles) en esas
# carpetas, en la actual y en las típicas del usuario. Devuelve 1 si no hay ninguna.
buscar_rom() {
    local d f
    for d in "$@" "$PWD" "$HOME/Descargas" "$HOME/Downloads" "$HOME/Documentos" "$HOME/Documents" \
             "$HOME/Escritorio" "$HOME/Desktop" "$HOME/Juegos" "$HOME/Games" "$HOME/ROMs" "$HOME/roms"; do
        [ -d "$d" ] || continue
        while IFS= read -r -d '' f; do
            if probar_rom "$f"; then printf '%s' "$f"; return 0; fi
        done < <(find "$d" -maxdepth 2 -type f -iname '*.gba' -size "${ROM_TAM}c" -print0 2>/dev/null)
    done
    return 1
}

# ── Versión del proyecto ───────────────────────────────────────────────────
leer_version() {
    local v="$1/VERSION"
    if [ -f "$v" ]; then tr -d '[:space:]' < "$v"; else printf '0.0'; fi
}

# Huella del proyecto: cambia si cambia algo que afecte al juego compilado (parches, fuentes, configuración).
# Los textos se leen sin los retornos de carro, para que no cambie si el mismo zip llega con CRLF.
huella_proyecto() {
    local raiz="$1" f h
    {
        for f in game.toml CMakeLists.txt bios_libre/bios_libre.toml bios_libre/bios_libre.bin tools/construir.sh tools/jugar.sh; do
            [ -f "$raiz/$f" ] && printf '%s\n' "$f"
        done
        (cd "$raiz" && find parches src -type f 2>/dev/null)
    } | LC_ALL=C sort -u | while IFS= read -r f; do
        case "$f" in
            *.bin) h="$(sha256sum "$raiz/$f" | cut -d' ' -f1)" ;;
            *)     h="$(tr -d '\r' < "$raiz/$f" | sha256sum | cut -d' ' -f1)" ;;
        esac
        printf '%s:%s\n' "$f" "$h"
    done | sha256sum | cut -d' ' -f1
}

# ── Manifiesto de la instalación (instalacion.cfg: clave=valor) ───────────
declare -gA MF=()
leer_manifiesto() { # carpeta → rellena MF; 1 si no hay manifiesto
    local f="$1/instalacion.cfg" k v
    MF=()
    [ -f "$f" ] || return 1
    while IFS='=' read -r k v; do
        case "$k" in ''|'#'*) continue ;; esac
        MF["$k"]="$v"
    done < "$f"
    return 0
}

es_instalacion() { [ -n "${1:-}" ] && [ -d "$1" ] && [ -f "$1/$EXE_JUEGO" ]; }

# Busca sola dónde está instalado el juego: la entrada del menú de aplicaciones y la carpeta por defecto.
buscar_instalacion() {
    local c cand=()
    if [ -f "$ARCHIVO_ACCESO" ]; then
        c="$(sed -n 's/^Path=//p' "$ARCHIVO_ACCESO" | head -1)"
        [ -n "$c" ] && cand+=("$c")
    fi
    cand+=("$DESTINO_POR_DEFECTO")
    for c in "${cand[@]}"; do
        if es_instalacion "$c"; then (cd "$c" && pwd); return 0; fi
    done
    return 1
}

# Núcleos para compilar: cada proceso del compilador puede usar más de 1 GiB de RAM.
calcular_nucleos() {
    local n mem_kb porram
    if [ -n "${MTP_NUCLEOS:-}" ]; then printf '%s' "$MTP_NUCLEOS"; return; fi
    n="$(nproc 2>/dev/null || echo 2)"
    mem_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || true)"
    if [ -n "$mem_kb" ]; then
        porram=$(( mem_kb / 1536 / 1024 ))
        [ "$porram" -lt "$n" ] && n="$porram"
    fi
    [ "$n" -ge 1 ] || n=1
    printf '%s' "$n"
}

# Espacio libre (en MiB) del sistema de archivos donde está o estará una carpeta.
espacio_libre_mib() {
    local d="$1"
    while [ ! -d "$d" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done
    df -Pk "$d" 2>/dev/null | awk 'NR==2{print int($4/1024)}'
}

# ¿La carpeta solo tiene datos del usuario (lo que deja desinstalar.sh al conservar partidas y ajustes)?
# La lista tiene que coincidir con la de desinstalar.sh y con la de copiar_juego() en instalar.sh.
solo_datos_de_usuario() {
    local d="$1" otro
    otro="$(find "$d" -mindepth 1 \
        \( -path "$d/capturas" -o -path "$d/capturas/*" \
           -o -path "$d/copias-de-partidas" -o -path "$d/copias-de-partidas/*" \
           -o -path "$d/config.ini" -o -path "$d/keybinds.ini" -o -path "$d/launcher-window.ini" \
           -o -path "$d/rom.cfg" -o -path "$d/bios.cfg" \
           -o -path "$d/roms/*.sav" -o -path "$d/roms/*.state[0-9]" \) -prune \
        -o \( -type f -o -type l \) -print -quit 2>/dev/null)"
    [ -z "$otro" ]
}
