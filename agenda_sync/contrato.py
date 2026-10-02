"""Montagem e escrita do agenda.json (contrato v1, docs/CONTRATOS.md)."""

from __future__ import annotations

import json
import os
import time
from datetime import date
from pathlib import Path

from agenda_sync import PRODUCER

SCHEMA_VERSION = 1

# Campos que mudam a cada execução sem mudar o que o widget desenha. Ficam fora da comparação
# "mudou?"; senão todo sync regravaria o arquivo e acordaria os widgets à toa.
VOLATEIS_RAIZ = ("generatedAt",)
VOLATEIS_FONTE = ("lastAttemptAt", "lastOkAt")


def escrever_atomico(destino: Path, dados: bytes, tentativas: int = 10) -> None:
    """tmp na mesma pasta + os.replace. Repete se um leitor (Rainmeter) segurar o arquivo no Windows."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    tmp = destino.with_name(f".{destino.name}.{os.getpid()}.tmp")
    with tmp.open("wb") as fh:
        fh.write(dados)
        fh.flush()
        os.fsync(fh.fileno())
    for i in range(tentativas):
        try:
            os.replace(tmp, destino)
            return
        except PermissionError:
            if i == tentativas - 1:
                tmp.unlink(missing_ok=True)
                raise
            time.sleep(0.05 * (i + 1))


def montar(
    *,
    de: date,
    ate: date,
    fontes: list[dict],
    eventos: list[dict],
    proximo_feriado: dict | None,
    animacoes: bool,
    agora: int | None = None,
) -> dict:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "producer": PRODUCER,
        "generatedAt": int(agora if agora is not None else time.time()),
        "janela": {"de": de.isoformat(), "ate": ate.isoformat()},
        "ambiente": {"animacoes": bool(animacoes)},
        "proximoFeriado": proximo_feriado,
        "sources": fontes,
        "events": eventos,
    }


def serializar(doc: dict) -> bytes:
    """UTF-8 sem BOM, acentos literais, uma chave por linha (o Lua lê; humano consegue conferir)."""
    return (json.dumps(doc, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def _estavel(doc: dict) -> dict:
    d = {k: v for k, v in doc.items() if k not in VOLATEIS_RAIZ}
    d["sources"] = [{k: v for k, v in s.items() if k not in VOLATEIS_FONTE} for s in doc.get("sources", [])]
    return d


def mudou(atual: dict, destino: Path) -> bool:
    try:
        anterior = json.loads(destino.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return True
    return _estavel(anterior) != _estavel(atual)


def gravar_se_mudou(doc: dict, destino: Path) -> bool:
    """Grava o agenda.json só se o conteúdo estável mudou. Devolve True se gravou."""
    if not mudou(doc, destino):
        return False
    escrever_atomico(destino, serializar(doc))
    return True
