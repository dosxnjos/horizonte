# Armadilhas

O que já mordeu (ou morde se ninguém avisar). Formato: **sintoma**, **causa**, **como evitar**.
Achou outra: acrescente aqui, no mesmo formato.

## Rainmeter

### Caixa "Rainmeter.ini não pôde ser salvo" aparece na tela do usuário
- **Sintoma:** abre um diálogo modal de erro na tela do usuário. O "caminho do arquivo"
  que ele mostra é uma lista de bangs, por exemplo
  `[!SetVariable X "..." "Horizonte\Relogio"][!CommandMeasure ...]Rainmeter.ini`. O
  processo `Rainmeter.exe` que o chamou fica pendurado. Aconteceu em 02/10/2026, durante a
  Fase 2.
- **Causa:** pela **linha de comando**, o `Rainmeter.exe` só aceita bang no formato
  `!Bang arg1 arg2`. A sintaxe com colchetes `[!Bang ...][!Bang ...]` vale só dentro de
  skin (Actions). Na linha de comando, o primeiro argumento que não começa com `!` é lido
  como **caminho de settings**: sobe uma segunda instância que tenta salvar um
  `Rainmeter.ini` nesse "caminho" e mostra o diálogo.
- **Como evitar:**
  - pela linha de comando, um bang por chamada, sem colchetes. Exemplo:
    `& "C:\Program Files\Rainmeter\Rainmeter.exe" !SetVariable DebugAgenda "C:\x.json" "Horizonte\Relogio"`;
  - para vários bangs, faça várias chamadas;
  - se o diálogo já apareceu, mate só o processo extra (aquele cujo CommandLine começa
    com `[`), nunca a instância principal.

### Caixa "Não foi possível recarregar a skin ...: Arquivo não encontrado"
- **Sintoma:** aparece um diálogo modal na tela do usuário com o nome de uma config de
  teste (aconteceu com `Horizonte\_TesteCpu` em 02/10/2026).
- **Causa:** a pasta ou o `.ini` da config foi apagado enquanto ela ainda estava ativa, ou
  antes de um `!Refresh`/`!RefreshApp`. A instância principal tenta recarregar e mostra o
  erro.
