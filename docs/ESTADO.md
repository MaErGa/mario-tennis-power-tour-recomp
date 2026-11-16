# Estado del proyecto (leer al retomar)

Última comprobación: 15-nov-2026 (versión 0.4.4), en Linux (sandbox de 2 núcleos, sin tarjeta de
sonido, sin Windows).

## Qué funciona

- Compilación desde cero con `tools/construir.sh` (descarga gbarecomp y
  recomp-ui, aplica `parches/`, recompila BIOS libre y ROM, compila, monta `juego/`).
- **Compilación ligera para Windows (`tools/construir.ps1`)**: sin MSYS2, sin git y
  sin Python. Descarga Zig 0.16.0, CMake 4.4.4 y Ninja 1.13.2 (ruedas de PyPI, con
  SHA-256 fijado), SDL2 2.30.9 y las fuentes en zip de gbarecomp, arm-recomp-core,
  toml++ y recomp-ui en el commit fijado (≈ 150 MB de descarga, ≈ 0,5 GB de
  herramientas, ≈ 1 GB de compilación). Aplica `parches/` con un aplicador propio
  en PowerShell (resultado idéntico al de `git apply`, comprobado) y deja el `.exe`
  solo con `SDL2.dll` al lado. Probado de punta a punta con las herramientas de
  Zig, CMake y Ninja **de Linux** colocados donde `construir.ps1` espera los de
  Windows (`MTP_PRUEBA_LINUX=1`), con compilación cruzada a `x86_64-windows-gnu`.
  El `.exe` resultante, ejecutado bajo Wine 9, da capturas idénticas una a una
  (32 de 32 en español) a las de la compilación con MinGW. También se probó el
  instalador entero (`INSTALAR.ps1`, 5 min con las herramientas ya descargadas).
  **No se pudo ejecutar `zig.exe` de Windows** en el entorno de pruebas (ver
  `NOTAS_TECNICAS.md`): hace falta confirmarlo en un Windows real.
- **`ACTUALIZAR.bat` / `tools/ACTUALIZAR.ps1`**: encuentra solo la instalación
  (registro de «Aplicaciones», carpeta por defecto, accesos directos, discos),
  reutiliza la ROM de la carpeta del juego, compara una huella (`instalacion.json`)
  con la versión nueva y reinstala con el mismo método. Probado con PowerShell 7
  en Linux (prueba seca): sin cambios no hace nada, con cambios actualiza
  conservando partidas, accesos y registro, `-Forzar`, carpeta inválida y sin
  instalación.
- **Icono personalizado**: `icono.ico` junto a `INSTALAR.bat` / `ACTUALIZAR.bat` se
  copia a la carpeta del juego y lo usan los accesos directos y «Aplicaciones»;
  `ACTUALIZAR` puede aplicar solo un icono nuevo sin recompilar. Probada la lógica en
  Linux (prueba seca); **el cambio real del icono de los `.lnk` (COM `WScript.Shell`)
  no se ha podido probar sin Windows**. No hay icono dentro del `.exe` (la ventana y la
  barra de tareas mientras el juego corre usan el genérico): haría falta incrustar un
  recurso `.rc` en la compilación con Zig o poner el icono de ventana con SDL.
- **Filtros de imagen (0.3.0, rehechos en 0.3.1 y 0.3.2; parche 0004)**: nueve opciones en
  *Texture filtering* (Nearest, Linear, Sharp fractional, Scale2x/3x/4x, HD smooth, LCD grid,
  CRT). La 0.3.0 los dibujaba ampliando y estirando con filtro lineal y el resultado se
  veía solo desenfocado; la 0.3.1 replica los ampliadores por un entero y dibuja la rejilla
  LCD y las líneas CRT como máscara a la resolución de la ventana; la 0.3.2 compone esa
  máscara por CPU (sin mezclas de la tarjeta), añade el cambio en directo con F12 y arregla
  el interruptor «Linear filter» del menú del juego, que no hacía nada con los filtros
  2–8. Se comprobó con OpenGL (Xvfb) y Direct3D 9 (Wine) de punta a
  punta: clic en el menú → `config.ini` → `--image-filter` → `GBARECOMP_FILTRO` →
  capturas de la ventana real (Xvfb) en pantalla completa 1280×720, ventana 3× y los modos
  16:9, también combinadas con *Screen model*. Pruebas automáticas
  (`tools/pruebas/probar_filtros.sh`): Scale2x y Scale3x frente a la definición de la
  especificación, que una imagen de un solo color salga de un solo color con cada filtro,
  replicación entera, cobertura de las rayas, media y periodicidad de las máscaras LCD y CRT,
  compensación de brillo y mezcla de HD smooth. Coste ≤ 5 ms por fotograma (HD smooth en
  ventana grande es el peor caso). *Sharp fractional* ya funciona (antes la fila no hacía nada).
