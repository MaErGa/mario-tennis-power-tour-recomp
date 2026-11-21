# Registro de cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). El número
de versión está en el archivo `VERSION` (lo lee `ACTUALIZAR.bat` para saber si hay algo nuevo).

## [0.4.5] — 2026-11-20

### Añadido
- **Importar y exportar partidas de emulador desde el menú de arranque.** Botón **«Partidas»** en la
  cabecera del menú (el que sale antes de empezar el juego). Pantalla con la ruta y la fecha de tu
  partida actual y estos botones: *Importar de un emulador…*, *Exportar a un emulador…*, *Hacer copia
  ahora* y *Abrir carpeta*; debajo, la lista de copias de seguridad con *Recuperar*.
  - **Importar:** eliges el `.sav` (o el `.srm` de RetroArch) con el selector de archivos del sistema
    (o con el explorador integrado si no hay uno), el menú lo comprueba, te enseña qué va a usar y
    pide *Confirmar*. **Antes de sustituir tu partida guarda una copia** en `copias-de-partidas`
    (junto a `config.ini`, con el nombre `partida_<fecha>_<motivo>.sav`). Si no se puede hacer la
    copia, no se toca nada.
  - **Qué acepta:** archivos de 32 KiB; los que traen relleno (`0xFF`/`0x00`) o la misma partida
    repetida hasta 64 o 128 KiB se recortan a 32 KiB; los que miden menos se completan con `0xFF`.
    Avisa si la partida está en blanco.
  - **Qué rechaza (sin tocar nada):** los estados rápidos (*save states*) de emuladores, los
    archivos vacíos, los que traen datos de otro tipo de guardado (Flash, EEPROM, otro juego) y los
    enormes.
  - **Exportar:** escribe tu partida (32 KiB, igual byte a byte) donde elijas; si el nombre no lleva
    extensión añade `.sav`. No cambia tu partida. Recuerda que para usarla en un emulador debe
    llamarse como la ROM de ese emulador.
  - Español e inglés.
- `src/partidas.h` y `src/partidas.cpp` (la lógica, en C, sin depender del menú) y
  `tools/pruebas/probar_partidas_menu.sh`, que la compila con un `main` de prueba y comprueba
  90 casos (tamaños, relleno, copias repetidas, estados rápidos, copias de seguridad, restaurar,
  rutas con espacios y con tildes). La CI también lo ejecuta.

### Cambiado
- Parche nuevo `parches/recomp-ui-0006-partidas-de-emulador-en-el-menu.patch` (3 archivos de
  recomp-ui: `launcher_model.h`, `launcher_i18n.cpp`, `launcher_imgui.cpp`), encima del 0005.
  Idempotente y aplicable con `aplicar_parches.py`, `construir.ps1` y la CI.
- El ejemplo del aviso de versión del README y de la plantilla de errores usan ahora 0.4.5/0.4.6.

### Por qué está en el menú de arranque y no en el de `Esc`
- Con el juego en marcha, al cerrarse volvería a guardar su SRAM en memoria encima de la partida
  importada. Antes de empezar, el juego no ha cargado nada y la importación es segura.

### Lo que no se ha podido probar
- **Un Windows real:** el selector nativo de archivos y «Abrir carpeta». En Linux se probó con la
  ventana real (Xvfb): importar con relleno y copia previa, exportar (idéntico al original),
  recuperar una copia y los mensajes de rechazo.
- **Una partida jugada de verdad en un emulador** (mGBA, RetroArch…): se probó con archivos de prueba.

## [0.4.4] — 2026-11-15

### Añadido
- **Visor de capturas dentro del menú de arranque.** Botón «Capturas» en la cabecera del menú:
  muestra en una rejilla las capturas de la carpeta `capturas` (las 150 más recientes, la última
  primero, con su fecha y hora). Al pulsar una se abre grande, con «Anterior» / «Siguiente»,
  «Borrar» (hay que pulsarlo dos veces; la primera lo arma y lo dice en el propio botón),
  «Abrir carpeta» (la abre en el explorador del sistema) y «Cerrar» (vuelve a la rejilla). Sin capturas, una carpeta que no existe o
  una imagen dañada salen con un aviso, sin cerrar el menú. Español e inglés.
