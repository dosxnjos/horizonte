# Horizonte

Um pacote de widgets para o desktop do Windows, feito em
[Rainmeter](https://www.rainmeter.net/). Ele responde três perguntas sem você
abrir nada:
- o que vem agora na sua agenda;
- se o PC está engasgando;
- quanto sobra das suas contas Claude.

> **Status: em desenho.** Ainda não há widget para instalar. A visão, a
> arquitetura e as fases estão no
> [roadmap](roadmap/2026-10-02-horizonte-visao-e-plano.md). O mockup interativo
> está em [`horizonte-visao-2026-10-02.html`](horizonte-visao-2026-10-02.html):
> baixe e abra no navegador.

## Os widgets

| widget | mostra |
| --- | --- |
| Relógio | hora, data e o próximo feriado |
| Dia | o que está acontecendo agora, o próximo compromisso ou quanto tempo você tem livre, e a linha do dia |
| Agenda | os próximos 14 dias de várias agendas Google, com eventos recorrentes e os horários livres |
| Máquina | CPU, RAM, GPU, espaço livre do SSD e cotas do Google Drive para desktop |
| Claude | uso da janela de 5h da conta ativa e das outras contas, lido do claude-usage-tray (app de bandeja, projeto à parte) |
| Aviso | um cartão com o botão Entrar, 5 min antes da reunião |

Cada widget liga, desliga e muda de lugar sozinho. Todos dividem o mesmo tema.

## Como os dados chegam

- **Agenda:** um helper em Python (`agenda_sync`) baixa os endereços iCal das
  suas agendas, expande os eventos recorrentes e grava um `agenda.json` local.
  Os endereços secretos ficam no Gerenciador de Credenciais do Windows, nunca em
  arquivo. Uso: [docs/agenda_sync.md](docs/agenda_sync.md); formato do arquivo:
  [docs/CONTRATOS.md](docs/CONTRATOS.md).
- **Máquina:** medidas nativas do Rainmeter.
- **Claude:** leitura do `snapshot.json` que o claude-usage-tray grava. O widget
  nunca chama a API da Anthropic.

## Privacidade

Este repositório é público. Nele nunca entra:
- endereço de agenda;
- e-mail;
- título real de compromisso;
- arquivo de dados local.

`tools/varrer-segredos.sh` confere isso antes de cada commit.

## Créditos

A primeira versão deste widget era uma modificação do Enigma GCal (Kaelri) /
eclectic-tech (CC BY-NC-SA 3.0). O Horizonte é reescrito do zero e não
reaproveita código dele, mas a ideia de juntar várias agendas numa lista vem de
lá.

## Licença

[MIT](LICENSE)
