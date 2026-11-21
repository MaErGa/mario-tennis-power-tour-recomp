# Notas técnicas — cómo funciona por dentro

## Cadena de construcción

```
tu ROM ──gba_recompile──► generated/*.cpp (64 trozos) ─┐
BIOS libre ─gba_recompile─► generated_bios/*.cpp ──────┼─► MarioTennisPowerTourRecomp
src/main.cpp + menú (recomp-ui) + runtime gbarecomp ───┘
```

`gba_recompile` lee `game.toml` y traduce a C++ cada función ARM/Thumb que
encuentra. El resultado se enlaza con el runtime de gbarecomp, que emula el
resto de la GBA (PPU, DMA, temporizadores, audio, SRAM).

- **Descubrimiento**: `speculative_literal_harvest = false` (decodificar datos
  como código es el error caro), escaneo AOT de punteros a callbacks en toda la
  ROM, `static_resume_all = true` (una IRQ puede volver a cualquier instrucción)
  y 64 trozos para compilar en paralelo.
- **Trozos recompilados**: se compilan con `-O1 -foptimize-sibling-calls`
  (`MTP_SHARD_OPT`). Con `-O0` la pila del anfitrión se desborda tras unos 3.000
  fotogramas porque las llamadas en cola de la GBA se vuelven llamadas reales.
  En Windows el ejecutable reserva 256 MiB de pila.
- **BIOS libre**: 16 KiB de Cult-of-GBA (MIT), recompilada con una configuración
  generada de sus símbolos (`bios_libre/bios_libre.toml`). Su pantalla de
  arranque se queda esperando una interrupción, por eso `[bios] skip_intro = true`.

## Código que no es ROM estática

El juego ejecuta código desde tres tipos de sitios que el análisis estático no
ve directamente:

1. **IWRAM copiada de la ROM** por DMA3 al arrancar (IntrMain en `0x03000100`,
   rutinas en `0x03000220`, una en `0x03006000`). Se declaran como
   `[[code_copy]]` en `game.toml`, con sus puntos de entrada como `[[extra_func]]`
   (incluidos 17 bloques «`bx pc` + ARM» de IWRAM).
2. **Rutinas que se copian a RAM cada vez que se usan**: una en la zona de pila
   `0x03007C00..0x03007F00` (se copia desde `0x080019C0` cada fotograma) y el
   descompresor del juego (ROM `0x080129E8`, copiado a `0x03001400`). Se
   ejecutan con el intérprete.
3. **Módulos de código en EWRAM** (`0x02008000`): el juego descomprime del
   orden de 50 módulos de código según la pantalla (tabla de recursos en
   `0x08C28000`). Cambian con la pantalla, así que se interpretan.

`src/main.cpp` instala dos ganchos del runtime para esto:

- `despacho_ram`: IntrMain devuelve a veces a `0x030001C6` en modo ARM (media
  palabra más allá de la instrucción). La CPU real ignora los 2 bits bajos;
  el gancho los alinea antes de despachar.
- `forzar_interprete`: devuelve `0` (despacho nativo), `1` (intérprete del
  subárbol de llamadas) o `2` (desenrollar hasta el bucle principal, que sigue
  paso a paso). EWRAM → 2; IWRAM → nativo solo si los bytes de RAM coinciden con
  la imagen de la ROM, si no → 1.

## Parches al framework (`parches/`)

Se aplican con `tools/aplicar_parches.py` sobre el commit fijado de gbarecomp
(son idempotentes: si ya están aplicados, los salta). El aplicador elige los parches por el
nombre de la carpeta que se le da: `externo/gbarecomp` → `parches/gbarecomp-*.patch` y
`externo/recomp-ui` → `parches/recomp-ui-*.patch` (ver más abajo).

1. **`0001-interprete-y-puente-con-presupuesto`**: el valor `2` del gancho de
   intérprete forzado y un puente con presupuesto de instrucciones
   (`GBARECOMP_NESTED_BRIDGE_BUDGET`, 1.000.000 por defecto). Sin él, un puente
   anidado cuyo código «vuelve» por un camino que no es la dirección de retorno
   del llamante (cambio de pila, reanudación de tarea) acaba interpretando todo
   el juego sin presentar fotogramas. Con presupuesto, si se agota, el PC queda
   donde está y los llamantes generados desenrollan hasta el bucle principal.
2. **`0002-menu-bios-libre-y-aspecto`**: el menú acepta también la BIOS libre
   (SHA-1 `2e41f9d3…`) además de la de Nintendo, y el selector de aspecto ya no
   lleva la etiqueta EXPERIMENTAL.
3. **`0003-pantalla-estirada-y-difuminada`**: modos de presentación 16:9. Se
   eligen con `GBARECOMP_STRETCH` (`1` estirado, `2` barras difuminadas), que
   `main.cpp` fija desde el menú o desde `--stretch` / `--blur-bars`. El fondo
   difuminado reduce la imagen dos veces (÷4 y ÷4) con filtro lineal para que
   las barras no repitan, como un fantasma, el marcador ni los personajes.

4. **`0004-filtros-de-imagen`**: nueve filtros de imagen por CPU (ver «Filtros de imagen»)
   y su selector en el menú. Toca `host_window.cpp`/`.h` (el bloque de filtros, la textura
   ampliada, la composición LCD/CRT, el filtro en directo y `present()`), `launcher_seam.h`
   (opción `image_filter`, `--image-filter`, `config.ini`), `runtime.h`
   (`RunOptions::launcher_filter_*`) y `runtime.cpp` (atajos F12 y el interruptor «Linear
   filter» del menú del juego). Rehecho en 0.3.1 (los filtros de 0.3.0 solo desenfocaban) y
   en 0.3.2 (máscara por CPU, filtro en directo).
5. **`0005-partidas-de-emulador`**: al cargar la SRAM, si el `.sav` es mayor que los
   32 KiB del juego y lo que sobra es relleno (todo `0x00` o `0xFF`) o una repetición de
   los primeros 32 KiB, se recorta, se deja una copia `.sav.original` (una sola vez) y se
   avisa por la consola. Si lo que sobra son datos distintos, no se toca y el runtime
   sigue su camino de siempre (rechaza el archivo por grande). Al guardar, el `.sav`
   queda con su tamaño real.

