import json
from datetime import date

import httpx
import pytest

from agenda_sync import config as cfgmod
from agenda_sync import ical, sync

from conftest import SP, epoch, ler

# URLs falsas no formato das reais (para provar que não vazam), em domínio reservado .invalid
URLS = {
    "pessoal": "https://feeds.example.invalid/calendar/ical/pessoal.ficticio%40example.org/private-abc123/basic.ics",
    "corporativo": "https://feeds.example.invalid/calendar/ical/corp.ficticio%40example.org/private-def456/basic.ics",
    "feriados": "https://feeds.example.invalid/calendar/ical/feriados%40example.org/public/basic.ics",
}
HOJE = date(2026, 10, 2)
AGORA = epoch(2026, 10, 2, 12)


class Rede:
    """Transporte falso: cada URL devolve o que o teste mandar e conta as chamadas."""

    def __init__(self):
        self.respostas = {
            URLS["pessoal"]: (200, ler("basico.ics")),
            URLS["corporativo"]: (200, ler("recorrencia.ics")),
            URLS["feriados"]: (200, ler("feriados.ics")),
        }
        self.chamadas: dict[str, int] = {}

    def __call__(self, req: httpx.Request) -> httpx.Response:
        url = str(req.url)
        self.chamadas[url] = self.chamadas.get(url, 0) + 1
        resp = self.respostas[url]
        if isinstance(resp, Exception):
            raise resp
        status, corpo, *ct = resp
        return httpx.Response(status, content=corpo, headers={"content-type": ct[0] if ct else "text/calendar"})


@pytest.fixture
def base(isolar_pasta):
    cfg = cfgmod.carregar_config(isolar_pasta)
    cfgmod.fonte(cfg, "feriados")["url"] = URLS["feriados"]
    cfg["fontes"][1]["contaIndice"] = 1
    cfg["intervaloFeriadosH"] = 24  # o padrão é semanal; 24 h deixa os testes de cadência legíveis
    cfgmod.salvar_config(cfg, isolar_pasta)
    return isolar_pasta


@pytest.fixture
def rede():
    return Rede()


def rodar(base, rede, agora=AGORA, segredos=None, avisos=None, hoje=HOJE):
    segredos = URLS if segredos is None else segredos
    avisos = avisos if avisos is not None else []
    resumo = sync.rodar(
        base,
        hoje=hoje,
        local_tz=SP,
        agora=agora,
        transport=httpx.MockTransport(rede),
        ler_segredo=lambda fid: segredos.get(fid),
        animacoes=lambda: True,
        avisar=lambda exe, cfgs: avisos.append(list(cfgs)) or len(cfgs),
    )
    doc = json.loads(cfgmod.agenda_path(base).read_text(encoding="utf-8"))
    return resumo, doc


def _fonte(doc, fid):
    return next(s for s in doc["sources"] if s["id"] == fid)


def _eventos(doc, fid):
    return [e for e in doc["events"] if e["source"] == fid]


# ------------------------------------------------------------------ caminho feliz


def test_sync_completo_gera_contrato(base, rede):
    avisos = []
    resumo, doc = rodar(base, rede, avisos=avisos)
    assert doc["schemaVersion"] == 1 and doc["producer"].startswith("agenda_sync ")
    assert doc["generatedAt"] == AGORA
    assert doc["janela"] == {"de": "2026-10-01", "ate": "2026-10-17"}
    assert doc["ambiente"] == {"animacoes": True}
    assert doc["proximoFeriado"] == {"data": "2026-10-12", "nome": "Feriado sintetico de outubro"}
    assert [s["id"] for s in doc["sources"]] == ["pessoal", "corporativo", "feriados"]
    assert [s["cor"] for s in doc["sources"]] == ["#7AA2F7", "#C3A6FF", "#5FD0B5"]
    for s in doc["sources"]:
        assert s["status"] == "ok" and s["httpStatus"] == 200 and s["erro"] is None
        assert s["lastOkAt"] == AGORA and s["lastAttemptAt"] == AGORA
    assert _eventos(doc, "pessoal") and _eventos(doc, "corporativo")
    # feriado de novembro fica fora da lista (janela de 15 dias), mas o de outubro entra
    assert [e["startDate"] for e in _eventos(doc, "feriados")] == ["2026-10-12"]
    # conta do corporativo vai no link
    assert all("/u/1/" in e["link"] for e in _eventos(doc, "corporativo"))
    assert resumo["gravou"] is True and avisos == [["Horizonte\\Dia", "Horizonte\\Agenda", "Horizonte\\Relogio"]]


