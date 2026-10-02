# Armadilhas

O que já mordeu (ou morde se ninguém avisar). Formato: **sintoma**, **causa**, **como evitar**.
Achou outra: acrescente aqui, no mesmo formato.

## Rainmeter

### Acento vira `Ã©` / `TAMBÃ‰M` no widget
- **Sintoma:** texto com acento aparece quebrado (mojibake).
- **Causa:** o Rainmeter lê `.ini`/`.inc` sem BOM como ANSI. UTF-8 sem BOM vira lixo.
- **Como evitar:** todo `.ini`/`.inc` em **UTF-16 LE com BOM**. O `.gitattributes` já
  converte na working tree (`working-tree-encoding=UTF-16LE-BOM`). A ferramenta Write grava
  UTF-8; depois de escrever, converta com
  `Get-Content -Raw -Encoding UTF8 x | Set-Content -Encoding Unicode x`. Lua pode ficar em
  UTF-8 sem BOM se só tiver ASCII.

### `; comentário` no fim da linha vira parte do valor
- **Sintoma:** uma URL, cor ou fórmula "funciona por acaso" ou quebra sem erro; no skin antigo,
  `GoogleCalendar2=...; <-- ADICIONE TAMBÉM`.
- **Causa:** no Rainmeter, `;` só é comentário **no início da linha**. No meio do valor é dado.
- **Como evitar:** comentário sempre em linha própria. O `migrar-do-ini` mantém o `;` colado
  ao valor e descarta só o que vem depois de um espaço.

### `UpdateRate` do WebParser "não bate" com os segundos
- **Sintoma:** feed baixado muito mais (ou menos) vezes do que o esperado.
- **Causa:** `UpdateRate` conta **ciclos de Update do skin**, não segundos. Com `Update=1000`,
  `UpdateRate=900` = 15 min; com `Update=500`, vira 7,5 min.
- **Como evitar:** calcular sempre `UpdateRate × Update`. No Horizonte o download é do
  `agenda_sync`; os widgets não usam WebParser para a agenda.

### Widget some no Win+D
- **Sintoma:** "Mostrar área de trabalho" esconde o widget.
- **Causa:** só `AlwaysOnTop=-2` (On Desktop) sobrevive ao Win+D; `0` (normal) é minimizado
  junto com as janelas.
- **Como evitar:** todo widget do pacote com `AlwaysOnTop=-2`, exceto o `Aviso` (`1`, por
  cima de tudo, por poucos segundos).

### Rodar `Rainmeter.exe !bang` com o Rainmeter fechado abre o Rainmeter
- **Sintoma:** o Rainmeter "se abre sozinho" depois de um sync.
- **Causa:** `Rainmeter.exe` com um bang na linha de comando inicia o app se ele não estiver
  rodando.
- **Como evitar:** `agenda_sync/windows.py` só manda o bang se a janela `DummyRainWClass` (ou o
  processo) existir. Bang para config descarregada é ignorado pelo próprio Rainmeter.

## Python no Windows

### `ZoneInfoNotFoundError` só no Windows
- **Sintoma:** `zoneinfo.ZoneInfo("America/Sao_Paulo")` falha; no Linux funciona.
- **Causa:** o Windows não tem a base IANA em disco; o `zoneinfo` depende do pacote `tzdata`.
- **Como evitar:** `tzdata` é dependência obrigatória no `pyproject.toml`. Não remover.

### Feed baixa no navegador mas o helper dá "offline" na rede da empresa
- **Sintoma:** `status=offline` só na rede corporativa.
- **Causa:** (a) o httpx usa o próprio pacote de certificados e não confia na CA que o proxy
  corporativo injeta; (b) o httpx só lê proxy de variável de ambiente, não do registro do
  Windows.
- **Como evitar:** `truststore` (certificados do Windows) e proxy por
  `urllib.request.getproxies()`/`proxy_bypass()` (leem o registro), em `agenda_sync/fetch.py`.
  Proxy por script PAC/WPAD **não** é coberto: se aparecer, é a próxima coisa a tratar.

