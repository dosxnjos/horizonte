[Variables]
; Horizonte: variáveis comuns a todos os widgets. Cada .ini inclui este arquivo primeiro.
; Arquivo em UTF-16 LE com BOM. Comentário só em linha própria: ";" no meio do valor é dado.

; Escala de geometria e fonte. 1 enquanto o Rainmeter roda DPI-unaware (o Windows estica x1,25).
; Com o shim HighDpiAware (depois que o skin antigo sair): AppliedDPI/96, ex.: 1.25.
; Toda medida dos widgets é multiplicada por #Scale#; fonte = px * 0.75 * #Scale#.
Scale=1

; Tema visual: escolhe o arquivo Tokens-#Tema#.inc
Tema=expressivo

; Animação: 1 = transições curtas ligadas; 0 = tudo muda seco.
; Também desliga sozinho quando o agenda.json diz ambiente.animacoes=false (efeitos do Windows).
Animacoes=1

; Releitura de reserva do agenda.json, em segundos (só redesenha se o conteúdo mudou)
ReleituraS=60

; Depuração. DebugHora=HH:MM congela o relógio nessa hora (vazio = hora real).
; DebugLog=1 grava eventos de rotina em %LOCALAPPDATA%\Horizonte\widget.log (erros sempre vão).
; DebugAgenda=<caminho> lê outro agenda.json (teste de estados); vazio = %LOCALAPPDATA%\Horizonte\agenda.json.
DebugHora=
DebugLog=0
DebugAgenda=
; DebugSnapshot=<caminho> lê outro snapshot.json do claude-usage-tray; vazio = %LOCALAPPDATA%\claude-usage-tray\snapshot.json.
; No Dia, DebugHora=HH:MM vale como "hoje, a essa hora" (cartão, agulha e linha do dia).
DebugSnapshot=

; Modo privado (cadeado da Agenda): 1 = títulos viram "Compromisso". O clique no cadeado grava
; Privado=0/1 no Local.inc (!WriteKeyValue), então o estado sobrevive a refresh e reinício.
Privado=0

; Apelidos das contas Claude. Padrão "conta N"; o apelido real fica no Local.inc (não versionado).
ApelidoConta1=conta 1
ApelidoConta2=conta 2
ApelidoConta3=conta 3
ApelidoConta4=conta 4
ApelidoConta5=conta 5
ApelidoConta6=conta 6
ApelidoConta7=conta 7
ApelidoConta8=conta 8

; Máquina: discos com anel próprio, separados por vírgula (máximo 3). Unidade fora da lista não é
; medida. Padrão: só o C:. Exemplo no Local.inc: Discos=C:,G:
Discos=C:
; Rótulo fixo por unidade: RotuloDisco<letra>. Sem rótulo, aparece a própria letra ("D:").
; O rótulo do volume nunca é lido (o do Google Drive contém o e-mail).
RotuloDiscoC=SSD
RotuloDiscoG=Drive
; Máquina na bateria: leitura de CPU/RAM/GPU a cada N segundos e sem animação.
; DebugBateria=1 simula a bateria (0 simula a tomada; vazio = estado real do PowerPlugin).
BateriaCadenciaS=5
DebugBateria=

; Claude: o snapshot.json do claude-usage-tray é relido a cada ReleituraClaudeS segundos (só leitura).
; "Bandeja parada" = savedAt com mais de TrayParadoS segundos E o processo da bandeja ausente.
ReleituraClaudeS=20
TrayParadoS=150
; Executável da bandeja (clique no bloco "bandeja parada"). Sempre com variável de ambiente
; (%USERPROFILE%, %LOCALAPPDATA%), nunca com o nome de usuário escrito; o caminho real vai no Local.inc.
TrayExe=%USERPROFILE%\claude-usage-tray\Claude Usage Tray.exe
; DebugTray=0 finge o processo da bandeja ausente (1 = presente; vazio = o real).
DebugTray=

; Sobrescritas desta máquina (fora do repo). Modelo: Local.example.inc
@IncludeLocal=#@#Local.inc
