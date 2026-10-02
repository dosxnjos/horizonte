from datetime import date
from zoneinfo import ZoneInfo

from agenda_sync import ical

from conftest import SP, epoch, ler, utc

DE, ATE_EXCL = date(2026, 10, 1), date(2026, 10, 18)


def _expandir(nome, de=DE, ate=ATE_EXCL, tz=SP):
    return ical.ordenar(ical.expandir(ler(nome), "pessoal", de, ate, conta=2, local_tz=tz))


def _por_titulo(evs, titulo):
    return [e for e in evs if e["title"] == titulo]


# ------------------------------------------------------------------ eventos simples


def test_evento_com_tzid():
    (e,) = _por_titulo(_expandir("basico.ics"), "Alinhamento semanal")
    assert e["start"] == utc(2026, 10, 5, 12) and e["end"] == utc(2026, 10, 5, 13)
    assert e["allDay"] is False and e["recurring"] is False


def test_evento_utc_z():
    (e,) = _por_titulo(_expandir("basico.ics"), "Evento em UTC")
    assert (e["start"], e["end"]) == (utc(2026, 10, 6, 13), utc(2026, 10, 6, 14))


def test_evento_floating_usa_hora_local():
    (e,) = _por_titulo(_expandir("basico.ics"), "Evento flutuante")
    assert e["start"] == epoch(2026, 10, 7, 8)  # 08:00 local = 11:00Z
    (e_ny,) = _por_titulo(_expandir("basico.ics", tz=ZoneInfo("America/New_York")), "Evento flutuante")
    assert e_ny["start"] == epoch(2026, 10, 7, 8, tz=ZoneInfo("America/New_York"))


def test_dia_inteiro_e_data_nunca_epoch():
    (e,) = _por_titulo(_expandir("basico.ics"), "Dia inteiro")
    assert e["allDay"] is True
    assert (e["startDate"], e["endDate"]) == ("2026-10-08", "2026-10-09")
    assert "start" not in e and "end" not in e


def test_multi_dia():
    (e,) = _por_titulo(_expandir("basico.ics"), "Viagem de tres dias")
    assert (e["startDate"], e["endDate"]) == ("2026-10-10", "2026-10-13")
    (p,) = _por_titulo(_expandir("basico.ics"), "Plantao noturno")
    assert p["end"] - p["start"] == 4 * 3600


def test_sem_dtend_datetime_vira_uma_hora():
    (e,) = _por_titulo(_expandir("basico.ics"), "Sem fim com hora")
    assert e["end"] - e["start"] == 3600


def test_sem_dtend_date_vira_um_dia():
    (e,) = _por_titulo(_expandir("basico.ics"), "Sem fim dia inteiro")
    assert (e["startDate"], e["endDate"]) == ("2026-10-11", "2026-10-12")


def test_duration_respeitada():
    (e,) = _por_titulo(_expandir("basico.ics"), "Com DURATION")
    assert e["end"] - e["start"] == 45 * 60


def test_cancelado_some_e_fora_da_janela_some():
    titulos = {e["title"] for e in _expandir("basico.ics")}
    assert "Evento cancelado" not in titulos
    assert "Fora antes" not in titulos and "Fora depois" not in titulos


def test_meet_url_da_descricao_conferencia_e_teams():
    evs = _expandir("basico.ics")
    assert _por_titulo(evs, "Alinhamento semanal")[0]["meetUrl"] == "https://meet.google.com/abc-defg-hij"
    conf = _por_titulo(evs, "Chamada com conferencia")[0]
    assert conf["meetUrl"] == "https://meet.google.com/xyz-abcd-efg"
    assert conf["location"] is None  # local que era só a URL some
    assert _por_titulo(evs, "Chamada no Teams")[0]["meetUrl"].startswith("https://teams.microsoft.com/l/meetup-join/")
    assert _por_titulo(evs, "Evento em UTC")[0]["meetUrl"] is None


def test_location_sem_email_e_sem_descricao():
    (e,) = _por_titulo(_expandir("basico.ics"), "Alinhamento semanal")
    assert e["location"] == "Sala 3 - responsavel"
    assert "description" not in e and "Pauta" not in str(e)


def test_link_da_semana_com_conta():
    (e,) = _por_titulo(_expandir("basico.ics"), "Alinhamento semanal")
    assert e["link"] == "https://calendar.google.com/calendar/u/2/r/week/2026/10/5"


