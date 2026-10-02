---
tipo: roadmap
status: aprovado o rumo (02/10); nada executado no skin ainda
data: 2026-10-02
atualizado: 2026-10-02 (decisões do Gabriel aplicadas, § 6)
origem: sessão 528c8c6b (pedido do Gabriel: "quais melhorias você faria… quero ideias")
---

# Horizonte: do widget "sem graça" ao painel de bordo do desktop

> **Para quem nunca viu a conversa.** O Gabriel usa um skin Rainmeter
> (`Documents\Rainmeter\Skins\GoogleCalendar`) com relógio e os próximos eventos de
> três agendas Google. Ele "serve, mas é sem graça". O código está desorganizado.
> Ele pediu ideias com liberdade total para reconstruir, inclusive trocando de
> tecnologia. Também pediu anéis estilo o ícone do
> [claude-usage-tray](../../claude-usage-tray/README.md) com CPU %, RAM %, GB
> livres do SSD e os limites das contas Claude.
>
> **Correção de premissa:** "Cloud Usage" é o `claude-usage-tray` (Claude, não
> cloud). O pedido literal "contas cloud" também cabe: G:, H: e I: são o Google
> Drive para desktop (`GoogleDriveFS` rodando). Este plano atende os dois.
>
> **Como foi feito:** workflow de 16 agentes:
> - auditoria linha a linha do skin;
> - mapa do contrato de dados do tray;
> - 5 pesquisas de tecnologia com fonte;
> - 4 visões independentes (evolutiva, web no desktop, app próprio, radical);
> - 3 juízes por lente (utilidade, viabilidade, encantamento);
> - síntese;
> - crítico de completude.
>
> A matéria-prima dos agentes não foi versionada. O que importa está aqui.

**Mockup visual:**
[`../horizonte-visao-2026-10-02.html`](../horizonte-visao-2026-10-02.html). É
standalone e abre direto no navegador.

