#!/usr/bin/env python3
"""Aplica a un checkout de gbarecomp los parches de parches/*.patch.

Uso: aplicar_parches.py RAIZ_GBARECOMP [CARPETA_PARCHES]

Es idempotente: si un parche ya está aplicado (se puede revertir sin error), lo
salta. Si no encaja ni aplicado ni sin aplicar, aborta con un mensaje claro.
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
               else Path(__file__).resolve().parent.parent / "parches")
    parches = sorted(carpeta.glob("gbarecomp-*.patch"))
    if not parches:
        print(f"No hay parches en {carpeta}", file=sys.stderr)
        return 1
    for p in parches:
        if git_apply(raiz, p, "--reverse", "--check").returncode == 0:
            print(f"  ya aplicado : {p.name}")
            continue
        comprobacion = git_apply(raiz, p, "--check")
        if comprobacion.returncode != 0:
            print(f"ERROR: {p.name} no encaja en {raiz}.\n{comprobacion.stderr}",
                  file=sys.stderr)
            print("Comprueba que gbarecomp está en el commit fijado en tools/construir.sh.",
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