- **Aviso de «hay una versión nueva» al abrir el menú.** Al abrir el menú de arranque se pide, en
  segundo plano y sin retrasar nada, el archivo `VERSION` del repositorio (unos pocos bytes). Si es
  mayor que la versión instalada, sale una franja arriba con el número y un botón «Ocultar»
  (solo en la pantalla de inicio del menú).
  **Solo avisa**: no descarga ni instala nada; para actualizar se sigue usando `ACTUALIZAR.bat` del
  zip nuevo. Sin internet, con una dirección que no responda o con una respuesta que no sea un
  número de versión, no sale nada. Se desactiva con `[Menu] CheckUpdates = 0` en `config.ini`
  y la dirección se cambia con `[Menu] UpdateUrl = https://…` (o al compilar, con
  `-DMTP_URL_VERSION=…`). Solo se admiten direcciones `https://` (y `http://` hacia la propia
  máquina, para pruebas).
- `src/aviso_actualizacion.cpp` (el módulo del aviso) y `tools/pruebas/probar_aviso.sh`, con 12
  casos contra un servidor local (versión nueva, igual, anterior, `0.4.10` frente a `0.4.3`,
  basura, 404, sin servidor, dirección externa `http` rechazada, intento de inyección con
  comillas, `CheckUpdates = 0`, `UpdateUrl` en el ini). La CI también lo ejecuta.

### Cambiado
- Parche nuevo `parches/recomp-ui-0005-visor-de-capturas-y-aviso-de-version.patch` (5 archivos de
  recomp-ui: `launcher_gl.c/.h`, `launcher_model.h`, `launcher_i18n.cpp`, `launcher_imgui.cpp`),
  encima del 0004. Idempotente y aplicable con `aplicar_parches.py`, `construir.ps1` y la CI.
- El menú dice «Capturas» y no «Screenshots» y el resto de textos nuevos llevan su traducción;
  los mensajes de estado del visor (borrada, no se pudo borrar, no se pudo leer la imagen) también.

### Sobre el perfil por mando
- Ya existía en recomp-ui («Guardar / Renombrar / Borrar perfil» por mando, ligado al identificador
  del mando) y desde 0.4.3 está traducido. El teclado guarda su asignación solo en `keybinds.ini`.
  **No se ha podido probar con un mando físico** (el entorno de pruebas no tiene ninguno).

### Corregido
- **La comprobación de Linux de GitHub Actions fallaba al subir el repositorio desde Windows**: allí los
  `.sh` pierden el permiso de ejecución y llamarlos directamente da «Permission denied» (salía en rojo
  a los 14 s, en el paso de los filtros). El workflow, el README y `CONTRIBUTING.md` los ejecutan ahora con
  `bash tools/…`, que funciona con o sin ese permiso. Reproducido en local quitando el permiso a los scripts.

### Sin comprobar
- La descarga del aviso en **Windows** (WinHTTP) está compilada pero **no se ha ejecutado en un
  Windows real**; en Linux (con `curl`) sí, con las 12 pruebas de arriba.
- «Abrir carpeta» llama a `SDL_OpenURL`; no se puede ver en la pantalla virtual de pruebas.
- Navegar por las miniaturas solo con teclado/mando: el menú entra en las tarjetas igual que el
  original (no se puede pulsar Intro dentro de ellas); con el ratón funciona todo.
- La dirección de comprobación por defecto (`raw.githubusercontent.com/MaErGa/…/main/VERSION`) es
  la prevista para el repositorio; si lo publicas con otro nombre o rama, cámbiala como se dijo.

## [0.4.3] — 2026-11-14

### Cambiado
- **Lo que quedaba en inglés en los menús, traducido.** Ahora salen en español (y siguen en inglés
  si eliges «English» en «Idioma del menú»): la pantalla de **asignación de controles**
  (títulos «Asignación del teclado/mando», «Asignar todos», «Valores por defecto», «[ pulsa una
  tecla... ]», «Asignando 3/10: pulsa Arriba», «Escuchando...», cancelar, guardar/renombrar/borrar
  perfil), los **nombres de las direcciones y de las teclas** (Arriba, Abajo, Izquierda, Derecha,
  Intro, Mayús der., Ctrl izq.…), los **modelos de pantalla** («Sin filtro», «Sin luz», «Luz
  frontal», «Luz trasera», «Clásica»), los **atajos** de los ajustes («Alt+Intro», «Mayús+P»,
  «Teclado num. +»), el aviso de **«Saltar el lanzador al arrancar»**, los mensajes del selector
  de archivos («(integrado)», «No hay selector de archivos…») y todo el **explorador de archivos
  integrado** (título, «Subir», «Inicio», «Archivo», «Usar el archivo elegido», avisos de error).
  Los botones de la consola (A, B, L, R, Start, Select) conservan su nombre, que es el que lleva el
  mando de verdad. Solo cambia lo que se dibuja: `config.ini` y `keybinds.ini` siguen guardando
  `Return`, `Shift+P`, etc., así que las configuraciones existentes siguen valiendo.
