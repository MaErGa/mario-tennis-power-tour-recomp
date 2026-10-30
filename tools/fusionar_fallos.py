#!/usr/bin/env python3
"""Añade a game.toml las entradas fiables que el runtime propuso al jugar.

Uso:
    python3 tools/fusionar_fallos.py game.toml juego/recomp_master_misses_BTMP.toml.frag [más.frag ...]

Al cerrar el juego con normalidad, el runtime escribe un fragmento
(recomp_master_misses_BTMP.toml.frag) con las direcciones que tuvo que ejecutar
con el intérprete porque el análisis estático no las vio. Este script lee esos
fragmentos y añade como [[extra_func]] las que son seguras:

  * ROM (0x08000000..0x08FFFFFF): se añaden.
  * IWRAM dentro de un [[code_copy]] declarado: se añaden (código copiado de la ROM).
  * BIOS (< 0x4000), EWRAM (módulos descomprimidos al vuelo) y la zona de pila de
    IWRAM: se ignoran (se interpretan a propósito; ver src/main.cpp).

No toca nada que ya esté en game.toml. Después hay que volver a ejecutar
tools/construir.sh para regenerar y recompilar.
"""
import re
import sys

MARCA = "# (se añaden debajo de esta línea)"


def leer_entradas(texto):
    """Devuelve [(addr, modo, veces)] de los bloques [[extra_func]] de un texto TOML."""
    entradas = []
    for bloque in re.split(r"(?m)^\[\[extra_func\]\]\s*$", texto)[1:]:
        m_addr = re.search(r"(?m)^addr\s*=\s*(0x[0-9A-Fa-f]+|\d+)", bloque)
        m_modo = re.search(r'(?m)^mode\s*=\s*"(arm|thumb)"', bloque)
        if not (m_addr and m_modo):
            continue
        veces = re.search(r"bridged x(\d+)", bloque)
        entradas.append((int(m_addr.group(1), 0), m_modo.group(1),
                         int(veces.group(1)) if veces else 0))
    return entradas


def tramos_code_copy(texto):
    tramos = []
    for bloque in re.split(r"(?m)^\[\[code_copy\]\]\s*$", texto)[1:]:
        ini = re.search(r"(?m)^runtime_start\s*=\s*(0x[0-9A-Fa-f]+)", bloque)
        tam = re.search(r"(?m)^size\s*=\s*(0x[0-9A-Fa-f]+)", bloque)
        if ini and tam:
            tramos.append((int(ini.group(1), 0), int(ini.group(1), 0) + int(tam.group(1), 0)))
    return tramos


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ruta_toml, fragmentos = sys.argv[1], sys.argv[2:]
    toml = open(ruta_toml, encoding="utf-8").read()
    existentes = {(a, m) for a, m, _ in leer_entradas(toml)}
    existentes |= {(a, "arm" if m == "thumb" else "thumb") for a, m in set(existentes)} & set()
    tramos = tramos_code_copy(toml)

    propuestas = {}
    for ruta in fragmentos:
        for addr, modo, veces in leer_entradas(open(ruta, encoding="utf-8").read()):
            propuestas[(addr, modo)] = max(veces, propuestas.get((addr, modo), 0))

    nuevas, ignoradas = [], {"bios": 0, "ewram": 0, "iwram": 0, "otras": 0, "ya": 0}
    for (addr, modo), veces in sorted(propuestas.items()):
        if (addr, modo) in existentes:
            ignoradas["ya"] += 1
        elif addr < 0x4000:
            ignoradas["bios"] += 1
        elif 0x02000000 <= addr < 0x03000000:
            ignoradas["ewram"] += 1
        elif 0x03000000 <= addr < 0x04000000:
            if any(a <= addr < b for a, b in tramos):
                nuevas.append((addr, modo, veces, "iwram_rt"))
            else:
                ignoradas["iwram"] += 1
        elif 0x08000000 <= addr < 0x09000000:
            nuevas.append((addr, modo, veces, "rom_rt"))
        else:
            ignoradas["otras"] += 1

    if nuevas:
        if MARCA not in toml:
            toml = toml.rstrip("\n") + "\n\n" + MARCA + "\n"
        toml = toml.rstrip("\n") + "\n"
        for addr, modo, veces, pref in nuevas:
            toml += (f'\n[[extra_func]]\naddr = 0x{addr:08X}\nmode = "{modo}"\n'
                     f'name = "{pref}_{addr:08X}"\nnote = "añadida desde el registro de fallos; interpretada x{veces}"\n')
        open(ruta_toml, "w", encoding="utf-8").write(toml)

    print(f"Añadidas {len(nuevas)} entradas a {ruta_toml}.")
    print("Ignoradas: " + ", ".join(f"{k}={v}" for k, v in ignoradas.items() if v))
    if nuevas:
        print("Ahora vuelve a ejecutar tools/construir.sh (o CONSTRUIR.bat).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
