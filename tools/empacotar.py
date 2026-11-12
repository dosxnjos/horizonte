"""Monta o instalador .rmskin do Horizonte a partir da pasta skin/.

Formato (código do SkinInstaller do Rainmeter, Library/DialogPackage.cpp e DialogInstall.cpp):
um zip com RMSKIN.ini (seção [rmskin]) e RMSKIN.bmp (400 x 60) na raiz, a pasta Skins/<config>/
e, opcional, Layouts/<nome>/Rainmeter.ini; depois do zip, um rodapé de 16 bytes:
int64 com o tamanho do zip + byte de flags (0) + "RMSKIN\\0".

Uso:  uv run python tools/empacotar.py --versao 1.0.0 [--saida dist]
Fica de fora: Local.inc e Local.example.inc (da máquina de quem desenvolve) e arquivo oculto.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SKIN = RAIZ / "skin"
CONFIG = "Horizonte"
FORA = {"Local.inc", "Local.example.inc"}

# Layout genérico (px lógicos), para caber numa tela de 1280 de largura. O do repo
# (layouts/Horizonte) é o da máquina do autor e não vai no pacote.
POSICOES = {
    "Relogio": (60, 60),
    "Dia": (60, 301),
    "Agenda": (514, 60),
    "Maquina": (918, 60),
    "Claude": (918, 259),
}


def utf16(texto: str) -> bytes:
    return b"\xff\xfe" + texto.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-16-le")


def rmskin_ini(versao: str) -> bytes:
    return utf16(
        "[rmskin]\n"
        f"Name={CONFIG}\n"
        "Author=dosxnjos\n"
        f"Version={versao}\n"
        "LoadType=Skin\n"
        f"Load={CONFIG}\\Relogio\\Relogio.ini\n"
        f"VariableFiles={CONFIG}\\@Resources\\Settings.inc\n"
        "MinimumRainmeter=4.5.0.0\n"
        "MinimumWindows=10.0\n"
    )


def layout_ini() -> bytes:
    partes = ["; Horizonte: the five widgets. Manage > Layouts > Horizonte > Load (replaces the current layout).\n[Rainmeter]\n"]
    for nome, (x, y) in POSICOES.items():
        partes.append(
            f"\n[{CONFIG}\\{nome}]\nActive=1\nWindowX={x}\nWindowY={y}\nClickThrough=0\n"
            "Draggable=1\nSnapEdges=1\nKeepOnScreen=1\nAlwaysOnTop=-2\n"
        )
    return utf16("".join(partes))


def cabecalho_bmp() -> bytes | None:
    """RMSKIN.bmp 400 x 60 (cabeçalho do instalador). Sem Pillow, o pacote sai sem ele."""
    try:
        from io import BytesIO

        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return None
    w, h = 400, 60
    img = Image.new("RGB", (w, h))
    px = img.load()
    a, b = (21, 48, 45), (36, 30, 24)
    for x in range(w):
        t = x / (w - 1)
        cor = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
        for y in range(h):
            px[x, y] = cor
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((16, 14, 72, 46), radius=16, fill=(134, 224, 200))
    d.ellipse((84, 22, 100, 38), fill=(255, 178, 122))
    try:
        f = ImageFont.truetype("C:/Windows/Fonts/SegUIVar.ttf", 26)
    except OSError:
        f = ImageFont.load_default()
    d.text((112, 13), "Horizonte", font=f, fill=(226, 241, 236))
    out = BytesIO()
    img.save(out, format="BMP")
    return out.getvalue()


def montar(versao: str, saida: Path) -> Path:
    saida.mkdir(parents=True, exist_ok=True)
    alvo = saida / f"{CONFIG}_{versao}.rmskin"
    arquivos = []
    for p in sorted(SKIN.rglob("*")):
        if not p.is_file() or p.name in FORA:
            continue
        rel = p.relative_to(SKIN)
        if any(parte.startswith(".") for parte in rel.parts):
            continue
        arquivos.append((p, f"Skins/{CONFIG}/{rel.as_posix()}"))
    with zipfile.ZipFile(alvo, "w", compression=zipfile.ZIP_DEFLATED) as z:
        bmp = cabecalho_bmp()
        if bmp:
            z.writestr("RMSKIN.bmp", bmp)
        z.writestr("RMSKIN.ini", rmskin_ini(versao))
        for p, nome in arquivos:
            z.write(p, nome)
        z.writestr(f"Layouts/{CONFIG}/Rainmeter.ini", layout_ini())
    tamanho = alvo.stat().st_size
    with alvo.open("ab") as f:
        f.write(struct.pack("<qB7s", tamanho, 0, b"RMSKIN\x00"))
    print(f"{alvo} ({len(arquivos)} arquivos do skin, {alvo.stat().st_size} bytes)")
    return alvo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--versao", required=True)
    ap.add_argument("--saida", default=str(RAIZ / "dist"))
    a = ap.parse_args()
    montar(a.versao, Path(a.saida))
    return 0


if __name__ == "__main__":
    sys.exit(main())
