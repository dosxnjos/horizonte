# Widget da central: ideias e recomendação (02/10/2026)

O dono pediu "um widget de integração com a central": quantos cards estão
executando agora, quantos estão em próximo, um pouco do painel de entregas, "como
está o status geral das coisas". Este documento junta três propostas, a crítica
delas e a recomendação. Nada foi construído ainda.

**Regra deste arquivo (repo público):** só contagens genéricas de exemplo. Nenhum
título de card, nome de pedido, e-mail, conta ou dado de negócio. "Você" é o dono
do desktop; "outra pessoa" é quem decide negócio.

## 1. O que a central já oferece de dado útil

Tudo por rota GET em `127.0.0.1:8137`, sem precisar mudar nada nela:

| dado | rota | custo medido |
| --- | --- | --- |
| servidor de pé | `/api/health` | ~0,05 s |
| esteira ligada, pausada, rodando o quê (papel, desde) | `/api/maestro/janela` | ~2,7 s |
| próximos da fila, quantos podem rodar já (`elegivel`), slots | `/api/maestro/fila?n=5` | ~2,9 s |
| pulso do maestro, saúde das sessões, escada de modelos | `/api/vigia` | ~0,4 s |
| ritmo do dia (rodadas fechadas por resultado) | `/api/diario?mes=AAAA-MM` | ~0,02 s |
| decisões abertas por dono, números do dia | `/api/apresentacao?dias=1` | ~2,5 s, ~140 KB |
| hora da próxima rodada, pausa e motivo | `/api/maestro/estado` | 0,2 s hoje, já passou de 4 min |

O que **não** existe numa rota leve: sessões pedindo você, idade exata da decisão
mais antiga, "pista fechada pela RAM" de forma estável, e o painel de entregas por
pedido (a rota `/api/entregas` está planejada, não feita).

Armadilhas de leitura: a coluna "próximo" do board não é o que roda já (a maior
parte espera outro card, agenda ou pasta livre); "agora" no board inclui card
humano, que não ocupa slot; fusos misturados (hora local sem fuso × UTC com `Z`).
O widget mostra o número que o backend já decidiu, nunca recalcula.

## 2. As três propostas

| proposta | em uma frase | nota do crítico |
| --- | --- | --- |
| **Pistas** | cartão de 430 px com uma pista por slot (papel, há quanto tempo), os próximos em chips, o ritmo do dia e uma faixa âmbar do que espera você | 6,5/10: responde melhor "está andando?", mas é denso demais para um relance, mostra título por padrão e o bloco "pista fechada" não se sustenta com as rotas de hoje |
| **Entregas** | o pedido no lugar do card: "N coisas travadas por sua causa", até 3 pedidos em voo com etapas e previsão em palavras, e o que ficou pronto hoje | 5/10 hoje, 8/10 depois: o herói "travam algo seu" é o número mais acionável de todos, mas pedidos ainda é unidade vazia (a rota e o registro de pedidos não existem) |
| **Maré** | um disco de 80 px cuja forma e cor dizem de quem é a vez: calmo (IA andando), âmbar com número (chegou coisa sua), vermelho (travou), cinza (leitura velha); detalhe só no hover | 8/10: relance com o menor custo de atenção, zero título, funciona com as rotas de hoje; o contra é que a classificação mora no helper, provisoriamente |

## 3. Recomendação: a Maré, com o detalhe das Pistas no hover

Um widget só, `Horizonte\Central`. Parado, é um seixo. Sob o mouse, abre um
cartão com a esteira e os números. O herói "travam algo seu" das Entregas entra
depois, como evolução do estado âmbar, quando a rota de entregas existir.

### Layout

```
RELANCE (96 x 96, disco de 80 px, fundo transparente)

  ANDANDO            TE ESPERA          TRAVADO            VELHO
   .------.           _.-^^-._          \  |  /           .  -  -  .
  /        \        .´        `.      - .----. -        '            '
 |~~~~~~~~~~|      (     3      )     - | !  | -        :     ··     :
 |≈≈≈≈≈≈≈≈≈≈|       `.  novas .´      - '----' -        .            .
  \≈≈≈≈≈≈≈≈/          `-.__.-´          /  |  \           '  -  -  '
   '------'        cookie âmbar        sol vermelho      tracejado cinza
 água = 2 de 3     número = novidades  glifo "!"         sem número
 slots ocupados    suas desde o clique

 QUIETO: disco liso, sem água (pausa sua, limite de conta, nada pronto, manutenção)
 MARÉ BAIXA (21 h–7 h, só andando/quieto): disco de 40 px a 60%

