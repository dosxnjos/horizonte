"""Orquestra um ciclo de sincronização: fontes -> eventos -> agenda.json -> aviso aos widgets.

Tudo que toca o mundo (rede, keyring, relógio, fuso, Rainmeter) é injetável para o teste.
O log nunca recebe URL nem título: só contagens, status, bytes e duração.
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import sys
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta, tzinfo
from pathlib import Path
from typing import Callable

import httpx

from agenda_sync import config as cfgmod
from agenda_sync import contrato, fetch, ical, windows

log = logging.getLogger("agenda_sync")

DIAS_FERIADO = 60


def configurar_log(base: Path) -> None:
    destino = str(cfgmod.log_path(base))
    for antigo in [h for h in log.handlers if isinstance(h, logging.handlers.RotatingFileHandler)]:
        if antigo.baseFilename == os.path.abspath(destino):
            return
        log.removeHandler(antigo)
        antigo.close()
    base.mkdir(parents=True, exist_ok=True)
    h = logging.handlers.RotatingFileHandler(destino, maxBytes=128 * 1024, backupCount=1, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(h)
    log.setLevel(logging.INFO)


@contextmanager
def trava(base: Path):
    """Uma execução por vez (a tarefa agendada pode disparar logon + rede juntos). Ocupado -> None."""
    base.mkdir(parents=True, exist_ok=True)
    fh = open(base / "sync.lock", "a+b")
    try:
        if sys.platform == "win32":
            import msvcrt

            try:
                fh.seek(0)
                msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                yield None
                return
            try:
                yield fh
            finally:
                fh.seek(0)
                try:
                    msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
                except OSError:
                    pass
        else:
            yield fh
    finally:
        fh.close()


def mensagem_erro(status: str, publica: bool) -> str | None:
    if status == "ok":
        return None
    if status == "offline":
        return "sem conexão (ou rede pedindo login); mostrando o último dado bom"
    if status == "formato":
        return "o feed veio incompleto ou fora do formato iCal; nova tentativa no próximo ciclo"
    if status == "inesperado":
        return "falha inesperada nesta fonte; veja o sync.log (as outras fontes seguem normais)"
    if status == "endereco_invalido":
        if publica:
            return "endereço dos feriados inválido no config.toml: confira o campo url"
        return "endereço gravado não é uma URL válida: rode agenda-sync configurar"
    if status == "sem_credencial":
        if publica:
            return "endereço dos feriados ausente: rode agenda-sync migrar-do-ini ou preencha o config.toml"
        return "endereço não configurado: rode agenda-sync configurar"
    if status.startswith("http"):
        codigo = status[4:]
        if codigo in ("404", "401", "403", "410"):
            if publica:
                return f"o Google respondeu {codigo}: confira o endereço dos feriados no config.toml"
            return f"o Google respondeu {codigo}: regere o endereço secreto e rode agenda-sync configurar"
        return f"o Google respondeu {codigo}; nova tentativa no próximo ciclo"
    return "falha desconhecida; veja o sync.log"


def _ler_json(p: Path) -> dict:
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _gravar_json(p: Path, dados: dict) -> None:
    contrato.escrever_atomico(p, json.dumps(dados, ensure_ascii=False).encode("utf-8"))


def _offset_local(local_tz: tzinfo | None) -> int:
    agora = datetime.now(tz=local_tz) if local_tz else datetime.now().astimezone()
    return int(agora.utcoffset().total_seconds())


def _expandir_com_cache(
    cache: Path, fonte_id: str, corpo: bytes, hash_: str, de: date, ate_excl: date, conta: int, local_tz: tzinfo | None
) -> tuple[list[dict], bool]:
    """Expande ou reaproveita a expansão anterior (mesmo hash sem DTSTAMP, mesma janela). (eventos, reaproveitou)"""
    chave = {
        "v": ical.VERSAO_EXPANSAO,  # código da expansão mudou: o cache antigo não vale
        "hash": hash_,
        "de": de.isoformat(),
        "ate": ate_excl.isoformat(),
        "conta": conta,
        "tz": _offset_local(local_tz),
    }
    p = cache / f"{fonte_id}.eventos.json"
    anterior = _ler_json(p)
    if anterior.get("chave") == chave and isinstance(anterior.get("events"), list):
        return anterior["events"], True
    eventos = ical.expandir(corpo, fonte_id, de, ate_excl, conta=conta, local_tz=local_tz)
    _gravar_json(p, {"chave": chave, "events": eventos})
    return eventos, False


def sincronizar(
    base: Path | None = None,
    *,
    hoje: date | None = None,
    local_tz: tzinfo | None = None,
    agora: int | None = None,
    transport: httpx.BaseTransport | None = None,
    ler_segredo: Callable[[str], str | None] | None = None,
    animacoes: Callable[[], bool] = windows.animacoes_ligadas,
    avisar: Callable[[str, list[str]], int] | None = windows.avisar_widgets,
) -> dict:
    """Um ciclo completo. Devolve um resumo sem dado pessoal (status por fonte, contagens, gravou?)."""
    base = base or cfgmod.base_dir()
    ler_segredo = ler_segredo or cfgmod.ler_segredo
    t0 = time.monotonic()
    cfg = cfgmod.carregar_config(base)
    cache = cfgmod.cache_dir(base)
    cache.mkdir(parents=True, exist_ok=True)
    estado_p = cache / "estado.json"
    estado = _ler_json(estado_p)

    agora = int(agora if agora is not None else time.time())
    hoje = hoje or (datetime.now(tz=local_tz).date() if local_tz else date.today())
    janela_dias = int(cfg.get("janelaDias", 15))
    de = hoje - timedelta(days=1)
    ate = hoje + timedelta(days=janela_dias)
    ate_excl = ate + timedelta(days=1)
    timeout = float(cfg.get("timeoutS", 20))
    intervalo_feriados = float(cfg.get("intervaloFeriadosH", cfgmod.CONFIG_PADRAO["intervaloFeriadosH"])) * 3600

    fontes_saida: list[dict] = []
    todos: list[dict] = []
    prox_feriado = None
    resumo: dict = {"fontes": {}, "gravou": False, "eventos": 0}

    for f in cfg["fontes"]:
        fid = f["id"]
        publica = f.get("tipo") == "publica"
        conta = int(f.get("contaIndice", cfg.get("contaIndice", 0)))
        st = dict(estado.get(fid, {}))
        raw_p = cache / f"{fid}.ics"
        url = (f.get("url") or "").strip() if publica else ler_segredo(fid)
        info = {"bytes": 0, "ms": 0, "vevents": 0, "baixou": False}
        try:
            eventos, pf = _processar_fonte(
                fid, publica, conta, st, raw_p, url, info,
                cache=cache, agora=agora, hoje=hoje, de=de, ate_excl=ate_excl, timeout=timeout,
                intervalo_feriados=intervalo_feriados, transport=transport, local_tz=local_tz,
            )
            if fid == "feriados":
                prox_feriado = pf
        except Exception as exc:  # noqa: BLE001 - uma fonte quebrada nunca derruba as outras
            log.warning("fonte=%s falha_inesperada tipo=%s", fid, type(exc).__name__)
            st.update(status="formato", httpStatus=None, erro=mensagem_erro("inesperado", publica), lastAttemptAt=agora)
            # como toda falha: mantém o último download bom (sem credencial continua vazio)
            eventos, pf = _ultimo_bom(fid, raw_p, cache, hoje, de, ate_excl, conta, local_tz) if url else ([], None)
            if fid == "feriados":
                prox_feriado = pf

        estado[fid] = st
        todos.extend(eventos)
        fontes_saida.append(
            {
                "id": fid,
                "nome": f.get("nome", fid),
                "cor": f.get("cor", "#FFFFFF"),
                "status": st.get("status", "sem_credencial"),
                "httpStatus": st.get("httpStatus"),
                "lastOkAt": st.get("lastOkAt"),
                "lastAttemptAt": st.get("lastAttemptAt", agora),
                "erro": st.get("erro"),
            }
        )
        resumo["fontes"][fid] = {"status": st.get("status"), "eventos": len(eventos)}
        log.info(
            "fonte=%s status=%s http=%s baixou=%s bytes=%d vevents=%d eventos=%d ms=%d",
            fid, st.get("status"), st.get("httpStatus"), info["baixou"], info["bytes"], info["vevents"], len(eventos), info["ms"],
        )

    _gravar_json(estado_p, estado)
    doc = contrato.montar(
        de=de,
        ate=ate,
        fontes=fontes_saida,
        eventos=ical.ordenar(todos),
        proximo_feriado=prox_feriado,
        animacoes=animacoes(),
        agora=agora,
    )
    destino = cfgmod.agenda_path(base)
    gravou = contrato.gravar_se_mudou(doc, destino)
    avisos = 0
    if gravou and avisar is not None:
        try:
            avisos = avisar(cfg.get("rainmeterExe", cfgmod.RAINMETER_PADRAO), list(cfg.get("widgets", [])))
        except Exception:  # noqa: BLE001
            avisos = 0
    resumo.update(gravou=gravou, eventos=len(doc["events"]), avisos=avisos)
    log.info(
        "ciclo eventos=%d gravou=%s avisos=%d ms=%d", len(doc["events"]), gravou, avisos, int((time.monotonic() - t0) * 1000)
    )
    return resumo


def _processar_fonte(
    fid, publica, conta, st, raw_p, url, info, *, cache, agora, hoje, de, ate_excl, timeout,
    intervalo_feriados, transport, local_tz,
) -> tuple[list[dict], dict | None]:
    """Baixa (ou pula), classifica, expande. Atualiza `st` e `info` no lugar. (eventos na janela, próximo feriado)"""
    prox_feriado = None
    novo = None
    if not url:
        st.update(status="sem_credencial", httpStatus=None, erro=mensagem_erro("sem_credencial", publica), lastAttemptAt=agora)
        return [], None
    recente = (
        publica
        and st.get("status") == "ok"
        and st.get("lastOkAt")
        and agora - int(st["lastOkAt"]) < intervalo_feriados
        and raw_p.exists()
    )
    if not recente:
        info["baixou"] = True
        res = fetch.baixar(url, timeout=timeout, transport=transport)
        info.update(bytes=res.bytes, ms=res.ms)
        st["lastAttemptAt"] = agora
        st["httpStatus"] = res.http_status
        if res.status == "ok":
            novo = res.corpo  # status/lastOkAt só depois que o feed expandir: "ok" que não parseia é formato
        elif res.status == "endereco_invalido":
            st.update(status="sem_credencial", erro=mensagem_erro("endereco_invalido", publica))
            return [], None
        else:
            st.update(status=res.status, erro=mensagem_erro(res.status, publica))
    corpo = novo if novo is not None else (raw_p.read_bytes() if raw_p.exists() else None)
    if corpo is None:
        return [], None

    ate_exp = _ate_expansao(fid, hoje, ate_excl)
    h = ical.hash_sem_dtstamp(corpo)
    try:
        eventos, reaproveitou = _expandir_com_cache(cache, fid, corpo, h, de, ate_exp, conta, local_tz)
        info["reaproveitou"] = reaproveitou
        info["vevents"] = ical.contar_vevents(corpo)
    except Exception as exc:  # noqa: BLE001 - feed que não parseia cai para o último bom
        log.warning("fonte=%s expansao_falhou tipo=%s", fid, type(exc).__name__)
        st.update(status="formato", erro=mensagem_erro("formato", publica))
        if novo is None:  # o próprio último bom não expande: não há o que mostrar
            return [], None
        return _ultimo_bom(fid, raw_p, cache, hoje, de, ate_excl, conta, local_tz)
    if novo is not None:
        st.update(status="ok", erro=None, lastOkAt=agora)
        if st.get("hash") != h or not raw_p.exists():
            try:
                contrato.escrever_atomico(raw_p, novo)
                st["hash"] = h
            except OSError as exc:  # disco/antivírus: os eventos deste ciclo valem; o .ics bom antigo fica
                log.warning("fonte=%s cache_ics_falhou tipo=%s", fid, type(exc).__name__)
    if fid == "feriados":
        prox_feriado = ical.proximo_feriado(eventos, hoje, DIAS_FERIADO)
    return [e for e in eventos if ical.toca_janela(e, de, ate_excl, local_tz)], prox_feriado


def _ate_expansao(fid: str, hoje: date, ate_excl: date) -> date:
    """Feriados expandem até 60 dias (proximoFeriado); as outras fontes, só a janela."""
    return max(ate_excl, hoje + timedelta(days=DIAS_FERIADO + 1)) if fid == "feriados" else ate_excl


def _ultimo_bom(
    fid: str, raw_p: Path, cache: Path, hoje: date, de: date, ate_excl: date, conta: int, local_tz: tzinfo | None
) -> tuple[list[dict], dict | None]:
    """Eventos do último .ics bom em disco (falha de parse ou inesperada). Sem .ics ou sem parse: vazio."""
    try:
        if not raw_p.exists():
            return [], None
        corpo = raw_p.read_bytes()
        eventos, _ = _expandir_com_cache(
            cache, fid, corpo, ical.hash_sem_dtstamp(corpo), de, _ate_expansao(fid, hoje, ate_excl), conta, local_tz
        )
    except Exception:  # noqa: BLE001
        return [], None
    pf = ical.proximo_feriado(eventos, hoje, DIAS_FERIADO) if fid == "feriados" else None
    return [e for e in eventos if ical.toca_janela(e, de, ate_excl, local_tz)], pf


def rodar(base: Path | None = None, **kwargs) -> dict | None:
    """Ponto de entrada do comando `sync`: log + trava. None se outra execução estiver em curso."""
    base = base or cfgmod.base_dir()
    configurar_log(base)
    with trava(base) as ok:
        if ok is None:
            log.info("ciclo pulado: outra execução em curso")
            return None
        try:
            return sincronizar(base, **kwargs)
        except Exception as exc:  # noqa: BLE001
            log.error("ciclo falhou tipo=%s", type(exc).__name__)
            raise
        finally:
            for h in list(log.handlers):
                h.flush()
