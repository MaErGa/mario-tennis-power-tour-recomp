# Cómo colaborar

Gracias por echar una mano. Este es un proyecto personal y sin ánimo de lucro; cualquier
ayuda (arreglos, pruebas en Windows, traducciones, ideas) es bienvenida.

## La regla que no se negocia

**No subas ni adjuntes nunca**: la ROM, la BIOS de Nintendo, capturas o vídeos con
recursos del juego que sustituyan a tenerlo, el código generado a partir de la ROM
(`generated/`), ni el ejecutable ya compilado (`juego/`, `build/`). Las incidencias o
*pull requests* que los incluyan se cerrarán y se borrará el contenido. El `.gitignore`
ya los excluye: no lo desactives.

Una captura de pantalla para explicar un fallo está bien. No pidas ni ofrezcas ROMs.

## Antes de abrir una incidencia

- Indica tu **versión de Windows** (o Linux), el contenido de `VERSION` y qué método de
  instalación usaste (ligero o MSYS2).
- Adjunta el registro del instalador: **`%TEMP%\mario-tennis-instalador.log`**
  (pégalo en la incidencia; no contiene tu ROM).
- Si el fallo es del juego, di en qué pantalla, en qué idioma y qué filtro/aspecto tenías.

## Probar los cambios

Todo lo que se pueda probar sin Windows tiene una prueba automática:

```sh
# Filtros de imagen: hace falta una copia de gbarecomp (el commit de tools/construir.sh)
# con los parches aplicados; el script extrae el bloque de filtros y lo prueba con g++.
# (Los parches de recomp-ui se aplican igual sobre su carpeta: la carpeta debe llamarse
# «recomp-ui», porque el nombre decide qué parches le tocan.)
python3 tools/aplicar_parches.py <carpeta de gbarecomp>
bash tools/pruebas/probar_filtros.sh <carpeta de gbarecomp>

# Herramienta de partidas, carpeta de compilación y desinstalador (necesitan PowerShell 7)
pwsh tools/pruebas/probar_partidas.ps1
pwsh tools/pruebas/probar_obra.ps1
pwsh tools/pruebas/probar_desinstalar.ps1
```

Comprobaciones rápidas de sintaxis (también las pasa GitHub Actions):

```sh
for f in tools/*.sh tools/pruebas/*.sh; do bash -n "$f"; done
python3 -m py_compile tools/*.py
pwsh tools/pruebas/comprobar_sintaxis.ps1     # sintaxis de los .ps1 y que lleven BOM
```

GitHub Actions ejecuta lo mismo en cada *pull request*.

## Normas de estilo

- **Idioma:** comentarios, textos de la interfaz y nombres de variables en **español de
  España** (tuteo: «elige», «pulsa»; sin voseo). Los textos del menú de recomp-ui se
  traducen con los parches `recomp-ui-NNNN-*.patch` (tabla `kSpanish[]`); si añades un texto
  nuevo, mételo ahí y comprueba con `MTP_I18N_DEBUG=1` que no queda ninguno sin traducir.
- **Scripts de PowerShell:** guardados en UTF-8 **con BOM** y finales de línea CRLF (así
  los lee bien Windows PowerShell 5.1). El `.gitattributes` fuerza el CRLF; el BOM ya lo
  llevan los archivos, así que no lo quites al editarlos.
- **Parches** (`parches/gbarecomp-NNNN-*.patch` y `parches/recomp-ui-NNNN-*.patch`, uno por
  proyecto de `externo/`): se aplican en orden por nombre, tanto con
  `git apply` como con el aplicador de `tools/construir.ps1`, que **solo entiende cambios
  en archivos existentes**, no archivos nuevos. Si necesitas código nuevo, ponlo dentro de
  un archivo ya existente, entre marcas claras (mira cómo lo hace el parche 0004).
- Cualquier cambio en `parches/`, `src/`, `game.toml`, `CMakeLists.txt`, `bios_libre/` o
  `tools/construir.*` cambia la huella de la versión y hace que `ACTUALIZAR.bat` reinstale.
  Sube el número de `VERSION` y anótalo en `CHANGELOG.md`.
- Cambios pequeños y con una prueba, cuando se pueda.

## Licencia de lo que aportes

Al enviar un cambio aceptas que se publique bajo la licencia del proyecto
(**PolyForm Noncommercial 1.0.0**, ver `LICENSE`), igual que gbarecomp, del que depende.