6. **`0006-avance-rapido-sin-bajar-fps`** (0.3.1, reescrito en 0.3.2 y 0.3.3; toca también `gba_ppu.{h,cpp}`): ver «Avance rápido (Tab)».

7. **`0007-captura-de-pantalla`** (0.4.0): acción `HK_SCREENSHOT` (`Screenshot`, F10) en
   `host_window.cpp`/`.h` (`ev.screenshot`, `config_dir()` y `announce()`, un aviso temporal en el
   título) y en `runtime.cpp`: `mtp_captura_si_toca()` guarda el siguiente fotograma que se
   dibuje (también en el bucle de pausa), ampliado por un entero hasta ≥ 720 px de alto, en
   `<carpeta de config.ini>/capturas/`. `mtp_deflate()` sustituye los bloques sin comprimir de
   `write_png` por un DEFLATE con Huffman fijo y búsqueda LZ77 con cadenas de hash (sin zlib);
   afecta también a `--dump-png`. Con el menú de Esc abierto los atajos no llegan al runtime.
8. **`0008-nitidez-con-escalado-de-windows`** (0.4.0): `mtp_escala_por_dpi()` en `host_window.cpp`.
   `src/main.cpp` pone `SDL_WINDOWS_DPI_AWARENESS=permonitorv2` antes de que SDL inicie el
   vídeo (SDL lee los *hints* también del entorno). Con el proceso consciente del DPI la ventana
   mide píxeles reales, así que la escala pedida se multiplica por `SDL_GetDisplayDPI / 96` y se
   redondea hacia abajo a un entero (`floor(escala·f + 0,4)`), sin pasar del escritorio
   utilizable (`SDL_GetDisplayUsableBounds`, con un margen de 40·f px para la barra de título);
   el factor también se guarda para que el menú de Esc use `io.FontGlobalScale` y
   `ScaleAllSizes`. En Windows solo se aplica si el *hint* no es `unaware`/`0`. Para probarlo en
   cualquier sistema: `MTP_FACTOR_DPI=1.5`.

**Los parches solo pueden modificar archivos existentes.** El aplicador de
`tools/construir.ps1` (el del Windows ligero, sin git) entiende los *hunks* de
modificación pero no los archivos nuevos, así que el código nuevo va dentro de archivos
que ya existen, entre marcas `INICIO/FIN` (el bloque de filtros de 0004 es el ejemplo;
`tools/pruebas/probar_filtros.sh` lo extrae por esas marcas para probarlo aparte).
`tools/aplicar_parches.py` decide qué parches ya están puestos mirando **desde el último
hacia atrás**: el último que se puede revertir sin error y todos los anteriores cuentan
como aplicados (con 0004 aplicado, el chequeo inverso de 0003 falla porque ambos tocan
las mismas líneas, y eso no quiere decir que 0003 falte).

El menú del framework solo sabe pasar un «ancho de vista» por opción de aspecto;
los modos 1 y 2 se señalan con anchos centinela (`241` y `242`, que no son
anchos reales) que `main()` traduce a `GBARECOMP_STRETCH` y quita de los
argumentos antes de llamar a `run_game()`.

### Parches de recomp-ui (`parches/recomp-ui-*.patch`)

1. **`recomp-ui-0001-menu-en-espanol`** (0.4.0):
   - `src/common/launcher_i18n.cpp`: tabla `kSpanish` (pares inglés → español) y la rama
     `es`/`es-ES` de `launcher_i18n_text()`. La variable de entorno `MTP_IDIOMA_MENU` manda sobre
     la macro `RECOMP_UI_LANGUAGE`, que `CMakeLists.txt` fija con
     `recomp_target_launcher_language(game_launcher_ui "${MTP_IDIOMA_MENU}")`.
   - `src/common/backends/imgui/runtime_ui_imgui.cpp` (el menú de Esc): todo texto que se
     dibuja (secciones, filas, descripciones, valores, estado, avisos, pie) pasa por `tr()`.
     Los textos que no están en la tabla se muestran tal cual, así que el inglés no cambia (salvo
     el pie, que ahora muestra «Enter / A  Select …» en vez de «Select  Select …»).
   - `src/common/backends/imgui/launcher_imgui.cpp` (menú de arranque): la fila «Partida» (clave
     nueva «Save game», con más sitio), «Import», el botón de relación de aspecto y la línea
     «ROM verified».
   - **Si subes el commit de recomp-ui:** los textos nuevos saldrán en inglés hasta que se añadan a
     la tabla. Para encontrarlos, busca los literales de `recomp_runtime_settings.c` y de
     `launcher_imgui.cpp` (`ui_text("…")`) que no estén en `kSpanish`. Los textos largos del menú de
     Esc tienen que caber en ≈ 36 caracteres (filas con − / +) o ≈ 45 (interruptores), o pisan los
     controles de la derecha. Las traducciones están (sin formato C) en el propio parche.
   - El aplicador de PowerShell no entiende archivos nuevos: por eso la tabla va *dentro* de
     `launcher_i18n.cpp`.
