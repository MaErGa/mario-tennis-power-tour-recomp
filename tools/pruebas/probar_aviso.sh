#!/usr/bin/env bash
# Prueba el aviso de «hay una versión nueva» (src/aviso_actualizacion.cpp) contra un servidor
# HTTP local: no necesita internet, ni la ROM, ni compilar el juego.
# Uso: tools/pruebas/probar_aviso.sh      (necesita g++, python3 y curl)
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'kill "${pid_servidor:-0}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

cat > "$tmp/prueba.cpp" <<'CPP'
#include <chrono>
#include <cstdio>
#include <thread>
extern "C" const char* mtp_aviso_actualizacion(void);
int main() {
    for (int i = 0; i < 50; ++i) {
        const char* a = mtp_aviso_actualizacion();
        if (a[0]) { std::printf("AVISO=%s\n", a); return 0; }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    std::printf("sin aviso\n");
    return 0;
}
CPP
g++ -std=c++17 -O1 -Wall -Wextra -DMTP_VERSION='"0.4.3"' -DMTP_URL_VERSION_DEFECTO='""' \
    "$tmp/prueba.cpp" "$raiz/src/aviso_actualizacion.cpp" -o "$tmp/prueba" -pthread

mkdir "$tmp/srv"
printf '0.4.4\n'  > "$tmp/srv/nueva"
printf '0.4.3\n'  > "$tmp/srv/igual"
printf '0.4.2\n'  > "$tmp/srv/vieja"
printf '0.4.10\n' > "$tmp/srv/diez"
printf '1.0\n'    > "$tmp/srv/mayor"
printf '<html>hola</html>\n' > "$tmp/srv/basura"
puerto=$((20000 + RANDOM % 20000))
(cd "$tmp/srv" && exec python3 -m http.server "$puerto" --bind 127.0.0.1 >/dev/null 2>&1) &
pid_servidor=$!
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$puerto/igual" >/dev/null 2>&1 && break; sleep 0.1; done
base="http://127.0.0.1:$puerto"

fallos=0
caso() {  # caso "nombre" "esperado" url [config.ini]
    local salida
    salida="$(MTP_URL_VERSION="$3" MTP_CONFIG_INI="${4:-/no/existe}" "$tmp/prueba")"
    if [ "$salida" = "$2" ]; then echo "ok   $1"; else echo "FALLO $1: salió «$salida», se esperaba «$2»"; fallos=$((fallos + 1)); fi
}
caso "versión más nueva"            "AVISO=0.4.4"  "$base/nueva"
caso "misma versión"                "sin aviso"    "$base/igual"
caso "versión más vieja"            "sin aviso"    "$base/vieja"
caso "0.4.10 es mayor que 0.4.3"    "AVISO=0.4.10" "$base/diez"
caso "1.0 es mayor que 0.4.3"       "AVISO=1.0"    "$base/mayor"
caso "respuesta que no es versión"  "sin aviso"    "$base/basura"
caso "dirección que da 404"         "sin aviso"    "$base/noexiste"
caso "servidor que no responde"     "sin aviso"    "http://127.0.0.1:1/nueva"
caso "http a un servidor externo"   "sin aviso"    "http://example.com/VERSION"
caso "dirección con comillas"       "sin aviso"    "$base/nueva'; touch $tmp/HACKEADO; echo '"
[ ! -e "$tmp/HACKEADO" ] || { echo "FALLO: se ejecutó código de la dirección"; fallos=$((fallos + 1)); }

printf '[Menu]\nLanguage = es\nCheckUpdates = 0\n' > "$tmp/apagado.ini"
caso "CheckUpdates = 0"             "sin aviso"    "$base/nueva" "$tmp/apagado.ini"
printf '[Menu]\nUpdateUrl = %s/nueva\n' "$base" > "$tmp/url.ini"
salida="$(MTP_CONFIG_INI="$tmp/url.ini" "$tmp/prueba")"
if [ "$salida" = "AVISO=0.4.4" ]; then echo "ok   UpdateUrl en config.ini"; else echo "FALLO UpdateUrl: «$salida»"; fallos=$((fallos + 1)); fi

[ "$fallos" -eq 0 ] && echo "Aviso de versión: todo correcto" || { echo "$fallos fallo(s)"; exit 1; }
