"""Prova independente da recorrência (Fase 1): expande as séries do .ics real com dateutil.rrule
e compara com o agenda.json. Nunca imprime URL, título ou conteúdo: só contagens e índices.

Uso (depois de um `agenda-sync sync`; o .ics vai para %TEMP% e é apagado no fim):
    uv run python tools/prova_recorrencia.py pessoal
    uv run python tools/prova_recorrencia.py corporativo

Independente do helper: a expansão aqui é `dateutil.rrule` + EXDATE + RECURRENCE-ID feitos à
mão; do agenda_sync só reaproveita config (credencial), fetch (download) e a fórmula do `id`.
Fuso fixo America/Sao_Paulo. Saída esperada: "faltando" = 0 em toda linha e
"recurring mas não previstas" = 0.
"""

import hashlib
import json
import os
import sys
import tempfile
from collections import Counter
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from dateutil.rrule import rrulestr
from icalendar import Calendar

from agenda_sync import config as cfgmod
from agenda_sync import fetch

LOCAL = ZoneInfo("America/Sao_Paulo")
FONTE = sys.argv[1] if len(sys.argv) > 1 else "pessoal"

agenda = json.loads(cfgmod.agenda_path().read_text(encoding="utf-8"))
de = date.fromisoformat(agenda["janela"]["de"])
ate_excl = date.fromisoformat(agenda["janela"]["ate"]) + timedelta(days=1)
ini_j = datetime.combine(de, time(), LOCAL)
fim_j = datetime.combine(ate_excl, time(), LOCAL)

url = cfgmod.ler_segredo(FONTE)
res = fetch.baixar(url, timeout=30)
fd, tmp = tempfile.mkstemp(suffix=".ics", dir=os.environ["TEMP"])
try:
    with os.fdopen(fd, "wb") as fh:
        fh.write(res.corpo)
    print(f"download: status={res.status} http={res.http_status} bytes={len(res.corpo)}")
    cal = Calendar.from_ical(open(tmp, "rb").read())
finally:
    os.remove(tmp)
print(f"tmp apagado: {not os.path.exists(tmp)}")


def as_dt(v):
    """date -> (date, True); datetime naive -> local; aware -> como veio."""
    if isinstance(v, datetime):
        return (v if v.tzinfo else v.replace(tzinfo=LOCAL)), False
    return v, True


def instante(v):
    v, dia = as_dt(v)
    return v.isoformat() if dia else v.astimezone(timezone.utc).isoformat()


def vals(prop):
    if prop is None:
        return []
    lst = prop if isinstance(prop, list) else [prop]
    out = []
    for p in lst:
        out.extend(x.dt for x in p.dts)
    return out


eventos = [c for c in cal.walk("VEVENT")]
masters, overrides = {}, {}
for c in eventos:
    uid = str(c.get("UID"))
    if c.get("RECURRENCE-ID") is not None:
        overrides.setdefault(uid, []).append(c)
    elif c.get("RRULE") is not None or c.get("RDATE") is not None:
        masters[uid] = c
print(f"VEVENT={len(eventos)} series_com_RRULE/RDATE={len(masters)} overrides={sum(len(v) for v in overrides.values())}")


def chave_id(uid, inicio, dia):
    k = inicio.isoformat() if dia else str(int(inicio.timestamp()))
    return hashlib.sha1(f"{FONTE}|{uid}|{k}".encode()).hexdigest()[:16]


def toca(inicio, fim, dia):
    if dia:
        return inicio < ate_excl and fim > de
    if fim == inicio:
        return ini_j <= inicio < fim_j
    return inicio < fim_j and fim > ini_j


