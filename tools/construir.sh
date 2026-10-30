#!/usr/bin/env bash
# construir.sh — de tu ROM al juego, en un solo paso (Linux, macOS y MSYS2/Windows).
#
#   tools/construir.sh [ruta/a/tu_rom.gba]
#
# Si no pasas la ROM, usa la que haya en roms/. Hace, por orden:
#   1. Comprueba que la ROM es la versión europea de Mario Tennis: Power Tour (SHA-1).
#   2. Descarga gbarecomp (framework) y recomp-ui (menú) en las versiones probadas.
#   3. Aplica los parches de parches/ al framework.
#   4. Compila el recompilador, y con él recompila la BIOS libre y TU ROM a C++.
#   5. Compila el juego y monta la carpeta juego/ lista para ejecutar.
set -euo pipefail

# En Windows (MSYS2) git puede convertir los finales de línea al clonar y eso rompe
# los parches: se desactiva para todos los git de este script (también submódulos).
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.autocrlf
export GIT_CONFIG_VALUE_0=false

# ── Versiones fijadas (las que se han probado) ─────────────────────────────
GBARECOMP_URL="https://github.com/mstan/gbarecomp.git"
GBARECOMP_COMMIT="edc2b80c73d83a2f35b9cfedaea0ea8d14647697"
RECOMP_UI_URL="https://github.com/mstan/recomp-ui.git"
RECOMP_UI_COMMIT="0546fbcb0126bb14bf88d2128b4fe8a4229570a3"
ROM_SHA1="d61990974040d405b5bf8436ac8e1e0beb0f7964"
ROM_TAM=16777216

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

EXTERNO="$RAIZ/externo"
COMPILACION="$RAIZ/build"
SALIDA="$RAIZ/juego"
ROM_DESTINO="$RAIZ/roms/mario_tennis_power_tour_eur.gba"
# MTP_NUCLEOS limita los procesos de compilación en paralelo (cada uno puede usar
# más de 1 GiB de RAM; el instalador de Windows lo ajusta a la memoria libre).
NUCLEOS="${MTP_NUCLEOS:-$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) | head -1)}"

# En MSYS2 CMake es un programa de Windows: las rutas que van DENTRO de una opción
# -DNOMBRE=ruta hay que dárselas ya convertidas (C:/...). En Linux no cambia nada.
ruta_nativa() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
paso()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fallo() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ── 0. Herramientas ────────────────────────────────────────────────────────
for h in git cmake python3 ninja; do
    command -v "$h" >/dev/null 2>&1 || fallo "Falta «$h». Instálalo (ver README.md) y vuelve a ejecutar."
done
if command -v g++ >/dev/null 2>&1; then :; elif command -v clang++ >/dev/null 2>&1; then :; else
    fallo "Falta un compilador de C++ (g++ o clang++)."
fi
sha1_de() {
    if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -d' ' -f1
    else shasum -a 1 "$1" | cut -d' ' -f1; fi
}
tam_de() { wc -c < "$1" | tr -d ' '; }