def test_eventos_ordenados_e_campos(base, rede):
    _, doc = rodar(base, rede)
    chaves = [e["start"] if not e["allDay"] else epoch(*map(int, e["startDate"].split("-"))) for e in doc["events"]]
    assert chaves == sorted(chaves)
    for e in doc["events"]:
        assert {"id", "source", "title", "allDay", "recurring", "location", "meetUrl", "link"} <= set(e)
        if e["allDay"]:
            assert set(e) >= {"startDate", "endDate"} and "start" not in e
        else:
            assert isinstance(e["start"], int) and isinstance(e["end"], int) and e["end"] >= e["start"]


def test_json_utf8_sem_bom(base, rede):
    rodar(base, rede)
    bruto = cfgmod.agenda_path(base).read_bytes()
    assert not bruto.startswith(b"\xef\xbb\xbf")
    bruto.decode("utf-8")


def test_contrato_sem_url_de_feed_nem_email(base, rede):
    _, doc = rodar(base, rede)
    texto = cfgmod.agenda_path(base).read_text(encoding="utf-8")
    assert "calendar/ical" not in texto
    assert "example.invalid" not in texto and "private-" not in texto
    assert "description" not in texto and "Pauta" not in texto

    def varrer(no, chave=None):
        if isinstance(no, dict):
            for k, v in no.items():
                varrer(v, k)
        elif isinstance(no, list):
            for v in no:
                varrer(v, chave)
        elif isinstance(no, str) and chave not in ("meetUrl", "link"):
            assert "@" not in no, f"'@' no campo {chave}"

    varrer(doc)


# ------------------------------------------------------------------ falhas por fonte


def test_offline_mantem_eventos_do_ultimo_sucesso(base, rede):
    _, antes = rodar(base, rede)
    rede.respostas[URLS["pessoal"]] = httpx.ConnectError("sem rede")
    _, depois = rodar(base, rede, agora=AGORA + 600)
    s = _fonte(depois, "pessoal")
    assert s["status"] == "offline" and s["httpStatus"] is None
    assert s["lastOkAt"] == AGORA and s["lastAttemptAt"] == AGORA + 600
    assert "último dado bom" in s["erro"]
    assert _eventos(depois, "pessoal") == _eventos(antes, "pessoal")
    assert _fonte(depois, "corporativo")["status"] == "ok"


def test_html_de_portal_cativo_e_offline(base, rede):
    rodar(base, rede)
    rede.respostas[URLS["corporativo"]] = (200, ler("portal.html"), "text/html")
    _, doc = rodar(base, rede, agora=AGORA + 600)
    assert _fonte(doc, "corporativo")["status"] == "offline"
    assert _eventos(doc, "corporativo")


def test_404_marca_status_e_mensagem_acionavel(base, rede):
    rodar(base, rede)
    rede.respostas[URLS["corporativo"]] = (404, b"<html>Error 404</html>", "text/html")
    _, doc = rodar(base, rede, agora=AGORA + 600)
    s = _fonte(doc, "corporativo")
    assert s["status"] == "http404" and s["httpStatus"] == 404
    assert "regere o endereço secreto" in s["erro"] and "agenda-sync configurar" in s["erro"]
    assert _eventos(doc, "corporativo")  # último bom continua visível, com o erro ao lado


def test_404_sem_nunca_ter_tido_sucesso_fica_vazio(base, rede):
    rede.respostas[URLS["corporativo"]] = (404, b"", "text/html")
    _, doc = rodar(base, rede)
    assert _fonte(doc, "corporativo")["status"] == "http404" and _fonte(doc, "corporativo")["lastOkAt"] is None
    assert _eventos(doc, "corporativo") == []


