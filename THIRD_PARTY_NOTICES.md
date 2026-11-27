# Avisos de terceros

Este proyecto no contiene la ROM ni la BIOS de Nintendo, ni código generado a
partir de ellas. Lo que sí incluye, y lo que descarga y usa al construir el
juego en tu equipo, tiene estas licencias.

## Lo que viaja dentro del repositorio

| Qué | Dónde | Autoría | Licencia |
|---|---|---|---|
| Instalador, actualizador, scripts, `game.toml`, host (`src/`) y pruebas | raíz, `tools/`, `src/` | MaErGa | PolyForm Noncommercial 1.0.0 (`LICENSE`) |
| Parches a gbarecomp | `parches/` | MaErGa, sobre código de Matthew Stanley | PolyForm Noncommercial 1.0.0 (son obras derivadas de gbarecomp) |
| BIOS libre ya compilada (`bios_libre.bin`, 16 KiB) y su configuración, del proyecto [Cult-of-GBA/BIOS](https://github.com/Cult-of-GBA/BIOS) | `bios_libre/` | DenSinH y fleroviux | MIT (`bios_libre/LICENSE-Cult-of-GBA-BIOS.txt`) |

La BIOS libre se redistribuye con su aviso de copyright y su licencia, como exige la MIT.

## Lo que se descarga al construir (no viaja en el repositorio)

Todo se baja de su sitio original, en una versión (o *commit*) fija, al ejecutar el
instalador o `tools/construir.sh`.

| Componente | Para qué | Licencia |
|---|---|---|
| [gbarecomp](https://github.com/mstan/gbarecomp) (Matthew Stanley) | Recompilador y runtime de GBA | PolyForm Noncommercial 1.0.0, **salvo** `src/runtime/bios_hle.*` (ver abajo) |
| [arm-recomp-core](https://github.com/mstan/arm-recomp-core) (Matthew Stanley) | Núcleo ARM/Thumb de gbarecomp | MIT |
| [recomp-ui](https://github.com/mstan/recomp-ui) (Matthew Stanley) | Menú de configuración | MIT |
| [recomp-net](https://github.com/RetroPortingToolKit/recomp-net) (colaboradores de recomp-net) | Red del juego en línea (cable por red) | MIT |
| [rbengine](https://github.com/RetroPortingToolKit/rbengine) (colaboradores de retcomm-rbengine) | Motor de retroceso del juego en línea | MIT |
| Servidores STUN públicos (por defecto, los de Google y Cloudflare) | Solo se les pregunta una vez la dirección pública al usar «En línea»; no se descarga ni se enlaza nada | — (servicio de red, no se redistribuye) |
| [toml++](https://github.com/marzer/tomlplusplus) (Mark Gillard) | Lector de `game.toml` | MIT |
| [SDL2](https://libsdl.org/) | Ventana, vídeo, audio y mandos | zlib |
| [Zig](https://ziglang.org/) | Compilador de C/C++ del método ligero (solo al compilar) | MIT |
| [CMake](https://cmake.org/) | Configuración de la compilación (solo al compilar) | BSD 3-Clause |
| [Ninja](https://ninja-build.org/) | Ejecución de la compilación (solo al compilar) | Apache 2.0 |
| [MSYS2](https://www.msys2.org/) y MinGW-w64 | Método clásico de respaldo (opcional, solo al compilar) | Varias (GPL/BSD/MIT según el paquete) |

### Sobre `bios_hle` y la licencia MPL-2.0

Dos archivos de gbarecomp (`src/runtime/bios_hle.h` y `bios_hle.cpp`) derivan de
[mGBA](https://github.com/mgba-emu/mgba) (Jeffrey Pfau y colaboradores) y están bajo
**MPL-2.0**, no bajo PolyForm. Este repositorio no los contiene: el programa que
construyes en tu equipo sí los enlaza. Su texto completo y su código fuente están en el
repositorio de gbarecomp (`third_party/MPL-2.0.txt`, `THIRD_PARTY_ATTRIBUTION.md`).

### Código portado dentro de gbarecomp

gbarecomp acredita en su `THIRD_PARTY_ATTRIBUTION.md` partes portadas de
[JRickey/gba-recomp](https://github.com/JRickey/gba-recomp) (MIT o Apache 2.0, con
permiso del autor): detección del motor de sonido, simulación del color de la pantalla
y reloj de cartucho, entre otras.

## Qué NO se redistribuye, nunca

- La ROM de *Mario Tennis: Power Tour*, ni ningún trozo de ella.
- La BIOS oficial de Nintendo (el proyecto usa la libre).
- El código C++ que el recompilador genera a partir de tu ROM, ni el ejecutable ya
  compilado, ni capturas o recursos del juego.

*Mario*, *Mario Tennis*, Nintendo y Camelot son marcas de sus propietarios. Este
proyecto no está afiliado a ellos ni aprobado por ellos.

Si has visto un error en esta lista (una licencia mal atribuida, un autor que falta),
abre una incidencia o un *pull request*: se corrige en cuanto se avise.