### Proxy estranho no registro vira "rode agenda-sync configurar"
- **Sintoma:** todas as fontes em `sem_credencial` (ou `formato` com "veja o sync.log") logo
  depois de ligar uma VPN ou um proxy `socks`.
- **Causa:** o httpx recusa `socks://` com `ValueError` e `socks5://` sem o pacote `socksio`
  com `ImportError` ao **criar o cliente**; o `ValueError` caía no mesmo `except` do endereço
  inválido.
- **Como evitar:** só a validação do próprio endereço decide `endereco_invalido`
  (`fetch.baixar`); proxy que o httpx não aceita cai para conexão direta (`fetch.criar_cliente`).

### Evento da noite do último dia some da agenda
- **Sintoma:** um compromisso avulso às 22:30 do último dia da janela (ou um evento marcado em
  outro fuso) não aparece, embora esteja dentro da janela no fuso local.
- **Causa:** `recurring_ical_events.between(date, date)` compara as datas no fuso **de cada
  evento**. O Google exporta os avulsos em UTC (`Z`): 22:30 de Brasília é 01:30 do dia seguinte
  em UTC, fora do limite.
- **Como evitar:** `ical.expandir` pede 1 dia de folga para cada lado e corta exato no fuso
  local com `ical.toca_janela` (`tests/test_ical.py`, fixture `janela_fusos.ics`).

### Correção na expansão "não pega" na máquina real
- **Sintoma:** o código novo passa no pytest, mas o `agenda.json` real continua com o erro antigo
  até o dia seguinte.
- **Causa:** o cache `cache\<fonte>.eventos.json` é reaproveitado enquanto o feed (sem
  `DTSTAMP`) e a janela não mudam.
- **Como evitar:** a chave do cache leva `ical.VERSAO_EXPANSAO`; suba esse número a cada
  mudança no que `expandir` devolve.

### Feed sem `DTEND` dura zero minutos
- **Sintoma:** reunião sem hora de fim some da linha do dia (início = fim).
- **Causa:** pelo RFC 5545, `DTSTART` com hora e sem `DTEND`/`DURATION` dura zero; o
  `recurring-ical-events` segue o RFC e preenche `DTEND = DTSTART`.
- **Como evitar:** `ical.py` olha o componente original (`_indexar`) e, sem `DTEND` nem
  `DURATION`, aplica 1 h (com hora) ou 1 dia (dia inteiro).

### Todo sync reprocessa o feed inteiro
- **Sintoma:** CPU e regravação a cada ciclo mesmo sem nada novo na agenda.
- **Causa:** o Google muda o `DTSTAMP` de todos os eventos a cada download; comparar o corpo
  bruto sempre dá "mudou".
- **Como evitar:** hash do corpo **sem as linhas `DTSTAMP`** (`ical.hash_sem_dtstamp`).

### `PermissionError` ao gravar o `agenda.json`
- **Sintoma:** sync falha de vez em quando com acesso negado no `os.replace`.
- **Causa:** no Windows, trocar um arquivo que outro processo está lendo naquele instante é
  negado (o Rainmeter lendo o JSON).
- **Como evitar:** `contrato.escrever_atomico` repete até 10 vezes com espera crescente.

## Windows

### Na bateria a agenda nunca sincroniza
- **Sintoma:** no notebook fora da tomada o `lastOkAt` não anda.
- **Causa:** tarefa agendada nasce com "iniciar só na energia" e "parar se for para a
  bateria" ligados.
- **Como evitar:** na tarefa, `AllowStartIfOnBatteries`, `DontStopIfGoingOnBatteries` e
  `StartWhenAvailable` (este último recupera execuções perdidas no sono).

### Defender mata o script como trojan
- **Sintoma:** o instalador ou a tarefa somem com alerta de ameaça.
- **Causa:** `powershell -WindowStyle Hidden -ExecutionPolicy Bypass` lançado de dentro de
  outro PowerShell é a assinatura clássica de malware.
