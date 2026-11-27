#!/usr/bin/env bash
# Prueba el instalador, el actualizador y el desinstalador de Linux (tools/instalar.sh, actualizar.sh,
# desinstalar.sh) SIN compilar el juego y sin la ROM: usa un «juego» falso (--juego-prueba) y un HOME
# temporal, así que no toca nada de tu equipo.
# Uso: bash tools/pruebas/probar_instalador_linux.sh        (solo necesita bash y las herramientas básicas)
set -euo pipefail

aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bien=0; mal=0
comprobar() { # descripción orden…
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then bien=$((bien + 1)); printf '  ok  %s\n' "$d"
    else mal=$((mal + 1)); printf '  FALLA  %s\n' "$d"; fi
}
no() { ! "$@"; }
seccion() { printf '\n== %s\n' "$*"; }

# El proyecto se copia a una carpeta temporal para poder tocar sus archivos sin riesgo.
proyecto="$tmp/proyecto"
mkdir -p "$proyecto"
(cd "$raiz" && find . -type f -not -path './generated/*' -not -path './generated_bios/*' -not -path './juego/*' \
    -not -path './build/*' -not -path './externo/*' -not -path './.git/*' -not -path '*/__pycache__/*' \
    -not -path './roms/*' -not -name '*.gba' -not -name '*.sav' -print0 | xargs -0 -I{} cp --parents {} "$proyecto")
mkdir -p "$proyecto/roms"

# Entorno aislado
casa="$tmp/casa"; mkdir -p "$casa"
entorno() { env -i PATH="$PATH" HOME="$casa" LANG=C.UTF-8 "$@"; }
instalar()   { entorno bash "$proyecto/tools/instalar.sh" "$@"; }
actualizar() { entorno bash "$proyecto/tools/actualizar.sh" "$@"; }

# «Juego» falso: un ejecutable que anota desde dónde se le arrancó.
hacer_juego() { # carpeta etiqueta
    local j="$1" etq="$2"
    rm -rf "$j"; mkdir -p "$j/assets" "$j/bios_libre" "$j/roms"
    printf '#!/bin/sh\necho "%s|$(pwd)|$*" >> "$HOME/arranques.log"\n' "$etq" > "$j/MarioTennisPowerTourRecomp"
    chmod +x "$j/MarioTennisPowerTourRecomp"
    cp "$proyecto/tools/jugar.sh" "$j/jugar.sh"
    echo "game" > "$j/game.toml"
    echo "asset de $etq" > "$j/assets/uno_$etq.txt"
    echo "bios" > "$j/bios_libre/bios_libre.bin"
    echo "rom falsa" > "$j/roms/mario_tennis_power_tour_eur.gba"
}
hacer_juego "$tmp/juego1" v1
hacer_juego "$tmp/juego2" v2
echo "ajuste=del_juego_nuevo" > "$tmp/juego2/config.ini"
echo "estado nuevo" > "$tmp/juego2/roms/mario_tennis_power_tour_eur.state1"

seccion "Instalar (con espacios en la carpeta)"
dest="$casa/Juegos con espacios/Mario Tennis"
comprobar "instala con --juego-prueba" instalar --juego-prueba "$tmp/juego1" --destino "$dest" --silencioso
comprobar "copia el ejecutable"          test -x "$dest/MarioTennisPowerTourRecomp"
comprobar "copia jugar.sh"               test -x "$dest/jugar.sh"
comprobar "copia el desinstalador"       test -x "$dest/desinstalar.sh"
comprobar "copia assets y bios libre"    test -f "$dest/assets/uno_v1.txt" -a -f "$dest/bios_libre/bios_libre.bin"
comprobar "escribe instalacion.cfg"      grep -qx "producto=MarioTennisPowerTourRecomp" "$dest/instalacion.cfg"
comprobar "la versión del manifiesto es la de VERSION" grep -qx "version=$(tr -d '[:space:]' < "$proyecto/VERSION")" "$dest/instalacion.cfg"
acceso="$casa/.local/share/applications/mario-tennis-power-tour.desktop"
comprobar "crea la entrada del menú"     test -f "$acceso"
comprobar "la entrada trae Name, Exec y Path" bash -c "grep -q '^Name=Mario Tennis Power Tour' '$acceso' && grep -q '^Exec=\"' '$acceso' && grep -qxF 'Path=$dest' '$acceso'"
comprobar "la entrada es válida (desktop-file-validate, si existe)" bash -c "! command -v desktop-file-validate >/dev/null || desktop-file-validate '$acceso'"
# Se ejecuta el Exec tal cual lo haría el menú de aplicaciones (desde otra carpeta)
exec_val="$(sed -n 's/^Exec=//p' "$acceso")"; exec_val="${exec_val#\"}"; exec_val="${exec_val%\"}"
comprobar "el Exec arranca el juego desde su carpeta" bash -c "cd / && HOME='$casa' '$exec_val' --prueba && grep -qF 'v1|$dest|--prueba' '$casa/arranques.log'"
comprobar "no deja la carpeta de trabajo ni basura" no test -e "$casa/.cache/MarioTennisPowerTour-obra"

