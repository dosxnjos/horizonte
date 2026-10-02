"""Expansão de um .ics em eventos do contrato (sem rede, sem disco: função pura).

RRULE, RDATE, EXDATE e RECURRENCE-ID ficam com o recurring-ical-events; STATUS:CANCELLED,
DTEND ausente, fuso, dia inteiro e higiene de privacidade ficam aqui.
"""

from __future__ import annotations

import hashlib
import re
from datetime import date, datetime, timedelta, tzinfo

import icalendar
import recurring_ical_events

_URL = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)
_MEET = re.compile(r"https://(?:meet\.google\.com/[a-z0-9-]+|teams\.microsoft\.com/l/meetup-join/[^\s<>\"']+)", re.IGNORECASE)
_EMAIL = re.compile(r"(?:mailto:)?[^\s<>\"'(),;:]+@[^\s<>\"'(),;:]+\.[^\s<>\"'(),;:]+", re.IGNORECASE)
_DTSTAMP = re.compile(rb"^DTSTAMP[;:].*?(?:\r?\n|$)", re.MULTILINE)

# Entra na chave do cache de expansão (sync._expandir_com_cache). Suba a cada mudança no que
# `expandir` devolve; senão a máquina real segue com a expansão velha até o feed ou a janela mudar.
VERSAO_EXPANSAO = 2


def hash_sem_dtstamp(corpo: bytes) -> str:
    """Hash do feed ignorando DTSTAMP (o Google muda a cada download) para pular reprocessamento."""
    return hashlib.sha256(_DTSTAMP.sub(b"", corpo)).hexdigest()


def contar_vevents(corpo: bytes) -> int:
    return corpo.count(b"BEGIN:VEVENT")


def _epoch(dt: datetime, local_tz: tzinfo | None) -> int:
    if dt.tzinfo is None:  # floating: hora local da máquina
        dt = dt.replace(tzinfo=local_tz) if local_tz is not None else dt.astimezone()
    return int(dt.timestamp())


def _meia_noite_epoch(d: date, local_tz: tzinfo | None) -> int:
    return _epoch(datetime(d.year, d.month, d.day), local_tz)


def _texto(v) -> str:
    return str(v).strip() if v is not None else ""


def _limpar(texto: str) -> str:
    """Tira e-mail e URL de texto exibível (título, local). O repo é público e o JSON também é dado."""
    t = _URL.sub("", texto)
    t = _EMAIL.sub("", t)
    t = re.sub(r"\s{2,}", " ", t).strip(" ,;-\t\r\n")
    return t


def _meet_url(comp) -> str | None:
    conf = _texto(comp.get("X-GOOGLE-CONFERENCE"))
    m = _MEET.search(conf)
    if m:
        return m.group(0).rstrip(".,;)>")
    for campo in ("DESCRIPTION", "LOCATION"):
        m = _MEET.search(_texto(comp.get(campo)))
        if m:
            return m.group(0).rstrip(".,;)>")
    return None


def _chave_rid(v) -> str | None:
    if v is None:
        return None
    dt = v.dt if hasattr(v, "dt") else v
    if isinstance(dt, datetime):
        if dt.tzinfo is not None:  # instante absoluto: o mesmo RECURRENCE-ID em fusos diferentes casa
            return str(int(dt.timestamp()))
        return dt.strftime("%Y%m%dT%H%M%S")
    return dt.isoformat()


def _indexar(cal) -> tuple[set[str], dict[tuple[str, str | None], bool]]:
    """UIDs recorrentes e, por (UID, RECURRENCE-ID), se o componente original tinha fim explícito."""
    recorrentes: set[str] = set()
    tem_fim: dict[tuple[str, str | None], bool] = {}
    for comp in cal.walk("VEVENT"):
        uid = _texto(comp.get("UID"))
        rid = comp.get("RECURRENCE-ID")
        if comp.get("RRULE") is not None or comp.get("RDATE") is not None or rid is not None:
            recorrentes.add(uid)
        tem_fim[(uid, _chave_rid(rid))] = comp.get("DTEND") is not None or comp.get("DURATION") is not None
    return recorrentes, tem_fim


def toca_janela(ev: dict, de: date, ate_exclusivo: date, local_tz: tzinfo | None) -> bool:
    """O evento do contrato toca [de, ate_exclusivo) no fuso local? (dia inteiro por data, com hora por epoch)"""
    if ev["allDay"]:
        return ev["startDate"] < ate_exclusivo.isoformat() and ev["endDate"] > de.isoformat()
    ini = _meia_noite_epoch(de, local_tz)
    fim = _meia_noite_epoch(ate_exclusivo, local_tz)
    if ev["end"] == ev["start"]:  # duração zero (lembrete): conta o instante
        return ini <= ev["start"] < fim
    return ev["start"] < fim and ev["end"] > ini