- Parche nuevo `parches/recomp-ui-0004-textos-pendientes-en-espanol.patch`, que además añade
  `MTP_I18N_DEBUG=1`: con ella el menú escribe en la consola cada texto en inglés que pasó por la
  tabla de traducciones sin tener entrada, para encontrar lo que falte tras actualizar recomp-ui.
- Comprobado con capturas de la ventana real del menú de arranque (inicio, configurar mando,
  asignación automática, ajustes, aviso, explorador integrado) en español y en inglés.

## [0.4.2] — 2026-11-14

### Corregido
- **Menú de Esc desbordado con el escalado de Windows.** Con el escalado al 150 %/200 % el
  texto del menú crecía pero el panel no (seguía en 780 píxeles): el título se pisaba con
  «Ajustes de Game Boy Advance», las descripciones salían cortadas y el pie chocaba con el
  botón «Continuar» (visto en una captura de un Windows real con la ventana a escala 6).
  Ahora todas las medidas del panel (ancho, alto, márgenes, columna de secciones, altura de
  fila, botones − / +, campo de texto) se multiplican por el mismo factor que el texto, y el
  panel es algo más ancho también sin escalado (900 en vez de 780 píxeles, el máximo que cabe
  en la ventana). Si aun así un texto no cupiera (otro idioma, ventana pequeña), se recorta con
  «...» en lugar de pisar otros controles o cortarse a mitad de letra. Parche nuevo
  `parches/recomp-ui-0003-menu-de-esc-con-escalado-de-windows.patch`. Comprobado con capturas
  simulando factores de 1,5 y 2,0 con la ventana a 1440×960.

## [0.4.1] — 2026-11-14

### Añadido
- **Selector «Idioma del menú» (Español / English).** Está en los ajustes del menú de arranque
  (al final del panel de pantalla) y en el menú de Esc dentro del juego (sección Sistema, última
  fila). Cambia **solo los menús**, nunca el idioma del juego (ese sigue en la pantalla de
  selección de idioma del propio juego). El cambio se aplica al instante, sin reiniciar, y se
  recuerda en `config.ini`, sección `[Menu]`, clave `Language` (`es` o `en`); el actualizador
  conserva ese archivo. Sin elección guardada se usa el idioma de compilación (`es`).
  Parche nuevo `parches/recomp-ui-0002-selector-de-idioma-del-menu.patch`. `src/main.cpp` fija
  la variable `MTP_CONFIG_INI` (ruta de `config.ini` junto al ejecutable) para que los menús
  sepan dónde guardarlo.
- La fila elegida del menú de Esc ahora se desplaza hasta verse entera al moverse con el
  teclado (antes, en la sección Sistema, la última fila quedaba cortada por abajo).

### Cambiado
- `MTP_IDIOMA_MENU=es|en` (variable de entorno) sigue existiendo, pero ahora solo sirve para
  forzar el idioma en pruebas: manda sobre lo elegido en el selector. La opción de CMake
  `MTP_IDIOMA_MENU` pasa a ser el idioma por defecto antes de que la persona elija.

## [0.4.0] — 2026-11-12

Tres novedades pedidas tras la 0.3.4: el menú en español, una tecla de capturas y la imagen
nítida con el escalado de Windows.

### Añadido
- **Menú en español.** El menú que se abre con **Esc** (Pantalla, Gráficos, Sonido, Sistema:
  pantalla completa, tamaño de ventana, filtro lineal, volumen, estados guardados, reiniciar,
  salir…) y el menú de arranque (ROM, mando, ajustes) salen en español de España, con tildes
  y ñ. Las traducciones van en un parche nuevo para recomp-ui
  (`parches/recomp-ui-0001-menu-en-espanol.patch`), que `construir.sh`, `construir.ps1` y la
  CI aplican igual que los de gbarecomp. Opción de CMake `MTP_IDIOMA_MENU` (`es` por
  defecto, `en` para el inglés original) y, para probar sin recompilar, la variable de
  entorno `MTP_IDIOMA_MENU=en`. Lo que recomp-ui no traduce de fábrica (modelos de pantalla
  como «Raw», nombres de mods y de red) sigue en inglés. El pie del menú ahora dice
  qué teclas usar («Intro / A  Elegir    Esc / B  Atrás    Flechas  Mover») en lugar de
  repetir «Select» y «Back».
