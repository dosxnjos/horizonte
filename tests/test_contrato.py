import json
import os
from datetime import date

import pytest

from agenda_sync import contrato


def test_escrita_atomica_substitui_e_nao_deixa_tmp(tmp_path):
    alvo = tmp_path / "agenda.json"
    alvo.write_bytes(b"antigo")
    contrato.escrever_atomico(alvo, b"novo")
    assert alvo.read_bytes() == b"novo"
    assert [p.name for p in tmp_path.iterdir()] == ["agenda.json"]


def test_escrita_atomica_repete_se_leitor_segura_o_arquivo(tmp_path, monkeypatch):
    alvo = tmp_path / "agenda.json"
    alvo.write_bytes(b"antigo")
    real = os.replace
    falhas = {"n": 2}

    def replace_ocupado(a, b):
        if falhas["n"]:
            falhas["n"] -= 1
            raise PermissionError("arquivo em uso")
        return real(a, b)

    monkeypatch.setattr(contrato.os, "replace", replace_ocupado)
    contrato.escrever_atomico(alvo, b"novo")
    assert alvo.read_bytes() == b"novo" and falhas["n"] == 0


def test_escrita_atomica_desiste_sem_corromper(tmp_path, monkeypatch):
    alvo = tmp_path / "agenda.json"
    alvo.write_bytes(b"antigo")

    def sempre_ocupado(a, b):
        raise PermissionError("arquivo em uso")

    monkeypatch.setattr(contrato.os, "replace", sempre_ocupado)
    monkeypatch.setattr(contrato.time, "sleep", lambda _s: None)
    with pytest.raises(PermissionError):
        contrato.escrever_atomico(alvo, b"novo")
    assert alvo.read_bytes() == b"antigo"
    assert [p.name for p in tmp_path.iterdir()] == ["agenda.json"]


def _doc(agora=1, status="ok", eventos=None):
    return contrato.montar(
        de=date(2026, 10, 1),
        ate=date(2026, 10, 17),
        fontes=[{"id": "pessoal", "status": status, "lastOkAt": agora, "lastAttemptAt": agora}],
        eventos=eventos or [],
        proximo_feriado=None,
        animacoes=True,
        agora=agora,
    )


def test_volateis_nao_contam_como_mudanca(tmp_path):
    alvo = tmp_path / "agenda.json"
    assert contrato.gravar_se_mudou(_doc(1), alvo) is True
    assert contrato.gravar_se_mudou(_doc(999), alvo) is False
    assert json.loads(alvo.read_text(encoding="utf-8"))["generatedAt"] == 1
    assert contrato.gravar_se_mudou(_doc(999, status="offline"), alvo) is True


def test_json_corrompido_e_regravado(tmp_path):
    alvo = tmp_path / "agenda.json"
    alvo.write_text("{meio arquivo", encoding="utf-8")
    assert contrato.gravar_se_mudou(_doc(), alvo) is True
    json.loads(alvo.read_text(encoding="utf-8"))


def test_serializar_mantem_acento_sem_bom():
    bruto = contrato.serializar({"t": "Reunião"})
    assert "Reunião".encode("utf-8") in bruto and not bruto.startswith(b"\xef\xbb\xbf")


def test_config_example_espelha_o_padrao():
    import tomllib
    from pathlib import Path

    from agenda_sync import config as cfgmod

    exemplo = tomllib.loads((Path(__file__).parents[1] / "config.example.toml").read_text(encoding="utf-8"))
    assert exemplo == cfgmod.CONFIG_PADRAO
