[Variables]
; Tema Aurora (design/horizonte-v1-aurora.html): vidro escuro, luz como material, um único acento âmbar.
; Escolha: Tema=aurora. Mesmos nomes do Tokens-expressivo.inc; o que muda é o papel de cada um:
;   - superfícies em R,G,B,A (vidro translúcido). O Rainmeter não desfoca o que está atrás, então o
;     vidro é mais opaco que o do protótipo (alfa ~0,82 no lugar de 0,50 sobre blur de 30 px);
;   - o relógio não tem cartão: CorPri é quase transparente (alfa 1, para o arrasto continuar pegando)
;     e os dígitos flutuam sobre o papel de parede, como no protótipo;
;   - o cartão Dia não muda de forma (raio 14 em todos os papéis) e muda pouco de cor: o papel é
;     dito pelo texto e por um tom quente ou frio no vidro (variáveis Dia* abaixo, lidas pelo Dia.lua).
; Simplificações (o Rainmeter não faz): sem blur, sem grão, sem hairline de 1 px na borda.

; vidro: --glass rgba(21,20,18,.50) sobre blur; aqui 21,20,18 a ~0,82
CorS=21,20,18,210
CorSHi=26,25,23,214
; texto: --text #EDEBE8, --text-2 a 70 % sobre o vidro
CorOn=237,235,232
CorOnV=172,170,167
; relógio sem cartão: dígitos #F6F4F0 (.w-clock)
CorPri=0,0,0,1
CorOnPri=246,244,240
; único acento quente: --amber #FFC27A (pílula "agora" da Agenda), texto --lit-fg #161412
CorSol=255,194,122
CorOnSol=22,20,18
; urgente: vidro com um tom âmbar
CorSold=52,38,24,224
CorOnSold=255,222,190
; livre: vidro com um tom frio
CorCalm=22,30,28,214
CorOnCalm=214,232,224
; agendas: croma baixo, mesma luminosidade (--c-pess #A8C4A2, --c-corp #9DAECB, --c-fer #D6A59E)
CorAgPes=168,196,162
CorAgCor=157,174,203
CorAgFer=214,165,158
; controles
CorCtl=22,20,18
CorOnCtl=237,235,232

; Cartão Dia (Dia.lua): fundo, texto e raios (TL,TR,BR,BL) por papel. Vazio = o padrão do tema
; (CorSHi/CorSold/CorSol/CorCalm e os raios do Expressivo). Aqui o AGORA não vira um bloco laranja:
; fica no vidro, com o âmbar só no tom.
DiaFundoAgora=64,46,26,230
DiaTextoAgora=255,230,200
DiaRaiosProximo=14,14,14,14
DiaRaiosUrgente=14,14,14,14
DiaRaiosAgora=14,14,14,14
DiaRaiosLivre=14,14,14,14

; Chip do feriado: branco a 14 % sobre o papel de parede
AlfaChip=36
; Dois-pontos do relógio: opacidade 0,6
AlfaDoisPontos=153

; Raios: --r-w 14 (contêiner); chip mantém 10
RaioCartao=14
RaioChip=10