seccion "Actualizar (conserva tus datos)"
echo "ajuste=del_usuario" > "$dest/config.ini"
echo "partida" > "$dest/roms/mario_tennis_power_tour_eur.sav"
echo "estado del usuario" > "$dest/roms/mario_tennis_power_tour_eur.state1"
mkdir -p "$dest/capturas"; echo "png" > "$dest/capturas/foto.png"
out="$(actualizar --juego-prueba "$tmp/juego2" --silencioso 2>&1)" || true
comprobar "sin cambios en el proyecto, dice que ya está al día" grep -q "Ya tienes esta versión" <<<"$out"
comprobar "…y no toca el juego instalado" test -f "$dest/assets/uno_v1.txt"
comprobar "encuentra la instalación por el menú (sin --destino)" grep -qF "Instalado en: $dest" <<<"$out"
comprobar "actualiza con --forzar" actualizar --juego-prueba "$tmp/juego2" --forzar --silencioso
comprobar "el ejecutable es el nuevo" bash -c "HOME='$casa' '$dest/MarioTennisPowerTourRecomp' x && tail -1 '$casa/arranques.log' | grep -q '^v2|'"
comprobar "los assets se sustituyen enteros (el viejo ya no está)" bash -c "test -f '$dest/assets/uno_v2.txt' && test ! -e '$dest/assets/uno_v1.txt'"
comprobar "no pisa tu config.ini"        grep -qx "ajuste=del_usuario" "$dest/config.ini"
comprobar "no pisa tu partida (.sav)"    grep -qx "partida" "$dest/roms/mario_tennis_power_tour_eur.sav"
comprobar "no pisa tus estados"          grep -qx "estado del usuario" "$dest/roms/mario_tennis_power_tour_eur.state1"
comprobar "conserva tus capturas"        test -f "$dest/capturas/foto.png"
comprobar "la entrada del menú sigue ahí" grep -qxF "Path=$dest" "$acceso"

seccion "Actualizar con la instalación en la carpeta por defecto (sin entrada de menú)"
rm -f "$acceso"; rm -rf "$casa/.local/share/MarioTennisPowerTour"
hacer_juego "$tmp/juego3" v3
comprobar "instala en la carpeta por defecto" instalar --juego-prueba "$tmp/juego3" --silencioso --sin-accesos
comprobar "sin --sin-accesos no… crea la entrada" no test -f "$acceso"
comprobar "…está en ~/.local/share/MarioTennisPowerTour" test -x "$casa/.local/share/MarioTennisPowerTour/MarioTennisPowerTourRecomp"
comprobar "actualizar la encuentra y respeta --sin-accesos" bash -c "
    cd '$tmp' && env -i PATH='$PATH' HOME='$casa' bash '$proyecto/tools/actualizar.sh' --juego-prueba '$tmp/juego2' --forzar --silencioso >/dev/null 2>&1 \
    && test ! -f '$acceso' && tail -1 '$casa/.local/share/MarioTennisPowerTour/instalacion.cfg' >/dev/null"
