# Widgets do pacote Horizonte

Como cada widget funciona, que variáveis ele lê e como depurar. Visão e fases: [roadmap](../roadmap/2026-10-02-horizonte-visao-e-plano.md);
formato do `agenda.json`: [CONTRATOS.md](CONTRATOS.md); o que já mordeu: [ARMADILHAS.md](ARMADILHAS.md).

## Instalar e ligar

```powershell
powershell -NoProfile -File instalar.ps1 -ComSkin -SemDisparar
```

`-ComSkin` liga a pasta `skin\` do repo em `Documents\Rainmeter\Skins\Horizonte` por junction e
manda `!RefreshApp` (sem isso a pasta nova não aparece). Depois, cada widget é uma config própria:

```
"C:\Program Files\Rainmeter\Rainmeter.exe" !ActivateConfig Horizonte\Relogio Relogio.ini
```

Posição e camada se mudam por bang (nunca editando o `Rainmeter.ini` à mão):
`!Move X Y Horizonte\Relogio`, `!ZPos -2 Horizonte\Relogio` (`-2` = no desktop, sobrevive ao Win+D).

## Layout `Horizonte`

O Rainmeter não tem bang para **salvar** layout: salvar é copiar o `%APPDATA%\Rainmeter\Rainmeter.ini`
para `%APPDATA%\Rainmeter\Layouts\<nome>\Rainmeter.ini`, em UTF-16 LE (ou usar Gerenciar → Layouts →
Salvar). Carregar é `Rainmeter.exe !LoadLayout "<nome>"`, que troca a lista inteira de skins pela do
layout: o que não está nele não é carregado.

O repo versiona [`layouts/Horizonte/Rainmeter.ini`](../layouts/Horizonte/Rainmeter.ini), só com as 5
seções `Horizonte\*` (sem `SkinPath`). Para usar noutra máquina: copiar a pasta `layouts\Horizonte`
para `%APPDATA%\Rainmeter\Layouts\` e mandar `!LoadLayout "Horizonte"` (o caminho do `!LoadLayout`
não foi exercitado nesta máquina; aqui as posições foram aplicadas por `!Move`).

Posições (px lógicos; monitor principal de 2048 × 864 com barra de 48, área útil até y=816):

| widget | X, Y | janela |
| --- | --- | --- |
| Relógio | 0, 197 | 430 × 217 |
| Dia | 0, 426 | 430 × 290 (cartão 268, 284 com aviso) |
| Agenda | 454, 197 | 380 × altura da lista |
| Máquina | 858, 197 | 330 × 187 (+72 por disco a mais) |
| Claude | 858, 396 | 330 × ~254 |

- **Y=197** é o do skin antigo (`GoogleCalendar`). Vão de 12 entre widgets empilhados e de 24 entre
  colunas. Todos com `AlwaysOnTop=-2`, `Draggable=1`, `SnapEdges=1`, `KeepOnScreen=1`: o ajuste fino é
  arrastar.
- **Por que a Agenda tem coluna própria** (decisão técnica, 03/10): empilhada sob o Dia, ela começaria
  em y≈722 e teria 94 px até a barra, menos que o cabeçalho (68). Subir a coluna inteira para y=0
  deixaria ~291 px, ou seja, `MaxItems=2` no pior caso. Ao lado, ela tem 619 px (197 a 816).
- **`MaxItems=6` no `Local.inc`** desta máquina (não versionado; apagar a linha volta ao 8). Com 8, a
  agenda real de 03/10 passou da área útil e o fim do cartão ficou **atrás da barra de tarefas**
  ([ARMADILHAS](ARMADILHAS.md#cartão-da-agenda-atrás-da-barra-de-tarefas)). Com 6 a mesma agenda ocupa
  ~520 px. Pior caso teórico com 6 (6 eventos em 6 dias + faixa de erro de 3 fontes), estimado pelas
  medidas da seção Agenda: ~650 px, ~30 além da área útil; `MaxItems=5` cobre até ele.
- **Reverter:** `!LoadLayout "Horizonte antes da integracao"` volta às posições anteriores (os 5
  estavam no monitor secundário, X ≥ 2048); `!LoadLayout "GoogleCalendar antigo"` religa o skin
  antigo em 0,197 e desliga os 5 do Horizonte. Os dois layouts existem só nesta máquina
  (`%APPDATA%\Rainmeter\Layouts\`), criados em 03/10.
- Com o notebook desencaixado, o monitor principal muda de tamanho e o `KeepOnScreen` empurra os
  widgets para dentro da tela: posições acima valem para o monitor externo. Não testado.

### Nitidez (DPI): shim HighDpiAware, **não aplicado**

O Rainmeter roda DPI-unaware e o Windows estica a janela ×1,25 (borra um pouco). O shim de
compatibilidade deixa nítido, mas vale para **todo** o Rainmeter (qualquer outro skin encolhe 20 %).
Habilitar:

1. `reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "C:\Program Files\Rainmeter\Rainmeter.exe" /t REG_SZ /d "~ HIGHDPIAWARE" /f`
   (o nome do valor é o caminho do executável; se já houver um valor para ele com outras flags,
   acrescente `HIGHDPIAWARE` em vez de trocar).
2. Sair do Rainmeter (bandeja → Sair) e abrir de novo; o shim só vale para processo novo.
3. `Scale=1.25` no `Local.inc` (é da máquina, não do pacote; `Variaveis.inc` fica com 1).
   Geometria e fonte já multiplicam por `#Scale#`.
4. **As posições passam a ser px físicos**: os widgets pulam. Reposicionar ×1,25 com `!Move`:
   Relógio 0,246; Dia 0,533; Agenda 568,246; Máquina 1073,246; Claude 1073,495. Depois, salvar o
   layout de novo.

Reverter: `reg delete "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "C:\Program Files\Rainmeter\Rainmeter.exe" /f`,
reiniciar o Rainmeter, tirar o `Scale` do `Local.inc` e `!LoadLayout "Horizonte"`. Não testado
com monitores de DPI diferentes (os dois desta máquina estão a 125 %); se o Rainmeter se comportar
mal assim, fica o modo borrado (roadmap § Resultado dos spikes).

## Base (`skin\@Resources`)

Todo widget inclui, nesta ordem: `Variaveis.inc` → `Tokens.inc` → `Estilos.inc`.