- **Captura de pantalla con F10** (parche 0007). Guarda la imagen del juego, sin filtros ni
  marcos y ampliada con vecino más cercano (1200×800 en el modo 3:2), como PNG en la carpeta
  `capturas`, junto a `config.ini`, con el nombre `MarioTennis_AAAA-MM-DD_HH-MM-SS.png`. El
  título de la ventana avisa unos segundos. Funciona también con el juego en pausa. La tecla se
  cambia en `config.ini`, `[KeyMap]`, `Screenshot`. El escritor de PNG ahora comprime
  (DEFLATE con Huffman fijo, sin zlib): una captura pesa ≈ 70 KB en vez de ≈ 3 MB. Con el
  menú de Esc abierto la tecla no responde: ciérralo antes. El desinstalador conserva la
  carpeta `capturas` cuando eliges conservar las partidas.

### Cambiado
- **Imagen nítida con el escalado de Windows (125 %, 150 %…)** (parche 0008 y
  `src/main.cpp`). El programa se declara «consciente del DPI por monitor»
  (`SDL_WINDOWS_DPI_AWARENESS=permonitorv2`, que SDL lee al iniciar el vídeo): Windows deja de
  estirar la ventana y las líneas de 1 píxel de la rejilla LCD y de las líneas CRT se dibujan
  tal cual. Para que la ventana no se vea más pequeña, la escala se ajusta al factor de
  Windows **en múltiplos enteros** (con escala 3 al 150 % la ventana pasa a 4×, nunca a un
  4,5× con píxeles desiguales) y se recorta para que quepa en el escritorio; el menú de Esc
  se agranda con el mismo factor. En el menú «Window scale» muestra ya la escala real.
  Para volver al comportamiento anterior (Windows estira la ventana): variable de entorno
  `SDL_WINDOWS_DPI_AWARENESS=unaware`. **Ya no hace falta** el truco de las propiedades del
  `.exe` que decía el README. **No se ha podido probar en un Windows real**: el factor se
  simuló en Linux con `MTP_FACTOR_DPI=1.5`.
- `tools/aplicar_parches.py` elige los parches por el nombre de la carpeta
  (`gbarecomp-*.patch` o `recomp-ui-*.patch`).

### Pruebas
- `tools/pruebas/probar_desinstalar.ps1`: el desinstalador conserva partidas, ajustes y
  capturas, y sin esa opción no deja nada (también en GitHub Actions).

## [0.3.4] — 2026-11-08

### Corregido
- **ACTUALIZAR (e INSTALAR) fallaba con «No hay espacio suficiente para compilar» aunque el
  juego estuviera en una unidad con mucho sitio.** La carpeta temporal de compilación
  (≈ 1,5 GB, se borra al terminar) iba siempre al perfil del usuario, normalmente en `C:`
  (en el caso real: 1,3 GB libres en `C:` y el juego en `D:`). Ahora, si esa unidad va justa,
  se usa `<unidad>\MTP-obra` en la unidad donde está el juego y, si tampoco llega, en el disco
  fijo con más espacio libre; avisa de cuál usa. Si ya hay una carpeta de compilación
  conservada de una instalación anterior se reutiliza. Si ninguna unidad tiene sitio, el
  error lo explica (hay que liberar espacio en alguna). Prueba automática nueva:
  `tools/pruebas/probar_obra.ps1` (también en GitHub Actions).

## [0.3.3] — 2026-11-08

Tercera ronda del avance rápido. Con la 0.3.2 el título mostraba «turbo x1.4 — 21.1 fps» y
la pregunta era por qué bajan los fps al pulsar Tab y por qué el juego apenas aceleraba.

