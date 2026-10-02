"""Pastas locais, config.toml e credenciais (keyring).

Nada daqui é versionado: tudo mora em %LOCALAPPDATA%\\Horizonte (ou em HORIZONTE_DIR, para teste).
"""

from __future__ import annotations

import copy
import os
import tomllib
from pathlib import Path

import tomli_w

SERVICO_KEYRING = "Horizonte"
FONTES_PRIVADAS = ("pessoal", "corporativo")

RAINMETER_PADRAO = r"C:\Program Files\Rainmeter\Rainmeter.exe"

# A URL pública dos feriados NÃO vem no código: o repo é público e o varredor de segredos
# barra qualquer endereço de calendário. Ela entra no config.toml via `migrar-do-ini` ou à mão.
CONFIG_PADRAO: dict = {
    "schemaVersion": 1,
    "contaIndice": 0,
    "intervaloFeriadosH": 168,  # semanal (roadmap § 4, "Cadência dos feriados")
    "janelaDias": 15,
    "timeoutS": 20,
    "rainmeterExe": RAINMETER_PADRAO,
    "widgets": ["Horizonte\\Dia", "Horizonte\\Agenda", "Horizonte\\Relogio"],
    "fontes": [
        {"id": "pessoal", "nome": "Pessoal", "cor": "#7AA2F7", "tipo": "privada", "contaIndice": 0},
        {"id": "corporativo", "nome": "Corporativo", "cor": "#C3A6FF", "tipo": "privada", "contaIndice": 0},
        {"id": "feriados", "nome": "Feriados", "cor": "#5FD0B5", "tipo": "publica", "contaIndice": 0, "url": ""},
    ],
}


def base_dir() -> Path:
    """Pasta de dados: HORIZONTE_DIR (testes) ou %LOCALAPPDATA%\\Horizonte."""
    sobrescrita = os.environ.get("HORIZONTE_DIR")
    if sobrescrita:
        return Path(sobrescrita)
    local = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return Path(local) / "Horizonte"


def config_path(base: Path | None = None) -> Path:
    return (base or base_dir()) / "config.toml"


def cache_dir(base: Path | None = None) -> Path:
    return (base or base_dir()) / "cache"


def agenda_path(base: Path | None = None) -> Path:
    return (base or base_dir()) / "agenda.json"


def log_path(base: Path | None = None) -> Path:
    return (base or base_dir()) / "sync.log"


def _mesclar_padrao(cfg: dict) -> dict:
    """Completa chaves ausentes com o padrão, sem apagar o que o usuário escreveu."""
    out = copy.deepcopy(CONFIG_PADRAO)
    for k, v in cfg.items():
        if k != "fontes":
            out[k] = v
    if "fontes" in cfg:
        padrao_por_id = {f["id"]: f for f in CONFIG_PADRAO["fontes"]}
        fontes = []
        for f in cfg["fontes"]:
            base = copy.deepcopy(padrao_por_id.get(f.get("id"), {"tipo": "privada", "contaIndice": 0}))
            base.update(f)
            fontes.append(base)
        out["fontes"] = fontes
    return out


def carregar_config(base: Path | None = None) -> dict:
    """Lê o config.toml; cria com o padrão se faltar."""
    p = config_path(base)
    if not p.exists():
        salvar_config(CONFIG_PADRAO, base)
        return copy.deepcopy(CONFIG_PADRAO)
    with p.open("rb") as fh:
        return _mesclar_padrao(tomllib.load(fh))


def salvar_config(cfg: dict, base: Path | None = None) -> None:
    from agenda_sync.contrato import escrever_atomico

    p = config_path(base)
    p.parent.mkdir(parents=True, exist_ok=True)
    escrever_atomico(p, tomli_w.dumps(cfg).encode("utf-8"))


def fonte(cfg: dict, fonte_id: str) -> dict | None:
    return next((f for f in cfg["fontes"] if f.get("id") == fonte_id), None)


def ler_segredo(fonte_id: str) -> str | None:
    """URL secreta da fonte no Gerenciador de Credenciais. None se ausente ou keyring indisponível."""
    try:
        import keyring

        return keyring.get_password(SERVICO_KEYRING, fonte_id) or None
    except Exception:  # noqa: BLE001 - backend ausente equivale a "sem credencial"
        return None


def gravar_segredo(fonte_id: str, valor: str) -> None:
    import keyring

    keyring.set_password(SERVICO_KEYRING, fonte_id, valor)
