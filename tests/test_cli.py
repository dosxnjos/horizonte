import codecs
import json
import tomllib

import pytest

from agenda_sync import cli
from agenda_sync import config as cfgmod

# valores falsos no formato dos reais; nunca podem aparecer na saída
URL1 = "https://feeds.example.invalid/calendar/ical/um%40example.org/private-aaa111/basic.ics"
URL2 = "https://feeds.example.invalid/calendar/ical/dois%40example.org/private-bbb222/basic.ics;x=1"
URL3 = "https://feeds.example.invalid/calendar/ical/feriados%40example.org/public/basic.ics"

INI = (
    "[Rainmeter]\r\nUpdate=1000\r\n\r\n[Variables]\r\n"
    "; comentário de linha inteira\r\n"
    f"GoogleCalendar1={URL1}\r\n"
    f"GoogleCalendar2={URL2} ; <-- ADICIONE TAMBÉM\r\n"  # ';' colado é dado; o resto depois do espaço é lixo
    f"GoogleCalendar3 = {URL3}\r\n"
    "Titulo=Agenda com acentuação\r\n"
)


def _gravador():
    gravados = {}
    return gravados, lambda k, v: gravados.__setitem__(k, v)


@pytest.mark.parametrize(
    "codificar",
    [
        lambda s: s.encode("utf-8"),  # o skin antigo real: UTF-8 sem BOM
        lambda s: codecs.BOM_UTF8 + s.encode("utf-8"),
        lambda s: codecs.BOM_UTF16_LE + s.encode("utf-16-le"),  # padrão novo do Rainmeter
        lambda s: s.encode("utf-16"),  # BOM do sistema
    ],
    ids=["utf8", "utf8-bom", "utf16le-bom", "utf16-bom"],
)
def test_migrar_do_ini_todas_as_codificacoes(isolar_pasta, tmp_path, capsys, codificar):
    ini = tmp_path / "Gcalendar.ini"
    ini.write_bytes(codificar(INI))
    gravados, gravar = _gravador()
    assert cli.cmd_migrar_do_ini(str(ini), isolar_pasta, gravar=gravar) == 0
    assert gravados == {"pessoal": URL1, "corporativo": URL2}
    with cfgmod.config_path(isolar_pasta).open("rb") as fh:
        cfg = tomllib.load(fh)
    assert cfgmod.fonte(cfg, "feriados")["url"] == URL3
    saida = capsys.readouterr()
    texto = saida.out + saida.err
    assert f"pessoal: gravada ({len(URL1)} caracteres)" in texto
    assert f"corporativo: gravada ({len(URL2)} caracteres)" in texto
    for proibido in ("example", "calendar/ical", "private-", "https"):
        assert proibido not in texto


def test_migrar_do_ini_arquivo_sem_chaves(isolar_pasta, tmp_path, capsys):
    ini = tmp_path / "vazio.ini"
    ini.write_text("[Variables]\nOutra=1\n", encoding="utf-8")
    gravados, gravar = _gravador()
    assert cli.cmd_migrar_do_ini(str(ini), isolar_pasta, gravar=gravar) == 1
    assert gravados == {}


def test_migrar_do_ini_arquivo_inexistente(isolar_pasta, tmp_path):
    assert cli.cmd_migrar_do_ini(str(tmp_path / "nao.ini"), isolar_pasta, gravar=lambda *a: None) == 2


def test_configurar_grava_sem_ecoar(isolar_pasta, capsys):
    respostas = iter([URL1, ""])
    gravados, gravar = _gravador()
    assert cli.cmd_configurar(isolar_pasta, perguntar=lambda _p: next(respostas), gravar=gravar) == 0
    assert gravados == {"pessoal": URL1}
    out = capsys.readouterr().out
    assert "pessoal: gravada" in out and "corporativo: mantida" in out and "example" not in out


