"""Integração com o Windows: preferência de animação e aviso aos widgets do Rainmeter."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SPI_GETCLIENTAREAANIMATION = 0x1042
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)


def animacoes_ligadas() -> bool:
    """'Efeitos de animação' do Windows (Acessibilidade > Efeitos visuais). Fora do Windows: True."""
    if sys.platform != "win32":
        return True
    try:
        import ctypes

        valor = ctypes.c_int(1)
        ok = ctypes.windll.user32.SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, ctypes.byref(valor), 0)
        return bool(valor.value) if ok else True
    except Exception:  # noqa: BLE001
        return True


def rainmeter_rodando() -> bool:
    """Evita que o bang abra o Rainmeter quando ele está fechado (Rainmeter.exe com bang inicia o app)."""
    if sys.platform != "win32":
        return False
    try:
        import ctypes

        # janela principal do Rainmeter
        if ctypes.windll.user32.FindWindowW("DummyRainWClass", None):
            return True
    except Exception:  # noqa: BLE001
        pass
    try:
        saida = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq Rainmeter.exe", "/NH"],
            capture_output=True,
            text=True,
            timeout=10,
            creationflags=CREATE_NO_WINDOW,
        ).stdout
        return "rainmeter.exe" in saida.lower()
    except Exception:  # noqa: BLE001
        return False


def avisar_widgets(rainmeter_exe: str, configs: list[str]) -> int:
    """Manda !CommandMeasure mLeitor "Recarregar()" a cada config. Devolve quantos bangs saíram."""
    exe = Path(rainmeter_exe)
    if not exe.exists() or not rainmeter_rodando():
        return 0
    enviados = 0
    for cfg in configs:
        try:
            subprocess.run(
                f'"{exe}" !CommandMeasure mLeitor "Recarregar()" "{cfg}"',
                timeout=10,
                creationflags=CREATE_NO_WINDOW,
                check=False,
            )
            enviados += 1
        except Exception:  # noqa: BLE001 - Rainmeter fechado ou travado: o widget relê no próximo ciclo
            continue
    return enviados
