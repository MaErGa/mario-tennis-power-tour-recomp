#!/usr/bin/env bash
# Prueba el juego en línea por código de invitación (src/invitacion.cpp) por la red local, sin
# internet y sin el juego: dos procesos (anfitrión e invitado) se pasan los códigos por archivos
# y se conectan por el bucle local, con dos servidores STUN de juguete (tools/pruebas/stun_falso.py).
#
# Necesita g++ y python3. Uso: tools/pruebas/probar_invitacion.sh
set -uo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../.." && pwd)"
tmp="$(mktemp -d)"
pids=()
limpiar() { for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$tmp"; }
trap limpiar EXIT

command -v g++ >/dev/null 2>&1 || { echo "OMITIDA: falta g++"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "OMITIDA: falta python3"; exit 0; }

fallos=0
bien() { echo "  ok  $1"; }
mal()  { echo "  FALLO  $1"; fallos=$((fallos + 1)); }
cada() { if eval "$2"; then bien "$1"; else mal "$1"; fi; }

echo "== Compilando la prueba"
g++ -std=c++20 -O1 -DMTP_NETPLAY=1 -I"$raiz/src" "$aqui/prueba_invitacion.cpp" "$raiz/src/invitacion.cpp" \
    -o "$tmp/prueba" -pthread || { echo "FALLO: no compila"; exit 1; }
P="$tmp/prueba"

echo "== Códigos"
"$P" codigos > "$tmp/codigos.txt" 2>&1; cat "$tmp/codigos.txt" | sed 's/^/  /'
cada "los códigos" "! grep -q FALLO '$tmp/codigos.txt'"

# Servidores STUN de juguete en dos direcciones de loopback distintas.
arrancar_stun() { # direccion [--desplazar N]
    python3 -I "$aqui/stun_falso.py" "$@" > "$tmp/stun_$1.txt" 2>&1 &
    pids+=($!)
    for _ in $(seq 1 50); do grep -q listo "$tmp/stun_$1.txt" 2>/dev/null && return 0; sleep 0.1; done
    return 1
}
arrancar_stun 127.0.0.1:3478 || { echo "FALLO: no arranca el STUN de juguete"; exit 1; }
arrancar_stun 127.0.0.2:3478 || { echo "FALLO: no arranca el segundo STUN de juguete"; exit 1; }
export MTP_INV_IP_LOCAL=127.0.0.1
export MTP_STUN_SERVERS="127.0.0.1:3478 127.0.0.2:3478"

echo "== Nombres (limpieza y guardado)"
"$P" nombres "$tmp/config_nombres.ini" > "$tmp/nombres.txt" 2>&1; sed 's/^/  /' "$tmp/nombres.txt"
cada "nombres" "! grep -q FALLO '$tmp/nombres.txt' && [ \"\$(grep -c '  ok' '$tmp/nombres.txt')\" -ge 18 ]"
printf '[Menu]\nLanguage = es\n[Online]\nNombre = Lucía; la de Telde\n' > "$tmp/config_leer.ini"
cada "se lee el nombre guardado de config.ini" "[ \"\$(MTP_CONFIG_INI='$tmp/config_leer.ini' '$P' nombre_guardado)\" = 'NOMBRE_GUARDADO [Lucía; la de Telde]' ]"
cada "sin config.ini no hay nombre guardado" "[ \"\$(MTP_CONFIG_INI='$tmp/no_existe.ini' '$P' nombre_guardado)\" = 'NOMBRE_GUARDADO []' ]"

echo "== Rechazos y cancelar"
"$P" rechazos > "$tmp/rechazos.txt" 2>&1; sed 's/^/  /' "$tmp/rechazos.txt"
cada "rechazos" "! grep -q FALLO '$tmp/rechazos.txt' && [ \"\$(grep -c '  ok' '$tmp/rechazos.txt')\" -ge 14 ]"

# Anfitrión + invitado. $1 = nombre, el resto: variables de entorno para el INVITADO.
pareja() {
    local n="$1"; shift
    rm -f "$tmp/$n".inv "$tmp/$n".resp
    "$P" anfitrion "$tmp/$n.inv" "$tmp/$n.resp" > "$tmp/$n.h.txt" 2>&1 &
    local ph=$!
    env "$@" "$P" invitado "$tmp/$n.inv" "$tmp/$n.resp" > "$tmp/$n.g.txt" 2>&1 &
    local pg=$!
    wait $ph; RH=$?
    wait $pg; RG=$?
}
campo() { sed -n "s/.* $2=\\([^ ]*\\).*/\\1/p" "$1" | head -1; }
arg() { grep '^ARGS' "$1" | sed -n "s/.*$2 \\([^ ]*\\).*/\\1/p" | head -1; }

echo "== Conexión normal (dos STUN de juguete)"
pareja normal MTP_INV_DUMMY=1
cada "anfitrión conectado" "[ $RH -eq 0 ]"
cada "invitado conectado" "[ $RG -eq 0 ]"
cada "se averiguó la dirección pública (anfitrión)" "[ \"\$(campo '$tmp/normal.h.txt' sin_internet)\" = 0 ]"
cada "se averiguó la dirección pública (invitado)" "[ \"\$(campo '$tmp/normal.g.txt' sin_internet)\" = 0 ]"
cada "sin NAT simétrico (anfitrión)" "[ \"\$(campo '$tmp/normal.h.txt' nat)\" = 0 ]"
cada "el anfitrión es el asiento 0" "[ \"\$(arg '$tmp/normal.h.txt' --netplay-seat)\" = 0 ]"
cada "el invitado es el asiento 1" "[ \"\$(arg '$tmp/normal.g.txt' --netplay-seat)\" = 1 ]"
cada "misma sesión, distinta de cero" "[ -n \"\$(arg '$tmp/normal.h.txt' --netplay-session)\" ] && [ \"\$(arg '$tmp/normal.h.txt' --netplay-session)\" = \"\$(arg '$tmp/normal.g.txt' --netplay-session)\" ] && [ \"\$(arg '$tmp/normal.h.txt' --netplay-session)\" != 0 ]"
bh="$(arg "$tmp/normal.h.txt" --netplay-bind)"; bg="$(arg "$tmp/normal.g.txt" --netplay-bind)"
ph="$(arg "$tmp/normal.h.txt" --netplay-peer)"; pg="$(arg "$tmp/normal.g.txt" --netplay-peer)"
cada "el par del anfitrión es el puerto del invitado" "[ \"\${ph##*:}\" = \"\${bg##*:}\" ]"
cada "el par del invitado es el puerto del anfitrión" "[ \"\${pg##*:}\" = \"\${bh##*:}\" ]"
echo "      anfitrión: $bh → $ph    invitado: $bg → $pg"

echo "== Nombres por la conexión"
amigo() { sed -n 's/^AMIGO \[\(.*\)\]$/\1/p' "$1" | head -1; }
pareja nombres MTP_PRUEBA_NOMBRE='Marta Pérez'
cada "conectan con nombres" "[ $RH -eq 0 ] && [ $RG -eq 0 ]"
export MTP_PRUEBA_NOMBRE_ANF='Matías'
rm -f "$tmp"/nom.inv "$tmp"/nom.resp
MTP_PRUEBA_NOMBRE='Matías' "$P" anfitrion "$tmp/nom.inv" "$tmp/nom.resp" > "$tmp/nom.h.txt" 2>&1 &
ph=$!
MTP_PRUEBA_NOMBRE='Marta Pérez' "$P" invitado "$tmp/nom.inv" "$tmp/nom.resp" > "$tmp/nom.g.txt" 2>&1 &
pg=$!
wait $ph; RH=$?; wait $pg; RG=$?
cada "conectan con nombres puestos por los dos" "[ $RH -eq 0 ] && [ $RG -eq 0 ]"
cada "el anfitrión ve el nombre del invitado" "[ \"\$(amigo '$tmp/nom.h.txt')\" = 'Marta Pérez' ]"
cada "el invitado ve el nombre del anfitrión" "[ \"\$(amigo '$tmp/nom.g.txt')\" = 'Matías' ]"
cada "el anfitrión pasa su nombre a la partida" "grep '^ARGS' '$tmp/nom.h.txt' | grep -q -- '--mtp-nombre Matías --mtp-nombre-amigo Marta Pérez'"
cada "el invitado pasa su nombre a la partida" "grep '^ARGS' '$tmp/nom.g.txt' | grep -q -- '--mtp-nombre Marta Pérez --mtp-nombre-amigo Matías'"
rm -f "$tmp"/apo.inv "$tmp"/apo.resp
MTP_PRUEBA_NOMBRE='Matías' "$P" anfitrion "$tmp/apo.inv" "$tmp/apo.resp" > "$tmp/apo.h.txt" 2>&1 &
ph=$!
MTP_PRUEBA_NOMBRE='Marta' MTP_PRUEBA_APODO='Mi prima' "$P" invitado "$tmp/apo.inv" "$tmp/apo.resp" > "$tmp/apo.g.txt" 2>&1 &
pg=$!
wait $ph; RH=$?; wait $pg; RG=$?
cada "con apodo conectan igual" "[ $RH -eq 0 ] && [ $RG -eq 0 ]"
cada "el apodo manda sobre el nombre anunciado (solo en quien lo puso)" "[ \"\$(amigo '$tmp/apo.g.txt')\" = 'Mi prima' ] && [ \"\$(amigo '$tmp/apo.h.txt')\" = 'Marta' ]"
cada "sin nombres no se añade ningún argumento de nombre" "! grep '^ARGS' '$tmp/normal.h.txt' | grep -q -- '--mtp-nombre'"
unset MTP_PRUEBA_NOMBRE_ANF

echo "== Sin STUN (sin internet): solo red local"
export MTP_STUN_SERVERS="127.0.0.1:9"
pareja sinnet MTP_INV_DUMMY=1
cada "anfitrión sin internet" "[ \"\$(campo '$tmp/sinnet.h.txt' sin_internet)\" = 1 ]"
cada "invitado sin internet" "[ \"\$(campo '$tmp/sinnet.g.txt' sin_internet)\" = 1 ]"
cada "aun así conectan por la red local" "[ $RH -eq 0 ] && [ $RG -eq 0 ]"

echo "== NAT simétrico (dos servidores que ven puertos distintos)"
arrancar_stun 127.0.0.3:3478 --desplazar 1 || { echo "FALLO: STUN simétrico"; exit 1; }
export MTP_STUN_SERVERS="127.0.0.1:3478 127.0.0.3:3478"
pareja simetrico MTP_INV_DUMMY=1
cada "el anfitrión detecta su NAT simétrico" "[ \"\$(campo '$tmp/simetrico.h.txt' nat)\" = 1 ]"
cada "el invitado sabe que el anfitrión lo es" "[ \"\$(campo '$tmp/simetrico.g.txt' amigo_nat)\" = 1 ]"
cada "el anfitrión sabe que el invitado lo es" "[ \"\$(campo '$tmp/simetrico.h.txt' amigo_nat)\" = 1 ]"
cada "con la red local aún conectan" "[ $RH -eq 0 ] && [ $RG -eq 0 ]"

echo "== Versiones distintas"
export MTP_STUN_SERVERS="127.0.0.1:3478 127.0.0.2:3478"
rm -f "$tmp/version.inv" "$tmp/version.resp"
"$P" anfitrion "$tmp/version.inv" "$tmp/version.resp" > "$tmp/version.h.txt" 2>&1 &
ph=$!; pids+=($ph)
MTP_INV_IDENTIDAD=otra-version "$P" invitado "$tmp/version.inv" "$tmp/version.resp" > "$tmp/version.g.txt" 2>&1
kill $ph 2>/dev/null; wait $ph 2>/dev/null
cada "el invitado con otra versión es rechazado (UNIRSE 3)" "grep -q 'UNIRSE 3' '$tmp/version.g.txt'"

echo "== El invitado desaparece: tiempo agotado"
rm -f "$tmp/fant.inv"
MTP_INV_NONCE=424242 MTP_INV_PLAZO=3 "$P" fantasma "$tmp/fant.inv" > "$tmp/fant.txt" 2>&1; rf=$?
cada "el anfitrión acaba con error de tiempo (ERR_TIEMPO = 6)" "[ $rf -ne 0 ] && grep -q 'error=6' '$tmp/fant.txt'"

echo
if [ "$fallos" -eq 0 ]; then echo "Pruebas de la invitación: todo bien"; else echo "Pruebas de la invitación: $fallos fallos"; exit 1; fi
