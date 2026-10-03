[Variables]
; Tema Expressivo, esquema escuro "Ardósia" (design/horizonte-v1-expressivo.html, body[data-wall="ardosia"]).
; Cores em R,G,B (alfa se acrescenta no uso: #CorOnPri#,153). Hex do protótipo ao lado do nome.

; superfícies: --s #15302D, --s-hi #1F3D39
CorS=21,48,45
CorSHi=31,61,57
; texto sobre superfície: --on #E2F1EC, --on-v #A6BFB9
CorOn=226,241,236
CorOnV=166,191,185
; primária (relógio): --pri #86E0C8, --on-pri #00211B
CorPri=134,224,200
CorOnPri=0,33,27
; sol (AGORA): --sol #FFB27A, --on-sol #2F1300
CorSol=255,178,122
CorOnSol=47,19,0
; sol escuro (urgente): --sold #4A2E1C, --on-sold #FFDCC6
CorSold=74,46,28
CorOnSold=255,220,198
; calma (livre): --calm #0F4A40, --on-calm #B4F3E2
CorCalm=15,74,64
CorOnCalm=180,243,226
; agendas: --ag-pes #FFA9C5, --ag-cor #8ED0FF, --ag-fer #EBCB6A
CorAgPes=255,169,197
CorAgCor=142,208,255
CorAgFer=235,203,106
; controles: --ctl #0A1E1C, --on-ctl #E3F0EB
CorCtl=10,30,28
CorOnCtl=227,240,235

; Chip sobre a primária: on-pri a 14% (o color-mix do protótipo), em alfa 0..255
AlfaChip=36
; Dois-pontos do relógio: opacidade 0,6
AlfaDoisPontos=153

; Raios (px lógicos, multiplicar por #Scale#)
RaioCartao=32
RaioChip=10
