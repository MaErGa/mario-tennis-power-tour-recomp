#!/usr/bin/env python3
"""Aplica a un checkout (gbarecomp o recomp-ui) los parches de parches/*.patch.

Uso: aplicar_parches.py RAIZ [CARPETA_PARCHES]

Los parches de cada proyecto se llaman como su carpeta: a «externo/gbarecomp» le tocan
parches/gbarecomp-*.patch y a «externo/recomp-ui», parches/recomp-ui-*.patch.

Es idempotente: salta los parches ya aplicados (el último que se puede revertir sin
error y todos los anteriores). Si uno no encaja, aborta con un mensaje claro.
Necesita «git» (se usa «git apply», que no exige que la carpeta sea un repo).
"""
import subprocess
import sys
from pathlib import Path


def git_apply(raiz: Path, parche: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(raiz), "apply", "--whitespace=nowarn", *extra, str(parche)],
        capture_output=True, text=True)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    raiz = Path(sys.argv[1]).resolve()
    carpeta = (Path(sys.argv[2]) if len(sys.argv) > 2
               else Path(__file__).resolve().parent.parent / "parches").resolve()
    parches = sorted(carpeta.glob(f"{raiz.name}-*.patch"))
    if not parches:
        print(f"No hay parches {raiz.name}-*.patch en {carpeta}", file=sys.stderr)
        return 1
    # ¿Hasta cuál de los parches está ya aplicado? Se mira de atrás adelante: el último
    # que se puede revertir sin error es el último aplicado (los anteriores, también). No
    # se puede comprobar cada uno por separado: un parche posterior puede haber tocado
    # las líneas de contexto de uno anterior y este ya no encajaría ni aplicado ni sin aplicar.
    ultimo_aplicado = -1
    for i in range(len(parches) - 1, -1, -1):
        if git_apply(raiz, parches[i], "--reverse", "--check").returncode == 0:
            ultimo_aplicado = i
            break
    for i, p in enumerate(parches):
        if i <= ultimo_aplicado:
            print(f"  ya aplicado : {p.name}")
            continue
        comprobacion = git_apply(raiz, p, "--check")
        if comprobacion.returncode != 0:
            print(f"ERROR: {p.name} no encaja en {raiz}.\n{comprobacion.stderr}",
                  file=sys.stderr)
            print(f"Comprueba que {raiz.name} está en el commit fijado en tools/construir.sh.",
                  file=sys.stderr)
            return 1
        resultado = git_apply(raiz, p)
        if resultado.returncode != 0:
            print(f"ERROR aplicando {p.name}:\n{resultado.stderr}", file=sys.stderr)
            return 1
        print(f"  aplicado    : {p.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