# ── 1. La ROM ──────────────────────────────────────────────────────────────
paso "Buscando y verificando tu ROM"
ROM_ORIGEN="${1:-}"
if [ -z "$ROM_ORIGEN" ]; then
    # Sin argumento: la ROM ya colocada, o cualquier .gba de roms/ con el SHA-1 correcto.
    for c in "$ROM_DESTINO" "$RAIZ"/roms/*.gba; do
        [ -f "$c" ] || continue
        if [ "$(tam_de "$c")" = "$ROM_TAM" ] && [ "$(sha1_de "$c")" = "$ROM_SHA1" ]; then
            ROM_ORIGEN="$c"; break
        fi
    done
    [ -n "$ROM_ORIGEN" ] || fallo "No encuentro tu ROM. Copia el .gba europeo (16 MiB) en roms/ o pásalo como argumento."
fi
[ -f "$ROM_ORIGEN" ] || fallo "No existe el archivo: $ROM_ORIGEN"
[ "$(tam_de "$ROM_ORIGEN")" = "$ROM_TAM" ] || fallo "La ROM debe medir 16 MiB (16777216 bytes); esta mide $(tam_de "$ROM_ORIGEN")."
SHA_ROM="$(sha1_de "$ROM_ORIGEN")"
if [ "$SHA_ROM" != "$ROM_SHA1" ]; then
    fallo "Esta ROM no es la versión europea (BTMP, rev. 0) que soporta el proyecto.
  SHA-1 de tu archivo : $SHA_ROM
  SHA-1 esperado      : $ROM_SHA1"
fi
mkdir -p "$RAIZ/roms"
if [ "$(cd "$(dirname "$ROM_ORIGEN")" && pwd)/$(basename "$ROM_ORIGEN")" != "$ROM_DESTINO" ]; then
    cp "$ROM_ORIGEN" "$ROM_DESTINO"
fi
echo "ROM correcta (SHA-1 $SHA_ROM)."

# ── 2. Framework y menú ────────────────────────────────────────────────────
traer() { # nombre url commit
    local dir="$EXTERNO/$1"
    if [ ! -d "$dir/.git" ]; then
        paso "Descargando $1"
        mkdir -p "$EXTERNO"
        git clone --quiet "$2" "$dir"
    fi
    if [ "$(git -C "$dir" rev-parse HEAD)" != "$3" ]; then
        git -C "$dir" fetch --quiet origin "$3" 2>/dev/null || git -C "$dir" fetch --quiet origin
        # Los parches se vuelven a aplicar después: se descarta lo que hubiera.
        git -C "$dir" checkout --quiet --force "$3"
    fi
    git -C "$dir" submodule update --init --recursive --quiet
}
traer gbarecomp "$GBARECOMP_URL" "$GBARECOMP_COMMIT"
traer recomp-ui "$RECOMP_UI_URL" "$RECOMP_UI_COMMIT"

# ── 3. Parches al framework (idempotentes) ─────────────────────────────────
paso "Aplicando los parches de parches/ a gbarecomp"
python3 -I "$RAIZ/tools/aplicar_parches.py" "$EXTERNO/gbarecomp"

# ── 4. Recompilador, BIOS libre y tu ROM ───────────────────────────────────
paso "Compilando el recompilador (gba_recompile)"
cmake -S "$EXTERNO/gbarecomp" -B "$COMPILACION/recompilador" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$COMPILACION/recompilador" --target gba_recompile -j "$NUCLEOS"
RECOMPILADOR="$(find "$COMPILACION/recompilador" -maxdepth 2 -type f \( -name gba_recompile -o -name gba_recompile.exe \) | head -1)"
[ -n "$RECOMPILADOR" ] || fallo "No encuentro gba_recompile tras compilarlo."

paso "Recompilando la BIOS libre"
"$RECOMPILADOR" --bios "$RAIZ/bios_libre/bios_libre.bin" \
    --config "$RAIZ/bios_libre/bios_libre.toml" --out "$RAIZ/generated_bios"

paso "Recompilando tu ROM (de ARM/Thumb a C++)"
"$RECOMPILADOR" --rom "$ROM_DESTINO" --config "$RAIZ/game.toml" --out "$RAIZ/generated"

# ── 5. El juego ────────────────────────────────────────────────────────────
paso "Compilando el juego (la primera vez tarda; usa $NUCLEOS núcleos)"
cmake -S "$RAIZ" -B "$COMPILACION/juego" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DGBARECOMP_ROOT="$(ruta_nativa "$EXTERNO/gbarecomp")" -DRECOMP_UI_ROOT="$(ruta_nativa "$EXTERNO/recomp-ui")" >/dev/null
cmake --build "$COMPILACION/juego" --target MarioTennisPowerTourRecomp -j "$NUCLEOS"

paso "Montando la carpeta juego/"
rm -rf "$SALIDA"
mkdir -p "$SALIDA/roms" "$SALIDA/bios_libre"
BINARIO="$(find "$COMPILACION/juego" -maxdepth 1 -type f \( -name MarioTennisPowerTourRecomp -o -name MarioTennisPowerTourRecomp.exe \) | head -1)"
[ -n "$BINARIO" ] || fallo "No encuentro el ejecutable compilado."
cp "$BINARIO" "$SALIDA/"
# DLL (Windows) y recursos del menú que dejó CMake junto al ejecutable.
cp -f "$COMPILACION/juego"/*.dll "$SALIDA/" 2>/dev/null || true
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        # El .exe depende de SDL2.dll y de las DLL de MinGW (libstdc++, libgcc,
        # winpthread...): se copian junto a él para que «juego/» sea autónoma y
        # funcione con doble clic sin tener MSYS2 en el PATH.
        if command -v ldd >/dev/null 2>&1; then
            ldd "$BINARIO" | awk '/=> \/(mingw64|ucrt64|clang64)\//{print $3}' |
                while read -r dll; do cp -f "$dll" "$SALIDA/"; done
        fi
        ;;
esac
[ -d "$COMPILACION/juego/assets" ] && cp -r "$COMPILACION/juego/assets" "$SALIDA/assets"
cp "$RAIZ/game.toml" "$SALIDA/"
cp "$RAIZ/bios_libre/bios_libre.bin" "$RAIZ/bios_libre/LICENSE-Cult-of-GBA-BIOS.txt" "$SALIDA/bios_libre/"
cp "$ROM_DESTINO" "$SALIDA/roms/"
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) cp "$RAIZ/tools/JUGAR.bat" "$SALIDA/JUGAR.bat" ;;
    *) cp "$RAIZ/tools/jugar.sh" "$SALIDA/jugar.sh"; chmod +x "$SALIDA/jugar.sh" ;;
esac

paso "Listo"
echo "El juego está en: $SALIDA"
echo "Ejecútalo con JUGAR.bat (Windows) o ./jugar.sh (Linux)."