achados_ids = {e["id"] for e in agenda["events"] if e["source"] == FONTE}
achados_rec = {e["id"] for e in agenda["events"] if e["source"] == FONTE and e.get("recurring")}
stats = Counter()
linhas = []
esperados_total = set()
for idx, (uid, m) in enumerate(sorted(masters.items(), key=lambda kv: str(kv[1].get("DTSTART").dt))):
    if str(m.get("STATUS", "")).upper() == "CANCELLED":
        stats["serie_cancelada"] += 1
        continue
    dt0, dia = as_dt(m.get("DTSTART").dt)
    if m.get("DTEND") is not None:
        dur = as_dt(m.get("DTEND").dt)[0] - dt0
    elif m.get("DURATION") is not None:
        dur = m.get("DURATION").dt
    else:
        dur = timedelta(days=1) if dia else timedelta(hours=1)
    if dia and dur <= timedelta(0):
        dur = timedelta(days=1)
    base = datetime.combine(dt0, time()) if dia else dt0
    regra = m.get("RRULE")
    rset_txt = regra.to_ical().decode() if regra is not None else None
    until_passado = False
    if regra is not None and regra.get("UNTIL"):
        u = regra["UNTIL"][0]
        u = datetime.combine(u, time(23, 59, 59), LOCAL) if not isinstance(u, datetime) else (u if u.tzinfo else u.replace(tzinfo=LOCAL))
        until_passado = u < ini_j
    ativa_criterio = regra is not None and not until_passado  # "UNTIL futuro ou sem UNTIL"
    stats["ativa_criterio_tarefa"] += ativa_criterio
    # expansão independente
    ocorr = []
    if rset_txt:
        partes = [p for p in rset_txt.split(";") if not p.upper().startswith("UNTIL=")]
        r = rrulestr(";".join(partes), dtstart=base)
        if regra.get("UNTIL"):
            u = regra["UNTIL"][0]
            if not isinstance(u, datetime):  # UNTIL só data: inclui o dia inteiro
                u = datetime.combine(u, time(23, 59, 59))
                u = u if dia else u.replace(tzinfo=base.tzinfo)
            elif dia:
                u = u.astimezone(LOCAL).replace(tzinfo=None) if u.tzinfo else u
            elif u.tzinfo is None:
                u = u.replace(tzinfo=base.tzinfo)
            r = r.replace(until=u)
            stats["until_formato_" + type(regra["UNTIL"][0]).__name__] += 1
        lim = (datetime.combine(ate_excl, time()) if dia else fim_j) + timedelta(days=1)
        for o in r:
            if o >= lim:
                break
            ocorr.append(o)
    for rd in vals(m.get("RDATE")):
        rv, _ = as_dt(rd)
        ocorr.append(datetime.combine(rv, time()) if dia and not isinstance(rv, datetime) else rv)
    # viva = a regra ainda gera ocorrência a partir do início da janela (sem limite de horizonte)
    marco = datetime.combine(de, time()) if dia else ini_j
    viva = bool(rset_txt) and r.after(marco, inc=True) is not None
    if rset_txt and not viva and ativa_criterio and regra.get("COUNT"):
        stats["count_esgotado"] += 1
    exd = {instante(x if not dia else (x.date() if isinstance(x, datetime) else x)) for x in vals(m.get("EXDATE"))}
    por_inst = {}
    for o in ocorr:
        ini = o.date() if dia else o
        if instante(ini) in exd:
            stats["exdate_aplicado"] += 1
            continue
        por_inst[instante(ini)] = (ini, ini + dur)
    for ov in overrides.get(uid, []):
        rid = ov.get("RECURRENCE-ID")
        if rid.params.get("RANGE"):
            stats["range_thisandfuture"] += 1
        k = instante(rid.dt)
        por_inst.pop(k, None)
        if str(ov.get("STATUS", "")).upper() == "CANCELLED":
            stats["override_cancelado"] += 1
            continue
        oi, odia = as_dt(ov.get("DTSTART").dt)
        if ov.get("DTEND") is not None:
            of = as_dt(ov.get("DTEND").dt)[0]
        elif ov.get("DURATION") is not None:
            of = oi + ov.get("DURATION").dt
        else:
            of = oi + (timedelta(days=1) if odia else timedelta(hours=1))
        por_inst["ov|" + k] = (oi, of)
        stats["override_aplicado"] += 1
    na_janela = [(i, f) for (i, f) in por_inst.values() if toca(i, f, isinstance(i, date) and not isinstance(i, datetime))]
    esp = {chave_id(uid, i, isinstance(i, date) and not isinstance(i, datetime)) for i, _ in na_janela}
    esperados_total |= esp
    enc = esp & achados_ids
    if ativa_criterio or esp:
        linhas.append((idx, ativa_criterio, viva, len(esp), len(enc), sorted(esp - achados_ids)))
        if viva and not esp:
            prox = r.after(marco, inc=True)
            p_d = prox.date() if isinstance(prox, datetime) else prox
            print(f"  idx {idx}: FREQ={regra.get('FREQ')} próxima ocorrência {(p_d - ate_excl).days} dias depois do fim da janela; EXDATE/override na janela: {sum(1 for k in por_inst if k.startswith('ov|'))}")

print("stats:", dict(stats))
print("séries ativas pelo critério da tarefa (sem UNTIL ou UNTIL futuro):", sum(1 for l in linhas if l[1]))
print("  dessas, ainda vivas (têm ocorrência a partir do início da janela):", sum(1 for l in linhas if l[1] and l[2]))
print("idx | ativa | viva | esperadas na janela | encontradas | faltando")
for idx, at, vv, ne, nf, falt in linhas:
    print(f"{idx:>3} | {at!s:5} | {vv!s:5} | {ne:>3} | {nf:>3} | {len(falt)}")
print(f"TOTAL esperadas={len(esperados_total)} encontradas={len(esperados_total & achados_ids)}")
extras = achados_rec - esperados_total
print(f"no agenda.json marcadas recurring mas não previstas pela expansão independente: {len(extras)}")
print(f"eventos {FONTE} no agenda.json: {len(achados_ids)} (recurring={len(achados_rec)})")