def test_truncado_e_formato_e_mantem_anterior(base, rede):
    _, antes = rodar(base, rede)
    rede.respostas[URLS["pessoal"]] = (200, ler("truncado.ics"))
    _, doc = rodar(base, rede, agora=AGORA + 600)
    assert _fonte(doc, "pessoal")["status"] == "formato"
    assert _eventos(doc, "pessoal") == _eventos(antes, "pessoal")


def test_sem_credencial(base, rede):
    _, doc = rodar(base, rede, segredos={"pessoal": URLS["pessoal"]})
    s = _fonte(doc, "corporativo")
    assert s["status"] == "sem_credencial" and "agenda-sync configurar" in s["erro"]
    assert _eventos(doc, "corporativo") == [] and URLS["corporativo"] not in rede.chamadas


def test_feriados_sem_url_no_config(isolar_pasta, rede):
    _, doc = rodar(isolar_pasta, rede)  # config padrão: url dos feriados vazia
    s = _fonte(doc, "feriados")
    assert s["status"] == "sem_credencial" and "migrar-do-ini" in s["erro"]
    assert doc["proximoFeriado"] is None


# ------------------------------------------------------------------ cache e economia


def test_feriados_baixados_no_maximo_a_cada_24h(base, rede):
    rodar(base, rede)
    rodar(base, rede, agora=AGORA + 3600)
    rodar(base, rede, agora=AGORA + 23 * 3600)
    assert rede.chamadas[URLS["feriados"]] == 1
    assert rede.chamadas[URLS["pessoal"]] == 3
    _, doc = rodar(base, rede, agora=AGORA + 25 * 3600)
    assert rede.chamadas[URLS["feriados"]] == 2
    assert doc["proximoFeriado"]["data"] == "2026-10-12"


def test_feriados_em_cache_continuam_no_json(base, rede):
    rodar(base, rede)
    _, doc = rodar(base, rede, agora=AGORA + 3600)
    assert _fonte(doc, "feriados")["status"] == "ok"
    assert _eventos(doc, "feriados") and doc["proximoFeriado"]


def test_so_dtstamp_mudou_nao_reprocessa(base, rede, monkeypatch):
    rodar(base, rede)
    chamadas = []
    original = ical.expandir
    monkeypatch.setattr(ical, "expandir", lambda *a, **k: chamadas.append(a[1]) or original(*a, **k))
    rede.respostas[URLS["pessoal"]] = (200, ler("basico.ics").replace(b"DTSTAMP:20261001T120000Z", b"DTSTAMP:20261002T150000Z"))
    rodar(base, rede, agora=AGORA + 600)
    assert chamadas == []  # mesmo hash sem DTSTAMP e mesma janela: nenhuma fonte reexpandida


def test_janela_nova_reexpande(base, rede, monkeypatch):
    rodar(base, rede)
    chamadas = []
    original = ical.expandir
    monkeypatch.setattr(ical, "expandir", lambda *a, **k: chamadas.append(a[1]) or original(*a, **k))
    _, doc = rodar(base, rede, agora=AGORA + 86400, hoje=date(2026, 10, 3))
    assert set(chamadas) >= {"pessoal", "corporativo"}
    assert doc["janela"]["de"] == "2026-10-02"


def test_grava_so_quando_muda_e_so_entao_avisa(base, rede):
    avisos = []
    r1, d1 = rodar(base, rede, avisos=avisos)
    mtime = cfgmod.agenda_path(base).stat().st_mtime_ns
    r2, d2 = rodar(base, rede, agora=AGORA + 600, avisos=avisos)
    assert r1["gravou"] is True and r2["gravou"] is False
    assert len(avisos) == 1 and cfgmod.agenda_path(base).stat().st_mtime_ns == mtime
    assert d2["generatedAt"] == AGORA  # arquivo intocado
    rede.respostas[URLS["pessoal"]] = (200, ler("basico.ics").replace(b"Evento em UTC", b"Evento em UTC mudou"))
    r3, d3 = rodar(base, rede, agora=AGORA + 1200, avisos=avisos)
    assert r3["gravou"] is True and len(avisos) == 2 and d3["generatedAt"] == AGORA + 1200


