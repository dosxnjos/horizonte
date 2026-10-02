"""Linha de comando: agenda-sync {sync,configurar,migrar-do-ini,status,entrar}.

Regra: nada aqui imprime URL de agenda, token ou título de evento.
"""

from __future__ import annotations

import argparse
import codecs
import getpass
import json
import os
import re
import sys
import time
from pathlib import Path

from agenda_sync import __version__
from agenda_sync import config as cfgmod

# GoogleCalendarN do skin antigo -> apelido (roadmap § 3, "Apelidos")
MAPA_INI = {"GoogleCalendar1": "pessoal", "GoogleCalendar2": "corporativo", "GoogleCalendar3": "feriados"}
JANELA_ENTRAR_S = 30 * 60


def _saida_utf8() -> None:
    for fluxo in (sys.stdout, sys.stderr):
        try:
            fluxo.reconfigure(encoding="utf-8", errors="replace")
        except Exception:  # noqa: BLE001
            pass


# ---------------------------------------------------------------- migrar-do-ini


def ler_texto_ini(caminho: Path) -> str:
    """Decodifica o .ini do Rainmeter: BOM UTF-16 LE/BE ou UTF-8; sem BOM tenta UTF-8 e cai para cp1252."""
    dados = caminho.read_bytes()
    if dados.startswith(codecs.BOM_UTF16_LE) or dados.startswith(codecs.BOM_UTF16_BE):
        return dados.decode("utf-16")
    if dados.startswith(codecs.BOM_UTF8):
        return dados[3:].decode("utf-8")
    try:
        return dados.decode("utf-8")
    except UnicodeDecodeError:
        return dados.decode("cp1252", errors="replace")


def extrair_urls_ini(texto: str) -> dict[str, str]:
    """{apelido: url} das chaves GoogleCalendarN. ';' no meio do valor NÃO é comentário no Rainmeter,
    então só se descarta o que vem depois do primeiro espaço (padrão 'url ; <-- nota' do skin antigo)."""
    achados: dict[str, str] = {}
    for linha in texto.splitlines():
        m = re.match(r"^\s*(GoogleCalendar\d+)\s*=(.*)$", linha)
        if not m or m.group(1) not in MAPA_INI:
            continue
        valor = m.group(2).strip().strip('"')
        token = valor.split()[0] if valor.split() else ""
        if token.lower().startswith("http"):
            achados[MAPA_INI[m.group(1)]] = token
    return achados


def cmd_migrar_do_ini(caminho: str, base: Path | None = None, gravar=None) -> int:
    gravar = gravar or cfgmod.gravar_segredo
    p = Path(os.path.expandvars(caminho))
    if not p.is_file():
        print(f"arquivo não encontrado: {p.name}", file=sys.stderr)
        return 2
    urls = extrair_urls_ini(ler_texto_ini(p))
    if not urls:
        print("nenhuma chave GoogleCalendar1/2/3 com endereço http encontrada", file=sys.stderr)
        return 1
    cfg = cfgmod.carregar_config(base)
    for apelido in ("pessoal", "corporativo", "feriados"):
        url = urls.get(apelido)
        if not url:
            print(f"{apelido}: ausente no .ini")
            continue
        if apelido in cfgmod.FONTES_PRIVADAS:
            gravar(apelido, url)
            print(f"{apelido}: gravada ({len(url)} caracteres)")
        else:
            f = cfgmod.fonte(cfg, apelido)
            if f is not None:
                f["url"] = url
            print(f"{apelido}: gravada no config.toml ({len(url)} caracteres)")
    cfgmod.salvar_config(cfg, base)
    return 0


# ---------------------------------------------------------------- configurar


def cmd_configurar(base: Path | None = None, perguntar=None, gravar=None) -> int:
    perguntar = perguntar or getpass.getpass
    gravar = gravar or cfgmod.gravar_segredo
    cfgmod.carregar_config(base)  # garante o config.toml
    print("Cole o endereço secreto em formato iCal de cada agenda (Google Agenda > Configurações >")
    print("Integrar agenda). A digitação não aparece. Enter vazio mantém o que já está gravado.")
    for apelido in cfgmod.FONTES_PRIVADAS:
        valor = perguntar(f"{apelido}: ").strip()
        if not valor:
            print(f"{apelido}: mantida")
            continue
        if not valor.lower().startswith("https://"):
            print(f"{apelido}: ignorada (precisa começar com https://)")
            continue
        gravar(apelido, valor)
        print(f"{apelido}: gravada ({len(valor)} caracteres)")
    return 0


# ---------------------------------------------------------------- status


def _idade(segundos: float) -> str:
    s = int(max(segundos, 0))
    if s < 90:
        return f"{s} s"
    if s < 5400:
        return f"{s // 60} min"
    if s < 172800:
        return f"{s // 3600} h"
    return f"{s // 86400} dias"