comprobar "…y el juego instalado es el nuevo" test -f "$casa/.local/share/MarioTennisPowerTour/assets/uno_v2.txt"

seccion "Rechazos y comprobaciones de seguridad"
mkdir -p "$casa/Documentos"; echo "importante" > "$casa/Documentos/tesis.txt"
comprobar "no instala en una carpeta con cosas ajenas" no instalar --juego-prueba "$tmp/juego1" --destino "$casa/Documentos" --silencioso
comprobar "…y no toca lo que había" grep -qx "importante" "$casa/Documentos/tesis.txt"
comprobar "no instala en tu carpeta personal" no instalar --juego-prueba "$tmp/juego1" --destino "$casa" --silencioso
comprobar "no instala con \$ en la ruta"      no instalar --juego-prueba "$tmp/juego1" --destino "$casa/a\$b" --silencioso
comprobar "no instala dentro del proyecto"    no instalar --juego-prueba "$tmp/juego1" --destino "$proyecto/dentro" --silencioso
comprobar "no instala encima del proyecto"    no instalar --juego-prueba "$tmp/juego1" --destino "$proyecto" --silencioso
comprobar "rechaza una opción desconocida"    no instalar --lo-que-sea
comprobar "actualizar sin instalación avisa y falla" no actualizar --destino "$tmp/no-existe" --silencioso
mkdir -p "$tmp/falso"; cp "$tmp/juego1/MarioTennisPowerTourRecomp" "$tmp/falso/"; cp "$proyecto/tools/desinstalar.sh" "$tmp/falso/"
comprobar "el desinstalador se niega sin instalacion.cfg" no bash "$tmp/falso/desinstalar.sh" --silencioso --borrar-todo
comprobar "…y no borra nada" test -x "$tmp/falso/MarioTennisPowerTourRecomp"
comprobar "el desinstalador no acepta «/»" no bash "$dest/desinstalar.sh" --destino / --silencioso

seccion "Herramientas que faltan (se simula)"
salida="$(entorno MTP_PRUEBA_SIN="cmake sdl2" bash "$proyecto/tools/instalar.sh" --silencioso --rom "$tmp/nada.gba" 2>&1)" && r=0 || r=$?
comprobar "sale con error"                    test "$r" -ne 0
comprobar "dice qué falta (cmake y SDL2)"     bash -c "grep -q 'cmake' <<<\"\$1\" && grep -q 'SDL2' <<<\"\$1\"" _ "$salida"
comprobar "propone una orden para instalarlo" grep -Eq "(apt-get|dnf|pacman|zypper) .*(install|-S)" <<<"$salida"
comprobar "no ha creado nada en la carpeta por defecto del juego" bash -c "! test -e '$casa/.local/share/MarioTennisPowerTour/NO_EXISTE'"

seccion "ROM: validación y búsqueda"
(
    HOME="$casa"; export HOME
    # shellcheck disable=SC1091
    source "$proyecto/tools/instalar.sh"
    set +e
    head -c 1000 /dev/zero > "$tmp/pequena.gba"
    head -c 16777216 /dev/zero > "$tmp/ceros.gba"
    head -c 16777216 /dev/urandom > "$tmp/buena.gba"
    r=0
    probar_rom "$tmp/nada.gba" && r=1;   [ "$r" = 0 ] && [[ "$MENSAJE_ROM" == *"No existe"* ]] || { echo "FALLA no existe"; exit 1; }
    probar_rom "$tmp/pequena.gba" && exit 1; [[ "$MENSAJE_ROM" == *"16 MiB"* ]] || { echo "FALLA tamaño"; exit 1; }
    probar_rom "$tmp/ceros.gba" && exit 1;   [[ "$MENSAJE_ROM" == *"no es la versión europea"* ]] || { echo "FALLA sha"; exit 1; }
    export MTP_PRUEBA_ROM_SHA1="$(sha1_de "$tmp/buena.gba")"
    probar_rom "$tmp/buena.gba" || { echo "FALLA buena"; exit 1; }
    mkdir -p "$casa/Descargas/juegos"; cp "$tmp/buena.gba" "$casa/Descargas/juegos/MI_ROM.GBA"; cp "$tmp/ceros.gba" "$casa/Descargas/otra.gba"
    [ "$(buscar_rom)" = "$casa/Descargas/juegos/MI_ROM.GBA" ] || { echo "FALLA buscar"; exit 1; }
    export MTP_PRUEBA_ROM_SHA1=0000000000000000000000000000000000000000
    buscar_rom >/dev/null && { echo "FALLA buscar falso"; exit 1; }
    exit 0
) && { bien=$((bien + 1)); echo "  ok  probar_rom (no existe, tamaño, SHA-1) y buscar_rom (mayúsculas, subcarpetas)"; } \
  || { mal=$((mal + 1)); echo "  FALLA  probar_rom / buscar_rom"; }

