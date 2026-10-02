from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

FIXTURES = Path(__file__).parent / "fixtures"
SP = ZoneInfo("America/Sao_Paulo")


def ler(nome: str) -> bytes:
    return (FIXTURES / nome).read_bytes()


def epoch(ano, mes, dia, hora=0, minuto=0, tz=SP) -> int:
    return int(datetime(ano, mes, dia, hora, minuto, tzinfo=tz).timestamp())


def utc(ano, mes, dia, hora=0, minuto=0) -> int:
    return epoch(ano, mes, dia, hora, minuto, tz=timezone.utc)


@pytest.fixture(autouse=True)
def isolar_pasta(tmp_path, monkeypatch):
    """Nenhum teste toca o %LOCALAPPDATA% real nem o Gerenciador de Credenciais."""
    monkeypatch.setenv("HORIZONTE_DIR", str(tmp_path / "Horizonte"))
    import agenda_sync.config as cfg

    def _proibido(*_a, **_k):
        raise AssertionError("teste tentou usar o keyring real")

    monkeypatch.setattr(cfg, "gravar_segredo", _proibido)
    monkeypatch.setattr(cfg, "ler_segredo", lambda _id: None)
    return tmp_path / "Horizonte"