def test_ordenado_por_inicio_com_dia_inteiro_na_meia_noite():
    evs = _expandir("basico.ics")
    chaves = [e["start"] if not e["allDay"] else epoch(*map(int, e["startDate"].split("-"))) for e in evs]
    assert chaves == sorted(chaves)


def test_id_estavel_e_unico():
    a, b = _expandir("recorrencia.ics"), _expandir("recorrencia.ics")
    assert [e["id"] for e in a] == [e["id"] for e in b]
    assert len({e["id"] for e in a}) == len(a)


# ------------------------------------------------------------------ recorrência


def test_weekly_com_exdate_e_recurrence_id_remarcado():
    evs = [e for e in _expandir("recorrencia.ics") if e["title"].startswith("Daily de produto")]
    inicios = [e["start"] for e in evs]
    assert inicios == [
        epoch(2026, 10, 5, 9, 30),  # segunda
        # quarta 07/10 removida pelo EXDATE
        epoch(2026, 10, 12, 14, 0),  # segunda remarcada de 09:30 para 14:00
        epoch(2026, 10, 14, 9, 30),  # quarta
    ]
    assert all(e["recurring"] for e in evs)
    assert evs[1]["title"] == "Daily de produto (remarcada)"


def test_daily_count_com_instancia_cancelada():
    evs = _por_titulo(_expandir("recorrencia.ics"), "Checagem diaria")
    # COUNT=5 a partir de 30/09: 30/09 fora da janela, 03/10 cancelada
    assert [e["start"] for e in evs] == [epoch(2026, 10, d, 10) for d in (1, 2, 4)]


def test_monthly_byday_primeira_sexta():
    evs = _por_titulo(_expandir("recorrencia.ics"), "Fechamento do mes")
    assert [e["start"] for e in evs] == [epoch(2026, 10, 2, 16)]


def test_yearly_dia_inteiro():
    (e,) = _por_titulo(_expandir("recorrencia.ics"), "Aniversario ficticio")
    assert (e["startDate"], e["endDate"], e["recurring"]) == ("2026-10-10", "2026-10-11", True)


def test_dia_inteiro_semanal_com_until():
    evs = _por_titulo(_expandir("recorrencia.ics"), "Sexta sem reuniao")
    assert [e["startDate"] for e in evs] == ["2026-10-02", "2026-10-09"]


def test_rdate():
    evs = _por_titulo(_expandir("recorrencia.ics"), "Revisao avulsa")
    assert [e["start"] for e in evs] == [epoch(2026, 10, 1, 17), epoch(2026, 10, 15, 17)]


# ------------------------------------------------------------------ calendário e fuso


def test_virada_de_mes():
    evs = _expandir("virada_mes.ics", de=date(2026, 10, 29), ate=date(2026, 11, 15))
    (atr,) = _por_titulo(evs, "Atravessa a meia-noite")
    assert atr["end"] - atr["start"] == 3600
    assert atr["link"].endswith("/2026/10/31")
    (pd,) = _por_titulo(evs, "Primeiro dia do mes")
    assert (pd["startDate"], pd["endDate"]) == ("2026-11-01", "2026-11-02")
    rot = _por_titulo(evs, "Rotina da virada")
    assert [e["start"] for e in rot] == [
        epoch(2026, 10, 30, 8), epoch(2026, 10, 31, 8), epoch(2026, 11, 1, 8), epoch(2026, 11, 2, 8)
    ]


def test_horario_de_verao_new_york():
    evs = _expandir("dst_ny.ics", de=date(2027, 3, 9), ate=date(2027, 3, 26))
    # 09:00 em NY: EST (UTC-5) antes de 14/03/2027, EDT (UTC-4) depois
    assert [e["start"] for e in evs] == [utc(2027, 3, 11, 14), utc(2027, 3, 18, 13), utc(2027, 3, 25, 13)]
    assert all(e["end"] - e["start"] == 3600 for e in evs)