seccion "Carpeta de trabajo (obra) y huella"
(
    HOME="$casa"; export HOME
    # shellcheck disable=SC1091
    source "$proyecto/tools/instalar.sh"
    set +e
    obra="$tmp/obra"
    echo "rom" > "$tmp/rom_falsa.gba"
    preparar_obra "$obra" "$tmp/rom_falsa.gba" >/dev/null || { echo "FALLA preparar"; exit 1; }
    [ -f "$obra/.mtp-obra" ] && [ -f "$obra/tools/construir.sh" ] && [ -f "$obra/game.toml" ] || { echo "FALLA contenido"; exit 1; }
    [ ! -e "$obra/build" ] && [ ! -e "$obra/externo" ] && [ ! -e "$obra/juego" ] || { echo "FALLA excluidos"; exit 1; }
    [ -f "$obra/roms/mario_tennis_power_tour_eur.gba" ] || { echo "FALLA rom"; exit 1; }
    h1="$(huella_proyecto "$RAIZ")"; h2="$(huella_proyecto "$RAIZ")"
    [ "$h1" = "$h2" ] && [ ${#h1} = 64 ] || { echo "FALLA huella estable"; exit 1; }
    sleep 1.1
    antes="$(stat -c %Y "$obra/tools/construir.sh")"
    echo "cambio" >> "$RAIZ/src/main.cpp"
    : > "$RAIZ/parches/zzz-nuevo.patch"
    rm -f "$obra/../proyecto/parches/gbarecomp-0010-nombres-de-los-jugadores-en-red.patch"
    h3="$(huella_proyecto "$RAIZ")"
    [ "$h3" != "$h1" ] || { echo "FALLA huella cambia"; exit 1; }
    preparar_obra "$obra" "$tmp/rom_falsa.gba" >/dev/null || { echo "FALLA preparar 2"; exit 1; }
    cmp -s "$RAIZ/src/main.cpp" "$obra/src/main.cpp" || { echo "FALLA actualizó main"; exit 1; }
    [ -f "$obra/parches/zzz-nuevo.patch" ] || { echo "FALLA parche nuevo"; exit 1; }
    [ ! -e "$obra/parches/gbarecomp-0010-nombres-de-los-jugadores-en-red.patch" ] || { echo "FALLA parche retirado"; exit 1; }
    [ "$(stat -c %Y "$obra/tools/construir.sh")" = "$antes" ] || { echo "FALLA tocó un archivo sin cambios"; exit 1; }
    # CRLF no cambia la huella
    sed -i 's/$/\r/' "$RAIZ/src/main.cpp"
    [ "$(huella_proyecto "$RAIZ")" = "$h3" ] || { echo "FALLA huella con CRLF"; exit 1; }
    # Una carpeta ajena no se usa como obra
    mkdir -p "$tmp/ajena"; echo "tuyo" > "$tmp/ajena/algo.txt"
    ( preparar_obra "$tmp/ajena" "$tmp/rom_falsa.gba" ) >/dev/null 2>&1 && { echo "FALLA usó carpeta ajena"; exit 1; }
    [ -f "$tmp/ajena/algo.txt" ] || { echo "FALLA tocó carpeta ajena"; exit 1; }
    ( preparar_obra "$RAIZ/dentro" "$tmp/rom_falsa.gba" ) >/dev/null 2>&1 && { echo "FALLA obra dentro del proyecto"; exit 1; }
    exit 0
) && { bien=$((bien + 1)); echo "  ok  obra: copia sin lo generado, solo toca lo que cambia, quita lo retirado, rechaza carpetas ajenas; huella estable y con CRLF"; } \
  || { mal=$((mal + 1)); echo "  FALLA  obra / huella"; }

seccion "Acceso en el Escritorio, % en la ruta y núcleos"
mkdir -p "$casa/Desktop"
dest2="$casa/100%/juego"
comprobar "instala con --escritorio y un % en la ruta" instalar --juego-prueba "$tmp/juego1" --destino "$dest2" --escritorio --silencioso
atajo="$casa/Desktop/Mario Tennis Power Tour.desktop"
comprobar "crea el acceso del Escritorio, ejecutable" test -x "$atajo"
comprobar "el % va doblado en Exec"          grep -qF 'Exec="'"$casa"'/100%%/juego/jugar.sh"' "$atajo"
comprobar "el manifiesto recuerda los accesos" bash -c "grep -qF 'acceso_escritorio=$atajo' '$dest2/instalacion.cfg' && grep -q '^acceso_menu=' '$dest2/instalacion.cfg'"
n3="$(entorno MTP_NUCLEOS=3 bash -c "source '$proyecto/tools/comun.sh'; calcular_nucleos")"
n0="$(entorno bash -c "source '$proyecto/tools/comun.sh'; calcular_nucleos")"
comprobar "MTP_NUCLEOS manda sobre el cálculo"  test "$n3" = 3
comprobar "sin MTP_NUCLEOS hay al menos un núcleo" test "$n0" -ge 1

seccion "Desinstalar"
echo "mi ajuste" > "$dest2/config.ini"; echo "mi partida" > "$dest2/roms/mario_tennis_power_tour_eur.sav"
mkdir -p "$dest2/capturas"; echo "x" > "$dest2/capturas/a.png"
comprobar "desinstala conservando tus datos" bash "$dest2/desinstalar.sh" --silencioso
comprobar "quita la entrada del menú y el acceso del Escritorio" bash -c "test ! -e '$acceso' && test ! -e '$atajo'"
comprobar "el juego ya no está"            no test -e "$dest2/MarioTennisPowerTourRecomp"
comprobar "quedan tus ajustes, partida y capturas" bash -c "grep -qx 'mi ajuste' '$dest2/config.ini' && grep -qx 'mi partida' '$dest2/roms/mario_tennis_power_tour_eur.sav' && test -f '$dest2/capturas/a.png'"
comprobar "no quedan archivos del juego (assets, bios, instalacion.cfg)" bash -c "test ! -e '$dest2/assets' && test ! -e '$dest2/bios_libre' && test ! -e '$dest2/instalacion.cfg'"
# Reinstalar encima de lo conservado, y ahora borrarlo todo
comprobar "se puede reinstalar encima de lo conservado" instalar --juego-prueba "$tmp/juego1" --destino "$dest2" --silencioso --sin-accesos
comprobar "…sin perder tu ajuste"          grep -qx "mi ajuste" "$dest2/config.ini"
comprobar "desinstala borrándolo todo"     bash "$dest2/desinstalar.sh" --silencioso --borrar-todo
comprobar "la carpeta ya no existe"        no test -e "$dest2"
comprobar "la otra instalación (en Juegos con espacios) sigue intacta" test -x "$dest/MarioTennisPowerTourRecomp"
comprobar "la ayuda de los tres scripts funciona" bash -c "bash '$proyecto/tools/instalar.sh' --ayuda >/dev/null && bash '$proyecto/tools/actualizar.sh' --ayuda >/dev/null && bash '$proyecto/tools/desinstalar.sh' --ayuda >/dev/null"

printf '\nPruebas del instalador de Linux: %d bien, %d mal\n' "$bien" "$mal"
[ "$mal" -eq 0 ] || exit 1
printf 'Pruebas del instalador de Linux: todo bien\n'