- **Como evitar:**
  - config de teste vai **fora** de `skin\`, por exemplo em `temp\`, com junction própria;
  - ordem ao terminar: `!DeactivateConfig "<config>"` primeiro, conferir `Active=0` no
    `Rainmeter.ini`, e **só depois** apagar a pasta;
  - nunca apagar uma pasta de skin com o Rainmeter apontando para ela.

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

### Módulo Lua em UTF-16 dá erro de sintaxe no `dofile`
- **Sintoma:** `dofile('comum.lua')` falha com erro de sintaxe na linha 1 (ou o acento sai
  mojibake se o módulo estiver em UTF-8 e for lido como ANSI).
- **Causa:** só o `ScriptFile` do measure é lido pelo Rainmeter (que entende UTF-16 LE com BOM). O
  `dofile`/`loadfile` do Lua 5.1 lê bytes crus: o BOM `FF FE` e os zeros do UTF-16 não são Lua.
- **Como evitar:** módulos do `@Resources\Lua` passam por `carregar.lua` (ASCII, por `dofile`), que
  decodifica UTF-16 e chama `loadstring`. Só `json.lua` e `carregar.lua` ficam ASCII.
  [widgets.md § Base](widgets.md#base-skinresources).

### `SKIN` é `nil` dentro do módulo carregado
- **Sintoma:** `attempt to index global 'SKIN' (a nil value)` na primeira linha do módulo que usa
  `SKIN`, embora o script do widget use `SKIN` normalmente.
- **Causa:** o Rainmeter põe `SKIN` no ambiente próprio do script do widget, não no `_G`. Um chunk
  de `loadstring`/`dofile` nasce com o `_G`.
- **Como evitar:** `carregar.lua` faz `setfenv(fn, getfenv(2))`: o módulo herda o ambiente de quem
  chamou. Não carregar módulo que usa `SKIN` por `dofile` direto.

### Chip (ou qualquer meter) medido com largura zero
- **Sintoma:** o fundo do chip sai com ~24 px, só o padding, embora o texto apareça inteiro.
- **Causa:** `SKIN:GetMeter(x):GetW()` devolve **0 para meter oculto** (`Hidden=1`), mesmo depois
  de `!UpdateMeter`.
- **Como evitar:** `!ShowMeter` antes de `!UpdateMeter` e `GetW()`; esconder só depois, se for o
  caso.

### Measure Script parou de rodar com `DefaultUpdateDivider=-1`
- **Sintoma:** o `Update()` do Lua não é chamado; a hora não vira.
- **Causa:** `DefaultUpdateDivider` no `[Rainmeter]` vale para meters **e measures**.
- **Como evitar:** o measure Script que precisa do tick leva `UpdateDivider=1` explícito. Os
  meters ficam em `-1` e o Lua manda `!UpdateMeter`/`!Redraw` só quando algo muda (parado = zero
  redesenho).

### `Edit` em arquivo UTF-16 do skin quebra o arquivo
- **Sintoma:** depois de editar um `.ini`/`.inc`/`.lua` do `skin\` com uma ferramenta que grava
  UTF-8, o Rainmeter mostra mojibake ou o Lua não carrega.
- **Causa:** a working tree desses arquivos é UTF-16 LE com BOM; ferramentas de texto costumam ler
  ou gravar UTF-8.
- **Como evitar:** editar, depois rodar `powershell -NoProfile -File tools\skin-utf16.ps1`
  (converte para UTF-16 o que estiver sem BOM, idempotente; pula `json.lua` e `carregar.lua`).
  Observado em 02/10 (widget Dia): o `Edit` do Claude Code preservou o UTF-16 LE com BOM do
  `Dia.lua`; o `Write` grava UTF-8 em arquivo novo, mas sobre um UTF-16 existente gravou UTF-16 sem
  BOM (03/10, [abaixo](#write-num-arquivo-utf-16-seguido-do-skin-utf16ps1-duplica-os-zeros)). Rodar o
  script depois de qualquer um dos dois não custa nada.

### Widget novo não aparece com `!ActivateConfig`
- **Sintoma:** `!ActivateConfig Horizonte\Dia Dia.ini` não faz nada; a seção não entra no
  `Rainmeter.ini`.
- **Causa:** o Rainmeter só enxerga pastas de config novas (mesmo dentro da junction) depois de
  reler a árvore de skins.
- **Como evitar:** `!RefreshApp` (ou `instalar.ps1 -ComSkin -SemDisparar`) depois de criar a pasta
  do widget, e só então `!ActivateConfig`.

### Texto colado ao vizinho ("termina15:30")
- **Sintoma:** dois Strings postos lado a lado pelo Lua (`X` = X do anterior + `GetW()`) ficam
  sem o espaço que terminava o primeiro texto.
- **Causa:** `GetW()` do meter String não conta o espaço em branco do fim.
- **Como evitar:** somar a largura de um espaço quando o texto termina em `' '` (o `Dia.lua` soma
  4 px a 14 px), ou levar o espaço para o começo do texto seguinte.

### Container "some" com o próprio desenho
- **Sintoma:** um Shape usado como `Container=` de outro meter não aparece mais na tela.
- **Causa:** o meter que serve de Container vira só máscara: o Rainmeter não o desenha.
- **Como evitar:** máscara num Shape à parte, com a mesma geometria (no Dia: `BotaoMasc` recorta o
  rótulo "Entrar" e o `Botao` desenha a pílula).

### Tooltip de uma linha aparece em cima de outra
- **Sintoma:** passando o mouse numa linha da Agenda, o tooltip mostra o título de outro evento (02/10).
- **Causa:** o Shape tinha `X=0`, `Y=0` e desenhava a forma lá embaixo, em coordenadas absolutas. O
  retângulo do meter vai da origem até a borda da forma, e o `ToolTipText` vale para esse retângulo
  inteiro: o tooltip do slot de baixo cobria todas as linhas de cima. O hover (`MouseOverAction`)
  não sofre, porque usa a forma.
- **Como evitar:** Shape com tooltip ou clique fica **na posição dele** (`X`/`Y` do meter) e desenha
  em coordenadas locais (`Rectangle 0,0,w,h`). Vale para pontos, botões e linhas.

### GPU Engine pesa mesmo lido a cada 5 s
- **Sintoma:** com a Máquina carregada e nada mudando na tela, o `Rainmeter.exe` gasta ~3,5 pontos de
  um núcleo a mais e ~10 MB a mais de RAM (02/10).
- **Causa:** `UsageMonitor` com `Alias=GPU` consulta a categoria "GPU Engine" (centenas de
  instâncias) numa thread própria enquanto o measure estiver configurado para ela. Ler o measure
  menos vezes (`!UpdateMeasure` a cada 5 s) não muda nada.
- **Como evitar:** o measure fica apontado para um contador barato (`Processor Information`) e o Lua
  troca para `Alias=GPU` por `!SetOption` só durante uma amostra de 2 s a cada 10 s
  (`Maquina.lua`, `gpuCaro`/`amostrarGpu`). Medido: parado volta a ficar no ruído.

### UsageMonitor custa CPU com o measure desligado
- **Sintoma:** os measures do "processo mais pesado" (`Alias=CPU`/`RAM`, categoria Process) custam
  ~2 pontos de um núcleo mesmo com `Disabled=1` (02/10).
- **Causa:** a mesma da GPU: a thread do plugin consulta toda categoria configurada, ligada ou não.
- **Como evitar:** em repouso o measure aponta para o contador do `mCpu`; o hover troca para o alias
  e a saída do mouse volta e manda um `!UpdateMeasure` com as opções de repouso antes do
  `!DisableMeasure` (`topLigar`/`topDesligar`).

### CPU do processo dividida duas vezes
- **Sintoma:** o hover mostraria "powershell 0,5%" para um laço que ocupa um núcleo inteiro.
- **Causa:** o `UsageMonitor` (`Alias=CPU`) já entrega o "% Processor Time" do processo dividido
  pelos núcleos lógicos: um núcleo inteiro de 14 = 7 % (medido em 02/10, igual ao Gerenciador).
- **Como evitar:** não dividir pelo nº de threads no Lua.

### Log cheio de "'ActionList1' is currently running"
- **Sintoma:** o `Rainmeter.log` ganha um aviso por troca de valor quando vários anéis animam juntos.
- **Causa:** `!CommandMeasure mAT "Execute 1"` com a lista já rodando é ignorado com aviso.
- **Como evitar:** o Lua guarda se a lista está rodando e só manda `Execute` quando não está
  (`ligarTimer` no `Maquina.lua`). Com isso, uma lista com `Repeat` finito pode acabar sozinha com
  animação pela metade: use um teto alto (`Repeat Passo, 30, 1000`), `Stop 1` quando ninguém anima e
  um vigia no `Update()` que religa.

### `!WriteKeyValue` pela linha de comando dá "Illegal path"
- **Sintoma:** `Rainmeter.exe !WriteKeyValue Variables X 1 "C:\Dev\horizonte\skin\@Resources\Local.inc"`
  não grava nada; com `Logging=1`, o log diz `!WriteKeyValue: Illegal path`.
- **Causa:** o Rainmeter só escreve em arquivos dentro da pasta de skins ou de settings, e o caminho
  real do repo (o alvo da junction) não está nela.
- **Como evitar:** dentro do skin, `#@#Local.inc` (resolve para `Documents\Rainmeter\Skins\...`);
  fora, editar o arquivo direto (ele é local e não versionado). O caminho pela junction
  (`Documents\Rainmeter\Skins\Horizonte\...`) deve passar, mas não foi testado.

