#!/usr/bin/env python3
"""Servidor STUN de juguete para las pruebas de src/invitacion.cpp (no es para uso real).

Contesta a cada «Binding Request» con la dirección desde la que le escriben
(XOR-MAPPED-ADDRESS). Con --desplazar N suma N al puerto que dice haber visto: así se imita
un NAT simétrico (cada servidor ve un puerto distinto).

Uso: stun_falso.py IP:PUERTO [--desplazar N]
Escribe «listo» en la salida estándar cuando ya escucha.
"""
import socket
import struct
import sys

COOKIE = 0x2112A442


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ip, puerto = sys.argv[1].rsplit(":", 1)
    desplazar = 0
    if "--desplazar" in sys.argv:
        desplazar = int(sys.argv[sys.argv.index("--desplazar") + 1])
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((ip, int(puerto)))
    print("listo", flush=True)
    while True:
        datos, origen = s.recvfrom(2048)
        if len(datos) < 20 or datos[0:2] != b"\x00\x01":
            continue
        if struct.unpack(">I", datos[4:8])[0] != COOKIE:
            continue
        tid = datos[8:20]
        ip_v = struct.unpack(">I", socket.inet_aton(origen[0]))[0]
        puerto_v = (origen[1] + desplazar) & 0xFFFF
        valor = struct.pack(">BBHI", 0, 1, puerto_v ^ (COOKIE >> 16), ip_v ^ COOKIE)
        atributo = struct.pack(">HH", 0x0020, len(valor)) + valor
        cabecera = struct.pack(">HHI", 0x0101, len(atributo), COOKIE) + tid
        s.sendto(cabecera + atributo, origen)


if __name__ == "__main__":
    sys.exit(main())
