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

## Descargar

Ve a la pestaña **[Releases](https://github.com/MaErGa/MarioTennisPowerTourRecomp/releases)** y baja
`MarioTennisPowerTourRecomp-X.Y.Z.zip` (equivale al «Source code (zip)» de GitHub). Descomprímelo y haz
doble clic en **`INSTALAR.bat`** (Windows) o, en **Linux**, ejecuta **`bash tools/instalar.sh`**: el instalador
compila el juego **en tu PC con tu propia ROM** (ver «Cómo usarlo»). Aquí **no hay `.exe` ni ROM** para bajar: el programa contiene el código del juego
traducido y por eso no se puede publicar; cada persona lo construye con su propio volcado. Si ya lo
tienes instalado, descomprime la versión nueva y usa `ACTUALIZAR.bat` (Windows) o `bash tools/actualizar.sh` (Linux); el menú te avisa cuando hay una.

## Estado

Comprobado en Linux (compilación desde cero con tu ROM, ejecución con ventana
virtual y sin ventana):

| Cosa | Estado |
|---|---|
| Verificar tu ROM por SHA-1 y recordarla (se elige una vez) | Funciona |
| Menú de arranque: ROM, mando, teclado, vídeo, audio | Funciona, **en español** (también la asignación de controles, los atajos, los modelos de pantalla y el explorador de archivos) |
| **Menú del juego (Esc) en español** | **Funciona**: pantalla, gráficos, sonido y sistema, con tildes y ñ; comprobado con capturas de la ventana real (a 100 % y simulando un 150 %) |
| **Selector «Idioma del menú» (Español / English)** | **Funciona** en el menú de arranque y en el de Esc: cambia al instante, se guarda en `config.ini` y no toca el idioma del juego. Comprobado con capturas de la ventana real |
| **Captura de pantalla (F10)** | **Funciona**: guarda un PNG de la imagen del juego, sin filtros, en la carpeta `capturas` (también en pausa). Comprobado en Linux y **en un Windows real** (16-nov-2026: capturas del juego en español hechas con F10; si se pulsa dos veces en el mismo segundo, la segunda lleva `_2`) |
| **Visor de capturas en el menú** (botón «Capturas») | **Funciona**: rejilla de miniaturas, vista grande con Anterior/Siguiente, borrar (con confirmación) y abrir carpeta. Comprobado con capturas de la ventana real en Linux (rejilla, vista grande, carpeta vacía, imagen dañada, español e inglés); «Abrir carpeta» y el manejo solo con teclado/mando **sin probar** |
| **Aviso de versión nueva al abrir el menú** | **Funciona en Linux** (12 pruebas con un servidor local); la descarga de Windows (WinHTTP) está compilada pero **sin probar en un Windows real**. Se apaga con `[Menu] CheckUpdates = 0` |
| **Perfil por mando** (recordar tus botones) | Lo trae recomp-ui («Guardar/Renombrar/Borrar perfil»), traducido desde 0.4.3; **sin probar con un mando físico** |
| **Imagen nítida con el escalado de Windows (125 %, 150 %…)** | El programa se declara consciente del DPI y ajusta la ventana en múltiplos enteros; el menú de Esc crece con el texto (0.4.2). Visto funcionando en un Windows real; el último ajuste del menú se comprobó simulando factores 1,5 y 2,0 |
| Arranque con la BIOS libre | Funciona |
| **Los cinco idiomas** (inglés, alemán, francés, español, italiano): selección, aviso de salud, creación de personaje, introducción | **Funciona** en los cinco, también sin compilador en el equipo |
| Modo historia: habitación, diálogos, plaza, academia, restaurante y menús (Super Golpes, etc.) | Funciona en los cinco idiomas |
| **Partido de tenis** (Exhibición, Mario contra Peach) | **Funciona**: pista, saque y jugadores se mueven |
| Pantalla 3:2, 16:9 estirado y 16:9 con barras difuminadas | Funciona (ver «Pantalla») |
| **Filtros de imagen** (9: Scale2x/3x/4x, rejilla LCD de la GBA, CRT, «HD smooth»…) | **Funciona**: se eligen en el menú de arranque o **en directo con F12** (se guarda), y se comprobaron con capturas de la ventana real (ventana, pantalla completa y los tres modos de aspecto) con OpenGL y con Direct3D 9 (Wine); pruebas automáticas de cada filtro. La rejilla LCD y las líneas CRT se calculan por CPU sobre la imagen final, así que no dependen de la tarjeta gráfica. **Sin probar con una tarjeta gráfica real en Windows (Direct3D 11)** |
| **Avance rápido (Tab)** | Salta el dibujado de los fotogramas intermedios y no espera entre ellos: va todo lo rápido que permita tu equipo, hasta el multiplicador (×4 por defecto). El título de la ventana muestra la velocidad real y el coste de emular/dibujar (`turbo x2.4 \| 31 img/s \| emu 4.1 ms \| dib 9.7 ms`). Sin parpadeos (0 de ≈ 4.000 capturas). **Sin medir en un Windows real** |
| **Partidas de emuladores** (`.sav` de 32 KiB) y herramienta `PARTIDAS.bat` | El juego carga y recorta un `.sav` con relleno (probado con el juego compilado) y la herramienta pasa sus pruebas con PowerShell 7 en Linux. **Sin probar:** en un Windows real y con una partida jugada de verdad |
| Rendimiento | ≈ 110–120 fotogramas/s sin ventana en un equipo de 2 núcleos (el juego pide 59,7) |
| Audio | El juego genera sonido (comprobado: señal mezclada no silenciosa en un partido). **No se ha escuchado** (el entorno de pruebas no tiene tarjeta de sonido) |
| **Jugar online con un amigo por código de invitación** (0.5.0, **experimental**) | Pantalla «En línea» del menú: crear sala, pasaros dos códigos, nombres para identificaros y la partida arranca sola. Comprobado en Linux con dos instancias reales del juego (se conectan, acuerdan el arranque y avanzan miles de ticks por las pantallas de idioma y de elección de personaje), el protocolo con routers NAT simulados (Linux) y la interfaz entera con ventana virtual. **Sin probar:** entre dos casas por internet de verdad, en Windows, **un partido completo en línea** y sesiones largas (ver «Jugar online con un amigo») |
| **Estados con nombre, rebobinar y avance rápido ajustable** (0.7.0) | Comprobados en Linux con la ROM real (ventana virtual): guardar y cargar con F1–F9 y desde el menú, avisos en pantalla, nombres (también con ñ) que sobreviven a reiniciar, rebobinar con **1** (varios saltos seguidos), avance rápido con **2** a 4× y fijado desde el menú a 6× (se ve en el título). **Sin comprobar:** con un mando de verdad (gatillos), en Windows, con el audio (en el avance rápido se silencia) y una partida larga rebobinando |
| Torneos completos, minijuegos, multijugador por cable (sin red) | **Sin comprobar** |
| `.exe` de Windows (compilación cruzada con MinGW) | Arranca bajo Wine; una partida nueva en español (la que se veía rota en Windows) sale idéntica a la de Linux |
| `INSTALAR.bat` en un Windows real (11), método antiguo con MSYS2 | La ventana, la comprobación del equipo y la detección de MSYS2 funcionaron; falló `pacman` por un bloqueo antiguo (`db.lck`), ya corregido |
| **Linux: `tools/instalar.sh`, `actualizar.sh` y `desinstalar.sh`** (0.6.0) | **Funcionan** en Ubuntu 24.04 con tu ROM, de punta a punta: comprueba las herramientas (y se ofrece a instalar las que falten), verifica la ROM, compila (≈ 9 min en 2 núcleos), instala en la carpeta que elijas, crea la entrada del menú de aplicaciones (y, si quieres, el acceso del Escritorio), el juego arranca desde ese acceso y llega a la pantalla de idiomas; actualizar sin cambios no hace nada y con `--forzar` tarda 15 s reutilizando lo compilado sin tocar tus partidas ni ajustes; desinstalar conserva tus datos o lo borra todo. Más 62 comprobaciones automáticas en un HOME aislado. **Sin probar:** otras distribuciones, escritorios distintos del de las pruebas (GNOME, KDE…), tarjeta gráfica y sonido reales (PipeWire/PulseAudio), mando |
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
| Espacio libre que hace falta **mientras se instala** | ≈ 1,5 GB en **cualquier** unidad: normalmente `C:`, y si va justa se usa la del juego u otra con sitio (compilar genera ≈ 1 GB; se borra al terminar) |
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

**Instalador (lo recomendado).** Descomprime el zip y, dentro de esa carpeta:

```sh
bash tools/instalar.sh
```

Te va preguntando lo necesario (con `--ayuda` salen todas las opciones):

1. Mira si tienes `git`, `cmake`, `ninja`, `python3`, un compilador de C++ y las cabeceras de SDL2. Si
   falta algo, te dice la orden exacta para tu distribución (`apt`, `dnf`, `pacman` o `zypper`) y te
   ofrece ejecutarla (pide tu contraseña con `sudo`; con `--instalar-dependencias` no pregunta).
2. Busca tu ROM europea (en `roms/`, la carpeta actual, Descargas, Documentos, Escritorio…) o te pide la
   ruta; la comprueba por SHA-1. **La ROM no viene con el proyecto.**
3. Te pregunta en qué carpeta instalar (por defecto `~/.local/share/MarioTennisPowerTour`; los espacios
   en la ruta no dan problema), si quieres además un acceso en el Escritorio y si conservas los archivos
   de compilación (≈ 700 MB) para que actualizar sea mucho más rápido.
4. Compila en una carpeta temporal (`~/.cache/MarioTennisPowerTour-obra`), copia el juego a su carpeta,
   crea la entrada **«Mario Tennis Power Tour»** del menú de aplicaciones (Categoría *Juegos*; usa un icono
   genérico del tema: aquí no se distribuye arte del juego) y deja un `desinstalar.sh` junto al juego.

Sin preguntas: `bash tools/instalar.sh --rom ~/roms/mtpt.gba --destino ~/Juegos/MarioTennis --silencioso`.
Necesita unos 2 GB libres para compilar (se borran al terminar, salvo que los conserves) y ≈ 300 MB para
el juego. En el equipo de pruebas (2 núcleos, 8 GB) tarda unos 9 minutos; cada proceso del compilador
puede usar más de 1 GB de RAM, así que se limitan según la memoria libre (`MTP_NUCLEOS=1` si te quedas
sin ella). El registro completo queda en `~/.cache/MarioTennisPowerTour-instalador.log`.

**Actualizar:** descomprime la versión nueva y ejecuta `bash tools/actualizar.sh`. Encuentra solo dónde
lo instalaste (por la entrada del menú o la carpeta por defecto; si no, `--destino`), no hace nada si ya
tienes esa versión (`--forzar` lo reinstala igualmente), reutiliza la ROM ya instalada y **conserva tus
partidas, estados, capturas y ajustes**. Si conservaste los archivos de compilación, tarda segundos.
**Desinstalar:** `~/.local/share/MarioTennisPowerTour/desinstalar.sh` (te pregunta si conservas tus
partidas y ajustes; `--silencioso` los conserva, `--borrar-todo` lo quita todo). Tu ROM original nunca se toca.

**Sin instalador** (compilar dentro de la propia carpeta, para desarrollar):

```sh
bash tools/construir.sh /ruta/a/tu_rom.gba     # o deja la ROM en roms/ y no pases nada
cd juego && ./jugar.sh
```

Descarga gbarecomp y recomp-ui en las versiones probadas, aplica los parches de `parches/`, recompila la
BIOS libre y tu ROM, compila y monta la carpeta `juego/`.

Cosas de Linux a tener en cuenta:

- **Selector de archivos:** si tienes `zenity` o `kdialog`, el menú los usa; si no, usa su explorador
  integrado (el botón «Buscar ROM (integrado)»), así que no es obligatorio.
- **Aviso de versión nueva:** usa `curl` si está instalado; sin él, simplemente no avisa.
- **Mando:** SDL2 lo reconoce solo; si no responde, mira los permisos de `/dev/input` de tu distribución.
- **Pantalla y sonido:** SDL2 usa X11 o Wayland (XWayland) y PipeWire, PulseAudio o ALSA. Solo se ha
  probado con una pantalla virtual y sonido de prueba: si algo no sale, abre un *issue* con tu distribución y escritorio.
- **Juego online:** necesita poder enviar y recibir UDP. La conexión sale desde tu propio puerto, así que
  con `ufw` o `firewalld` normalmente no hay que abrir nada (**no probado** con ellos); un NAT simétrico o
  un CGNAT sí lo impiden (ver «Jugar online con un amigo»).

## El menú de configuración

Se abre cada vez al ejecutar el juego (marca «Saltar el lanzador al arrancar» para
saltarlo). Recuerda la ROM y la configuración junto al ejecutable (`rom.cfg`,
`config.ini`, `keybinds.ini`). Permite elegir mando o teclado y reasignar los
botones, escala de la ventana, pantalla completa, filtro de imagen, modelo de
pantalla (el filtro de color de la GBA), relación de aspecto y volumen. Tanto este menú
como el del juego (Esc) están en **español** o en **inglés**, a tu elección: la fila
**«Idioma del menú»** (Español / English) está en los ajustes de este menú (al final del
panel de pantalla) y en el menú de Esc (sección Sistema, la última fila). Cambia al instante,
se recuerda en `config.ini` (`[Menu]`, `Language`) y **solo afecta a los menús**: el idioma del
juego se elige dentro del juego, como siempre. Sin elegir nada, el menú sale en español.

Opciones de línea de órdenes útiles: `--no-launcher` (arrancar sin menú),
`--launcher` (forzarlo), `--scale N`, `--fullscreen`, `--volume N`,
`--stretch` y `--blur-bars` (modos de pantalla, abajo) y `--image-filter N` (filtro de
imagen, abajo).

### Atajos de teclado

| Tecla | Qué hace |
|---|---|
| Flechas | Moverse |
| **X** / **Z** | Botón A / botón B |
| **C** / **V** | Botón L / botón R |
| **Intro** | Start |
| **Mayús derecho** | Select |
| **Mayús + F1…F9** | **Guardar estado** en la ranura 1–9 (sale un aviso con la ranura y su nombre) |
| **F1…F9** | **Cargar estado** de esa ranura |
| **Tab** (mantener) | Avance rápido (turbo) |
| **F12** / **Mayús + F12** | Siguiente / anterior **filtro de imagen**, en directo (el nombre sale unos segundos en el título y se guarda) |
| **F10** | **Captura de pantalla** (PNG en la carpeta `capturas`) |
| **Mayús + P** | Pausa |
| **Alt + Intro** | Pantalla completa |
| **F** | Fotogramas por segundo en el título de la ventana |
| **Esc** | Menú del juego, en español (pantalla, gráficos, sonido, sistema, herramientas, estados guardados, salir) |
| **1** (mantener) | **Rebobinar**: vuelve 1 s atrás cada medio segundo, hasta 30 s (también con el gatillo izquierdo del mando) |
| **2** (mantener) | **Avance rápido** (también con el gatillo derecho); con `Esc → Herramientas` se puede fijar |

Los estados (F1–F9) se guardan junto al juego como `roms/mario_tennis_power_tour_eur.state1`
… `state9` y son **independientes de las partidas normales** (guardar dentro del juego, el
`.sav`). Cada uno puede llevar un **nombre** (`Esc → Estados guardados`, Intro sobre la ranura; sin nombre
se ve la fecha del guardado); se apunta en `…stateN.info`. Un estado solo se carga con **la misma ROM**
con la que se guardó (el juego lo comprueba por su SHA-1; si no, sale «No se pudo cargar el estado»).

Los atajos del sistema se pueden cambiar en `config.ini`, sección `[KeyMap]`
(`Fullscreen`, `Pause`, `Turbo`, `WindowBigger`, `WindowSmaller`, `VolumeUp`, `VolumeDown`,
`DisplayPerf`, `ImageFilterNext`, `ImageFilterPrev`, `Screenshot`); los botones del juego, en el menú de
arranque o en `keybinds.ini`.

### Capturas de pantalla (F10)

**F10** guarda la imagen del juego (sin filtros, sin barras y sin menús) como PNG en la
carpeta `capturas`, junto a `config.ini`: `MarioTennis_2026-11-12_10-30-00.png`. Se amplía
con vecino más cercano hasta unos 720 píxeles de alto como mínimo (1200×800 en 3:2), con los
píxeles nítidos, y pesa unos 70 KB. Funciona también con el juego en pausa; con el menú de Esc
abierto no, ciérralo antes. El título de la ventana confirma «captura guardada». La tecla se
cambia en `config.ini`, `[KeyMap]`, `Screenshot = F11` (por ejemplo). El desinstalador
conserva esa carpeta si eliges conservar tus partidas.

### Visor de capturas (en el menú)

El botón **«Capturas»** de la cabecera del menú de arranque abre una rejilla con las capturas
de la carpeta `capturas` (las 150 más recientes, la última primero; el nombre del archivo
`MarioTennis_2026-11-14_17-32-05.png` se enseña como «14/11/2026  17:32:05»). Pulsa una para verla grande;
desde ahí: **Anterior / Siguiente**, **Borrar** (pulsa dos veces: la primera lo arma y el botón
pasa a «¿Borrar? Pulsa otra vez»), **Abrir carpeta** (abre `capturas` en el explorador) y
**Cerrar** (vuelve a la rejilla). Las miniaturas se hacen al vuelo, de dos en dos y solo las que
se ven, y se liberan al salir; una imagen que no se pueda leer sale con un aviso en lugar de
romper el menú. Solo lee la carpeta `capturas` que
hay junto a `config.ini`.

### Aviso de versión nueva

Al abrir el menú de arranque, el programa pide **una vez** y en segundo plano el archivo `VERSION`
del repositorio (una petición `GET` por HTTPS de unos pocos bytes; no envía nada tuyo). Si el
número es mayor que el instalado, sale una franja arriba con «Hay una versión nueva: 0.6.1 (tienes la 0.6.0)…» y un
botón **Ocultar** (solo en la pantalla de inicio del menú). Es **solo un aviso**: no descarga ni instala nada; para actualizar descarga el
zip nuevo y usa `ACTUALIZAR.bat` (ver arriba). Sin internet, con la dirección caída o con una
respuesta que no sea un número de versión, simplemente no sale nada.

En `config.ini`, sección `[Menu]`:

```ini
[Menu]
CheckUpdates = 0                      ; desactiva la comprobación (por defecto 1)
UpdateUrl = https://…/VERSION         ; otra dirección del archivo VERSION
```

La dirección por defecto se fija al compilar (`-DMTP_URL_VERSION=…`, por defecto el `VERSION` de la
rama `main` de `MaErGa/MarioTennisPowerTourRecomp` en `raw.githubusercontent.com`); si publicas el
proyecto con otro nombre o rama, cámbiala ahí o en `UpdateUrl`. Solo se aceptan direcciones
`https://` (y `http://` hacia `127.0.0.1`/`localhost`, para pruebas). La variable de entorno
`MTP_URL_VERSION` manda sobre `config.ini`.

### Avance rápido (Tab)

Mientras **mantienes pulsada la tecla Tab** el juego va más deprisa (sin sonido). El
multiplicador máximo va de 2 a 10 (por defecto 4) y se cambia en `config.ini`, sección
`[Launcher]`, `assist_fast_forward_multiplier`. La tecla se puede cambiar en la sección
`[KeyMap]` (línea `Turbo`).

Cómo funciona (0.3.3): los fotogramas que no se dibujan **ni siquiera se pintan por
dentro** (es lo que más tiempo cuesta) y el programa no espera entre ellos. El juego va
**todo lo rápido que permita tu equipo, hasta N veces la velocidad normal**, y las
imágenes que se dibujan se reparten según lo que cueste dibujar en tu equipo (entre 60 y
≈ 15 por segundo).

**Mientras mantienes Tab, el título de la ventana muestra lo que está pasando**, por
ejemplo `turbo x2.4 | 31 img/s | emu 4.1 ms | dib 9.7 ms`:

- `x2.4`: velocidad real del juego respecto a la normal. Si pone `x4.0` (o tu multiplicador)
  va al máximo permitido; sube el multiplicador en `config.ini` si quieres más.
- `img/s`: imágenes dibujadas por segundo. **Es normal que baje** con turbo: se dibujan
  menos imágenes precisamente para que el juego vaya más deprisa. El contador de la tecla
  **F** muestra lo mismo (imágenes dibujadas, no velocidad del juego).
- `emu`: milisegundos que cuesta emular un fotograma en tu equipo (el límite del turbo es
  ≈ 16,7 ms ÷ `emu` veces la velocidad normal). `dib`: lo que cuesta dibujar una imagen más.

Si el turbo no sube de `x1.0`–`x1.5`, abre un *issue* con una captura del título.

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

### Filtros de imagen y color

Hay **dos cosas independientes** que se pueden combinar, las dos en *Settings → Display*:

**Texture filtering** (el filtro de imagen; se calcula por CPU sobre el fotograma ya
terminado y no toca la emulación):

| N | Filtro | Qué hace |
|---|---|---|
| 0 | Nearest | Píxeles cuadrados, sin suavizar |
| 1 | Linear | Suavizado de la tarjeta gráfica (borroso al ampliar; es el único que **sí** emborrona a propósito) |
| 2 | Sharp fractional | Amplía cada píxel un número entero de veces y deja el último ajuste a la tarjeta: nítido aunque la ventana no sea múltiplo de 240×160 |
| 3 / 4 / 5 | Scale2x / Scale3x / Scale4x | Ampliadores de píxel-art (AdvMAME): suavizan diagonales y curvas sin emborronar el texto. El resultado se replica un número entero de veces más para que el ajuste final a la ventana sea mínimo y los bordes sigan nítidos |
| 6 | HD smooth | Scale4x con un suavizado muy ligero (cada vecino pesa solo el 12,5 %): bordes redondeados y limpios, sin el aspecto de «foto desenfocada» |
| 7 | LCD grid (GBA) | La rejilla de píxeles de la pantalla de la GBA original, dibujada **a la resolución de tu ventana** (rayas de 1 píxel nítidas), no sobre una imagen ampliada. Es el filtro más fácil de reconocer: una cuadrícula oscura entre los píxeles |
| 8 | CRT scanlines | Líneas de barrido (centro del haz brillante, bordes más oscuros), también a la resolución de la ventana |

**Cambiar de filtro sin reiniciar:** **F12** pasa al siguiente y **Mayús + F12** al anterior;
el nombre aparece unos segundos en el título de la ventana (en pantalla completa no se ve
el título, pero sí el efecto) y queda guardado en `config.ini` para la próxima vez. En el
menú del juego (**Esc**) hay un interruptor «Linear filter»: activa el filtro 1 (Linear) o
el 0 (Nearest); para los demás usa F12 o el menú de arranque.

Qué esperar de cada uno a 3× (720×480): **7 y 8 se notan a primera vista** (cuadrícula y
rayas). **3, 4, 5 y 6 son sutiles a propósito**: solo redondean diagonales y curvas, y en
un juego con tanto color plano y tanto sprite grande la diferencia es pequeña; compáralos
pulsando F12 con el 0. Si no ves **ninguna** diferencia entre el 0 y el 7, cuéntalo en una
incidencia con el texto del título y el tamaño de ventana.

La rejilla LCD y las líneas CRT oscurecen la imagen; el programa sube un poco el brillo de
origen para compensarlo (hasta un 40 %). Se calculan **por CPU sobre la imagen final** (no
usan mezclas de la tarjeta gráfica, así que se ven igual con OpenGL, Direct3D o el
*renderer* por software). **Límites:** si la imagen en pantalla tiene menos de 2 píxeles
de ventana por píxel del juego (ventana menor de 480×320) la rejilla/líneas no se dibujan,
porque no se verían; por encima de 1920×1080 (1440p, 4K a pantalla completa…) se calculan
a la mitad de resolución (o un tercio, etc.) y se estiran, con rayas de 2 píxeles o más.

**Escalado de Windows (125 %, 150 %…):** desde la 0.4.0 el programa se declara consciente
del DPI, así que Windows ya no estira la ventana y la rejilla y las líneas se ven nítidas.
Para que la ventana no salga más pequeña, la escala que eliges se multiplica por el factor
de Windows y se redondea a un entero que quepa en tu pantalla (escala 3 al 150 % → 4×; en el
menú del juego, «Window scale» muestra el valor real). Si prefieres el comportamiento
antiguo: variable de entorno `SDL_WINDOWS_DPI_AWARENESS=unaware`. Una captura de un Windows real
(ventana a escala 6) confirmó que el programa es consciente del DPI y que el menú sale en español;
también destapó que el panel del menú de Esc no crecía con el texto, corregido en la 0.4.2
(comprobado simulando factores de 1,5 y 2,0, aún no en ese Windows). Si ves algo raro, cuéntalo.

**Screen model** (el filtro de color de la GBA, que ya traía el framework): Raw, Unlit,
Frontlit, Backlit o Classic simulan cómo se veían los colores en las distintas
pantallas de la consola. Se combina con cualquiera de los filtros de arriba y con los
tres modos de aspecto.

También por línea de órdenes: `--image-filter N` (0 a 8); se guarda en `config.ini`
(`image_filter` en `[Launcher]`). El programa lo pasa al runtime con la variable de
entorno `GBARECOMP_FILTRO`.

Lo que **no** hay:
- **No se cargan *shaders* de RetroArch** (`.glsl`, `.glslp`): la presentación usa
  `SDL_Renderer`, que no tiene cauce de *shaders*. Por eso los filtros van por CPU y
  vienen incluidos.
- **«HD» son ampliadores, no texturas nuevas.** No hay paquetes de texturas ni de texto
  en alta resolución: el juego dibuja a 240×160 con fondos y *sprites*, y sustituirlos
  exigiría un trabajo artístico que no existe. Lo que se consigue es que el texto y los
  bordes se vean limpios al ampliar.

### Partidas: compatibles con las de los emuladores

El juego guarda en una **SRAM de 32 KiB**, y su archivo `.sav` es esa memoria tal cual
(el mismo formato que mGBA, VisualBoyAdvance-M, RetroArch —que lo llama `.srm`—,
BizHawk, no$gba y los flashcarts). Está junto a la ROM
(`roms\mario_tennis_power_tour_eur.sav` dentro de la carpeta del juego).

- **Desde el menú de arranque (0.4.5):** pulsa **«Partidas»** en la cabecera del menú que sale
  antes de empezar el juego. Ahí tienes *Importar de un emulador…*, *Exportar a un emulador…*,
  *Hacer copia ahora*, *Abrir carpeta* y la lista de copias de seguridad con *Recuperar*. Elige
  el archivo con el selector del sistema (o el explorador integrado), el menú lo comprueba y te
  pide confirmar; antes de sustituir tu partida guarda una copia en `copias-de-partidas`
  (junto a `config.ini`). Está en el menú de arranque y no en el menú de `Esc` de dentro del
  partido a propósito: con el juego en marcha, al cerrarse volvería a guardar encima de la
  partida importada.
- **Traer una partida de un emulador (a mano):** copia su archivo `.sav` (o `.srm`) con ese nombre
  sobre el de aquí, o usa **`PARTIDAS.bat`** (en el menú Inicio: *Partidas de Mario Tennis
  Power Tour*), que lo hace guardando antes una copia de la tuya.
- **Llevar tu partida a un emulador:** *Partidas* → *Exportar a un emulador…* (o `PARTIDAS.bat` →
  *Exportar*). Para mGBA y VBA el archivo debe llamarse como la ROM de ese emulador, pero con la
  extensión `.sav` (RetroArch: `.srm`).
- Si el archivo viene con **relleno o repetido hasta 64 o 128 KiB**, el juego lo recorta a
  los 32 KiB reales al cargarlo, anota el aviso en la consola y deja una copia
  `.sav.original`. Si lo que sobra son datos distintos (otro tipo de guardado u otro
  juego), no lo toca y te avisa.
- **Los estados rápidos de un emulador (*save states*) no se pueden importar:** son
  volcados de la memoria de *ese* emulador. Usa la partida normal del juego. Este
  programa tiene sus propios estados con **F1–F9** (formato propio, no intercambiable).
- `PARTIDAS.bat` también hace **copias de seguridad** y las **restaura**. Antes de
  importar comprueba el archivo: rechaza los estados rápidos, los archivos vacíos y los
  que traen datos de otro tipo de guardado (Flash o EEPROM, u otro juego); completa con
  `0xFF` los que midan menos de 32 KiB; avisa si la partida está en blanco; y siempre
  te pide confirmar. Guarda antes una copia de tu partida actual y se niega a tocar nada
  con el juego abierto (al cerrarse volvería a guardar la partida anterior).

*No se ha probado en un Windows real.* Sí con PowerShell 7 en Linux (pruebas automáticas
de importar, exportar, copias y restaurar), y el juego compilado cargó y recortó un `.sav`
de 128 KiB con relleno. La pantalla *Partidas* del menú (0.4.5) se probó con la ventana real en
Linux/Xvfb (importar con relleno y copia previa, exportar, recuperar) y su lógica con
`tools/pruebas/probar_partidas_menu.sh` (90 comprobaciones); el selector nativo de archivos de Windows
y el explorador de carpetas no se han visto en un Windows real. Lo que **no** se ha hecho es traer una partida jugada de verdad
desde un emulador.

### Jugar online con un amigo (experimental, 0.5.0)

Botón **«En línea»** en la cabecera del menú de arranque. **No hay servidor, ni cuenta, ni programa
aparte**: os pasáis dos códigos por el chat que queráis (WhatsApp, Discord…) y la partida arranca sola.

1. Los dos tenéis **la misma versión de este programa y la misma ROM** (el menú avisa si no).
2. *(Opcional)* Escribe **tu nombre**: es el que verá tu amigo, para identificaros por vuestro nombre y
   no por el del personaje del juego. Se guarda en `config.ini` (`[Online] Nombre`). Y puedes poner un
   **apodo para tu amigo** que solo ves tú (no se guarda).
3. Uno pulsa **«Crear una sala»** y le manda a su amigo el **código de invitación** (*Copiar*).
4. El amigo pulsa **«Unirme a una sala»**, pega ese código (*Pegar*) y pulsa *Continuar*; le sale un
   **código de respuesta**, que le devuelve al anfitrión.
5. El anfitrión pega el código de respuesta y pulsa **«Conectar»**. Los dos se conectan y el juego
   arranca solo. Durante los primeros segundos de la partida, la ventana del anfitrión rotula
   quién es quién (tu nombre en verde a la izquierda, el de tu amigo en blanco a la derecha) y el
   título de la ventana pone «Nombre1 vs Nombre2».

Cómo funciona y qué se cuenta a quién:

- Los códigos (40 caracteres en grupos de 4) llevan **tu dirección IP pública** y la de tu red
  local: dáselos **solo a tu amigo**. Para averiguar tu dirección pública se consulta **una vez** a
  un servidor STUN público (por defecto los de Google y Cloudflare); ese servidor no recibe los
  códigos, ni los nombres, ni nada de la partida. Si prefieres otro, o ninguno, se cambia en
  `config.ini` (`[Online] StunServers = host:puerto host:puerto`) o con la variable
  `MTP_STUN_SERVERS`. **No hay ningún servidor nuestro.**
- Los dos ordenadores se conectan **directamente** (UDP, perforando el NAT del router), sin
  abrir puertos a mano. La primera vez, el cortafuegos de Windows puede pedir permiso de red:
  dáselo (redes privadas). El nombre que escribes se envía a tu amigo al conectar (se limpia:
  solo texto UTF-8 válido, hasta 24 bytes, sin caracteres de control).
- Cada ordenador simula **las dos consolas** (modo cable con retroceso, *rollback*), así que hace
  falta un PC que vaya sobrado; si el tuyo va justo en el modo normal, irá peor aquí.

Límites que conviene saber antes de quedar con alguien:

- **No funciona con todas las redes.** Si uno de los dos está detrás de un NAT simétrico o de un
  CGNAT (muchos datos móviles, redes de empresa y algunas operadoras de fibra), la conexión directa
  no es posible; el menú lo detecta y lo avisa, y la prueba acaba con un error de tiempo (el
  anfitrión espera unos 4 minutos; el invitado, 45 segundos). Tampoco funciona con IPv6 (solo
  IPv4).
- Hace falta que **los dos** tengáis idéntico el programa, la ROM, el código generado y la BIOS
  libre: si algo difiere, se rechaza la conexión en vez de arrancar una partida que se
  desincronizaría.
- Experimental: la partida puede cortarse o desincronizarse. No hay reconexión.

Qué se ha comprobado y qué no (honestamente):

- **Sí (Linux):** dos instancias reales del juego se conectan por el código, acuerdan el arranque
  y avanzan más de 7.000 ticks por las pantallas de idioma y de elección de personaje sin
  errores, a unos 58 ticks/s cada una en un equipo de 2 núcleos; el protocolo de códigos con
  routers NAT reales de Linux en redes virtuales aisladas (dos NAT domésticos: conecta; simétrico en
  un lado o en los dos, o sin STUN: no conecta y avisa); los nombres (limpieza, guardado, viaje por
  la conexión, rótulo y título); y el recorrido completo por las pantallas del menú con ventana virtual.
- **No:** una conexión **entre dos casas por internet de verdad**; Windows (ni el cortafuegos ni el
  `.exe`; el módulo de red compila para Windows con MinGW, nada más); **un partido completo en línea**
  (solo se llegó a las pantallas previas); sesiones largas (posibles desincronizaciones); equipos lentos.
- Pruebas automáticas: `tools/pruebas/probar_invitacion.sh` (códigos, errores, nombres y
  conexión local) y `tools/pruebas/probar_invitacion_nat.sh` (con routers NAT virtuales; necesita
  root, `ip` e `iptables`).

## Qué incluye y qué no

| Incluido | Licencia |
|---|---|
| Configuración del recompilador (`game.toml`), host (`src/`), scripts, pruebas y `parches/` | **PolyForm Noncommercial 1.0.0** (`LICENSE`): los parches son obras derivadas de gbarecomp y el juego que construyes lo enlaza |
| BIOS libre `bios_libre/` | MIT (Cult-of-GBA); ver `bios_libre/LICENSE-Cult-of-GBA-BIOS.txt` |

Ojo con la licencia: **gbarecomp es de uso no comercial** (PolyForm Noncommercial
1.0.0), así que este proyecto es solo para uso personal y sin ánimo de lucro.
recomp-ui (el menú) es MIT. La lista completa de licencias de lo que se descarga al
construir está en [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

**No se incluye ni se debe subir** la ROM, el código generado a partir de ella
(`generated/`), ni la carpeta `juego/`: derivan del juego de Nintendo. El
`.gitignore` ya los excluye. Cada persona construye el juego en su equipo con su
propio volcado.

## Estructura

```
INSTALAR.bat           Windows: abre el instalador (elige ROM y carpeta), con doble clic
ACTUALIZAR.bat         Windows: actualiza una instalación existente (la encuentra sola)
icono.ico              (opcional, lo pones tú) icono de los accesos directos
PARTIDAS.bat           Windows: importa/exporta partidas de emuladores y hace copias
VERSION                Número de versión del proyecto (lo lee ACTUALIZAR)
CHANGELOG.md           Qué cambia en cada versión
LICENSE                PolyForm Noncommercial 1.0.0
THIRD_PARTY_NOTICES.md Licencias de todo lo que se usa o se descarga
CONTRIBUTING.md        Cómo colaborar (y lo que nunca se sube)
SECURITY.md            Cómo avisar de un fallo de seguridad
.github/               Plantillas de incidencias y de pull request, y la comprobación automática
tools/INSTALAR.ps1     El instalador de PowerShell (ventana, método ligero + respaldo MSYS2, accesos)
tools/ACTUALIZAR.ps1   El actualizador (detecta la instalación, compara, reinstala)
tools/comun.ps1        Funciones compartidas (ROM, búsqueda de instalación, huella de versión)
tools/construir.ps1    Compilación ligera de Windows: Zig + CMake + Ninja + SDL2, sin git ni MSYS2
tools/DESINSTALAR.ps1  El desinstalador (se copia a la carpeta del juego)
tools/PARTIDAS.ps1     Importar, exportar, copias y restaurar partidas (se copia a la carpeta del juego)
tools/pruebas/         Pruebas automáticas: filtros de imagen, aviso de versión, partidas, juego en línea, instalador de Linux y sintaxis de los .ps1
CONSTRUIR.bat          Windows: compila dentro de la carpeta del proyecto (método ligero)
CONSTRUIR-MSYS2.bat    Windows: lo mismo con el método clásico (MSYS2)
tools/construir.sh     Compilación en Linux (y la del método clásico en Windows)
tools/instalar.sh, actualizar.sh, desinstalar.sh, comun.sh, jugar.sh   Instalador, actualizador y desinstalador de Linux (+ funciones comunes y arranque)
tools/aplicar_parches.py   Aplica parches/*.patch a gbarecomp (idempotente)
tools/fusionar_fallos.py   Añade a game.toml las entradas que el runtime encontró
tools/JUGAR.bat, jugar.sh  Lanzadores que se copian a juego/
game.toml              Configuración del recompilador y del runtime
src/main.cpp           Host: ganchos de RAM, identidad del cartucho, modos de pantalla
src/game_launcher_boot.*   Puente con el menú de arranque (recomp-ui)
src/aviso_actualizacion.cpp   Aviso de «hay una versión nueva» del menú (comprueba VERSION en segundo plano)
src/invitacion.h, .cpp   Jugar online sin servidor: códigos de invitación, STUN, perforación de NAT y nombres
parches/               Cambios mínimos a gbarecomp (se aplican solos)
bios_libre/            BIOS libre (MIT) y su configuración
docs/ESTADO.md         Estado detallado y hallazgos (leer al retomar)
docs/NOTAS_TECNICAS.md Cómo funciona por dentro
```

## Pruebas

No necesitan la ROM. Los filtros se prueban sobre una copia de gbarecomp con los parches
aplicados, y la herramienta de partidas con PowerShell 7:

```sh
python3 tools/aplicar_parches.py <carpeta de gbarecomp>     # el commit de tools/construir.sh
bash tools/pruebas/probar_filtros.sh <carpeta de gbarecomp>
bash tools/pruebas/probar_aviso.sh                          # el aviso de versión, contra un servidor local
bash tools/pruebas/probar_partidas_menu.sh                  # importar/exportar partidas del menú (compila src/partidas.cpp)
bash tools/pruebas/probar_invitacion.sh                     # códigos de invitación, nombres y conexión local (compila src/invitacion.cpp)
sudo bash tools/pruebas/probar_invitacion_nat.sh            # lo mismo con routers NAT virtuales (necesita root, ip e iptables; si no, se omite)
bash tools/pruebas/probar_instalador_linux.sh               # instalar/actualizar/desinstalar en Linux con un juego falso y un HOME temporal (62 comprobaciones)
pwsh tools/pruebas/probar_partidas.ps1
pwsh tools/pruebas/comprobar_sintaxis.ps1
```

GitHub Actions (`.github/workflows/comprobar.yml`) ejecuta todo eso, y las pruebas de
partidas también en Windows PowerShell 5.1 (esa parte no bloquea: se escribió sin poder
ejecutarla en un Windows real).

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