2. **`recomp-ui-0002-selector-de-idioma-del-menu`** (0.4.1), encima del 0001:
   - `launcher_i18n.{h,cpp}`: el encabezado pasa a `extern "C"` y se añaden
     `launcher_i18n_menu_language()` (0 = es, 1 = en) y `launcher_i18n_set_menu_language()`. El
     idioma efectivo se resuelve en `launcher_i18n_language()` por este orden:
     `MTP_IDIOMA_MENU` > `[Menu] Language` de `config.ini` (se lee una sola vez, con un lector
     propio de INI de ≈ 30 líneas; ruta en `MTP_CONFIG_INI`, por defecto `config.ini`) > macro
     `RECOMP_UI_LANGUAGE`. Al elegir se guarda con `launcher_ini_kv_write` (escritura puntual
     de una clave: respeta el resto del archivo, incluida la sección `[Launcher]` que el
     lanzador reescribe entera y que, por eso, no sirve para guardar claves nuevas).
   - `recomp_runtime_settings.c`: una fila más, siempre presente, al final de «System»
     (clave `menu.language`, opciones «Español» / «English» sin traducir, escritas en UTF-8 con
     escapes `\x`). `recomp_runtime_ui.c` la resuelve él mismo (`is_menu_language()`) en
     `recomp_runtime_ui_current_value` y en `adjust_current`, sin pasar por las funciones del
     anfitrión, así que gbarecomp no necesita ningún cambio.
   - `launcher_imgui.cpp`: `row_menu_language()` (un `settings_combo_row`) al final del panel de
     pantalla, en sus dos salidas (el camino «clásico» con `return` y el «profundo»).
   - `runtime_ui_imgui.cpp`: la fila seleccionada se desplaza hasta verse entera
     (`SetScrollHereY`) cuando el teclado la deja cortada por arriba o por abajo. Sin esto la
     fila del idioma, al ser la quinta de «Sistema», quedaba medio oculta.
   - `src/main.cpp` define `MTP_CONFIG_INI` (carpeta del ejecutable + `config.ini`, igual que el
     lanzador) con `entorno_por_defecto`.

3. **`recomp-ui-0003-menu-de-esc-con-escalado-de-windows`** (0.4.2), encima del 0002, solo
   `runtime_ui_imgui.cpp`:
   - `factor_escala()` devuelve `io.FontGlobalScale` (el factor de Windows que fija el parche 0008 de
     gbarecomp; 1 en el modo táctil, que ya tiene su propia escala). Se multiplican por él las
     medidas de `theme` (altura de fila, espacios, radios: `push_runtime_style` las usa en lugar de
     las del estilo de ImGui, por eso `ScaleAllSizes` no bastaba), el margen, el máximo de ancho
     (ahora 900) y de alto (680), el umbral de «modo ancho» (640), la columna de secciones (190),
     los botones − / + (38 y 6) y el campo de texto (200).
   - `recortar_a_ancho()` recorta con «...» (sin partir un carácter UTF-8) la etiqueta y la
     descripción de cada fila: la descripción nunca llega a la zona de los botones − / + y la
     etiqueta no pisa el valor.
   - Para reproducirlo en Linux: `MTP_FACTOR_DPI=2.0` con una pantalla virtual de 1920×1080
     (con 1280×720 la ventana se recorta al escritorio y no se ve el desborde).

4. **`recomp-ui-0004-textos-pendientes-en-espanol`** (0.4.3), encima del 0003, en
   `launcher_i18n.cpp` y `launcher_imgui.cpp`:
   - Unas 80 entradas nuevas en `kSpanish[]` y las llamadas a `ui_text()` que faltaban en la pantalla
     de asignación de controles, el selector de archivos, el explorador integrado y los avisos.
   - La tabla se busca por el texto inglés **exacto** y una misma palabra tiene una sola traducción
     en todo el programa. Por eso hay tres ayudantes: `etiqueta_direccion()` traduce solo
     Up/Down/Left/Right en las filas de asignación (si no, «Select» saldría como «Elegir» y «Up»
     como «Arriba» donde no toca); `etiqueta_atajo()` pasa «Alt+Return» a «Alt+Intro» y
     «Shift+P» a «Mayús+P» **solo al dibujar** (en `config.ini` sigue lo original); y el botón de
     subir carpeta del explorador usa la clave `Up##carpeta` (ImGui oculta lo que va tras `##`, así
     en inglés se ve «Up» y en español «Subir»).
   - `MTP_I18N_DEBUG=1` (solo depuración): escribe en `stderr`, una vez cada uno, los textos que
     `lookup()` no encuentra. **Ojo:** el lanzador dibuja muchos textos directamente con
     `ImGui::Text(...)`/`Button(...)`, que no pasan por la tabla y no salen en ese aviso; tras
     actualizar recomp-ui conviene mirar también `grep -n 'ImGui::\(Text\|Button\|TextColored\)(\s*"'
     launcher_imgui.cpp`. Es lo que se hizo para esta versión (se recorrieron unos 250 literales y se
     tradujeron los que puede ver quien usa la GBA; el resto son pantallas de otras consolas, mods o
     *netplay*, que este proyecto no muestra).

5. **`recomp-ui-0005-visor-de-capturas-y-aviso-de-version`** (0.4.4), encima del 0004, en
   `launcher_gl.c/.h`, `launcher_model.h`, `launcher_i18n.cpp` y `launcher_imgui.cpp`:
   - `launcher_texture_load_thumb(ruta, max_w, max_h, &ancho, &alto)`: carga con stb_image, reduce
     por un factor entero (promedio de bloques) hasta caber en `max_w × max_h` y sube una textura
     GL_LINEAR (una captura de 1200×800 ocupa 3,8 MB de textura; la miniatura de 300×200, ≈ 0,24 MB).
     Una imagen ilegible devuelve una textura con `id == 0` y el visor lo avisa (no se reintenta
     cada fotograma: `Foto::intentada`). La vista grande usa `launcher_texture_load` sin reducir.
   - `LNG_VIEW_CAPTURES` (nueva vista del modelo) y `namespace capturas` en `launcher_imgui.cpp`
     con `draw_capturas(LauncherModel*, const LauncherTheme&)`: lista `capturas/*.png` junto a
     `MTP_CONFIG_INI` (las 150 con el nombre mayor = más recientes), miniaturas perezosas (solo las
     visibles, y como mucho 2 por fotograma), vista grande con navegación y borrado en dos pulsaciones. El botón de la
     cabecera llama a `capturas::liberar()` antes de cambiar de vista para refrescar la lista.
   - Los cuadros de miniatura son `InvisibleButton` con `ImGuiButtonFlags_EnableNav`; sin eso ImGui
     no los puede enfocar con teclado/mando (aun así, dentro de las tarjetas la tecla Intro no entra,
     igual que en el panel original).
   - `eyebrow()` dibuja byte a byte: sus títulos van **sin tildes** («CAPTURAS»)
     porque no decodifica UTF-8.
   - Aviso de versión: el parche declara `extern "C" const char* mtp_aviso_actualizacion(void)` y
     `mtp_version_instalada(void)` **solo si** `MTP_EXTRAS_MENU` está definida (la pone el
     `CMakeLists.txt` del proyecto en el objetivo `game_launcher_ui`); si no, sustitutos que devuelven
     «» y nada cambia. Los define `src/aviso_actualizacion.cpp`, que se compila en el ejecutable.
     La franja de aviso solo se dibuja en el panel de inicio y se oculta con una variable estática
     por sesión (no se guarda).
   - Para regenerar el parche tras cambiar el árbol de pruebas: copiar el árbol, aplicar 0001–0004, y
     `git diff` de los 5 archivos; comprobar siempre con los dos aplicadores
     (`tools/aplicar_parches.py` y `tools/construir.ps1`) y que la segunda pasada diga «ya aplicado».
     El aplicador de Python elige los parches por el **nombre de la carpeta** (`recomp-ui`), así que
     una prueba hecha en una carpeta con otro nombre no encuentra nada.