- **Avance rápido, tecla Tab (0.3.1 a 0.3.3, parche 0006 y `src/main.cpp`)**: la 0.3.0 bajaba
  los fps al pulsar Tab; la 0.3.1 lo arregló pero el juego solo iba ≈ ×1,2–1,7 (se pintaban
  todos los fotogramas y había esperas); la 0.3.2 no pinta los fotogramas que no se dibujan
  (y evitó los parpadeos en negro); la 0.3.3 reparte las imágenes según lo que cuesta dibujar
  y elimina un cuello de botella propio del port (la comprobación IWRAM = ROM, más de un
  tercio del tiempo de un partido). Entorno de pruebas: ≈ ×1,7 (0.3.2) → ≈ ×2,4 (0.3.3), sin
  parpadeos (0 de ≈ 4.000 capturas). El título muestra `turbo xN.N | img/s | emu ms | dib ms`.
  Limitado por la CPU; **no se ha medido en un Windows real** (en el equipo de quien lo
  probó, la 0.3.2 daba ×1,4 con 21 imágenes/s: la 0.3.3 debería mejorarlo, pero falta
  confirmarlo con una captura del título).
- **Menú en español (0.4.0, `parches/recomp-ui-0001-menu-en-espanol.patch`)**: tabla
  `kSpanish` en `launcher_i18n.cpp` de recomp-ui (≈ 270 textos), el dibujado del menú del
  juego (`runtime_ui_imgui.cpp`) pasa cada texto por `launcher_i18n_text` y unas etiquetas del
  menú de arranque se cambiaron (fila «Partida», «ROM verificada», relación de aspecto).
  Idioma por `MTP_IDIOMA_MENU` de CMake (`es`) o por la variable de entorno del mismo
  nombre. Comprobado con capturas de la ventana real (Xvfb) de las cuatro secciones del
  menú de Esc, del menú de arranque y de sus ajustes, a 100 % y con un factor 1,5 simulado;
  con tildes, ñ, signos de interrogación y exclamación (la fuente los trae). Los textos largos
  se acortaron para que no pisen los botones de la derecha. **Sin traducir:** modelos de pantalla
  («Raw», «Unlit»…), mods, juego en red y los textos de error del lanzador.
- **Selector de idioma del menú (0.4.1, `parches/recomp-ui-0002-selector-de-idioma-del-menu.patch`)**:
  fila «Idioma del menú» (Español / English) en los ajustes del menú de arranque y como última
  fila de «Sistema» en el menú de Esc. Estado en `launcher_i18n.cpp`: orden de prioridad
  `MTP_IDIOMA_MENU` (pruebas) > `[Menu] Language` de `config.ini` (ruta en `MTP_CONFIG_INI`, la fija
  `main.cpp`) > idioma de compilación. Se guarda con `launcher_ini_kv_write` (escritura puntual:
  no pisa la sección `[Launcher]`, que el lanzador reescribe entera, ni se pierde al guardar él).
  Comprobado con capturas de la ventana real: cambio al instante en los dos menús, persistencia
  al reabrir, que sobrevive a «JUGAR» (el lanzador guarda su sección), y creación de
  `config.ini` cuando no existía. El menú de Esc ahora desplaza la fila elegida hasta verla
  entera (antes la última fila de Sistema quedaba cortada). No cambia el idioma del juego.
- **Menú de Esc con el escalado de Windows (0.4.2, `parches/recomp-ui-0003-…patch`)**: una
  captura de la persona usuaria en un Windows real (14-nov, ventana a escala 6) confirmó que el
  menú sale en español y que el programa es consciente del DPI, y destapó que el panel seguía en
  780 píxeles mientras el texto crecía (título pisado, descripciones cortadas, pie sobre
  «Continuar»). Corregido multiplicando las medidas fijas por `io.FontGlobalScale` (factor_escala)
  y recortando con «...» lo que no cabe; reproducido y comprobado con `MTP_FACTOR_DPI` 1,5 y 2,0.