> **Decisão de forma (Gabriel, 02/10):** não é um widget único. É um **pacote
> novo** (suite Rainmeter `Horizonte`, distribuída como `.rmskin`) com **vários
> widgets separados**. Cada um tem config própria, posição e liga/desliga
> independentes, e todos dividem o mesmo `@Resources` (tokens, Lua, estilos). O
> skin GoogleCalendar antigo é aposentado quando o pacote cobrir a agenda. O
> mapa dos widgets está em [§ 3](#3-arquitetura). Onde este texto fala em
> "painel", leia "o conjunto de widgets".
>
> **O repositório é público** (conta pessoal `dosxnjos`). Valem as regras de
> [§ 3.1](#31-repositório-público-o-que-nunca-entra).

---

## 0. Antes de sonhar: o que está quebrado hoje (verificado)

| # | achado | evidência | impacto |
| --- | --- | --- | --- |
| 1 | **Uma agenda inteira sumiu calada.** `GoogleCalendar2` responde **HTTP 404** (página HTML "Error 404") | feed baixado em 02/10; `Reader.lua` marca "Invalid Feed Format" e o merge (`Update()`, linhas 87-99) sobrescreve `Feeds[1]`, apagando o erro | compromissos dessa agenda não aparecem e nada avisa. **Causa:** o endereço tinha expirado; o Gabriel regerou em 02/10. O defeito de esconder o erro continua no código |
| 2 | **Eventos recorrentes nunca aparecem** (daily, semanal, aniversário) | o `.ics` do Google não expande RRULE; `?singleevents=true&orderby=…` são parâmetros da API v3, ignorados no `.ics` (mesmo tamanho com e sem). Das 43 séries do GoogleCalendar1, 6 estão ativas e são todas descartadas pelo filtro `DateEnd > now` (`Reader.lua:89, :291`) | a reunião mais frequente da semana é a que o widget não mostra |
| 3 | **Rede desproporcional:** ~363 KB/min ≈ **520 MB/dia** ≈ 15 GB/mês para 8 linhas | 3 WebParser a cada 60 s (`Gcalendar.ini:180-208`). O calendário de **feriados** (102 KB) também é baixado a cada minuto. O `DTSTAMP` muda a cada download, então `Raw ~= Feeds[f].Raw` (`:125`) sempre reprocessa as 865 VEVENTs | rede e CPU gastos à toa; ruim em 4G/notebook |
| 4 | **URLs secretas em texto puro** no `[Variables]` do `Gcalendar.ini` | `private-…/basic.ics` | quem lê o arquivo lê a agenda; **regerar** os endereços |
| 5 | Um feed vazio trava tudo em "Loading…" | `Update()` retorna cedo se qualquer WebParser estiver vazio (`Reader.lua:40-45`) | uma queda de rede apaga o widget |
| 6 | "Tomorrow" erra na virada do mês | comparação por dia do mês (`Reader.lua:~470`) | 30/09 → 01/10 não vira "amanhã" |
| 7 | Interface metade inglês, metade português; mojibake (`TAMBÃ‰M`) | `.ini` em UTF-8 sem BOM, lido como ANSI | qualquer acento novo quebra |
| 8 | Lixo de debug e cópia-cola | `; <-- ADICIONE TAMBÉM` **não é comentário** no meio do valor (funciona por acaso); `LeftMouseUpAction` duplicado em 6 itens; `SolidColor=255,0,0,1` só nos itens 6-8 (clique inconsistente); `NumOfItems=15` para 8 meters | manutenção frágil |
| 9 | Código e assets mortos | `Tabs.lua`, `MeasureActive1`, ~25 variáveis do Enigma, as 8 PNGs de `@Resources\Images`, módulos History/EventFile | ruído para quem for mexer |
| 10 | Sem escala de DPI | o Windows está a 125% (`AppliedDPI=120`) e o Rainmeter 4.5 desenha em px físicos | texto pequeno e borrado em monitor de DPI diferente |
| 11 | Fundo some na base | gradiente 210→0 (`:220-224`): o fim da lista fica sem contraste em papel de parede claro | legibilidade |

**O que presta e sobrevive como ideia:**
- várias agendas numa lista com cor por agenda;
- o relógio grande com a data embaixo;
- o hover que clareia;
- o clique que abre a semana no Google Agenda;
- agrupar a série recorrente numa linha com ♻;
- janela de 14 dias;
- posição fixa no desktop (`AlwaysOnTop=-2`, sobrevive ao Win+D);
- update dirigido por evento (`UpdateDivider -1` + `FinishAction`).

Crédito ao Enigma GCal (Kaelri / eclectic-tech, CC BY-NC-SA). A reescrita não
reaproveita código, mas mantém o crédito de cortesia.

### Varredura do Rainmeter em si (o "app", não só o skin)

- **Versão 4.5.26** (maio/2026), ativa. Plugins nativos úteis já instalados:
  `UsageMonitor` (CPU/GPU/processo), `PowerPlugin` (bateria), `RunCommand`,
  `ActionTimer` (animação), `FolderInfo`, `CoreTemp`, `Process`.
- **`illustro` (6 skins) está instalado e inativo:** pode sair.
- **`@Vault\Plugins` está vazio.**
- **`HardwareAcceleration` não está definido no `Rainmeter.ini`.** Ligar o
  Direct2D por hardware tende a melhorar Shape/anti-alias. *A provar:* medir
  CPU/RAM antes e depois.
- **Não há layout salvo.** Salvar um layout permite voltar ao estado de hoje
  num clique durante a migração.
- **Há um terceiro app de desktop na mesma família:** `claude-switch-gui`,
  aberto pelo menu do tray. Num app próprio futuro, ele seria absorvido junto.

---

## 1. O sonho (norte): o "painel de bordo" do Gabriel

Hoje são três coisas desconexas: o skin do Rainmeter, o ícone de bandeja do
Claude e o `claude-switch-gui`. O norte é **um produto só, com quatro
superfícies**, todas lendo o mesmo estado:

1. **Painel no desktop** (o que aparece no Win+D). Mostra:
   - relógio;
   - o cartão **AGORA / PRÓXIMO / LIVRE**, que nunca fica vazio;
   - a **linha do dia** com a agulha do agora;
   - a lista de 14 dias com os vãos livres escritos;
   - os **instrumentos**: anéis de CPU, RAM, SSD e Claude, mais as cotas do
     Drive.
2. **Avisos fora do desktop.** Um cartão discreto 5 min antes da reunião, com o
   botão **Entrar**. O atalho **Ctrl+Alt+M** entra na próxima reunião de
   qualquer lugar.
3. **Modo expandido** (atalho), um console de 960×600 com três áreas:
   - a semana em timeline vertical;
   - as contas Claude completas;
   - sparklines de 1 h da máquina.

   Inclui uma paleta Ctrl+K: "meet", "agenda", "trocar pessoal".
4. **Bandeja.** O anel do Claude de hoje passa a ser só mais uma superfície do
   mesmo app, que absorve `claude-usage-tray` e `claude-switch-gui`.

### Os momentos que justificam o produto

- **A daily volta a aparecer.** Recorrência expandida de verdade, com ♻ e a
  série colapsada numa linha só ("Daily produto ♻ seg–sex", mostrando só a
  próxima). Sem isso, uma daily ocupa a lista inteira.
- **O dia numa olhada.** A agulha âmbar anda pela régua 07–21h. Os buracos
  aparecem escritos: "livre 16:00–18:00 · 2h", o lugar óbvio para uma sessão
  longa de Claude Code.
- **O cartão muda de papel sozinho:**
  - "EM 23 MIN";
  - âmbar aos 15 min;
  - o botão Meet acende aos 10 min;
  - "AGORA · termina 15:30" com a barra enchendo;
  - "dia livre a partir de 17:30 · amanhã 09:00 Daily".
- **Combustível do Claude.** O anel fala a língua da bandeja (mesmas cores,
  zoom 95→100). A partir de 60% ele responde "posso abrir mais uma sessão?":
  `~acaba 14:40 · ♻ 14:59` (hora local: o `ResetsAt` vem em UTC). Se não der tempo: "dados tem folga (23%): troque
  pela bandeja".
- **Reset do Claude dentro da linha do dia.** Um tick ♻ às 14:59 aparece na
  régua. Se o reset cai num vão livre, o vão ganha a dica "sessão longa de
  Claude cabe aqui". Agenda e limite viram um sinal só.
- **Disco em dias de cobertura,** como estoque: "80 GB livres · −0,4 GB/dia →
  ~200 dias". O hover mostra o **estoque parado**: "Downloads 12 GB sem uso há
  60+ dias", via `FolderInfo`. É o raciocínio de giro de estoque aplicado ao SSD.
- **Cotas do Drive como anéis/barras:** "Drive corporativo 26/100 GB livres". O
  rótulo do volume tem o e-mail, então o painel **sempre** mostra um apelido.
- **Quem está pesando:** hover no anel da CPU mostra "chrome 18%"; no da RAM,
  "maior: msedge 1,9 GB".
- **Erro que fala.** Um ponto vermelho com a mensagem "GoogleCalendar2: 404
  desde 02/10, regere o endereço secreto". Acaba o sumiço calado.
- **Modo privado automático em reunião.** No AGORA com link de Meet (ou com o
  Teams ativo), os títulos viram "Reunião" e as contas viram "Conta 1/2" até o
  fim do evento. O cadeado no rodapé é o override manual.
- **Feriado como contexto,** não como linha: "sexta, 2 de outubro · feriado
  seg 12/10".
- **Bateria.** O painel economiza sozinho (CPU a cada 5 s, sem animação) e
  mostra "⚡ 64% · 3h10".
- **Fim de expediente,** no tooltip do relógio depois das 18h: "4 reuniões ·
  3h12 em reunião".

### Identidade visual (própria, nunca a do tray nem de outro produto)

Metáfora: **céu noturno com o sol no horizonte**. Fundo frio e escuro e **um
único acento quente, que marca o AGORA**.

| token | hex | uso |
| --- | --- | --- |
| Base | `#0E1013` a 88% | painel, raio 16 |
| Superfície | branco a 4% | cartão herói, hover |
| Linha | `#262A31` | trilhos, divisória |
| Texto | `#EEF0F3` | relógio, títulos |
| TextoSec | `#B4BAC5` | data, horários (≈7,2:1 no pior caso) |
| TextoTer | `#8E95A3` | rótulos ≥11 px, **nunca dentro de cartão** (lá cai para ≈4,15:1, abaixo do AA) |
| **Agora** | `#FFC27A` | agulha, urgência <15 min, halo |
| Instrumento | `#C5CEDB` | anéis de sistema em repouso (neutros; cor só quando pedem atenção) |
| Agenda1 / Agenda2 / Feriados | `#7AA2F7` / `#C3A6FF` / `#5FD0B5` | cor por agenda |
| Alerta / Crítico | `#F5A623` / `#E5484D` | semântica |
| ClaudeOk / Velho | `#30A46C` / `#747684` | **exclusivas do Claude**, contrato herdado do tray |

Tipografia, toda nativa do Windows 11:
- **Segoe UI Variable Display 600** no relógio;
- **Segoe UI Variable Text** no corpo;
- **Cascadia Mono** nas horas em coluna, para a lista não "dançar";
- **Segoe Fluent Icons** nos ícones.

Movimento:
- **zero animação contínua**;
- varredura dos anéis de 360 ms ao carregar;
- pulso de 3× na transição para AGORA;
- o reset do Claude recolhe o arco uma vez.

Nada pisca, nada respira em loop.

**Regra dos anéis Claude (inviolável, vem do tray):**
- anel = janela **5h da conta ativa**, nunca a pior janela;
- verde <60 ≤ âmbar <85 ≤ vermelho;
- zoom a partir de 95% (a faixa 95→100 vira a volta inteira), com um ponto
  marcando a troca de escala;
- dado velho = cinza com a idade sempre visível, **e só quando o tray diz
  `Stale`**. Um limiar próprio de idade deixaria o widget cinza com o ícone
  colorido.

O widget **só lê** o `snapshot.json` da bandeja: nunca chama `cswap`, a API da
Anthropic nem o `usage.json` do cswap. Uma segunda engine dividiria o orçamento
por token e derrubaria as duas em 429 (invariante nº 1 do tray).

---

## 2. Tecnologia: onde o sonho roda

A pesquisa (com fontes, 28 candidatos) comparou os hospedeiros contra quatro
requisitos duros: **sobreviver ao Win+D**, aceitar clique, ler arquivo local e
ter dado de disco/CPU nativo.

| hospedeiro | veredito | por quê |
| --- | --- | --- |
| **Rainmeter 4.5 (Shape + Lua)** | **base agora** | único que cumpre os 4 requisitos hoje, com ~20 MB medidos. Perde blur real, gradiente cônico e letter-spacing |
| Rainmeter + plugin WebView2 | plano B visual | HTML/CSS dentro do Rainmeter, mantendo o Win+D. Mas tem 1 release, 11 estrelas e issue #17 aberta; estima 80–170 MB. Portão: ≤150 MB e <1% de CPU em 24 h |
| **App próprio Tauri 2** | **norte**, com portão | é o que entrega as 4 superfícies e absorve o tray. Custo: toolchain Rust/Node/MSVC de 5–8 GB, +40–130 MB de RAM. **A provar:** ficar visível no Win+D sem truque frágil de WorkerW/HWND_BOTTOM, que não tem fonte confiável no build 26200 |
| Zebar / YASB | descartado | sem click-through (Zebar #243), barra só no topo (YASB), Zebar sem release desde 03/2026 |
| Seelen UI | descartado | Win+D esconde os widgets no 24H2 (#1674); 350–1.290 MB |
| Lively Wallpaper | descartado | vira o papel de parede; sem disco nem arquivo arbitrário |
| Widgets Board do Windows | descartado | não fica no desktop; Adaptive Cards não desenha anel |
| WinUI 3 / Electron | descartado | acrylic vira sólido em janela inativa (o estado normal de um widget) / RAM 2–5× a do Tauri sem ganho visual |

**A jogada que faz nada se perder:** separar **dados** de **desenho** por dois
contratos em JSON.
- `agenda.json`, gerado pelo helper `agenda-sync`;
- `snapshot.json`, gerado pelo tray.

O Rainmeter é só o **primeiro renderizador**. Se ele virar teto, o app próprio
lê os **mesmos arquivos** e nada do trabalho de dados se joga fora.

---

## 3. Arquitetura

### O pacote: uma suite, vários widgets

Cada widget é uma **config Rainmeter própria**: arrasta, liga e desliga sozinho e
pode ir para outro monitor. Todos dividem o mesmo `@Resources`. Um **layout**
`Horizonte` (do próprio Rainmeter) guarda a arrumação padrão e volta a ela num
clique.

| widget (config) | mostra | lê | posição padrão |
| --- | --- | --- | --- |
| `Horizonte\Relogio` | hora, data em pt-BR, chip do próximo feriado | measure `Time` + `agenda.json` (só `proximoFeriado`) | X=0, Y=197: **onde o skin antigo está hoje** |
| `Horizonte\Dia` | cartão agora/próximo/livre + linha do dia | `agenda.json` | logo abaixo do Relógio |
| `Horizonte\Agenda` | lista de 14 dias, vãos livres, pontos de saúde das fontes, frescor | `agenda.json` | abaixo do Dia (a mesma coluna de hoje) |
| `Horizonte\Maquina` | anéis de CPU, RAM, GPU e C: (GB livres), barras das cotas do Drive | measures nativos | livre; o Gabriel decide depois |
| `Horizonte\Claude` | anel 5h da conta ativa + barras das inativas | `snapshot.json` do tray | livre; o Gabriel decide depois |
| `Horizonte\Aviso` | cartão T−5 com Entrar | ativado pelo `Dia` | canto inferior direito, só quando há reunião |
| `Horizonte\Fio` | linha do dia sobre a barra de tarefas | variáveis empurradas pelo `Dia` | experimento (fase 4) |

O que muda por ter vários widgets:
- **Cada widget tem a própria instância de Lua.** `Dia` e `Agenda` leem o
  `agenda.json` cada um (15 KB, só quando o `generatedAt` muda). O custo é
  desprezível e um não trava o outro.
- **O helper avisa os widgets da agenda** com um bang por config:
  `[!CommandMeasure mLeitor "Recarregar()" "Horizonte\Dia"]`, e o mesmo para
  `Horizonte\Agenda` e `Horizonte\Relogio`. Bang para config descarregada é
  ignorado, sem erro.
- **O orçamento de altura some.** Os 648 px de antes cabiam com 10 px de folga;
  separado, cada bloco vai para onde couber, inclusive no segundo monitor.
- **Estilo único:** `Tokens.inc` e `Estilos.inc` são incluídos por todos. Mudar
  uma cor muda a suite inteira.
- **Distribuição:** `.rmskin` gerado do repo e anexado como release no GitHub.
  O `instalar.ps1` cuida do que o `.rmskin` não faz: venv do helper, tarefa
  agendada e atalho.

```
C:\Dev\horizonte\                 repo público, conta pessoal dosxnjos
  skin\  ── junction ──> Documents\Rainmeter\Skins\Horizonte
    Relogio\Relogio.ini           cada .ini: UTF-16 LE BOM; AlwaysOnTop=-2; só @Include
    Dia\Dia.ini
    Agenda\Agenda.ini
    Maquina\Maquina.ini
    Claude\Claude.ini
    Aviso\Aviso.ini               AlwaysOnTop=1, ativado e desativado pelo Dia (fase 3)
    Fio\Fio.ini                   experimento (fase 4)
    @Resources\Variaveis.inc      Scale (AppliedDPI/96), MaxItems, Privado, apelidos…
    @Resources\Tokens.inc         paleta e fontes
    @Resources\Estilos.inc        MeterStyles comuns (cartão, anel, linha, texto)
    @Resources\Lua\               comum.lua (tempo, json, arquivo) + agenda, claude, aneis, anim, json.lua (MIT)
  layouts\Horizonte\Rainmeter.ini arrumação padrão da suite
  agenda_sync\                    Python 3.14 + uv: httpx+truststore, icalendar,
                                  recurring-ical-events, keyring, tzdata
  tests\fixtures\*.ics            só sintéticas, nunca o .ics real
  instalar.ps1 / desinstalar.ps1  venv, junction (fallback: cópia), tarefa agendada, atalho
  config.example.toml             modelo versionado; o config.toml real fica fora do repo
%LOCALAPPDATA%\Horizonte\         config.toml, agenda.json, cache, disco.tsv, sync.log (nunca no repo)
Gerenciador de Credenciais        Horizonte/pessoal, Horizonte/corporativo (URLs secretas)
```

### 3.1 Repositório público: o que nunca entra

O repo é público e qualquer pessoa lê o histórico inteiro. Um segredo commitado
uma vez fica lá mesmo se for apagado depois.

**Nunca entra:**
- URL de agenda (`calendar/ical`, `private-`);
- e-mail (inclusive dentro do campo `Org` do snapshot);
- título real de compromisso;
- `config.toml`, `agenda.json`, `snapshot.json`, `sync.log` ou qualquer cópia
  deles;
- caminho com o nome do usuário do Windows (usar `%USERPROFILE%`,
  `%LOCALAPPDATA%`, `#SKINSPATH#`);
- nome de colega ou da empresa em exemplo, mockup ou fixture.

**Como se garante:**
- `.gitignore` cobre `config.toml`, `*.json` fora de `tests/`, `temp/` e
  `*.log`;
- fixtures são sintéticas, escritas à mão;
- antes de todo push: `tools/varrer-segredos.sh` busca padrões genéricos
  (`private-`, `calendar/ical`, `@gmail`, `Organization`, `Users\`) e mais os
  termos de `.segredos-locais`. Esse arquivo fica fora do repo e guarda domínios
  e nomes reais, que não podem virar padrão público. Na fase 1 o script vira um
  hook `pre-commit`;
- **licença MIT** (decisão técnica, reversível enquanto ninguém contribuir).
  O `json.lua` é MIT, então combina. Crédito de cortesia ao Enigma GCal no
  README.

**Três canais, um dono cada:**
1. **Máquina.** Measures nativos a 1 s: `UsageMonitor` "% Processor Utility",
   `PhysicalMemory` e `FreeDiskSpace` de C:, G:, H: e I:. Há um `!Redraw` só
   quando o valor arredondado muda: CPU de 5 em 5 pontos, senão redesenharia a
   1 Hz para sempre.
2. **Agenda.** O `agenda-sync` roda pela tarefa agendada, sem processo
   residente. Gatilhos: logon, a cada 10 min, rede disponível e **retomada do
   sono**. A cada execução ele:
   - valida `BEGIN:VCALENDAR` **e** `END:VCALENDAR` (download truncado não
     passa);
   - faz hash sem `DTSTAMP`, para não reprocessar o que não mudou;
   - expande RRULE/EXDATE/RECURRENCE-ID;
   - filtra `STATUS:CANCELLED`;
   - grava de forma atômica.

   Formato do `agenda.json`:
   - horas em **epoch UTC** (o Lua formata com o fuso do Windows);
   - dia inteiro como **data**, nunca ISO com offset, que cairia às 21:00 do dia
     anterior;
   - nunca contém URL nem e-mail.
3. **Claude.** O tray continua sendo o coletor único. O painel lê o
   `snapshot.json` a cada 20 s e:
   - tolera o BOM;
   - se a leitura pegar o arquivo pela metade (a escrita do tray ainda não é
     atômica), mantém o último estado bom;
   - distingue "tray vivo sem medição nova" de "tray morto" pelo plugin
     `Process`.

**Credenciais:**
- **fase 0:** as URLs saem do skin para
  `%APPDATA%\Rainmeter\Secrets\GoogleCalendar.inc`;
- **da fase 1 em diante:** ficam só no Gerenciador de Credenciais, gravadas pelo
  próprio Gabriel com `agenda-sync configurar` (entrada oculta). A agenda
  `feriados` é pública e a URL dela fica no `config.toml`;
- **backup opcional** num cofre de segredos pessoal.

**Apelidos** (Gabriel, 02/10). Ficam no `config.toml` local:

| fonte | apelido | cor |
| --- | --- | --- |
| GoogleCalendar1 | `pessoal` | Agenda1 `#7AA2F7` |
| GoogleCalendar2 | `corporativo` | Agenda2 `#C3A6FF` |
| GoogleCalendar3 | `feriados` | Feriados `#5FD0B5` |

O código só conhece os apelidos.

---

## 4. Fases (cada uma entrega algo usável sozinha)

### Fase 0 · Estancar o skin de hoje (1 a 2 h de agente)

**Escopo reduzido em 02/10.** O pacote novo substitui o skin antigo, então polir
o skin antigo (pt-BR, visual, limpeza de código) seria trabalho jogado fora. Fica
só o que vale até o pacote chegar. Backup `Gcalendar.ini.bak` antes de mexer.

**Rede** (o ganho grande, 3 linhas)
- `UpdateRate=900` (15 min) nas duas agendas;
- `86400` nos feriados;
- tirar os parâmetros `?singleevents…`, que o `.ics` ignora.

**Segredos**
- URLs para `%APPDATA%\Rainmeter\Secrets\GoogleCalendar.inc` via `@Include`.
- O endereço `corporativo` **já foi regerado pelo Gabriel em 02/10**. O 404
  vinha de um endereço expirado.
- O `pessoal` nunca saiu desta máquina; regerar é opcional.

**Robustez mínima**
- `Update()` não trava em "Loading…" com um feed vazio.

**Rainmeter**
- salvar o layout atual (`GoogleCalendar antigo`) para poder voltar;
- remover o illustro;
- testar `HardwareAcceleration=1`, medindo CPU e RAM antes e depois.

**Prova:**
- a rede do `Rainmeter.exe` cai de ~363 KB/min para **~17,5 KB/min**
  (≈25 MB/dia, −95%), medida em 1 h;
- buscar `private-` no `Gcalendar.ini` não acha nada;
- o `corporativo` volta a mostrar eventos, conferido contra o Google Agenda.

### Fase 1 · Agenda de verdade (1 a 1,5 dia)

1. **Spike de 30 min:** `io.open` + `os.getenv('LOCALAPPDATA')` + `json.lua`
   dentro do Lua do Rainmeter 4.5.26. Plano B: WebParser `file://` + um
   `agenda.tsv`.
2. **`agenda-sync`:** `sync`, `configurar`, `status`, `entrar`, com:
   - `tzdata` no venv, sem o qual o `zoneinfo` falha no Windows;
   - `truststore` e o proxy do sistema, para funcionar na rede corporativa;
   - portal cativo tratado como offline, não como erro de formato.
3. **Tarefa agendada:**
   - **`AllowStartIfOnBatteries` + `DontStopIfGoingOnBatteries` +
     `StartWhenAvailable`**. Sem isso, **na bateria a agenda nunca
     sincroniza**, porque o padrão do Windows desliga;
   - na bateria, cadência de 30 min.
4. **Ponte para o skin antigo:** o helper grava também um `agenda-legado.inc` e
   o skin de hoje troca os 3 WebParser por `@Include`. **As recorrências voltam
   antes de qualquer redesenho.**

**Prova:**
- as 6 séries ativas aparecem nas datas certas, conferidas contra a visão de 14
  dias do Google;
- o pytest cobre EXDATE, ocorrência remarcada, cancelada, dia inteiro com UNTIL
  e a virada de mês;
- Wi-Fi off → status offline, e a agenda continua na tela.

### Fase 2 · Pacote Horizonte: os widgets (2 a 3 dias)

A suite nova, conforme o mockup e o mapa de [§ 3](#3-arquitetura). Ordem de
construção:
1. `@Resources` comum (tokens, estilos, `comum.lua`);
2. `Relogio`;
3. `Dia` + `Agenda`;
4. `Maquina`;
5. `Claude`;
6. o layout `Horizonte`.

Cada widget fica utilizável sozinho assim que fica pronto. Antes de construir,
quatro spikes de 5 min:
- **Escala:** `Scale` por Registry measure (`AppliedDPI/96`).
- **Fonte:** a fórmula `FontSize = px × 0,75 × Scale` (*a provar*: pode escalar
  duas vezes).
- **CPU:** o contador "% Processor Utility" em nome inglês e localizado, com
  fallback `Measure=CPU` e o tooltip "aprox.".
- **GPU:** anel com `UsageMonitor Alias=GPU`.

Depois, os widgets:

**Anéis**
- CPU, RAM, C: em GB livres e GPU, com histerese:
  - CPU âmbar ≥85% sustentado por 10 s;
  - C: âmbar <15% livre.
- Cotas do Drive como barras finas, com apelido.

**Claude**
- só leitor do snapshot;
- contas inativas com 5h/7d;
- estados de dado velho só pelo `Stale` do tray.

**Comportamento**
- modo privado;
- menu de contexto;
- todos os estados (vazio, offline, 404, tray parado, limite estourando);
- **retomada do sono:** salto de relógio > 2× Update suprime alertas de idade
  por ~3 min.

**Na saída**
- o skin GoogleCalendar é **descarregado, não apagado**;
- o `Relogio`, o `Dia` e a `Agenda` ocupam a coluna onde ele estava;
- entram docs: README, ARMADILHAS, CONTRATOS;
- `.rmskin` da versão 0.1 como release no GitHub.

**Prova:**
- captura sobre papel de parede branco e preto;
- anéis de CPU/RAM a ±3 pontos do Gerenciador de Tarefas;
- o anel Claude bate com o ícone da bandeja nas fixtures 62/88/97/100% e Stale;
- Rainmeter ≤30 MB de RAM privada;
- sobrevive ao Win+D;
- funciona com o notebook desencaixado do monitor externo.

### Fase 2b · Contrato v1 do `snapshot.json` (no repo do tray, 1 dia, em paralelo)

- escrita atômica: tmp + `[IO.File]::Replace`;
- `schemaVersion`, `cadenceS`, `MeasuredAt` por conta;
- `limits {amber:60, red:85, tailFrom:95}`;
- **alias** do cswap: nunca e-mail. **O campo `Org` contém o e-mail e nunca é
  exibido**;
- `lastAttemptAt` / `lastError`.

A invariante nº 5 do `CLAUDE.md` do tray é atualizada junto.

### Fase 3 · Fora do desktop (1,5 a 2 dias)

- **Aviso T−5** com Entrar/Adiar. Ele:
  - some em 60 s;
  - não aparece para reunião começada há mais de 5 min (caso de quem acorda o
    notebook);
  - *a provar:* não rouba o foco.
- **Ctrl+Alt+M** por `.lnk` no Menu Iniciar. *A provar*; plano B: AutoHotkey, por
  decisão do Gabriel.
- Hover "quem está pesando".
- Disco em dias de cobertura e estoque parado de Downloads.
- Autonomia do Claude, calculada sobre **valores diferentes**, não só leituras
  diferentes: com `Pct` inteiro, a regressão vira degrau.
- Reset ♻ na linha do dia.
- Perfil de bateria.

### Fase 4 · Experimentos com critério de saída (1 dia, item a item)

- **Fio do dia:** linha de 4 px sobre a barra de tarefas, só com degraus de
  estado. Sai se aparecer sobre vídeo em tela cheia ou apresentação e isso
  incomodar em 1 semana.
- **Vidro FrostBehind:** sai se virar cor sólida com a janela inativa.
- **Fundo amostrado do papel de parede.**

### Fase 5 · O norte: app próprio (portão explícito)

**Abre quando** qualquer um destes acontecer:
- o teto visual do Rainmeter incomodar depois de 2 semanas de painel novo;
- for pedido o modo expandido ou a paleta Ctrl+K.

**Pré-requisito:** spike de 1 dia que **prove** Tauri 2 visível no Win+D no
build 26200 e ≤150 MB ociosos.

O app lê os mesmos `agenda.json`/`snapshot.json`. Depois, absorve a bandeja (com
o mesmo mutex do tray) e o `claude-switch-gui`.

Opcional nesta fase: **Calendar API v3** com OAuth de app instalado, que traz:
- cores reais;
- foco e ausência;
- RSVP exato;
- <1 MB/dia.

---

## 5. Decisões técnicas (tomadas, reversíveis)

| decisão | confiança | o que reverteria |
| --- | --- | --- |
| Rainmeter como 1º renderizador; app próprio como norte com portão | média-alta | WebView2 plugin medir ≤80 MB e resolver a #17; ou spike Tauri provar Win+D |
| Recorrência num helper Python, nunca em Lua | alta | Python barrado por antivírus → mesmo contrato em PowerShell 7 + Ical.Net |
| Contratos JSON neutros entre dados e desenho | alta | nenhuma prevista |
| Anéis de sistema neutros (cor só com histerese) | média | o Gabriel preferir cor sempre |
| Ponto do zoom 95 por fora do anel, porque o centro tem o número | média | teste visual mostrando que o número sozinho já separa 98 de 100 |

## 6. Decisões do Gabriel

**Respondidas em 02/10/2026:**

| pergunta | resposta |
| --- | --- |
| Endereços secretos | O `corporativo` estava expirado (era o 404) e ele já regerou. O `pessoal` fica como está. |
| De quem é cada agenda | 1 = pessoal, 2 = corporativo (conta do trabalho), 3 = feriados (pública) |
| Apelidos | `pessoal`, `corporativo`, `feriados` |
| Repositório | conta pessoal `dosxnjos`, **público** (regras em § 3.1) |
| Posição | fica onde está hoje (X=0, Y=197); o resto ele arruma depois |
| Forma | **pacote novo com vários widgets separados**, não um widget único |

**Em aberto:**
1. **Apelidos das contas Claude e dos drives G:/H:/I:.** Proposta até ele
   decidir: as contas Claude por apelido no `config.toml`, com padrão
   `conta <N do cswap>`. Os drives como `drive G`, `drive H`, `drive I`.
2. **Fase 5 / Calendar API:** só depois de 2 semanas com o pacote.
3. **Atalho por AutoHotkey,** só se o `.lnk` falhar na fase 3.

## Descartado e impraticável

| o quê | motivo | decisor |
| --- | --- | --- |
| Widget único com tudo (o "painel" da 1ª versão deste plano) | o Gabriel prefere vários widgets num pacote; separado também elimina o aperto de altura | gabriel, 02/10 |
| Polir o skin antigo na fase 0 (pt-BR, visual, limpeza) | vira trabalho jogado fora com o pacote novo; a fase 0 ficou só com rede, segredo e robustez mínima | fable, 02/10 |
| Parser ICS/RRULE escrito em Lua 5.1 | maior risco técnico; biblioteca pronta resolve | fable (evidência) |
| Tauri agora | toolchain pesado, Win+D sem prova | fable (evidência) |
| Zebar, YASB, Seelen, Lively, Widgets Board, WinUI 3, Electron | ver § 2 | fable (evidência) |
| Paleta do claude-usage-tray como identidade | regra da casa: design system não se compartilha entre produtos; herda-se só a semântica do Claude | regra C:\Dev |
| Animação contínua (dois-pontos piscando, respiração, glow da hora) | reprova no 100º dia e mantém o redraw ligado | juízes |
| Frase de "clima do PC" | metáfora a mais; a cor com histerese já comunica | juiz 1 |
| GET condicional no `.ics` | o Google responde `no-cache/no-store` | pesquisa |
| `eid` do Google no link | embutiria o ID da agenda (e-mail) no JSON | fable |
| Seguir o Foco/Não Perturbe do Windows | sem API pública estável → toggle próprio | pesquisa |
| Widget chamando cswap/API Anthropic | segunda engine; viola a invariante nº 1 do tray | contrato do tray |

## O que o pedido não dizia

- **Achados de saúde, não só de estética:** o 404 silencioso, as recorrências
  invisíveis, os 520 MB/dia e as URLs secretas em texto puro. Sem eles, um
  redesenho bonito continuaria mostrando a agenda errada.
- **Cotas do Google Drive** (G:/H:/I:) entraram como "contas cloud": a leitura
  literal do pedido, a custo zero.
- **Bateria, sono, proxy corporativo, fuso e DPI** entraram como requisito. Cada
  um sozinho faria o painel mentir em algum cenário real deste notebook.
- **Contratos JSON** para nada ser jogado fora se o Rainmeter virar teto.
- **Varredura do Rainmeter em si:** illustro morto, aceleração por hardware e
  layout salvo.