### Corregido
- **El juego gastaba más de un tercio de su tiempo en una comprobación propia de este
  port** (`src/main.cpp`, `ram_coincide_con_rom`). Cada vez que el código recompilado de
  IWRAM empieza una instrucción hay que comprobar que la RAM sigue igual que la ROM, y se
  hacía leyendo 8 palabras por el puente del bus (con sus contadores, comprobaciones y
  vigilancia de bucles de espera). Ahora se comparan los 16 bytes directamente en memoria
  (IWRAM y ROM no tienen efectos al leerse; si hubiera una sustitución de lecturas de
  ROM activa se usa el camino de antes). **Resultado idéntico, mucho más barato**: medido
  con callgrind en un partido, de 5,10 a 3,90 mil millones de instrucciones en 60
  fotogramas (≈ −34 % sin contar el arranque), y el turbo del entorno de pruebas pasa de
  ≈ ×1,7 a ≈ ×2,4. También da más margen en juego normal en equipos justos.
- **Avance rápido (parche 0006, reescrito otra vez): el reparto de imágenes se adapta al
  equipo.** Antes se dibujaba una imagen cada N fotogramas (o cada 11 ms): en un equipo
  al que dibujar le sale caro eso dejaba poco tiempo para emular. Ahora el programa mide
  cuánto cuesta emular un fotograma y cuánto cuesta dibujar uno más, y dibuja solo lo
  justo para que dibujar no pase del 30 % del tiempo (entre 60 y ≈ 15 imágenes por
  segundo). El tope ×N se hace con un reloj acumulado que no «recupera» esperas pasadas:
  si el equipo no llega, el juego va a tope y no espera nunca. Sin parpadeos en negro
  (0 de ≈ 4.000 capturas, también al pulsar/soltar Tab y cargar un estado).

### Cambiado
- **El título muestra ahora diagnóstico mientras mantienes Tab**: `turbo x2.4 | 31 img/s |
  emu 4.1 ms | dib 9.7 ms` (velocidad real, imágenes dibujadas por segundo, coste de
  emular un fotograma y sobrecoste de dibujar uno). Sirve para saber qué limita el turbo
  en cada equipo; si algo no va, una captura del título lo cuenta casi todo.
  `GBARECOMP_MTP_DIAG=1` lo escribe también por la consola cada segundo.

### Explicación
- **El contador de la tecla F cuenta imágenes dibujadas por segundo, no la velocidad del
  juego.** Con turbo se dibujan menos imágenes (los fotogramas intermedios se emulan pero
  no se pintan, y es justo lo que permite ir más deprisa), así que baja; lo que sube es
  la velocidad (`turbo xN.N` del título).

## [0.3.2] — 2026-11-07

Segunda ronda tras probar la 0.3.1 en un equipo real: con Tab no se notaba más velocidad,
los filtros «no se veían» y faltaban los atajos de teclado a la vista.

### Corregido
- **Avance rápido (Tab) apenas aceleraba** (parche 0006, reescrito). La 0.3.1 arreglaba que
  bajaran los fotogramas dibujados, pero seguía pintando por dentro **todos** los
  fotogramas y esperando entre dibujos, así que el juego iba solo ≈ ×1,2–1,7. Ahora los
  fotogramas que no se dibujan **no se pintan** y no hay esperas cuando el equipo va justo:
  va todo lo rápido que permita la CPU, hasta el multiplicador. Medido en el entorno de
  pruebas (2 núcleos): de ≈ 100 a ≈ 125–135 fotogramas emulados por segundo (≈ ×2,1–2,2),
  con la ventana a ≈ 60 dibujos por segundo. La CPU sigue mandando: en un equipo más
  potente sube hasta el multiplicador (×4 por defecto).
- **Parpadeos en negro durante el avance rápido** (aparecían al saltarse el pintado):
  el PPU ahora indica si el fotograma enganchado está pintado entero y el programa nunca
  dibuja uno que no lo esté. 0 de ≈ 2.700 capturas de ventana en negro, también al
  pulsar y soltar Tab y al cargar un estado en pleno turbo.
- **Rejilla LCD y líneas CRT**: se calculan ahora por CPU sobre la imagen final (antes se
  multiplicaba una textura con una mezcla de la tarjeta gráfica). Se ven igual con
  OpenGL, Direct3D 9 (comprobado con Wine) y el renderer por software, y ya no hay tope
  superior de tamaño: por encima de 1920×1080 se calculan a la mitad (o menos) de
  resolución y se estiran. Coste: 0,3 ms a 720×480 y 1,9 ms a 1920×1080 (LCD), ≈ 5 ms (CRT).