| arquivo | o que tem |
| --- | --- |
| `Variaveis.inc` | `Scale`, `Tema`, `Animacoes`, `ReleituraS`, `Privado` (cadeado da Agenda; o clique grava no `Local.inc`), variáveis de depuração, apelidos `ApelidoConta1..8` (padrão `conta N`), discos da Máquina (`Discos`, `RotuloDisco<letra>`, `BateriaCadenciaS`, `DebugBateria`), Claude (`ReleituraClaudeS`, `TrayParadoS`, `TrayExe`, `DebugTray`) e, por último, `@Include` do `Local.inc` |
| `Local.inc` | **não versionado** (`.gitignore`): sobrescritas da máquina, como os apelidos reais das contas Claude. Modelo: `Local.example.inc`. Sem ele, tudo funciona com os padrões |
| `Tokens.inc` | inclui `Tokens-#Tema#.inc` e fixa o que não muda com o tema: cores do contrato Claude (`ClaudeOk/Alerta/Critico/Velho` e `ClaudeTrilho`, o `#46464E` do trilho das barras da bandeja), saúde de fonte (`CorAlerta`, `CorCritico`) e fontes (`FonteDisplay`, `FonteTexto`, `FonteMono`) |
| `Tokens-expressivo.inc` | tema Expressivo, esquema "Ardósia" do protótipo: `CorS`, `CorSHi`, `CorOn`, `CorOnV`, `CorPri`, `CorOnPri`, `CorSol`, `CorOnSol`, `CorSold`, `CorOnSold`, `CorCalm`, `CorOnCalm`, `CorAgPes/Cor/Fer`, `CorCtl`, `CorOnCtl`, alfas (`AlfaChip`, `AlfaDoisPontos`) e raios. Cores em `R,G,B`; o alfa se acrescenta no uso: `#CorOnPri#,153` |
| `Estilos.inc` | MeterStyles: `EstTexto`, `EstDisplay`, `EstMono`, `EstDigito`, `EstChip` |
| `Lua\carregar.lua` | carregador de módulos (ASCII, por `dofile`); aceita módulo em UTF-16 LE com BOM e passa o ambiente do widget (onde mora o `SKIN`) para o módulo |
| `Lua\comum.lua` | leitor de JSON com cache do último estado bom (`comum.leitor`), datas em pt-BR por tabela (`dataExtensa`, `diaCurtoData`, `rotuloFeriado`), caminhos (`caminhoDados`, `caminhoAgenda`, `caminhoSnapshot`), tempo (`inicioDoDia`, `duracao` "1h30", `epochIso` para o `ResetsAt` do tray), `corHex`, `urlSegura` (filtro de URL antes de virar ação de clique), `expandirAmbiente` (`%VAR%` → valor), `existe`, log |
| `Lua\anel.lua` | anel no gesto do protótipo para qualquer tamanho: `anel.novo(px, traço, Scale)` e, dele, `disco` (círculo/cookie/sol de N lóbulos, com giro), `arcos` (trilho + indicador com a folga de 4 px; varredura mínima opcional) e `ponto` (marcador acima do topo). Só gera as strings de `Shape`. Hoje só o Claude usa; o `Maquina.lua` tem a cópia original (migrar é pendência) |
| `Lua\anim.lua` | molas pré-calculadas (mesma física do protótipo: rigidez `k`, amortecimento `z`), `anim.valor(mola, s)`, `anim.nomeada(nome, eps)` (eps 0,01 corta a cauda invisível das molas que passam do ponto e faz `forma`/`boing` caberem em ~0,42 s; `row` é a da entrada da Agenda), easing, interpolação de cor (`anim.cor`, `anim.alfa`) |
| `Lua\json.lua` | rxi/json.lua 0.1.2 (MIT), ASCII |