6. **`recomp-ui-0006-partidas-de-emulador-en-el-menu`** (0.4.5), encima del 0005, en
   `launcher_model.h`, `launcher_i18n.cpp` y `launcher_imgui.cpp`:
   - `LNG_VIEW_PARTIDAS` (nueva vista) y `namespace partidas` con `draw_partidas(LauncherModel*,
     const LauncherTheme&)`; el botón «Partidas» de la cabecera está junto al de «Capturas».
   - La lógica **no** está en el parche: son funciones `extern "C"` de `src/partidas.h` /
     `src/partidas.cpp` (se compilan en el ejecutable; `game_launcher_ui` tiene `src` entre sus
     directorios de inclusión). Así se prueban sin el menú (`tools/pruebas/probar_partidas_menu.sh`).
   - La partida es la ROM elegida (`m->rom_full`) con la extensión cambiada a `.sav`. Importar:
     lee el origen, rechaza estados rápidos / vacíos / otros formatos / enormes, recorta el relleno
     (0xFF o 0x00) o la copia repetida de 64/128 KiB, completa con 0xFF lo que mida menos de 32 KiB,
     guarda una copia `partida_<sello>_<motivo>.sav` en `copias-de-partidas` (junto a `config.ini`) y
     escribe el `.sav` por un archivo temporal `.nueva` + renombrado (se borra el destino antes, por
     Windows). Si la copia falla, no se toca nada.
   - Selector de archivos: `ui_pick_file` / `ui_pick_save_file` (zenity o kdialog si existen; si no,
     el explorador integrado, que filtra por patrones y rechaza solo las extensiones que no encajan).
   - Textos: tabla `kSpanish` y `ui_text()`. Una etiqueta con `##` (por ejemplo «Open folder##copias»)
     debe armarse con `std::string(ui_text("Open folder")) + "##copias"`; si no, no se traduce.
   - Regenerar el parche: copiar el árbol, aplicar 0001–0005 y `git diff` de los 3 archivos; el
     aplicador de Python elige los parches por el nombre de la carpeta (`recomp-ui`).

### Aviso de versión: módulo y ajustes

`src/aviso_actualizacion.cpp` (solo se compila con `MTP_MENU=ON`):

- Estado atómico 0/1/2 (sin empezar / comprobando / terminado). La primera llamada a
  `mtp_aviso_actualizacion()` lanza el hilo (`CreateThread` en Windows, `std::thread` en el resto);
  hasta que termina devuelve `""`. Nunca bloquea el fotograma.
- Descarga: WinHTTP en Windows (plazos 4/4/4/6 s, solo código 200, máximo 256 bytes) y
  `curl -fsS --max-time 6` por `popen` en Linux. La dirección solo admite `[A-Za-z0-9-._~:/%+]`
  (por eso no hay nada que escapar en la orden de `curl`), `https://` o `http://127.0.0.1`/`localhost`.
- Versión: 2 a 4 partes numéricas, ninguna mayor que 100000; se compara parte a parte (por eso
  `0.4.10` > `0.4.3`). Cualquier otra respuesta se descarta.
- Ajustes (`config.ini`, `[Menu]`): `CheckUpdates` (`0`/`false`/`no` lo apaga) y `UpdateUrl`.
  `MTP_URL_VERSION` (entorno) manda sobre ambos. Valor por defecto: variable de CMake
  `MTP_URL_VERSION` (`-DMTP_URL_VERSION=…`); `MTP_VERSION` sale del archivo `VERSION`.
- Prueba: `tools/pruebas/probar_aviso.sh` (compila el módulo con un `main` mínimo y un
  `http.server` local; 12 casos).

## Filtros de imagen

La presentación es `SDL_Renderer` (Direct3D 11 en Windows): no hay cauce de *shaders*
propio, así que **no se pueden cargar los `.glsl`/`.glslp` de RetroArch**. El fotograma
terminado de 240×160 (formato `0xFFRRGGBB`) se filtra en la CPU, se sube a una textura
mayor y se dibuja en lugar de la normal. No tocan la emulación ni el fotograma que usan
las capturas de verificación.

**Por qué la 0.3.0 «solo desenfocaba».** Se generaba una imagen de 3× o 4× y la tarjeta la
estiraba a la ventana con filtro lineal en un factor casi nunca entero (1,5×, 2,67×…): eso
vuelve a mezclar los píxeles vecinos. La rejilla LCD y las líneas CRT, pintadas dentro de
esa imagen, quedaban convertidas en un velo gris. *HD smooth* encima suavizaba con un
núcleo [1 2 1]/4 (el 25 % de cada vecino). La 0.3.1 hizo dos cosas (la segunda cambió en
la 0.3.2):

1. **Replicación entera (`factor_post`)**: tras un ampliador (Scale2x/3x/4x, HD smooth) el
   resultado se replica 1–4 veces más (el mayor entero que cabe en la ventana, sin pasar de
   2048 px de ancho). Así el ajuste lineal final de la tarjeta suele ser de un factor menor
   de 2 y los bordes siguen nítidos. *Sharp fractional* usa la misma idea con `factor_nitido`
   (mayor entero que cabe, tope 6).
2. **Máscara a la resolución de la ventana (LCD y CRT).** La 0.3.1 multiplicaba una textura
   de máscara por encima con `SDL_BLENDMODE_MOD`; se veía bien con OpenGL y con Direct3D 9
   (Wine), pero dependía de que la tarjeta hiciera esa mezcla y de que la máscara cayera
   exacta en píxeles de pantalla. **Desde la 0.3.2 se compone por CPU** (`mtp_imagen_con_mascara`):
   a la imagen de 240×160 se le aplica la ganancia de brillo (`ganancia_mascara`, hasta
   ×1,4, porque la máscara solo oscurece) y se multiplica por la máscara a la resolución
   de la imagen en pantalla (`componer`: vecino más cercano de origen × gris de la
   máscara). Sale una textura `ARGB8888` del tamaño de la imagen en pantalla que se dibuja
   **sin filtro y sin mezclas especiales** (`mtp_copiar_compuesta`, en píxeles de ventana,
   sin el tamaño lógico de SDL), así que se ve igual con OpenGL, Direct3D o el renderer por
   software. Si la imagen en pantalla pasa de 1920×1080 se compone a `1/k` (`reduccion_mascara`,
   k entero, 2 para 1440p y 4K) y la tarjeta la estira sin filtro. Con menos de 2 píxeles de
   pantalla por píxel del juego no hay máscara y queda la imagen nítida normal.

| N | Filtro | Qué se genera | Coste medido* |
|---|---|---|---|
| 0, 1 | Nearest, Linear | nada (los hace SDL) | 0 |
| 2 | Sharp fractional | ampliación entera `factor_nitido` (≤ 6) | 0,28 ms (×6) |
| 3 | Scale2x (AdvMAME2x) + replicación | 2 × `factor_post` | 0,57 ms (×2, replicado ×3) |
| 4 | Scale3x (AdvMAME3x) + replicación | 3 × `factor_post` | 0,82 ms (×3, replicado ×2) |
| 5 | Scale4x (Scale2x dos veces) + replicación | 4 × `factor_post` | 0,32 ms (sin replicar) |
| 6 | HD smooth: Scale4x + suavizado [1 6 1]/8 horizontal y vertical + replicación | 4 × `factor_post` | 2,86 ms (sin replicar), 4,68 ms (replicado ×2) |
| 7 | LCD grid: máscara (raya de 1 px, el 14 % de la celda si es grande, deja pasar el 70 % de la luz) × imagen de origen | composición a la resolución de la imagen en pantalla | 0,33 ms a 720×480; 1,9 ms a 1920×1080 |
| 8 | CRT scanlines: máscara (4 muestras por fila, centro del haz a plena luz, bordes hasta el 45 %) × imagen de origen | ídem | ≈ 5 ms a 1920×1080 |

\* Por fotograma, en el entorno de pruebas (2 núcleos); el presupuesto es 16,7 ms. Construir
la máscara cuesta ≈ 8 ms (LCD) o ≈ 1 ms (CRT) a 1920×1080, **una sola vez** por cambio de
tamaño o de filtro. En la rejilla LCD la mayoría de las filas de la máscara se repiten
(`filas_repetidas`) y `componer` las copia en vez de recalcularlas (de 5,9 a 1,9 ms a
1080p). Si el renderer no admite una textura tan grande, el filtro se desactiva solo y se
dibuja la imagen normal.

- **Filtro en directo (0.3.2):** `HostWindow::cycle_image_filter` (atajos `ImageFilterNext`
  = F12 y `ImageFilterPrev` = Mayús+F12, configurables en `[KeyMap]`) cambia la variable
  `g_mtp_filtro`, ajusta `linear_filter` (solo el filtro 1 es lineal), pone el nombre en el
  título durante 3 s (en ASCII: con un guion largo, `SDL_SetWindowTitle` falla en X11 con la
  configuración regional C) y reescribe `image_filter`, `linear_filter` y `sharp_filter`
  en `config.ini` (solo las líneas que ya existen; escribe un `.tmp` y lo renombra).
  El interruptor «Linear filter» del menú del juego (`runtime_ui_get/set`) ahora mueve el
  filtro entre 1 y 0; antes solo tocaba `linear_filter` y **no tenía efecto con los filtros
  2–8**, que es probablemente lo que veía quien probaba filtros desde el menú del juego.
- **Sharp fractional** necesitaba un factor que depende de la ventana: `factor_nitido`
  usa el mayor entero que cabe (tope 6) y la tarjeta hace el último ajuste, de modo que
  con ventanas de tamaño fraccionario no aparecen píxeles de anchos desiguales. Antes la
  fila existía en el menú pero no hacía nada.
- **Cómo llega la elección al runtime:** el menú guarda `image_filter` en `config.ini`
  (`[Launcher]`) y pasa `--image-filter N`; `main.cpp` lo quita de los argumentos y fija
  `GBARECOMP_FILTRO` (como hace con `GBARECOMP_STRETCH`). **Ojo al probar:** si se arranca
  con cualquier argumento (por ejemplo `--load-state`) el menú se salta y `config.ini` **no
  se aplica**; hay que pasar `--image-filter N`, `--scale N`, etc. a mano.
- **Por qué el selector usa el catálogo de «texture filter» y no el de «sharp filter»:**
  en el panel *Display* de recomp-ui, la fila `has_sharp_filter` («Scaling filter») tiene
  prioridad sobre `has_texture_filter` y no admite el catálogo propio; con
  `launcher_expose_sharp_filter = false` aparece el selector de nueve opciones del anfitrión.
- **Se combina con el filtro de color de la GBA** (fila *Screen model*, `color_lut`):
  el color se aplica al convertir el fotograma y el filtro de imagen trabaja después
  sobre ese resultado. También con los tres modos de aspecto (en los modos 16:9 la imagen
  se dibuja en píxeles de ventana, sin tamaño lógico).
- **Escalado de Windows:** el proceso no declara que entiende PPP altos, así que con un
  escalado del 125 %/150 % Windows estira la ventana entera y emborrona las rayas de 1
  píxel. No se ha cambiado (hace falta probarlo en un Windows real); el README explica la
  opción de compatibilidad del `.exe` para quien la necesite.
- **Qué se comprobó y qué no:** capturas de la ventana real con Xvfb (OpenGL por software)
  y con Wine (Direct3D 9) en pantalla completa 1280×720, ventana 3× y modos 16:9, y las
  pruebas de `tools/pruebas/filtros_test.cpp`. **No** se ha visto con Direct3D 11 en un
  Windows real.

## Avance rápido (Tab)

Con la tecla de avance rápido (`Turbo`, por defecto Tab, mientras se mantiene) el bucle de
`run_game()` emula N fotogramas por cada uno que dibuja (N = `assist_fast_forward_multiplier`,
de 2 a 10, por defecto 4) y silencia el audio. En cada fotograma dibujado el
`FramePacer::wait_for_next_frame()` espera hasta 1/59,7275 s. En la 0.3.0 solo se dibujaba
cuando `frame % N == 0`: si el equipo no llegaba a N veces la velocidad, cada dibujo
tardaba más de 16,7 ms y el contador de fps caía a ≈ 38. La 0.3.1 añadió un dibujo por
tiempo (12 ms), pero seguía **rasterizando los N fotogramas** y esperando en el pacer, así
que el avance real era de solo ≈ ×1,2–1,7: quien lo probaba notaba «60 fps igual que sin
Tab».

El parche 0006 (reescrito en la 0.3.2 y la 0.3.3) hace cuatro cosas:

1. **No pinta los fotogramas que no se van a dibujar.** `GbaPpu::set_rasterization_enabled`
   (ya existía) se activa solo en el fotograma que toca dibujar; en los demás el PPU sigue
   llevando los registros y el seguimiento afín pero no rasteriza las 160 líneas.
2. **Reparto de imágenes según el coste medido (0.3.3).** En cada gancho de dibujado se
   miden, con media móvil, `mtp_e_ms` (coste de un fotograma emulado sin dibujar: emulación
   + gancho, sin esperas) y `mtp_d_ms` (sobrecoste de uno dibujado: pintar, componer el
   filtro, presentar). Las muestras se recortan (×2,5 y ×4) para que un tirón del sistema no
   dispare la media, y cada 30 fotogramas seguidos dibujados se salta uno para que `e` no
   se quede sin muestras. La imagen siguiente se pide cuando `transcurrido + e + d ≥ t_img`,
   con `t_img = clamp(d / 0,30; 16,74; 66)` ms (dibujar no se come más del 30 % del tiempo,
   entre 60 y ≈ 15 imágenes/s), o cuando se alcanzan `tope = ceil(N · t_img / 16,74)`
   fotogramas. Antes (0.3.1/0.3.2) era «cada N fotogramas o 11 ms», lo que en un equipo al
   que dibujar le cuesta ≈ 30 ms dejaba el juego en ×1,4 con 21 imágenes/s.
3. **Tope ×N con reloj acumulado, sin pacer.** Tras cada imagen `mtp_meta += fotogramas ·
   16,74 / N` y se espera hasta `mtp_meta` solo si se va por delante (`sleep_until` + giro
   fino). Si se va por detrás no se espera y, pasados 100 ms de retraso, la meta se
   reinicia (no se «recupera» tiempo perdido). El pacer (`FramePacer`) sigue mandando en
   juego normal.
4. **Nunca se dibuja un fotograma que el PPU no pintó.** `GbaPpu::latched_is_rasterized()`
   (`frame_skipped_` se activa si se salta alguna línea visible y se limpia al pasar de
   fotograma; el fotograma enganchado en el VBlank solo cuenta como pintado si la
   rasterización estuvo activa en todas sus líneas). Sin esto, el gancho de dibujado del
   bucle exterior (que corre a `vcount = 0` del fotograma siguiente) enseñaba el
   fotograma enganchado anterior, que estaba a cero: ≈ 15–18 % de las capturas salían
   en negro. Con la comprobación: 0 de ≈ 4.000 capturas (también pulsando y soltando Tab
   y cargando estado en pleno turbo).

El título muestra `<título> - turbo xN.N | N img/s | emu X ms | dib Y ms` cada segundo
mientras dura el turbo (velocidad = fotogramas emulados por segundo / 59,7275). Con
`GBARECOMP_MTP_DIAG=1` se escribe también por `stderr`. Sin avance rápido no cambia nada
(`mtp_toca_dibujar` devuelve `true`, la rasterización está activa, el indicador de
fotograma pintado es siempre cierto y se sigue esperando con el pacer).

**Dónde se iba el tiempo (0.3.3).** Perfil con callgrind de 60 fotogramas de un partido
(`valgrind --tool=callgrind ./MarioTennisPowerTourRecomp --frames 60 --load-state …`):
la comprobación `ram_coincide_con_rom` de `src/main.cpp` se ejecuta por cada instrucción
de código recompilado de IWRAM (`runtime_should_yield` llama al gancho
`forzar_interprete` en cada prólogo) y leía 8 palabras por `bus_read_u32` (puente del bus,
≈ 100 instrucciones cada una): ≈ 1,3 mil millones de instrucciones, más del 25 % del total
y > 35 % del bucle de juego. Con la comparación directa de 16 bytes (`memcmp` contra
`iwram_ptr()` y `rom_ptr()`) bajó a ≈ 0,1 mil millones. Lo que queda del bucle: el
rasterizado del PPU (≈ 30 %, que el turbo ya se salta en los fotogramas intermedios), el
intérprete de las rutinas de IWRAM que el juego se autoescribe y de los módulos de EWRAM
(≈ 18 % del total medido, un paso por instrucción con copia de estado: `runtime_force_interp_step`) y el
reloj/temporizadores (`runtime_tick`).

**Límite real: la CPU.** Emular el juego cuesta ≈ 4–7 ms por fotograma en el entorno de
pruebas (2 núcleos, sin GPU), así que ahí el turbo llega a ≈ ×2,4 y no a ×4 o ×10. En un
equipo con más potencia sube hasta el multiplicador. No se ha medido en Windows real.
Ideas pendientes para ir más rápido: acelerar `runtime_force_interp_step` (no recargar el
estado de la CPU en cada paso) y compilar los *shards* con `-O2` en vez de `-O1`
(`MTP_SHARD_OPT`), a costa de mucho más tiempo de compilación en la instalación.

## Partidas

- El `.sav` es la SRAM de 32 KiB en bruto, sin cabecera: el mismo formato que usan los
  emuladores. Ruta: la de la ROM con la extensión `.sav` (en la instalación,
  `roms\mario_tennis_power_tour_eur.sav`), salvo que `game.toml` indique otra con `save_path`.
  `PARTIDAS.ps1` la deduce de `rom.cfg`.
- Estados F1–F9: `<rom>.stateN`, formato propio del runtime. **No son** estados de
  emulador y no se pueden convertir entre ellos.
- `tools/PARTIDAS.ps1` importa/exporta con comprobación (`Probar-Sav`: rechaza estados
  rápidos y archivos comprimidos, recorta relleno igual que el parche 0005, completa con
  `0xFF` los archivos cortos, avisa de partidas en blanco), hace copias en
  `copias-de-partidas\` antes de sobrescribir y se niega a trabajar con el juego abierto.
  El instalador lo copia como `Partidas.ps1`/`Partidas.bat` y crea su acceso en el menú
  Inicio; el desinstalador conserva también `*.sav.*` (copias y `.original`).

## Por qué no hay vista ampliada real (16:9 de verdad)

El framework permite que un juego declare `view_width` mayor de 240 y dibuje
más escenario en los márgenes, pero el juego tiene que rellenarlos (Mega Man
Zero lo hace). Mario Tennis no tiene datos fuera de los 240 px: la prueba con
284×160 dio márgenes negros en menús, modo historia y partido. Por eso se ofrecen
solo los tres modos de presentación.

## Autocuración y registro de fallos

Cuando el juego salta a una dirección sin código nativo, el runtime la ejecuta
con el intérprete y apunta la dirección. Si hay `gcc` (o `tcc`) disponible, la
compila en caliente en `recomp_cache/` y la reutiliza al siguiente arranque. Al
cerrar con normalidad escribe `recomp_master_misses_BTMP.toml.frag`;
`tools/fusionar_fallos.py` convierte las direcciones seguras en `[[extra_func]]`
de `game.toml` (ROM y los tramos de IWRAM que son copia de ROM; ignora BIOS,
EWRAM y zona de pila, que se interpretan a propósito).

## Fondo roto en Windows (y por qué `game.toml` tiene ~900 entradas)

Un Windows 11 real mostró la pantalla «¿Quieres un chico?» con los fondos hechos
de trozos de letras. Causa: sin `gcc` ni `tcc` en el equipo el autocurado no puede
compilar nada y todo salto a una dirección que no está en `game.toml` pasa por el
intérprete. Había dos problemas:

1. **La BIOS libre** vuelve de cada interrupción por `0x00000120` (`add lr, pc, #0`
   antes de llamar al manejador del juego). Esa dirección no estaba en
   `bios_libre/bios_libre.toml`, así que cada IRQ (decenas de miles) pasaba por el
   intérprete y la carga de gráficos quedaba corrompida. En Linux no se notaba
   porque `gcc` la compilaba en el primer segundo. Ahora está como
   `exception_irq_retorno`.