### Argumento vazio some no caminho do PowerShell
- **Sintoma:** `& Rainmeter.exe '!SetVariable' 'DebugSnapshot' '' 'Horizonte\Claude'` não volta o widget
  ao arquivo real; o `widget.log` diz "arquivo ausente" logo depois (03/10, widget Claude).
- **Causa:** o Windows PowerShell 5.1 descarta argumento string vazio ao chamar programa nativo: o bang
  chega como `!SetVariable DebugSnapshot Horizonte\Claude` e a variável vira o nome da config.
- **Como evitar:** para zerar uma variável de depuração, `!Refresh` da config (o `!SetVariable` não
  sobrevive a ele); ou passar `'""'`. Leitor com último estado bom segura a tela enquanto isso.

### Bang pelo Git Bash com `\$var` no nome da config
- **Sintoma:** `!ZPos`/`!Refresh` "não fazem nada"; com `Logging=1` aparece `Skin "Horizonte$c" does
  not exist` (03/10).
- **Causa:** aspas e barras invertidas atravessam duas camadas (bash e PowerShell); `"Horizonte\\$c"`
  dentro de um `powershell -Command "..."` chega com o `$` ou a barra errados.
- **Como evitar:** loop de bangs num `.ps1` (`"Horizonte\$c"` com o `$c` do próprio PowerShell), ou um
  bang por chamada com o nome da config escrito por inteiro.
