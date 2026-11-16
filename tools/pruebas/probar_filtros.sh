#!/usr/bin/env bash
# Compila y ejecuta las pruebas de los filtros de imagen (parche 0004).
# Uso: probar_filtros.sh RAIZ_GBARECOMP   (un gbarecomp con los parches ya aplicados)
set -euo pipefail
raiz="${1:?Uso: probar_filtros.sh RAIZ_GBARECOMP_PARCHEADO}"
aqui="$(cd "$(dirname "$0")" && pwd)"
origen="$raiz/src/runtime/host_window.cpp"
[ -f "$origen" ] || { echo "No encuentro $origen"; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# El bloque va entre dos marcas de comentario (INICIO / FIN filtros de imagen).
awk '/INICIO filtros de imagen/{d=1} d{print} /FIN filtros de imagen/{d=0}' "$origen" > "$tmp/filtros_extraido.inc"
[ -s "$tmp/filtros_extraido.inc" ] || { echo "No encuentro el bloque de filtros en $origen (¿está aplicado el parche 0004?)"; exit 2; }
g++ -std=c++17 -O2 -Wall -Wextra -I"$tmp" -o "$tmp/filtros_test" "$aqui/filtros_test.cpp"
"$tmp/filtros_test"