HOVER (cartão abre à direita do disco, 360 x 200, raio 32)
 .----------------------------------------------------------------.
 | ( andando sozinha )                 próxima 20:53 · em 4 min    |  pílula
 |                                                                |
 | 1  [ARQ]  projeto-a                                    31 min  |  pistas, discreto:
 |    ================-----------------------------               |  papel · projeto ·
 | 2  [EXE]  projeto-b                                    12 min  |  há quanto tempo,
 |    ======----------------------------------------              |  sem título
 |                                                                |
 |   2          N           N · N          N                       |
 |  agora    prontos     decisões        feitas hoje               |
 |                       você · outra                              |
 |  ------------------------------------------------------------  |
 |  2 novas decisões suas desde 14:10 · clique abre a mesa         |
 |  leitura há 1 min                                               |
 '----------------------------------------------------------------'

LINHA DO DIA (widget Dia, já existe): um traço por faixa de 15 min com etapa fechada
  07        09          12            15     ▌agora       18           21
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     ╷ ╷╷  ╷   ╷╷╷ ╷         ╷╷ ╷╷╷╷ ╷  ╷
```

### Blocos

1. **Disco (relance).** Estados por precedência: travado > te espera > andando >
   quieto; velho quando a leitura passou do prazo. A água no andando é
   `rodando / slots`. O âmbar acende só pelo que **mudou** desde o último clique
   (base = menor contagem vista; responder decisões nunca acende o âmbar). O
   estoque de decisões e urgentes nunca vira cor: só número no hover.
2. **Pílula da esteira (hover).** Uma frase: "andando sozinha", "terminando a
   rodada", "pausada até 21:30", "pausada: manutenção", "pausada: limite da conta ·
   volta 01:40", "desligada", "parada com fila", "maestro sem sinal há N min",
   "central fora do ar". Pausa por limite é calma, nunca vermelha: o anel de uso
   fica no widget Claude, que já existe.
3. **Pistas (hover).** Uma linha por slot ocupado: papel (ARQ/EXE/REV), projeto,
   há quanto tempo, trilho de 4 px numa escala de 60 min. **Discreto por padrão:**
   sem título. Pista "quieta" (sessão sem sinal acima do limiar que a central
   informa) ganha cor de atenção, não âmbar.
4. **Quatro números (hover).** agora · prontos (podem rodar já) · decisões (você ·
   outra pessoa) · feitas hoje. Antes das 10 h, "feitas" vira "desde ontem 18 h",
   porque a esteira trabalha de noite.
5. **Traços na linha do Dia.** Altura 2 a 8 px pela contagem da faixa de 15 min,
   35% de alfa, herdando a cor do papel do Dia. Sem clique, sem alarme.

### De onde vem cada número

| número | rota → campo | cadência | fase |
| --- | --- | --- | --- |
| servidor de pé | `/api/health` | 60 s | 1 |
| pulso do maestro | `/api/vigia` → `ultima_rodada.watchdog_maestro.heartbeat_idade_min` **somado** à idade de `ultima_rodada.quando` (o vigia roda a cada 5 min) | 60 s | 1 |
| limiar de silêncio | `/api/vigia` (lido, nunca fixo no widget) | 60 s | 1 |
| ligada, pausando, em curso (papel, desde) | `/api/maestro/janela` → `ativo`, `pausando`, `em_curso{papel, desde}`, `janela` | 120 s | 1 |
| slots e rodando (água) | `/api/maestro/fila?n=5` → `previsao_wip{slots, rodando}` | 120 s | 1 |
| prontos | `/api/maestro/fila` → contagem de `elegivel=true` | 120 s (`n=5`), total exato só na Fase 2 | 1/2 |
| decisões por dono, agora, feitas hoje | `/api/apresentacao?dias=1` → `decisoes.por_dono`, `numeros.em_agora`, `numeros.rodadas_feito` | 5 min | 1 |
| idade da decisão mais antiga | `/api/apresentacao` → `decisoes.mais_antigas` (top 5; falha se a sua mais antiga ficar fora) | 5 min | 1, exata na 2 |
| próxima rodada, pausa e motivo | `/api/maestro/estado` → `proxima_rodada_em`, `pausado_ate`, `conta_ativa.bloqueio` | 5 min, timeout 10 s | 1 |
| projeto da pista | `/api/maestro/estado` → `em_curso.cwd` reduzido ao nome da pasta | 5 min | 1 |
| traços do Dia | `/api/diario?mes=AAAA-MM` → `tipo=rodada`, `resultado=feito`, por 15 min | 5 min | 1 |
| sessões pedindo você | não existe sem rota nova | — | 2 |
| pista fechada pela RAM | `slots_auto` só reporta na passada em que muda; até a Fase 2, desenhar `slots_config` e mostrar a RAM como nota no hover | — | 2 |

**Nunca ler:** `/api/state` (vários MB), `/api/sessoes` (o GET pode gravar no
estado), `/api/ciclos` (~30 s a frio), nenhum arquivo em `dados/` da central nem o
registro de sessões em disco (`open()` cru de outro processo trava a escrita no
Windows).

### Estados de borda

- Central relançando (acontece a cada commit, dezenas de vezes por dia): até
  10 min de conexão recusada mantém o último estado, rodapé "central reiniciando".
  Só depois disso: "central fora do ar há N min".
- Central desligada de propósito: quieto e cinza, "central desligada". Nunca
  vermelho.
- Helper parado: o `central.json` só muda quando o conteúdo muda, então ele leva
  `vivo_bloco` (epoch arredondado a 10 min, regravado pelo menos a cada 10 min).
  Mais de 20 min sem renovar → velho, "última leitura 20:41".
- JSON ausente, pela metade ou `schemaVersion` diferente: `comum.leitor` mantém o
  último estado bom e loga em `widget.log`. Sem estado bom: velho, "aguardando a
  central".
- `/api/maestro/estado` lenta: some só a hora da próxima rodada; o pulso não
  depende dela.
- Pausa por limite: quieto, "volta HH:MM".
- Fila sem nada pronto: quieto, "nada pronto para rodar", texto neutro.
- Número acima de 99: "99+", total no tooltip.
- Fusos: o helper converte tudo para epoch UTC; o Lua só formata no fuso do
  Windows.
- Animações desligadas (`Animacoes=0` ou `ambiente.animacoes=false`): troca seca.

### Motion

Nada em laço. Parado = zero redesenho (`DefaultUpdateDivider=-1`). Padrão
`ActionTimer` + `os.clock()` com as molas do `anim.lua`, sempre até ~500 ms.

- Troca de estado do disco: a forma muda (círculo → cookie → sol) com mola
  `boing`, a cor cruza em 450 ms.
- Entrada em "te espera": um anel de 2 px expande de 80 para 112 px e some em
  600 ms, uma vez. Travado: dois anéis. Durante reunião no Dia, o âmbar não pulsa;
  o vermelho sim.
- Água: o nível muda por mola quando o número de rodadas muda; a superfície é
  estática, não ondula sozinha.
- Número: rolagem de dígito herdada do Relógio.
- Hover: o cartão revela a largura de 96 para 360 px (~400 ms) e fecha em 170 ms,
  250 ms depois de o mouse sair.
- Maré baixa: 80 → 40 px e opacidade 1 → 0,6 em 700 ms, uma vez, às 21 h.
- O minuto que passa (31 → 32 min) é redesenho seco: o widget calcula o tempo a
  partir de `desde` contra `os.time()`, sem o helper regravar o arquivo.

## 4. Como o dado chega

| caminho | a favor | contra | veredito |
| --- | --- | --- | --- |
| widget lê arquivo da central direto (`dados/*.json`) | zero processo novo | viola a regra da central de ler só pela porta própria; `open()` cru trava a escrita dela no Windows; o formato desses arquivos muda na modularização em curso | descartado |
| central exporta um snapshot para o Horizonte | um escritor só, régua no backend | a central vira escritora de uma pasta de outro projeto; depende de fase que ainda não existe; desligar exige mexer na central | descartado agora |
| **helper no Horizonte lê rotas GET e grava JSON local** | zero mudança na central; a rota HTTP é a borda que a modularização preserva (o despacho continua no `server.py`, quem muda é o arquivo interno); aguenta os relançamentos guardando o último retrato bom; respeita o contrato do Horizonte ("os widgets nunca falam com a rede") | a classificação do estado mora no helper até existir a rota de resumo | **recomendado** |

**Como fica:** `central_sync`, no repo do Horizonte, no molde do `agenda_sync`.

- Lê só GET em `127.0.0.1:8137`, nas cadências da tabela acima (cerca de 3 a 4
  GETs por minuto).
- Grava `%LOCALAPPDATA%\Horizonte\central.json`: UTF-8 sem BOM, `tmp` +
  `os.replace` com retentativa, só quando o conteúdo muda (ignorando campos
  voláteis), mais o `vivo_bloco`.
- Depois de gravar: `!CommandMeasure mLeitor "Recarregar()" Horizonte\Central` (e
  `Horizonte\Dia`, para os traços).
- **Higiene antes de gravar:** descarta `titulo`, `resumo`, `arquivos`, `cwd`
  (fica só o nome da pasta), `email`, `conta_email`, ids de card e de sessão.
  Teste pytest varre o JSON atrás de `@`, `c[0-9a-f]{12}` e `R$`.
- Contrato novo em [`docs/CONTRATOS.md`](../docs/CONTRATOS.md): `central.json`,
  `schemaVersion 1`. Fixtures do repo com nomes genéricos (`projeto-a`).
- **Reversão:** desativar a config `Horizonte\Central` e parar a tarefa do helper.
  Nenhum resíduo na central.

**O que precisaria ser feito na central** (vira card para a sessão dona dela; não
se faz daqui):

- `GET /api/resumo`, só leitura, com ETag e cache de 30 a 60 s, contrato
  declarado em `docs/ESTADO.md` para consumidor externo (widget, celular, aviso no
  chat) e teste próprio. Campos:
  - `pulso{estado, motivo, desde}` já classificado no backend (tira a régua do
    helper);
  - `maestro{ativo, pausando, pausado_ate, motivo_pausa, heartbeat_idade_min`
    corrigido`, limiar_silencio_min, proxima_rodada_em}`;
  - `slots{config, max_auto, ram_pct}` (resolve a "pista fechada");
  - `pistas[]{papel, projeto, desde_epoch, silencio_min}` sem título;
  - `fila{prontos, depende, agendado, pasta_ocupada, pausa}`;
  - `espera_voce{decisoes, travam, mais_antiga_dias, sessoes_pedindo}` (sessões
    contadas sem efeito colateral de escrita);
  - `hoje{rodadas, feito, voltou, esperando, sem_resultado}`.
- Entra depois das fases iniciais da modularização da central (o despacho de rotas
  fica no `server.py`). A decisão é técnica.
- Opcional: uma âncora `#card=<id>` no board, para o clique abrir o card certo.
  Hoje todo clique cai na raiz.

Com a rota, o helper vira repasse: uma chamada a cada 30 a 60 s no lugar de três
leituras do estado inteiro por minuto.

## 5. Banco de ideias para depois

- **Herói das entregas** no estado âmbar: "N travam algo seu · a mais antiga há
  N d", quando a rota de entregas existir.
- **Pedidos em voo** (até 3, etapas feitas/total, previsão em palavras como "nos
  próximos dias"), quando os pedidos estiverem registrados.
- **Mini-série de 7 dias** de etapas fechadas contra a mediana, sem cor de festa.
- **Ponto de pedido entregue** na linha do Dia, além dos traços de etapa.
- **Chip "outra pessoa trava N"**, para cobrar com número.
- **Composição da fila** numa barra de 6 px (prontos, esperando outro card,
  agendados, pasta ocupada), sem cor de urgência.
- **Medidor de folga da máquina** (RAM/CPU), explicando por que a esteira segurou
  um slot.
- **Notificação de evento** (rodada caiu, servidor fora) a partir do resumo, quando
  houver contrato.

## 6. O que precisa da decisão do dono

1. **Título de card no hover:** nunca, ou liga por chave no `Local.inc`?
   Recomendo nunca: o widget fica bom só com papel, projeto e tempo, e o risco de
   compartilhar a tela some.
2. **Aviso durante reunião:** silenciar o pulso âmbar quando o Dia está em
   reunião? Recomendo silenciar o âmbar e manter o vermelho.
3. **Maré baixa à noite:** encolher o disco fora do expediente? Recomendo sim, das
   21 h às 7 h, e só quando está calmo ou quieto.

O resto (caminho do dado, cadências, cores, motion) é decisão técnica, já tomada
pela opção mais reversível: desligar o widget e parar o helper desfaz tudo.

## O que o pedido não dizia

- **Privacidade por padrão:** repo público e tela compartilhável; o helper limpa
  antes de gravar e o teste cobra.
- **Aguentar os relançamentos:** a central relança a cada commit; sem o último
  retrato bom, o widget piscaria o dia todo.
- **Não duplicar o widget Claude:** uso das contas fica lá; aqui, só "volta HH:MM".
- **Helper morto ≠ central quieta:** o `vivo_bloco` separa os dois.
- **Carga no servidor:** cadências escolhidas para não pesar numa máquina que já
  roda com a RAM alta.
