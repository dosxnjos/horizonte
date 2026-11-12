"""O .rmskin sai no formato que o SkinInstaller do Rainmeter aceita e sem arquivo da máquina."""

import importlib.util
import struct
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("empacotar", RAIZ / "tools" / "empacotar.py")
empacotar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(empacotar)


def test_rmskin_rodape_e_conteudo(tmp_path):
    alvo = empacotar.montar("9.9.9", tmp_path)
    dados = alvo.read_bytes()
    tamanho, flags, chave = struct.unpack("<qB7s", dados[-16:])
    assert chave == b"RMSKIN\x00" and flags == 0
    assert tamanho == len(dados) - 16
    with zipfile.ZipFile(alvo) as z:
        nomes = z.namelist()
        ini = z.read("RMSKIN.ini").decode("utf-16")
    assert "Name=Horizonte" in ini and "Author=dosxnjos" in ini and "Version=9.9.9" in ini
    assert "VariableFiles=Horizonte\\@Resources\\Settings.inc" in ini
    assert "Skins/Horizonte/Relogio/Relogio.ini" in nomes
    assert "Skins/Horizonte/@Resources/Settings.inc" in nomes
    assert "Layouts/Horizonte/Rainmeter.ini" in nomes
    assert not any(n.endswith(("Local.inc", "Local.example.inc")) for n in nomes)
    assert all("\\" not in n for n in nomes)