**Escala.** O Rainmeter roda DPI-unaware: o Windows estica a janela inteira (×1,25 nesta máquina)
e borra um pouco. Por isso `Scale=1` e as medidas são as lógicas do protótipo. Toda medida é
`n*#Scale#` e toda fonte é `px*0.75*#Scale#` (o Rainmeter mede pt a 96 DPI). Quando o shim
HighDpiAware entrar, `Scale=1.25` no `Local.inc` e reposicionar: [§ Nitidez](#nitidez-dpi-shim-highdpiaware-não-aplicado).

**Encoding.** `.ini`, `.inc` e `.lua` dos widgets em UTF-16 LE com BOM (o `.gitattributes`
converte na working tree). Exceção: `json.lua` e `carregar.lua`, ASCII, porque o `dofile` do
Lua 5.1 lê bytes crus. A ferramenta Write grava UTF-8 (ou UTF-16 sem BOM, sobre um arquivo que já
era UTF-16): depois de editar, rode `powershell -NoProfile -File tools\skin-utf16.ps1` (idempotente;
trata os dois casos).

**Script de widget, esqueleto.** O measure Script de quem lê `agenda.json` se chama **`mLeitor`**
e tem `Recarregar()` (o `agenda_sync` chama depois de gravar). No `Initialize()`:

```lua
local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
comum = carregar('comum'); anim = carregar('anim')
comum.iniciar('NomeDoWidget')
leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
```

`leitor:ler(forcar)` devolve `dados, mudou`. Ele compara o texto cru com a última leitura (o Lua
não tem mtime) e só decodifica quando mudou. Arquivo ausente, JSON pela metade ou
`schemaVersion` diferente mantêm o último estado bom e gravam um erro no log **uma vez por
conteúdo ruim**: o leitor guarda o texto cru que falhou (`cruRuim`) e, enquanto o arquivo seguir
igual, não decodifica nem loga de novo a cada releitura (antes: uma linha de erro por minuto por
widget). `leitor.erro` continua dizendo o problema.

**Animação.** Só transição curta (≤ 500 ms) disparada por mudança; nunca laço. O padrão: um
measure `ActionTimer` com `ActionList1=Repeat Passo, 16, 120` e
`Passo=[!CommandMeasure mLeitor "Passo()"][!UpdateMeasure mAT]`; o Lua calcula o progresso por
`os.clock()` (tempo de parede no Windows), desenha, e manda `Stop 1` quando acaba. Assim a curva
não depende de quantos quadros o Rainmeter conseguiu (~38 fps reais). Por quadro, atualizar só
os meters que se mexem (`!UpdateMeterGroup`), não `*`.

**Parado = zero redesenho.** `DefaultUpdateDivider=-1` no `[Rainmeter]`: meter nenhum se atualiza
sozinho; o Lua manda `!UpdateMeter`/`!Redraw` quando algo muda. Atenção: o `DefaultUpdateDivider`
vale também para measures, então o measure Script que precisa rodar a cada ciclo leva
`UpdateDivider=1`.

**Custo da suíte** (revisão de 03/10, os 5 widgets, Rainmeter 4.5.26, skin antigo **desativado**;
`Get-Process` do `Rainmeter.exe` principal em 60 s; máquina com 50 a 96 % de carga por outras
sessões, então o ruído é alto):

| situação | CPU (% de um núcleo) | RAM privada |
| --- | --- | --- |
| nenhum widget do Horizonte carregado | 0,39 % | 80,2 MB |
| os 5 widgets, valores reais | 5,5 % com a máquina a 96 % de carga; 3,4 % a 82 % | 88,5 a 90,1 MB |
| os 5, sem a Máquina | 0,83 % | 89,7 MB |
| os 5, Máquina com valores fixos (`Forcar`) | 2,3 % | 89,4 MB |

- Quase todo o custo parado é da Máquina com a CPU oscilando: ~370 passos de animação por minuto
  (dígitos rolando); com valores fixos, 14 passos por minuto. Delta de RAM da suíte: **+8 a +10 MB**
  (meta ≤ +15 MB).
- Virada do minuto, com a Máquina fixa: ~94 ms de CPU somados em 2 s (Relógio rola, Dia e Claude
  recalculam); os segundos vizinhos ficam em 0 a 16 ms.
- Para medir: o processo principal é o **mais antigo**; cada bang pela linha de comando sobe um
  `Rainmeter.exe` efêmero ([ARMADILHAS](ARMADILHAS.md#get-process-rainmeter-devolve-dois-processos)).

## Relógio (`Horizonte\Relogio`)

Estádio cheio na cor primária (`CorPri`, texto `CorOnPri`), 430 × 217 px lógicos, raio = metade da
altura. HH:MM em Segoe UI Variable Display 700 a 112 px, dois-pontos a 60 % de opacidade e 6,7 px
acima. Embaixo, a data em pt-BR ("sexta, 2 de outubro", Display 600, 18 px) e o chip do próximo
feriado ("feriado seg 12/10", Text 600, 13 px, fundo `CorOnPri` a 14 %, raio 10). Sem segundos.

**Como funciona.**
- `Update=1000` só para notar a virada do minuto: o `Update()` do Lua compara `HH:MM` com o que
  está na tela e, se mudou, anima só os dígitos que mudaram. A data e o chip se refazem quando o
  dia muda.
- Cada dígito tem um slot próprio: um Shape (`Masc1..4`) usado como **Container** (máscara) e
  dois Strings dentro (`DnSai`, o antigo, sobe e sai; `DnEntra`, o novo, vem de baixo). A
  máscara tem degradê de alfa de 12 % em cima e embaixo, como o `mask-image` do protótipo.
- **Lição do protótipo:** no HTML, o `letter-spacing` negativo deixava o slot mais estreito que o
  dígito e o `overflow` cortava a borda do vizinho. Aqui cada slot (84 px) é mais largo que o
  dígito (64 px) e os slots se **sobrepõem**: cada máscara só corta os próprios Strings, nunca o
  vizinho. O aperto vem só da posição dos centros (passo de 58,8 px, igual ao protótipo).
- Rolagem: mola crítica (`anim.CFG.rolagem`, k=560, z=1: sem overshoot), ~350 ms, passo de
  123 px (1,1 em, o mesmo do protótipo).
- Entrada (ao carregar, ou pelo menu "Repetir a entrada"): os quatro dígitos sobem em cascata
  (40 ms entre eles) e a data e o chip aparecem em fade de 300 ms; a janela em si já entra com o
  fade nativo do Rainmeter.
- O chip lê `agenda.json.proximoFeriado`: some se for `null` ou se a data já passou (arquivo
  velho); "feriado hoje" no próprio dia; senão "feriado `dia` dd/mm". O tooltip do chip mostra o
  nome do feriado (dado local, em tempo de execução). O chip é medido pelo Lua
  (`GetW` do texto + 12 px de cada lado) e vai 12 px depois da data.
- Animação desligada (`Animacoes=0` ou `ambiente.animacoes=false` no `agenda.json`, que vem dos
  "Efeitos de animação" do Windows): tudo muda seco.
- Releitura do `agenda.json`: na hora, por `Recarregar()` (o `agenda_sync` chama), e de reserva a
  cada `ReleituraS` (60 s), só redesenhando se o conteúdo mudou.

**Variáveis do `Relogio.ini`** (`[Variables]`, px lógicos): `DigCx1..4` (centro de cada dígito),
`DoisPontosCx`, `SlotL` (largura do slot), `MascY`/`MascH` (faixa da máscara), `DigY` (Y do String
em repouso dentro da máscara), `DigPasso` (deslocamento da rolagem).

**Custo medido** (02/10, Rainmeter 4.5.26, Windows a 125 %, junto com o skin antigo):
- parado: ~0,1 ponto percentual de um núcleo a mais que sem o relógio (média de 70 s, 0,46 % →
  0,64 %, incluindo uma virada de minuto);
- por virada animada: mediana de 44 ms de CPU (20 amostras), ou seja ~11 % de um núcleo durante
  ~0,4 s;
- RAM privada do Rainmeter: 79,6 MB com o relógio (base medida no spike: 79,5 MB).

### Depurar

| como | o que faz |
| --- | --- |
| `DebugHora=13:59` no `Local.inc` (ou `!SetVariable` + `!Refresh`) | congela o relógio nessa hora |
| `!CommandMeasure mLeitor "Forcar('13:59')" Horizonte\Relogio` | congela já, **animando** a troca; `Forcar('')` volta à hora real |
| `!CommandMeasure mLeitor "Quadro('13:59','14:00',0.25)" Horizonte\Relogio` | desenha um quadro **parado** da rolagem na fração 0,25 da mola (prova visual determinística); `Forcar('')` desfaz |
| `!CommandMeasure mLeitor "Entrada()" Horizonte\Relogio` | repete a entrada |
| `!SetVariable DebugAgenda "C:\caminho\teste.json" Horizonte\Relogio` e depois `!CommandMeasure mLeitor "Recarregar()" Horizonte\Relogio` | lê outro `agenda.json` (estado sem feriado, feriado hoje, JSON quebrado); `DebugAgenda` vazio volta ao real |
| `DebugLog=1` no `Local.inc` | grava eventos de rotina em `%LOCALAPPDATA%\Horizonte\widget.log` (erros vão sempre, também para o log do Rainmeter) |

Captura de tela para prova: `cap.ps1` (DPI-aware) recebe coordenadas **físicas** = lógicas × 1,25.
Para ver a animação de verdade, capture em rajada num processo só (uma captura por processo leva
~300 ms, mais que a rolagem inteira).

### Simplificações em relação ao protótipo

- **Rolagem por dois Strings, não por carretel.** No HTML cada dígito é um carretel 0–9 (de 9 para
  0 ele gira a volta toda para trás) com mola `rapida` (k=800, z=0,6, que passa do ponto). Aqui o
  dígito antigo sobe e o novo vem de baixo, com mola crítica (pedido da fase: sem overshoot).
- **Sem blur de movimento** nos dígitos e sem blur/escala na entrada do widget: o Rainmeter não
  tem filtro de blur. A entrada é fade nativo da janela + dígitos em cascata + fade da data.
- **Cor do chip:** o protótipo usa `color-mix` em oklab; aqui é alfa 36/255 sobre a primária
  (mistura em sRGB). Diferença invisível a olho.
- **Largura fixa** (430 px): no HTML o rodapé quebra linha se não couber. A data mais longa
  ("quarta, 30 de setembro") com o chip mais longo cabe com folga estimada de ~9 px (estimativa
pela largura medida no protótipo, não capturada no Rainmeter).
- Nitidez: enquanto o Rainmeter rodar DPI-unaware, o widget sai levemente borrado (esticado
  ×1,25 pelo Windows). Resolve com o shim HighDpiAware + `Scale=1.25` (roadmap § Resultado dos
  spikes).

## Dia (`Horizonte\Dia`)

Cartão de 430 × 268 px lógicos (284 com a linha de aviso) cuja **cor e forma dizem o papel**, e
embaixo a linha do dia. Lê `agenda.json` (eventos com hora; os de dia inteiro ficam de fora) e, do
`snapshot.json` do claude-usage-tray, **só** o `ResetsAt` da barra `5h` da conta `Active`.

| papel | quando | fundo / texto | raios (TL TR BR BL) | o que diz |
| --- | --- | --- | --- | --- |
| PRÓXIMO | próximo evento de hoje a até `LivreMin` (120 min) | `CorSHi` / `CorOn` | 32 32 32 32 | "Próximo, em 23 min" (até `EmMin`=60) ou "Próximo, às 16:00"; título 32 px 700; "15:00 às 15:30, corporativo" + ♻ se recorrente |
| URGENTE | a até `UrgenteMin` (15 min) | `CorSold` / `CorOnSold` | 22 × 4 | igual ao PRÓXIMO |
| AGORA | há evento em curso | `CorSol` / `CorOnSol` | 56 14 56 14 | "Agora" ou "Agora (2)" na sobreposição; barra ondulada de progresso; "termina 15:30, faltam 25 min" |
| LIVRE | nada em curso e o próximo de hoje está a mais de `LivreMin`, ou acabou o dia | `CorCalm` / `CorOnCalm` | 72 × 4 | "livre até 15:00, 3h" (+ "depois 15:00 título"), "dia livre a partir de 18:30" ou "dia livre" (+ "amanhã 09:00 título" / "qua 07/10 …" / "nada mais na agenda") |

**Como funciona.**
- `Update=1000` só para notar a virada do minuto; o conteúdo é recalculado uma vez por minuto (e
  na releitura). Se a **chave** do estado muda (papel + evento, ou o nº de eventos em curso), anima;
  se só o texto muda ("em 23 min" → "em 22 min", agulha), redesenha seco.
- No AGORA principal = o evento em curso que começou por último. **Entrar** usa o `meetUrl` dele
  ou, se não tiver, o de outro evento em curso.
- **Botão Entrar**: some sem `meetUrl`; círculo apagado (ícone, fundo `on` a 14 %) até `AcendeMin`
  (10 min); pílula acesa com rótulo a ≤ 10 min e no AGORA. Clique abre o `meetUrl`; clique no
  título abre o `link` do evento. As duas URLs passam por `comum.urlSegura` (só `http(s)`, sem
  espaço, aspas, colchete nem `#`) antes de virar `LeftMouseUpAction=[url]`. O meter `Botao` fica
  na posição da pílula (o Lua escreve `X`/`Y` e a forma em coordenadas locais): o retângulo do meter
  é a área do tooltip "Entrar na videochamada", que antes (forma em `X=0,Y=0`) cobria o rótulo e o
  topo do título ([ARMADILHAS](ARMADILHAS.md#tooltip-de-uma-linha-aparece-em-cima-de-outra)). A
  máscara `BotaoMasc` fica em 0,0, porque o `BotaoRotulo` se posiciona relativo a ela.
- **Modo privado**: com `Privado=1` (cadeado da Agenda) os títulos de evento do cartão e o tooltip
  viram "Compromisso". O clique no cadeado manda `!SetVariable Privado` e
  `!CommandMeasure mLeitor "Privado(0|1)"` para o Dia; na carga, o Dia lê `Privado` do `Local.inc`.
- **Linha do dia**: 07–21h por padrão (`LinhaDe`/`LinhaAte`); alarga até a hora cheia do 1º/último
  evento de hoje, até o agora (de noite) e até o reset do Claude se ele cair ainda hoje; antes das
  07h vira 00–24. Blocos na cor da agenda (`CorAgPes/Cor/Fer` pelo id da fonte; fonte desconhecida
  usa o `cor` do JSON): passado 30 %, futuro 62 %, atual 100 %. No AGORA o bloco puxa 60 % para a
  cor do texto (as cores pastel somem no laranja). Rótulos: as pontas e as horas múltiplas de 3
  (a ≥ 1,5 h das pontas), o que dá 07 09 12 15 18 21 no padrão. Agulha de 4 × 30 px na cor do
  texto. ♻ do reset: opacidade 0,8 (0,35 se o `ResetsAt` já passou: snapshot velho), tooltip
  "Claude renova às HH:MM".
- **Aviso** (a linha de baixo, que aumenta o cartão para 284 px): toda fonte com `status` ≠ `ok`
  ("corporativo offline, dados de 16:24"; `httpNNN` vira "erro NNN"), e "agenda.json sumiu" /
  "ilegível, mostrando a última leitura" quando o arquivo falha depois de uma leitura boa.
- **Sem `agenda.json` desde o início**: papel PRÓXIMO, "agenda indisponível" e a dica do
  `agenda-sync`. Sem eventos: "dia livre", "nada mais na agenda".
- **Snapshot do tray**: relido a cada `ReleituraSnapS` (60 s), só leitura; BOM e arquivo pela
  metade (o tray ainda não grava atômico) mantêm o último estado bom. Nunca uma segunda coleta.

**Motion** (tudo ≤ 450 ms, disparado por troca de estado; parado = zero redesenho):
- cor de fundo e do texto interpolam em 450 ms (ease-out cúbico);
- raios dos cantos por mola `forma` (k=420, z=0,55, com eps 0,01: ~0,40 s, passa um pouco do
  ponto) e o fundo "respira" de 0,965 a 1 por mola `boing` na troca de papel;
- texto: o antigo sai em 150 ms subindo 8 px; o novo entra de 18 px abaixo por mola `espacial`
  (~0,25 s);
- botão: a pílula cresce da direita para a esquerda por mola `boing`; o rótulo fica dentro de um
  Container com a mesma pílula (o `clip-path` do protótipo);
- AGORA: a onda da barra ganha amplitude por mola `boing` e há **um** acendimento (branco a 22 %
  sobre o fundo, 100 ms subindo e ~350 ms apagando), só na entrada no AGORA.
- Custo medido (02/10, junto com o skin antigo e o Relógio): parado 1,09 % → 1,15 % de um núcleo
  (dentro do ruído; RAM privada 80,7 → 80,3 MB); por transição PRÓXIMO ↔ AGORA, mediana de 78 ms de
  CPU (20 amostras; ~17 % de um núcleo durante 0,45 s).

**Variáveis do `Dia.ini`**: `LivreMin`, `EmMin`, `UrgenteMin`, `AcendeMin` (minutos),
`LinhaDe`/`LinhaAte` (horas), `ReleituraSnapS`.

### Depurar

| como | o que faz |
| --- | --- |
| `!SetVariable DebugAgenda "<json>" Horizonte\Dia` e `!SetVariable DebugSnapshot "<json>" Horizonte\Dia`, depois `!CommandMeasure mLeitor "Recarregar()" Horizonte\Dia` | lê fixtures em vez dos arquivos reais (vazio volta ao real) |
| `!CommandMeasure mLeitor "Forcar('14:50')" Horizonte\Dia` | "hoje, a essa hora", **animando** a troca; `Forcar('')` volta à hora real. `DebugHora=HH:MM` no `Local.inc` faz o mesmo desde a carga (vale também para o Relógio) |
| `!CommandMeasure mLeitor "Quadro('14:51','15:05',0.25)" Horizonte\Dia` | quadro **parado** da transição na fração 0,25 de 450 ms |
| `!CommandMeasure mLeitor "Esquecer()" Horizonte\Dia` | esquece o último estado bom e relê (prova "arquivo ausente desde o início" sem `!Refresh`, que zera o `DebugAgenda`) |
| `!CommandMeasure mLeitor "Entrada()" Horizonte\Dia` | repete a entrada |

Fixtures sintéticas e scripts de prova (fora do repo, em `temp\fase2\dia\`): `gerar.py` gera
`agenda-{normal,sobreposicao,vazia,amanha,velha,larga,madrugada,quebrada}.json` com eventos de
**hoje** e `snapshot{,-noite,-parcial}.json`; `estado.sh HH:MM nome [agenda] [snapshot]` força e
captura; `rajada.ps1` captura a animação em rajada; `cpu.ps1`/`cpu-anim.ps1` medem o custo.

### Simplificações em relação ao protótipo

- **Blocos na cor da agenda**, não no `currentColor` do protótipo (pedido da fase); no AGORA eles
  puxam 60 % para a cor do texto para não sumir no laranja.
- **Sem blur** na troca de texto (o Rainmeter não tem filtro): só opacidade e deslocamento.
- **Sem rolagem de dígitos** em "em 23 min"/"faltam 20 min": o minuto troca seco (o Relógio já
  rola; aqui seriam 4 Containers a mais por um texto pequeno).
- **Título numa linha só**, cortado com reticências (o HTML quebra linha); o tooltip mostra
  inteiro. Sem `letter-spacing` exato: `InlineSetting=CharacterSpacing` aproxima o −0,02 em.
- **Agulha sem mola** (no protótipo, mola `needle`): ela pula para o lugar novo a cada minuto e no
  `Forcar` (0,4 px por minuto não justifica uma animação).
- **Sem escala no botão ao clicar** e sem foco de teclado (o Rainmeter não tem `:active`/foco).
- O ♻ e o ícone de vídeo são glifos do Segoe Fluent Icons (`E895`, `E714`), não os SVGs do
  protótipo.

## Agenda (`Horizonte\Agenda`)

Cartão de 380 px lógicos (fundo `CorS`, raio 32), altura pela lista (`DynamicWindowSize=1`). Lê
`agenda.json`. Medidas do protótipo: cabeçalho até y=68, cabeçalho de dia 36,2 px, evento 38, vão
30,9, "mais N" 30,9 + 18 de respiro.

| parte | o que mostra |
| --- | --- |
| cabeçalho | "Próximos 14 dias" (Display 650, 15 px, `CorOnV`); um ponto de 8 px por fonte; cadeado 40 × 40 |
| ponto de saúde | `ok` = cor da agenda (`CorAgPes/Cor/Fer`; fonte desconhecida usa o `cor` do JSON); `offline`, `http5xx` e status desconhecido = âmbar (`CorAlerta`, dado velho); `http4xx`, `formato`, `sem_credencial` = vermelho (`CorCritico`, precisa de ação) e cresce para 5,4 px. Tooltip: "`id`: sincronizada" ou "`id`: " + `sources[].erro` |
| faixa de erro | no topo da lista quando alguma fonte falha: uma linha por fonte, primeira frase em negrito ("Agenda corporativa offline, dados de 16:55.") + o `erro` do helper, que já diz o que fazer. Também para arquivo ausente/ilegível/de outra versão. Fundo = cor do pior caso a 16 % sobre `CorS` |
| cabeçalho de dia | "Hoje" (sempre), "amanhã, sábado", "segunda, 5/10"; rótulo pela diferença de início de dia |
| evento | hora em Cascadia Mono 13 px, "dia todo", ou pílula "agora" (`CorSol`) se já começou; ponto de 10 px na cor da agenda; título (Text 550, 15 px, cortado com reticências; tooltip com título, horário e agenda); à direita, rótulo da série, ♻ se `recurring` e ícone de vídeo se houver `meetUrl` |
| vão livre | só hoje, entre dois eventos com hora da lista, a partir do maior fim acumulado (sobreposição): "livre 15:30 às 17:30, 2h" se ≥ `VaoMin` |
| rodapé | "mais N eventos até 16/10" (16/10 = hoje + `DiasLista`) ou "nada mais até 16/10" |

**Regras da lista.**
- Entram os eventos que **ainda não acabaram** (relógio local, conferido a cada virada de minuto) e
  começam até o fim de hoje + `DiasLista`. Evento de dia inteiro vale até a meia-noite do `endDate`
  (exclusivo); um de vários dias que começou ontem aparece em "Hoje" como "dia todo".
- Fontes em `FontesOcultas` (padrão `feriados`) não ocupam linha: o feriado está no chip do Relógio.
- Até `MaxItems` eventos (cabeçalhos e vãos não contam; teto físico de 26 linhas). O resto vira o
  "mais N". Hoje sem nada: "nada mais hoje".
- **Série diária colapsada.** Ocorrências já expandidas pelo helper com a mesma fonte, título, hora de
  início e duração e `recurring=true` viram uma linha só (a próxima) quando são ≥ 3 e nunca ficam mais
  de 3 dias sem ocorrer (sexta → segunda). Rótulo "diário" (todo dia do intervalo) ou "seg a sex"
  (todos os dias úteis e só eles); senão, sem rótulo. Série semanal (2 ocorrências em 14 dias) não
  colapsa. É agrupamento para exibir, não expansão de recorrência (essa continua só no helper).
  **Caminho limpo futuro:** um campo opcional `serie` no contrato (derivado do UID) trocaria a
  heurística por identidade; fica para quando mexerem no `agenda_sync`.
- **Modo privado**: o cadeado (ou o menu "Modo privado") troca todos os títulos, inclusive o
  tooltip, por "Compromisso". O estado vai para `Privado=0/1` no `Local.inc` por `!WriteKeyValue`
  (sem `Local.inc`, o Lua cria o arquivo em UTF-16 LE com BOM só com `[Variables]` antes do bang;
  conferido em 02/10) e sobrevive a refresh e reinício. O clique também avisa o Dia
  (`Privado(0|1)`), que esconde o título do cartão; conferido em 03/10.
- **Altura**: o estado mais alto medido (8 eventos hoje, 4 vãos, faixa com 2 fontes) dá ~720 px
  lógicos; o pior teórico (8 eventos em 8 dias + faixa de 3 fontes) ~790. Com `KeepOnScreen=1`, um
  `Y` que não deixe essa folga acima da barra de tarefas deixa o fim do cartão **atrás da barra**: o
  Rainmeter não empurrou a janela em 03/10 ([ARMADILHAS](ARMADILHAS.md#cartão-da-agenda-atrás-da-barra-de-tarefas)).
  Nesta máquina o teto vem do `MaxItems=6` ([§ Layout](#layout-horizonte)).
- **Clique**: na linha abre o `link` do evento; no ícone de vídeo abre o `meetUrl` (os dois por
  `comum.urlSegura`). Hover: fundo `CorOn` a 7 % e raio 12 → 19, 120 ms. Em repouso o fundo tem
  alfa 1, não 0: pixel 100 % transparente não recebe o mouse na janela do Rainmeter.

**Como funciona.**
- 26 slots genéricos no `.ini` (`Bg`, `Tm`, `Tt`, `Ro`, `Rc`, `Vd` por slot, `Group=S<n>`); o Lua
  monta a lista, escreve cada linha num slot e compara a assinatura de cada slot (tipo, chave,
  posição, textos, cor, ícones, links) com a anterior.
- `Update=1000` só para a virada do minuto; o conteúdo é remontado uma vez por minuto e na
  releitura. Releitura do `agenda.json`: na hora pelo `Recarregar()` e de reserva a cada `ReleituraS`.
- Por quadro, só os slots cujo alfa/deslocamento/hover mudou são redesenhados
  (`!UpdateMeterGroup S<n>`), e o cabeçalho só se mudou.

**Motion** (disparado por mudança; parado = zero redesenho):
- **entrada** (carga ou "Repetir a entrada"): cartão e cabeçalho aparecem, e as linhas sobem 10 px
  com alfa pela mola `row` (k=420, z=0,72; ~0,3 s), escalonadas em até 35 ms (no máximo 150 ms no
  total): termina em ~0,45 s;
- **troca**: cada linha cuja assinatura mudou some em 110 ms e a nova entra 4 px abaixo em 220 ms
  (crossfade). O cartão cresce desde o início ou encolhe depois que a linha velha sumiu;
- **cadeado**: raio 20 → 12 por mola `boing`, fundo de `CorOn` 8 % para `CorOn` e ícone de `CorOnV`
  para `CorS` em 300 ms; o glifo (`E785` aberto / `E72E` fechado) troca seco;
- **saúde**: cor do ponto em 300 ms e raio 4 → 5,4 por mola `boing`.

**Custo medido** (02/10, junto com o skin antigo, Relógio e Dia; Rainmeter 4.5.26):
- parado: dentro do ruído (90 s com a Agenda 0,80 % de um núcleo; sem ela 0,94 %); RAM privada
  +0,5 a 1,5 MB;
- por transição (janela de 1 s, 16 amostras): entrada mediana 63 ms de CPU; troca de uma linha
  31 ms; troca da lista inteira (evento acabou e tudo subiu) 78 ms. O passo do `ActionTimer` é de
  30 ms (~25 quadros/s): com 16 ms (como no Dia) a troca da lista inteira custava ~150 ms, porque o
  `!Redraw` repinta a janela inteira.

**Variáveis do `Agenda.ini`** (definidas **antes** dos `@Include`, então o `Local.inc` pode
sobrescrever): `MaxItems` (8), `VaoMin` (45 min), `DiasLista` (14), `FontesOcultas` (`feriados`).

### Depurar

| como | o que faz |
| --- | --- |
| `!SetVariable DebugAgenda "<json>" Horizonte\Agenda` e `!CommandMeasure mLeitor "Recarregar()" Horizonte\Agenda` | lê uma fixture (vazio volta ao real) |
| `!CommandMeasure mLeitor "Forcar('14:37')" Horizonte\Agenda` | "hoje, a essa hora", **animando** a troca; `Forcar('')` volta à hora real |
| `!CommandMeasure mLeitor "AlternarPrivado()" Horizonte\Agenda` | o mesmo que clicar no cadeado (grava no `Local.inc`) |
| `!CommandMeasure mLeitor "Esquecer()" Horizonte\Agenda` | esquece o último estado bom e relê (prova "sem arquivo desde o início") |
| `!CommandMeasure mLeitor "Entrada()" Horizonte\Agenda` | repete a entrada |

Fixtures sintéticas e scripts de prova (fora do repo, em `temp\fase2\agenda\`): `gerar.py` gera
`agenda-{normal,diario,offline,404,vazia,poucos,quebrada}.json` relativos a hoje; `estado.sh HH:MM
nome [json]` força e captura; `rajada.ps1` + `folha.py` capturam e montam a animação;
`hover.ps1` põe o mouse numa linha e captura; `cpu-anim.ps1` mede o custo por transição.

### Simplificações em relação ao protótipo

- **Crossfade por slot, não FLIP.** No HTML cada linha tem chave e, quando uma some, as de baixo
  deslizam por mola. Aqui as linhas são posições fixas: quando uma linha some, todas as de baixo
  mudam de conteúdo e fazem crossfade juntas (há um instante de ~30 ms com a lista vazia entre a
  saída e a entrada).
- **Sem blur e sem escala** na saída/entrada das linhas (o Rainmeter não tem filtro): só alfa e
  deslocamento.
- **Cadeado sem a haste animada**: o protótipo desloca a haste do cadeado por mola; aqui o glifo
  aberto/fechado troca seco e só o botão muda de forma e cor.
- **Faixa de erro com uma linha por fonte** e o `erro` do helper, em vez do texto fixo do protótipo
  ("Reconecte a conta pela bandeja"), que não corresponde ao que o `agenda_sync` pede.
- **Ponto na cor da agenda quando ok** (pedido da fase), não o verde `--ok` do protótipo.
- **Vão de 45 min** (pedido da fase); no protótipo eram 60.

## Máquina (`Horizonte\Maquina`)

Cartão de 330 × 187 px lógicos (fundo `CorS`, raio 32) com título "Máquina" e uma fileira de anéis
de 68 px em colunas de 66 px (vão 6): **CPU, RAM, GPU** e um anel por disco da lista `Discos`. Cada
disco a mais alarga o cartão em 72 px (o Lua desenha o cartão). Medidas e cores são as do
protótipo (`Ring` de `design/horizonte-v1-expressivo.html`, viewBox 128 em 68 px): traço 11, folga
de 4 px entre as pontas redondas do indicador e do trilho, disco interno com alfa 0,15, trilho com
alfa 0,24 e indicador cheio, tudo na cor da faixa. Número no centro em Display 700, 20 px, unidade
(`%`, `GB`, `TB`) a 8,4 px com alfa 0,7; legenda em Text 600, 12,5 px; sublegenda em `CorOnV`.

| anel | número / arco | sublegenda | âmbar | vermelho | hover (linha à direita do título) | clique |
| --- | --- | --- | --- | --- | --- | --- |
| CPU | `% Processor Utility` (`_Total`), limitado a 0..100, média móvel de 5 s; de 5 em 5 | — | ≥ 85 por 10 s | ≥ 95 por 30 s | processo mais pesado: "chrome 18%" | `taskmgr` |
| RAM | `PhysicalMemory` usado / total; de 1 em 1 | usados, "9,3G" | ≥ 85 por 10 s | ≥ 93 por 30 s | maior processo: "maior: msedge 1,9 GB" | `resmon` |
| GPU | `UsageMonitor Alias=GPU Index=0`, amostrado; de 5 em 5 | — | ≥ 85 por 10 s | ≥ 95 por 30 s | — | `taskmgr` |
| disco | número = **GB livres** (TB acima de 999 GB), arco = **% usado** | "livres" | < 15 % livre | < 8 % livre | "C: 74 de 476 GB livres" | C: `ms-settings:storagesense`; outro: abre a unidade |

- **Neutro em repouso**: indicador `CorOnV` (`--on-v`) sobre o próprio trilho a 24 % (dá o tom de
  `--s-hi` sobre o cartão, como no protótipo). Cor só quando o anel pede atenção.
- **Histerese**: subir exige o valor acima do limiar pelo tempo da tabela (cada limiar com o próprio
  relógio); descer exige ficar 5 pontos abaixo (RAM 3; disco 1) por 5 s (disco: na hora). De
  vermelho, desce para âmbar se ainda estiver acima do limiar do âmbar menos a histerese. Por isso
  um disco que passou de 85 % usado só volta ao neutro abaixo de 84 %.
- **Valor mostrado = valor do arco**, quantizado (CPU/GPU de 5 em 5, RAM de 1 em 1, disco em GB
  inteiros) com zona morta de 0,6 passo: o número só troca quando o bruto se afasta mais de 0,6
  passo do que está na tela. Parado, nada se redesenha; **o tick de 1 s só lê measures**.
- **Discos**: `Discos=C:` no `Variaveis.inc` (até 3, separados por vírgula; sobrescreva no
  `Local.inc`: `Discos=C:,G:`). Rótulo fixo por `RotuloDisco<letra>` (`C`=SSD, `G`=Drive); sem rótulo,
  a letra. O rótulo do volume nunca é lido (o do Google Drive tem o e-mail). Unidade fora da lista
  não é medida (measures `mDisco1..3` ficam `Disabled`); unidade da lista que não existe mostra "–",
  sem sublegenda, e o tooltip "X: indisponível". Discos são lidos a cada 30 s.
- **Processo mais pesado** (hover): `mTopCpu`/`mTopRam` só viram `Alias=CPU`/`RAM` (`Index=1`,
  `Blacklist=_Total|Idle`, `Rollup=1`) enquanto o mouse está no anel, e voltam ao contador barato
  na saída ([ARMADILHAS](ARMADILHAS.md#usagemonitor-custa-cpu-com-o-measure-desligado)). O valor de
  CPU por processo do UsageMonitor **já vem dividido pelos 14 núcleos lógicos** (um laço ocupando um
  núcleo inteiro aparece como 7 %, igual ao Gerenciador de Tarefas): não se divide de novo. Nome do
  processo passa por `comum.textoSeguro` e perde `[`, `]` e `#`.
- **GPU por amostra**: `mGpu` fica no contador barato e o Lua aponta para `Alias=GPU` por 2 s a cada
  10 s (30 s na bateria), lê e volta. A entrada espera a primeira amostra: por ~2 s depois da carga
  o cartão mostra os trilhos vazios.
- **Reserva da CPU**: se o `% Processor Utility` ficar em 0 por 5 leituras enquanto o `Measure=CPU`
  passa de 3, o Lua troca para o `Measure=CPU` e o hover ganha "(aprox.)". Não provado na máquina
  real (o contador existe aqui).
- **Bateria** (`PowerPlugin`, consultado a cada 10 s): CPU/RAM lidas a cada `BateriaCadenciaS` (5 s)
  em vez de 1 s, GPU a cada 30 s e **nada anima** (troca seca). Feito pela cadência do Lua, não por
  `UpdateDivider`: todos os measures já são `UpdateDivider=-1` e só o Lua os atualiza.
- **Retomada do sono**: o `os.clock` conta o tempo dormindo. Se entre duas leituras passou mais de
  2× a cadência (mínimo 10 s), o Lua zera os "acima desde"/"abaixo desde" de todos os anéis: um
  limiar cruzado antes do sono não vira alerta sustentado na volta (roadmap, Fase 2). Não provado com
  sono real; só a leitura do código.
- `agenda.json` só para `ambiente.animacoes` (efeitos de animação do Windows desligados = sem
  animação); measure `mLeitor` com `Recarregar()`, como os outros.

**Motion** (disparado por mudança; parado = zero redesenho):
- **entrada** (carga ou menu "Repetir a entrada"): cada anel varre do 0 ao valor pela mola `rolagem`
  (crítica, ~350 ms), escalonados em 60 ms, com o número rolando de baixo; termina em ~0,4 s. Um
  `!Redraw` só para o quadro 0 de todos (antes, a tela mostrava por um quadro metade dos anéis já
  zerados);
- **troca de faixa**: varredura do 0 de novo, cor em 400 ms (ease-out cúbico), disco interno vira
  "cookie" (âmbar, 10 lóbulos, amplitude 0,05) ou "sol" (vermelho, 0,1) pela mola `boing` e gira
  ±18° pela `espacial`;
- **troca de valor**: só os dígitos que mudaram rolam (mola `rolagem`, Container com degradê de 12 %
  em cima e embaixo, como o Relógio); o arco pula para o valor novo **sem tween** (a 1 Hz seria
  animação quase contínua);
- passo do `ActionTimer` de 30 ms (como na Agenda); `Stop 1` assim que nenhum anel anima, e o
  `Update()` religa a lista se ela acabar sozinha com anel animando.

**Custo medido** (02-03/10, Rainmeter 4.5.26, junto com Relógio, Dia e Agenda; máquina ocupada por
outras sessões):
- parado com valores fixos (`Forcar`, só leitura de measures + amostra da GPU): 1,30 % de um núcleo
  contra 1,13 % sem a Máquina (90 s cada; dentro do ruído); RAM privada sem diferença (82 MB);
- **antes da amostragem da GPU** o mesmo teste dava 3,4 a 4,5 % (+2,3 a +3,3 pontos) e +10 MB: era
  só o contador `GPU Engine` ([ARMADILHAS](ARMADILHAS.md#gpu-engine-pesa-mesmo-lido-a-cada-5-s));
- com os valores reais e a CPU oscilando entre 50 e 100 % de utility: 3,6 % (+2,5 pontos; ~35
  rolagens em 90 s). Não medido com a máquina calma;
- por transição (janela de 1 s, mediana de 16; a janela sem transição dá 16 ms): rolagem de um
  número 47 ms, troca de faixa 78 ms, entrada 156 ms.

**Variáveis** (`Variaveis.inc`, sobrescrevíveis no `Local.inc`): `Discos`, `RotuloDisco<letra>`,
`BateriaCadenciaS`, `DebugBateria` (1 = finge bateria, 0 = finge tomada, vazio = real). Limiares e
tempos ficam na tabela `FAIXAS` do `Maquina.lua`.

### Depurar

| como | o que faz |
| --- | --- |
| `!CommandMeasure mLeitor "Forcar('cpu',96)" Horizonte\Maquina` | finge o valor (`cpu`, `ram`, `gpu` em %; `C:` em GB livres); a faixa respeita os tempos sustentados. `Forcar('cpu','')` volta ao real |
| `!CommandMeasure mLeitor "ForcarBateria('1')" Horizonte\Maquina` | finge a bateria (`'0'` a tomada, `''` o real) |
| `!CommandMeasure mLeitor "Entrada()" Horizonte\Maquina` | repete a entrada |
| `!CommandMeasure mLeitor "Log(1)" Horizonte\Maquina` | liga o log de rotina sem refresh: cada leitura, cada troca de valor ("cpu 45% -> 80% (bruto 80.7, faixa 0)") e cada amostra da GPU; `Log(0)` desliga |
| `!CommandMeasure mLeitor "Contar()" Horizonte\Maquina` | grava quantos passos do `ActionTimer` rodaram desde a última chamada e quantos foram ociosos (prova de que o timer para) |
| `Discos=C:,G:,X:` no `Local.inc` + `!Refresh` | mais discos, inclusive um inexistente |

Scripts de prova (fora do repo, em `temp\fase2\maquina\`): `cap.sh` captura a janela em 900,620,
`rajada.ps1` + `folha.py` capturam e montam uma animação, `hover.ps1` põe o mouse num anel e captura,
`lado.py` monta a comparação com o protótipo, `cpu-anim.ps1` mede o custo por transição. O widget
precisa estar em `!Move 900 620` e `!ZPos 1` para as capturas.

### Simplificações em relação ao protótipo

- **Arco sem mola na troca de valor.** No HTML o arco anda pela mola `data` a cada mudança; aqui só
  na entrada e na troca de faixa (pedido da fase: nada de tween a 1 Hz).
- **Varredura com a mola `rolagem`** (crítica, ~350 ms), não a `data` (k=260, ~0,5 s), para caber nos
  360 ms pedidos.
- **Cookie/sol por Path de 72 pontos** recalculado a cada quadro (`!SetOption` do `Shape`), não por
  SVG; forma igual a olho.
- **Sem blur** nos dígitos (como no Relógio).
- **Unidade aparece antes do número na entrada** (o `%` fica no lugar enquanto o dígito sobe); no HTML
  os dois entram juntos.
- **GPU atualiza a cada 10 s**, não a 1 s: o contador custa caro (acima).

## Claude (`Horizonte\Claude`)

Cartão de 330 px lógicos (fundo `CorS`, raio 32; altura pelo Lua: 254 no caso comum) com título
"Claude", o **anel de 136 px da janela "5h" da conta ativa** à esquerda e, à direita (x=180, 126 px), as
**contas inativas** com barras 5h e 7d. Embaixo, a legenda. Lê **só**
`%LOCALAPPDATA%\claude-usage-tray\snapshot.json` (nunca `cswap`, API nem `usage.json`; roadmap § 1).
Medidas do protótipo (`.w-claude` de `design/horizonte-v1-expressivo.html`): anel com traço 9 do viewBox,
número em Display 700 a 40 px com `%` a 16,8 px e 70 %, nome da conta em Display 650 15 px, etiqueta e
linhas em Text 12,5 px, valor em Cascadia Mono, legenda em Text 13,5 px com o começo em 600 na cor do texto.

| o quê | regra |
| --- | --- |
| conta do anel | a `Active=true`; sem nenhuma, a primeira (`Get-ActiveAccount` da bandeja) |
| valor do anel | barra `Label="5h"`; sem ela, a primeira barra (`Get-SessionPct`). O número é o `Pct` como veio (arredondado); o arco usa o `Pct` limitado a 0..100 |
| cor | verde `#30A46C` < 60 ≤ âmbar `#F5A623` < 85 ≤ vermelho `#E5484D`. Disco interno na cor a 15 %: círculo, cookie (10 lóbulos, 0,05) no âmbar, sol (0,1) no vermelho. Trilho na cor a 24 % |
| zoom | de 95 em diante o arco mostra `(p-95)/5` da volta (mínimo de 8°, como a bandeja: 95 % é "início da cauda", não anel vazio) e aparece o **ponto marcador** acima do topo, na cor do arco. Sem texto |
| dado velho | `Stale=true` da bandeja: anel, disco e barras daquela conta em cinza `#747684`, número a 62 %, e a idade **sempre visível** embaixo do número ("há 21 min"); idade = `AgeS` + (agora − `savedAt`). `AgeS` nulo: "antiga" no anel e "medição antiga" na legenda. Nenhum limiar próprio de idade (o widget nunca fica cinza com o ícone colorido) |
| bandeja parada | `savedAt` com mais de `TrayParadoS` (150 s) **e** o processo `Claude Usage Tray.exe` ausente (`Measure=Process`, consultado só quando o `savedAt` passou do limite): anel cinza com a idade, e a legenda vira um **bloco cinza** "bandeja parada, dados de 00:10. Clique para abrir." O clique roda o `TrayExe` (expandido pelo Lua, conferido com `io.open`; com a bandeja viva não lança nada). Sem `TrayExe` válido, o bloco diz para ajustar no `Local.inc` |
| nome da conta | `ApelidoConta<Num>` (o `Num` do snapshot, não a posição) ou "conta N". **E-mail e `Org` nunca aparecem**, nem no log |
| legenda | "5h, produto, renova 14:59 (em 22 min)": `ResetsAt` (UTC) → hora local; outro dia ganha o dia curto ("sex 14:59"). `ResetsAt` vazio: "janela não iniciada"; já passado (snapshot velho): "renovou às 00:10". Velho: "sem medição nova há 21 min (última às 00:16)". Quebra em 282 px e o cartão cresce |
| status ≠ ok | por texto, nunca por cor: `expired` "token expirado", `relogin` "re-login preciso", `notoken` "sem credencial salva", `apikey` "conta usa API key", `offline` "API indisponível", `ratelimited` "limite da API (429)", `nodata` "sem medição recente", outro "sem dados". Na ativa vai no fim da legenda; sem barras, o anel fica "–" e a legenda diz só o status. Na inativa: com barras, vira a etiqueta no lugar de "inativa"; sem barras, uma linha de texto no lugar das barras |
| contas inativas | nome + etiqueta ("inativa", a idade se `Stale`, ou o status) e as barras **5h e 7d**: 4 px, ponta redonda, trilho `#46464E`, preenchimento mínimo de 2 px (1 % ainda aparece), cor pela mesma régua (cinza se `Stale`). Até 4 contas; passando disso, 3 e "mais N contas". O cartão cresce se a coluna passar da altura do anel |
| hover no anel | a coluna da direita troca (fade de 180 ms) para **todas as barras da ativa** (5h, 7d, Fable...), com etiqueta "ativa"; a coluna do rótulo alarga para 36 px quando há rótulo longo. Sem inativas, a coluna em repouso mostra a ativa **só com a barra do anel** (5h): a regra é "só 5h na ativa", e 7d/Fable da ativa aparecem só no hover (03/10; antes a coluna mostrava todas as barras da ativa em repouso) |
| sem snapshot | "bandeja ainda sem medição" com o anel "–" (ou o bloco "bandeja parada" se o processo não está). JSON pela metade, BOM ou arquivo sumido depois de uma leitura boa: mantém o último estado bom e grava o erro no `widget.log` |

**Como funciona.**
- `Update=1000` só como relógio: a cada `ReleituraClaudeS` (20 s) relê o snapshot (o leitor só decodifica
  se o texto mudou) e recalcula; na virada do minuto recalcula (a legenda conta minutos). O recálculo
  compara **assinaturas do que está na tela** (anel, coluna, legenda/altura), não o arquivo: a bandeja
  regrava o `savedAt` a cada minuto mesmo sem mudança. Parado, só a legenda se redesenha uma vez por
  minuto, e o `!SetOption` só sai quando o valor muda.
- `agenda.json` só para `ambiente.animacoes`; measure `mLeitor` com `Recarregar()`, como os outros.
- Meters: `Anel` (Shape: disco, trilho, indicador, ponto), `Masc` + `DS/DE1..3` (dígitos que rolam),
  `Uni`, `Cap` (idade), `Hit` (hover), `Nm/Tg1..4` e `Rl/Rb/Rv1..8` (coluna), `Leg`, `Bloco`/`BlocoTxt`.
  Grupos `GA` (anel), `GP` (coluna), `GL` (cartão e legenda): o passo da animação só atualiza o grupo que
  mexe.

**Motion** (disparado por mudança; parado = zero redesenho; tudo em ~0,42 s):
- **valor**: o arco anda do valor antigo ao novo pela mola `dado` (crítica, k=260, eps 0,01: ~0,41 s),
  **sem overshoot** (o dado não quica); dígitos que mudaram rolam (mola `rolagem`, Container com degradê);
- **troca de faixa**: cor em 400 ms (ease-out), o disco vira cookie/sol pela mola `boing` (a **forma**
  quica) e gira ±18° pela `espacial`;
- **travessia do 95** (entrar ou sair do zoom): o arco varre do 0, porque a escala mudou; o ponto cresce
  ou some pela `boing`;
- **barras**: mesma mola do arco quando o valor muda; **entrada**: anel e barras varrem do 0 e os dígitos
  sobem (menu "Repetir a entrada").

**Custo medido** (03/10, Rainmeter 4.5.26, junto com Relógio, Dia, Agenda e Máquina; máquina com ~76 %
de CPU por outras sessões, o que deixa o ruído alto):
- parado: dentro do ruído (60 s com o Claude 2,4 % e 4,9 % de um núcleo; sem ele 5,4 % e 5,4 %; RAM
  privada 84 a 87 MB nos dois casos). Prova direta: em 75 s parado, **0 passos** do `ActionTimer` e um
  único recálculo com redesenho (a virada do minuto);
- por transição (janela de 1 s, mediana): troca de faixa 62 → 88 47 ms; travessia do zoom 88 → 97
  63 ms; entrada 125 ms. A janela **sem** transição deu os mesmos 47 ms (a Máquina rolando números com a
  CPU alta): o custo próprio da troca fica abaixo do que essa medição separa.

**Variáveis** (`Variaveis.inc`, sobrescrevíveis no `Local.inc`): `ReleituraClaudeS` (20), `TrayParadoS`
(150), `TrayExe` (padrão `%USERPROFILE%\claude-usage-tray\Claude Usage Tray.exe`; sempre com variável
de ambiente, o caminho real desta máquina fica no `Local.inc`), `DebugTray`, `ApelidoConta<N>`.

### Depurar

| como | o que faz |
| --- | --- |
| `!SetVariable DebugSnapshot "<json>" Horizonte\Claude` e `!CommandMeasure mLeitor "Recarregar()" Horizonte\Claude` | lê um snapshot de teste. Para voltar ao real, `!Refresh` ([ARMADILHAS](ARMADILHAS.md#argumento-vazio-some-no-caminho-do-powershell)) |
| `!CommandMeasure mLeitor "ForcarTray('0')" Horizonte\Claude` | finge a bandeja fechada (`'1'` aberta, `''` o real); `DebugTray=0` no `Local.inc` faz o mesmo desde a carga |
| `!SetOption mTray ProcessName "NaoExiste.exe" Horizonte\Claude` | prova o caminho real do "processo ausente" sem fechar a bandeja |
| `!CommandMeasure mLeitor "Esquecer()" Horizonte\Claude` | esquece o último estado bom e relê (prova "sem snapshot desde o início") |
| `!CommandMeasure mLeitor "Entrada()" Horizonte\Claude` | repete a entrada |
| `!CommandMeasure mLeitor "Log(1)" Horizonte\Claude` e `"Contar()"` | log de rotina sem refresh; passos do `ActionTimer` desde a última chamada |

Fixtures e scripts de prova (fora do repo, em `temp\fase2\claude\`): `gerar.py` gera `snap-*.json`
relativos a agora (p31 a p100, velho, velho sem idade, janela não iniciada, renovou, 429, offline, inativa
expirada/velha, sem ativa, só uma conta, muitas contas, parado, vazio, pela metade; e-mails em
`example.invalid`); `estado.sh nome` força e captura; `rajada.ps1` + `grade.py` capturam a animação;
`clicar.ps1` move/clica o mouse; `cpu.ps1`/`cpu-anim.ps1` medem o custo; `capbase.ps1` captura os outros
widgets. O widget precisa estar em `!Move 900 150` e `!ZPos 1` para as capturas.

### Simplificações em relação ao protótipo

- **Barras no gesto da bandeja**, não no do protótipo: 4 px com trilho `#46464E` (pedido da fase), sem a
  folga de 4 px nem o ponto de parada; e as barras de uma conta só ficam cinza se **aquela** conta estiver
  `Stale` (no protótipo, a cena "velho" acinzenta tudo).
- **Zoom também com dado velho**: o protótipo desliga o zoom quando está velho; a bandeja não (o ponto
  marca a escala, a cor diz que é velho). Segue a bandeja, que é o contrato.
- **Mola do arco** com eps 0,01 (~0,41 s) para caber nos 500 ms; a cauda cortada é 1 % do trajeto.
- **Sem blur** nos dígitos e na troca do hover (o Rainmeter não tem filtro); o hover é só fade de alfa.
- **Legenda sem `text-wrap: balance`**: quebra onde couber (282 px).
- **Ponto do zoom** acima do topo do anel, como o protótipo; a bandeja, a 16 px, põe o ponto no centro.
- Cookie/sol por `Path` de 72 pontos recalculado por quadro (o mesmo do `Maquina.lua`, agora em
  `anel.lua`).
