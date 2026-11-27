# Seguridad

Los instaladores descargan herramientas y fuentes de internet y las ejecutan en tu equipo,
así que su integridad importa:

- Zig, CMake, Ninja y SDL2 se descargan con **SHA-256 fijado** en `tools/construir.ps1`.
- Las fuentes de gbarecomp, arm-recomp-core, recomp-net, rbengine, toml++ y recomp-ui se descargan
  en un **commit exacto**, no en una rama.
- Nada se instala con permisos de administrador.
- `tools/instalar.sh` (Linux) solo usa `sudo` si le dices que instale las herramientas que faltan (te
  enseña la orden antes y pide tu contraseña a `sudo`; nunca la ve el script). Todo lo demás se hace con
  tu usuario, dentro de la carpeta que elijas (por defecto `~/.local/share/MarioTennisPowerTour`) y de
  `~/.cache`; no toca nada fuera de ellas, de la entrada del menú de aplicaciones y, si lo pides, del
  acceso del Escritorio. `desinstalar.sh` solo borra una carpeta que tenga el
  `instalacion.cfg` de este juego.
- El juego ya instalado **no se conecta a internet** salvo por dos cosas. La primera: al abrir el menú de
  arranque pide una vez el archivo `VERSION` del repositorio (una petición `GET` por HTTPS,
  unos pocos bytes, sin enviar nada tuyo) para avisar si hay una versión nueva. Solo compara
  números; no descarga ni ejecuta nada. Se apaga con `[Menu] CheckUpdates = 0` en `config.ini`.
  Solo se admiten direcciones `https://` con caracteres «seguros» (y `http://` a `127.0.0.1` para
  pruebas), y se descartan respuestas que no parezcan un número de versión.
- La segunda es **solo si tú usas «En línea»** (0.5.0):
  - Se consulta una vez a un servidor STUN público (por defecto de Google y Cloudflare; se cambia en
    `[Online] StunServers`) para conocer tu dirección pública; no recibe códigos, nombres ni
    partidas.
  - Se abre un **puerto UDP** y se habla **directamente con el ordenador de tu amigo**, que ve tu
    dirección IP pública (va dentro del código de invitación: dáselo solo a quien quieras). No hay
    ningún servidor nuestro. El otro jugador puede ver también tu IP local.
  - El nombre que escribes viaja a tu amigo; se limpia en recepción (UTF-8 válido, hasta 24 bytes,
    sin caracteres de control).
  - La partida en red es experimental y está pensada para amigos: no la uses con desconocidos.
  - Si no la usas, el programa no abre ningún puerto.

Si encuentras un fallo que permita ejecutar código no previsto, sobrescribir archivos
fuera de la carpeta elegida o saltarse esas comprobaciones, **no lo publiques en una
incidencia abierta**: usa «Report a vulnerability» en la pestaña *Security* del
repositorio (avisos privados de GitHub) y se corregirá lo antes posible.

Los fallos del juego en sí (cierres, gráficos rotos) van por el camino normal de
incidencias; ver `CONTRIBUTING.md`.
