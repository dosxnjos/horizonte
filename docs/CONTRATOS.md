# Contratos de dados

Os widgets nunca falam com a rede. Eles leem arquivos JSON que outro processo grava. Este
arquivo é o dono do formato de cada um.

| arquivo | quem grava | quem lê |
| --- | --- | --- |
| `%LOCALAPPDATA%\Horizonte\agenda.json` | `agenda_sync` ([uso](agenda_sync.md)) | `Relogio`, `Dia`, `Agenda` |
| `snapshot.json` do claude-usage-tray | o tray (projeto à parte) | `Claude` (fase 2; contrato v1 na fase 2b do roadmap); `Dia` lê só `accounts[Active].Bars[Label=5h].ResetsAt` (ISO 8601 com fuso, UTF-8 com BOM) para o ♻ da linha do dia |

## `agenda.json` (schemaVersion 1)

### Como é gravado

- **UTF-8 sem BOM**, uma chave por linha.
- **Escrita atômica:** grava `.agenda.json.<pid>.tmp` na mesma pasta e troca com `os.replace`.
  Se o Rainmeter estiver lendo o arquivo no instante da troca, o Windows nega; o helper tenta
  de novo até 10 vezes. O leitor nunca vê arquivo pela metade.
- **Só quando muda.** A comparação ignora os campos voláteis: `generatedAt` e, em cada fonte,
  `lastAttemptAt` e `lastOkAt`. Sem isso, cada execução (a cada 10 min) regravaria o arquivo e
  acordaria os widgets à toa. Consequência: **`generatedAt` é o instante da última mudança de
  conteúdo**, não da última execução. Frescor se lê pelo `status` de cada fonte.
- Depois de gravar, o helper manda `!CommandMeasure mLeitor "Recarregar()"` para
  `Horizonte\Dia`, `Horizonte\Agenda` e `Horizonte\Relogio` (lista em `widgets` no
  `config.toml`). Se o Rainmeter estiver fechado, não manda nada.

### Formato

```jsonc
{
  "schemaVersion": 1,
  "producer": "agenda_sync 0.1.0",
  "generatedAt": 1790960400,                 // epoch UTC (s) da última mudança de conteúdo
  "janela": {"de": "2026-10-01", "ate": "2026-10-17"},  // ontem até hoje+janelaDias, fuso local, inclusivo
  "ambiente": {"animacoes": true},           // "Efeitos de animação" do Windows (SPI_GETCLIENTAREAANIMATION)
  "proximoFeriado": {"data": "2026-10-12", "nome": "..."},  // fonte feriados, até 60 dias; senão null
  "sources": [
    {
      "id": "pessoal",                       // pessoal | corporativo | feriados
      "nome": "Pessoal",
      "cor": "#7AA2F7",
      "status": "ok",                        // ok | offline | formato | sem_credencial | http404 | http401 | httpNNN
      "httpStatus": 200,                     // null se não houve resposta HTTP (offline, sem_credencial)
      "lastOkAt": 1790960400,                // último download que baixou E expandiu; null se nunca
      "lastAttemptAt": 1790960400,           // última tentativa de download
      "erro": null                           // texto curto, acionável, pt-BR; null quando ok
    }
  ],
  "events": [
    {
      "id": "3f2a9c0d1e7b4a55",              // sha1(fonte|UID|início)[:16], estável entre execuções
      "source": "pessoal",
      "title": "...",
      "allDay": false,
      "start": 1791201600,                   // epoch UTC (s); o widget formata no fuso do Windows
      "end": 1791205200,
      "recurring": true,                     // a série tem RRULE/RDATE ou a ocorrência foi remarcada
      "location": "Sala 3",                  // sem e-mail nem URL; null se vazio
      "meetUrl": "https://meet.google.com/abc-defg-hij",  // Meet ou Teams; null se não houver
      "link": "https://calendar.google.com/calendar/u/0/r/week/2026/10/5"
    },
    {
      "id": "...", "source": "feriados", "title": "...",
      "allDay": true,
      "startDate": "2026-10-12",             // data local, nunca epoch
      "endDate": "2026-10-13",               // EXCLUSIVA (padrão iCal): evento de 1 dia tem endDate = startDate + 1
      "recurring": false, "location": null, "meetUrl": null, "link": "..."
    }
  ]
}
```

### Regras que o leitor pode assumir

- `events` vem **ordenado por início**. Evento de dia inteiro conta da meia-noite local do
  `startDate` e, no empate, vem antes do evento com hora.
- Evento com hora tem `start`/`end` e **não** tem `startDate`/`endDate`; dia inteiro é o
  contrário. `end >= start` sempre.
- Estão na lista os eventos que **tocam** a janela, medida no fuso local (um evento que começou
  anteontem e termina amanhã aparece; um evento às 22:30 do último dia aparece mesmo que no
  `.ics` ele esteja em UTC, no dia seguinte). Evento de duração zero entra se o instante cai na
  janela.
- Recorrência já vem expandida: cada ocorrência é um item. RRULE, RDATE, EXDATE e
  RECURRENCE-ID (ocorrência remarcada) já foram aplicados; `STATUS:CANCELLED` já saiu.
- `DTEND` ausente vira 1 h (evento com hora) ou 1 dia (dia inteiro). `DURATION` é respeitada.
- Evento "flutuante" (sem fuso no `.ics`) é tratado como hora local da máquina.
- Fonte com falha (`offline`, `httpNNN`, `formato`) **mantém os eventos do último download
  bom**, com o `status` e o `erro` dizendo que estão velhos. Fonte `sem_credencial` não tem
  eventos.

### O que nunca entra

- URL do feed (os endereços secretos ficam no Gerenciador de Credenciais).
- E-mail em qualquer campo: título e local passam por limpeza de e-mail e URL. Só sai o que
  tem forma de e-mail (`algo@dominio.tld`); um `@` solto num título ("Almoço @ 12h") fica.
- `DESCRIPTION` do evento (pode trazer pauta, telefone, e-mail de convidado). Dela só sai o
  `meetUrl`.
- Lista de convidados, organizador, `eid` do Google (embutiria o ID da agenda, que é o e-mail).

O teste `tests/test_sync.py::test_contrato_sem_url_de_feed_nem_email` varre o JSON por `@`
fora de `meetUrl`/`link` e por `calendar/ical`.

### Mudança de contrato

Campo novo opcional: mesmo `schemaVersion`, leitor ignora o que não conhece. Remover ou mudar o
sentido de um campo: `schemaVersion` + 1, e os widgets checam a versão antes de ler.