def test_borda_da_janela_no_fuso_local():
    # janela [01/10, 18/10) em Brasília; a lib compara datas no fuso de cada evento
    titulos = {e["title"] for e in _expandir("janela_fusos.ics")}
    assert "Ultimo dia a noite em UTC" in titulos  # 17/10 22:30 local = 18/10 01:30Z
    assert "Ultimo dia em outro fuso" in titulos  # 18/10 09:00 Tóquio = 17/10 21:00 local
    assert "Madrugada do primeiro dia" in titulos
    assert "Logo depois da janela" not in titulos  # 18/10 00:00 local: fim exclusivo
    assert "Termina quando a janela abre" not in titulos  # 30/09 23:00 até 01/10 00:00 local


def test_evento_em_andamento_quando_a_janela_abre():
    evs = _expandir("janela_fusos.ics")
    (e,) = _por_titulo(evs, "Comecou antes e segue")
    assert e["start"] == epoch(2026, 9, 29, 9) and e["end"] == epoch(2026, 10, 3, 9)
    (d,) = _por_titulo(evs, "Dias inteiros que atravessam")
    assert (d["startDate"], d["endDate"]) == ("2026-09-29", "2026-10-03")
    assert not _por_titulo(evs, "Dias inteiros que acabam antes")  # endDate exclusivo = 01/10


def test_duracao_zero_na_borda_entra():
    (e,) = _por_titulo(_expandir("janela_fusos.ics"), "Lembrete na meia-noite")
    assert e["start"] == e["end"] == epoch(2026, 10, 1)


def test_exdate_e_recurrence_id_em_utc_numa_serie_com_tzid():
    evs = _por_titulo(_expandir("recorrencia_extra.ics"), "Serie com excecoes em UTC")
    assert [e["start"] for e in evs] == [
        epoch(2026, 10, 1, 10),  # quinta
        # 06/10 tirada pelo EXDATE em Z
        epoch(2026, 10, 8, 10),
        # 13/10 remarcada (RECURRENCE-ID em Z) para 25/10: sai da janela
        epoch(2026, 10, 15, 10),
        epoch(2026, 10, 16, 10),  # 27/10 (fora) remarcada para 16/10: entra
    ]
    assert len({e["id"] for e in evs}) == len(evs)


def test_instancia_orfa_aparece_uma_vez():
    (e,) = _por_titulo(_expandir("recorrencia_extra.ics"), "Instancia sem a serie")
    assert e["start"] == epoch(2026, 10, 8, 15) and e["recurring"] is True


def test_evento_quebrado_nao_derruba_o_feed():
    titulos = {e["title"] for e in _expandir("recorrencia_extra.ics")}
    assert "Evento quebrado" not in titulos and "Regra quebrada" not in titulos
    assert "Instancia sem a serie" in titulos


def test_toca_janela_dia_inteiro_e_hora():
    de, ate = date(2026, 10, 1), date(2026, 10, 18)
    dia = {"allDay": True, "startDate": "2026-10-17", "endDate": "2026-10-18"}
    assert ical.toca_janela(dia, de, ate, SP)
    assert not ical.toca_janela(dict(dia, startDate="2026-10-18", endDate="2026-10-19"), de, ate, SP)
    hora = {"allDay": False, "start": epoch(2026, 10, 17, 23, 59), "end": epoch(2026, 10, 18, 0, 30)}
    assert ical.toca_janela(hora, de, ate, SP)
    assert not ical.toca_janela(dict(hora, start=epoch(2026, 10, 18), end=epoch(2026, 10, 18, 1)), de, ate, SP)


# ------------------------------------------------------------------ utilitários


def test_hash_ignora_dtstamp():
    a = ler("basico.ics")
    b = a.replace(b"DTSTAMP:20261001T120000Z", b"DTSTAMP:20261002T235959Z")
    assert a != b and ical.hash_sem_dtstamp(a) == ical.hash_sem_dtstamp(b)
    c = a.replace(b"Evento em UTC", b"Evento em UTC!")
    assert ical.hash_sem_dtstamp(a) != ical.hash_sem_dtstamp(c)


def test_proximo_feriado_ate_60_dias():
    evs = ical.ordenar(ical.expandir(ler("feriados.ics"), "feriados", date(2026, 10, 1), date(2026, 12, 3), local_tz=SP))
    assert ical.proximo_feriado(evs, date(2026, 10, 2)) == {"data": "2026-10-12", "nome": "Feriado sintetico de outubro"}
    assert ical.proximo_feriado(evs, date(2026, 10, 13))["data"] == "2026-11-02"
    assert ical.proximo_feriado(evs, date(2026, 11, 3)) is None