- **Como evitar:** rodar scripts com `powershell -NoProfile -File x.ps1` em primeiro plano.
  Para não piscar console, o próprio Python usa `CREATE_NO_WINDOW` nos subprocessos.

### Pela tarefa dá `sem_credencial`, à mão funciona
- **Sintoma:** `agenda-sync sync` no terminal traz as 3 fontes `ok`; rodando pela tarefa,
  `pessoal` e `corporativo` voltam `sem_credencial`.
- **Causa:** o Gerenciador de Credenciais é por sessão de logon do usuário (DPAPI). Tarefa
  registrada como S4U ("executar estando o usuário conectado ou não") ou conta de serviço não
  enxerga as credenciais.
- **Como evitar:** o `instalar.ps1` registra com o usuário atual, `-LogonType Interactive`.

### "A tarefa rodou mas o `generatedAt` não mudou"
- **Sintoma:** `Start-ScheduledTask` termina com `LastTaskResult` 0, mas o `generatedAt` do
  `agenda.json` (e o mtime do arquivo) continuam velhos.
- **Causa:** de propósito: o JSON só é regravado quando o conteúdo muda, e o `generatedAt`
  marca a última mudança. Isso evita acordar o Rainmeter a cada 10 min à toa.
- **Como evitar:** para saber se o ciclo rodou, olhe a linha `ciclo` no `sync.log` ou o
  `lastAttemptAt` em `cache\estado.json`. Para forçar a regravação num teste, renomeie o
  `agenda.json` antes de disparar.

### `.ps1` com acento vira lixo no Windows PowerShell 5.1
- **Sintoma:** mensagens do `instalar.ps1` com `Ã£` no lugar de `ã`, ou erro de parse numa
  string com acento.
- **Causa:** o PowerShell 5.1 lê `.ps1` sem BOM como ANSI; a ferramenta Write grava UTF-8 sem BOM.
- **Como evitar:** `.ps1` em **UTF-8 com BOM**. Depois de escrever:
  `Get-Content -Raw -Encoding UTF8 x | Set-Content -Encoding UTF8 -NoNewline x` (no 5.1,
  `UTF8` grava com BOM).

### Repetição "para sempre" da tarefa falha ao registrar
- **Sintoma:** `New-ScheduledTaskTrigger ... -RepetitionDuration ([TimeSpan]::MaxValue)` dá
  "O XML da tarefa contém um valor formatado incorretamente ou fora do intervalo"
  (`Duration:P99999999DT23H59M59S`; reproduzido em 02/10/2026).
- **Causa:** o Agendador não aceita a duração máxima do .NET como "indefinido".
- **Como evitar:** omitir `-RepetitionDuration`; no Windows 10/11 a repetição fica sem fim
  (`Repetition.Duration` vazio, conferido no `instalar.ps1`).

## Repositório público

### Varredor de segredos barra a URL dos feriados
- **Sintoma:** `tools/varrer-segredos.sh` acusa o padrão de endereço iCal do Google
  (`.../calendar/ical/...`) num arquivo de código ou doc, inclusive nesta própria página se
  alguém escrever o domínio inteiro.
- **Causa:** até a agenda **pública** de feriados tem o formato de URL das agendas secretas; o
  varredor não sabe a diferença (e não deve saber).
- **Como evitar:** nenhuma URL de calendário no repo, nem a pública. O padrão do `config.toml`
  nasce com `url = ""`; quem preenche é o `migrar-do-ini` ou a pessoa, no arquivo local.
  Teste usa domínio reservado `.invalid` e `example.org`.

### Fixture `.ini` versionada não testa o arquivo real
- **Sintoma:** o teste de `migrar-do-ini` passa, mas a migração do skin real falha (ou o
  contrário).
- **Causa:** o `.gitattributes` converte `*.ini` para UTF-16 LE com BOM na working tree; o
  skin antigo real é UTF-8 sem BOM. Uma fixture `.ini` commitada nunca seria UTF-8.
- **Como evitar:** os testes geram o `.ini` em `tmp_path`, nas quatro codificações
  (`tests/test_cli.py`).