- **El interruptor «Linear filter» del menú del juego (Esc) no tenía efecto con los filtros
  2–8** (solo cambiaba entre Nearest y Linear). Es probablemente lo que hacía pensar que
  «el filtro no existe». Ahora mueve el filtro entre Linear (1) y Nearest (0) y se guarda.

### Añadido
- **Cambiar de filtro en directo: F12** (siguiente) y **Mayús + F12** (anterior). El nombre
  del filtro sale unos segundos en el título de la ventana y se guarda en `config.ini`.
  Configurable en `[KeyMap]` (`ImageFilterNext`, `ImageFilterPrev`).
- **Velocidad real del avance rápido en el título** de la ventana mientras se mantiene
  Tab: `turbo x2.3`.
- **Sección «Atajos de teclado»** en el README con todas las teclas (estados F1–F9 /
  Mayús+F1–F9, Tab, pausa, pantalla completa, F12…).
- README: qué esperar de cada filtro (7 y 8 se notan a primera vista; 3–6 son sutiles a
  propósito) y cómo evitar el emborronado del escalado de Windows (125 %/150 %).

### Cambiado
- `tools/pruebas/filtros_test.cpp`: pruebas de la composición (máscara blanca, negra y gris,
  rejilla LCD real, filas repetidas, reducción por encima de 1920×1080, nombres de filtro).

### Límites conocidos de esta versión
- Solo se ha probado con OpenGL por software (Xvfb) y con Direct3D 9 (Wine); **no** con
  Direct3D 11 en un Windows real.
- El avance rápido sigue limitado por la CPU (la emulación cuesta ≈ 8 ms por fotograma en
  el equipo de pruebas): `turbo x1.0`–`x1.3` en el título significa que el equipo no da más.
- Probando con argumentos de línea de órdenes (por ejemplo `--load-state`) el menú se salta
  y `config.ini` no se aplica: hay que pasar `--image-filter N`, `--scale N`… a mano.

## [0.3.1] — 2026-11-03

Correcciones tras probar la 0.3.0 en un equipo real: bajaban los fotogramas con Tab y los
filtros solo desenfocaban la imagen.

### Corregido
- **Avance rápido (Tab) bajaba los fotogramas** (parche nuevo 0006). Con Tab solo se dibuja
  1 de cada N fotogramas (N = multiplicador, de 2 a 10, por defecto 4) y el programa
  esperaba al fotograma N antes de dibujar; si el equipo no llegaba a N veces la
  velocidad, esa espera pasaba de 1/60 s y la imagen y el contador de fps caían. Ahora
  también se dibuja cuando han pasado 12 ms de trabajo desde el último dibujo: la imagen
  sigue a ≈ 60 fps y el juego va todo lo rápido que permita el equipo, hasta N veces. Si
  el equipo sí llega, manda la regla de siempre. Sin Tab no cambia nada. Medido en el
  entorno de pruebas con ×10: de ≈ 38 a ≈ 58 fotogramas dibujados por segundo, con ≈ 230–280
  emulados por segundo.
- **Los filtros de imagen solo desenfocaban** (parche 0004, rehecho):
  - *Scale2x/3x/4x y HD smooth*: la imagen ampliada se estiraba después a la ventana con
    filtro lineal de la tarjeta gráfica, lo que volvía a emborronar los bordes. Ahora el
    resultado se replica un número entero de veces más, así el ajuste final es mínimo y los
    bordes siguen nítidos. *HD smooth* suaviza mucho menos (cada vecino pesa el 12,5 % en
    vez del 25 %).
  - *LCD grid* y *CRT scanlines*: ya no se pintan sobre la imagen ampliada (al estirarla se
    convertían en un velo borroso). Se calculan como una máscara del tamaño exacto de la
    imagen en pantalla y se multiplican por encima, con rayas de 1 píxel nítidas a
    cualquier tamaño, y se compensa el brillo que quitan. La máscara se construye solo
    cuando cambia el tamaño de la ventana.
  - Se comprobó con capturas de la ventana real en pantalla completa 1280×720, ventana 3×
    (720×480) y los modos 16:9 estirado y con lados difuminados.

- El instalador ligero anotaba «2 archivo(s)» en el registro para los parches que tocan un
  solo archivo (PowerShell trata una lista de un elemento como el elemento). Solo era el
  texto del registro; los parches se aplicaban bien.

### Cambiado
- Coste de los filtros: ≤ 5 ms por fotograma en el entorno de pruebas (el peor caso es
  *HD smooth* en ventanas grandes).
