"""Download de um feed iCal com classificação do resultado.

Rede: httpx + truststore (certificados do Windows, inclusive a CA da rede corporativa) e o
proxy do sistema lido do registro pelo urllib (o httpx sozinho só olha variáveis de ambiente).
Nunca registra nem devolve a URL: quem chama só recebe status, bytes e corpo.
"""

from __future__ import annotations

import re
import ssl
import time
import urllib.request
from dataclasses import dataclass
from urllib.parse import urlsplit

import httpx

from agenda_sync import __version__

_HTML = re.compile(rb"<\s*(!doctype\s+html|html|head|body)\b", re.IGNORECASE)


@dataclass
class Resultado:
    status: str  # ok | offline | formato | httpNNN | endereco_invalido (vira sem_credencial no contrato)
    http_status: int | None
    corpo: bytes | None  # só quando status == "ok"
    bytes: int
    ms: int


def _proxy_para(url: str) -> str | None:
    """Proxy do sistema (registro do Windows / variáveis de ambiente) para esta URL, respeitando exceções."""
    try:
        host = urlsplit(url).hostname or ""
        if host and urllib.request.proxy_bypass(host):
            return None
        proxies = urllib.request.getproxies()
        return proxies.get("https") or proxies.get("all") or proxies.get("http")
    except Exception:  # noqa: BLE001 - sem proxy legível = conexão direta
        return None


def _ssl_ctx() -> ssl.SSLContext | bool:
    try:
        import truststore

        return truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    except Exception:  # noqa: BLE001 - fallback para o certifi do httpx
        return True


def criar_cliente(url: str, timeout: float, transport: httpx.BaseTransport | None = None) -> httpx.Client:
    kwargs: dict = {
        "timeout": timeout,
        "follow_redirects": True,
        "headers": {"User-Agent": f"agenda_sync/{__version__}"},
        "trust_env": False,  # proxy vem de _proxy_para (que já cobre as variáveis de ambiente)
    }
    if transport is not None:
        kwargs["transport"] = transport
        return httpx.Client(**kwargs)
    kwargs["verify"] = _ssl_ctx()
    proxy = _proxy_para(url)
    if proxy:
        try:
            return httpx.Client(**kwargs, proxy=proxy)
        except (ValueError, ImportError, httpx.InvalidURL):
            # proxy do sistema que o httpx não entende (socks://, socks5 sem socksio, lixo no registro):
            # tenta direto em vez de culpar o endereço da agenda (docs/ARMADILHAS.md)
            pass
    return httpx.Client(**kwargs)


def classificar(http_status: int, corpo: bytes, content_type: str = "") -> str:
    """ok | offline | formato | httpNNN para uma resposta HTTP recebida."""
    if http_status == 511:  # Network Authentication Required: portal cativo declarado
        return "offline"
    if http_status != 200:
        return f"http{http_status}"
    inicio = corpo.lstrip(b"\xef\xbb\xbf \t\r\n")[:2048]
    if inicio.upper().startswith(b"BEGIN:VCALENDAR"):
        fim = corpo.rstrip(b" \t\r\n")[-64:].upper()
        return "ok" if fim.endswith(b"END:VCALENDAR") else "formato"
    if "html" in content_type.lower() or _HTML.search(inicio):
        return "offline"  # 200 com HTML = portal cativo / proxy pedindo login
    return "formato"


def baixar(url: str, timeout: float = 20.0, transport: httpx.BaseTransport | None = None) -> Resultado:
    t0 = time.monotonic()
    # Só o endereço em si decide "endereco_invalido" (vira sem_credencial: "rode configurar").
    # Erro de proxy, rede ou redirect nunca cai aqui.
    try:
        partes = urlsplit(url)
        httpx.URL(url)
        valido = partes.scheme in ("http", "https") and bool(partes.hostname)
    except (httpx.InvalidURL, ValueError):
        valido = False
    if not valido:
        return Resultado("endereco_invalido", None, None, 0, 0)
    try:
        with criar_cliente(url, timeout, transport) as cliente:
            r = cliente.get(url)
            corpo = r.content
            status = classificar(r.status_code, corpo, r.headers.get("content-type", ""))
            ms = int((time.monotonic() - t0) * 1000)
            return Resultado(status, r.status_code, corpo if status == "ok" else None, len(corpo), ms)
    except (httpx.HTTPError, httpx.InvalidURL, ssl.SSLError, OSError, ValueError):
        # sem rede, DNS, timeout, TLS interceptado sem CA conhecida, redirect para lugar estranho: "offline"
        ms = int((time.monotonic() - t0) * 1000)
        return Resultado("offline", None, None, 0, ms)