2. **Funciones de la partida nueva y del partido** que solo se habían probado con
   partidas guardadas. Se jugó una partida nueva en los cinco idiomas, un paseo
   aleatorio por menús y escenarios y un partido, y se fusionaron los fallos
   (`tools/fusionar_fallos.py`). Con eso el partido deja de interpretar su lógica.

Para comprobar que algo no depende del compilador: `GBARECOMP_SELFHEAL_RECOMPILE=0`.
Con esa variable solo deben quedar sin cubrir `0x030009A4` y `0x03001400`
(el descompresor copiado a IWRAM, que se interpreta a propósito) y, según la
pantalla, direcciones de EWRAM.

## Dónde se compila (carpeta de obra)

Compilar necesita ≈ 1,5 GB libres (herramientas, fuentes y objetos; se borra al terminar
salvo «Conservar los archivos de compilación»). `Obtener-DirObra` (`tools/INSTALAR.ps1`)
elige dónde, por este orden:

1. La carpeta conservada de una instalación anterior (`instalacion.json` → `obra`), si
   todavía tiene `build\`: ya está casi todo compilado y casi no hace falta espacio.
2. `%LOCALAPPDATA%\MarioTennisPowerTour\obra` (lo de siempre), si la ruta es corta y sin
   acentos ni espacios (`$LongitudMaxObra`, Zig y CMake las llevan mal) **y** su unidad
   tiene el espacio necesario.
3. `<unidad>\MTP-obra` en la primera unidad con sitio: la del juego, y luego los demás
   discos fijos de más a menos espacio libre (si el perfil tiene acentos, primero la del
   sistema, como antes). Avisa de cuál usa.
4. Si ninguna llega, devuelve la de siempre y `Comprobar-Espacio` explica qué falta.

Hasta la 0.3.3 se usaba siempre el paso 2: con el juego en `D:` pero `C:` casi llena
(1,3 GB libres) la actualización fallaba con «No hay espacio suficiente para compilar».
Todo lo que escribe la compilación va dentro de la carpeta de obra (`descargas`,
`herramientas`, `cache-zig`, `build`), así que no hace falta más; fuera solo queda el
registro del instalador en `%TEMP%` (unos KB). `tools/pruebas/probar_obra.ps1` simula discos
con más o menos espacio.

## Por qué el instalador ligero usa Zig (y no MSYS2)

El método clásico instalaba MSYS2 y gcc (≈ 3 GB en disco) solo para compilar. Zig trae
un compilador de C y C++ completo (clang) y las bibliotecas de C de MinGW dentro de
un único programa de ≈ 100 MB, y sabe compilar de forma cruzada. `construir.ps1`:

- Descarga las ruedas de PyPI (`ziglang`, `cmake`, `ninja`; son zips con el `.exe`
  dentro, y PyPI da la URL directa y el SHA-256) y SDL2 `-devel-…-mingw.tar.gz` de la
  versión oficial. No hay instalador, no se toca el registro ni el `PATH`.
- Usa Zig como `gcc`/`g++` con envoltorios `.cmd` (`zig cc -target x86_64-windows-gnu`)
  y un `zig-windows.cmake` como cadena de herramientas. Con ese destino el `.exe`
  sale sin dependencias de `libstdc++`, `libgcc` ni `winpthread`: solo necesita
  `SDL2.dll`.
- Baja las fuentes como zips por commit en lugar de clonar. Para eso hace falta
  `toml++` aparte: `gbarecomp` lo clonaría con git al configurar, pero si ya está en
  `externo/gbarecomp/third_party/tomlpp` lo usa tal cual. El submódulo
  `arm-recomp-core` también va por su zip.
- Aplica los parches con un aplicador propio (analiza los bloques `@@`, busca el
  contexto cerca de la línea indicada y reconoce un bloque ya aplicado). Probado
  contra `git apply`: mismo resultado byte a byte, y es idempotente.
- Solo regenera el C++ y solo recompila lo que ha cambiado: guarda una huella
  (`game.toml`, BIOS, parches, recompilador, ROM) junto a `generated/`. Al copiar los
  archivos del proyecto a la carpeta de trabajo les pone la fecha de ahora cuando
  cambian, porque Ninja decide por fechas y la de un zip puede ser anterior a la de
  lo ya compilado.
- Todo queda dentro de la carpeta de trabajo (`herramientas/`, `descargas/`,
  `cache-zig/`, `externo/`, `build/`, `generated*/`): borrarla no deja rastro.

Cosas que se aprendieron probándolo:

- `zig.exe` de Windows no se pudo probar aquí: bajo Wine (9 y 11, esta última en
  su variante wow64) falla con `CacheCheckFailed` / `manifest_create Unexpected`
  nada más compilar algo, porque Wine no implementa un parámetro de `NtLockFile`
  (`fixme:file:NtLockFile Unimplemented yet parameter`) que Zig usa en su caché. Es
  una limitación de Wine, no de Zig en Windows, pero no está comprobado. Por eso la
  prueba usa el Zig de Linux haciendo de compilador cruzado. `cmake.exe` y
  `ninja.exe` de Windows sí se ejecutaron bajo Wine (configurar funcionó).
- `$nombre:` dentro de una cadena de PowerShell se lee como una variable con
  ámbito: hay que escribir `${nombre}:`.
- `Get-Item` no ve archivos ocultos sin `-Force` (en Linux, los que empiezan por
  punto), y eso rompía la copia de `.gitignore`.
- Zig mete una comprobación de comportamiento indefinido en C: se desactiva con
  `-fno-sanitize=undefined` (en C++ no hace falta, pero no molesta). Los avisos se
  silencian con `-w`: el código generado produce miles.

`ACTUALIZAR.ps1` guarda en `instalacion.json` la versión, una huella SHA-256 de lo que
decide cómo sale el juego (`game.toml`, `CMakeLists.txt`, BIOS libre, parches, `src/`,
`construir.ps1/.sh`) y el método usado. Si la huella nueva coincide, no hay nada que
actualizar. Si el usuario conservó la carpeta de compilación, se reutilizan las
herramientas y lo ya compilado.

## Variables de entorno útiles

| Variable | Efecto |
|---|---|
| `GBARECOMP_SELFHEAL_VERBOSE=1` | Detalle por dirección de la autocuración |
| `GBARECOMP_NESTED_BRIDGE_BUDGET=N` | Presupuesto del puente anidado (0 = sin límite) |
| `GBARECOMP_INPUT_REPLAY=fichero` | Repite entradas (`fotograma,0xTECLAS`; 0 = pulsado; bits A,B,Select,Start,Derecha,Izquierda,Arriba,Abajo,R,L) |
| `GBARECOMP_DIAGNOSTICS=0` | Sin carpeta de diagnósticos (es lo que usa `main.cpp` por defecto) |
| `GBARECOMP_STRETCH=1\|2` | Modo de pantalla 16:9 (lo fija el menú) |
| `GBARECOMP_FILTRO=0..8` | Filtro de imagen (lo fija el menú; ver «Filtros de imagen») |
| `MTP_IDIOMA_MENU=es\|en` | Fuerza el idioma de los menús (pruebas); manda sobre lo elegido en el selector |
| `MTP_I18N_DEBUG=1` | Los menús escriben en `stderr` cada texto en inglés sin traducción (solo lo que pasa por la tabla; ver parche 0004) |
| `MTP_URL_VERSION=https://…/VERSION` | Dirección del `VERSION` para el aviso de versión nueva (pruebas; manda sobre `config.ini`). Para pruebas locales vale `http://127.0.0.1:PUERTO/VERSION` |
| `MTP_CONFIG_INI=ruta` | Ruta del `config.ini` donde los menús guardan el idioma (`[Menu] Language`); la fija `main.cpp` junto al ejecutable |
| `SDL_WINDOWS_DPI_AWARENESS=unaware` | Vuelve a que Windows estire la ventana (por defecto `permonitorv2`) |
| `MTP_FACTOR_DPI=1.5` | Simula un escalado del 150 % (para probar el ajuste de ventana y de menú en cualquier sistema) |
| `--frames N --dump-png f.png` | Ejecuta N fotogramas sin ventana y guarda una captura |
| `--tcp PUERTO` | Servidor de depuración (avanzar fotogramas, estados, captura, audio) |
