#!/usr/bin/env bash
# Prueba el juego en línea por código de invitación (src/invitacion.cpp) con ROUTERS DE VERDAD
# (NAT de Linux) entre dos equipos, en redes virtuales aisladas:
#
#   anfitrión ── NAT A ──┐                      ┌── NAT B ── invitado
#   10.0.1.2             └── «Internet» ────────┘            10.0.2.2
#                          (con dos servidores STUN: 198.51.100.1 y .2)
#
# Casos: dos NAT «de casa» (puerto conservado y filtro por dirección y puerto: debe conectar),
# un NAT simétrico en un lado y en los dos (no se puede perforar: debe avisar y acabar con el
# error de tiempo) y sin servidor STUN alcanzable (el código solo vale en la misma red).
#
# Necesita root (o sudo sin contraseña), `ip`, `iptables`, g++ y python3. Si falta algo, se
# omite y sale con código 0. Uso: tools/pruebas/probar_invitacion_nat.sh
set -uo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../.." && pwd)"

omitir() { echo "OMITIDA: $1"; exit 0; }
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then exec sudo -n -E bash "$0" "$@"; fi
    omitir "hace falta ser root (redes virtuales)"
fi
export PATH="$PATH:/usr/sbin:/sbin"
command -v ip >/dev/null 2>&1 || omitir "falta «ip» (iproute2)"
command -v iptables >/dev/null 2>&1 || omitir "falta «iptables»"
command -v g++ >/dev/null 2>&1 || omitir "falta g++"
command -v python3 >/dev/null 2>&1 || omitir "falta python3"

id="mtp$$"
H="${id}h"; NA="${id}na"; I="${id}i"; NB="${id}nb"; G="${id}g"
tmp="$(mktemp -d)"
pids=()
limpiar() {
    for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
    for n in "$H" "$NA" "$I" "$NB" "$G"; do ip netns del "$n" 2>/dev/null; done
    rm -rf "$tmp"
}
trap limpiar EXIT

ip netns add "$H" 2>/dev/null && ip netns add "$NA" && ip netns add "$I" && ip netns add "$NB" && ip netns add "$G" \
    || omitir "no se pueden crear espacios de red (¿contenedor sin permisos?)"

enlazar() { # ns1 if1 ip1 ns2 if2 ip2
    ip link add "$2" netns "$1" type veth peer name "$5" netns "$4" || return 1
    ip -n "$1" addr add "$3" dev "$2"; ip -n "$1" link set dev "$2" up
    ip -n "$4" addr add "$6" dev "$5"; ip -n "$4" link set dev "$5" up
}
for n in "$H" "$NA" "$I" "$NB" "$G"; do ip -n "$n" link set dev lo up; done
enlazar "$H" eth0 10.0.1.2/24 "$NA" lan 10.0.1.1/24 || omitir "no se pueden crear enlaces virtuales"
enlazar "$NA" wan 203.0.113.1/24 "$I" ea 203.0.113.254/24
enlazar "$NB" wan 192.0.2.1/24 "$I" eb 192.0.2.254/24
enlazar "$G" eth0 10.0.2.2/24 "$NB" lan 10.0.2.1/24
ip -n "$H" route add default via 10.0.1.1
ip -n "$G" route add default via 10.0.2.1
ip -n "$NA" route add default via 203.0.113.254
ip -n "$NB" route add default via 192.0.2.254
ip -n "$I" addr add 198.51.100.1/32 dev lo
ip -n "$I" addr add 198.51.100.2/32 dev lo
for n in "$NA" "$NB" "$I"; do ip netns exec "$n" sysctl -qw net.ipv4.ip_forward=1; done

nat() { # router ns, "normal" o "simetrico"
    local r="$1" modo="$2"
    ip netns exec "$r" iptables -t nat -F
    ip netns exec "$r" iptables -F FORWARD
    if [ "$modo" = simetrico ]; then
        ip netns exec "$r" iptables -t nat -A POSTROUTING -o wan -j MASQUERADE --random
    else
        ip netns exec "$r" iptables -t nat -A POSTROUTING -o wan -j MASQUERADE
    fi
    # Lo de fuera solo entra si es respuesta a algo que salió (lo normal en un router de casa). Lo no
    # solicitado se DESCARTA, también el dirigido al propio router (INPUT): si no, Linux anotaría ese
    # paquete como una conexión nueva y el paquete de salida con el mismo puerto ya no podría
    # conservarlo (los routers de casa no hacen eso).
    ip netns exec "$r" iptables -F INPUT
    ip netns exec "$r" iptables -A INPUT -i lo -j ACCEPT
    ip netns exec "$r" iptables -A INPUT -i lan -j ACCEPT
    ip netns exec "$r" iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip netns exec "$r" iptables -P INPUT DROP
    ip netns exec "$r" iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip netns exec "$r" iptables -A FORWARD -i lan -j ACCEPT
    ip netns exec "$r" iptables -P FORWARD DROP
}