- Las pruebas de `tools/pruebas/filtros_test.cpp` cubren el nuevo diseño: factor y
  replicación, cobertura de las rayas, medias y periodicidad de las máscaras LCD y CRT,
  compensación de brillo y mezcla de *HD smooth*.

### Límites conocidos de esta versión
- Solo se ha probado con el *renderer* por software de Linux (Xvfb), **no** con Direct3D 11
  en un Windows real: allí la imagen se puede ver algo distinta.
- La rejilla LCD y las líneas CRT no se dibujan si la imagen en pantalla es menor de
  480×320 ni si pasa de 2560×1440 (queda la imagen nítida de base).
- *Linear* sigue siendo borroso a propósito, y *Sharp fractional* y *Nearest* no han cambiado.

## [0.3.0] — 2026-11-02

### Añadido
- **Filtros de imagen** (parche 0004), en *Settings → Display → Texture filtering* del menú
  de arranque y con `--image-filter N` por línea de órdenes: Nearest, Linear,
  Sharp fractional, Scale2x, Scale3x, Scale4x, HD smooth, LCD grid (GBA) y CRT scanlines.
  Se aplican por CPU al presentar el fotograma, no tocan la emulación y se combinan con
  el modelo de pantalla (*Screen model*, el filtro de color de la GBA) y con los tres
  modos de relación de aspecto.
- **Partidas de otros emuladores** (parche 0005): el `.sav` de este juego es SRAM en bruto
  de 32 KiB, el mismo formato que usan mGBA, RetroArch y otros emuladores, así que se
  puede copiar tal cual. Si viene con relleno o repetido hasta 64 o 128 KiB (pasa con
  algunos programas y con las copias de flashcarts), se recorta a los 32 KiB reales y se
  conserva una copia `.original`.
- **`PARTIDAS.bat` / `tools/PARTIDAS.ps1`**: importar, exportar, hacer copias, restaurar y
  abrir la carpeta de partidas, con comprobación del archivo y copias de seguridad
  automáticas antes de sobrescribir. El instalador crea su acceso en el menú Inicio.
- Pruebas automáticas en `tools/pruebas/` (filtros y partidas) y comprobación en GitHub
  Actions (`.github/workflows/comprobar.yml`).
- Repositorio: `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  plantillas de incidencias y de *pull request*.

### Cambiado
- *Sharp fractional* ahora funciona de verdad (antes la opción no tenía efecto).
- `tools/aplicar_parches.py` detecta qué parches ya están aplicados mirando desde el último
  y admite una ruta relativa.
- El desinstalador conserva también las copias de seguridad de partidas (`*.sav.*`).

### Sin cambios / límites conocidos
- No se cargan *shaders* de RetroArch (`.glsl`, `.glslp`): la presentación usa
  `SDL_Renderer`, sin cauce de *shaders* propio.
- «HD» aquí significa ampliadores de píxel-art por CPU; no hay paquetes de texturas ni de
  texto en alta resolución (el juego dibuja en 240×160 con *sprites* y fondos, no hay
  recursos que sustituir).
- Los estados guardados de emuladores (`.ss1`, `.state`) no se pueden importar; los
  estados F1–F9 de este programa tienen formato propio.

## [0.2.1] — 2026-10-30
### Añadido
- `ACTUALIZAR.bat`: encuentra solo la instalación, compara una huella de la versión y
  reinstala conservando partidas, ajustes y accesos directos.
- Icono personalizado (`icono.ico`) para los accesos directos y «Aplicaciones».

## [0.2.0] — 2026-10-29
### Cambiado
- **Instalación ligera**: se compila con Zig + CMake + Ninja + SDL2 sin instalar nada en
  Windows. Descarga ≈ 150 MB (antes ≈ 3 GB con MSYS2), el juego instalado ocupa ≈ 55 MB.
  MSYS2 queda como respaldo (`CONSTRUIR-MSYS2.bat`).
- Instalador de PowerShell con ventana (ROM, carpeta de destino, accesos directos).

## [0.1.0] — 2026-10-28
### Añadido
- Primera versión: recompilación estática de *Mario Tennis: Power Tour* (EUR, `BTMP`) con
  gbarecomp, BIOS libre (sin BIOS de Nintendo), menú de arranque, verificación de la ROM
  por SHA-1, modos de pantalla 3:2, 16:9 estirado y 16:9 con barras difuminadas, y los
  cinco idiomas del juego comprobados.
