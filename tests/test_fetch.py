import httpx

from agenda_sync import fetch, sync

from conftest import ler

URL = "https://feeds.example.invalid/feed.ics"


def _transport(status, corpo, content_type="text/calendar"):
    return httpx.MockTransport(lambda req: httpx.Response(status, content=corpo, headers={"content-type": content_type}))


def test_ics_valido_ok():
    r = fetch.baixar(URL, transport=_transport(200, ler("basico.ics")))
    assert r.status == "ok" and r.http_status == 200 and r.corpo == ler("basico.ics") and r.bytes > 0


def test_ics_truncado_e_formato():
    r = fetch.baixar(URL, transport=_transport(200, ler("truncado.ics")))
    assert r.status == "formato" and r.corpo is None


def test_html_no_lugar_do_ics_e_offline():
    r = fetch.baixar(URL, transport=_transport(200, ler("portal.html"), "text/html; charset=utf-8"))
    assert r.status == "offline"
    # mesmo sem content-type correto, o HTML é reconhecido pelo corpo
    assert fetch.classificar(200, ler("portal.html"), "application/octet-stream") == "offline"


def test_404_vira_http404_com_erro_acionavel():
    r = fetch.baixar(URL, transport=_transport(404, b"<html>Error 404</html>", "text/html"))
    assert r.status == "http404" and r.http_status == 404
    msg = sync.mensagem_erro("http404", publica=False)
    assert "404" in msg and "regere o endereço secreto" in msg and "agenda-sync configurar" in msg


def test_401_e_500():
    assert fetch.baixar(URL, transport=_transport(401, b"")).status == "http401"
    assert fetch.baixar(URL, transport=_transport(503, b"")).status == "http503"
    assert "nova tentativa" in sync.mensagem_erro("http503", publica=False)


def test_portal_cativo_511_e_offline():
    assert fetch.classificar(511, b"<html></html>") == "offline"


def test_sem_rede_e_offline():
    def falha(req):
        raise httpx.ConnectError("sem rede", request=req)

    r = fetch.baixar(URL, transport=httpx.MockTransport(falha))
    assert r.status == "offline" and r.http_status is None


def test_timeout_e_offline():
    def lento(req):
        raise httpx.ReadTimeout("lento", request=req)

    assert fetch.baixar(URL, transport=httpx.MockTransport(lento)).status == "offline"


def test_bom_utf8_e_espacos_aceitos():
    corpo = b"\xef\xbb\xbf\r\n" + ler("basico.ics") + b"\r\n\r\n"
    assert fetch.classificar(200, corpo) == "ok"


def test_texto_qualquer_e_formato():
    assert fetch.classificar(200, b"ola mundo") == "formato"


def test_endereco_invalido_so_pelo_proprio_endereco():
    for ruim in ("nao-e-url", "webcal://feeds.example.invalid/x.ics", "https://", "https://[::1/x"):
        assert fetch.baixar(ruim).status == "endereco_invalido", ruim


def test_erro_ao_montar_o_cliente_e_offline_nao_credencial(monkeypatch):
    def quebra(*_a, **_k):
        raise ValueError("proxy que o httpx não entende")

    monkeypatch.setattr(fetch, "criar_cliente", quebra)
    assert fetch.baixar(URL).status == "offline"


def test_proxy_que_o_httpx_recusa_cai_para_conexao_direta(monkeypatch):
    for proxy in ("socks://127.0.0.1:1080", "lixo://x", "socks5://127.0.0.1:1080"):
        monkeypatch.setattr(fetch, "_proxy_para", lambda _u, p=proxy: p)
        with fetch.criar_cliente(URL, 5) as cliente:  # não levanta: monta sem proxy
            assert isinstance(cliente, httpx.Client)


def test_proxy_http_do_sistema_e_usado(monkeypatch):
    monkeypatch.setattr(fetch, "_proxy_para", lambda _u: "http://127.0.0.1:3128")
    with fetch.criar_cliente(URL, 5) as cliente:
        transporte = cliente._transport_for_url(httpx.URL(URL))
        assert transporte is not cliente._transport  # rota pelo proxy, não pela conexão direta


def test_cliente_real_usa_truststore_e_timeout(monkeypatch):
    monkeypatch.setattr(fetch, "_proxy_para", lambda _u: None)
    import truststore

    assert isinstance(fetch._ssl_ctx(), truststore.SSLContext)
    with fetch.criar_cliente(URL, 7) as cliente:
        assert cliente.timeout.read == 7 and cliente.timeout.connect == 7
