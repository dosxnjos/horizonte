[Variables]
; Tema Expressivo, esquema claro "Pistache" (design/horizonte-v1-expressivo.html, body[data-wall="pistache"]).
; Mesmos nomes e mesma geometria do Tokens-expressivo.inc; só as cores mudam. Escolha: Tema=pistache.
; Cores em R,G,B (alfa se acrescenta no uso). Hex do protótipo ao lado do nome.

; superfícies: --s #F6FAEA, --s-hi #E9F0D6
CorS=246,250,234
CorSHi=233,240,214
; texto sobre superfície: --on #1A1F12, --on-v #4B523F
CorOn=26,31,18
CorOnV=75,82,63
; primária (relógio): --pri #2D5A12, --on-pri #E4FFCB
CorPri=45,90,18
CorOnPri=228,255,203
; sol (AGORA): --sol #FF8640, --on-sol #2B0F00
CorSol=255,134,64
CorOnSol=43,15,0
; sol escuro (urgente): --sold #FFDCC8, --on-sold #5A2400
CorSold=255,220,200
CorOnSold=90,36,0
; calma (livre): --calm #C5EE95, --on-calm #142300
CorCalm=197,238,149
CorOnCalm=20,35,0
; agendas: --ag-pes #B3155A, --ag-cor #155FA0, --ag-fer #8A6200
CorAgPes=179,21,90
CorAgCor=21,95,160
CorAgFer=138,98,0
; controles: --ctl #1D2513, --on-ctl #EEF5E2
CorCtl=29,37,19
CorOnCtl=238,245,226

; Chip sobre a primária: on-pri a 14 %, em alfa 0..255
AlfaChip=36
; Dois-pontos do relógio: opacidade 0,6
AlfaDoisPontos=153

; Raios (px lógicos, multiplicar por #Scale#)
RaioCartao=32
RaioChip=10
