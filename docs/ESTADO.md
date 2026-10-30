# Estado del proyecto (leer al retomar)

Última comprobación: 30-oct-2026, en Linux (sandbox de 2 núcleos, sin tarjeta de
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
- Menú de arranque: ROM verificada por SHA-1 («ROM verified»), mando/teclado,
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
  guardado/carga de partida (la SRAM está configurada; no se probó un ciclo
  completo de guardar y volver a abrir).
- Mandos reales (solo se probó el teclado simulado).

## Limitaciones conocidas

- Parte del juego (módulos de código de EWRAM, rutinas copiadas a la zona de
  pila, el descompresor) se ejecuta con el intérprete del runtime: es correcto
  pero más lento que el código recompilado.
- El menú de recomp-ui solo está en inglés e italiano.
- El modo de pantalla se aplica al arrancar; para cambiarlo hay que reabrir.
- No hay vista ampliada 16:9 real (ver `NOTAS_TECNICAS.md`).
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