def test_mudanca_de_status_regrava(base, rede):
    rodar(base, rede)
    rede.respostas[URLS["pessoal"]] = httpx.ConnectError("sem rede")
    r, _ = rodar(base, rede, agora=AGORA + 600)
    assert r["gravou"] is True


# ------------------------------------------------------------------ log, trava, config


def test_log_sem_url_nem_titulo(base, rede):
    rodar(base, rede)
    rede.respostas[URLS["corporativo"]] = (404, b"", "text/html")
    rodar(base, rede, agora=AGORA + 600)
    log = cfgmod.log_path(base).read_text(encoding="utf-8")
    assert "fonte=pessoal status=ok" in log and "fonte=corporativo status=http404" in log
    for proibido in ("example", "calendar/ical", "private-", "@", "Alinhamento", "Daily", "Feriado sintetico"):
        assert proibido not in log, proibido


def test_trava_impede_execucao_concorrente(base, rede):
    with sync.trava(base) as t:
        assert t is not None
        assert sync.rodar(base, transport=httpx.MockTransport(rede), ler_segredo=URLS.get, avisar=None) is None
    assert rede.chamadas == {}


def test_config_padrao_criado(isolar_pasta):
    cfg = cfgmod.carregar_config(isolar_pasta)
    assert cfgmod.config_path(isolar_pasta).exists()
    assert [f["id"] for f in cfg["fontes"]] == ["pessoal", "corporativo", "feriados"]
    assert cfg["intervaloFeriadosH"] == 168 and cfg["janelaDias"] == 15 and cfg["contaIndice"] == 0
    assert cfgmod.fonte(cfg, "feriados")["url"] == ""


def test_endereco_invalido_nao_derruba_as_outras_fontes(base, rede):
    segredos = dict(URLS, corporativo="nao-e-url")
    _, doc = rodar(base, rede, segredos=segredos)
    s = _fonte(doc, "corporativo")
    assert s["status"] == "sem_credencial" and "agenda-sync configurar" in s["erro"]
    assert _fonte(doc, "pessoal")["status"] == "ok" and _fonte(doc, "feriados")["status"] == "ok"


def test_falha_inesperada_numa_fonte_isola(base, rede, monkeypatch):
    from agenda_sync import fetch

    original = fetch.baixar

    def explode_no_pessoal(url, **k):
        if url == URLS["pessoal"]:
            raise RuntimeError("bug qualquer")
        return original(url, **k)

    monkeypatch.setattr(fetch, "baixar", explode_no_pessoal)
    _, doc = rodar(base, rede)
    assert _fonte(doc, "pessoal")["status"] == "formato" and "sync.log" in _fonte(doc, "pessoal")["erro"]
    assert _fonte(doc, "corporativo")["status"] == "ok" and _eventos(doc, "corporativo")


def test_feed_com_bom_expande(base, rede):
    rede.respostas[URLS["pessoal"]] = (200, b"\xef\xbb\xbf\r\n" + ler("basico.ics"))
    _, doc = rodar(base, rede)
    assert _fonte(doc, "pessoal")["status"] == "ok" and _eventos(doc, "pessoal")


# ------------------------------------------------------------------ revisão adversarial (fase 1)

# Passa no classificar (começa e termina certo), mas o icalendar não consegue ler.
NAO_PARSEIA = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:x@fixture.invalid\r\nEND:VCALENDAR\r\n"


