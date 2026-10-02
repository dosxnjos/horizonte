# Estudo estético do Horizonte (02/10/2026)

O dono achou o primeiro mockup "muito anos 2010, defasado" e pediu "coisa moderna,
com motion". Este estudo foi feito em quatro etapas:
- pesquisa de tendências de 2024 a 2026: sistemas operacionais, produto e motion;
- crítica do mockup;
- quatro direções construídas como protótipos interativos;
- revisão de código, QA visual e três juízes.

**Para ver:** abra [`direcoes/index.html`](direcoes/index.html) no navegador.

## Por que o primeiro mockup parecia 2010

O degradê não morreu. O que envelheceu foi o **tipo** de degradê usado:

| traço | onde estava | o que se faz hoje |
| --- | --- | --- |
| faixa de brilho branco no topo de cada cartão | `.widget::before`, branco 9%→0 em 22 px | luz de 1 px na borda (hairline), não verniz |
| céu azul→roxo→vinho com estrelas | fundo da cena | papel de parede abstrato e calmo; degradê interpolado em OKLCH, sem meio "lamacento" |
| sombra grande e difusa | `0 20px 50px -20px rgba(0,0,0,.6)` | profundidade pela borda e pela superfície, sombra curta ou nenhuma |
| `text-shadow` em todo texto | todo o widget | superfície com contraste suficiente, texto limpo |
| cartão dentro de cartão, com faixa colorida de 3 px | cartão Dia | um nível só, com geometria concêntrica |
| neutros azulados frios | tokens base | neutro de baixa saturação, levemente quente (o caminho do Linear em 2026) |

O consenso das fontes é que **o degradê continua existindo como luz**: uma
hairline, a variação dentro de um anel ou o brilho atrás da superfície, com grão
fino. Nunca como tinta cobrindo o cartão.

## O que é motion moderno (e o que não é)

**É:**
- **mola** no lugar de duração fixa, com amortecimento crítico como padrão e
  quique só em forma, nunca em dado;
- **números que rolam** só no dígito que mudou, na direção certa;
- **anel que varre** quando o valor muda, com histerese para não tremer;
- **forma que se transforma** quando o estado muda (o cartão Dia indo de PRÓXIMO
  para AGORA), em vez de sumir e reaparecer;
- **entrada escalonada curta**, uma vez só;
- **resposta imediata** a hover e clique.

**Não é:** animação ambiente em loop, gradiente que respira, bounce em tudo, nem
um spotlight que segue o cursor num widget onde o mouse quase nunca passa.

Valores de referência:
- **Windows 11:** 167/250/333 ms com `cubic-bezier(0,0,0,1)`;
- **Material:** molas com amortecimento de 0,9 a 1;
- **Apple:** `numericText` para dígitos;
- **NumberFlow:** referência na web.

## As quatro direções

| direção | ideia | identidade | motion | viabilidade | soma |
| --- | --- | --- | --- | --- | --- |
| [Instrumento](direcoes/instrumento.html) | aparelho de medição: fosco sólido, números de mostrador, um acento | 7,5 | 7,0 | 8,0 | **22,5** |
| [Expressivo](direcoes/expressivo.html) | cor chapada forte; a forma conta o estado | 6,5 | 7,5 | 7,0 | **21,0** |
| [Vidro líquido](direcoes/vidro-liquido.html) | lente sobre o papel de parede, borda acesa pela hora | 6,0 | 8,0 | 4,0 | 18,0 |
| [Aurora](direcoes/aurora.html) | vidro escuro granulado, luz como material | 4,0 | 8,5 | 5,5 | 18,0 |

**Recomendação dos juízes:** híbrido com base no **Instrumento**, mais estes
enxertos:
1. relógio em dígitos cheios (a matriz de pontos só como acento, porque se lê
   devagar);
2. do Vidro, **a luz do sol na borda**: a hairline muda de cor e direção
   conforme a hora (fria de manhã, branca ao meio-dia, âmbar no fim da tarde). É
   o que dá sentido ao nome "Horizonte";
3. do Expressivo, o **cartão Dia que muda de forma e de cor por estado**;
4. números que rolam só no dígito que mudou;
5. a regra **"dado não quica, forma quica"**;
6. um único acendimento ao entrar em AGORA, no lugar do pulso 3×.

## Cabe no Rainmeter?

**Quase tudo cabe:**
- fundo sólido com hairline e grão em PNG;
- anéis segmentados com `StrokeDashes`;
- dígitos que rolam: dois String meters num Container que serve de máscara;
- molas por tabela pré-calculada em Lua tocada pelo ActionTimer;
- luz da borda recalculada uma vez por minuto.

**Não cabe:**
- desfoque durante as transições;
- mola interrompida que mantém a velocidade;
- reordenação fluida da lista;
- raio maior que 8 px com o desktop desfocado atrás.

**Custo de RAM:**

| caminho | RAM |
| --- | --- |
| Rainmeter puro | ~20 MB (medido) |
| plugin WebView2 | +80 a 170 MB (estimado) |
| app próprio | +40 a 130 MB (estimado) |

**Portão técnico (proposta):** um spike mede a CPU do Rainmeter animando um
widget de 400×300. Meta:
- 0% parado;
- pico de ~5% de um núcleo durante uma transição.

Se o pico passar disso, ou se o movimento sem blur parecer "morto" ao dono, a
rota é o plugin WebView2 dentro do Rainmeter.

## Decisão: Expressivo (Gabriel, 02/10)

> "gostei muito da aurora, mas pensando muito, quem ganhou meu coração foi a
> expressivo"

A escolha vai contra a recomendação dos juízes, que preferiam o Instrumento. Vale
o gosto do dono: o Expressivo ficou em 2º, com viabilidade 7 no Rainmeter. A base
de trabalho é [`horizonte-v1.html`](horizonte-v1.html), que parte do Expressivo
com o conteúdo já decidido:
- só o disco C:, com o rótulo "Windows";
- contas Claude chamadas `produto` e `dados`.

A [direção original](direcoes/expressivo.html) fica intacta como registro do
estudo.

**Pontos fracos do Expressivo apontados pelos juízes, a resolver na v1:**
- **Cara de Google:** é a assinatura do Material 3, e o nome "Horizonte" não
  significa nada visualmente. Candidato a resolver: a luz da hora do dia, que veio
  do Vidro e era o enxerto mais citado.
- **Contador antigo:** o número passava pelos 9 dígitos ao ir de 9 para 0. Ainda
  precisa conferir se a revisão corrigiu.

## Decisões em aberto (dono: Gabriel)

1. ~~Direção~~: Expressivo. Em aberto: o que da Aurora entra nele.
2. **Cor do AGORA:** o âmbar colide com o anel do Claude em âmbar. Os juízes
   recomendam azul-aço para o AGORA, deixando âmbar e vermelho só para alerta.
3. **Relógio:** dígitos cheios (leitura imediata) ou matriz de pontos (assinatura
   mais forte).