- **Textos pendientes en español (0.4.3, `parches/recomp-ui-0004-…patch`)**: pantalla de asignación
  de controles, nombres de direcciones y teclas, modelos de pantalla, atajos, aviso de «Saltar el
  lanzador», selector de archivos y explorador integrado. Comprobado con capturas de la ventana real
  del menú en español y en inglés (el inglés no cambia). Lo que sigue en inglés son pantallas que
  esta consola no muestra (mods, *netplay*, otras consolas) y el texto de los errores internos del
  recompilador. Con `MTP_I18N_DEBUG=1` se ve qué textos pasan sin traducir.
- **Visor de capturas en el menú (0.4.4, `parches/recomp-ui-0005-…patch`)**: botón «Capturas» →
  rejilla de miniaturas (150 más recientes), vista grande, Anterior/Siguiente, Borrar con doble
  pulsación, Abrir carpeta (`SDL_OpenURL`) y Cerrar. Se comprobó con capturas de la ventana real del menú en
  Linux/Xvfb (1280×720 y 1920×1080): rejilla, vista grande, navegación, borrado (el archivo
  desaparece), PNG corrupto («No se pudo leer esta imagen»), carpeta vacía y carpeta inexistente,
  español e inglés. Las miniaturas se hacen con `launcher_texture_load_thumb` (decodifica con stb_image,
  reduce por un factor entero promediando bloques y sube una textura de ≤ 360×240; dos por fotograma).
- **Aviso de versión nueva (0.4.4, `src/aviso_actualizacion.cpp`)**: hilo aparte que pide el
  `VERSION` del repositorio (WinHTTP en Windows, `curl` en Linux; máximo 256 bytes; plazo de 6 s),
  lo compara por partes numéricas (`0.4.10` > `0.4.3`) y el menú lo enseña como franja con
  «Ocultar». El menú lo llama a través de dos funciones `extern "C"` (`mtp_aviso_actualizacion`,
  `mtp_version_instalada`), declaradas dentro de `#if defined(MTP_EXTRAS_MENU)` (la define CMake
  solo en `game_launcher_ui`); sin la definición, el parche usa un sustituto que devuelve «».
  `tools/pruebas/probar_aviso.sh` lo prueba contra un servidor local (12 casos) y lo ejecuta la CI.
- **Perfil por mando**: es de recomp-ui (Guardar/Renombrar/Borrar perfil, por identificador de
  mando); traducido en 0.4.3. No se ha probado con un mando físico.
- **Captura de pantalla (0.4.0, parche 0007)**: tecla `Screenshot` (F10 por defecto) →
  `capturas/MarioTennis_<fecha>.png`, imagen del juego ampliada por un entero (≥ 720 px de alto,
  vecino más cercano), aviso en el título 3 s. El PNG se comprime con un DEFLATE propio
  (Huffman fijo + LZ77); se comprobó que Python (`zlib`/Pillow) lo lee y que la imagen es la
  esperada. Con el juego en marcha y en pausa; no con el menú de Esc abierto.
- **Imagen nítida con el escalado de Windows (0.4.0, parche 0008 y `src/main.cpp`)**:
  `SDL_WINDOWS_DPI_AWARENESS=permonitorv2` por defecto; escala de ventana × factor de Windows
  (`SDL_GetDisplayDPI`), en múltiplos enteros y recortada al escritorio utilizable; el menú de
  Esc usa `FontGlobalScale`/`ScaleAllSizes` con ese factor. **Solo se pudo simular**
  (`MTP_FACTOR_DPI=1.5`, ventana 960×640 y menú agrandado correctos); las llamadas de Windows
  (`SetProcessDpiAwarenessContext` dentro de SDL, `GetDpiForMonitor`) no se han ejecutado.
- **Partidas (0.3.0, parche 0005 y `PARTIDAS`)**: el juego compilado carga un `.sav` de
  128 KiB con relleno, usa los primeros 32 KiB, deja `.sav.original` y al guardar escribe
  32 KiB. `tools/PARTIDAS.ps1` (importar, exportar, copias, restaurar, rechazo de
  estados rápidos y de archivos de otro tipo) pasa `tools/pruebas/probar_partidas.ps1` con
  PowerShell 7 en Linux. Una instalación en seco copia `Partidas.ps1` y `Partidas.bat` a la
  carpeta del juego, y una desinstalación en seco con «conservar partidas» deja intactos el
  `.sav`, el `.sav.original` y la carpeta `copias-de-partidas`.