def cmd_status(base: Path | None = None, agora: float | None = None) -> int:
    agora = agora if agora is not None else time.time()
    p = cfgmod.agenda_path(base)
    if not p.exists():
        print("agenda.json ainda não existe: rode agenda-sync sync")
        return 1
    doc = json.loads(p.read_text(encoding="utf-8"))
    # o agenda.json só é regravado quando o conteúdo muda; o lastOkAt real de cada fonte mora no estado do cache
    try:
        estado = json.loads((cfgmod.cache_dir(base) / "estado.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        estado = {}
    print(f"agenda.json: conteúdo mudou há {_idade(agora - doc.get('generatedAt', 0))}, "
          f"janela {doc['janela']['de']} a {doc['janela']['ate']}, {len(doc.get('events', []))} eventos")
    for s in doc.get("sources", []):
        if estado.get(s["id"], {}).get("lastOkAt"):
            s["lastOkAt"] = estado[s["id"]]["lastOkAt"]
    contagem: dict[str, int] = {}
    for e in doc.get("events", []):
        contagem[e["source"]] = contagem.get(e["source"], 0) + 1
    for s in doc.get("sources", []):
        ok = f"último ok há {_idade(agora - s['lastOkAt'])}" if s.get("lastOkAt") else "nunca ok"
        linha = f"  {s['id']:<12} {s['status']:<15} {contagem.get(s['id'], 0):>3} eventos  {ok}"
        if s.get("erro"):
            linha += f"  -> {s['erro']}"
        print(linha)
    pf = doc.get("proximoFeriado")
    if pf:
        print(f"próximo feriado: {pf['data']}")
    return 0


# ---------------------------------------------------------------- entrar


def escolher_reuniao(eventos: list[dict], agora: float) -> dict | None:
    """Evento com meetUrl em andamento (o que começou por último) ou o próximo em até 30 min."""
    com_link = [e for e in eventos if not e.get("allDay") and e.get("meetUrl")]
    andamento = [e for e in com_link if e["start"] <= agora < e["end"]]
    if andamento:
        return max(andamento, key=lambda e: e["start"])
    proximos = [e for e in com_link if agora < e["start"] <= agora + JANELA_ENTRAR_S]
    return min(proximos, key=lambda e: e["start"]) if proximos else None


def cmd_entrar(base: Path | None = None, agora: float | None = None, abrir=None) -> int:
    agora = agora if agora is not None else time.time()
    abrir = abrir or os.startfile  # type: ignore[attr-defined]
    cfg = cfgmod.carregar_config(base)
    eventos: list[dict] = []
    p = cfgmod.agenda_path(base)
    if p.exists():
        try:
            eventos = json.loads(p.read_text(encoding="utf-8")).get("events", [])
        except ValueError:
            eventos = []
    ev = escolher_reuniao(eventos, agora)
    if ev:
        abrir(ev["meetUrl"])
        print("abrindo a reunião")
        return 0
    abrir(f"https://calendar.google.com/calendar/u/{int(cfg.get('contaIndice', 0))}/r/day")
    print("nenhuma reunião agora nem nos próximos 30 min: abrindo o dia no Google Agenda")
    return 0


# ---------------------------------------------------------------- main


def main(argv: list[str] | None = None) -> int:
    _saida_utf8()
    ap = argparse.ArgumentParser(prog="agenda-sync", description="Agenda do Horizonte: baixa, expande e grava o agenda.json.")
    ap.add_argument("--version", action="version", version=f"agenda_sync {__version__}")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sync", help="baixa as fontes e grava o agenda.json")
    sub.add_parser("configurar", help="grava as URLs secretas no Gerenciador de Credenciais")
    m = sub.add_parser("migrar-do-ini", help="copia as URLs do .ini do skin antigo, sem imprimir")
    m.add_argument("caminho", help="caminho do Gcalendar.ini antigo")
    sub.add_parser("status", help="status por fonte e idade do agenda.json")
    sub.add_parser("entrar", help="abre a reunião em andamento ou a próxima em até 30 min")
    args = ap.parse_args(argv)

    if args.cmd == "sync":
        from agenda_sync.sync import rodar

        resumo = rodar()
        if resumo is None:
            print("outra sincronização em curso; nada feito")
            return 0
        partes = [f"{fid}={r['status']}({r['eventos']})" for fid, r in resumo["fontes"].items()]
        print(f"{' '.join(partes)} | eventos={resumo['eventos']} gravou={'sim' if resumo['gravou'] else 'não'}")
        return 0
    if args.cmd == "configurar":
        return cmd_configurar()
    if args.cmd == "migrar-do-ini":
        return cmd_migrar_do_ini(args.caminho)
    if args.cmd == "status":
        return cmd_status()
    if args.cmd == "entrar":
        return cmd_entrar()
    return 2
