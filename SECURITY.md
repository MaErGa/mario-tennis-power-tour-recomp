# Seguridad

Los instaladores descargan herramientas y fuentes de internet y las ejecutan en tu equipo,
así que su integridad importa:

- Zig, CMake, Ninja y SDL2 se descargan con **SHA-256 fijado** en `tools/construir.ps1`.
- Las fuentes de gbarecomp, arm-recomp-core, toml++ y recomp-ui se descargan en un
  **commit exacto**, no en una rama.
- Nada se instala con permisos de administrador.
- El juego ya instalado **no se conecta a internet** salvo por una cosa: al abrir el menú de
  arranque pide una vez el archivo `VERSION` del repositorio (una petición `GET` por HTTPS,
  unos pocos bytes, sin enviar nada tuyo) para avisar si hay una versión nueva. Solo compara
  números; no descarga ni ejecuta nada. Se apaga con `[Menu] CheckUpdates = 0` en `config.ini`.
  Solo se admiten direcciones `https://` con caracteres «seguros» (y `http://` a `127.0.0.1` para
  pruebas), y se descartan respuestas que no parezcan un número de versión.

Si encuentras un fallo que permita ejecutar código no previsto, sobrescribir archivos
fuera de la carpeta elegida o saltarse esas comprobaciones, **no lo publiques en una
incidencia abierta**: usa «Report a vulnerability» en la pestaña *Security* del
repositorio (avisos privados de GitHub) y se corregirá lo antes posible.

Los fallos del juego en sí (cierres, gráficos rotos) van por el camino normal de
incidencias; ver `CONTRIBUTING.md`.
