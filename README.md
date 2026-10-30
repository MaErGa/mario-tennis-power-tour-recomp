# Mario Tennis: Power Tour — versión nativa para PC (GBA → PC)

Proyecto para ejecutar **Mario Tennis: Power Tour** (GBA, versión europea `BTMP`,
revisión 0) como programa nativo de PC. No es un emulador: el código ARM/Thumb
de la ROM se traduce a C++ por adelantado (*recompilación estática*) con el
framework [gbarecomp](https://github.com/mstan/gbarecomp) y se enlaza con un
runtime que reproduce el hardware de la GBA (vídeo, audio, DMA, temporizadores,
guardado). El menú de configuración es [recomp-ui](https://github.com/mstan/recomp-ui).

**No hace falta la BIOS de Nintendo.** El proyecto incluye una BIOS libre
(licencia MIT, [Cult-of-GBA](https://github.com/Cult-of-GBA/BIOS)). Lo único que
tienes que aportar es tu propia ROM.

## Estado

Comprobado en Linux (compilación desde cero con tu ROM, ejecución con ventana
virtual y sin ventana):

| Cosa | Estado |
|---|---|
| Verificar tu ROM por SHA-1 y recordarla (se elige una vez) | Funciona |
| Menú de arranque: ROM, mando, teclado, vídeo, audio | Funciona (en inglés) |
| Arranque con la BIOS libre | Funciona |
| **Los cinco idiomas** (inglés, alemán, francés, español, italiano): selección, aviso de salud, creación de personaje, introducción | **Funciona** en los cinco, también sin compilador en el equipo |
| Modo historia: habitación, diálogos, plaza, academia, restaurante y menús (Super Golpes, etc.) | Funciona en los cinco idiomas |
| **Partido de tenis** (Exhibición, Mario contra Peach) | **Funciona**: pista, saque y jugadores se mueven |
| Pantalla 3:2, 16:9 estirado y 16:9 con barras difuminadas | Funciona (ver «Pantalla») |
| Rendimiento | ≈ 110–120 fotogramas/s sin ventana en un equipo de 2 núcleos (el juego pide 59,7) |
| Audio | El juego genera sonido (comprobado: señal mezclada no silenciosa en un partido). **No se ha escuchado** (el entorno de pruebas no tiene tarjeta de sonido) |
| Torneos completos, minijuegos, multijugador por cable | **Sin comprobar** |
| `.exe` de Windows (compilación cruzada con MinGW) | Arranca bajo Wine; una partida nueva en español (la que se veía rota en Windows) sale idéntica a la de Linux |
| `INSTALAR.bat` en un Windows real (11), método antiguo con MSYS2 | La ventana, la comprobación del equipo y la detección de MSYS2 funcionaron; falló `pacman` por un bloqueo antiguo (`db.lck`), ya corregido |
| **Instalador ligero (sin MSYS2) y `ACTUALIZAR.bat`** | Probados de punta a punta en Linux con las mismas herramientas (Zig, CMake, Ninja) y PowerShell 7: instala, actualiza, y una actualización con un cambio pequeño tarda segundos. **Falta probarlos en un Windows real** |
| `CONSTRUIR.bat` / `JUGAR.bat` en un Windows real | **Sin probar** |

Es un proyecto en desarrollo: cuando el juego llega a código que el análisis
estático no vio, lo ejecuta con un intérprete y lo anota para añadirlo a
`game.toml` (ver «Cómo mejorarlo»). `game.toml` ya recoge unas 900 entradas
halladas jugando una partida nueva en los cinco idiomas, recorriendo menús y
escenarios y jugando un partido, de modo que el juego **no depende de tener un
compilador instalado** para verse bien. Solo se interpretan, a propósito, el
descompresor del juego y los módulos de código de EWRAM.

## Cómo usarlo

### Cuánto pesa

| | Tamaño |
|---|---|
| Descarga (Zig, CMake, Ninja, SDL2 y las fuentes) | ≈ 150 MB, una sola vez |
| Espacio libre que hace falta **mientras se instala** | ≈ 1,5 GB (compilar genera ≈ 1 GB; se borra al terminar) |
| **El juego instalado** | **≈ 55 MB** (incluye tu ROM de 16 MB) |
| Este zip | unos 0,1 MB |

Antes el instalador pedía 6 GB porque instalaba MSYS2 (un entorno de desarrollo
entero, ≈ 3 GB) solo para compilar. Ahora usa [Zig](https://ziglang.org/), que
trae el compilador en un único programa de 100 MB, y no instala nada en Windows:
todo lo temporal vive en una carpeta que se borra sola. Si falla el método ligero,
el instalador ofrece el clásico (MSYS2) como respaldo.

### Windows (instalador de PowerShell)

1. Descomprime el zip donde quieras (la ROM no hace falta ponerla dentro).
2. Haz doble clic en **`INSTALAR.bat`**. Se abre una ventana en la que eliges:
   - **tu ROM** europea de Mario Tennis: Power Tour (16 MiB, `.gba`). Si está en
     `roms\`, Descargas, Escritorio o Documentos, aparece ya rellenada. Se
     comprueba por tamaño y SHA-1, así que puede tener cualquier nombre;
   - **la carpeta donde instalar el juego** (por defecto
     `%LOCALAPPDATA%\Programs\Mario Tennis Power Tour`; puedes poner otra unidad);
   - si quieres accesos directos en el escritorio y en el menú Inicio.
   - si quieres **conservar los archivos de compilación** (≈ 1 GB) para que las
     actualizaciones sean mucho más rápidas (por defecto no: se borran).
3. Pulsa **Instalar** y espera. La primera vez tarda entre 20 y 60 minutos y
   necesita internet: descarga las herramientas ligeras (≈ 150 MB), recompila tu
   ROM, compila el juego y lo copia a la carpeta elegida **con tu ROM y la BIOS
   libre**. Hacen falta ≈ 1,5 GB libres mientras se compila; al terminar se borra
   lo temporal y el juego ocupa ≈ 55 MB.
4. Abre el juego desde el acceso directo (o `JUGAR.bat` de la carpeta). Aparece
   el menú: comprueba que pone «ROM verified», ajusta lo que quieras y pulsa
   **Play**.

El instalador no necesita ser administrador. Si ejecutas **`INSTALAR.bat` otra vez**
sobre la misma carpeta, reinstala el juego y **conserva tus partidas y ajustes**.

### Actualizar (sin instalar todo desde cero)

Cuando te llegue una versión nueva del proyecto (un zip nuevo), descomprímelo y haz
doble clic en **`ACTUALIZAR.bat`**. No te pregunta dónde está el juego ni tu ROM:

1. **Encuentra solo la instalación** (lista de «Aplicaciones» de Windows, carpeta por
   defecto, accesos directos y carpetas típicas de tus discos; si no la halla, te
   deja elegir la carpeta).
2. **Compara** la versión nueva con la instalada. Si no hay nada nuevo, te lo dice
   y no toca nada.
3. **Reutiliza tu ROM** (la que ya está en la carpeta del juego) y el mismo método
   con el que instalaste.
4. Reinstala **conservando tus partidas, ajustes y accesos directos**.

Si al instalar marcaste «Conservar los archivos de compilación», solo se
recompila lo que ha cambiado: un cambio pequeño tarda segundos y uno que toque
`game.toml` tarda menos que la primera vez, pero recompila casi todo. Sin
conservarlos, vuelve a descargar las herramientas y compila entero (20-60 min), pero
sigue sin pedirte nada. Opciones: `-Forzar` (reinstalar aunque sea la misma versión),
`-Destino <carpeta>`, `-Rom <ruta>`, `-Silencioso`, `-ConservarObra`.

(Es un `.bat` + `.ps1` y no un `.exe`: un `.exe` sin firmar digitalmente asusta
más a SmartScreen y al antivirus, y no aporta nada.)

### Icono de los accesos directos

Si dejas un archivo **`icono.ico`** junto a `INSTALAR.bat`, el instalador lo copia a la
carpeta del juego y lo usa en los accesos directos (escritorio y menú Inicio) y en
«Aplicaciones» de Windows. Si ya tienes el juego instalado, deja el `icono.ico` junto a
`ACTUALIZAR.bat` y ejecútalo: si el juego ya está al día, solo cambia el icono (sin
recompilar nada). No se incluye uno en el zip: la imagen del juego es de Nintendo y este
proyecto no distribuye recursos suyos. Sirve cualquier `.ico` con varios tamaños (16 a 256 px).
Un consejo: la portada entera se ve como una mancha a 16-32 px; un recorte de un personaje
(p. ej. la cara de Mario con la gorra) se reconoce mucho mejor. Ahora mismo el icono solo
afecta a los accesos directos y a «Aplicaciones»: la ventana del juego mientras corre (y su
botón en la barra de tareas) sigue con el icono genérico.

**Desinstalar:** «Aplicaciones» de Windows (aparece como *Mario Tennis Power
Tour*), el menú Inicio, o `Desinstalar.bat` en la carpeta del juego. Te
pregunta si quieres conservar tus partidas (`.sav`) y ajustes. Si usaste el
método clásico, no quita MSYS2 (el ligero no instala nada fuera de su carpeta).

Sin ventanas (consola o automatizado):

```powershell
powershell -ExecutionPolicy Bypass -File tools\INSTALAR.ps1 -Rom D:\roms\mtpt.gba -Destino E:\Juegos\MarioTennis -Silencioso
```

Parámetros: `-Rom`, `-Destino`, `-SinAccesos`, `-ConservarObra`, `-Silencioso`,
`-Metodo auto|ligero|msys2` (por defecto `auto`: ligero y, si falla, MSYS2),
`-Msys2 <carpeta>`. **`CONSTRUIR.bat`** compila dentro de la propia carpeta del
proyecto con el método ligero (crea `juego\`; la carpeta no puede tener espacios
ni acentos) y **`CONSTRUIR-MSYS2.bat`** hace lo mismo con el método clásico.

### Linux

Hacen falta `git`, `cmake`, `g++` (o `clang++`), `ninja` y las cabeceras de SDL2
(`sudo apt install build-essential cmake git ninja-build libsdl2-dev python3`).

```sh
tools/construir.sh /ruta/a/tu_rom.gba     # o deja la ROM en roms/ y no pases nada
cd juego && ./jugar.sh
```

El script comprueba la ROM, descarga gbarecomp y recomp-ui en las versiones
probadas, aplica los parches de `parches/`, recompila la BIOS libre y tu ROM,
compila y monta la carpeta `juego/` (ejecutable, `game.toml`, BIOS libre, tu ROM).
Desde cero, en el entorno de pruebas (2 núcleos), tarda unos 4 minutos.

## El menú de configuración

Se abre cada vez al ejecutar el juego (marca «Skip launcher on boot» para
saltarlo). Recuerda la ROM y la configuración junto al ejecutable (`rom.cfg`,
`config.ini`, `keybinds.ini`). Permite elegir mando o teclado y reasignar los
botones, escala de la ventana, pantalla completa, filtro de imagen, relación de
aspecto y volumen. El menú de recomp-ui solo está en inglés e italiano.

Opciones de línea de órdenes útiles: `--no-launcher` (arrancar sin menú),
`--launcher` (forzarlo), `--scale N`, `--fullscreen`, `--volume N`,
`--stretch` y `--blur-bars` (modos de pantalla, abajo).

### Pantalla: 3:2, 16:9 estirado y 16:9 con barras difuminadas

La GBA dibuja 240×160 (relación 3:2). En *Settings → Display → Aspect ratio*
hay tres modos:

| Modo | Qué hace |
|---|---|
| **3:2 (Native)** | La imagen original, sin deformar, con barras negras si la ventana es 16:9 |
| **16:9 (Stretched)** | La imagen se estira para llenar toda la ventana 16:9. Se ve ≈ 18 % más ancha de lo original |
| **16:9 (Blurred sides)** | La imagen 3:2 sin deformar y, en vez de negro, las barras laterales se rellenan con una copia muy difuminada y oscura de la propia imagen |

En los dos modos 16:9 la ventana se abre ya en 16:9 y se puede redimensionar;
en pantalla completa ocupan todo el monitor. El modo se elige al arrancar (para
cambiarlo hay que volver a abrir el juego).

**No hay un 16:9 «ampliado» de verdad** (ver más escenario a los lados): la GBA
solo dibuja 240 px de ancho y el juego no tiene contenido fuera de ellos; lo
probado con la vista ampliada del framework solo da márgenes negros. Se
descartó en lugar de ofrecer una opción que no aporta nada.

## Qué incluye y qué no

| Incluido | Licencia |
|---|---|
| Configuración del recompilador (`game.toml`), host (`src/`), scripts | Tuya al publicarlo |
| `parches/` (cambios a gbarecomp) | Los de gbarecomp: **PolyForm Noncommercial 1.0.0** |
| BIOS libre `bios_libre/` | MIT (Cult-of-GBA); ver `bios_libre/LICENSE-Cult-of-GBA-BIOS.txt` |

Ojo con la licencia: **gbarecomp es de uso no comercial** (PolyForm Noncommercial
1.0.0) y el juego que construyes lo enlaza, así que este proyecto es solo para
uso personal y sin ánimo de lucro. recomp-ui (el menú) es MIT.

**No se incluye ni se debe subir** la ROM, el código generado a partir de ella
(`generated/`), ni la carpeta `juego/`: derivan del juego de Nintendo. El
`.gitignore` ya los excluye. Cada persona construye el juego en su equipo con su
propio volcado.

## Estructura

```
INSTALAR.bat           Windows: abre el instalador (elige ROM y carpeta), con doble clic
ACTUALIZAR.bat         Windows: actualiza una instalación existente (la encuentra sola)
icono.ico              (opcional, lo pones tú) icono de los accesos directos
VERSION                Número de versión del proyecto (lo lee ACTUALIZAR)
tools/INSTALAR.ps1     El instalador de PowerShell (ventana, método ligero + respaldo MSYS2, accesos)
tools/ACTUALIZAR.ps1   El actualizador (detecta la instalación, compara, reinstala)
tools/comun.ps1        Funciones compartidas (ROM, búsqueda de instalación, huella de versión)
tools/construir.ps1    Compilación ligera de Windows: Zig + CMake + Ninja + SDL2, sin git ni MSYS2
tools/DESINSTALAR.ps1  El desinstalador (se copia a la carpeta del juego)
CONSTRUIR.bat          Windows: compila dentro de la carpeta del proyecto (método ligero)
CONSTRUIR-MSYS2.bat    Windows: lo mismo con el método clásico (MSYS2)
tools/construir.sh     Compilación en Linux (y la del método clásico en Windows)
tools/aplicar_parches.py   Aplica parches/*.patch a gbarecomp (idempotente)
tools/fusionar_fallos.py   Añade a game.toml las entradas que el runtime encontró
tools/JUGAR.bat, jugar.sh  Lanzadores que se copian a juego/
game.toml              Configuración del recompilador y del runtime
src/main.cpp           Host: ganchos de RAM, identidad del cartucho, modos de pantalla
src/game_launcher_boot.*   Puente con el menú de arranque (recomp-ui)
parches/               Cambios mínimos a gbarecomp (se aplican solos)
bios_libre/            BIOS libre (MIT) y su configuración
docs/ESTADO.md         Estado detallado y hallazgos (leer al retomar)
docs/NOTAS_TECNICAS.md Cómo funciona por dentro
```

## Cómo mejorarlo

1. Juega y cierra el juego con normalidad: el runtime escribe
   `recomp_master_misses_BTMP.toml.frag` junto al ejecutable con las direcciones
   que tuvo que interpretar.
2. `python3 tools/fusionar_fallos.py game.toml juego/recomp_master_misses_BTMP.toml.frag`
   añade a `game.toml` las entradas fiables.
3. Vuelve a ejecutar `tools/construir.sh` (o `CONSTRUIR.bat`).

Si algo falla en tu equipo, `GBARECOMP_SELFHEAL_VERBOSE=1` imprime el detalle por
dirección. Si tienes `gcc` en el `PATH`, el runtime compila en caliente (carpeta
`recomp_cache/`) las funciones que faltan y las reutiliza en el siguiente
arranque; sin compilador usa el intérprete, que va algo más lento pero funciona.

## Proyectos relacionados

- [gbarecomp](https://github.com/mstan/gbarecomp) y [recomp-ui](https://github.com/mstan/recomp-ui):
  el framework y el menú (commits fijados en `tools/construir.sh` y `tools/construir.ps1`).
- [Zig](https://ziglang.org/) (compilador de C/C++ del método ligero), CMake, Ninja y SDL2.
- [Cult-of-GBA/BIOS](https://github.com/Cult-of-GBA/BIOS): la BIOS libre.
- [mtp-eu-decomp](https://github.com/DanielBenGD/mtp-eu-decomp): decompilación de
  esta misma revisión, en fase inicial. Sus nombres de función podrán servir
  de semillas.

## Aviso legal

Proyecto no oficial de ingeniería inversa para preservación y estudio. *Mario*,
*Mario Tennis*, Nintendo y Camelot son marcas de sus propietarios. Este
repositorio no contiene ROMs, BIOS de Nintendo ni recursos del juego, y no debe
usarse para distribuirlos.