def test_configurar_recusa_http_sem_tls(isolar_pasta, capsys):
    respostas = iter(["http://inseguro.invalid/x.ics", ""])
    gravados, gravar = _gravador()
    cli.cmd_configurar(isolar_pasta, perguntar=lambda _p: next(respostas), gravar=gravar)
    assert gravados == {} and "inseguro" not in capsys.readouterr().out


# ------------------------------------------------------------------ entrar


def _ev(inicio, fim, meet="https://meet.google.com/aaa-bbbb-ccc", all_day=False):
    if all_day:
        return {"allDay": True, "startDate": "2026-10-02", "endDate": "2026-10-03", "meetUrl": meet}
    return {"allDay": False, "start": inicio, "end": fim, "meetUrl": meet}


def test_escolher_reuniao():
    agora = 1_000_000
    em_andamento = _ev(agora - 600, agora + 600, "https://meet.google.com/em-andamento")
    proxima = _ev(agora + 20 * 60, agora + 50 * 60, "https://meet.google.com/proxima")
    longe = _ev(agora + 40 * 60, agora + 60 * 60, "https://meet.google.com/longe")
    sem_link = _ev(agora - 60, agora + 60, None)
    assert cli.escolher_reuniao([sem_link, em_andamento, proxima], agora)["meetUrl"].endswith("em-andamento")
    assert cli.escolher_reuniao([sem_link, longe, proxima], agora)["meetUrl"].endswith("proxima")
    assert cli.escolher_reuniao([sem_link, longe, _ev(0, 0, all_day=True)], agora) is None


def test_entrar_abre_meet_ou_dia_do_google(isolar_pasta):
    agora = 2_000_000
    doc = {"events": [_ev(agora + 300, agora + 3600, "https://meet.google.com/xyz-abcd-efg")]}
    cfgmod.agenda_path(isolar_pasta).parent.mkdir(parents=True, exist_ok=True)
    cfgmod.agenda_path(isolar_pasta).write_text(json.dumps(doc), encoding="utf-8")
    abertos = []
    cli.cmd_entrar(isolar_pasta, agora=agora, abrir=abertos.append)
    cli.cmd_entrar(isolar_pasta, agora=agora + 7200, abrir=abertos.append)
    assert abertos == ["https://meet.google.com/xyz-abcd-efg", "https://calendar.google.com/calendar/u/0/r/day"]


def test_entrar_sem_agenda_json(isolar_pasta):
    abertos = []
    assert cli.cmd_entrar(isolar_pasta, agora=0, abrir=abertos.append) == 0
    assert abertos == ["https://calendar.google.com/calendar/u/0/r/day"]


# ------------------------------------------------------------------ status


def test_status_sem_titulos(isolar_pasta, capsys):
    doc = {
        "generatedAt": 1000,
        "janela": {"de": "2026-10-01", "ate": "2026-10-17"},
        "proximoFeriado": {"data": "2026-10-12", "nome": "Feriado X"},
        "sources": [
            {"id": "pessoal", "status": "ok", "lastOkAt": 1000, "erro": None},
            {"id": "corporativo", "status": "http404", "lastOkAt": None, "erro": "o Google respondeu 404: regere"},
        ],
        "events": [{"source": "pessoal", "title": "Titulo Secreto"}],
    }
    cfgmod.agenda_path(isolar_pasta).parent.mkdir(parents=True, exist_ok=True)
    cfgmod.agenda_path(isolar_pasta).write_text(json.dumps(doc), encoding="utf-8")
    assert cli.cmd_status(isolar_pasta, agora=1600) == 0
    out = capsys.readouterr().out
    assert "Titulo Secreto" not in out and "Feriado X" not in out
    assert "pessoal" in out and "http404" in out and "1 eventos" in out and "10 min" in out


def test_status_sem_arquivo(isolar_pasta, capsys):
    assert cli.cmd_status(isolar_pasta) == 1


def test_main_versao(capsys):
    with pytest.raises(SystemExit) as e:
        cli.main(["--version"])
    assert e.value.code == 0 and "agenda_sync" in capsys.readouterr().out