def link_semana(conta: int, d: date) -> str:
    return f"https://calendar.google.com/calendar/u/{conta}/r/week/{d.year}/{d.month}/{d.day}"


def expandir(
    corpo: bytes,
    fonte_id: str,
    de: date,
    ate_exclusivo: date,
    conta: int = 0,
    local_tz: tzinfo | None = None,
) -> list[dict]:
    """Eventos do feed que tocam [de, ate_exclusivo) no formato do contrato (ainda sem ordenar)."""
    cal = icalendar.Calendar.from_ical(corpo.removeprefix(b"\xef\xbb\xbf").lstrip())  # BOM/linha vazia antes do BEGIN
    recorrentes, tem_fim = _indexar(cal)
    eventos: list[dict] = []
    # A lib compara limites `date` no fuso de CADA evento: um evento em Z (o Google exporta assim os
    # avulsos) às 22:30 de Brasília no último dia vira 01:30 do dia seguinte e sumiria. Folga de 1 dia
    # para cada lado e o corte exato no fuso local fica com toca_janela (docs/ARMADILHAS.md).
    folga = timedelta(days=1)
    # skip_bad_series: um VEVENT com DTSTART ou RRULE quebrado é pulado, não derruba a fonte inteira
    for occ in recurring_ical_events.of(cal, skip_bad_series=True).between(de - folga, ate_exclusivo + folga):
        if _texto(occ.get("STATUS")).upper() == "CANCELLED":
            continue
        uid = _texto(occ.get("UID"))
        inicio = occ.get("DTSTART").dt
        fim = occ.get("DTEND").dt if occ.get("DTEND") is not None else None
        rid = occ.get("RECURRENCE-ID")
        fim_explicito = tem_fim.get((uid, _chave_rid(rid)), tem_fim.get((uid, None), False))
        dia_inteiro = not isinstance(inicio, datetime)
        if not fim_explicito or fim is None:
            fim = inicio + (timedelta(days=1) if dia_inteiro else timedelta(hours=1))

        titulo = _limpar(_texto(occ.get("SUMMARY"))) or "(sem título)"
        local = _limpar(_texto(occ.get("LOCATION"))) or None
        ev: dict = {"source": fonte_id, "title": titulo}
        if dia_inteiro:
            if isinstance(fim, datetime):
                fim = fim.date()
            if fim <= inicio:
                fim = inicio + timedelta(days=1)
            ev["allDay"] = True
            ev["startDate"] = inicio.isoformat()
            ev["endDate"] = fim.isoformat()
            chave_inicio = inicio.isoformat()
            dia_link = inicio
            ordem = _meia_noite_epoch(inicio, local_tz)
        else:
            if not isinstance(fim, datetime):
                fim = datetime(fim.year, fim.month, fim.day, tzinfo=inicio.tzinfo)
            ini_epoch = _epoch(inicio, local_tz)
            fim_epoch = max(_epoch(fim, local_tz), ini_epoch)
            ev["allDay"] = False
            ev["start"] = ini_epoch
            ev["end"] = fim_epoch
            chave_inicio = str(ini_epoch)
            dia_link = datetime.fromtimestamp(ini_epoch, tz=local_tz).date()  # tz None = fuso do Windows
            ordem = ini_epoch
        ev["id"] = hashlib.sha1(f"{fonte_id}|{uid}|{chave_inicio}".encode("utf-8")).hexdigest()[:16]
        ev["recurring"] = uid in recorrentes
        ev["location"] = local
        ev["meetUrl"] = _meet_url(occ)
        ev["link"] = link_semana(conta, dia_link)
        ev["_ordem"] = ordem
        if toca_janela(ev, de, ate_exclusivo, local_tz):
            eventos.append(ev)
    return eventos


def ordenar(eventos: list[dict]) -> list[dict]:
    """Ordena por início (dia inteiro conta da meia-noite local) e remove a chave interna."""
    eventos = sorted(eventos, key=lambda e: (e["_ordem"], 0 if e["allDay"] else 1, e["source"], e["title"], e["id"]))
    return [{k: v for k, v in e.items() if k != "_ordem"} for e in eventos]


def proximo_feriado(eventos: list[dict], hoje: date, dias: int = 60) -> dict | None:
    limite = hoje + timedelta(days=dias)
    candidatos = sorted(
        (e for e in eventos if e.get("allDay") and hoje.isoformat() <= e["startDate"] <= limite.isoformat()),
        key=lambda e: e["startDate"],
    )
    if not candidatos:
        return None
    return {"data": candidatos[0]["startDate"], "nome": candidatos[0]["title"]}
