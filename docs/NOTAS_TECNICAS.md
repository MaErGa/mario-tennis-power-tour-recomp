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
(son idempotentes: si ya están aplicados, los salta).

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

El menú del framework solo sabe pasar un «ancho de vista» por opción de aspecto;
los modos 1 y 2 se señalan con anchos centinela (`241` y `242`, que no son
anchos reales) que `main()` traduce a `GBARECOMP_STRETCH` y quita de los
argumentos antes de llamar a `run_game()`.

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
| `--frames N --dump-png f.png` | Ejecuta N fotogramas sin ventana y guarda una captura |
| `--tcp PUERTO` | Servidor de depuración (avanzar fotogramas, estados, captura, audio) |