def test_feed_que_nao_parseia_nao_avanca_last_ok_at(base, rede):
    _, antes = rodar(base, rede)
    rede.respostas[URLS["pessoal"]] = (200, NAO_PARSEIA)
    _, doc = rodar(base, rede, agora=AGORA + 600)
    s = _fonte(doc, "pessoal")
    assert s["status"] == "formato" and s["lastOkAt"] == AGORA and s["lastAttemptAt"] == AGORA + 600
    assert _eventos(doc, "pessoal") == _eventos(antes, "pessoal")
    estado = json.loads((cfgmod.cache_dir(base) / "estado.json").read_text(encoding="utf-8"))
    assert estado["pessoal"]["lastOkAt"] == AGORA  # o `status` do CLI lê daqui


def test_feed_que_nao_parseia_na_primeira_vez_fica_vazio(base, rede):
    rede.respostas[URLS["pessoal"]] = (200, NAO_PARSEIA)
    _, doc = rodar(base, rede)
    s = _fonte(doc, "pessoal")
    assert s["status"] == "formato" and s["lastOkAt"] is None and _eventos(doc, "pessoal") == []


def test_falha_inesperada_mantem_o_ultimo_bom(base, rede, monkeypatch):
    from agenda_sync import fetch

    _, antes = rodar(base, rede)
    original = fetch.baixar

    def explode_no_pessoal(url, **k):
        if url == URLS["pessoal"]:
            raise RuntimeError("bug qualquer")
        return original(url, **k)

    monkeypatch.setattr(fetch, "baixar", explode_no_pessoal)
    _, doc = rodar(base, rede, agora=AGORA + 600)
    assert _fonte(doc, "pessoal")["status"] == "formato"
    assert _eventos(doc, "pessoal") == _eventos(antes, "pessoal") != []


def test_offline_sem_cache_de_expansao_reexpande_o_ics_bom(base, rede):
    _, antes = rodar(base, rede)
    (cfgmod.cache_dir(base) / "pessoal.eventos.json").unlink()
    rede.respostas[URLS["pessoal"]] = httpx.ConnectError("sem rede")
    _, doc = rodar(base, rede, agora=AGORA + 600)
    assert _fonte(doc, "pessoal")["status"] == "offline"
    assert _eventos(doc, "pessoal") == _eventos(antes, "pessoal") != []


def test_cache_de_versao_antiga_e_reexpandido(base, rede, monkeypatch):
    rodar(base, rede)
    p = cfgmod.cache_dir(base) / "pessoal.eventos.json"
    velho = json.loads(p.read_text(encoding="utf-8"))
    velho["chave"]["v"] = ical.VERSAO_EXPANSAO - 1
    velho["events"] = []  # expansão velha (errada) que o cache não pode servir
    p.write_text(json.dumps(velho), encoding="utf-8")
    chamadas = []
    original = ical.expandir
    monkeypatch.setattr(ical, "expandir", lambda *a, **k: chamadas.append(a[1]) or original(*a, **k))
    _, doc = rodar(base, rede, agora=AGORA + 600)
    assert chamadas == ["pessoal"] and _eventos(doc, "pessoal")


def test_feriados_padrao_semanal(isolar_pasta, rede):
    cfg = cfgmod.carregar_config(isolar_pasta)
    cfgmod.fonte(cfg, "feriados")["url"] = URLS["feriados"]
    cfgmod.salvar_config(cfg, isolar_pasta)
    rodar(isolar_pasta, rede)
    rodar(isolar_pasta, rede, agora=AGORA + 6 * 86400)
    assert rede.chamadas[URLS["feriados"]] == 1
    rodar(isolar_pasta, rede, agora=AGORA + 7 * 86400 + 60, hoje=date(2026, 10, 9))
    assert rede.chamadas[URLS["feriados"]] == 2


def test_evento_da_noite_do_ultimo_dia_entra_no_json(base, rede):
    rede.respostas[URLS["pessoal"]] = (200, ler("janela_fusos.ics"))
    _, doc = rodar(base, rede, hoje=date(2026, 10, 2))  # janela 01/10 a 17/10
    titulos = {e["title"] for e in _eventos(doc, "pessoal")}
    assert {"Ultimo dia a noite em UTC", "Ultimo dia em outro fuso", "Comecou antes e segue"} <= titulos
    assert "Logo depois da janela" not in titulos
