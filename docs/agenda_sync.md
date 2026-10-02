# agenda_sync: o helper da agenda

Programa em Python que baixa os feeds iCal das agendas Google, expande os eventos recorrentes e
grava o [`agenda.json`](CONTRATOS.md) que os widgets leem. Não fica rodando: cada execução faz
um ciclo e sai. Quem chama é a tarefa agendada `\Horizonte\AgendaSync` ou você.

## Instalar (uso diário)

Na raiz do repo, numa janela do PowerShell, com [uv](https://docs.astral.sh/uv/) no PATH:

```powershell
powershell -NoProfile -File instalar.ps1
```

1. `uv sync` cria ou atualiza o `.venv` do repo.
2. Registra a tarefa `\Horizonte\AgendaSync`. Rodar de novo substitui a tarefa.
3. Dispara o primeiro ciclo. `-SemDisparar` pula esse passo.

`-ComSkin` também liga `skin\` na pasta de skins do Rainmeter por junction (fase 2; sem `skin\`
no repo, não faz nada). A pasta de skins vem do `SkinPath` do `Rainmeter.ini`, com
`Documents\Rainmeter\Skins` como reserva. Se a junction falhar, a skin é copiada. Pasta
`Horizonte` de verdade já existente em Skins nunca é sobrescrita.

O instalador **não** grava credenciais: faça a [primeira configuração](#primeira-configuração)
antes ou depois, tanto faz.

### A tarefa agendada

| item | valor | por quê |
| --- | --- | --- |
| ação | `.venv\Scripts\pythonw.exe -m agenda_sync sync`, pasta = repo | `pythonw` não abre janela de console |
| gatilhos | logon; a cada 10 min sem fim; volta do sono (`Power-Troubleshooter` ID 1, atraso 1 min); rede conectada (`NetworkProfile/Operational` ID 10000, atraso 15 s) | o atraso dá tempo de a rede subir; sem ele o 1º ciclo pós-sono sai `offline` |
| bateria | `AllowStartIfOnBatteries` + `DontStopIfGoingOnBatteries` | o padrão do Windows **nunca** roda na bateria |
| perdeu o horário | `StartWhenAvailable` | PC desligado na hora: roda assim que der |
| sobreposição | `MultipleInstances IgnoreNew` (e o `sync.lock`) | logon e rede disparando juntos |
| limite | 2 min | 3 downloads de até 20 s cada e a expansão cabem com folga |
| conta | usuário atual, `Interactive`, `Limited` | só a sessão do usuário enxerga o Gerenciador de Credenciais |

### Desinstalar

```powershell
powershell -NoProfile -File desinstalar.ps1         # tarefa e junction; dados e credenciais ficam
powershell -NoProfile -File desinstalar.ps1 -Tudo   # também credenciais e %LOCALAPPDATA%\Horizonte
```

- `-Tudo` apaga as credenciais pela mesma biblioteca que as gravou (`keyring`).
- Os arquivos do helper saem de `%LOCALAPPDATA%\Horizonte`; subpastas que não são dele ficam.
- A junction da skin sai sem tocar no repo. Uma cópia (pasta de verdade) não é apagada.
- O `.venv` fica no repo; apague à mão se quiser.

## Desenvolvimento

Na raiz do repo, com [uv](https://docs.astral.sh/uv/) e Python 3.14:

```powershell
uv sync                 # cria .venv com as dependências
uv run pytest           # testes (só fixtures sintéticas, sem rede, sem keyring)
uv run agenda-sync --help
```

`python -m agenda_sync <comando>` funciona igual dentro do venv.

## Primeira configuração

Quem vem do skin antigo `GoogleCalendar` migra sem digitar nada:

```powershell
uv run agenda-sync migrar-do-ini "%USERPROFILE%\Documents\Rainmeter\Skins\GoogleCalendar\Gcalendar.ini"
```

- `GoogleCalendar1` vira `pessoal` e `GoogleCalendar2` vira `corporativo`: vão para o
  **Gerenciador de Credenciais do Windows** (serviço `Horizonte`, usuário = apelido).
- `GoogleCalendar3` (feriados, pública) vai para o `config.toml`.
- Lê `.ini` em UTF-8 ou UTF-16, com ou sem BOM. Não imprime endereço: só
  `pessoal: gravada (N caracteres)`.

Sem o skin antigo, ou para trocar um endereço regerado:

```powershell
uv run agenda-sync configurar
```

Pede o endereço secreto de `pessoal` e `corporativo` sem mostrar o que você cola. Enter vazio
mantém o que já está gravado. O endereço dos feriados vai à mão no `config.toml` (campo `url`
da fonte `feriados`): o modelo está em [`config.example.toml`](../config.example.toml).

## Comandos

| comando | faz |
| --- | --- |
| `sync` | um ciclo: baixa cada fonte, expande, grava o `agenda.json` se mudou e avisa os widgets |
| `configurar` | grava os endereços secretos no Gerenciador de Credenciais (entrada oculta) |
| `migrar-do-ini <ini>` | copia os endereços do skin antigo, sem imprimir |
| `status` | status por fonte, idade do `agenda.json` e contagem de eventos (sem títulos) |
| `entrar` | abre o link da reunião em andamento, ou da próxima em até 30 min; senão abre o dia no Google Agenda |

## Onde mora cada coisa (tudo fora do repo)

| caminho | o quê |
| --- | --- |
| `%LOCALAPPDATA%\Horizonte\config.toml` | fontes, cores, janela, intervalos. Criado com o padrão na 1ª execução |
| `%LOCALAPPDATA%\Horizonte\agenda.json` | a saída ([contrato](CONTRATOS.md)) |
| `%LOCALAPPDATA%\Horizonte\cache\<fonte>.ics` | último download válido de cada fonte (base do modo offline) |
| `%LOCALAPPDATA%\Horizonte\cache\<fonte>.eventos.json` | expansão já feita, reaproveitada enquanto o feed e a janela não mudam |
| `%LOCALAPPDATA%\Horizonte\cache\estado.json` | status, `lastOkAt`, hash por fonte |
| `%LOCALAPPDATA%\Horizonte\sync.log` | log rotativo (128 KB + 1 backup), sem URL e sem título |
| Gerenciador de Credenciais, `Horizonte` / `pessoal`, `corporativo` | os endereços secretos |

`HORIZONTE_DIR` troca a pasta inteira (os testes usam isso).

## `config.toml`

| chave | padrão | sentido |
| --- | --- | --- |
| `contaIndice` | 0 | o `<n>` de `calendar.google.com/calendar/u/<n>` no `entrar` sem reunião |
| `fontes[].contaIndice` | 0 | o mesmo, para o `link` dos eventos daquela fonte (a agenda corporativa costuma ser a conta 1) |
| `intervaloFeriadosH` | 168 | a fonte `feriados` só baixa de novo depois disso (semanal: roadmap § 4, "Cadência dos feriados") |
| `janelaDias` | 15 | janela = ontem até hoje + N |
| `timeoutS` | 20 | timeout do download |
| `rainmeterExe` | `C:\Program Files\Rainmeter\Rainmeter.exe` | para avisar os widgets |
| `widgets` | Dia, Agenda, Relogio | configs que recebem o `Recarregar()` |
| `fontes[].nome`, `.cor` | Pessoal `#7AA2F7`, Corporativo `#C3A6FF`, Feriados `#5FD0B5` | vão para `sources[]` no JSON |

## Como um ciclo funciona

1. **Credencial.** `pessoal` e `corporativo` vêm do keyring; `feriados`, do `config.toml`.
   Faltou: status `sem_credencial`, com o comando que resolve no `erro`.
2. **Download.** httpx com timeout de 20 s, certificados do Windows (truststore, cobre a CA da
   rede corporativa) e o proxy do sistema (lido do registro, com as exceções; proxy que o httpx
   não entende, como `socks://`, cai para conexão direta). Feriados: no máximo 1 download por
   semana (`intervaloFeriadosH`).
3. **Classificação.**

   | resposta | status |
   | --- | --- |
   | 200 com `BEGIN:VCALENDAR` e `END:VCALENDAR` | `ok` |
   | 200 com `BEGIN:VCALENDAR` sem o fim (download cortado) | `formato` |
   | 200 com HTML (portal cativo de hotel/aeroporto), 511, sem rede, timeout | `offline` |
   | 404, 401, 403, 410 | `http404` etc., com "regere o endereço secreto e rode agenda-sync configurar" |
   | outro código | `httpNNN`, "nova tentativa no próximo ciclo" |

4. **Hash sem `DTSTAMP`.** O Google muda o `DTSTAMP` a cada download; sem ele, o hash só muda
   quando a agenda muda. Mesmo hash, mesma janela e mesma `VERSAO_EXPANSAO` (em `ical.py`; suba
   a cada mudança no que a expansão devolve): reaproveita a expansão do cache.
5. **Expansão** com `recurring-ical-events` (RRULE, RDATE, EXDATE, RECURRENCE-ID), fusos pelo
   `zoneinfo` + `tzdata`, filtro de `STATUS:CANCELLED`, limpeza de e-mail e URL.
6. **Falha** (rede, HTTP, feed que não parseia, erro inesperado) mantém os eventos do último
   download bom daquela fonte; só o status muda. `lastOkAt` só anda quando o feed baixou **e**
   expandiu.
7. **Gravação** atômica, só se o conteúdo mudou; aí avisa os widgets (sem abrir janela de
   console e sem abrir o Rainmeter se ele estiver fechado).

Duas execuções ao mesmo tempo (logon e rede disparando juntos): a segunda vê a trava
`sync.lock` e sai sem fazer nada.

## Diagnóstico

```powershell
uv run agenda-sync status
Get-Content "$env:LOCALAPPDATA\Horizonte\sync.log" -Tail 20
Get-ScheduledTaskInfo -TaskPath '\Horizonte\' -TaskName AgendaSync   # LastRunTime, LastTaskResult (0 = ok)
Start-ScheduledTask   -TaskPath '\Horizonte\' -TaskName AgendaSync   # roda um ciclo agora
```

Cada linha do log: `fonte=<id> status=<s> http=<código> baixou=<sim/não> bytes=<n> vevents=<n> eventos=<n> ms=<n>`.
Cada ciclo fecha com `ciclo eventos=<n> gravou=<True/False> avisos=<n> ms=<n>`.

| sintoma | onde olhar |
| --- | --- |
| `generatedAt` parado há horas | normal se a agenda não mudou: ele marca a última **mudança de conteúdo**. Vivo = linha `ciclo` recente no log e `lastAttemptAt` em `cache\estado.json` |
| nenhuma linha nova no log | `LastTaskResult` da tarefa; `267011` = nunca rodou, `267014` = foi interrompida (limite de 2 min ou parada à mão) |
| `sem_credencial` só pela tarefa (à mão funciona) | a tarefa precisa rodar como o usuário, logon `Interactive`; reinstale com `instalar.ps1` |
| recorrência suspeita (série faltando ou sobrando) | `uv run python tools/prova_recorrencia.py pessoal`: expande o feed real com `dateutil` à parte e compara com o `agenda.json`, só com contagens |
| `offline` só depois de acordar o PC | normal no 1º minuto; o gatilho de volta do sono espera 1 min e o de rede, 15 s |

Armadilhas conhecidas: [ARMADILHAS.md](ARMADILHAS.md).