- **Repositorio**: `LICENSE` (PolyForm Noncommercial 1.0.0), `THIRD_PARTY_NOTICES.md`,
  `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, plantillas de GitHub y
  `.github/workflows/comprobar.yml`. Cada paso de ese flujo se ejecutó en local contra una
  copia limpia de gbarecomp en el commit fijado (parches aplicados dos veces, filtros,
  partidas, sintaxis y BOM de los `.ps1`, YAML válido). **El flujo en sí no se ha ejecutado
  en GitHub.**
- Menú de arranque: ROM verificada por SHA-1 («ROM verificada»), mando/teclado,
  escala, pantalla completa, filtro, relación de aspecto, volumen.
- Arranque con BIOS libre → selección de idioma → modo historia (habitación,
  diálogos, plaza, exterior de la academia, restaurante, menú de Super Golpes).
- **Los cinco idiomas (en, de, fr, es, it)**: partida nueva de principio a fin de
  la introducción (selección, aviso, creación de personaje, nombre, habitación) y
  paseo aleatorio por plaza, academia, restaurante y menús, **con el compilador en
  caliente desactivado** (`GBARECOMP_SELFHEAL_RECOMPILE=0`), que es la situación
  de un Windows sin `gcc` ni `tcc`. Un partido de exhibición también.
- **Partido de Exhibición** (Menú principal → Exhibition → Mario vs. Peach):
  pista, «1st Serve» y movimiento de jugadores.
- Rendimiento sin ventana: ≈ 110 fotogramas/s con `gcc` disponible y ≈ 120 sin
  compilador (medido en un partido, 1.800 fotogramas, 2 núcleos). El juego
  necesita 59,7.
- Audio: la mezcla del partido no es silencio (pico 21.792, RMS ≈ 4.800 sobre
  32.000 muestras). Falta escucharlo por altavoces.
- Modos de pantalla 3:2 / 16:9 estirado / 16:9 con barras difuminadas,
  comprobados en un partido y de punta a punta desde el menú
  (`aspect_index = 2` → ventana 852×480 con lados difuminados).

## Qué no se ha comprobado

- **Novedades de 0.3.0 a 0.4.4 en un Windows real** (además de lo dicho arriba sobre el DPI; F10
  **sí** se comprobó en un Windows real el 16-nov-2026 con capturas del juego; si en otro equipo
  no responde, `[KeyMap] Screenshot = F11`): los filtros y el avance rápido se
  dibujan con `SDL_Renderer` (Direct3D 11 en Windows) y solo se vieron y midieron con el de
  Linux/Xvfb (por software); `PARTIDAS.ps1` se probó
  con PowerShell 7 en Linux y **no** con Windows PowerShell 5.1 ni con ventanas reales
  (selector de archivos, menú); el acceso directo «Partidas» del menú Inicio (COM
  `WScript.Shell`) tampoco. El trabajo de Windows de la CI está pensado para dar esa
  información (no bloquea).
- **Partidas jugadas de verdad desde un emulador**: se probó el recorte y la carga con
  archivos de prueba, no con el progreso real de una partida de mGBA o RetroArch.
- **Shaders de RetroArch, paquetes de texturas o de texto HD**: no existen (ver README).
- **Estados rápidos de emuladores**: no son compatibles y no se pueden convertir.
- **Windows real con el método ligero**: `construir.ps1` e `INSTALAR.ps1` nuevos no
  se han ejecutado todavía en un Windows de verdad. Lo que sí se comprobó es cada
  pieza con equivalentes de Linux. Puntos a vigilar en Windows: que `zig.exe` y
  `cmake.exe` arranquen sin que el antivirus o SmartScreen los bloquee, que `tar.exe`
  abra el SDL2 `.tar.gz`, que PowerShell 5.1 descomprima las ruedas con
  `System.IO.Compression`, que `github.com/<repo>/archive/<commit>.zip` descargue
  (desde esta máquina de pruebas está bloqueado, aquí se simuló con los mismos
  zips) y las rutas largas (por eso la carpeta temporal se limita a 70 caracteres).
  Si algo de eso falla, el instalador ofrece el método clásico con MSYS2.
- **Windows real (MSYS2)**: el `.exe` compilado de forma cruzada (MinGW, SDL2 2.30.9)
  arranca bajo Wine 9 y, tras 900 fotogramas, produce una imagen idéntica píxel a
  píxel a la de Linux. Pero `CONSTRUIR.bat` y `JUGAR.bat` están escritos y no se
  han ejecutado en un Windows de verdad (no hay Windows en el entorno de
  pruebas). Bajo Wine el autocurado con `tcc` falla (no hay `tcc`) y se queda en
  el intérprete, que es correcto. Puntos a
  vigilar (método clásico): instalación de MSYS2 con `winget`, ruta del `PATH` de MinGW en
  `JUGAR.bat`, la pila de 256 MiB del enlazador y el tiempo de compilación.
- **Instalador de Windows (`INSTALAR.bat` + `tools/INSTALAR.ps1`)**: primera prueba
  en un Windows 11 real (PowerShell 5.1): la ventana, la comprobación del equipo
  y la detección de MSYS2 funcionaron; `pacman` falló en todas las órdenes con
  «no se pudo bloquear la base de datos» (`db.lck` antiguo o pacman de un intento
  anterior). Corregido con `Preparar-Pacman` (espera al pacman en marcha, quita el
  bloqueo y reintenta la instalación de paquetes). **Pendiente de volver a
  probar** desde ahí: instalación de paquetes, `construir.sh` bajo MSYS2 (rutas,
  git sin conversión de finales de línea, GCC más nuevo que el de la compilación
  cruzada), copia a la carpeta elegida, accesos directos, entrada de
  «Aplicaciones» y desinstalador. La lógica sin partes de Windows (ROM por
  SHA-1, carpeta, subcarpeta si no está vacía, no pisar partidas, desinstalar)
  se probó con `-PruebaSeca` en Linux con PowerShell 7. Si la ventana falla, el
  instalador sigue en la consola. El registro queda en
  `%TEMP%\mario-tennis-instalador.log`.
- **Sonido real** por altavoces/mando.
- Torneos completos, minijuegos, modos con cable, partidos dobles largos,
  un ciclo completo de jugar, guardar desde el juego y volver a abrir (la SRAM está
  configurada, se carga y se vuelca bien, pero no se ha jugado hasta un punto de guardado).
- Mandos reales (solo se probó el teclado simulado).

## Limitaciones conocidas

- Parte del juego (módulos de código de EWRAM, rutinas copiadas a la zona de
  pila, el descompresor) se ejecuta con el intérprete del runtime: es correcto
  pero más lento que el código recompilado.
- El menú está en español e inglés (selector «Idioma del menú»); quedan en inglés los modelos de
  pantalla («Raw», «Unlit»…), los mods, el juego en red y los textos de error del lanzador.
- El modo de pantalla se aplica al arrancar; para cambiarlo hay que reabrir.
- El aviso de versión nueva es solo un aviso (no actualiza), y su dirección por defecto es la prevista
  para el repositorio (`MaErGa/MarioTennisPowerTourRecomp`, rama `main`); si es otra hay que cambiarla.
- En el visor de capturas, la navegación solo con teclado/mando no entra en las tarjetas del menú
  (pasa igual en el panel original de recomp-ui); con el ratón funciona todo.
- No hay vista ampliada 16:9 real (ver `NOTAS_TECNICAS.md`).
- Los filtros de imagen se calculan en la CPU (≤ 5 ms por fotograma en el equipo de
  pruebas); en un equipo muy lento el más pesado (HD smooth en ventana grande) podría notarse.
- La rejilla LCD y las líneas CRT no se dibujan con la imagen en pantalla menor de 480×320;
  por encima de 1920×1080 se calculan a la mitad de resolución (rayas más gruesas).
- Con el escalado de Windows la escala de la ventana se ajusta en múltiplos enteros y se recorta
  al escritorio (escala 3 al 150 % → 4×); el valor que enseña el menú es el real, no el pedido.
- Licencia: gbarecomp es PolyForm Noncommercial; uso personal y no comercial.

## Cómo seguir

1. Juega más (torneo, minijuegos), cierra con normalidad y fusiona los fallos:
   `python3 tools/fusionar_fallos.py game.toml juego/recomp_master_misses_BTMP.toml.frag`
   y vuelve a ejecutar `tools/construir.sh`.
2. Probar en Windows y anotar aquí lo que falle.
3. Ver si convertir el descompresor y los módulos de EWRAM en código nativo
   (HLE o recompilación de los módulos descomprimidos) para ganar velocidad.
4. Si algún día se quiere un 16:9 ampliado real, habría que escribir un
   proveedor de márgenes por escena (qué dibujar fuera de los 240 px); el
   framework tiene los ganchos `extended_view_init` y `extended_view_frame`.
