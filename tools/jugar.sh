#!/usr/bin/env bash
# Arranca Mario Tennis: Power Tour (recomp). Abre el menú de configuración.
# Funciona desde cualquier carpeta y también a través de un enlace simbólico o del menú de aplicaciones.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec ./MarioTennisPowerTourRecomp "$@"