fallos=0
bien() { echo "  ok  $1"; }
mal()  { echo "  FALLO  $1"; fallos=$((fallos + 1)); }
cada() { if eval "$2"; then bien "$1"; else mal "$1"; fi; }

echo "== Compilando la prueba"
g++ -std=c++20 -O1 -DMTP_NETPLAY=1 -I"$raiz/src" "$aqui/prueba_invitacion.cpp" "$raiz/src/invitacion.cpp" \
    -o "$tmp/prueba" -pthread || { echo "FALLO: no compila"; exit 1; }
P="$tmp/prueba"

for ip_stun in 198.51.100.1 198.51.100.2; do
    ip netns exec "$I" python3 -I "$aqui/stun_falso.py" "$ip_stun:3478" > "$tmp/stun_$ip_stun.txt" 2>&1 &
    pids+=($!)
done
for _ in $(seq 1 50); do
    grep -q listo "$tmp/stun_198.51.100.1.txt" 2>/dev/null && grep -q listo "$tmp/stun_198.51.100.2.txt" 2>/dev/null && break
    sleep 0.1
done
export MTP_STUN_SERVERS="198.51.100.1:3478 198.51.100.2:3478"

campo() { sed -n "s/.* $2=\\([^ ]*\\).*/\\1/p" "$1" | head -1; }

# Anfitrión (tras NAT A) e invitado (tras NAT B). $1 = nombre; MTP_INV_PLAZO del entorno.
pareja() {
    local n="$1"
    rm -f "$tmp/$n".inv "$tmp/$n".resp
    ip netns exec "$H" "$P" anfitrion "$tmp/$n.inv" "$tmp/$n.resp" > "$tmp/$n.h.txt" 2>&1 &
    local ph=$!
    ip netns exec "$G" "$P" invitado "$tmp/$n.inv" "$tmp/$n.resp" > "$tmp/$n.g.txt" 2>&1 &
    local pg=$!
    wait $ph; RH=$?
    wait $pg; RG=$?
}

echo "== Dos routers de casa (cono, puerto conservado, lo no solicitado se descarta)"
nat "$NA" normal; nat "$NB" normal
pareja casa
cada "anfitrión conectado" "[ $RH -eq 0 ]"
cada "invitado conectado" "[ $RG -eq 0 ]"
cada "no se sospecha de NAT simétrico" "[ \"\$(campo '$tmp/casa.h.txt' nat)\" = 0 ] && [ \"\$(campo '$tmp/casa.g.txt' nat)\" = 0 ]"
cada "el anfitrión ve al invitado desde la IP pública de B" "grep -q 'par=192.0.2.1:' '$tmp/casa.h.txt'"
cada "el invitado ve al anfitrión desde la IP pública de A" "grep -q 'par=203.0.113.1:' '$tmp/casa.g.txt'"
grep -h '^FINAL' "$tmp/casa.h.txt" "$tmp/casa.g.txt" | sed 's/^/      /'

export MTP_INV_PLAZO=6
echo "== Un lado con NAT simétrico (no se puede perforar: debe avisar y acabar por tiempo)"
nat "$NA" normal; nat "$NB" simetrico
pareja sim1
cada "el invitado (NAT simétrico) lo detecta" "[ \"\$(campo '$tmp/sim1.g.txt' nat)\" = 1 ]"
cada "el anfitrión sabe que el amigo lo es" "[ \"\$(campo '$tmp/sim1.h.txt' amigo_nat)\" = 1 ]"
cada "no conectan: error de tiempo en los dos" "[ $RH -ne 0 ] && [ $RG -ne 0 ] && grep -q 'error=6' '$tmp/sim1.h.txt' && grep -q 'error=6' '$tmp/sim1.g.txt'"

echo "== Los dos con NAT simétrico"
nat "$NA" simetrico; nat "$NB" simetrico
pareja sim2
cada "anfitrión lo detecta" "[ \"\$(campo '$tmp/sim2.h.txt' nat)\" = 1 ]"
cada "invitado lo detecta" "[ \"\$(campo '$tmp/sim2.g.txt' nat)\" = 1 ]"
cada "acaban con error de tiempo" "[ $RH -ne 0 ] && grep -q 'error=6' '$tmp/sim2.h.txt'"

echo "== Sin servidor STUN alcanzable detrás de NAT: el código solo vale en la misma red"
nat "$NA" normal; nat "$NB" normal
export MTP_STUN_SERVERS="198.51.100.77:3478"
pareja sinstun
cada "el anfitrión sabe que no tiene dirección pública" "[ \"\$(campo '$tmp/sinstun.h.txt' sin_internet)\" = 1 ]"
cada "y como están en redes distintas no conectan (error de tiempo)" "[ $RH -ne 0 ] && grep -q 'error=6' '$tmp/sinstun.h.txt'"

echo
if [ "$fallos" -eq 0 ]; then echo "Pruebas de la invitación con NAT: todo bien"; else echo "Pruebas de la invitación con NAT: $fallos fallos"; exit 1; fi