- **Também sem PowerShell no meio** (03/10, revisão): um `for c in ...; "$RM" '!Refresh' "Horizonte\\$c"`
  direto no Git Bash não deu erro nenhum e não recarregou nada; o widget seguiu com o Lua antigo e o
  teste parecia "falhar". Confira o efeito (captura ou `widget.log`), nunca só a ausência de erro.

### `Get-Process Rainmeter` devolve dois processos
- **Sintoma:** um script de medição quebra com `[System.Object[]] não contém um método denominado
  'op_Subtraction'` logo depois de mandar um bang (03/10, revisão).
- **Causa:** cada `Rainmeter.exe !Bang` da linha de comando sobe um processo efêmero que entrega o
  bang à instância principal e sai. Por uns instantes há dois `Rainmeter.exe`; o efêmero não é o
  diálogo de erro (esse fica pendurado, com o CommandLine começando por `[`).
- **Como evitar:** medir o **mais antigo** (`Get-Process Rainmeter | Sort-Object StartTime |
  Select-Object -First 1`) ou esperar uns segundos depois do último bang.

### `Write` num arquivo UTF-16 seguido do `skin-utf16.ps1` duplica os zeros
- **Sintoma:** uma variável do `Local.inc` "não pega" (`MaxItems=6` e a Agenda seguiu com 8 itens,
  03/10, integração). O arquivo começa com `FF FE 5B 00 00 00 56 00`: cada letra virou letra + 3 zeros.
  Os apelidos das contas Claude e o `Privado` voltariam ao padrão no próximo refresh.
- **Causa:** a ferramenta `Write` do Claude Code, sobrescrevendo um arquivo que **já era** UTF-16 LE,
  gravou UTF-16 LE **sem BOM**. O `skin-utf16.ps1` de então só olhava o BOM, leu os bytes como UTF-8 e
  reencodou: UTF-16 dentro de UTF-16.
- **Como evitar:** o `skin-utf16.ps1` agora reconhece UTF-16 LE sem BOM (zeros nas posições ímpares) e
  só acrescenta o BOM (testado com UTF-8, UTF-16 com e sem BOM). Depois de converter, conferir os 4
  primeiros bytes: `FF FE` + letra + `00`. Para reescrever um arquivo UTF-16 inteiro, o caminho mais
  seguro é escrever o texto num arquivo UTF-8 à parte e convertê-lo para o destino.

### Cartão da Agenda atrás da barra de tarefas
- **Sintoma:** o rodapé da Agenda ("mais N eventos") fica coberto pela barra de tarefas; o
  `KeepOnScreen=1` não empurra a janela para cima (03/10, integração, com a Agenda em y=197 e 8 itens).
- **Causa:** com `DynamicWindowSize=1`, a janela cresce para baixo a partir do `Y`, e o `KeepOnScreen`
  não a trouxe de volta acima da barra. Não foi isolado se o limite dele é o monitor (864 px lógicos)
  em vez da área útil (816), ou se ele só age quando a janela é movida, não quando cresce.
- **Como evitar:** `Y` + altura máxima da Agenda ≤ área útil; o teto da altura é o `MaxItems`
  (`Local.inc`). Conta e posições: [widgets.md § Layout](widgets.md#layout-horizonte).

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

### Varredor "limpo" com segredo dentro do skin
- **Sintoma:** `tools/varrer-segredos.sh` diz "limpo", mas um `.inc`/`.lua` do `skin\` tem um
  caminho `C:\Users\<nome>` ou um e-mail.
- **Causa:** a working tree do skin é UTF-16 LE: cada letra vem colada a um byte zero e o `grep`
  não casa o padrão ASCII.
- **Como evitar:** o varredor detecta o BOM `FF FE` e passa o arquivo por `iconv` antes do
  `grep` (desde 02/10/2026; testado com um `.inc` UTF-16 sintético).
